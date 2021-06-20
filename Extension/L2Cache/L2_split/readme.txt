This folder is for split L1, L2 DCache and ICache.

Using L2 ICache won't do any better on origin tb(instruction), but will improve
performance magnificently in modified tb(instruction).

I_mem_L2Cache_origin: origin tb instruction
I_mem_L2Cache: modified instruction, add 32 nop within swap loop of BubbleSort