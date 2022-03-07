/*
 * ANDES Lab - University of California, Merced
 * This class provides the basic functions of a network node.
 *
 * @author UCM ANDES Lab
 * @date   2013/09/03
 *
 */
#include <Timer.h>
#include "includes/command.h"
#include "includes/packet.h"
#include "includes/CommandMsg.h"
#include "includes/sendInfo.h"
#include "includes/channels.h"
#include "includes/protocol.h"
#include "includes/neighbor.h"
#include "includes/flooding.h"
#include "includes/routing.h"
#include "includes/IP.h"
#include "includes/socket.h"

module Node{
	uses interface Boot;
	
	uses interface SplitControl as AMControl;
	uses interface Receive;
	
	uses interface SimpleSend as Sender;
	
	uses interface CommandHandler;
	
	uses interface NeighborDiscovery;
	uses interface Flooding;
	
	uses interface Routing;
	uses interface InternetProtocol as IP;
	
	uses interface Transport;
	uses interface Timer<TMilli> as ConnectDelay;
	uses interface Timer<TMilli> as CloseDelay;
	
	uses interface App;
}

implementation{
	pack sendPackage;
	
	socket_t fd_clnt, fd_accept, fd_listen;
	
	event void Boot.booted(){
		call AMControl.start();
		
		dbg(GENERAL_CHANNEL, "Booted\n");
	}

	event void AMControl.startDone(error_t err){
		if(err == SUCCESS){
			dbg(GENERAL_CHANNEL, "Radio On\n");
		}else{
			//Retry until successful
			call AMControl.start();
		}
	}

	event void AMControl.stopDone(error_t err){}

	event message_t* Receive.receive(message_t* msg, void* payload, uint8_t len){
		/*
		//dbg(GENERAL_CHANNEL, "Packet Received\n");
		if(len == sizeof(pack)) // Is the payload received the size of a pack?
		{
			pack* myMsg=(pack*) payload; // Interpret the received payload as a pack.
				
			//if(myMsg->dest != TOS_NODE_ID)
				//call Routing.forward(myMsg, myMsg->dest);
			
			//dbg(GENERAL_CHANNEL, "Package Payload: %s\n", myMsg->payload); // Output the pack's payload to the general channel.
			return msg;
		}
		
		dbg(GENERAL_CHANNEL, "Unknown Packet Type %d\n", len);
		*/
		return msg;
	}
	
	event void IP.receive(uint8_t *payload, uint8_t len, uint16_t source)
	{
		dbg(GENERAL_CHANNEL, "Package Payload: %s\n", payload);
	}

	event void CommandHandler.ping(uint16_t destination, uint8_t *payload){
		
		dbg(GENERAL_CHANNEL, "PING EVENT \n");
		//makePack(&sendPackage, TOS_NODE_ID, destination, 0, 0, 0, payload, PACKET_MAX_PAYLOAD_SIZE);
		
		call IP.send(payload, PACKET_MAX_PAYLOAD_SIZE, destination);
	}
	
	event void Flooding.readFlood(uint16_t src, uint8_t *payload, uint8_t len)
	{
		dbg(FLOODING_CHANNEL, "[FLOOD] %d saw %d flooded: %s\n", TOS_NODE_ID, src, payload);
	}

	event void CommandHandler.printNeighbors()
	{
		call NeighborDiscovery.printNeighborTable();
	}
	
	event void CommandHandler.printRouteTable()
	{
		call Routing.printRoutingTable();
	}
	
	event void CommandHandler.printLinkState(){}
	
	event void CommandHandler.printDistanceVector(){}
	
	event void CommandHandler.setTestServer(uint8_t source, uint8_t port)
	{/*
		//socket_t fd_listen;
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
		
	*/}
	
	event void ConnectDelay.fired()
	{/*
		fd_accept = call Transport.accept(fd_listen);
		if( fd_accept == NULL )
		{
			call ConnectDelay.startOneShot(2000);
		}
	*/}
	
	event void CommandHandler.setTestClient(uint8_t source, uint8_t srcPort, uint8_t destination, uint8_t destPort, uint16_t transfer)
	{/*
		socket_addr_t clntAddr, srvrAddr;
		
		clntAddr.port = (socket_port_t)srcPort;
		clntAddr.addr = (uint16_t)source;
		
		srvrAddr.port = (socket_port_t)destPort;
		srvrAddr.addr = (uint16_t)destination;
		
		if( (fd_clnt = call Transport.socket()) != NULL
			&& call Transport.bind(fd_clnt, &clntAddr) == SUCCESS )
		{
			call Transport.connect(fd_clnt, &srvrAddr);
			//Test
			call Transport.write(fd_clnt, transfer, SOCKET_BUFFER_SIZE);
		}
	*/}
	
	event void CommandHandler.killConn(uint8_t source, uint8_t srcPort, uint8_t destination, uint8_t destPort)
	{/*
		fd_clnt = call Transport.getConn(source, srcPort, destination, destPort);
		if(fd_clnt == NULL)
			return;
		
		if( call Transport.close(fd_clnt) != SUCCESS );
			dbg(TRANSPORT_CHANNEL, "[TRANSPORT] FAIL; <%d,%d> could not be closed.\n", TOS_NODE_ID, srcPort);
		
		return;
	*/}
	
	event void CloseDelay.fired()
	{
		// Vestigial
	}
	
	event void CommandHandler.setAppServer(){}
	
	event void CommandHandler.setAppClient(){}
	
}
