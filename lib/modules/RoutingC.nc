#include "../../includes/neighbor.h"
#include "../../includes/routing.h"

configuration RoutingC
{
	provides interface Routing;
}

implementation
{
	components RoutingP;
	Routing = RoutingP;
	
	// LSA Flooding
	components MainC;
	RoutingP.Boot -> MainC.Boot;
	
	components RandomC, new TimerMilliC() as LSATimer;
	RoutingP.Random -> RandomC;
	RoutingP.LSATimer -> LSATimer;
	
	components new PoolC(Edge, MAX_NEIGHBOR_TABLE) as LinkStateQP, new QueueC(Edge*, MAX_NEIGHBOR_TABLE) as LinkStateQ;
	RoutingP.LinkStateQP -> LinkStateQP;
	RoutingP.LinkStateQ -> LinkStateQ;
	
	components NeighborDiscoveryC, FloodingC;
	RoutingP.NeighborDiscovery -> NeighborDiscoveryC;
	RoutingP.Flooding -> FloodingC;
	
	// Dijkstra's
	components new TimerMilliC() as DijkstraTimer;
	RoutingP.DijkstraTimer -> DijkstraTimer;
	
	components new PoolC(uint16_t, MAX_GRAPH_ENTRIES) as DijkstraQP, new MinQueueC(uint16_t*, MAX_GRAPH_ENTRIES) as DijkstraQ;
	RoutingP.DijkstraQP -> DijkstraQP;
	RoutingP.DijkstraQ -> DijkstraQ;
	
	// Route Table
	components new HashmapC(Edge, MAX_GRAPH_ENTRIES) as RoutingTable;	// There should actually be space for V^2 edges, but this will do for now.
	RoutingP.RoutingTable -> RoutingTable;
}