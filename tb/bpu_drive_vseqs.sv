//==============================================================================
// Cac sequence: lai MOT chu ky day du 10 chan bang bpu_drive_seq.
//
//==============================================================================

//==============================================================================
// SEQ: bpu_branch_vseq --- mot nhanh: fetch thay opcode nhanh va execute giai
//   quyet no trong cung chu ky do.
//==============================================================================
class bpu_branch_vseq extends bpu_base_seq;

  bit [31:0] pc         = 32'h0000_0100;
  bit        taken      = 1'b1;
  bit [31:0] offset     = 32'h0000_0040;
  bit [31:0] btf        = 32'h0000_0040;
  bit [31:0] nxpc2      = 32'h0000_0108;   // chi dung khi auto_nxpc2 = 0
  bit        auto_nxpc2 = 1'b1;
  bit        deassert_after = 1'b1;        // 0 => cho phep nhanh o cac chu ky lien tiep

  `uvm_object_utils(bpu_branch_vseq)

  function new(string name="bpu_branch_vseq");
    super.new(name);
  endfunction

  virtual task body();
    bpu_drive_seq s;

    s = bpu_drive_seq::type_id::create("s1");
    s.pc_val       = pc;
    s.auto_nxpc    = 1'b1;
    s.auto_nxpc2   = auto_nxpc2;
    s.nxpc2_val    = nxpc2;
    s.is_branch_op = 1'b1;
    s.btf_val      = btf;
    s.flush_val    = 2'b00;
    s.halt_val     = 1'b0;

    s.is_branch_val = 1'b1;
    s.taken_val     = taken;
    s.offset_val    = offset;
    s.start(m_sequencer, this);

    if (deassert_after) begin
      s = bpu_drive_seq::type_id::create("s2");
      s.pc_val       = pc;
      s.auto_nxpc    = 1'b1;
      s.auto_nxpc2   = auto_nxpc2;
      s.nxpc2_val    = nxpc2;
      s.is_branch_op = 1'b1;
      s.btf_val      = btf;
      s.flush_val    = 2'b00;
      s.halt_val     = 1'b0;

      s.is_branch_val = 1'b0;
      s.taken_val     = 1'b0;
      s.offset_val    = 32'h0;
      s.start(m_sequencer, this);
    end
  endtask : body

endclass : bpu_branch_vseq



//==============================================================================
// SEQ: bpu_idle_vseq --- `count` chu ky khong lam doi trang thai nao: opcode
//   khong phai nhanh o fetch va is_branch=0 o execute. Dung de xa duong ong chuyen
//   huong giua hai phep do.
//
//==============================================================================
class bpu_idle_vseq extends bpu_base_seq;

  int unsigned count      = 4;
  bit [31:0]   nxpc2      = 32'h0000_0108;   // chi dung khi auto_nxpc2 = 0
  bit          auto_nxpc2 = 1'b1;
  bit          deassert_after = 1'b1;

  `uvm_object_utils(bpu_idle_vseq)

  function new(string name="bpu_idle_vseq");
    super.new(name);
  endfunction

  virtual task body();
    repeat (count) begin
      bpu_drive_seq s;

      s = bpu_drive_seq::type_id::create("s1");
      s.is_branch_op = 1'b0;
      s.opcode_val   = 7'b0010011;   // ADDI
      s.auto_nxpc    = 1'b1;
      s.auto_nxpc2   = auto_nxpc2;
      s.nxpc2_val    = nxpc2;
      s.flush_val    = 2'b00;
      s.halt_val     = 1'b0;

      s.is_branch_val = 1'b0;
      s.taken_val     = 1'b0;
      s.offset_val    = 32'h0;
      s.start(m_sequencer, this);

      if (deassert_after) begin
        // Chu ky thu hai cua vong: y het chu ky dau. is_branch da la 0 o ca hai,
        // dung nhu update_deassert cu gan 0 len tin hieu von da 0.
        s = bpu_drive_seq::type_id::create("s2");
        s.is_branch_op = 1'b0;
        s.opcode_val   = 7'b0010011;   // ADDI
        s.auto_nxpc    = 1'b1;
        s.auto_nxpc2   = auto_nxpc2;
        s.nxpc2_val    = nxpc2;
        s.flush_val    = 2'b00;
        s.halt_val     = 1'b0;

        s.is_branch_val = 1'b0;
        s.taken_val     = 1'b0;
        s.offset_val    = 32'h0;
        s.start(m_sequencer, this);
      end
    end
  endtask : body

endclass : bpu_idle_vseq
