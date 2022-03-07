#include "../../includes/channels.h"
#include "../../includes/packet.h"
#include "../../includes/IP.h"

module InternetProtocolP
{
	provides interface InternetProtocol;
	
	uses interface SimpleSend as IPSend;
	uses interface Receive as IPReceive;
	
	uses interface Routing;
}

implementation
{	
	pack forwardPackage, *frwdPack = &forwardPackage;			// Dedicated module memory for forwarding Link Layer packets.
	pack receivedPackage, *rcvdPack = &receivedPackage;			// Dedicated module memory for processing Link Layer packets.
	IPPacket IPPack, *ipp = &IPPack;						// Dedicated module memory for handling IP Packets.
	
	task void forward()
	{
		call IPSend.send(*frwdPack, frwdPack->dest);
	}
	
	event message_t* IPReceive.receive(message_t* msg, void* payload, uint8_t len)
	{
		if(len == sizeof(pack)) // Is the payload received the size of a pack?
		{
			*rcvdPack = *( (pack*)payload ); // Interpret the received payload as a pack and put it in memory that the whole module can access.
			
			switch(rcvdPack->protocol)
			{
				case PROTOCOL_PING: // Is it a flood packet?
					*ipp = *( (IPPacket*)rcvdPack->payload );	// Read the Link Layer payload as a IP packet.
					
					if(ipp->protocol == PROTOCOL_PING && (ipp->TTL)-- > 0)
					{
						if(ipp->dest == TOS_NODE_ID)
						{
							dbg(ROUTING_CHANNEL, "[ROUTING::IP] %d was the final destination of an IP Packet!\n", TOS_NODE_ID);
							signal InternetProtocol.receive(&ipp->payload, IP_MAX_PAYLOAD, ipp->src);	// Pass to interface.
						}
						else
						{
							makeIPPacket(ipp, ipp->src, ipp->dest, IP_TTL, PROTOCOL_PING, ipp->payload, IP_MAX_PAYLOAD);
							makePack(frwdPack, TOS_NODE_ID, (call Routing.next(ipp->dest)), ipp->TTL, PROTOCOL_PING, rcvdPack->seq, ipp, sizeof(IPPacket));
							
							dbg(ROUTING_CHANNEL, "[ROUTING::IP] %d is forwarding src=%d, dest=%d, TTL=%d\n", TOS_NODE_ID, ipp->src, ipp->dest, ipp->TTL);
							post forward();
						}
					}
					
					break;
					
				default:
					//dbg(ROUTING_CHANNEL, "[ROUTING::IP] Unrecognized Packet Protocol: %d\n", ipp->protocol);
					break;
			}
		
			return msg;
		}
		
		dbg(ROUTING_CHANNEL, "[ROUTING::IP] Received Unknown Packet Type %d\n", len);
		return msg;
	}
	
	command void InternetProtocol.send(uint8_t *payload, uint8_t len, uint16_t destination)
	{
		uint16_t nextHop = call Routing.next(destination);
		if(nextHop == 0) { return; }
		
		// FIXME: Chops data
		if(len > IP_MAX_PAYLOAD)
			len = IP_MAX_PAYLOAD;
		makeIPPacket(ipp, TOS_NODE_ID, destination, IP_TTL, PROTOCOL_PING, payload, len);
		
		makePack(frwdPack, TOS_NODE_ID, nextHop, IP_TTL, PROTOCOL_PING, 0, ipp, sizeof(IPPacket));
		dbg(ROUTING_CHANNEL, "[ROUTING::IP] %d is sending src=%d, dest=%d, TTL=%d\n", TOS_NODE_ID, ipp->src, ipp->dest, ipp->TTL);
		
		post forward();
	}
}