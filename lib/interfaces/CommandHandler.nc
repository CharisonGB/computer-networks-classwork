interface CommandHandler{
   // Events
   event void ping(uint16_t destination, uint8_t *payload);
   event void printNeighbors();
   event void printRouteTable();
   event void printLinkState();
   event void printDistanceVector();
   event void setTestServer(uint8_t source, uint8_t port);	// Now accepts <address, port> inputs.
   event void setTestClient();
   event void setAppServer();
   event void setAppClient();
}
