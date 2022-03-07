#include "../../includes/channels.h"
#include "../../includes/packet.h"
#include "../../includes/neighbor.h"
#include "../../includes/flooding.h"

module FloodingP
{
	provides interface Flooding;
	
	uses interface SimpleSend as FSend;
	uses interface Receive as FReceive;
	
	uses interface NeighborDiscovery;
}

// Building flood on the packet header.
// Might need to change this to build on AM_Packs to make our own packet type.

implementation
{
	pack forward;
	flood_t floodMsg;
	
	uint16_t neighborList[MAX_NEIGHBOR_TABLE]; // I think this ought to be statically allocated.
	uint16_t seqNum = 0;
	uint16_t seqCache;
	uint16_t lastHop = 0;
	
	// Copied makePack from the Skeleton Code
	void makePack(pack *Package, uint16_t src, uint16_t dest, uint16_t TTL, uint16_t protocol, uint16_t seq, uint8_t* payload, uint8_t length);
	
	// Other convenient methods
	uint16_t getFloodSource(pack *floodPacket);
	
	task void forwardToNeighbors()
	{
		uint16_t numNeighbors = call NeighborDiscovery.getNeighbors(&neighborList);		// Update the neighbor list
		uint16_t i;
		pack *fwd;
		fwd = &forward;
		
		//dbg(FLOODING_CHANNEL, "[FLOOD] %d is trying to forward!\n", TOS_NODE_ID);
		
		if(numNeighbors != 0)
		{
			for(i = 0; i < numNeighbors; i++)
			{
				if (neighborList[i] != lastHop) // By the time we get here, the last node this packet was sent from is in link layer dest.
				{
					fwd->dest = neighborList[i];
					seqCache = fwd->seq + 1;
					dbg(FLOODING_CHANNEL, "[FLOOD] %d Forwarding: Dest=%d|FloodSource=%d|TTL=%d|Sequence=%d\n", fwd->src, fwd->dest, getFloodSource(fwd), fwd->TTL, fwd->seq);
					call FSend.send(forward, neighborList[i]);
				}
				else
					dbg(FLOODING_CHANNEL, "[FLOOD] %d skipped forwarding back to Dest=%d\n", TOS_NODE_ID, lastHop);
			}
		}
		else
		{
			dbg(FLOODING_CHANNEL, "[FLOOD] %d tried to forward with no neighbors!\n", TOS_NODE_ID);
		}
		
		return;
	}
	
	command void Flooding.flood(uint8_t *payload, uint8_t len)
	{
		flood_t *FMsg = &floodMsg;
		
		if(len > FLOOD_MAX_PAYLOAD_SIZE) // Lossy to make room for flood header.
			len = FLOOD_MAX_PAYLOAD_SIZE;
		
		FMsg->fldSrc = TOS_NODE_ID;
		memcpy(FMsg->payload, payload, len);
		
		// Put this node as the link layer dest for the convenience of forwardToNeighbors().
		makePack(&forward, TOS_NODE_ID, TOS_NODE_ID, FLOOD_TTL, PROTOCOL_FLOOD, seqNum++, &floodMsg, len);
		post forwardToNeighbors();
		
		return;
	}
	
	event message_t* FReceive.receive(message_t* msg, void* payload, uint8_t len)
	{
		if(len == sizeof(pack)) // Is the payload received the size of a pack?
		{
			pack* FMsg = (pack*)payload; // Interpret the received payload as a pack.
			
			switch(FMsg->protocol)
			{
				case PROTOCOL_FLOOD: // Is it a flood packet?
					dbg(FLOODING_CHANNEL, "[FLOOD] %d Received: Source=%d|FloodSource=%d|TTL=%d|Sequence=%d|Protocol=%d\n", TOS_NODE_ID, FMsg->src, getFloodSource(FMsg), FMsg->TTL, FMsg->seq, FMsg->protocol);
					
					if(FMsg->seq >= seqCache && (FMsg->TTL)-- > 0) // Check TTL here since its in the Link Layer packs anyway.
					{
						flood_t* floodPacket = (flood_t*)FMsg->payload;		// Read the Link Layer payload as a flood packet.
						uint8_t* floodPayload = &floodPacket->payload;		// Make a pointer to the flood packet's payload.
						signal Flooding.readFlood(floodPayload, FLOOD_MAX_PAYLOAD_SIZE); // Pass to interface.
						
						lastHop = FMsg->src;
						makePack(&forward, TOS_NODE_ID, FMsg->dest, FMsg->TTL, PROTOCOL_FLOOD, FMsg->seq, FMsg->payload, len);
						post forwardToNeighbors(); // All good, forward to neighbors.
					}
					
					break;
					
				default:
					//dbg(FLOODING_CHANNEL, "[FLOOD] Unrecognized Packet Protocol: %d\n", FMsg->protocol);
					break;
			}
		
			return msg;
		}
		
		dbg(FLOODING_CHANNEL, "[FLOOD] Received Unknown Packet Type %d\n", len);
		return msg;
	}
	
	// Move to Packet header
	void makePack(pack *Package, uint16_t src, uint16_t dest, uint16_t TTL, uint16_t protocol, uint16_t seq, uint8_t* payload, uint8_t length)
	{
		Package->src = src;
		Package->dest = dest;
		Package->TTL = TTL;
		Package->seq = seq;
		Package->protocol = protocol;
		memcpy(Package->payload, payload, length);
	}
	
	uint16_t getFloodSource(pack *floodPacket)
	{
		flood_t *src = (flood_t*)(floodPacket->payload);
		return src->fldSrc;
	}
}