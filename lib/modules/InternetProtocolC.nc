configuration InternetProtocolC
{
	provides interface InternetProtocol;
}

implementation
{
	components InternetProtocolP;
	InternetProtocol = InternetProtocolP;
	
	components new SimpleSendC(AM_PACK);
	InternetProtocolP.IPSend -> SimpleSendC;
	
	components new AMReceiverC(AM_PACK);
	InternetProtocolP.IPReceive -> AMReceiverC;
	
	components RoutingC;
	InternetProtocolP.Routing -> RoutingC;
}