//Author: UCM ANDES Lab
//$Author: abeltran2 $
//$LastChangedDate: 2014-06-16 13:16:24 -0700 (Mon, 16 Jun 2014) $

#ifndef PROTOCOL_H
#define PROTOCOL_H

//PROTOCOLS
enum{
	PROTOCOL_PING = 0,		// Used in NeighborDiscovery module
	PROTOCOL_PINGREPLY = 1,	// Used in NeighborDiscovery module
	PROTOCOL_LINKSTATE = 2,	// Used in Routing module
	PROTOCOL_NAME = 3,
	PROTOCOL_TCP= 4,
	PROTOCOL_DV = 5,
	PROTOCOL_FLOOD = 6, 	// Used in Flooding module
	PROTOCOL_CMD = 99
};



#endif /* PROTOCOL_H */