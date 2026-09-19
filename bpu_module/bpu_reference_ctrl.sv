//------------------------------------------------------------------------------
// FILE: bpu_reference_ctrl.sv    `include VAO trong than class bpu_reference
//
// Vai tro: soi guong bpu_ctrl.v -- hai tang chuyen huong, ma flush, duong hieu
//   chinh o execute va MUX ngo ra.
//
//   compute_flush() va compute_correction() NHAN predicted_taken/pred_was_hit lam
//   tham so chu khong doc lai bang: hai gia tri do di ra tu duong carry-down va
//   thuoc ve nhanh dang o execute, thuong khac voi cai bang dang chua luc nay.
//
//   Phai `include SAU bpu_reference_state.sv va bpu_reference_predictor.sv.
//------------------------------------------------------------------------------

//==========================================================================
// Cac ham tien tinh
//==========================================================================
function automatic bit fetch_is_branch(bit [6:0] opcode);
   fetch_is_branch = (opcode == BPU_OPCODE_BRANCH);
endfunction

function automatic bit fetch_ready(bit [1:0] flush_in);
   fetch_ready = ((flush_in == 2'd0) || (flush_in == 2'd1));
endfunction

//==========================================================================
// Tang fetch -- doc theo chi muc nxpc2
//   f_valid = btb_valid_nxpc2 && predict_taken_nxpc2 && fetch_ready
//   f_nxpc2 = btb_target_nxpc2
//==========================================================================
function automatic void compute_fetch_tier(
   input  bit [31:0] nxpc2,
   input  bit [1:0]  flush_in,
   output bit        f_valid,
   output bit [31:0] f_nxpc2
);
   f_valid = read_btb_valid_nxpc2(nxpc2) && predict_taken_nxpc2(nxpc2) && fetch_ready(flush_in);
   f_nxpc2 = read_btb_target_nxpc2(nxpc2);
endfunction

//==========================================================================
// Tang du phong o decode -- doc theo chi muc nxpc. Bat cac nhanh ma tang fetch
// truot BTB, nho co opcode chi den o decode.
//   d_valid = fetch_is_branch && !btb_valid_nxpc && fetch_ready
//   d_nxpc2 = nxpc + branch_target_fetch
//==========================================================================
function automatic void compute_backstop(
   input  bit [31:0] nxpc,
   input  bit [6:0]  fetch_opcode,
   input  bit [1:0]  flush_in,
   input  bit [31:0] branch_target_fetch,
   output bit        d_valid,
   output bit [31:0] d_nxpc2
);
   d_valid = fetch_is_branch(fetch_opcode) && !read_btb_valid_nxpc(nxpc) && fetch_ready(flush_in);
   d_nxpc2 = nxpc + branch_target_fetch;
endfunction

//==========================================================================
// Flush, tuc so bong bong loi phai bo
//   khong phai nhanh -> 0
//   BTB truot        -> RE: 1 (tang du phong da chuyen huong), KHONG RE: 2
//   BTB trung        -> 2 khi du doan sai, con lai 0
//==========================================================================
function automatic bit [1:0] compute_flush(
   input bit is_branch,
   input bit pred_was_hit,
   input bit predicted_taken,
   input bit branch_taken
);
   if (!is_branch)
      compute_flush = 2'd0;
   else if (!pred_was_hit)
      compute_flush = branch_taken ? 2'd1 : 2'd2;
   else
      compute_flush = (predicted_taken != branch_taken) ? 2'd2 : 2'd0;
endfunction

//==========================================================================
// Hieu chinh o execute
//   corr_valid = is_branch && (predicted_taken != branch_taken)
//   corr_nxpc2 = branch_taken ? (pred_was_hit ? btb_target_pc : pc+offset)
//                             : pc + 4
// Luu y corr_nxpc2 van duoc tinh khi corr_valid = 0; MUX se bo di.
//==========================================================================
function automatic void compute_correction(
   input  bit [31:0] pc,
   input  bit        branch_taken,
   input  bit [31:0] branch_offset,
   input  bit        pred_was_hit,
   input  bit        predicted_taken,
   input  bit        is_branch,
   output bit        corr_valid,
   output bit [31:0] corr_nxpc2
);
   bit mispredict;
   mispredict = is_branch && (predicted_taken != branch_taken);
   corr_valid = mispredict;
   if (branch_taken)
      corr_nxpc2 = pred_was_hit ? read_btb_target_pc(pc) : (pc + branch_offset);
   else
      corr_nxpc2 = pc + 32'd4;
endfunction

//==========================================================================
// MUX ngo ra -- uu tien: hieu chinh > tang du phong > tang fetch
//==========================================================================
function automatic void compute_output_mux(
   input  bit        corr_valid,
   input  bit [31:0] corr_nxpc2,
   input  bit        d_valid,
   input  bit [31:0] d_nxpc2,
   input  bit        f_valid,
   input  bit [31:0] f_nxpc2,
   output bit        bpu_nxpc2_valid,
   output bit [31:0] bpu_nxpc2
);
   bpu_nxpc2_valid = corr_valid || d_valid || f_valid;
   if      (corr_valid) bpu_nxpc2 = corr_nxpc2;
   else if (d_valid)    bpu_nxpc2 = d_nxpc2;
   else if (f_valid)    bpu_nxpc2 = f_nxpc2;
   else                 bpu_nxpc2 = 32'd0;
endfunction
