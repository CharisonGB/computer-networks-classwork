#include "../../includes/socket.h"

module TransportP
{
	provides interface Transport;
	
	uses interface Boot;
	uses interface Random as Random;
	
	uses interface Queue<socket_t> as SocketQ;
	uses interface Hashmap<socket_store_t*> as SocketMap;
	uses interface Hashmap<socket_t> as PortMap; // FIXME: What if two connections have the same srcPort?
	
	uses interface Hashmap<conn_req_t> as PendingConnections; // FIXME: What if two connections have the same srcPort?
	//uses interface Pool<conn_req_t> as ConnQP;
	//uses interface Queue<conn_req_t*> as ConnQ;
	
	uses interface Timer<TMilli> as RTTimer;
	
	uses interface Timer<TMilli> as SendTimer;
	
	uses interface Timer<TMilli> as CloseWait;
	uses interface Timer<TMilli> as TimeWait;
	
	uses interface InternetProtocol as IP;
}

implementation
{
	socket_store_t *sckt, sockets[MAX_NUM_OF_SOCKETS];
	socket_t fd_send, fd_tprt, fd_closer;
	
	segment_t tranportSegment, *tprtSeg = &tranportSegment;
	//segment_t resendSegment, *reSeg = &resendSegment;
	
	uint16_t period = 1000, estimatedRTT;
	
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
	
	task void sendSegmentFrom()
	{
		sckt = call SocketMap.get(fd_tprt);
		
		makeSegment(
			tprtSeg, 
			sckt->src,			// Source port.
			sckt->dest.port,	// Destination port.
			sckt->lastSent,		// Sequence Number to SYNc up.
			sckt->nextExpected, // ACK next expected seq number.
			sckt->flag,
			sckt->effectiveWindow,	// Sliding Window.
			NULL,	// No Data to send.
			0		// No data is 0 bytes long.
		);
		
		call IP.send( (uint8_t*)tprtSeg, sizeof(segment_t), sckt->dest.addr );
		//dbg(TRANSPORT_CHANNEL, "[TRANSPORT::SSF] <%d,%d> sent to node %d\n", TOS_NODE_ID, sckt->src, sckt->dest.addr);
		return;
	}
	
	void receiveSegmentTo(socket_t fd, segment_t* seg)
	{
		uint8_t begin, end, numBytes;
		bool latestSeq, latestExpected, latestAck;
		sckt = call SocketMap.get(fd);
		
		switch(seg->flags)
		{
			case ACK: // Client
				dbg(TRANSPORT_CHANNEL, "[TRANSPORT::RCVD] ACK; <%d,%d>\n", TOS_NODE_ID, sckt->src);
				// Slide the window, and change its size if changed.
				// The next expectd byte was acked.
				
				// What if we get an ack ahead of lastAck but before lastSent?
				// In other words: check in the window for new ack.
				latestAck = FALSE;
				numBytes = 0;
				while(numBytes < sckt->effectiveWindow)
				{
					latestAck = ( (sckt->lastAck+1 + numBytes) == seg->ack-1 ) || latestAck;
					
					if( (sckt->lastAck+1 + numBytes) == sckt->lastSent )
						break;
					numBytes++;
				}
				
				if(latestAck)
				{
					sckt->lastAck = seg->ack-1;
					sckt->effectiveWindow = seg->advertWindow;
				}
				
				dbg(TRANSPORT_CHANNEL, "[TRANSPORT::RCVD] <%d,%d> got ack for byte %d\n", TOS_NODE_ID, sckt->src, sckt->lastAck);
				dbg(TRANSPORT_CHANNEL, "[TRANSPORT::RCVD] <%d,%d> got window ad for %d bytes\n", TOS_NODE_ID, sckt->src, sckt->effectiveWindow);
				
			return;
			
			default: // Server
				dbg(TRANSPORT_CHANNEL, "[TRANSPORT::RCVD] DATA; <%d,%d>: %s\n", TOS_NODE_ID, sckt->src, seg->payload);
				// Copy the data into the rcvdBuff:
				// Check that we wont overflow past lastRead.
				// The number of bytes can't be bigger than the window.
				// The seq can't surpass the lastRead.
				
				// Step backwards from lastRcvd.
				// If we hit seq, lastRcvd is further along and this is a resend.
				latestSeq = TRUE;
				latestExpected = FALSE;
				numBytes = 0;
				while(numBytes < seg->len)
				{
					latestSeq = !( (sckt->lastRcvd - numBytes) == seg->seq ) && latestSeq;
					latestExpected = ( (seg->seq - numBytes) == sckt->nextExpected ) || latestExpected;
					numBytes++;
				}
				
				begin = (seg->seq - seg->len)+1 % SOCKET_BUFFER_SIZE;
				end = sckt->lastRead % SOCKET_BUFFER_SIZE;
				numBytes = 0;
				while(numBytes < seg->len) // Read in only len many bytes.
				{
					if(begin == end) // Did we hit lastRead?
						break;
					
					// Update lastRcvd to be the seq of the byte we're copying.
					// Allows lastRcvd to move backwards!!!! WRONG AND BAD
					if(latestSeq)
						sckt->lastRcvd = ((seg->seq - seg->len)+1 + numBytes);
					
					sckt->rcvdBuff[begin++] = seg->payload[numBytes++];
					//dbg(TRANSPORT_CHANNEL, "[TRANSPORT::RCVD] <%d,%d> receiving byte %d: %d <- %d\n", TOS_NODE_ID, sckt->src, ((seg->seq - seg->len)+1 + numBytes)-1, sckt->rcvdBuff[begin-1], seg->payload[numBytes-1]);
					
					// Update the window.
					// Shouldn't keep crushing the window if we're getting a resend.
					if(sckt->effectiveWindow > 0)
						sckt->effectiveWindow--;
				}
				dbg(TRANSPORT_CHANNEL, "[TRANSPORT::RCVD] <%d,%d> received %d bytes\n", TOS_NODE_ID, sckt->src, numBytes);
				dbg(TRANSPORT_CHANNEL, "[TRANSPORT::RCVD] <%d,%d> lastRcvd=%d, nextExpected=%d \n", TOS_NODE_ID, sckt->src, sckt->lastRcvd, sckt->nextExpected);
				
				// The effectiveWindow starts after the lastRcvd
				// Ends at wrap around to last read
				begin = sckt->lastRcvd+1 % SOCKET_BUFFER_SIZE;
				end = sckt->lastRead % SOCKET_BUFFER_SIZE;
				numBytes = 0;
				while(numBytes < SOCKET_BUFFER_SIZE)
				{	
					if(begin == end) // Did we hit lastRead?
						break;
					begin++;
					numBytes++;
				}
				sckt->effectiveWindow = numBytes;
				dbg(TRANSPORT_CHANNEL, "[TRANSPORT::RCVD] <%d,%d> effectiveWindow=%d \n", TOS_NODE_ID, sckt->src, sckt->effectiveWindow);
				
				// Only ACK if we got in-order data, and only up to lastRcvd.
				if(latestExpected)
				{
					sckt->nextExpected = sckt->lastRcvd + 1;
					dbg(TRANSPORT_CHANNEL, "[TRANSPORT::RCVD] <%d,%d> nextExpected=%d sckt->lastRcvd+1=%d\n", TOS_NODE_ID, sckt->src, sckt->nextExpected, sckt->lastRcvd + 1);
					
				}
				
				sckt->flag = ACK;
				dbg(TRANSPORT_CHANNEL, "[TRANSPORT::RCVD] <%d,%d> ACKing nextExpected=%d \n", TOS_NODE_ID, sckt->src, sckt->nextExpected);
				fd_tprt = fd;
				post sendSegmentFrom();
				
			return;
		}
		
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
			dbg(TRANSPORT_CHANNEL, "[TRANSPORT::BIND] FAIL; %d couldn\'t bind to a new socket.\n", TOS_NODE_ID);
			return FAIL;
		}
		
		sckt = call SocketMap.get(fd);
		sckt->src = addr->port;
		call PortMap.insert(sckt->src, fd);
		// We know our address, so just add the source port number to this socket.
		//addr->addr = TOS_NODE_ID; // Redundant. Node ID stands-in for IP address.
		
		dbg(TRANSPORT_CHANNEL, "[TRANSPORT::BIND] SUCCESS; <%d,%d> bound to a new socket.\n", TOS_NODE_ID, sckt->src);
		return SUCCESS;
	}
	
	command error_t Transport.listen(socket_t fd)
	{
		// The socket at fd is listening for connections.
		
		// Make sure that fd is valid and actually bound to a socket. If not, report an err.
		if( fd == NULL || !call SocketMap.contains(fd) )
		{
			dbg(TRANSPORT_CHANNEL, "[TRANSPORT::LISTEN] FAIL; <%d,?> NULL or Unbound file descriptor.\n", TOS_NODE_ID);
			return FAIL;
		}
		
		// Move fd to LISTEN.
		sckt = call SocketMap.get(fd);
		sckt->state = LISTEN;
		dbg(TRANSPORT_CHANNEL, "[TRANSPORT::LISTEN] SUCCESS; <%d,%d> is listening.\n", TOS_NODE_ID, sckt->src);
		
		return SUCCESS;
	}
	
	/*conn_req_t* searchPendingConnections(uint8_t acceptingPort)
	{
		uint8_t i;
		
		while(i < call ConnQ.size() && !call ConnQ.empty())
		{
			
		}
		
		return NULL;
	}*/
	
	command socket_t Transport.accept(socket_t fd)
	{
		// Queue connection requests from IP.receive until this called to handle them.
		// Passive open.
		// Accept a connection attempt at listening socket fd.
		conn_req_t pendingConn;
		
		if( fd == NULL || !call SocketMap.contains(fd) )
		{
			dbg(TRANSPORT_CHANNEL, "[TRANSPORT::ACCEPT] FAIL; <%d,?> NULL or Unbound file descriptor.\n", TOS_NODE_ID);
			return NULL;
		}
		
		sckt = call SocketMap.get(fd);
		// Check that socket fd is listening. If not, return NULL.
		if( sckt->state != LISTEN )
		{
			dbg(TRANSPORT_CHANNEL, "[TRANSPORT::ACCEPT] FAIL; <%d,%d> isn\'t listening.\n", TOS_NODE_ID, sckt->src);
			return NULL;
		}
		
		// Check for a pending connection for this socket fd.
		if( !call PendingConnections.contains(sckt->src) )
		{
			dbg(TRANSPORT_CHANNEL, "[TRANSPORT::ACCEPT] FAIL; <%d,%d> has no pending connection requests.\n", TOS_NODE_ID, sckt->src);
			return NULL;
		}
		
		pendingConn = (call PendingConnections.get(sckt->src));
		
		// Update socket fd in response to the SYN.
		sckt->flag = SYN+ACK;
		sckt->state = SYN_RCVD;
		sckt->dest.port = pendingConn.srcPort;
		sckt->dest.addr = pendingConn.src;
		sckt->lastSent = (call Random.rand16() % 256);
		sckt->lastRcvd = pendingConn.seq;
		sckt->nextExpected = pendingConn.seq+1;
		
		fd_tprt = fd;
		post sendSegmentFrom();
		dbg(TRANSPORT_CHANNEL, "[TRANSPORT::ACCEPT] SUCCESS; <%d,%d> sent SYN+ACK\n", TOS_NODE_ID, sckt->src);
		
		call RTTimer.startOneShot(period);
		estimatedRTT = call RTTimer.getNow();
		
		call PendingConnections.remove(sckt->src);
		
		return fd;
	}
	
	command error_t Transport.connect(socket_t fd, socket_addr_t * addr)
	{
		// Active open a connection to server at addr through socket fd.
		
		// Can't connect on a NULL socket.
		if( fd == NULL || !call SocketMap.contains(fd) )
		{
			dbg(TRANSPORT_CHANNEL, "[TRANSPORT::CONNECT] FAIL; <%d,?> NULL or Unbound file descriptor.\n", TOS_NODE_ID);
			return FAIL;
		}
		
		sckt = call SocketMap.get(fd);
		// Set source and destination fields.
		// Assumes fd is bound already.
		//(call SocketMap.get(fd))->src = (call Random.rand16() % 256);
		call PortMap.insert( sckt->src, fd );
		
		sckt->dest = *addr;
		sckt->flag = SYN;
		sckt->lastSent = (call Random.rand16() % 256);
		sckt->nextExpected = NULL;
		
		fd_tprt = fd;
		post sendSegmentFrom();
		dbg(TRANSPORT_CHANNEL, "[TRANSPORT::CONNECT] SUCCESS; <%d,%d> sent SYN\n", TOS_NODE_ID, sckt->src);
		
		sckt->state = SYN_SENT;
		
		// Start the RTT estimation;
		call RTTimer.startOneShot(period);
		estimatedRTT = call RTTimer.getNow();
		
		return SUCCESS;
	}
	
	event void RTTimer.fired()
	{
		// Timer wrapped around. Preserve previous RTT and restart the clock.
		estimatedRTT += period;
		call RTTimer.startOneShot(period);
	}
	
	bool setup(socket_t fd, segment_t* seg, uint16_t source)
	{
		conn_req_t pendingConn;
		sckt = call SocketMap.get(fd);
		
		switch(seg->flags)
		{
			case SYN: // Server
				if(sckt->state != LISTEN)
				{
					dbg(TRANSPORT_CHANNEL, "[TRANSPORT::SETUP] REJECTION; <%d,%d> isn\'t listening.\n", TOS_NODE_ID, sckt->src);
					return FALSE;
				}
				
				pendingConn.src = source;
				pendingConn.srcPort = seg->src;
				pendingConn.destPort = seg->dest;
				pendingConn.seq = seg->seq;
				call PendingConnections.insert(pendingConn.destPort, pendingConn);
			return TRUE;
			
			case ACK: // Server
				if(sckt->state != SYN_RCVD)
				{
					//dbg(TRANSPORT_CHANNEL, "[TRANSPORT::SETUP] REJECTION; <%d,%d> isn\'t expecting an ACK.\n", TOS_NODE_ID, sckt->src);
					return FALSE;
				}
				
			// Move to ESTABLISHED. Update the socket.	
				sckt->state = ESTABLISHED;
				
			// Send Buffer Init
				sckt->lastWritten = sckt->lastSent;
				sckt->lastAck = seg->ack;
				
			// Receive Buffer Init
				sckt->lastRcvd = seg->seq;
				sckt->nextExpected = seg->seq+1;
				sckt->lastRead = sckt->lastRcvd;
				sckt->effectiveWindow = SOCKET_BUFFER_SIZE; // Get ready for data transfer.
				
				dbg(TRANSPORT_CHANNEL, "[TRANSPORT::SETUP] ESTABLISHED; <%d,%d>\n", TOS_NODE_ID, sckt->src);
			return TRUE;
			
			case SYN+ACK: //Client
				if(sckt->state != SYN_SENT)
				{
					dbg(TRANSPORT_CHANNEL, "[TRANSPORT::SETUP] REJECTION; <%d,%d> isn\'t expecting a SYN+ACK.\n", TOS_NODE_ID, sckt->src);
					return FALSE;
				}
				
			// Move to ESTABLISHED. Update the socket.
				sckt->flag = ACK;
				sckt->state = ESTABLISHED;
				sckt->RTT = period;
				
			// Send Buffer Init
				sckt->lastAck = seg->ack;
				sckt->lastSent++;
				sckt->lastWritten = sckt->lastSent;
				sckt->effectiveWindow = SOCKET_BUFFER_SIZE;
			
			// Receive Buffer Init
				sckt->lastRcvd = seg->seq;
				sckt->nextExpected = seg->seq+1;
				
				fd_tprt = fd;
				post sendSegmentFrom();
				dbg(TRANSPORT_CHANNEL, "[TRANSPORT::SETUP] ESTABLISHED; <%d,%d> sent ACK\n", TOS_NODE_ID, sckt->src);
			return TRUE;
			
			default:
			return FALSE;
		}
	}
	
	bool teardown(socket_t fd, segment_t* seg)
	{
		sckt = call SocketMap.get(fd);
		
		switch(seg->flags)
		{
			case ACK:
				switch(sckt->state)
				{
					case FIN_WAIT_1:
						sckt->state = FIN_WAIT_2;
						sckt->nextExpected = seg->seq+1;
						
						dbg(TRANSPORT_CHANNEL, "[TRANSPORT::TEARDOWN] CLOSING; <%d,%d> awaiting reciprocal FIN\n", TOS_NODE_ID, sckt->src);
					return TRUE;
					
					case LAST_ACK:
						// The other side is timing out their connection. Close our side.
						sckt->state = CLOSED;
						dbg(TRANSPORT_CHANNEL, "[TRANSPORT::TEARDOWN] CLOSED; <%d,%d>\n", TOS_NODE_ID, sckt->src);
						
						call RTTimer.stop();
						// FIXME
						// Clear the buffers?
						// Not a release, so keep all address and port data until overriden.
					return TRUE;
					
					default:
					break;
				}
			break;
			
			case FIN:
				switch(sckt->state)
				{
					case ESTABLISHED:
						sckt->state = CLOSE_WAIT;
						// Should timeout after waiting >RTT.
						fd_closer = fd;
						call CloseWait.startOneShot(sckt->RTT * 2);
						dbg(TRANSPORT_CHANNEL, "[TRANSPORT::TEARDOWN] CLOSING; <%d,%d> waiting to reciprocate FIN\n", TOS_NODE_ID, sckt->src);
						// Other side wants to close. Send an ACK and wait.
					break;
					
					case FIN_WAIT_2:
						sckt->state = TIME_WAIT;
						// Should timeout after waiting >RTT.
						fd_closer = fd;
						call TimeWait.startOneShot(sckt->RTT * 2);
						dbg(TRANSPORT_CHANNEL, "[TRANSPORT::TEARDOWN] CLOSING; <%d,%d> timing out.\n", TOS_NODE_ID, sckt->src);
						// Send an ACK to let the other side know its ok for them to fully close.
						// We'll close on timeout.
					break;
					
					default:
						dbg(TRANSPORT_CHANNEL, "[TRANSPORT::TEARDOWN] REJECTION; <%d,%d> isn\'t expecting a FIN.\n", TOS_NODE_ID, sckt->src);
					return FALSE;
				}
				
				// Prepare an ACK and send it.
				sckt->flag = ACK;
				sckt->lastSent++;
				sckt->nextExpected = seg->seq+1;
				
				fd_tprt = fd;
				post sendSegmentFrom();
				dbg(TRANSPORT_CHANNEL, "[TRANSPORT::TEARDOWN] CLOSING; <%d,%d> sent ACK\n", TOS_NODE_ID, sckt->src);
			return TRUE;
			
			default:
			return FALSE;
		}
		
		return FALSE;
	}
	
	task void sendWindow()
	{
		uint8_t begin, end, numBytes;
		sckt = call SocketMap.get(fd_send);
		// Assuming sockets that want to send are set.
		// Sliding Window compliance should happen here.
		// This will conditionally advance the lastSent pointer.
		// Lastsent can be no greater than lastAck + window
		
		// Load the whole window.
		// While loop can deal with wrapping indices.
		dbg(TRANSPORT_CHANNEL, "[TRANSPORT::SEND] <%d,%d> lastAck=%d lastWritten=%d\n", TOS_NODE_ID, sckt->src, sckt->lastAck, sckt->lastWritten);
		begin = (sckt->lastAck+1) % SOCKET_BUFFER_SIZE;
		end = sckt->lastWritten % SOCKET_BUFFER_SIZE;
		numBytes = 0;
		while(numBytes < sckt->effectiveWindow && numBytes < TRANSPORT_MAX_PAYLOAD)
		{
			if(begin == end) // Did we hit lastWritten?
				break;
			
			//dbg(TRANSPORT_CHANNEL, "[TRANSPORT::SEND] <%d,%d> sending byte %d: %d\n", TOS_NODE_ID, sckt->src, sckt->lastSent, sckt->sendBuff[begin]);
			tprtSeg->payload[numBytes++] = sckt->sendBuff[begin++];
			sckt->lastSent = sckt->lastAck + numBytes;
		}
		
		dbg(TRANSPORT_CHANNEL, "[TRANSPORT::SEND] <%d,%d> lastSent byte %d.\n", TOS_NODE_ID, sckt->src, sckt->lastSent);
		
		// Fill a segment and send.
		makeSegment(
			tprtSeg, 
			sckt->src,			// Source port.
			sckt->dest.port,	// Destination port.
			sckt->lastSent,		// Sequence Number.
			NULL,				// We're sending data, not ACKing.
			NONE,				// No flags.
			NULL,				// Sender doesnt advertise window.
			tprtSeg->payload,	// We're sending what we just loaded.
			numBytes			// Number of bytes we just loaded.
		);
		
		call IP.send( (uint8_t*)tprtSeg, sizeof(segment_t), sckt->dest.addr );
		dbg(TRANSPORT_CHANNEL, "[TRANSPORT::SEND] <%d,%d> sent %d bytes: %s\n", TOS_NODE_ID, sckt->src, numBytes, tprtSeg->payload);
	}
	
	event void SendTimer.fired()
	{
		uint8_t begin, end, numBytes;
		socket_t fd;
		uint8_t k = MAX_NUM_OF_SOCKETS;
		uint32_t* keys = call SocketMap.getKeys();
		
		
		// Rotate though all established sockets.
		while(k-- > 0)
		{
			// Get an established socket.
			fd = keys[k];
			if(fd == NULL)
				continue;
			
			//*sckt = sockets[k]; // Breaks bindings! DO NOT ACCESS SOCKETS W/O SocketMap
			sckt = call SocketMap.get(fd);
			if(sckt->state != ESTABLISHED)
				continue;
			
			fd_send = fd;
			post sendWindow();
		}
	}
	
	event void IP.receive(uint8_t *payload, uint8_t len, uint16_t source)
	{
		// Reinterpret the payload as a segment.
		segment_t* rcvdSeg = (segment_t*)payload;
		// Use a hashmap to get from port number to socket. Get a pointer to the socket.
		socket_t fd = call PortMap.get( rcvdSeg->dest ); // Could return junk rather than NULL!
		
		// Validate the fd.
		if( !call SocketMap.contains(fd) )
		{
			dbg(TRANSPORT_CHANNEL, "[TRANSPORT] FAIL; <%d,%d> is Unbound.\n", TOS_NODE_ID, rcvdSeg->dest);
			return;
		}
		sckt = call SocketMap.get(fd);
		dbg(TRANSPORT_CHANNEL, "[TRANSPORT] segment for <%d,%d>: %s\n", TOS_NODE_ID, rcvdSeg->dest, rcvdSeg->payload);
		// Processing flags; first pass.
		switch(rcvdSeg->flags)
		{
			case SYN:
				dbg(TRANSPORT_CHANNEL, "[TRANSPORT] SYN for <%d,%d>\n", TOS_NODE_ID, rcvdSeg->dest);
			break;
			
			case ACK:
				dbg(TRANSPORT_CHANNEL, "[TRANSPORT] ACK for <%d,%d>\n", TOS_NODE_ID, rcvdSeg->dest);
				
				// TEST ONLY
				//receiveSegmentTo(fd, rcvdSeg);
				
				sckt->RTT = estimatedRTT + call RTTimer.getNow();
				
				call RTTimer.startOneShot(period);
				estimatedRTT = call RTTimer.getNow();
			break;
			
			case SYN+ACK:
				dbg(TRANSPORT_CHANNEL, "[TRANSPORT] SYN+ACK for <%d,%d>\n", TOS_NODE_ID, rcvdSeg->dest);
				
				sckt->RTT = estimatedRTT + call RTTimer.getNow();
				
				call RTTimer.startOneShot(period);
				estimatedRTT = call RTTimer.getNow();
			break;
			
			case FIN:
				dbg(TRANSPORT_CHANNEL, "[TRANSPORT] FIN for <%d,%d>\n", TOS_NODE_ID, rcvdSeg->dest);
			break;
			
			default:
			break;
		}
		
		// Second pass of processing the segment.
		if(!setup(fd, rcvdSeg, source) && !teardown(fd, rcvdSeg))
		{
			receiveSegmentTo(fd, rcvdSeg);
		}
	}
	
	command uint16_t Transport.write(socket_t fd, uint8_t *buff, uint16_t bufflen)	// Pour data into the socket for us to handle.
	{
		uint8_t begin, end, numBytes;
		
		if( fd == NULL || !call SocketMap.contains(fd) )
		{
			dbg(TRANSPORT_CHANNEL, "[TRANSPORT::WRITE] FAIL; <%d,?> NULL or Unbound file descriptor.\n", TOS_NODE_ID);
			return FAIL;
		}
		sckt = call SocketMap.get(fd);
		
		if(sckt->state != ESTABLISHED)
		{
			dbg(TRANSPORT_CHANNEL, "[TRANSPORT::WRITE] FAIL; <%d,%d> wasn't eastablished.\n", TOS_NODE_ID, sckt->src);
			return FAIL;
		}
		
		// ASSUMPTION: LastWritten is properly initialized to the lastSent, which happens when we get the SYN+ACK
		// lastWritten starts at the initial seq and leads.
		// lastSent follows this.
		// lastWritten can wrap up to lastAck.
		// What will get sent depends on the window.
		
		dbg(TRANSPORT_CHANNEL, "[TRANSPORT::WRITE] <%d,%d> lastWritten=%d, lastAck=%d\n", TOS_NODE_ID, sckt->src, sckt->lastWritten, sckt->lastAck);
		
		begin = sckt->lastWritten+1 % SOCKET_BUFFER_SIZE;
		end = sckt->lastAck % SOCKET_BUFFER_SIZE;
		numBytes = 0;
		while(numBytes < bufflen)
		{
			if(begin == end) // Did we hit lastAck?
			{
				dbg(TRANSPORT_CHANNEL, "[TRANSPORT::WRITE] <%d,%d> wrote up to lastAck!\n", TOS_NODE_ID, sckt->src);
				break;
			}
			// Copy the byte into the buffer.
			sckt->sendBuff[begin++] = buff[numBytes++];
			//Copies correctly!
			sckt->lastWritten++;
			//dbg(TRANSPORT_CHANNEL, "[TRANSPORT::WRITE] <%d,%d> writing byte %d/%d: %d\n", TOS_NODE_ID, sckt->src, sckt->lastWritten, begin-1, sckt->sendBuff[begin-1]);
		}
		
		dbg(TRANSPORT_CHANNEL, "[TRANSPORT::WRITE] <%d,%d> wrote %d bytes of %s\n", TOS_NODE_ID, sckt->src, numBytes, buff);
		
		// We have something to send, so start the clock.
		if( !call SendTimer.isRunning() )
			call SendTimer.startPeriodic(4*period);
		
		return numBytes;
	}
	
	command error_t Transport.receive(pack* package)	// Reusing pack struct to represent TCP Segments.
	{

		return FAIL;
	}
	
	command uint16_t Transport.read(socket_t fd, uint8_t *buff, uint16_t bufflen)	// Get data that was sent to us out of the socket.
	{
		uint8_t begin, end, numBytes;
		
		if( fd == NULL || !call SocketMap.contains(fd) )
		{
			dbg(TRANSPORT_CHANNEL, "[TRANSPORT::READ] FAIL; <%d,?> NULL or Unbound file descriptor.\n", TOS_NODE_ID);
			return FAIL;
		}
		sckt = call SocketMap.get(fd);
		
		// Pulling from the receive buffer.
		// Advances lastRead pointer.
		// lastRead must be strictly behind nextExpected.
		
		begin = sckt->lastRead+1 % SOCKET_BUFFER_SIZE;
		end = sckt->nextExpected % SOCKET_BUFFER_SIZE;
		numBytes = 0;
		while(numBytes < bufflen)
		{
			if(begin == end) // Did we hit nextExpected?
				break;
			
			buff[numBytes++] = sckt->rcvdBuff[begin++];
			sckt->lastRead++;
			//dbg(TRANSPORT_CHANNEL, "[TRANSPORT::READ] <%d,%d> read byte %d: %d\n", TOS_NODE_ID, sckt->src, sckt->lastRead, buff[numBytes-1]);
			
			// We've read data, so the window can grow.
			if(sckt->effectiveWindow < SOCKET_BUFFER_SIZE)
				sckt->effectiveWindow++;
		}
		
		dbg(TRANSPORT_CHANNEL, "[TRANSPORT::READ] <%d,%d> read %d bytes of %s\n", TOS_NODE_ID, sckt->src, numBytes, buff);
		
		return numBytes;
	}
	
	command socket_t Transport.getConn(uint8_t source, uint8_t srcPort, uint8_t destination, uint8_t destPort)
	{
		socket_t fd;
		
		if(!call PortMap.contains(srcPort))
			return NULL;
		
		fd = call PortMap.get(srcPort);
		sckt = call SocketMap.get(fd);
		
		if(sckt->dest.addr == destination && sckt->dest.port == destPort)
			return fd;
		
		return NULL;
	}
	
	command error_t Transport.close(socket_t fd)
	{
		// Validate fd.
		if( fd == NULL || !call SocketMap.contains(fd) )
		{
			dbg(TRANSPORT_CHANNEL, "[TRANSPORT::CLOSE] FAIL; <%d,?> NULL or Unbound file descriptor.\n", TOS_NODE_ID);
			return FAIL;
		}
		
		sckt = call SocketMap.get(fd);
		
		// Return FAIL if this connection wasn't established in the first place.
		if(sckt->state != ESTABLISHED)
		{
			dbg(TRANSPORT_CHANNEL, "[TRANSPORT::CLOSE] FAIL; <%d,%d> isn\'t connected.\n", TOS_NODE_ID, sckt->src);
			return FAIL;
		}
		
		// We're initiating the close. Send the first FIN.
		sckt->state = FIN_WAIT_1;
		
		// Prepare a FIN and send it.
		sckt->flag = FIN;
		sckt->lastSent++;
		
		fd_tprt = fd;
		post sendSegmentFrom();
		dbg(TRANSPORT_CHANNEL, "[TRANSPORT::CLOSE] SUCCESS; <%d,%d> sent FIN\n", TOS_NODE_ID, sckt->src);
		
		call RTTimer.startOneShot(period);
		estimatedRTT = call RTTimer.getNow();
		
		return SUCCESS;
	}
	
	event void CloseWait.fired()
	{
		sckt = call SocketMap.get(fd_closer);
		
		if(sckt->state != CLOSE_WAIT)
		{
			dbg(TRANSPORT_CHANNEL, "[TRANSPORT::TEARDOWN] FAIL; <%d,%d> isn\'t connected.\n", TOS_NODE_ID, sckt->src);
			return;
		}
		
		sckt->flag = FIN;
		sckt->state = LAST_ACK;
		sckt->lastSent++;
		
		fd_tprt = fd_closer;
		post sendSegmentFrom();
		dbg(TRANSPORT_CHANNEL, "[TRANSPORT::TEARDOWN] CLOSING; <%d,%d> sent FIN\n", TOS_NODE_ID, sckt->src);
	}
	
	event void TimeWait.fired()
	{
		sckt = call SocketMap.get(fd_closer);
		sckt->state = CLOSED;
		call RTTimer.stop();
		dbg(TRANSPORT_CHANNEL, "[TRANSPORT::TEARDOWN] CLOSED; <%d,%d>\n", TOS_NODE_ID, sckt->src);
		return;
	}
	
	command error_t Transport.release(socket_t fd)
	{
		// Unclear if this is the opposite of bind().
		// Dont jump the gun implementing.
		return 0;
	}
}