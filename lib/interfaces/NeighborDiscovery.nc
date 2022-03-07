//#include "../../includes/channels.h"
//#include "../../includes/packet.h"

interface NeighborDiscovery
{
	command uint16_t getNeighbors(uint16_t *neighbors);
}

// TODO:
// Remove getNeighbors()
// Add bool isNeighbor(address)
// Add int numNeighbors()
