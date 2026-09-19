//------------------------------------------------------------------------------
// FILE: tests/hyb_btb_tests.sv
//
// Muc kiem chung theo BPU_Testplan_Hybrid_44.xlsx / sheet TestCase:
//   3.1 btb_write_and_target   [A] gop btb_write + btb_alias + btb_target
//                                   + btb_target_zero
//   3.2 btb_read_triple_port   [B] gop btb_dual_port + phan doc cua btb_revisit
//   3.3 btb_rw_all             [A] giu nguyen, offset doi theo sheet
//
//------------------------------------------------------------------------------

`ifndef BPU_PHT_STATES
`define BPU_PHT_STATES
  `define SNT 2'b00
  `define WNT 2'b01
  `define WT  2'b10
  `define ST  2'b11
`endif


//==============================================================================
// BASE dung chung cho cac muc trong tep nay va cac tep ke thua no.
//   - chk()      : phat uvm_error co gan NHAN PHA hien tai
//   - phase_of() : dat nhan pha
//   - drive_branch()/idle_cycles() : kich thich mot nhanh / n chu ky nghi
//==============================================================================
class hyb_base_test extends bpu_base_test;

  string test_label = "HYB";
  string cur_phase  = "-";
  int    err        = 0;
  int    err_in_phase[string];

  function new(string name, uvm_component parent); super.new(name, parent); endfunction

  protected function void select_clock();
    uvm_config_wrapper::set(this,
        "tb.clock_and_reset.agent.sequencer.run_phase",
        "default_sequence", clk10_rst5_seq::get_type());
  endfunction

  // Dat nhan pha. Moi loi phat ra sau day se mang nhan nay.
  protected function void phase_of(string p);
    cur_phase = p;
    if (!err_in_phase.exists(p)) err_in_phase[p] = 0;
    `uvm_info(test_label, $sformatf(">>> PHA [%s]", p), UVM_LOW)
  endfunction

  protected function void chk(bit cond, string msg);
    if (!cond) begin
      err++;
      err_in_phase[cur_phase]++;
      `uvm_error(test_label, $sformatf("[%s] %s", cur_phase, msg))
    end
  endfunction

  protected task automatic drive_branch(bit [31:0] pc, bit tk,
                                        bit [31:0] offset = 32'h40);
    bpu_branch_vseq v;
    v = bpu_branch_vseq::type_id::create($sformatf("b_%0t", $time));
    v.pc = pc; v.taken = tk; v.offset = offset; v.btf = offset;
    v.start(tb.bpu.tx_agent.sequencer);
    #1ns;
  endtask

  protected function void scoreboard_not_applicable(string why);
    tb.module_env.scoreboard.set_report_severity_override(UVM_ERROR, UVM_INFO);
    `uvm_info(test_label,
      {"scoreboard KHONG ap dung cho muc nay (ep trang thai noi bo bang backdoor): ", why},
      UVM_NONE)
  endfunction

  protected task automatic idle_cycles(int n);
    bpu_idle_vseq vi;
    vi = bpu_idle_vseq::type_id::create($sformatf("i_%0t", $time));
    vi.count = n; vi.start(tb.bpu.tx_agent.sequencer);
    // #1ns thay cho #5ns -- xem giai thich o drive_branch() ben tren.
    #1ns;
  endtask

  function void report_phase(uvm_phase phase);
    string s;
    super.report_phase(phase);
    s = "";
    foreach (err_in_phase[p])
      s = {s, $sformatf("    pha %-24s : %0d loi\n", p, err_in_phase[p])};
    if (err == 0)
      `uvm_info(test_label, $sformatf("PASSED\n%s", s), UVM_NONE)
    else
      `uvm_error(test_label, $sformatf("FAILED: %0d loi\n%s", err, s))
  endfunction

endclass : hyb_base_test


