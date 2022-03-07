#include "../../includes/packet.h"

interface SimpleSend{
   command error_t send(pack msg, uint16_t dest );
}

// SimpleSend only deals with packets as defined in packet.h, but
// could be modified to be generic and deal with any defined packet type.

// NotSoSimpleSend?
// Would need to replace sendInfo.h to support current Pool/Queue logic.
// Generic sendInfo? Define in NotSoSimpleSend locally to take advantage of generic type.
// Why is sendInfo even a header? SimpleSend looks like the only component that uses it.