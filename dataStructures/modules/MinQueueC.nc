generic module MinQueueC(typedef t, int n)
{
	provides interface MinQueue<t>;
}

implementation
{
	uint16_t MINQUEUE_MAX_SIZE = n;
	
	typedef struct minQueueEntry
	{
		uint16_t key;
		t value;
	}minQEntry;
	
	minQEntry heap[n];
	uint16_t numVals = 0;
	
	void sortMinHeap(uint16_t root)
	{
		uint16_t min;
		bool swapRoot;
		minQEntry temp;
		
		//dbg(GENERAL_CHANNEL, "[MINQUEUE] Sorting Heap\n");
		do
		{
			// Track the minimum key for the subtree attached to this root.
			min = root;
			swapRoot = FALSE;
			
			// Check if there are any leafs in this subtree.
			if (2*root+1 < numVals)
			{
				// Is the left leaf the smallest key?
				if (heap[2*root+1].key < heap[min].key)
					min = 2*root+1;
				
				// Does the right leaf exist and is it the smallest key?
				if (2*root+2 < numVals && heap[2*root+2].key < heap[min].key)
					min = 2*root+2;
				
				// Set the smallest key that we found as the root.
				swapRoot = (min != root);
				if (swapRoot)
				{
					//dbg(GENERAL_CHANNEL, "[MINQUEUE] Swapping Root\n");
					temp = heap[root];
					heap[root] = heap[min];
					heap[min] = temp;
					
					root = min;
				}
			}
		}while(swapRoot);
		
		// We've reached a leaf of the entire heap.
		return;
	}
	
	command void MinQueue.enqueue(uint16_t key, t input)
	{
		uint16_t i = ++numVals;		// Update the size of the queue.
		
		if(numVals <= MINQUEUE_MAX_SIZE)
		{
			// Assuming there's space, shift existing values down linearly.
			while(i-- > 1)
			{
				heap[i].key = heap[i-1].key;
				heap[i].value = heap[i-1].value;
			}
			
			// Make the new value the head of the queue.
			heap[0].key = key;
			heap[0].value = input;
			
			// Sort the heap, now with the new value.
			sortMinHeap(0);
		}
		
		return;
	}
	
	command t MinQueue.dequeue()
	{
		t min;
		
		min = heap[0].value;			// Take the minimum off the top.
		heap[0] = heap[numVals-1];		// Put a large key on the top for now.
		
		heap[--numVals].key = 0;
		
		sortMinHeap(0);		// Sort the heap.
		
		return min;
	}
	
	command bool MinQueue.empty()
	{
		return (numVals == 0);
	}
	
	command uint16_t MinQueue.size()
	{
		return numVals;
	}
}