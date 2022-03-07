interface InternetProtocol
{
	command void send(uint8_t *payload, uint16_t destination);
	event void receive(uint8_t *payload, uint8_t len, uint16_t source);
}

/* TODO for TCP
	Allow pass source address when signalling receive for socket binding checks.
*/