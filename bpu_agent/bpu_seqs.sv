//------------------------------------------------------------------------------
// Thu vien sequence tien ich cua bpu_agent.
//
//------------------------------------------------------------------------------

//------------------------------------------------------------------------------
//
// SEQUENCE: bpu_base_seq
//
// Vai tro: giu objection suot doi song cua sequence, de run phase khong ket thuc
// khi kich thich con dang duoc lai. Moi sequence trong tep deu ke thua.
//
//------------------------------------------------------------------------------
class bpu_base_seq extends uvm_sequence#(bpu_item);

  `uvm_object_utils(bpu_base_seq)

  function new(string name="bpu_base_seq");
    super.new(name);
  endfunction

  task pre_body();
    uvm_phase phase;
    `ifdef UVM_VERSION_1_2
      phase = get_starting_phase();
    `else
      phase = starting_phase;
    `endif
    if (phase != null) begin
      phase.raise_objection(this, get_type_name());
      `uvm_info(get_type_name(), "raise objection", UVM_MEDIUM)
    end
  endtask : pre_body

  task post_body();
    uvm_phase phase;
    `ifdef UVM_VERSION_1_2
      phase = get_starting_phase();
    `else
      phase = starting_phase;
    `endif
    if (phase != null) begin
      phase.drop_objection(this, get_type_name());
      `uvm_info(get_type_name(), "drop objection", UVM_MEDIUM)
    end
  endtask : post_body

endclass : bpu_base_seq

//------------------------------------------------------------------------------
//
// SEQUENCE: bpu_5_items
//
//  Nam item ngau nhien hoan toan -- phep thu nhanh xem agent co lai duoc khong.
//
//
//------------------------------------------------------------------------------
class bpu_5_items extends bpu_base_seq;

  `uvm_object_utils(bpu_5_items)

  function new(string name="bpu_5_items");
    super.new(name);
  endfunction

  virtual task body();
    `uvm_info(get_type_name(), "Executing bpu_5_items sequence", UVM_LOW)
    repeat(5)
      `uvm_do(req)
  endtask

endclass : bpu_5_items

