#include "../../includes/socket.h"

module AppP
{
	provides interface App;
	
	uses interface CommandHandler;
	
	uses interface Transport;
	
	uses interface Timer<TMilli> as ConnectDelay;
	uses interface Timer<TMilli> as WriteDelay;
	uses interface Timer<TMilli> as ReadDelay;
	
	uses interface Random as Random;
}

implementation
{
	socket_t fd_listen, fd_accept, fd_clnt;
	uint16_t transLen;
	uint8_t transferBuffer[64], *transBuff = &transferBuffer;
	
	command void App.idk()
	{
		
	}
	
	event void CommandHandler.setTestServer(uint8_t source, uint8_t port)
	{
		socket_addr_t srvrAddr;
		
		srvrAddr.port = (socket_port_t)port;
		srvrAddr.addr = (uint16_t)source;
		
		if( call ConnectDelay.isRunning() )
		{
			dbg(TRANSPORT_CHANNEL, "[TRANSPORT] BLOCKED; <%d,%d> tried to accept while another accept is in progress.\n", TOS_NODE_ID, srvrAddr.port);
			return;
		}
		
		if( (fd_listen = call Transport.socket()) != NULL
			&& call Transport.bind(fd_listen, &srvrAddr) == SUCCESS
			&& call Transport.listen(fd_listen) == SUCCESS )
		{
			call ConnectDelay.startOneShot(1000);
		}
	}
	
	event void ConnectDelay.fired()
	{
		fd_accept = call Transport.accept(fd_listen);
		if( fd_accept == NULL )
		{
			call ConnectDelay.startOneShot(2000);
		}
		
		//call ReadDelay.startOneShot(4000);
		call ReadDelay.startPeriodic(6000);
	}
	
	event void CommandHandler.setTestClient(uint8_t source, uint8_t srcPort, uint8_t destination, uint8_t destPort, uint16_t transfer)
	{
		socket_addr_t clntAddr, srvrAddr;
		
		clntAddr.port = (socket_port_t)srcPort;
		clntAddr.addr = (uint16_t)source;
		
		srvrAddr.port = (socket_port_t)destPort;
		srvrAddr.addr = (uint16_t)destination;
		
		if( (fd_clnt = call Transport.socket()) != NULL
			&& call Transport.bind(fd_clnt, &clntAddr) == SUCCESS )
		{
			call Transport.connect(fd_clnt, &srvrAddr);
			//call WriteDelay.startOneShot(3000);
			call WriteDelay.startPeriodic(4000);
			transLen = transfer;	// Transfer value broken when passed from TestSim to CommandHandler.
		}
	}
	
	event void WriteDelay.fired()
	{
		uint16_t numBytes = 0;
		//memcpy(transBuff, "Hello_World", 12);
		
		while(numBytes < transLen)
			transBuff[numBytes++] = (call Random.rand16() % 256);
		
		call Transport.write(fd_clnt, transBuff, transLen);
	}
	
	event void ReadDelay.fired()
	{
		call Transport.read(fd_accept, transBuff, 16);
		dbg(TRANSPORT_CHANNEL, "[TRANSPORT] %s\n", transBuff);
	}
	
	event void CommandHandler.killConn(uint8_t source, uint8_t srcPort, uint8_t destination, uint8_t destPort)
	{
		fd_clnt = call Transport.getConn(source, srcPort, destination, destPort);
		if(fd_clnt == NULL)
			return;
		
		if( call Transport.close(fd_clnt) != SUCCESS );
			dbg(TRANSPORT_CHANNEL, "[TRANSPORT] FAIL; <%d,%d> could not be closed.\n", TOS_NODE_ID, srcPort);
		
		return;
	}
	
	
	event void CommandHandler.setAppServer(){}
	
	event void CommandHandler.setAppClient(){}
	
	// Unused
	event void CommandHandler.ping(uint16_t destination, uint8_t *payload){}
	event void CommandHandler.printNeighbors(){}
	event void CommandHandler.printRouteTable(){}
	event void CommandHandler.printLinkState(){}
	event void CommandHandler.printDistanceVector(){}
}