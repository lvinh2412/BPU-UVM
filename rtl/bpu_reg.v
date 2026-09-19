//--------------------------------------------------------------------------------
//
// Module: bpu_reg.v
//
// Vai tro: bo nho du doan. Moi bang doc to hop, ghi o posedge clk voi dieu kien
//   (wr_en && !halt).
//
//   Trong cung mot chu ky, moi bang duoc doc o NHIEU dia chi: pc (execute, cho
//   duong cap nhat), nxpc (tang du phong) va nxpc2 (du doan o fetch). Con ghi thi
//   luon ghi o phia pc.
//
//   Luu y phu thuoc trong cung chu ky: local_pht lay chi muc tu NOI DUNG cua
//   local_bht, global_pht lay pc_index ^ ghr. Hai chi muc do dung gia tri CU cua
//   thanh ghi nguon, vi moi lenh ghi cung roi vao mot canh clock.
//
//-------------------------------------------------------------------------------

`timescale 1ns / 1ps

module bpu_reg(
    	 input         	clk
    	,input			rst_n
    	,input         	halt
    	,input 	[31:0] 	pc
    	,input	[31:0] 	nxpc
    	,input	[31:0] 	nxpc2                     
    	// BTB
    	,output        	btb_valid_pc
    	,output [31:0] 	btb_target_pc
    	,output        	btb_valid_nxpc
    	,output        	btb_valid_nxpc2           
    	,output [31:0] 	btb_target_nxpc2          
    	,input         	btb_wr_en
    	,input  [31:0] 	btb_wr_target
    	// Local BHT
    	,output [11:0]  local_bht_data_pc
    	,input         	local_bht_wr_en
    	,input  [11:0] 	local_bht_wr_data
    	// Local PHT
    	,output [1:0]  	local_pht_data_pc
    	,output [1:0]  	local_pht_data_nxpc2      
    	,input         	local_pht_wr_en
    	,input  [1:0]  	local_pht_wr_data
    	// Global PHT
    	,output [1:0]  	global_pht_data_pc
    	,output [1:0]  	global_pht_data_nxpc2     
    	,input         	global_pht_wr_en
    	,input  [1:0]  	global_pht_wr_data
    	// Choice
    	,output [1:0]  	choice_data_pc
    	,output [1:0]  	choice_data_nxpc2         
    	,input         	choice_wr_en
    	,input  [1:0]  	choice_wr_data
    	// GHR
    	,output [9:0]  	ghr_out
    	,input         	ghr_wr_en
    	,input  [9:0]  	ghr_wr_data
);

// Chi muc bang: chi lay bit dia chi tu, KHONG co truong tag -- hai PC cach nhau
// boi so 4 KB se trung chi muc
wire [9:0] pc_index	   = pc[11:2];
wire [9:0] nxpc_index  = nxpc[11:2];
wire [9:0] nxpc2_index = nxpc2[11:2];

// Bo nho
reg 	   btb_valid	[0:1023];   // 1024 x 1
reg [31:0] btb_target	[0:1023];   // 1024 x 32
reg [11:0]  local_bht	[0:1023];   // 1024 x 12  lich su re rieng tung PC
reg [1:0]  local_pht	[0:4095];   // 4096 x 2   chi muc la noi dung BHT
reg [1:0]  global_pht	[0:1023];   // 1024 x 2   gshare
reg [1:0]  choice		[0:1023];   // 1024 x 2   bo chon local hay global
reg [9:0]  ghr;                     // lich su toan cuc

// === BTB ===
// Doc
assign btb_target_pc    = btb_target[pc_index];
assign btb_target_nxpc2 = btb_target[nxpc2_index];          

assign btb_valid_pc    = btb_valid[pc_index];
assign btb_valid_nxpc  = btb_valid[nxpc_index];
assign btb_valid_nxpc2 = btb_valid[nxpc2_index];            

integer i;

// Ghi
always @(posedge clk or negedge rst_n) begin
	if(!rst_n) begin
		for (i=0; i< 1024; i = i+1) begin
			btb_valid[i]  <= 0;
			btb_target[i] <= 0;
		end
	end else
	if(btb_wr_en && !halt) begin
		btb_target[pc_index] <= btb_wr_target;
		btb_valid[pc_index]  <= 1'b1;
	end else begin
		btb_target[pc_index] <= btb_target[pc_index];
		btb_valid[pc_index]  <= btb_valid[pc_index];
	end
end


// === Local BHT ===
// Doc
assign local_bht_data_pc    = local_bht[pc_index];

// Ghi
always @(posedge clk or negedge rst_n) begin
	if(!rst_n) begin
		for (i=0; i< 1024; i = i+1) begin
			local_bht[i] <= 0;
		end
	end else
	if(local_bht_wr_en && !halt) begin
		local_bht[pc_index] <= local_bht_wr_data;
	end else begin
		local_bht[pc_index] <= local_bht[pc_index];
	end
end


// === Local PHT ===
// Hai muc: o BHT cua PC nay chinh la chi muc vao PHT
wire [11:0] local_pht_index_pc    = local_bht[pc_index];
wire [11:0] local_pht_index_nxpc2 = local_bht[nxpc2_index];

// Doc
assign local_pht_data_pc    = local_pht[local_pht_index_pc];
assign local_pht_data_nxpc2 = local_pht[local_pht_index_nxpc2];  

// Ghi
always @(posedge clk or negedge rst_n) begin
	if(!rst_n) begin
		for (i=0; i< 4096; i = i+1) begin
			local_pht[i] <= 0;
		end
	end else
	if(local_pht_wr_en && !halt) begin
		local_pht[local_pht_index_pc] <= local_pht_wr_data;
	end else begin
		local_pht[local_pht_index_pc] <= local_pht[local_pht_index_pc];
	end
end

// === Global PHT ===
// gshare: chi muc PC XOR lich su toan cuc
wire [9:0] global_pc_index    = pc_index    ^ ghr;
wire [9:0] global_nxpc2_index = nxpc2_index ^ ghr;

// Doc
assign global_pht_data_pc    = global_pht[global_pc_index];
assign global_pht_data_nxpc2 = global_pht[global_nxpc2_index];   

// Ghi
always @(posedge clk or negedge rst_n) begin
	if(!rst_n) begin
		for (i=0; i< 1024; i = i+1) begin
			global_pht[i] <= 0;
		end
	end else
	if(global_pht_wr_en && !halt) begin
		global_pht[global_pc_index] <= global_pht_wr_data;
	end else begin
		global_pht[global_pc_index] <= global_pht[global_pc_index];
	end
end

// === Choice ===
// Doc
assign choice_data_pc    = choice[pc_index];
assign choice_data_nxpc2 = choice[nxpc2_index];            

// Ghi
always @(posedge clk or negedge rst_n) begin
	if(!rst_n) begin
		// Reset ve WNT: nghieng ve local, chi cach mot buoc la doi sang global
		for (i=0; i< 1024; i = i+1) begin
			choice[i] <= 2'b01;
		end
	end else
	if(choice_wr_en && !halt) begin
		choice[pc_index] <= choice_wr_data;
	end else begin
		choice[pc_index] <= choice[pc_index];
	end
end

// === GHR ===
// Doc
assign ghr_out = ghr;

// Ghi
always @(posedge clk or negedge rst_n) begin
	if(!rst_n) begin
		ghr <= 10'd0;
	end else
	if(ghr_wr_en && !halt) begin
		ghr <= ghr_wr_data;
	end else begin
		ghr <= ghr;
	end
end
endmodule
