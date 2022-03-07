configuration FloodingC
{
	provides interface Flooding;
}

implementation
{
	components FloodingP;
	Flooding = FloodingP;
	
	components new SimpleSendC(AM_PACK);
	FloodingP.FSend -> SimpleSendC;
	
	components new AMReceiverC(AM_PACK);
	FloodingP.FReceive -> AMReceiverC;
	
	components NeighborDiscoveryC;
	FloodingP.NeighborDiscovery -> NeighborDiscoveryC;
}