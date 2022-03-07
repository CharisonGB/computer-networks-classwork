#include "../../includes/linkState.h"

configuration RoutingC
{
	provides interface Routing;
}

implementation
{
	components RoutingP;
	Routing = RoutingP;
	
	// Forwarding
	components new SimpleSendC(AM_PACK);
	RoutingP.Forwarder -> SimpleSendC;
	
	// LSP Flooding
	components MainC;
	RoutingP.Boot -> MainC.Boot;
	
	components new TimerMilliC() as Periodic;
	RoutingP.Periodic -> Periodic;
	
	components RandomC;
	RoutingP.Random -> RandomC;
	
	components NeighborDiscoveryC;
	RoutingP.NeighborDiscovery -> NeighborDiscoveryC;
	
	components FloodingC;
	RoutingP.Flooding -> FloodingC;
	
	// Dijkstra's
	components new TimerMilliC() as LongTimer;
	RoutingP.LongTimer -> LongTimer;
	
	components new HashmapC(graphEntry, MAX_GRAPH_ENTRIES) as Graph;
	RoutingP.Graph -> Graph;
	
	components new HashmapC(routingEntry, MAX_GRAPH_ENTRIES) as RoutingTable;
	RoutingP.RoutingTable -> RoutingTable;
	
	components new PoolC(graphEntry, 20);
	RoutingP.Pool -> PoolC;
	
	components new QueueC(graphEntry*, 20);
	RoutingP.Queue -> QueueC;
}