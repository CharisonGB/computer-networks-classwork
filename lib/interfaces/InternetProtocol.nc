interface InternetProtocol
{
	command void send(uint8_t *payload, uint16_t destination);
	event void receive(uint8_t *payload, uint8_t len);
}