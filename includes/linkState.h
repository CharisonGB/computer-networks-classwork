#ifndef LINKSTATE_H
#define LINKSTATE_H

#include "protocol.h"
#include "neighbor.h"
#include "flooding.h"

enum{
	LINKSTATE_HEADER_LENGTH = 6,
	LINKSTATE_MAX_PAYLOAD = FLOOD_MAX_PAYLOAD_SIZE - LINKSTATE_HEADER_LENGTH
};

enum{
	MAX_GRAPH_ENTRIES = 20
};

enum{
	EIGHT_BIT_INFINITY = 511
};

typedef nx_struct LinkState{
	nx_uint16_t src;
	nx_uint16_t seq;
	nx_uint8_t protocol;
	nx_uint8_t numNbrs;
	nx_uint8_t payload[LINKSTATE_MAX_PAYLOAD];
}linkState_t;

typedef struct GraphEntry{	// For network graph as Hashmap
	uint16_t address;
	uint16_t numNeighbors;
	uint8_t neighbors[LINKSTATE_MAX_PAYLOAD];
}graphEntry;

typedef struct RoutingTableEntry{
	uint16_t nextHop;
	uint8_t cost; // Cost in hops.
}routingEntry;

void logLinkState(linkState_t* lsp)
{
	char* list[LINKSTATE_MAX_PAYLOAD];
	uint16_t* payload = (uint16_t*)lsp->payload;
	uint8_t i;
	
	for(i = 0; i < lsp->numNbrs; i++)
		sprintf(list, "%s%d ", list, payload[i]);
	//list[lsp->numNbrs] = '\0';
	
	dbg(ROUTING_CHANNEL, "Src: %hhu Seq: %hhu Protocol: %hhu Neighbors: %hhu Payload: %s\n",
	lsp->src, lsp->seq, lsp->protocol, lsp->numNbrs, list);
}

void logGraphEntry(graphEntry* ge) // Junk printed w/ payload output
{
	char* list[LINKSTATE_MAX_PAYLOAD];
	uint16_t* payload = (uint16_t*)ge->neighbors;
	uint8_t i;
	
	for(i = 0; i < ge->numNeighbors; i++)
		sprintf(list, "%s%d ", list, payload[i]);
	//list[ge->numNeighbors] = "\0";
	
	dbg(ROUTING_CHANNEL, "Num: %hhu Payload: %s\n",
	ge->numNeighbors, list);
}

#endif