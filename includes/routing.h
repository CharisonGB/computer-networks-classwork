#ifndef ROUTING_H
#define ROUTING_H

#include "protocol.h"
#include "neighbor.h"
#include "flooding.h"

enum{
	LINKSTATE_HEADER_LENGTH = 2,
	LINKSTATE_MAX_PAYLOAD = FLOOD_MAX_PAYLOAD_SIZE - LINKSTATE_HEADER_LENGTH
};

enum{
	MAX_GRAPH_ENTRIES = 20
};

enum{
	MAX_COST = 255
};

typedef struct Edge{
	uint16_t nextHop;	// Address of the next hop.
	uint8_t cost; 		// Cost in hops.
}Edge;

typedef nx_struct LinkState{ // These are getting flooded
	//nx_uint16_t src;		// The source of an LSA is whoever flooded it, so use flood source instead.
	//nx_uint16_t seq;		// FIXME: We could be flooding anything, so this should be here. If we flood anything else later, I'll have to fix this!
	nx_uint8_t protocol;	// We could be flooding anything, so keep this here.
	nx_uint8_t numNbrs;		// <= sizeof(Edge) / LINKSTATE_MAX_PAYLOAD;
	nx_uint8_t payload[LINKSTATE_MAX_PAYLOAD];
}LinkState;

void makeLinkState(LinkState* linkstate, uint8_t protocol, uint8_t numNbrs, uint8_t* payload, uint8_t len)
{
	linkstate->protocol = protocol;
	linkstate->numNbrs = numNbrs;
	memcpy(linkstate->payload, payload, len);
}

#endif