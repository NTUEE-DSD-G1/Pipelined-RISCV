DSD_RISCV_G3

Baseline(RTL)
	1. make sure all files in "DSD_Final_Project_RISCV_G3/Src/Baseline/rtl" exist
	2. ncverilog Final_tb.v CHIP.v slow_memory.v +define+noHazard +access+r
	   ncverilog Final_tb.v CHIP.v slow_memory.v +define+hasHazard +access+r

Baseline(SYN)
	1. make sure all files in "DSD_Final_Project_RISCV_G3/Src/Baseline/syn" exist
	2. ncverilog Final_tb.v CHIP_syn.v slow_memory.v tsmc13.v +define+noHazard +define+SDF +access+r
	   ncverilog Final_tb.v CHIP_syn.v slow_memory.v tsmc13.v +define+hasHazard +define+SDF +access+r
	3. You can open CHIP_syn.ddc in dv to see the area

BrPred(RTL)
	1. make sure all files in "DSD_Final_Project_RISCV_G3/Src/Extension/BrPred/rtl" exist
	2. ncverilog Final_tb.v CHIP.v slow_memory.v +define+hasHazard +access+r
 	   ncverilog Final_tb.v CHIP.v slow_memory.v +define+BrPred +access+r
	3.(*) you can replace RISCV_BrPred.v with "others/RISCV_BrCache.v" and modify the include file in CHIP.v
	   Then repeat 2 to use the BPU with Branch prediction buffer
	4.(*) you can replace I_mem_hasHazard with "others/I_mem_hasHazard_modified" and change the file name to
	   I_mem_hasHazard. Then repeat 2 to use the instructions modified (see report for more details)

BrPred(SYN)
	1. make sure all files in "DSD_Final_Project_RISCV_G3/Src/Extension/BrPred/syn" exist
	2. ncverilog Final_tb.v CHIP_syn.v slow_memory.v tsmc13.v +define+hasHazard +define+SDF +access+r
	   ncverilog Final_tb.v CHIP_syn.v slow_memory.v tsmc13.v +define+BrPred +define+SDF +access+r
	3. You can open CHIP_syn.ddc in dv to see the area

Compression(RTL)

Compression(SYN)

L2cache(RTL)

L2cache(SYN)