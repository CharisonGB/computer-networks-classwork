#include "../../includes/socket.h"

configuration TransportC
{
	provides interface Transport;
}

implementation
{
	components TransportP;
	Transport = TransportP;
	
	components MainC;
	TransportP.Boot -> MainC.Boot;
	
	components new QueueC(socket_t, MAX_NUM_OF_SOCKETS) as SocketQ;
	TransportP.SocketQ -> SocketQ;
	components new HashmapC(socket_store_t*, MAX_NUM_OF_SOCKETS) as SocketMap;
	TransportP.SocketMap -> SocketMap;
	
	components new HashmapC(socket_t, MAX_NUM_OF_SOCKETS) as ListeningPorts;
	TransportP.ListeningPorts -> ListeningPorts;
	
	components InternetProtocolC;
	TransportP.IP -> InternetProtocolC;
	
	
}
