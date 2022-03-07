#include "../../includes/packet.h"

interface Routing
{
	command uint16_t next(uint16_t destination);
	command void printRoutingTable();
}