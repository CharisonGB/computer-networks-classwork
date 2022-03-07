#ifndef IP_H
#define IP_H

#include "packet.h"
#include "protocol.h"

enum{
	IP_HEADER_LENGTH = 6,
	IP_MAX_PAYLOAD = PACKET_MAX_PAYLOAD_SIZE - IP_HEADER_LENGTH,
	IP_TTL = 16
};

typedef nx_struct IPPacket{
	nx_uint16_t src;
	nx_uint16_t dest;
	nx_uint8_t TTL;
	nx_uint8_t protocol;
	nx_uint8_t payload[IP_MAX_PAYLOAD];
}IPPacket;

void makeIPPacket(IPPacket* ipp, uint16_t src, uint16_t dest, uint8_t TTL, uint8_t protocol, uint8_t* payload, uint8_t len)
{
	ipp->src = src;
	ipp->dest = dest;
	ipp->TTL = TTL;
	ipp->protocol = protocol;
	memcpy(ipp->payload, payload, len);
}

#endif