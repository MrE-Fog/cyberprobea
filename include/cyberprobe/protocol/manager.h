
#ifndef CYBERMON_ANALYSER_MANAGER_H
#define CYBERMON_ANALYSER_MANAGER_H

#include <cyberprobe/util/reaper.h>
#include <cyberprobe/protocol/observer.h>

namespace cyberprobe {

    namespace protocol {

        class manager : public observer, public util::reaper {
        public:

        };

    }

}

#endif

