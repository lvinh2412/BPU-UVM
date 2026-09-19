//------------------------------------------------------------------------------
// Cac sequence directed mot chu ky.
//
//------------------------------------------------------------------------------

//------------------------------------------------------------------------------
// SEQUENCE: bpu_drive_seq -- mot chu ky chi dinh day du ca 10 chan
//   auto_nxpc2 = 1 : nxpc2 = nxpc + 4, tuc fetch tuan tu
//   auto_nxpc2 = 0 : dung nxpc2_val, cho phep tra bang co chu dich
//------------------------------------------------------------------------------
class bpu_drive_seq extends bpu_base_seq;

  // --- phia fetch ---
  bit [31:0] pc_val       = 32'h0000_0100;
  bit [31:0] nxpc_val     = 32'h0000_0104;  // chi dung khi auto_nxpc = 0
  bit        auto_nxpc    = 1'b1;           // 1 => nxpc = pc_val + 4
  bit [31:0] nxpc2_val    = 32'h0000_0108;  // chi dung khi auto_nxpc2 = 0
  bit        auto_nxpc2   = 1'b1;           // 1 => nxpc2 = nxpc + 4
  bit        is_branch_op = 1'b1;           // 1 => fetch_opcode = BPU_OPCODE_BRANCH
  bit [6:0]  opcode_val   = 7'b0010011;     // chi dung khi is_branch_op = 0 (ADDI)
  bit [31:0] btf_val      = 32'h0000_0040;  // branch_target_fetch (nuoi tang du phong)
  bit [1:0]  flush_val    = 2'b00;          // flush_in: 0/1 san sang, 2 chua san sang
  bit        halt_val     = 1'b0;

  // --- phia execute ---
  bit        is_branch_val = 1'b1;          // 1 => chu ky nay co giai quyet mot nhanh
  bit        taken_val     = 1'b1;          // ket qua that cua nhanh
  bit [31:0] offset_val    = 32'h0000_0040; // branch_offset

  `uvm_object_utils(bpu_drive_seq)

  function new(string name="bpu_drive_seq");
    super.new(name);
  endfunction

  // ramdommize roi ghi de
  virtual task body();
    `uvm_create(req)

    if (!req.randomize() with {
          pc[1:0]          == 2'b00;
          nxpc[1:0]        == 2'b00;
          flush_in         != 2'b11;
          branch_offset[0] == 1'b0;
        })
      `uvm_error(get_type_name(), "randomize() failed in bpu_drive_seq")

    req.pc                  = pc_val;
    req.nxpc                = auto_nxpc ? (pc_val + 32'd4) : nxpc_val;
    req.nxpc2               = auto_nxpc2 ? (req.nxpc + 32'd4) : nxpc2_val;
    req.fetch_opcode        = is_branch_op ? BPU_OPCODE_BRANCH : opcode_val;
    req.branch_target_fetch = btf_val;
    req.flush_in            = flush_val;
    req.halt                = halt_val;

    req.is_branch           = is_branch_val;
    req.branch_taken        = taken_val;
    req.branch_offset       = {offset_val[31:1], 1'b0};

    `uvm_info(get_type_name(),
              $sformatf("drive: is_branch=%0d taken=%0d offset=%08h",
                        req.is_branch, req.branch_taken, req.branch_offset),
              UVM_HIGH)
    `uvm_send(req)
  endtask : body

endclass : bpu_drive_seq


//------------------------------------------------------------------------------
// SEQUENCE: bpu_opcode_sweep_seq
//   Quet du 128 gia tri opcode tai mot PC co dinh, con lai la nghi. Chi
//   7'b1100011 moi duoc tang du phong o decode coi la nhanh.
//
//------------------------------------------------------------------------------
class bpu_opcode_sweep_seq extends bpu_base_seq;

  bit [31:0] pc_val     = 32'h0000_0200;
  bit [31:0] nxpc2_val  = 32'h0000_0208;   // chi dung khi auto_nxpc2 = 0
  bit        auto_nxpc2 = 1'b1;            // 1 => nxpc2 = nxpc + 4

  `uvm_object_utils(bpu_opcode_sweep_seq)

  function new(string name="bpu_opcode_sweep_seq");
    super.new(name);
  endfunction

  virtual task body();
    for (int op = 0; op < 128; op++) begin
      `uvm_create(req)
      if (!req.randomize() with {
            pc[1:0]          == 2'b00;
            nxpc[1:0]        == 2'b00;
            flush_in         == 2'b00;
            branch_offset[0] == 1'b0;
          })
        `uvm_error(get_type_name(), "randomize() failed in opcode sweep")
      req.pc           = pc_val;
      req.nxpc         = pc_val + 32'd4;
      req.nxpc2        = auto_nxpc2 ? (req.nxpc + 32'd4) : nxpc2_val;
      req.fetch_opcode = op[6:0];
      req.halt         = 1'b0;
      req.flush_in     = 2'b00;
      req.branch_target_fetch = 32'h0;
      req.is_branch           = 1'b0;
      req.branch_taken        = 1'b0;
      req.branch_offset       = 32'h0;
      `uvm_send(req)
    end
  endtask : body

endclass : bpu_opcode_sweep_seq


//------------------------------------------------------------------------------
// SEQUENCE: bpu_flush_sweep_seq
//   Quet flush_in qua {0,1,2} voi opcode nhanh, de ca hai tang deu du dieu kien va
//   chi con fetch_ready quyet dinh chung co kich hoat hay khong.
//
//------------------------------------------------------------------------------
class bpu_flush_sweep_seq extends bpu_base_seq;

  bit [31:0] pc_val     = 32'h0000_0300;
  bit [31:0] nxpc2_val  = 32'h0000_0308;   // chi dung khi auto_nxpc2 = 0
  bit        auto_nxpc2 = 1'b1;            // 1 => nxpc2 = nxpc + 4

  `uvm_object_utils(bpu_flush_sweep_seq)

  function new(string name="bpu_flush_sweep_seq");
    super.new(name);
  endfunction

  virtual task body();
    bit [1:0] flush_vals[] = '{2'b00, 2'b01, 2'b10};
    foreach (flush_vals[i]) begin
      `uvm_create(req)
      if (!req.randomize() with {
            pc[1:0]          == 2'b00;
            nxpc[1:0]        == 2'b00;
            flush_in         != 2'b11;
            branch_offset[0] == 1'b0;
          })
        `uvm_error(get_type_name(), "randomize() failed in flush sweep")
      req.pc           = pc_val;
      req.nxpc         = pc_val + 32'd4;
      req.nxpc2        = auto_nxpc2 ? (req.nxpc + 32'd4) : nxpc2_val;
      req.fetch_opcode = BPU_OPCODE_BRANCH;
      req.flush_in     = flush_vals[i];
      req.halt         = 1'b0;
      // Phia execute NGHI -- xem ghi chu o bpu_opcode_sweep_seq.
      req.branch_target_fetch = 32'h0;
      req.is_branch           = 1'b0;
      req.branch_taken        = 1'b0;
      req.branch_offset       = 32'h0;
      `uvm_send(req)
    end
  endtask : body

endclass : bpu_flush_sweep_seq


//------------------------------------------------------------------------------
// SEQUENCE: bpu_idle_n_seq
//   N chu ky khong giai quyet nhanh nao, cac bang dung yen trong khi phia fetch
//   van chay.
//
//------------------------------------------------------------------------------
class bpu_idle_n_seq extends bpu_base_seq;

  int unsigned num = 1;   // so chu ky nghi can lai

  bit [31:0] pc_val = 32'h0000_0100;

  `uvm_object_utils(bpu_idle_n_seq)

  function new(string name="bpu_idle_n_seq");
    super.new(name);
  endfunction

  virtual task body();
    repeat (num) begin
      `uvm_create(req)
      if (!req.randomize() with {
            branch_offset[0] == 1'b0;
          })
        `uvm_error(get_type_name(), "randomize() failed in bpu_idle_n_seq")
      req.is_branch     = 1'b0;
      req.branch_taken  = 1'b0;
      req.branch_offset = 32'h0;

      req.pc                  = pc_val;
      req.nxpc                = pc_val + 32'd4;
      req.nxpc2               = pc_val + 32'd8;
      req.fetch_opcode        = 7'b0010011;   // ADDI, khong phai nhanh
      req.branch_target_fetch = 32'h0;
      req.flush_in            = 2'b00;
      req.halt                = 1'b0;
      `uvm_send(req)
    end
  endtask : body

endclass : bpu_idle_n_seq
