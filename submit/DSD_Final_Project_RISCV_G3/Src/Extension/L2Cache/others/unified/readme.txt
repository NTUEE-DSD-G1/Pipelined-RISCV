This folder is for L1 I/D Cache, unified L2 Cache (2 versions included).

Comparing to v1, v2 is optimized and bandwidth between L2 Cache & memory is reduced by 1/2,
which makes more sense.

simulation:
- RTL
  > ncverilog Final_tb.v CHIP.v slow_memory.v +access+r +define<+option>
- SYN
  > ncverilog Final_tb.v CHIP_syn.v slow_memory.v tsmc13.v +access+r +define<+option> +define+SDF
option: hasHazard, L2Cache, L2Cache_mod

(if want to simulate version 1, please change file name from Unified_L2_v1.v to Unified_L2.v)
(default version: v2)

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
  Dcache.v: 2-way L1 Dcache
  Unified_L2.v: unified L2 Cache (version 2)
  Unified_L2_v1.v: unified L2 Cache (version 1)



