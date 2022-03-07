#include "../../includes/neighbor.h"

configuration NeighborDiscoveryC
{
	provides interface NeighborDiscovery;
}

implementation
{
	components NeighborDiscoveryP;
	NeighborDiscovery = NeighborDiscoveryP;
	
	// Send and Receive for discovery packs
	components new SimpleSendC(AM_PACK);
	NeighborDiscoveryP.NDSend -> SimpleSendC;
	
	components new AMReceiverC(AM_PACK);
	NeighborDiscoveryP.NDReceive -> AMReceiverC;
	
	// Boot for starting the timer
	components MainC;
	NeighborDiscoveryP.Boot -> MainC.Boot;
	
	// Random numbers and Timer for discovery pings
	components RandomC;
	NeighborDiscoveryP.Random -> RandomC;
	
	components new TimerMilliC() as Periodic;
	NeighborDiscoveryP.Periodic -> Periodic;
	
	// The Neighbor Table
	components new HashmapC(NeighborData, MAX_NEIGHBOR_TABLE);
	NeighborDiscoveryP.NeighborTable -> HashmapC;
}