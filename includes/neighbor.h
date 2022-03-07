#ifndef NEIGHBOR_H
#define NEIGHBOR_H

enum{
	INACTIVE_THRESHOLD = 5,
	MAX_NEIGHBOR_TABLE = 6
};

typedef struct NeighborData{
	uint16_t address;
	uint16_t sent;
	uint16_t received;
	float_t linkQual;
	bool active;
}NeighborData;

#endif /* NEIGHBOR_STATS */