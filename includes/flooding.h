#ifndef FLOODING_H
#define FLOODING_H

#include "packet.h"

enum{
	FLOODING_HEADER_LENGTH = 2,
	FLOOD_MAX_PAYLOAD_SIZE = PACKET_MAX_PAYLOAD_SIZE - FLOODING_HEADER_LENGTH,
	FLOOD_TTL = 20,
	MAX_SEQCACHE = 20
};


typedef nx_struct FloodPacket{
	nx_uint16_t src;
	nx_uint8_t payload[FLOOD_MAX_PAYLOAD_SIZE];
}Floodable;

void makeFloodable(Floodable* fld, uint16_t src, uint8_t* payload, uint8_t length)
{
	fld->src = src;
	memcpy(fld->payload, payload, length);
}

#endif