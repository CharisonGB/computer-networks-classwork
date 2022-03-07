interface Flooding
{
	command void flood(uint8_t *payload, uint8_t len);
	event void readFlood(uint8_t *payload, uint8_t len);
}

// Todo
// event void readFloodPacket(uint8_t *payload, uint8_t len);