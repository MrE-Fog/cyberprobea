
#ifndef CYBERPROBE_EVENT_EVENT_H
#define CYBERPROBE_EVENT_EVENT_H

#ifdef HAVE_CONFIG_H
#include <config.h>
#endif

#include <vector>
#include <string>
#include <list>
#include <map>

#include <cyberprobe/protocol/base_context.h>
#include <cyberprobe/protocol/dns_protocol.h>
#include <cyberprobe/protocol/tls_handshake_protocol.h>
#include <cyberprobe/protocol/ntp_protocol.h>
#include <cyberprobe/util/uuid.h>

// Lua
extern "C" {
#include <lua.h>
#include <lualib.h>
#include <lauxlib.h>
}

namespace cyberprobe {

    class Event;

    // FIXME: Decouple this?  Interface?
    namespace analyser {
        class lua;
    }

    namespace event {    

	typedef std::map<std::string, std::pair<std::string,std::string> > 
	http_hdr_t;
    
	enum action_type {
	    CONNECTION_UP,
	    CONNECTION_DOWN,
	    TRIGGER_UP,
	    TRIGGER_DOWN,
	    UNRECOGNISED_STREAM,
	    UNRECOGNISED_DATAGRAM,
	    ICMP,
	    IMAP,
	    IMAP_SSL,
	    POP3,
	    POP3_SSL,
	    RTP,
	    RTP_SSL,
	    SIP_REQUEST,
	    SIP_RESPONSE,
	    SIP_SSL,
	    SMTP_AUTH,
	    SMTP_COMMAND,
	    SMTP_RESPONSE,
	    SMTP_DATA,
	    HTTP_REQUEST,
	    HTTP_RESPONSE,
	    FTP_COMMAND,
	    FTP_RESPONSE,
	    DNS_MESSAGE,
	    NTP_TIMESTAMP_MESSAGE,
	    NTP_CONTROL_MESSAGE,
	    NTP_PRIVATE_MESSAGE,
	    GRE_MESSAGE,
	    GRE_PPTP_MESSAGE,
	    ESP,
	    UNRECOGNISED_IP_PROTOCOL,
	    WLAN,
	    TLS_UNKNOWN,
	    TLS_CLIENT_HELLO,
	    TLS_SERVER_HELLO,
	    TLS_CERTIFICATES,
	    TLS_SERVER_KEY_EXCHANGE,
	    TLS_SERVER_HELLO_DONE,
	    TLS_HANDSHAKE_GENERIC,
	    TLS_CERTIFICATE_REQUEST,
	    TLS_CLIENT_KEY_EXCHANGE,
	    TLS_CERTIFICATE_VERIFY,
	    TLS_CHANGE_CIPHER_SPEC,
	    TLS_HANDSHAKE_FINISHED,
	    TLS_HANDSHAKE_COMPLETE,
	    TLS_APPLICATION_DATA
	};

	std::string& action2string(action_type a);
        
	class event {
	    static uuid_generator gen;
	public:
	    std::string id;
	    action_type action;
	    timeval time;
	    event() { id = gen.generate().to_string(); }
	    event(const action_type action,
		  const timeval& time) :
		action(action), time(time)
		{
		    id = gen.generate().to_string();
		}
	    virtual ~event() {}
	    virtual std::string get_device() const = 0;
	    virtual std::string& get_action() const {
		return action2string(action);
	    }
	    virtual int get_lua_value(analyser::lua&,
				      const std::string& name);
	    virtual void to_json(std::string& doc) {
                throw std::runtime_error("JSON not implemented.");
	    }
#ifdef WITH_PROTOBUF
            void to_protobuf(std::string& buf);
            virtual void to_protobuf(cyberprobe::Event& ev) {
                throw std::runtime_error("Protobuf not implemented.");
            }
#endif
        private:
            static int lua_json(lua_State* lua);
#ifdef WITH_PROTOBUF
            static int lua_protobuf(lua_State* lua);
#endif
        };

	class protocol_event : public event {
	public:
	    protocol_event(const action_type action,
			   const timeval& time,
			   cyberprobe::protocol::context_ptr cp);
	    virtual ~protocol_event() {}
	    cyberprobe::protocol::context_ptr context;
	    virtual std::string get_device() const;
            std::string device;
            std::string network;
            protocol::direction direc;
	};

    }

}

#endif

