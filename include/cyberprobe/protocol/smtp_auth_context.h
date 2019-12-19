
////////////////////////////////////////////////////////////////////////////
//
// SMTP Authentication Context
//
////////////////////////////////////////////////////////////////////////////

#ifndef CYBERMON_SMTP_AUTH_CONTEXT_H
#define CYBERMON_SMTP_AUTH_CONTEXT_H

#include <cyberprobe/protocol/context.h>
#include <cyberprobe/protocol/manager.h>

namespace cyberprobe {
namespace protocol {
    
// An SMTP_AUTH context.
    class smtp_auth_context : public context
    {
    public:

        // Constructor.
        smtp_auth_context(manager& m) : context(m) {}

        // Constructor, when specifying flow address and parent context.
        smtp_auth_context(manager& m, const flow_address& a, context_ptr p)
            : context(m)
            { 
                addr = a;
                parent = p; 
            }

        // Type is "smtp_auth".
        virtual std::string get_type()
            {
                return "smtp_auth";
            }

        typedef std::shared_ptr<smtp_auth_context> ptr;

        static context_ptr create(manager& m, const flow_address& f, context_ptr par)
            { 
                context_ptr cp = context_ptr(new smtp_auth_context(m, f, par));
                return cp;
            }

        // Given a flow address, returns the child context.
        static ptr get_or_create(context_ptr base, const flow_address& f)
            {
                context_ptr cp = context::get_or_create(base, f, smtp_auth_context::create);
                ptr sp = std::dynamic_pointer_cast<smtp_auth_context>(cp);
                return sp;
            }
    };

}
}

#endif

