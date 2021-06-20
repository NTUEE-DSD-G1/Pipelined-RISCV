// Top module of your design, you cannot modify this module!!
`include "Icache.v"
`include "Dcache.v"
`include "Dcache_L2.v"
`include "RISCV_Pipeline.v"

module CHIP (	clk,
				rst_n,
//----------for slow_memD------------
				mem_read_D,
				mem_write_D,
				mem_addr_D,
				mem_wdata_D,
				mem_rdata_D,
				mem_ready_D,
//----------for slow_memI------------
				mem_read_I,
				mem_write_I,
				mem_addr_I,
				mem_wdata_I,
				mem_rdata_I,
				mem_ready_I,
//----------for TestBed--------------				
				DCACHE_addr, 
				DCACHE_wdata,
				DCACHE_wen   
			);
input			clk, rst_n;
//--------------------------

output			    mem_read_D;
output			    mem_write_D;
output	[31:4]	mem_addr_D;
output	[127:0]	mem_wdata_D;
input	  [127:0]	mem_rdata_D;
input			      mem_ready_D;
//--------------------------
output		    	mem_read_I;
output		    	mem_write_I;
output	 [31:4]	mem_addr_I;
output	[127:0]	mem_wdata_I;
input 	[127:0]	mem_rdata_I;
input			      mem_ready_I;
//----------for TestBed--------------
output	 [29:0]	DCACHE_addr;
output	 [31:0]	DCACHE_wdata;
output		    	DCACHE_wen;
//--------------------------

// wire declaration
wire          ICACHE_ren;
wire          ICACHE_wen;
wire [29:0]   ICACHE_addr;
wire [31:0]   ICACHE_wdata;
wire          ICACHE_stall;
wire [31:0]   ICACHE_rdata;

wire          DCACHE_ren;
wire          DCACHE_wen;
wire [29:0]   DCACHE_addr;
wire [31:0]   DCACHE_wdata;
wire          DCACHE_stall;
wire [31:0]   DCACHE_rdata;

wire          DCACHE_L2_ren;
wire          DCACHE_L2_wen;
wire [27:0]   DCACHE_L2_addr;
wire [127:0]  DCACHE_L2_wdata;
wire          DCACHE_L2_ready;
wire [127:0]  DCACHE_L2_rdata;


//=========================================
	// Note that the overall design of your RISCV includes:
	// 1. pipelined RISCV processor
	// 2. data cache
	// 3. instruction cache

	// Baseline:
	// 1. supporting all instructions
	// 2. with caches
	// 3. Pass all test assembly programs
	// 4. Complete the circuit synthesis (without negative timing slack)


	RISCV_Pipeline i_RISCV(
		// control interface
		.clk            (clk)           , 
		.rst_n          (rst_n)         ,
//----------I cache interface-------		
		.ICACHE_ren     (ICACHE_ren)    ,
		.ICACHE_wen     (ICACHE_wen)    ,
		.ICACHE_addr    (ICACHE_addr)   ,
		.ICACHE_wdata   (ICACHE_wdata)  ,
		.ICACHE_stall   (ICACHE_stall)  ,
		.ICACHE_rdata   (ICACHE_rdata)  ,
//----------D cache interface-------
		.DCACHE_ren     (DCACHE_ren)    ,
		.DCACHE_wen     (DCACHE_wen)    ,
		.DCACHE_addr    (DCACHE_addr)   ,
		.DCACHE_wdata   (DCACHE_wdata)  ,
		.DCACHE_stall   (DCACHE_stall)  ,
		.DCACHE_rdata   (DCACHE_rdata)
	);
	

	Dcache D_cache(
		.clk        (clk)             ,
		.proc_reset (~rst_n)          ,
		.proc_read  (DCACHE_ren)      ,
		.proc_write (DCACHE_wen)      ,
		.proc_addr  (DCACHE_addr)     ,
		.proc_rdata (DCACHE_rdata)    ,
		.proc_wdata (DCACHE_wdata)    ,
		.proc_stall (DCACHE_stall)    ,
		.mem_read   (DCACHE_L2_ren)   ,
		.mem_write  (DCACHE_L2_wen)   ,
		.mem_addr   (DCACHE_L2_addr)  ,
		.mem_wdata  (DCACHE_L2_wdata) ,
		.mem_rdata  (DCACHE_L2_rdata) ,
		.mem_ready  (DCACHE_L2_ready)
	);

	Icache I_cache(
		.clk        (clk)             ,
		.proc_reset (~rst_n)          ,
		.proc_read  (ICACHE_ren)      ,
		.proc_write (ICACHE_wen)      ,
		.proc_addr  (ICACHE_addr)     ,
		.proc_rdata (ICACHE_rdata)    ,
		.proc_wdata (ICACHE_wdata)    ,
		.proc_stall (ICACHE_stall)    ,
		.mem_read   (mem_read_I)   ,
		.mem_write  (mem_write_I)   ,
		.mem_addr   (mem_addr_I)  ,
		.mem_rdata  (mem_rdata_I) ,
		.mem_wdata  (mem_wdata_I) ,
		.mem_ready  (mem_ready_I)
	);

	Dcache_L2 D_cache_L2(
			.clk        (clk)            ,
			.proc_reset (~rst_n)         ,
			.proc_read  (DCACHE_L2_ren)  ,
			.proc_write (DCACHE_L2_wen)  ,
			.proc_addr  (DCACHE_L2_addr) ,
			.proc_rdata (DCACHE_L2_rdata),
			.proc_wdata (DCACHE_L2_wdata),
			.proc_ready (DCACHE_L2_ready),
			.mem_read   (mem_read_D)     ,
			.mem_write  (mem_write_D)    ,
			.mem_addr   (mem_addr_D)     ,
			.mem_wdata  (mem_wdata_D)    ,
			.mem_rdata  (mem_rdata_D)    ,
			.mem_ready  (mem_ready_D)
	);
endmodule
