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
	
	// Forwarding delay for fragmented packets.
	components RandomC, new TimerMilliC() as ForwardDelay;
	FloodingP.Random -> RandomC;
	FloodingP.ForwardDelay -> ForwardDelay;
	
	components NeighborDiscoveryC;
	FloodingP.NeighborDiscovery -> NeighborDiscoveryC;
	
	// Sequence Number Cache.
	components new HashmapC(uint16_t, 8);
	FloodingP.SequenceCache -> HashmapC;
}