//==============================================================================
// 3.1 btb_write_and_target
//
// Sheet -- Test Flow: ghi mot entry roi ghi de bang offset khac; chay 100 chu ky
//   voi is_branch=0; quet bon loai offset (tien, lui, bang 0, va offset gay tran
//   32 bit cho dich bang 0); ghi hai PC trung pc[11:2] voi offset khac nhau.
// Sheet -- Pass: is_branch=1 -> btb_target = pc + branch_offset va btb_valid=1
//   trong ca bon loai offset, ke ca dich bang 32'h0. is_branch=0 -> khong ghi.
//   PC trung chi muc -> lan ghi sau thang.
// RTL Ref: bpu_predictor.v ; bpu_reg.v
//==============================================================================
class btb_write_and_target_test extends hyb_base_test;
  `uvm_component_utils(btb_write_and_target_test)
  function new(string name, uvm_component parent); super.new(name, parent); endfunction

  function void build_phase(uvm_phase phase);
    test_label = "TEST_3_1 (btb_write_and_target)";
    select_clock();
    super.build_phase(phase);
  endfunction

  task run_phase(uvm_phase phase);
    bpu_backdoor bd;
    super.run_phase(phase);
    bd = tb.module_env.backdoor;
    phase.raise_objection(this, "3_1");
    #100ns;

    //---- PHA A: ghi roi ghi de tai cung mot PC -----------------------------
    phase_of("A_write_overwrite");
    drive_branch(32'h0000_0100, 1'b1, 32'h40);          // btb[64] = 0x140
    chk(bd.read_btb_valid(64)  === 1'b1,          "btb_valid[64] != 1 sau lan ghi dau");
    chk(bd.read_btb_target(64) === 32'h0000_0140,
        $sformatf("btb_target[64]=0x%08h, ky vong 0x140 (pc+offset)", bd.read_btb_target(64)));
    drive_branch(32'h0000_0100, 1'b1, 32'h80);          // ghi de -> 0x180
    chk(bd.read_btb_target(64) === 32'h0000_0180,
        $sformatf("btb_target[64]=0x%08h, ky vong 0x180 (ghi de)", bd.read_btb_target(64)));

    //---- PHA B: 100 chu ky is_branch=0 -> khong ghi ------------------------
    phase_of("B_no_write_100cyc");
    idle_cycles(100);
    chk(bd.read_btb_valid(64)  === 1'b1,          "btb_valid[64] bi xoa trong 100 chu ky nghi");
    chk(bd.read_btb_target(64) === 32'h0000_0180,
        $sformatf("btb_target[64]=0x%08h doi trong luc nghi, ky vong giu 0x180", bd.read_btb_target(64)));
    chk(bd.read_btb_valid(1000) === 1'b0,         "btb_valid[1000] != 0: chu ky nghi da ghi nham entry");

    //---- PHA C: bon loai offset --------------------------------------------
    phase_of("C_four_offset_kinds");
    // (1) tien
    drive_branch(32'h0000_0200, 1'b1, 32'h0000_0040);
    chk(bd.read_btb_valid(128)  === 1'b1,         "offset tien: btb_valid[128] != 1");
    chk(bd.read_btb_target(128) === 32'h0000_0240,
        $sformatf("offset tien: btb_target[128]=0x%08h, ky vong 0x240", bd.read_btb_target(128)));
    // (2) lui (bu hai)
    drive_branch(32'h0000_0300, 1'b1, 32'hFFFF_FFC0);
    chk(bd.read_btb_valid(192)  === 1'b1,         "offset lui: btb_valid[192] != 1");
    chk(bd.read_btb_target(192) === 32'h0000_02C0,
        $sformatf("offset lui: btb_target[192]=0x%08h, ky vong 0x2C0", bd.read_btb_target(192)));
    // (3) bang 0
    drive_branch(32'h0000_0600, 1'b1, 32'h0000_0000);
    chk(bd.read_btb_valid(384)  === 1'b1,         "offset 0: btb_valid[384] != 1");
    chk(bd.read_btb_target(384) === 32'h0000_0600,
        $sformatf("offset 0: btb_target[384]=0x%08h, ky vong 0x600", bd.read_btb_target(384)));
    // (4) tran 32 bit -> dich bang 0. pc=0x400, offset=-0x400
    drive_branch(32'h0000_0400, 1'b1, 32'hFFFF_FC00);
    chk(bd.read_btb_valid(256)  === 1'b1,
        "offset tran: btb_valid[256] != 1 (entry co dich 0 VAN phai hop le)");
    chk(bd.read_btb_target(256) === 32'h0000_0000,
        $sformatf("offset tran: btb_target[256]=0x%08h, ky vong 0x0 (cat 32 bit)", bd.read_btb_target(256)));

    //---- PHA D: hai PC trung chi muc pc[11:2] ------------------------------
    phase_of("D_index_alias");
    drive_branch(32'h0000_0100, 1'b1, 32'h40);          // idx 64 -> 0x140
    chk(bd.read_btb_target(64) === 32'h0000_0140,
        $sformatf("alias buoc 1: btb_target[64]=0x%08h, ky vong 0x140", bd.read_btb_target(64)));
    drive_branch(32'h0000_1100, 1'b1, 32'h80);          // 0x1100 cung idx 64
    chk(bd.read_btb_target(64) === 32'h0000_1180,
        $sformatf("alias buoc 2: btb_target[64]=0x%08h, ky vong 0x1180 (lan ghi sau thang)",
                  bd.read_btb_target(64)));

    phase.drop_objection(this, "3_1");
  endtask
endclass : btb_write_and_target_test


//==============================================================================
// 3.2 btb_read_triple_port
//
// Sheet -- Test Flow: nap truoc cac entry; dat pc, nxpc va nxpc2 tro ba chi muc
//   khac nhau trong cung mot chu ky; doc truoc va sau canh len clk; cho dia chi
//   da ghi xuat hien lai o nxpc2.
// Sheet -- Pass: btb_valid doc doc lap tai pc, nxpc va nxpc2, cap nhat to hop
//   tuc thi; btb_target chi co o pc va nxpc2 (KHONG ton tai btb_target_nxpc);
//   doc trong luc ghi tra ve gia tri cu; cong nxpc2 doc dung target da luu nen
//   f_valid co the tich cuc.
// RTL Ref: bpu_reg.v
//
// GHI CHU DOC TIN HIEU: btb_valid_* va btb_target_* la to hop THUAN tu dia chi
// dang lai, khong phu thuoc carry-down, nen doc truc tiep sau khi lai la hop le

//==============================================================================
class btb_read_triple_port_test extends hyb_base_test;
  `uvm_component_utils(btb_read_triple_port_test)
  function new(string name, uvm_component parent); super.new(name, parent); endfunction

  function void build_phase(uvm_phase phase);
    test_label = "TEST_3_2 (btb_read_triple_port)";
    select_clock();
    super.build_phase(phase);
  endfunction

  local function bit rd_bit(string sig);
    uvm_hdl_data_t v;
    if (!uvm_hdl_read({"bpu_hw_top.dut.", sig}, v))
      `uvm_error(test_label, $sformatf("khong doc duoc bpu_hw_top.dut.%s", sig))
    return v[0];
  endfunction

  local function bit [31:0] rd_word(string sig);
    uvm_hdl_data_t v;
    if (!uvm_hdl_read({"bpu_hw_top.dut.", sig}, v))
      `uvm_error(test_label, $sformatf("khong doc duoc bpu_hw_top.dut.%s", sig))
    return v[31:0];
  endfunction

  task run_phase(uvm_phase phase);
    bpu_backdoor   bd;
    uvm_hdl_data_t dummy;
    bit [31:0] T64, T192;
    int k;
    super.run_phase(phase);
    bd = tb.module_env.backdoor;
    phase.raise_objection(this, "3_2");
    #100ns;

    //------------------------------------------------------------------------
    // HUAN LUYEN (chi lam MOT LAN, o day) qua duong cap nhat THAT cua DUT --
    // khong ep bang backdoor, nen reference model bam sat.
    //   0x100 (idx 64 ) : 24 nhanh taken, offset 0x40 -> btb_target = 0x140 va
    //                     lich su cuc bo bao hoa -> du doan T tai nxpc2 = 0x100
    //   0x300 (idx 192) : 1 nhanh taken, offset 0x40  -> btb_target = 0x340
    //   0x200 (idx 128) : KHONG cham -> btb_valid = 0
    //
    // TU DAY TRO DI KHONG CHAY THEM SEQUENCE NAO. Mot khi da ep NET giao dien,
    // hoat dong cua predict driver se tranh chap voi lenh ep. Moi lenh ep deu
    // canh theo negedge de so chu ky di qua la xac dinh.
    //------------------------------------------------------------------------
    T64  = 32'h0000_0140;
    T192 = 32'h0000_0340;
    for (k = 0; k < 24; k++) drive_branch(32'h0000_0100, 1'b1, 32'h40);
    drive_branch(32'h0000_0300, 1'b1, 32'h40);

    //---- PHA A: ba cong doc doc lap trong CUNG mot chu ky ------------------
    phase_of("A_three_ports_independent");
    chk(bd.read_btb_valid(64)  === 1'b1, "chuan bi: btb_valid[64] phai = 1");
    chk(bd.read_btb_valid(128) === 1'b0, "chuan bi: btb_valid[128] phai = 0");
    chk(bd.read_btb_valid(192) === 1'b1, "chuan bi: btb_valid[192] phai = 1");

    @(negedge bpu_hw_top.clock);
    bd.force_predict_inputs(.pc(32'h0000_0100),      // idx 64  hop le
                            .nxpc(32'h0000_0200),    // idx 128 khong hop le
                            .fetch_opcode(7'b0010011),
                            .branch_target_fetch(32'h0),
                            .flush_in(2'b00), .halt(1'b0),
                            .nxpc2(32'h0000_0300));  // idx 192 hop le
    @(posedge bpu_hw_top.clock);
    chk(rd_bit("btb_valid_pc")    === 1'b1, "btb_valid_pc != 1 (idx 64 hop le)");
    chk(rd_bit("btb_valid_nxpc")  === 1'b0, "btb_valid_nxpc != 0 (idx 128 khong hop le)");
    chk(rd_bit("btb_valid_nxpc2") === 1'b1, "btb_valid_nxpc2 != 1 (idx 192 hop le)");
    chk(rd_word("btb_target_pc")    === T64,
        $sformatf("btb_target_pc=0x%08h, ky vong 0x%08h", rd_word("btb_target_pc"), T64));
    chk(rd_word("btb_target_nxpc2") === T192,
        $sformatf("btb_target_nxpc2=0x%08h, ky vong 0x%08h", rd_word("btb_target_nxpc2"), T192));

    // Doi cho ba dia chi -> ba cong phai doi theo TUC THI (to hop)
    @(negedge bpu_hw_top.clock);
    bd.force_predict_inputs(.pc(32'h0000_0200),      // idx 128 khong hop le
                            .nxpc(32'h0000_0300),    // idx 192 hop le
                            .fetch_opcode(7'b0010011),
                            .branch_target_fetch(32'h0),
                            .flush_in(2'b00), .halt(1'b0),
                            .nxpc2(32'h0000_0100));  // idx 64  hop le
    @(posedge bpu_hw_top.clock);
    chk(rd_bit("btb_valid_pc")    === 1'b0, "doi dia chi: btb_valid_pc khong cap nhat to hop");
    chk(rd_bit("btb_valid_nxpc")  === 1'b1, "doi dia chi: btb_valid_nxpc khong cap nhat to hop");
    chk(rd_bit("btb_valid_nxpc2") === 1'b1, "doi dia chi: btb_valid_nxpc2 khong cap nhat to hop");
    chk(rd_word("btb_target_nxpc2") === T64,
        $sformatf("btb_target_nxpc2=0x%08h sau khi doi dia chi, ky vong 0x%08h",
                  rd_word("btb_target_nxpc2"), T64));

    //---- PHA B: KHONG ton tai btb_target_nxpc (kiem cau truc) --------------
    // uvm_hdl_read tren duong dan KHONG ton tai se tu phat UVM_ERROR
    // (UVM/DPI/NOBJ1) tu lop DPI. O day "khong doc duoc" chinh la KET QUA MONG
    // DOI, nen ha rieng id do xuong INFO trong luc kiem roi tra lai nhu cu.
    phase_of("B_no_btb_target_nxpc");
    uvm_top.set_report_severity_id_override(UVM_ERROR, "UVM/DPI/NOBJ1", UVM_INFO);
    chk(uvm_hdl_read("bpu_hw_top.dut.btb_target_nxpc", dummy) === 0,
        "doc duoc bpu_hw_top.dut.btb_target_nxpc -- RTL hybrid KHONG duoc co cong nay");
    uvm_top.set_report_severity_id_override(UVM_ERROR, "UVM/DPI/NOBJ1", UVM_ERROR);

    //---- PHA C: doc trong luc ghi tra ve gia tri CU ------------------------
    // is_branch chi duoc bat DUNG MOT chu ky: neu giu lau hon, moi canh len deu
    // cap nhat lai BTB/BHT/PHT/GHR/choice va lam hong trang thai da huan luyen.
    phase_of("C_read_during_write");
    @(negedge bpu_hw_top.clock);
    bd.force_predict_inputs(.pc(32'h0000_0100), .nxpc(32'h0000_0FF4),
                            .fetch_opcode(7'b0010011),
                            .branch_target_fetch(32'h0),
                            .flush_in(2'b00), .halt(1'b0),
                            .nxpc2(32'h0000_0FF8),
                            .is_branch(1'b1), .branch_taken(1'b1),
                            .branch_offset(32'h80));
    chk(bd.read_btb_target(64) === T64,
        $sformatf("read-during-write: btb_target[64]=0x%08h, ky vong 0x%08h (khong write-through)",
                  bd.read_btb_target(64), T64));
    @(negedge bpu_hw_top.clock);        // dung MOT canh len da di qua
    bd.force_predict_inputs(.pc(32'h0000_0100), .nxpc(32'h0000_0FF4),
                            .fetch_opcode(7'b0010011),
                            .branch_target_fetch(32'h0),
                            .flush_in(2'b00), .halt(1'b0),
                            .nxpc2(32'h0000_0FF8),
                            .is_branch(1'b0));   // dung cap nhat ngay
    chk(bd.read_btb_target(64) === 32'h0000_0180,
        $sformatf("write-after-clk: btb_target[64]=0x%08h, ky vong 0x180 (pc+offset)",
                  bd.read_btb_target(64)));

    //---- PHA D: nhan lai nhanh vong lap QUA CONG NXPC2 ---------------------
    // Dia chi da ghi xuat hien lai o nxpc2; cong nxpc2 phai doc dung target MOI
    // NHAT (0x180 do pha C vua ghi) va bit du doan = T -> f_valid tich cuc.
    phase_of("D_loop_revisit_via_nxpc2");
    @(negedge bpu_hw_top.clock);
    bd.force_predict_inputs(.pc(32'h0000_0FF0), .nxpc(32'h0000_0FF4),
                            .fetch_opcode(7'b0010011),   // decode khong phai nhanh -> d_valid=0
                            .branch_target_fetch(32'h0),
                            .flush_in(2'b00), .halt(1'b0),
                            .nxpc2(32'h0000_0100));      // dia chi vong lap quay lai
    @(posedge bpu_hw_top.clock);
    chk(rd_bit("btb_valid_nxpc2")     === 1'b1, "vong lap: btb_valid_nxpc2 != 1");
    chk(rd_word("btb_target_nxpc2")   === 32'h0000_0180,
        $sformatf("vong lap: btb_target_nxpc2=0x%08h, ky vong 0x180 (target moi nhat)",
                  rd_word("btb_target_nxpc2")));
    chk(rd_bit("predict_taken_nxpc2") === 1'b1, "vong lap: predict_taken_nxpc2 != 1");
    chk(bd.read_bpu_nxpc2_valid() === 1'b1, "vong lap: bpu_nxpc2_valid != 1 (f_valid khong tich cuc)");
    chk(bd.read_bpu_nxpc2()       === 32'h0000_0180,
        $sformatf("vong lap: bpu_nxpc2=0x%08h, ky vong 0x180 (= btb_target_nxpc2)",
                  bd.read_bpu_nxpc2()));

    bd.release_predict_inputs();
    @(negedge bpu_hw_top.clock);
    phase.drop_objection(this, "3_2");
  endtask
endclass : btb_read_triple_port_test


//==============================================================================
// 3.3 btb_rw_all
//
// Sheet -- Test Flow: lap i = 0..1023: ghi tai pc = i<<2 voi offset = i, sau do
//   doc lai toan bo entry.
// Sheet -- Pass: moi entry giu dung target da ghi; khong entry nao bi ghi de
//   ngoai y muon.
// RTL Ref: bpu_reg.v
//
// LECH NHO SO VOI SHEET: offset duoc lai la (i<<1) thay vi i.
//   Ly do: branch_offset la immediate B-type nen luon can chan 2 byte
//   (rang buoc c_offset_aligned trong bpu_item.sv, va bpu_drive_seq ep bit0=0),
//   nen mot offset LE khong the lai duoc qua UVC. (i<<1) van cho moi entry mot
//   target rieng biet -> muc dich "moi entry doc lap" duoc giu nguyen.
//==============================================================================
class btb_rw_all_mcseq_v2 extends bpu_base_seq;
  `uvm_object_utils(btb_rw_all_mcseq_v2)
  function new(string name="btb_rw_all_mcseq_v2"); super.new(name); endfunction
  virtual task body();
    bpu_branch_vseq v;
    for (int i = 0; i < 1024; i++) begin
      v = bpu_branch_vseq::type_id::create($sformatf("w%0d", i));
      v.pc     = (i << 2);
      v.taken  = 1'b1;
      v.offset = (i << 1);           // xem ghi chu lech o tren
      v.btf    = (i << 1);
      v.start(m_sequencer, this);
    end
  endtask
endclass

class btb_rw_all_test extends hyb_base_test;
  `uvm_component_utils(btb_rw_all_test)
  function new(string name, uvm_component parent); super.new(name, parent); endfunction

  function void build_phase(uvm_phase phase);
    test_label = "TEST_3_3 (btb_rw_all)";
    select_clock();
    uvm_config_wrapper::set(this, "tb.bpu.tx_agent.sequencer.run_phase",
        "default_sequence", btb_rw_all_mcseq_v2::get_type());
    super.build_phase(phase);
  endfunction

  function void extract_phase(uvm_phase phase);
    bpu_backdoor bd;
    bit [31:0]   exp;
    int          n_bad_valid, n_bad_target;
    super.extract_phase(phase);
    bd = tb.module_env.backdoor;
    phase_of("A_sweep_1024");
    n_bad_valid = 0; n_bad_target = 0;
    for (int i = 0; i < 1024; i++) begin
      exp = (i << 2) + (i << 1);          // target = pc + offset
      if (bd.read_btb_valid(i) !== 1'b1) begin
        n_bad_valid++;
        if (n_bad_valid <= 5)
          chk(1'b0, $sformatf("btb_valid[%0d] != 1", i));
      end
      if (bd.read_btb_target(i) !== exp) begin
        n_bad_target++;
        if (n_bad_target <= 5)
          chk(1'b0, $sformatf("btb_target[%0d]=0x%08h, ky vong 0x%08h",
                              i, bd.read_btb_target(i), exp));
      end
    end
    `uvm_info(test_label, $sformatf("quet 1024 entry: sai valid=%0d, sai target=%0d",
                                    n_bad_valid, n_bad_target), UVM_LOW)
    if (n_bad_valid > 5 || n_bad_target > 5)
      chk(1'b0, $sformatf("tong cong %0d sai valid + %0d sai target (chi in 5 dau)",
                          n_bad_valid, n_bad_target));
  endfunction
endclass : btb_rw_all_test
