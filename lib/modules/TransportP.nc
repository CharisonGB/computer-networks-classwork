#include "../../includes/socket.h"

module TransportP
{
	provides interface Transport;
	
	uses interface Boot;
	
	uses interface Queue<socket_t> as SocketQ;
	uses interface Hashmap<socket_store_t*> as SocketMap;
	
	uses interface Hashmap<socket_t> as ListeningPorts;
	
	uses interface InternetProtocol as IP;
}

implementation
{
	socket_store_t sockets[MAX_NUM_OF_SOCKETS];
	
	segment_t sendSegment, *sendSeg = &sendSegment;
	
	void initSockets()
	{
		uint8_t i;
		
		for(i = MAX_NUM_OF_SOCKETS; i > 0; i--)
		{
			call SocketMap.insert(i, &sockets[i-1]);		// Associate sockets with file descriptors.
			(call SocketMap.get(i))->state = CLOSED;	// Default sockets to closed connections.
			call SocketQ.enqueue( (socket_t)i );
		}
		
		dbg(TRANSPORT_CHANNEL, "[TRANSPORT::PORTS] %d has %d available sockets.\n", TOS_NODE_ID, call SocketQ.size());
	}
   
	event void Boot.booted()
	{
		initSockets();	// Queue all sockets as available on boot.
	}
	
	command socket_t Transport.socket()	// Socket allocation from internal availability.
	{
		if(call SocketQ.empty())
			return NULL;
		
		return call SocketQ.dequeue();
	}
	
	command error_t Transport.bind(socket_t fd, socket_addr_t *addr)
	{
		// Associate this <IP, port> w/ the socket at this fd.
		
		// Can't bind with an invalid socket or improperly closed socket.
		if(fd == NULL || (call SocketMap.get(fd))->state != CLOSED)
		{
			dbg(TRANSPORT_CHANNEL, "[TRANSPORT::BIND] %d failed to bind a new socket.\n", TOS_NODE_ID);
			return FAIL;
		}
		
		(call SocketMap.get(fd))->src = addr->port;
		// We know our address, so just add the source port number to this socket.
		//addr->addr = TOS_NODE_ID; // Redundant. Node ID stands-in for IP address.
		
		dbg(TRANSPORT_CHANNEL, "[TRANSPORT::BIND] %d bound port %d.\n", TOS_NODE_ID, addr->port);
		return SUCCESS;
	}
	
	command error_t Transport.listen(socket_t fd)
	{
		// The socket at fd is listening for connections.
		
		// Make sure that fd is valid and actually bound to a socket. If not, report an err.
		if( fd == NULL || !call SocketMap.contains(fd) )
		{
			dbg(TRANSPORT_CHANNEL, "[TRANSPORT::LISTEN] Socket at %d is NULL or Unbound.\n", TOS_NODE_ID);
			return FAIL;
		}
		
		// Move fd to LISTEN. ?Add fd to a map of listening sockets keyed by port number?
		(call SocketMap.get(fd))->state = LISTEN;
		call ListeningPorts.insert( (call SocketMap.get(fd))->src, fd ); // FIXME: ListeningPorts should hold connection requests, since thats where the deMUX actually needs to happen.
		dbg(TRANSPORT_CHANNEL, "[TRANSPORT::LISTEN] Port %d at %d is listening.\n", (call SocketMap.get(fd))->src, TOS_NODE_ID);
		
		return SUCCESS;
	}
	
	command socket_t Transport.accept(socket_t fd)
	{
		// Queue connection requests from IP.receive until this called to handle them.
		// Passive open.
		// Accept a connection attempt at listening socket fd.
		
		if( fd == NULL || !call SocketMap.contains(fd) )
		{
			dbg(TRANSPORT_CHANNEL, "[TRANSPORT::ACCEPT] Socket at %d is NULL or Unbound.\n", TOS_NODE_ID);
			return fd;
		}
		
		// Check that socket fd is listening. If not, return NULL.
		if( (call SocketMap.get(fd))->state != LISTEN )
		{
			dbg(TRANSPORT_CHANNEL, "[TRANSPORT::ACCEPT] Socket at %d isn't listening.\n", TOS_NODE_ID);
			return NULL;
		}
		
		// Get a pending connection.
		/*	TODO
			connect() will send the first SYN of the 3WHS.
			The segment will contain the information to fill fd's dest port field.
			IP.receive can pass up the IP address to fill fd's dest IP field.
			
			Task to finish processing the 3WHS.
			Send a SYN+ACK and move to SYN_RCVD.
			Wait for an ACK.
		*/
		
		return fd;
	}
	
	command error_t Transport.connect(socket_t fd, socket_addr_t * addr)
	{/*	TODO
		//Normally we'd also have send, but we don't need it for the scope of this project?
		
		// Active open a connection to server at addr through socket fd.
		
		// Can't connect on a NULL socket.
		if(fd == NULL)
			return FAIL;
		
		// Set source and destination fields.
		//(call SocketMap.get(fd))->src = // Some random number
		(call SocketMap.get(fd))->dest = *addr;
		
		// Is it worth it to write client/server versions of a 3WHS task?
		// How would it work?
		// Client side: Send a SYN, wait for SYN+ACK
		
		// Need to figure out how deMUX in receive works.
		
		// Try to send a SYN segment. Move our socket state to SYN_SENT.
		// FIXME: Use the actual seq and ack numbers of the socket.
		// makeSegment(sendSeg, ports[fd-1].src.port, ports[fd-1].dest.port, 0, 0 SYN, NULL, NULL, 0);
		// call IP.send( (uint8_t*)sendSeg, sizeof(segment_t) );
		// ports[fd-1].state = SYN_SENT;
		*/
		return SUCCESS;
		//FIXME: Untested
	}
	
	event void IP.receive(uint8_t *payload, uint8_t len, uint16_t source)
	{
		//TODO
		// Reinterpret the payload as a segment.
		segment_t* rcvdSeg = (segment_t*)payload;
		
		// When we receive a segment, we need a way of handing its data to the socket its intended for.
		// SYN evokes a different response than SYN+ACK, so deMUXing will require hardcoded responses.
		// IVE BEEN HANDED THE ANSWER. ITS A STATE MACHINE BASED ON FLAGS. STOP REINVENTING THE WHEEL.
		
		// The segment will contain which of our intended ports the message is for.
		// The segment will contain the flags we need to respond to.
		// We probably dont need tasks here.
		
		// Respond to SYN by pushing to a Pending Connections Queue.
	}
	
	command uint16_t Transport.write(socket_t fd, uint8_t *buff, uint16_t bufflen)	// Pour data into the socket for us to handle.
	{
		return 0;
	}
	
	command error_t Transport.receive(pack* package)	// Reusing pack struct to represent TCP Segments.
	{
		/*
			Why is this a command? Receive from what?
			IP would signal its own receive event to pass up here, so it can't be from below.
			Since its in the interface, then the param is coming from above or the sides.
			Maybe for actual data transfer, rather than setup/teardown.
		*/
		return FAIL;
	}
	
	command uint16_t Transport.read(socket_t fd, uint8_t *buff, uint16_t bufflen)	// Get data that was sent to us out of the socket.
	{
		return 0;
	}
	
	command error_t Transport.close(socket_t fd) { return 0; }
	command error_t Transport.release(socket_t fd) { return 0; }
}