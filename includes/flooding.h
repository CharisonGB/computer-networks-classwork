#ifndef FLOODING_H
#define FLOODING_H

#include "packet.h"

enum{
	FLOODING_HEADER_LENGTH = 2,
	FLOOD_MAX_PAYLOAD_SIZE = PACKET_MAX_PAYLOAD_SIZE - FLOODING_HEADER_LENGTH,
	FLOOD_TTL = 10
};


typedef nx_struct Flood{
	nx_uint16_t fldSrc;
	//nx_uint16_t seq;		// Already in Link Layer packets. Implement when building new packet type on top of AM_PACK.
	//nx_uint8_t TTL;		// Already in Link Layer packets. Implement when building new packet type on top of AM_PACK.
	nx_uint8_t payload[FLOOD_MAX_PAYLOAD_SIZE];
}flood_t;

#endif
