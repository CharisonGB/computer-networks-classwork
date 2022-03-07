#include "../../includes/packet.h"
#include "../../includes/neighbor.h"
#include "../../includes/flooding.h"
#include "../../includes/linkState.h"

module RoutingP
{
	provides interface Routing;
	
	uses interface SimpleSend as Forwarder; // Only for forwarding.
	
	uses interface Boot;
	uses interface Random;
	uses interface Timer<TMilli> as Periodic; // Periodic LSP floods.
	
	uses interface NeighborDiscovery;
	uses interface Flooding;
	
	uses interface Timer<TMilli> as LongTimer; // Dijkstra Timer.
	
	uses interface Hashmap<graphEntry> as Graph; // Hashmap for storing the network topo.
	uses interface Hashmap<routingEntry> as RoutingTable; // Hashmap for storing the Routing Table.
	
	uses interface Pool<graphEntry>;
	uses interface Queue<graphEntry*>;
}

implementation
{
	linkState_t LSP;	// Temp space for preparing LSPs.
	
	graphEntry gEntry;	// Temp space for preparing Graph Entries.
	graphEntry* gEnt = &gEntry;
	
	routingEntry rEntry;	// Temp space for preparing Routing Entries.
	routingEntry* rEnt = &rEntry;
	
	// Flood this node's neighbor list
	uint16_t neighborList[MAX_NEIGHBOR_TABLE];
	uint16_t seqNum = 0;
	uint16_t seqCache = 0;
	
	// Make linkstate packet prototype
	void makeLinkStatePacket(linkState_t* lsp, uint16_t src, uint16_t seq, uint8_t protocol, uint8_t nbrs, uint8_t* payload, uint8_t len);
	
	// Flood linkstate
	task void floodLSP()
	{
		linkState_t* lsp = &LSP;
		
		lsp->numNbrs = call NeighborDiscovery.getNeighbors(&neighborList);
		
		makeLinkStatePacket(&LSP, TOS_NODE_ID, seqNum++, PROTOCOL_LINKSTATE, lsp->numNbrs, &neighborList, LINKSTATE_MAX_PAYLOAD);
		call Flooding.flood(&LSP, FLOOD_MAX_PAYLOAD_SIZE);
		
		//dbg(ROUTING_CHANNEL, "[ROUTING] %d tried to flood an LSP: src=%d, seq=%d, pro=%d, nbrs=%d\n", TOS_NODE_ID, lsp->src, lsp->seq, lsp->protocol, lsp->numNbrs);
	}
	
	event void Periodic.fired()
	{
		post floodLSP();
	}
	
	task void dijkstra()
	{
		uint16_t numNeighbors = call NeighborDiscovery.getNeighbors(&neighborList);
		uint16_t i;
		
		routingEntry currentShortest;
		routingEntry* shortest = &currentShortest;
		
		routingEntry edgeWeight;
		routingEntry* edge = &edgeWeight;
		
		graphEntry* vertex;
		
		if(numNeighbors == 0)
			return;
		
		//** Init **//
		// Add that we are 0 hops away from ourselves to our RoutingTable.
		shortest->nextHop = TOS_NODE_ID;
		shortest->cost = 0;
		call RoutingTable.insert(TOS_NODE_ID, currentShortest);
		
		// Queue everybody we got an LSP from. Note we are not in our own graph.
		for(i = 0; i < call Graph.size(); i++)
		{
			if( !call Pool.empty() )
			{
				vertex = call Pool.get();
				*vertex = call Graph.get( *((call Graph.getKeys())+i) );
				call Queue.enqueue(vertex);
			}
		}
		
		if( call Queue.empty() )
			return;
		
		for(i = 0; i < call Queue.size(); i++)
		{
			vertex = call Queue.element(i);
			
			if( call NeighborDiscovery.isNeighbor(vertex->address) )
			{
				shortest->nextHop = vertex->address;
				shortest->cost = 1;
			}
			else
			{
				shortest->nextHop = TOS_NODE_ID; // We dont know how to get to it, so just stay here.
				shortest->cost = EIGHT_BIT_INFINITY;
			}
			
			call RoutingTable.insert(vertex->address, currentShortest);
		}
		
		//** Shortest Paths **//
		while( !call Queue.empty() )
		{
			vertex = call Queue.dequeue();
			
			for(i = 0; i < vertex->numNeighbors; i++)
			{
				currentShortest = call RoutingTable.get(vertex->neighbors[i]); // Our current nextHop and cost to vertex's neighbor.
				edgeWeight = call RoutingTable.get(vertex->address);
				
				// We know we're checking vertex's neighbor, so the number of hops from vertex to them is always 1.
				// Only update our RoutingTable entry if anything actually changes.
				if( shortest->cost > edge->cost + 1 )
				{
					shortest->cost = edge->cost + 1;
					shortest->nextHop = vertex->address;
				}
				
				call RoutingTable.insert(vertex->address, currentShortest);				
			}
			
			call Pool.put(vertex);
		}
	}
	
	event void LongTimer.fired()
	{
		post dijkstra();
		dbg(ROUTING_CHANNEL, "[ROUTING] %d posted a dijkstra task!\n", TOS_NODE_ID);
	}
	
	event void Boot.booted()
	{
		call Periodic.startPeriodic( (call Random.rand16() % 1000) + 1000 );
		//call Periodic.startOneShot( (call Random.rand16() % 1000) + 1000 );
		//call LongTimer.startOneShot( (call Random.rand16() % 5000) + 5000 );
	}
	
	// Receive linkState and put it in the Graph
	event void Flooding.readFlood(uint8_t *payload, uint8_t len)
	{
		linkState_t* lsp = (linkState_t*)payload;
		//dbg(ROUTING_CHANNEL, "[ROUTING] %d saw a packet from its routing module.\n", TOS_NODE_ID);
		
		switch(lsp->protocol)
		{
			case PROTOCOL_LINKSTATE:
				//dbg(ROUTING_CHANNEL, "[ROUTING] %d recognized LSP: src=%d, seq=%d\n", TOS_NODE_ID, LSPacket->src, LSPacket->seq);
				if(lsp->seq >= seqCache)
				{
					gEnt->address = lsp->src;
					gEnt->numNeighbors = lsp->numNbrs;
					memcpy(gEnt->neighbors, lsp->payload, LINKSTATE_MAX_PAYLOAD);
					//logLinkState(lsp);
					
					call Graph.insert(lsp->src, gEntry);
					//dbg(ROUTING_CHANNEL, "[ROUTING] %d added an entry to its Graph!\n", TOS_NODE_ID);
					
					// Start a timer to post a dijkstra task when we receive a valid LSP.
					if( call LongTimer.isRunning() == 0 )
						call LongTimer.startOneShot( (call Random.rand16() % 5000) + 5000 );
				}
				break;
			
			default:
				break;
		}
	}
	
	// Move to Link State Header
	void makeLinkStatePacket(linkState_t* lsp, uint16_t src, uint16_t seq, uint8_t protocol, uint8_t nbrs, uint8_t* payload, uint8_t len)
	{
		lsp->src = src;
		lsp->seq = seqNum;
		lsp->protocol = protocol;
		lsp->numNbrs = nbrs;
		memcpy(lsp->payload, payload, len);
	}
	
	command void Routing.forward(pack* sendPack, uint16_t destination)
	{
		if( call RoutingTable.isEmpty() )
			return;
		
		dbg(ROUTING_CHANNEL, "[ROUTING] %d Forwarded!\n", TOS_NODE_ID);
		
		rEntry = call RoutingTable.get(destination);
		call Forwarder.send(*sendPack, rEnt->nextHop);
	}
}