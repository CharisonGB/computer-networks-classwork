#include "../../includes/channels.h"
#include "../../includes/packet.h"
#include "../../includes/protocol.h"
#include "../../includes/neighbor.h"

module NeighborDiscoveryP
{
	provides interface NeighborDiscovery;
	
	uses interface Boot;
	uses interface Random;
	uses interface Timer<TMilli> as Periodic;
	
	uses interface SimpleSend as NDSend;
	uses interface Receive as NDReceive;
	
	uses interface Hashmap<NeighborData> as NeighborTable;
}

implementation
{
	uint8_t seqNum = 0;
	
	pack request;
	pack reply;
	
	// Copied makePack from the Skeleton Code
	void makePack(pack *Package, uint16_t src, uint16_t dest, uint16_t TTL, uint16_t protocol, uint16_t seq, uint8_t* payload, uint8_t length);
	
	// Other convenient methods for manipulating the Neighbor Table
	void setNeighbor(NeighborData *neighbor, uint16_t addr, uint16_t lastSent, uint16_t lastRec);
	void neighborReplied(uint16_t addr, uint16_t lastRec);
	void confirmActiveNeighbors(uint16_t lastSent);
	
	task void pingNeighbors()
	{
		pack *req = &request;
		
		//dbg(NEIGHBOR_CHANNEL, "[NEIGHBOR] %d is attempting to broadcast a discovery ping\n", TOS_NODE_ID);
		call NDSend.send(request, AM_BROADCAST_ADDR);
		
		confirmActiveNeighbors(req->seq);
	}
	
	event void Periodic.fired()
	{
		char qPayload[5] = "PING";
		
		makePack(&request, TOS_NODE_ID, AM_BROADCAST_ADDR, 0, PROTOCOL_PING, seqNum++, &qPayload[0], 5);
		post pingNeighbors();
	}
	
	event void Boot.booted()
	{
		//call Periodic.startOneShot( 100 );
		call Periodic.startPeriodic( (call Random.rand16() % 500) + 500 );
	}
	
	task void pingReply()
	{
		pack *rep = &reply;
		
		//dbg(NEIGHBOR_CHANNEL, "[NEIGHBOR] %d is attempting to send a ping reply to %d\n?", TOS_NODE_ID, rep->dest);
		call NDSend.send(reply, rep->dest);
	}
	
	event message_t* NDReceive.receive(message_t* msg, void* payload, uint8_t len)
	{
		if(len == sizeof(pack)) // Is the payload received the size of a pack?
		{
			pack* NDMsg = (pack*)payload; // Interpret the received payload as a pack.
			
			switch(NDMsg->protocol)
			{
				case PROTOCOL_PING: // Ping/PingReply
					//dbg(NEIGHBOR_CHANNEL, "[NEIGHBOR] %d received PING from %d, Sequence: %d\n", TOS_NODE_ID, NDMsg->src, NDMsg->seq); // Output the pack's sender.
					makePack(&reply, TOS_NODE_ID, NDMsg->src, 0, PROTOCOL_PINGREPLY, NDMsg->seq, NDMsg->payload, PACKET_MAX_PAYLOAD_SIZE);
					post pingReply();
					break;
					
				case PROTOCOL_PINGREPLY: // Gather Stats
					neighborReplied(NDMsg->src, NDMsg->seq);
					//dbg(NEIGHBOR_CHANNEL, "[NEIGHBOR] %d received PING REPLY from %d, Sequence: %d\n?", TOS_NODE_ID, NDMsg->src, NDMsg->seq);
					break;
					
				default:
					//dbg(NEIGHBOR_CHANNEL, "[NEIGHBOR] Unrecognized Packet Protocol: %d\n", NDMsg->protocol);
					break;
			}
		
			return msg;
		}
		
		dbg(NEIGHBOR_CHANNEL, "[NEIGHBOR] Received Unknown Packet Type %d\n", len);
		return msg;
	}
   
	command uint16_t NeighborDiscovery.getNeighbors(uint16_t *neighbors)
	{
		uint32_t *activeAddrs;
		uint16_t i;
		
		if( call NeighborTable.isEmpty() )
			return 0;
		
		activeAddrs = call NeighborTable.getKeys();
		
		for (i = 0; i < MAX_NEIGHBOR_TABLE; i++)
		{
			neighbors[i] = activeAddrs[i];
		}
		
		return call NeighborTable.size();
	}
	
	command bool NeighborDiscovery.isNeighbor(uint16_t address)
	{
		if( call NeighborTable.isEmpty() )
			return 0;
		
		return call NeighborTable.contains(address);
	}
	
	// Move to packet header
	void makePack(pack *Package, uint16_t src, uint16_t dest, uint16_t TTL, uint16_t protocol, uint16_t seq, uint8_t* payload, uint8_t length)
	{
		Package->src = src;
		Package->dest = dest;
		Package->TTL = TTL;
		Package->seq = seq;
		Package->protocol = protocol;
		memcpy(Package->payload, payload, length);
	}
	
	void setNeighbor(NeighborData *neighbor, uint16_t addr, uint16_t lastSent, uint16_t lastRec)
	{
		neighbor->address = addr;
		neighbor->sent = lastSent;
		neighbor->received = lastRec;
		neighbor->linkQual = ( (float_t)(lastRec+1) / (float_t)(lastSent+1) ) * 100;
		neighbor->active = (lastSent - lastRec) < INACTIVE_THRESHOLD;
	}
	
	void neighborReplied(uint16_t addr, uint16_t lastRec)
	{
		NeighborData myNeighbor;
		NeighborData *myNbr = &myNeighbor;
		
		if( (! call NeighborTable.isEmpty()) && call NeighborTable.contains(addr) )
		{
			myNeighbor = call NeighborTable.get(addr);	// Copy existing neighbor entry.
			//dbg(NEIGHBOR_CHANNEL, "[NEIGHBOR] Link from %d to %d: lastSent=%d, lastRec=%d\n", TOS_NODE_ID, myNbr->address, addr, myNbr->sent, myNbr->received);
			
			call NeighborTable.remove(addr);			// Remove the existing entry from the table.
		}
		else
		{
			myNbr->sent = lastRec;
			//dbg(NEIGHBOR_CHANNEL, "[NEIGHBOR] Link from %d to %d had no send history: Set lastSent=lastRec=%d\n", TOS_NODE_ID, addr, myNbr->sent);
		}
		
		setNeighbor(myNbr, addr, myNbr->sent, lastRec);
		//dbg(NEIGHBOR_CHANNEL, "[NEIGHBOR] Link from %d to %d: lastSent=%d, lastRec=%d, Qual=%f\n", TOS_NODE_ID, myNbr->address, myNbr->sent, myNbr->received, myNbr->linkQual);
		
		call NeighborTable.insert(addr, myNeighbor);
	}
	
	void confirmActiveNeighbors(uint16_t lastSent)
	{
		NeighborData myNeighbor;
		NeighborData *myNbr = &myNeighbor;
		
		uint32_t *activeAddrs;
		uint16_t numAddrs = call NeighborTable.size();		// Size of address list.
		uint16_t i;
		
		if( call NeighborTable.isEmpty() )
			return;
		
		activeAddrs = call NeighborTable.getKeys();		// Addresses in the Neighbor Table.
		
		for(i = 0; i < numAddrs; i++)
		{
			myNeighbor = call NeighborTable.get( activeAddrs[0] );	// Copy existing neighbor entry.
			call NeighborTable.remove( activeAddrs[0] );			// Remove the existing entry from the table. Next entry moved to index 0 by Hashmap.
			
			setNeighbor(myNbr, myNbr->address, lastSent, myNbr->received);
			
			if(myNbr->active)	// Only restore the updated neighbor if its active after the updated lastSent.
			{
				call NeighborTable.insert(myNbr->address, myNeighbor);
				dbg(NEIGHBOR_CHANNEL, "[NEIGHBOR] %d has neighbor %d: lastSent=%d, lastRec=%d, Qual=%f\n", TOS_NODE_ID, myNbr->address, myNbr->sent, myNbr->received, myNbr->linkQual);
			}
		}
	}
	
	
}