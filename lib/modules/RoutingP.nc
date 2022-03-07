#include "../../includes/packet.h"
#include "../../includes/neighbor.h"
#include "../../includes/flooding.h"
#include "../../includes/routing.h"

module RoutingP
{
	provides interface Routing;
	
	uses interface Boot;
	uses interface Random;
	uses interface Timer<TMilli> as LSATimer; // LSATimer LSA floods.
	
	uses interface Pool<Edge> as LinkStateQP;
	uses interface Queue<Edge*> as LinkStateQ;
	
	uses interface NeighborDiscovery;
	uses interface Flooding;
	
	uses interface Timer<TMilli> as DijkstraTimer; // Dijkstra Timer.
	
	uses interface Pool<uint16_t> as DijkstraQP;
	uses interface MinQueue<uint16_t*> as DijkstraQ;
	
	uses interface Hashmap<Edge> as RoutingTable; // Hashmap for storing the Routing Table.
}

implementation
{
	LinkState linkStateAdvert, *LSA = &linkStateAdvert;	// Module scope LinkState so tasks can manipulate LinkStates.
	uint16_t neighborList[MAX_NEIGHBOR_TABLE];
	uint16_t graph[MAX_GRAPH_ENTRIES][MAX_GRAPH_ENTRIES]; // This could be bitwise instead.
	
	void initGraph()
	{
		uint8_t v, n;
		
		for(v = 0; v < MAX_GRAPH_ENTRIES; v++)
		{
			for(n = 0; n < MAX_GRAPH_ENTRIES; n++)
			{
				if(n == v)
					graph[v][n] = 0;
				else
					graph[v][n] = MAX_COST;
			}
		}
	}
	
	void updateGraph(uint16_t vertex, Edge* nbrs, uint8_t len)
	{
		uint8_t i;
		
		for(i = 0; i < len; i++)
		{
			graph[vertex-1][nbrs[i].nextHop-1] = nbrs[i].cost;
			graph[nbrs[i].nextHop-1][vertex-1] = nbrs[i].cost;
			//dbg(ROUTING_CHANNEL, "[ROUTING] %d added graph[%d][%d]=%d\n", TOS_NODE_ID, vertex, nbrs[i].nextHop, nbrs[i].cost);
		}
	}
	
	void printGraph()
	{
		char graphStr[MAX_GRAPH_ENTRIES + 8], *str = &graphStr;
		uint8_t v, n;
		
		dbg(ROUTING_CHANNEL, "[ROUTING] %d\'s Topo Graph\n", TOS_NODE_ID);
		
		//sprintf(str, "%s", "\0");
		for(v = 0; v < MAX_GRAPH_ENTRIES; v++)
		{	
			sprintf(str, "%d:\t", v+1);
			for(n = 0; n < MAX_GRAPH_ENTRIES; n++)
			{
				if(graph[v][n] < MAX_COST)
					sprintf(str, "%s%d", str, graph[v][n]);
				else
					sprintf(str, "%s%s", str, "-");
			}
			dbg(ROUTING_CHANNEL, "[ROUTING]%s\n", str);
		}
	}
	
	event void Boot.booted()
	{
		initGraph();
		//printGraph();
		call LSATimer.startPeriodic( (call Random.rand16() % 1000) + 1000 );
		//call LSATimer.startOneShot( (call Random.rand16() % 1000) + 1000 );
		//call DijkstraTimer.startOneShot( (call Random.rand16() % 5000) + 5000 );
	}
	
	// Make up-to-date linkstate packets before flooding.
	void updateLinkState()
	{
		Edge* entry;
		uint16_t n = call NeighborDiscovery.getNeighbors(&neighborList);
		
		while(n-- > 0 && !call LinkStateQP.empty())
		{
			entry = call LinkStateQP.get();
			entry->nextHop = neighborList[n];
			entry->cost = 1;
			call LinkStateQ.enqueue(entry);
		}
	}
	
	void AdvertiseLinkState() // Pull off as many Edges from the queue as will fit in a LinkState. Flood the LSA.
	{
		uint8_t maxEdges = LINKSTATE_MAX_PAYLOAD/sizeof(Edge), i = 0;
		Edge payloadEdges[maxEdges], *pyldEdges = &payloadEdges, *entry;
		
		do
		{
			entry = call LinkStateQ.dequeue();
			pyldEdges[i] = *entry;
			call LinkStateQP.put(entry);
			//dbg(ROUTING_CHANNEL, "[ROUTING] %d loaded next=%d|cost=%d into an LSA!\n", TOS_NODE_ID, pyldEdges[i].nextHop, pyldEdges[i].cost);
		} while(++i < maxEdges && !call LinkStateQ.empty()); // i ends as the number of edges we actually loaded
		
		//dbg(ROUTING_CHANNEL, "[ROUTING] %d is advertising an LSA with %d entries!\n", TOS_NODE_ID, i);
		makeLinkState(LSA, PROTOCOL_LINKSTATE, i, (uint8_t*)pyldEdges, maxEdges*sizeof(Edge));
		call Flooding.flood((uint8_t*)LSA, sizeof(LinkState));
	}
	
	event void LSATimer.fired() // make LSAs here? Increment Edge list pointer.
	{	
		if( call LinkStateQ.empty() )
			updateLinkState();
		else
			AdvertiseLinkState();
	}
	
	// Receive linkState and put it in the Graph
	event void Flooding.readFlood(uint16_t src, uint8_t *payload, uint8_t len)
	{
		LinkState* lsa = (LinkState*)payload;
		Edge* pyldEdges;
		//dbg(ROUTING_CHANNEL, "[ROUTING] %d saw a packet from its routing module.\n", TOS_NODE_ID);
		
		switch(lsa->protocol)
		{
			case PROTOCOL_LINKSTATE:
				//dbg(ROUTING_CHANNEL, "[ROUTING] %d got LSA: src=%d, entries=%d\n", TOS_NODE_ID, src, lsa->numNbrs);
				
				pyldEdges = &lsa->payload;
				
				updateGraph(src, pyldEdges, lsa->numNbrs);
				
				// Start a timer to post a dijkstra task when we receive a valid LSA.
				if( call DijkstraTimer.isRunning() == 0 )
					call DijkstraTimer.startOneShot( (call Random.rand16() % 5000) + 5000 );
				break;
			
			default:
				break;
		}
	}
	
	task void dijkstra()
	{
		Edge currentShortest, *shortest = &currentShortest;
		
		uint16_t* consideration;
		uint16_t v, n;
		
		// Initialize neighbors our in the graph.
		n = call NeighborDiscovery.getNeighbors(&neighborList);
		
		if(n == 0)
			return;
		
		while(n-- > 0)
		{
			graph[TOS_NODE_ID-1][neighborList[n]-1] = 1;
			graph[neighborList[n]-1][TOS_NODE_ID-1] = 1;
		}
		
		// Queue all vertices in the graph.
		for(v = 0; v < MAX_GRAPH_ENTRIES; v++)
		{
			if( !call DijkstraQP.empty() )
			{
				consideration = call DijkstraQP.get();
				*consideration = v+1;
				call DijkstraQ.enqueue(graph[TOS_NODE_ID][*consideration], consideration);
				//dbg(ROUTING_CHANNEL, "[ROUTING::DIJKSTRA] %d queued graph[%d][%d]=%d\n", TOS_NODE_ID, TOS_NODE_ID, *consideration, graph[TOS_NODE_ID-1][(*consideration)-1]);
			}
			else { dbg(ROUTING_CHANNEL, "[ROUTING::DIJKSTRA] Dijkstra Pool Full! Out of Memory!\n"); }
		}
		
		// Find Shortest Paths
		while( !call DijkstraQ.empty() )
		{
			consideration = call DijkstraQ.dequeue();
			//dbg(ROUTING_CHANNEL, "[ROUTING::DIJKSTRA] %d is considering %d\n", TOS_NODE_ID, *consideration);
			
			for(n = MAX_GRAPH_ENTRIES; n > 0; n--)
			{
				if(graph[(*consideration)-1][n-1] != 1)	// Only check neighbors of consideration!
					continue;
				
				// Shortest will hold the cost of getting to consideration's neighbor directly.
				if( call RoutingTable.contains(n) )
				{
					*shortest = call RoutingTable.get(n);
					//dbg(ROUTING_CHANNEL, "[ROUTING::DIJKSTRA] %d\'s RT contains dest=%d:(next=%d, cost=%d)\n", TOS_NODE_ID, n, shortest->nextHop, shortest->cost);
				}
				else
				{
					shortest->cost = graph[TOS_NODE_ID-1][n-1];
					shortest->nextHop = n;
					//dbg(ROUTING_CHANNEL, "[ROUTING::DIJKSTRA] %d\'s RT didn\'t contain dest=%d:(next=%d, cost=%d)\n", TOS_NODE_ID, n, shortest->nextHop, shortest->cost);
				}
				
				if(graph[TOS_NODE_ID-1][n-1] > graph[TOS_NODE_ID-1][(*consideration)-1] + graph[(*consideration)-1][n-1])
				{
					graph[TOS_NODE_ID-1][n-1] = graph[TOS_NODE_ID-1][(*consideration)-1] + graph[(*consideration)-1][n-1];
					graph[n-1][TOS_NODE_ID-1] = graph[TOS_NODE_ID-1][n-1];
					shortest->cost = graph[TOS_NODE_ID-1][n-1];
					shortest->nextHop = (call RoutingTable.get(*consideration)).nextHop;	// Since we consider radially from our neighbors, this will always carry the correct nextHop to ancestor nodes.
				}
				//else { dbg(ROUTING_CHANNEL, "[ROUTING::DIJKSTRA] %d couldn\'t find a better path to %d\n", TOS_NODE_ID, n); }
				
				if(shortest->cost == MAX_COST)
					continue;
				
				call RoutingTable.insert(n, *shortest);
				//dbg(ROUTING_CHANNEL, "[ROUTING::DIJKSTRA] %d added dest=%d:(next=%d, cost=%d)\n", TOS_NODE_ID, n, shortest->nextHop, shortest->cost);
			}
			
			call DijkstraQP.put(consideration);
		}
	}
	
	event void DijkstraTimer.fired()
	{
		post dijkstra();
		//dbg(ROUTING_CHANNEL, "[ROUTING] %d posted a dijkstra task!\n", TOS_NODE_ID);
		//printGraph();
	}
	
	command void Routing.printRoutingTable()
	{
		char RTStr[MAX_GRAPH_ENTRIES * 32], *str = &RTStr;
		
		Edge* shortest;
		uint32_t* vertices = call RoutingTable.getKeys();
		uint8_t v;
		
		sprintf(str, "%s", "\n");
		for(v = 0; v < call RoutingTable.size(); v++)
		{
			*shortest = call RoutingTable.get(vertices[v]);
			sprintf(str, "%s%d:(next=%d, cost=%d)\n", str, vertices[v], shortest->nextHop, shortest->cost);
		}
		
		dbg(ROUTING_CHANNEL, "[ROUTING]%s\n", str);
	}
	
	command uint16_t Routing.next(uint16_t destination)
	{
		return ( call RoutingTable.get(destination) ).nextHop;
	}
}