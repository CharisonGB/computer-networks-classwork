//#include "../../includes/channels.h"
//#include "../../includes/packet.h"

interface NeighborDiscovery
{
	command uint16_t getNeighbors(uint16_t *neighbors);
	command bool isNeighbor(uint16_t address);
}

// TODO:
// Add bool isNeighbor(address)
// Add int numNeighbors()
