#ifndef NEIGHBOR_H
#define NEIGHBOR_H

enum{
	INACTIVE_THRESHOLD = 5,
	MAX_NEIGHBOR_TABLE = 8
};

typedef struct NeighborData{
	uint16_t addr;	// Address.
	uint16_t sent;		// Last packet sent (sequence number).
	uint16_t rcvd;	// Last packet received (sequence number).
	float_t linkQual;	// Link Quality estimate.
	bool active;		// Judgement of if this neighbor is still alive.
}Neighbor;

void setNeighbor(Neighbor *neighbor, uint16_t address, uint16_t lastSent, uint16_t lastRcvd)
{
	neighbor->addr = address;
	neighbor->sent = lastSent;
	neighbor->rcvd = lastRcvd;
	neighbor->linkQual = ( (float_t)(lastRcvd+1) / (float_t)(lastSent+1) ) * 100;
	neighbor->active = (lastSent - lastRcvd) < INACTIVE_THRESHOLD;
}

#endif