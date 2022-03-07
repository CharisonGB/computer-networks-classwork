#ifndef __SOCKET_H__
#define __SOCKET_H__

#include "packet.h"

enum{
    MAX_NUM_OF_SOCKETS = 10,
    ROOT_SOCKET_ADDR = 255,
    ROOT_SOCKET_PORT = 255,
    SOCKET_BUFFER_SIZE = 128,
};

enum socket_state{
    CLOSED,
    LISTEN,
    ESTABLISHED,
    SYN_SENT,
    SYN_RCVD,
	FIN_WAIT_1,
	FIN_WAIT_2,
	TIME_WAIT,
	CLOSE_WAIT,
	LAST_ACK
};

typedef nx_uint8_t nx_socket_port_t;
typedef uint8_t socket_port_t;

// socket_addr_t is a simplified version of an IP connection.
typedef nx_struct socket_addr_t{
    nx_socket_port_t port;
    nx_uint16_t addr;
}socket_addr_t;


// File descripter id. Each id is associated with a socket_store_t
typedef uint8_t socket_t;

// State of a socket. 
typedef struct socket_store_t{
    uint8_t flag;
    enum socket_state state;
    socket_port_t src;
    socket_addr_t dest;

    // This is the sender portion.
    uint8_t sendBuff[SOCKET_BUFFER_SIZE];
    uint8_t lastWritten;
    uint8_t lastAck;
    uint8_t lastSent;

    // This is the receiver portion
    uint8_t rcvdBuff[SOCKET_BUFFER_SIZE];
    uint8_t lastRead;
    uint8_t lastRcvd;
    uint8_t nextExpected;

    uint16_t RTT;
    uint8_t effectiveWindow;
}socket_store_t;

enum{
	TRANSPORT_HEADER_LENGTH = 9,
	TRANSPORT_MAX_PAYLOAD = PACKET_MAX_PAYLOAD_SIZE - TRANSPORT_HEADER_LENGTH
};

enum{
	NONE = 0,
	SYN = 1,	// 2^0
	ACK = 2,	// 2^1
	FIN = 4		// 2^2
	/*	Enumerating flags as unique powers of 2 also uniquely emumerates their sums.
		Each flag is analogous to a bit position.	*/
};

typedef nx_struct Segment{
	nx_socket_port_t src;
	nx_socket_port_t dest;
	nx_uint16_t seq;
	nx_uint16_t ack;
	nx_uint8_t flags;
	nx_uint8_t advertWindow;
	nx_uint8_t len;
	nx_uint8_t payload[TRANSPORT_MAX_PAYLOAD];
}segment_t;

void makeSegment(segment_t* seg, socket_port_t src, socket_port_t dest, uint16_t seq, uint16_t ack, uint8_t flags, uint8_t adwndw, uint8_t* pyld, uint8_t len)
{
	seg->src = src;
	seg->dest = dest;
	seg->seq = seq;
	seg->ack = ack;
	seg->flags = flags;
	seg->advertWindow = adwndw;
	seg->len = len;
	memcpy(seg->payload, pyld, len);
}

typedef struct ConnectionRequest{
	uint16_t src;
	socket_port_t srcPort;
	socket_port_t destPort;
	uint8_t seq;
}conn_req_t;

#endif
