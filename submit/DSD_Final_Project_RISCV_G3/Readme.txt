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
	1. make sure all files in "DSD_Final_Project_RISCV_G3/Src/Extension/Compression/rtl" exist
	2. ncverilog Final_tb.v CHIP.v slow_memory.v +define+decompression +access+r
 	   ncverilog Final_tb.v CHIP.v slow_memory.v +define+compression +access+r

Compression(SYN)
	1. make sure all files in "DSD_Final_Project_RISCV_G3/Src/Extension/Compression/syn" exist
	2. ncverilog Final_tb.v CHIP_syn.v slow_memory.v tsmc13.v +define+decompression +define+SDF +access+r
	   ncverilog Final_tb.v CHIP_syn.v slow_memory.v tsmc13.v +define+compression +define+SDF +access+r
	3. You can open CHIP_syn.ddc in dv to see the area
	4. There are some setup warning before the reset signal is given
L2cache(RTL)

	1. make sure all files in "DSD_Final_Project_RISCV_G3/Src/Extension/L2Cache/rtl" exist
	2. ncverilog Final_tb.v CHIP.v slow_memory.v +define+L2Cache +access+r
	3. For more information, please refer to readme.txt in "DSD_Final_Project_RISCV_G3/Src/Extension/L2Cache

L2cache(SYN)
	1. make sure all files in "DSD_Final_Project_RISCV_G3/Src/Extension/L2Cache/syn" exist
	2. ncverilog Final_tb.v CHIP_syn.v slow_memory.v tsmc13.v +define+L2Cache +define+SDF +access+r
	3. You can open CHIP_syn.ddc in dv to see the area
	4. There are some setup warning before the reset signal is given
	5. For more information, please refer to readme.txt in "DSD_Final_Project_RISCV_G3/Src/Extension/L2Cache