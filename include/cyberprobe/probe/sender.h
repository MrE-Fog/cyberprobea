
#ifndef SENDER_H
#define SENDER_H

#include <queue>
#include <memory>
#include <sys/time.h>

#include <cyberprobe/protocol/pdu.h>
#include <cyberprobe/stream/nhis11.h>
#include <cyberprobe/stream/etsi_li.h>
#include <cyberprobe/probe/management.h>
#include <cyberprobe/probe/parameterised.h>

#include <mutex>
#include <condition_variable>
#include <thread>

namespace cyberprobe {

using direction = cyberprobe::protocol::direction;

// Shared pointers to TCP/IP address.
typedef std::shared_ptr<tcpip::address> address_ptr;

// A packet on the packet queue: Device plus PDU.
class qpdu {
public:
    enum { PDU, TARGET_UP, TARGET_DOWN } msg_type;
    timeval tv;                             // Valid for: PDU
    std::shared_ptr<std::string> device;    // Valid for: PDU, TARGET_UP/DOWN
    std::shared_ptr<std::string> network; // Valid for: PDU, TARGET_UP/DOWN
    std::vector<unsigned char> pdu;         // Valid for: PDU
    address_ptr addr;                       // Valid for: TARGET_UP
    direction dir;                // Valid for: PDU, from/to target.
};

// Queue PDU pointer
typedef std::shared_ptr<qpdu> qpdu_ptr;

// Sender base class.  Provides a queue input into a thread.
class sender {
protected:

    // Input queue: Lock, condition variable, max size and the actual
    // queue.
    std::mutex mutex;
    std::condition_variable cond;
    static const unsigned int max_packets = 1024;
    std::queue<qpdu_ptr> packets;

    // State: true if we're running, false if we've been asked to stop.
    bool running;

    parameterised& global_pars;

    std::thread* thr;

public:

    // Constructor.
    sender(parameterised& p) : global_pars(p) {
	running = true;
	thr = 0;
    }

    virtual void start() {
	thr = new std::thread(&sender::run, this);
    }

    // Thread body.
    virtual void run();

    // Handler - called to handle the next PDU on the queue.
    virtual void handle(qpdu_ptr) = 0;

    // Destructor.
    virtual ~sender() { delete thr; }

    // Short-hand
    typedef std::vector<unsigned char>::const_iterator const_iterator;

    // Hints about targets coming on/off-stream
    virtual void target_up(std::shared_ptr<std::string> l,
			   std::shared_ptr<std::string> n,
			   const tcpip::address& a);
    virtual void target_down(std::shared_ptr<std::string> device,
			     std::shared_ptr<std::string> n);

    // Called to push a packet down the sender transport.
    void deliver(timeval tv,
                 std::shared_ptr<std::string> device,
		 std::shared_ptr<std::string> n,
                 direction dir,
		 const_iterator& start,
		 const_iterator& end);

    // Called to stop the thread.
    virtual void stop() {
	running = false;

	std::unique_lock<std::mutex> lk(mutex);
	cond.notify_all();
    }

    virtual void join() {
	if (thr)
	    thr->join();
    }

};

// Implements an NHIS 1.1 sender plus input queue.  This manages the
// state of the NHIS 1.1 connection, re-connecting if required.
// This is a thread: You should create, called 'connect', call 'start' to
// spawn the thread, then call 'deliver' when you have packets to transmit.
class nhis11_sender : public sender {
private:

    // NHIS 1.1 transport.
    std::map<std::string,cyberprobe::nhis11::sender> transport;

    // Connection details, host, port, transport.
    std::string h;
    unsigned short p;
    bool tls;

    // Params
    std::map<std::string, std::string> params;

public:

    // Constructor.
    nhis11_sender(const std::string& h, unsigned short p,
		  const std::string& transp,
		  const std::map<std::string, std::string>& params,
		  parameterised& globals) :
        sender(globals), h(h), p(p), params(params) {
	if (transp == "tls")
	    tls = true;
	else if (transp == "tcp")
	    tls = false;
	else
	    throw std::runtime_error("Transport " + transp + " not known.");
    }

    // Destructor.
    virtual ~nhis11_sender() {}

    // PDU handler
    virtual void handle(qpdu_ptr);

    // Short-hand
    typedef std::vector<unsigned char>::const_iterator const_iterator;

};

// Implements an ETSI LI sender plus input queue.  This manages the
// state of the LI connection, re-connecting if required.
// This is a thread: You should create, called 'connect', call 'start' to
// spawn the thread, then call 'deliver' when you have packets to transmit.
class etsi_li_sender : public sender {
private:

    typedef cyberprobe::etsi_li::sender e_sender;
    typedef cyberprobe::etsi_li::mux e_mux;

    // ETSI LI transport and mux...

    // Number of TCP connections to multiplex over.
    unsigned int num_connects;

    // Transports
    e_sender* transports;

    // Map of device/LIID to transport.
    std::map<std::string,e_sender&> transport_map;

    // Multiplexes
    std::map<std::string,e_mux> muxes;

    // Connection details, host, port.
    std::string h;
    unsigned short p;

    // Params
    std::map<std::string, std::string> params;

    // Round-round count.
    unsigned int cur_connect;

    // True if TLS enabled.
    bool tls;			

    // Map, records if appropriate IRI BEGIN messages have been sent
    // to introduce this device / LIID.
    std::map<std::string, bool> setup;

    // Initialise some configuration
    void initialise() { }

public:

    // Constructor.
    etsi_li_sender(const std::string& h, unsigned int short p,
                   const std::string& transp,
		   const std::map<std::string, std::string>& params,
		   parameterised& globals) :
        sender(globals), h(h), p(p), params(params), cur_connect(0)
        {

            // Get value of etsi-streams parameter, default is 12.
            std::string par = globals.get_parameter("etsi-streams", "12");
            std::istringstream buf(par);

            num_connects = 0;
            buf >> num_connects;
            if (num_connects <= 0)
                throw std::runtime_error("Couldn't parse etsi-streams value: " +
                                         par);

            transports = new e_sender[num_connects];
            if (transp == "tls")
                tls = true;
            else if (transp == "tcp")
                tls = false;
            else
                throw std::runtime_error("Transport " + transp + " not known.");
            initialise();
        }

    // PDU handler
    virtual void handle(qpdu_ptr);

    // Destructor.
    virtual ~etsi_li_sender() {
	muxes.clear();
	transport_map.clear();
	delete transports;
    }

    // Short-hand
    typedef std::vector<unsigned char>::const_iterator const_iterator;

};

};

#endif