//------------------------------------------------------------------------------
//
// SEQUENCE: bpu_idle_seq - mot chu ky nghi. Dung de gian cach cac nhanh, cho duong
// ong chuyen huong xa het giua hai phep do, va khong giai quyet nhanh nao nen cac
// bang dung yen.
//
//------------------------------------------------------------------------------
class bpu_idle_seq extends bpu_base_seq;

  `uvm_object_utils(bpu_idle_seq)

  function new(string name="bpu_idle_seq");
    super.new(name);
  endfunction

  virtual task body();
    `uvm_info(get_type_name(), "Executing BPU_IDLE_SEQ", UVM_LOW)
    `uvm_do_with(req, {req.nxpc == req.pc + 32'd4;
                       req.fetch_opcode != BPU_OPCODE_BRANCH;
                       req.halt == 1'b0;
                       req.flush_in == 2'b00;
                       req.is_branch == 1'b0;
                       req.branch_taken == 1'b0;
                       req.branch_offset == 32'h0;})
  endtask

endclass : bpu_idle_seq

//------------------------------------------------------------------------------
//
// SEQUENCE: bpu_branch_fetch_seq - mot chu ky co opcode bao "day la nhanh", tuc
// dieu kien de tang du phong o decode co the kich hoat.
//
//------------------------------------------------------------------------------
class bpu_branch_fetch_seq extends bpu_base_seq;

  `uvm_object_utils(bpu_branch_fetch_seq)

  function new(string name="bpu_branch_fetch_seq");
    super.new(name);
  endfunction

  virtual task body();
    `uvm_info(get_type_name(), "Executing BPU_BRANCH_FETCH_SEQ", UVM_LOW)
    `uvm_do_with(req, {req.fetch_opcode == BPU_OPCODE_BRANCH;
                       req.branch_target_fetch != 32'h0;
                       req.halt == 1'b0;
                       req.flush_in == 2'b00;
                       req.is_branch == 1'b0;
                       req.branch_taken == 1'b0;
                       req.branch_offset == 32'h0;})
  endtask

endclass : bpu_branch_fetch_seq

//------------------------------------------------------------------------------
//
// SEQUENCE: bpu_three_branches_seq - ba item nhanh lien tiep
//
//------------------------------------------------------------------------------
class bpu_three_branches_seq extends bpu_base_seq;

  `uvm_object_utils(bpu_three_branches_seq)

  bpu_branch_fetch_seq br_seq;

  function new(string name="bpu_three_branches_seq");
    super.new(name);
  endfunction

  virtual task body();
    `uvm_info(get_type_name(), "Executing BPU_THREE_BRANCHES_SEQ", UVM_LOW)
    repeat (3)
    `uvm_do(br_seq)
  endtask

endclass : bpu_three_branches_seq

//------------------------------------------------------------------------------
//
// SEQUENCE: bpu_halt_seq - mot chu ky co halt, phai dong bang ca cac bang lan
// duong ong carry-down.
//
//------------------------------------------------------------------------------
class bpu_halt_seq extends bpu_base_seq;

  `uvm_object_utils(bpu_halt_seq)

  function new(string name="bpu_halt_seq");
    super.new(name);
  endfunction

  virtual task body();
    `uvm_info(get_type_name(), "Executing BPU_HALT_SEQ", UVM_LOW)
    `uvm_create(req)
    // Phia execute NGHI -- xem ghi chu o bpu_branch_fetch_seq.
    assert(req.randomize() with {nxpc == pc + 32'd4;
                                 fetch_opcode != BPU_OPCODE_BRANCH;
                                 flush_in == 2'b00;
                                 is_branch == 1'b0;
                                 branch_taken == 1'b0;
                                 branch_offset == 32'h0;});
    req.halt = 1'b1;       // dat sau randomize: o day halt khong phai truong ngau nhien
    `uvm_send(req)
  endtask

endclass : bpu_halt_seq

//------------------------------------------------------------------------------
//
// SEQUENCE: bpu_branch_taken_seq - giai quyet mot nhanh voi ket qua RE
//
//------------------------------------------------------------------------------
class bpu_branch_taken_seq extends bpu_base_seq;

  // Phia fetch NGHI o dia chi nay -- ban hai-UVC lai phia fetch bang mot sequence
  // chay song song; voi item hop nhat thi chinh lop nay phai dat.
  bit [31:0] pc_val = 32'h0000_0100;

  `uvm_object_utils(bpu_branch_taken_seq)

  function new(string name="bpu_branch_taken_seq");
    super.new(name);
  endfunction

  virtual task body();
    `uvm_info(get_type_name(), "Executing BPU_BRANCH_TAKEN_SEQ", UVM_LOW)
    `uvm_do_with(req, {req.is_branch == 1'b1;
                       req.branch_taken == 1'b1;
                       req.branch_offset != 32'h0;
                       req.pc == pc_val;
                       req.nxpc == pc_val + 32'd4;
                       req.nxpc2 == pc_val + 32'd8;
                       req.fetch_opcode == 7'b0010011;   // ADDI, khong phai nhanh
                       req.branch_target_fetch == 32'h0;
                       req.flush_in == 2'b00;
                       req.halt == 1'b0;})
  endtask

endclass : bpu_branch_taken_seq

//------------------------------------------------------------------------------
//
// SEQUENCE: bpu_branch_nottaken_seq - giai quyet mot nhanh KHONG RE
//
//------------------------------------------------------------------------------
class bpu_branch_nottaken_seq extends bpu_base_seq;

  // Phia fetch NGHI -- xem ghi chu o bpu_branch_taken_seq.
  bit [31:0] pc_val = 32'h0000_0100;

  `uvm_object_utils(bpu_branch_nottaken_seq)

  function new(string name="bpu_branch_nottaken_seq");
    super.new(name);
  endfunction

  virtual task body();
    `uvm_info(get_type_name(), "Executing BPU_BRANCH_NOTTAKEN_SEQ", UVM_LOW)
    `uvm_do_with(req, {req.is_branch == 1'b1;
                       req.branch_taken == 1'b0;
                       req.branch_offset != 32'h0;
                       req.pc == pc_val;
                       req.nxpc == pc_val + 32'd4;
                       req.nxpc2 == pc_val + 32'd8;
                       req.fetch_opcode == 7'b0010011;   // ADDI, khong phai nhanh
                       req.branch_target_fetch == 32'h0;
                       req.flush_in == 2'b00;
                       req.halt == 1'b0;})
  endtask

endclass : bpu_branch_nottaken_seq

//------------------------------------------------------------------------------
//
// SEQUENCE: bpu_three_taken_seq - ba nhanh RE lien tiep
//
//------------------------------------------------------------------------------
class bpu_three_taken_seq extends bpu_base_seq;

  `uvm_object_utils(bpu_three_taken_seq)

  bpu_branch_taken_seq taken_seq;

  function new(string name="bpu_three_taken_seq");
    super.new(name);
  endfunction

  virtual task body();
    `uvm_info(get_type_name(), "Executing BPU_THREE_TAKEN_SEQ", UVM_LOW)
    repeat (3)
    `uvm_do(taken_seq)
  endtask

endclass : bpu_three_taken_seq

//------------------------------------------------------------------------------
//
// SEQUENCE: bpu_alternating_seq - N nhanh xen ke RE, KHONG RE, RE, ...
//
//------------------------------------------------------------------------------
class bpu_alternating_seq extends bpu_base_seq;

  // Phia fetch NGHI -- xem ghi chu o bpu_branch_taken_seq.
  bit [31:0] pc_val = 32'h0000_0100;

  `uvm_object_utils(bpu_alternating_seq)

  function new(string name="bpu_alternating_seq");
    super.new(name);
  endfunction

  virtual task body();
    bit cur_taken;
    `uvm_info(get_type_name(), "Executing BPU_ALTERNATING_SEQ", UVM_LOW)
    cur_taken = 1'b1;
    for (int i = 0; i < 10; i++) begin
      `uvm_create(req)
      assert(req.randomize() with {is_branch == 1'b1;
                                   branch_offset != 32'h0;
                                   pc == pc_val;
                                   nxpc == pc_val + 32'd4;
                                   nxpc2 == pc_val + 32'd8;
                                   fetch_opcode == 7'b0010011;
                                   branch_target_fetch == 32'h0;
                                   flush_in == 2'b00;
                                   halt == 1'b0;});
      req.branch_taken = cur_taken;   // override after randomize
      `uvm_send(req)
      cur_taken = ~cur_taken;
    end
  endtask
endclass : bpu_alternating_seq

//------------------------------------------------------------------------------
//
// SEQUENCE: bpu_rnd_seq
//
//------------------------------------------------------------------------------

class bpu_rnd_seq extends bpu_base_seq;

  `uvm_object_utils(bpu_rnd_seq)

  rand int count;

  constraint count_limit { count inside {[1:10]}; }

  function new(string name="bpu_rnd_seq");
    super.new(name);
  endfunction

  virtual task body();
    `uvm_info(get_type_name(), $sformatf("Executing BPU_RND_SEQ %0d times...", count), UVM_LOW)
    repeat (count) begin
      `uvm_do(req)
    end
  endtask

endclass : bpu_rnd_seq

//------------------------------------------------------------------------------
//
// SEQUENCE: six_bpu_seq
//
//------------------------------------------------------------------------------

class six_bpu_seq extends bpu_base_seq;

  `uvm_object_utils(six_bpu_seq)

  bpu_rnd_seq bss;

  function new(string name="six_bpu_seq");
    super.new(name);
  endfunction

  virtual task body();
    `uvm_info(get_type_name(), "Executing SIX_BPU_SEQ" , UVM_LOW)
    `uvm_do_with(bss, {count==6;})
  endtask

endclass : six_bpu_seq

//------------------------------------------------------------------------------
//
// SEQUENCE: bpu_exhaustive_seq
//
//------------------------------------------------------------------------------

class bpu_exhaustive_seq extends bpu_base_seq;

  `uvm_object_utils(bpu_exhaustive_seq)

  bpu_idle_seq              bidle;
  bpu_branch_fetch_seq      bbr;
  bpu_three_branches_seq    bthree;
  bpu_halt_seq              bhalt;
  bpu_branch_taken_seq      btaken;
  bpu_branch_nottaken_seq   bntaken;
  bpu_three_taken_seq       bthreetk;
  bpu_alternating_seq       balt;
  six_bpu_seq               bsix;

  function new(string name="bpu_exhaustive_seq");
    super.new(name);
  endfunction

  virtual task body();
    `uvm_info(get_type_name(), "Executing BPU_EXHAUSTIVE_SEQ" , UVM_LOW)
    `uvm_do(bidle)
    `uvm_do(bbr)
    `uvm_do(bthree)
    `uvm_do(bhalt)
    `uvm_do(btaken)
    `uvm_do(bntaken)
    `uvm_do(bthreetk)
    `uvm_do(balt)
    `uvm_do(bsix)
  endtask

endclass : bpu_exhaustive_seq

//------------------------------------------------------------------------------
//
// SEQUENCE: bpu_pc_sweep_seq - cac PC lien tiep, con lai la nghi. Tien de nap
// nhieu o BTB hoac de thu phan giai ma chi muc pc[11:2].
//
//------------------------------------------------------------------------------

class bpu_pc_sweep_seq extends bpu_base_seq;

  `uvm_object_utils(bpu_pc_sweep_seq)

  rand bit [31:0] pc_start;
  rand int        pc_count;

  constraint pc_start_aligned { pc_start[1:0] == 2'b00; }
  constraint pc_count_limit   { pc_count inside {[1:32]}; }

  function new(string name="bpu_pc_sweep_seq");
    super.new(name);
  endfunction

  virtual task body();
    bit [31:0] cur_pc;
    `uvm_info(get_type_name(),
              $sformatf("Executing BPU_PC_SWEEP_SEQ from 0x%08h, %0d items",
                        pc_start, pc_count), UVM_LOW)
    cur_pc = pc_start;
    for (int i = 0; i < pc_count; i++) begin
      `uvm_create(req)
      // Phia execute NGHI -- xem ghi chu o bpu_branch_fetch_seq.
      assert(req.randomize() with {fetch_opcode != BPU_OPCODE_BRANCH;
                                   halt == 1'b0;
                                   flush_in == 2'b00;
                                   is_branch == 1'b0;
                                   branch_taken == 1'b0;
                                   branch_offset == 32'h0;});
      req.pc   = cur_pc;
      req.nxpc = cur_pc + 32'd4;
      `uvm_send(req)
      cur_pc += 32'd4;
    end
  endtask

endclass : bpu_pc_sweep_seq

//------------------------------------------------------------------------------
//
// SEQUENCE: bpu_all_taken_seq - N nhanh RE lien tiep, du de day bo dem PHT len ST
// va lam on dinh cac thanh ghi lich su.
//
//------------------------------------------------------------------------------

class bpu_all_taken_seq extends bpu_base_seq;

  // Phia fetch NGHI -- xem ghi chu o bpu_branch_taken_seq.
  bit [31:0] pc_val = 32'h0000_0100;

  `uvm_object_utils(bpu_all_taken_seq)

  rand int taken_count;

  constraint taken_count_limit { taken_count inside {[1:32]}; }

  function new(string name="bpu_all_taken_seq");
    super.new(name);
  endfunction

  virtual task body();
    `uvm_info(get_type_name(),
              $sformatf("Executing BPU_ALL_TAKEN_SEQ, %0d taken branches",
                        taken_count), UVM_LOW)
    for (int i = 0; i < taken_count; i++) begin
      `uvm_create(req)
      assert(req.randomize() with {is_branch == 1'b1;
                                   branch_taken == 1'b1;
                                   branch_offset != 32'h0;
                                   pc == pc_val;
                                   nxpc == pc_val + 32'd4;
                                   nxpc2 == pc_val + 32'd8;
                                   fetch_opcode == 7'b0010011;
                                   branch_target_fetch == 32'h0;
                                   flush_in == 2'b00;
                                   halt == 1'b0;});
      `uvm_send(req)
    end
  endtask

endclass : bpu_all_taken_seq
