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
	
	components RandomC;
	TransportP.Random -> RandomC;
	
	components new QueueC(socket_t, MAX_NUM_OF_SOCKETS) as SocketQ;
	TransportP.SocketQ -> SocketQ;
	components new HashmapC(socket_store_t*, MAX_NUM_OF_SOCKETS) as SocketMap;
	TransportP.SocketMap -> SocketMap;
	
	components new HashmapC(socket_t, MAX_NUM_OF_SOCKETS) as PortMap;
	TransportP.PortMap -> PortMap;
	
	components new HashmapC(conn_req_t, MAX_NUM_OF_SOCKETS) as PendingConnections;
	TransportP.PendingConnections -> PendingConnections;
	
	//components new PoolC(conn_req_t, 2*MAX_NUM_OF_SOCKETS) as ConnQP;
	//components new QueueC(conn_req_t*, 2*MAX_NUM_OF_SOCKETS) as ConnQ;
	//TransportP.ConnQP -> ConnQP;
	//TransportP.ConnQ -> ConnQ;
	
	components new TimerMilliC() as StopWatch;
	TransportP.RTTimer -> StopWatch;
	
	components new TimerMilliC() as SendTimer;
	TransportP.SendTimer -> SendTimer;
	
	components new TimerMilliC() as ClientTimer, new TimerMilliC() as ServerTimer;
	TransportP.CloseWait -> ServerTimer;
	TransportP.TimeWait -> ClientTimer;
	
	components InternetProtocolC;
	TransportP.IP -> InternetProtocolC;
	
	
}
