`timescale 1ns/1ps

`include "BS.v"
`include "timing_generator.v"
`include "image_capture.v"
`include "image_source.v"

`define cycle1 13.5

module DUT_tb;

reg  [10:0] v_total1, v_size1;
reg  [9:0]  v_start1, v_sync1;
reg  [11:0] h_total1, h_size1;
reg  [10:0] h_start1, h_sync1;
reg  [22:0] vs_reset1; 
reg  [10:0] v_total2, v_size2;
reg  [9:0]  v_start2, v_sync2;
reg  [11:0] h_total2, h_size2;
reg  [10:0] h_start2, h_sync2;
reg  [22:0] vs_reset2; 
reg  rst1_n, clk1, clk2;
reg  pass; // 新增 pass 訊號定義

wire [26:0] DPi_DUT, DPo_DUT;
wire [2:0] Sync1;
wire [2:0] Sync2;

reg [31:0] check;

// 產生時脈訊號
always #(`cycle1/2) clk1 = ~clk1;      // 74MHz for 720p
always #((`cycle1*2/3)/2) clk2 = ~clk2; // 148MHz for 1080p

initial begin
					
/********** Timing parameter **********/
 		
  #0  clk1=0;
  #0  clk2=0;
	#0  rst1_n =1;

	// 720p 時序參數
	h_size1  = 12'd1280;
  h_total1 = 12'd1650;  
  h_sync1  = 11'd40;
  h_start1 = 11'd260;
  v_size1  = 11'd720;	
  v_total1 = 11'd750;
  v_sync1  = 10'd5;
  v_start1 = 10'd25;
	vs_reset1 = 23'd0; // 修正：添加預設值
  
  // 1080p 時序參數
  h_size2  = 12'd1920;
  h_total2 = 12'd2200;  
  h_sync2  = 11'd44;
  h_start2 = 11'd192;
  v_size2  = 11'd1080;	
  v_total2 = 11'd1125;
  v_sync2  = 10'd5;
  v_start2 = 10'd41;
	vs_reset2 = 23'd0; // 修正：添加預設值
  
  pass = 0; // 修正：初始化 pass 訊號，0 為雙線性插值模式
	
	#`cycle1 rst1_n =0;
	#`cycle1 rst1_n =1;

#20000000
$finish;

end	
	
/********** Waveform output **********/

initial begin
    `ifdef FSDB
    $fsdbDumpfile("top.fsdb");
    $fsdbDumpvars(0);
    `elsif FSDB_ALL
    $fsdbDumpfile("top.fsdb");
    $fsdbDumpvars(0, "+mda");
    `endif
end

/********** Image source **********/
image_source image_source(
   .clk(clk1),
   .rst_n(rst1_n),
   .Synci(Sync1),
   .DPo(DPi_DUT));

/********** Timing generator **********/
timing_generator timing_generator1(
  .Synco(Sync1),
  .clk(clk1),
  .rst_n(rst1_n),
  .v_total(v_total1),
  .v_sync(v_sync1),
  .v_start(v_start1),
  .v_size(v_size1),
  .h_total(h_total1),
  .h_sync(h_sync1),
  .h_start(h_start1),
  .h_size(h_size1),
  .vs_reset(vs_reset1));

/********** Timing generator **********/
timing_generator timing_generator2(
  .Synco(Sync2),
  .clk(clk2),
  .rst_n(rst1_n),
  .v_total(v_total2),
  .v_sync(v_sync2),
  .v_start(v_start2),
  .v_size(v_size2),
  .h_total(h_total2),
  .h_sync(h_sync2),
  .h_start(h_start2),
  .h_size(h_size2),
  .vs_reset(vs_reset2));

/********** Function to be verified (DUT) **********/

BS BS(
    .clk1(clk1),
    .clk2(clk2),
    .rst_n(rst1_n),
    .DPi(DPi_DUT[23:0]),
    .pass(pass),
    .Sync_720p(DPi_DUT[26:24]),
    .Sync_1080p(Sync2),
    .DPo(DPo_DUT));

/********** Image capture (saved to BMP file) **********/

image_capture image_capture(
  .clk(clk2),
  .rst_n(rst1_n),
  .DPi(DPo_DUT),
  .Hsize(h_size2),
  .Vsize(v_size2));

endmodule
