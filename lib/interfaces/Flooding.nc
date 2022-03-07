interface Flooding
{
	command void flood(uint8_t *payload, uint8_t len);
	event void readFlood(uint16_t src, uint8_t *payload, uint8_t len);
}