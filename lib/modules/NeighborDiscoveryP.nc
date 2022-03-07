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
	
	uses interface Hashmap<Neighbor> as NeighborTable;
}

implementation
{
	uint8_t sequenceNumber = 0;
	
	pack request, *req = &request;	// Dedicated module-scope memory for preparing ping requests.
	pack reply, *rep = &reply;		// Dedicated module-scope memory for preparing ping replies.
	
	Neighbor NTEntry, *entry = &NTEntry;	// Dedicated module-scope memory for manipulating NeighborTable entries.
	
	// Convenient methods for manipulating the Neighbor Table
	void updateNeighborReplies(pack* package);
	void updateNeighborRequests(uint16_t lastPingSent);
	
	task void pingNeighbors()
	{
		//dbg(NEIGHBOR_CHANNEL, "[NEIGHBOR] %d is broadcasting a discovery ping\n", TOS_NODE_ID);
		call NDSend.send(request, AM_BROADCAST_ADDR);
		updateNeighborRequests(req->seq);
	}
	
	event void Periodic.fired()
	{
		makePack(&request, TOS_NODE_ID, AM_BROADCAST_ADDR, 0, PROTOCOL_PING, sequenceNumber++, NULL, 0);
		post pingNeighbors();
	}
	
	event void Boot.booted()
	{
		//call Periodic.startOneShot( 100 );
		call Periodic.startPeriodic( (call Random.rand16() % 500) + 500 );
	}
	
	task void pingReply()
	{
		//dbg(NEIGHBOR_CHANNEL, "[NEIGHBOR] %d is sending a ping reply to %d\n", TOS_NODE_ID, rep->dest);
		call NDSend.send(reply, rep->dest);
	}
	
	event message_t* NDReceive.receive(message_t* msg, void* payload, uint8_t len)
	{
		if(len == sizeof(pack)) // Is the payload received the size of a pack?
		{
			pack* package = (pack*)payload; // Interpret the received payload as a pack.
			
			switch(package->protocol)
			{
				case PROTOCOL_PING: // Ping/PingReply
					//dbg(NEIGHBOR_CHANNEL, "[NEIGHBOR] %d received PING from %d, Sequence: %d\n", TOS_NODE_ID, package->src, package->seq); // Output the pack's sender.
					makePack(rep, TOS_NODE_ID, package->src, 0, PROTOCOL_PINGREPLY, package->seq, NULL, 0);
					post pingReply();
					break;
					
				case PROTOCOL_PINGREPLY: // Gather Stats
					updateNeighborReplies(package);
					//dbg(NEIGHBOR_CHANNEL, "[NEIGHBOR] %d received PING REPLY from %d, Sequence: %d\n?", TOS_NODE_ID, package->src, package->seq);
					break;
					
				default:
					//dbg(NEIGHBOR_CHANNEL, "[NEIGHBOR] Unrecognized Packet Protocol: %d\n", package->protocol);
					break;
			}
		
			return msg;
		}
		
		dbg(NEIGHBOR_CHANNEL, "[NEIGHBOR] Received Unknown Packet Type %d\n", len);
		return msg;
	}
	
	command bool NeighborDiscovery.isNeighbor(uint16_t address)
	{
		return call NeighborTable.contains(address);
	}
	
	// FIXME: Just pass a const reference to the key list of neighbors.
	command uint16_t NeighborDiscovery.getNeighbors(uint16_t *neighbors)
	{
		uint32_t* addresses;
		uint16_t n = call NeighborTable.size();
		
		if(n == 0)
			return n;
		
		addresses = call NeighborTable.getKeys();
		
		while(n-- > 0)
			neighbors[n] = addresses[n];
		
		return call NeighborTable.size();
	}
	
	command uint16_t NeighborDiscovery.numNeighbors()
	{
		return call NeighborTable.size();
	}
	
	command void NeighborDiscovery.printNeighborTable()
	{
		uint32_t* addresses = call NeighborTable.getKeys();
		uint16_t n = call NeighborTable.size();
		
		const char* title = "Neighbors:";
		char str[n*2], *row = &str;
		
		sprintf(row, "%s", "\0");
		while(n-- > 0)
			sprintf(row, "%s %d", row, addresses[n]);
		
		dbg(NEIGHBOR_CHANNEL, "[NEIGHBOR] %s%s\n", title, row);
	}
	
	void updateNeighborReplies(pack* package)
	{
		if( call NeighborTable.contains(package->src) )
			*entry = call NeighborTable.get(package->src);
		else
			entry->sent = package->seq;
		
		setNeighbor(entry, package->src, entry->sent, package->seq);
		call NeighborTable.insert(entry->addr, *entry);
	}
	
	void updateNeighborRequests(uint16_t lastPingSent)
	{
		uint32_t* addresses;
		uint16_t n = call NeighborTable.size();
		
		while(n-- > 0)
		{
			*entry = call NeighborTable.get( addresses[n] );	// Copy existing neighbor entry.
			
			if( !entry->active )
			{
				call NeighborTable.remove( addresses[n] );	// Remove this neighbor if it has crossed the inactive threshold.
				break;
			}
			
			setNeighbor(entry, entry->addr, lastPingSent, entry->rcvd);	// Update last sequence number sent to this neighbor.
			call NeighborTable.insert(entry->addr, *entry);
			//dbg(NEIGHBOR_CHANNEL, "[NEIGHBOR] %d has neighbor %d: lastSent=%d, lastRec=%d, Qual=%f\n", TOS_NODE_ID, entry->addr, entry->sent, entry->rcvd, entry->linkQual);
		}
	}
}