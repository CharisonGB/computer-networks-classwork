#include "../../includes/channels.h"
#include "../../includes/packet.h"
#include "../../includes/neighbor.h"
#include "../../includes/flooding.h"

module FloodingP
{
	provides interface Flooding;
	
	uses interface SimpleSend as FSend;
	uses interface Receive as FReceive;
	
	uses interface Random;
	uses interface Timer<TMilli> as ForwardDelay;
	
	uses interface NeighborDiscovery;
	
	uses interface Hashmap<uint16_t> as SequenceCache; // Stores last seen sequence number keyed by flood source.
}

implementation
{
	uint16_t neighborList[MAX_NEIGHBOR_TABLE];	// ND should really just hand me a const reference to read. FIXME later.
	uint16_t sequenceNumber = 0;
	
	uint8_t* buffer;
	uint8_t bufLen;
	
	pack forwardPackage, *frwdPack = &forwardPackage;			// Dedicated module-scope memory for forwarding Link Layer packets.
	pack receivedPackage, *rcvdPack = &receivedPackage;			// Dedicated module-scope memory for processing Link Layer packets.
	Floodable floodable, *fld = &floodable;						// Dedicated module-scope memory for handling Floodables.
	
	task void forwardToNeighbors()
	{
		uint16_t n = call NeighborDiscovery.getNeighbors(&neighborList);	// Update the neighbor list
		
		//if(n == 0) { dbg(FLOODING_CHANNEL, "[FLOOD] %d tried to forward with no neighbors!\n", TOS_NODE_ID); }
		
		while(n-- > 0)
		{
			if(fld->src == TOS_NODE_ID || neighborList[n] != rcvdPack->src)
			{
				frwdPack->dest = neighborList[n];
				call FSend.send(*frwdPack, frwdPack->dest);
			}
			//else { dbg(FLOODING_CHANNEL, "[FLOOD] %d skipped forwarding back to Dest=%d\n", TOS_NODE_ID, rcvdPack->src); }
		}
	}
	
	event void ForwardDelay.fired()
	{	
		if(bufLen > FLOOD_MAX_PAYLOAD_SIZE)
		{
			makeFloodable(fld, TOS_NODE_ID, buffer, FLOOD_MAX_PAYLOAD_SIZE);
			
			buffer += FLOOD_MAX_PAYLOAD_SIZE;
			bufLen -= FLOOD_MAX_PAYLOAD_SIZE;
			
			call ForwardDelay.startOneShot( (call Random.rand16() % 50) + 50 ); // This creates a loop that better paces out fragments.
		}
		else if(bufLen > 0)
		{
			makeFloodable(fld, TOS_NODE_ID, buffer, bufLen);
		}
		
		makePack(frwdPack, TOS_NODE_ID, NULL, FLOOD_TTL, PROTOCOL_FLOOD, sequenceNumber++, fld, sizeof(Floodable));
		//dbg(FLOODING_CHANNEL, "[FLOOD] FloodSource=%d|TTL=%d|Sequence=%d\n", fld->src, frwdPack->TTL, frwdPack->seq);
		
		post forwardToNeighbors();
	}
	
	command void Flooding.flood(uint8_t* payload, uint8_t len)
	{
		buffer = payload; // When this returns, will payload still point to the correct data?
		bufLen = len;
		
		// Starts a loop to fragment oversized payloads.
		//call ForwardDelay.startOneShot( (call Random.rand16() % 50) + 50 );

		makeFloodable(fld, TOS_NODE_ID, buffer, bufLen);
		
		makePack(frwdPack, TOS_NODE_ID, NULL, FLOOD_TTL, PROTOCOL_FLOOD, sequenceNumber++, fld, sizeof(Floodable));
		//dbg(FLOODING_CHANNEL, "[FLOOD] FloodSource=%d|TTL=%d|Sequence=%d\n", fld->src, frwdPack->TTL, frwdPack->seq);
		
		post forwardToNeighbors();
	}
	
	event message_t* FReceive.receive(message_t* msg, void* payload, uint8_t len)
	{
		if(len == sizeof(pack)) // Is the payload received the size of a pack?
		{
			*rcvdPack = *( (pack*)payload ); // Interpret the received payload as a pack and put it in memory that the whole module can access.
			
			switch(rcvdPack->protocol)
			{
				case PROTOCOL_FLOOD: // Is it a flood packet?
					*fld = *( (Floodable*)rcvdPack->payload );	// Read the Link Layer payload as a flood packet.
					
					//dbg(FLOODING_CHANNEL, "[FLOOD] %d Received: Source=%d|FloodSource=%d|TTL=%d|Sequence=%d|Protocol=%d\n", TOS_NODE_ID, rcvdPack->src, fld->src, rcvdPack->TTL, rcvdPack->seq, rcvdPack->protocol);
					
					if(rcvdPack->seq >= call SequenceCache.get(fld->src) && (rcvdPack->TTL)-- > 0)	// Check TTL here since its in the Link Layer packs anyway.
					{
						call SequenceCache.insert(fld->src, rcvdPack->seq + 1);	// Update the seqCache.
						
						signal Flooding.readFlood(fld->src, &fld->payload, FLOOD_MAX_PAYLOAD_SIZE); // Pass to interface.
						
						makePack(frwdPack, TOS_NODE_ID, NULL, rcvdPack->TTL, PROTOCOL_FLOOD, rcvdPack->seq, rcvdPack->payload, len);
						//dbg(FLOODING_CHANNEL, "[FLOOD] %d Forwarding: FloodSource=%d|TTL=%d|Sequence=%d\n", frwdPack->src, fld->src, frwdPack->TTL, frwdPack->seq);
						post forwardToNeighbors(); // All good, forward to neighbors.
					}
					
					break;
					
				default:
					//dbg(FLOODING_CHANNEL, "[FLOOD] Unrecognized Packet Protocol: %d\n", package->protocol);
					break;
			}
		
			return msg;
		}
		
		dbg(FLOODING_CHANNEL, "[FLOOD] Received Unknown Packet Type %d\n", len);
		return msg;
	}
}