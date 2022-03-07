interface MinQueue<t>
{
	command void enqueue(uint16_t key, t input);
	command t dequeue();
	command bool empty();
	command uint16_t size();
}