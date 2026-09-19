//--------------------------------------------------------------------------------
//
// Module: bpu_ctrl.v
//
// Vai tro: dieu khien chuyen huong. Ba nguon lai bpu_nxpc2, theo thu tu uu tien:
//     corr - hieu chinh o execute sau khi du doan sai
//     d    - tang du phong o decode: fetch truot BTB nhung opcode noi day dung la
//            lenh re
//     f    - tang fetch: BTB trung tai nxpc2 va tournament du doan RE
//
//   Quyet dinh o fetch duoc mang xuong qua hai thanh ghi, de execute so no voi
//   ket qua that cua CHINH lenh do.
//
//-------------------------------------------------------------------------------

`timescale 1ns / 1ps

module bpu_ctrl(
     input          clk                         
    ,input          rst_n                       
    ,input          halt                        
    ,input  [31:0]  pc
    ,input  [31:0]  nxpc
    ,input  [6:0]   fetch_opcode
    ,input  [1:0]   flush_in
    // execute (correction)
    ,input          is_branch
    ,input          branch_taken
    ,input  [31:0]  branch_offset               
    ,input  [31:0]  btb_target_pc               
    ,output [1:0]   bpu_flush
    // Stage 1: fetch (NXPC2)
    ,input          btb_valid_nxpc2
    ,input          predict_taken_nxpc2
    ,input  [31:0]  btb_target_nxpc2
	,input  [1:0]   local_pht_data_nxpc2
	,input  [1:0]   global_pht_data_nxpc2
    // Stage 2: decode backstop (NXPC)
    ,input          btb_valid_nxpc
    ,input  [31:0]  branch_target_fetch
	// output to predictor
	,output         local_carry
	,output         global_carry
    // output MUX
    ,output [31:0]  bpu_nxpc2
    ,output         bpu_nxpc2_valid
);

// Tien tinh: opcode BCC cua RV32I, va dieu kien "front-end con nhan chuyen huong"
// (flush_in = 2 nghia la da co hai bong bong tren duong, khong them nua)
wire fetch_is_branch = (fetch_opcode == 7'b1100011);
wire fetch_ready     = ((flush_in == 2'd0) || (flush_in == 2'd1));

// Tang FETCH (doc theo chi muc NXPC2)
wire        f_valid = (btb_valid_nxpc2 && predict_taken_nxpc2 && fetch_ready);
wire [31:0] f_nxpc2 = btb_target_nxpc2;

// Tang du phong o DECODE (doc theo chi muc NXPC)
wire        d_valid = (fetch_is_branch && !btb_valid_nxpc && fetch_ready);
wire [31:0] d_nxpc2 = nxpc + branch_target_fetch;

// CARRY-DOWN: bon thanh ghi dich sau 2, mang quyet dinh luc fetch xuong execute.
// Chi rst_n xoa chung; halt chi dong bang.
reg predic_taken_delay_1, btb_hit_delay_1;	// tai decode
reg predic_taken_delay_2, btb_hit_delay_2;  // tai execute

reg local_delay_1, global_delay_1; // tai decode
reg local_delay_2, global_delay_2; // tai execute

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        predic_taken_delay_1	<= 1'b0; btb_hit_delay_1 	<= 1'b0;
        predic_taken_delay_2 	<= 1'b0; btb_hit_delay_2	<= 1'b0;
		local_delay_1			<= 1'b0; global_delay_1		<= 1'b0;
		local_delay_2			<= 1'b0; global_delay_2		<= 1'b0;
    end else if (!halt) begin
        // Tang 1: fetch -> decode
		predic_taken_delay_1 	<= f_valid;
        btb_hit_delay_1			<= btb_valid_nxpc2;
		local_delay_1			<= local_pht_data_nxpc2[1];
		global_delay_1			<= global_pht_data_nxpc2[1];
		// Tang 2: decode -> execute. Phep OR gop d_valid vao, vi tang du phong
		// chuyen huong tre hon tang fetch mot chu ky -- ca hai cuoi cung deu co
		// nghia "front-end da bi chuyen huong cho lenh nay".
		predic_taken_delay_2    <= predic_taken_delay_1 | d_valid;
        btb_hit_delay_2			<= btb_hit_delay_1;
		local_delay_2			<= local_delay_1;
		global_delay_2			<= global_delay_1;
    end
end

wire predicted_taken = predic_taken_delay_2;   // front-end co bi chuyen huong?
wire pred_was_hit    = btb_hit_delay_2;        // co thong tin BTB de chuyen huong?
wire mispredict      = is_branch && (predicted_taken != branch_taken);

assign local_carry  = local_delay_2;
assign global_carry = global_delay_2;

// FLUSH (so bong bong) o execute
//   BTB truot -> RE:      1 bong bong (tang du phong da chuyen huong o decode)
//                KHONG RE: 2 bong bong
//   BTB trung -> 2 bong bong khi du doan sai, con lai 0
assign bpu_flush = (!is_branch)   ? 2'd0 :
                   (!pred_was_hit) ? (branch_taken ? 2'd1 : 2'd2) :
                   mispredict      ? 2'd2 : 2'd0;

// Dia chi HIEU CHINH: nhanh RE thi lay btb_target khi BTB trung, khong thi tinh
// lai pc+offset; nhanh KHONG RE thi di tiep pc+4.
wire        corr_valid = mispredict;
wire [31:0] corr_nxpc2 = branch_taken
                       ? (pred_was_hit ? btb_target_pc : (pc + branch_offset))
                       : (pc + 4);

// MUX ngo ra -- uu tien: hieu chinh > tang du phong > tang fetch
assign bpu_nxpc2_valid = (corr_valid || d_valid || f_valid);
assign bpu_nxpc2       = corr_valid ? corr_nxpc2 :
                         d_valid    ? d_nxpc2    :
                         f_valid    ? f_nxpc2    :
                                      32'b0      ;

endmodule
