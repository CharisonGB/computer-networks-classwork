#include "../../includes/packet.h"

interface Routing
{
	command void forward(pack* sendPack, uint16_t destination);
}