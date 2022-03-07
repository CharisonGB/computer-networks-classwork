#include "../../includes/channels.h"
#include "../../includes/packet.h"

interface NeighborDiscovery
{
	command bool isNeighbor(uint16_t address);
	command uint16_t getNeighbors(uint16_t *neighbors);
	command uint16_t numNeighbors();
	command void printNeighborTable();
}

// Change getNeighbors to return const reference to the neighborlist. This way we can just point to one instance from all modules.
