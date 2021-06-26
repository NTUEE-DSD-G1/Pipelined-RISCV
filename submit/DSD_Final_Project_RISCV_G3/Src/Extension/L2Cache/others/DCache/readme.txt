This folder is for RISC-V with DCache(L1, L2) and ICache(only L1).
Cuz for L2's tb, adding L2 ICache won't do any better.

simulation:
- RTL
  > ncverilog Final_tb.v CHIP.v slow_memory.v +access+r +define<+option>
- SYN
  > ncverilog Final_tb.v CHIP.v slow_memory.v tsmc13.v +access+r +define<+option> +define+SDF
option: hasHazard, L2Cache, L2Cache_mod

Files:
  ------- shared with other folders -------
  CHIP_syn.sdc: synthesis use
  CHIP.v: top module for RISC-V + Caches
  Final_tb.v: Overall tb
  D_mem: for data memory initialization
  I_mem: for instruction memory initialization
    I_mem_hasHazard: baseline's instructions
    I_mem_L2Cache: L2 Cache's instructions
    I_mem_L2Cache_mod: modified I_mem_L2Cache, for testing L2 I-Cache
  RISCV_Pipeline.v: RISC-V processor
  slow_memory.v: simulates memory
  TestBed_hasHazard.v: baseline's tb
  TestBed_L2Cache.v: L2Cache & modified L2Cache's tb
  ------ differ from spec ------
  Icache.v: directed map L1 ICache
  Icache_2way.v: 2 way associative L1 ICache
  Dcache.v: 2-way L1 DCache
  Dcache_L2.v: 2-way L2 DCache