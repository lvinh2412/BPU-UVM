//------------------------------------------------------------------------------
// FILE: tests/hyb_redirect_tests.sv
//
//   11.1 redirect_fetch_tier        [B]
//   11.2 redirect_backstop          [B]
//   11.3 redirect_priority_matrix   [B]
//   10.1 flush_truth_table          [C]  -- 8 o bang chan tri
//   10.2 flush_uses_carry_not_pc    [D]
//   12.1 corr_target_matrix         [C]  -- 3 dang dia chi hieu chinh
//   12.2 corr_flush_decoupling      [D]  -- DIEU TRA DesignNotes R3
//   13.1 mux_priority_and_valid     [B]  -- 8 to hop (corr, d, f)
//
// Ke thua hyb_carry_base_test (tests/hyb_carry_tests.sv) -> include SAU tep do.
//
//==============================================================================
// KY THUAT DUNG CHUNG: dieu khien DOC LAP ba dai luong tai chu ky F+2
//
//   pred_was_hit(F+2)    = btb_valid_nxpc2(F)                     <- chon nxpc2
//   predicted_taken(F+2) = f_valid(F) | d_valid(F+1)              <- chon nxpc2 + opcode
//   branch_taken         = gia tri cap tai execute                <- chon truc tiep
//
//   f_valid(F)   = btb_valid_nxpc2 && predict_taken_nxpc2 && ready
//   d_valid(F+1) = fetch_is_branch(opcode) && !btb_valid_nxpc && ready
//
//   => Dat opcode tai tang DECODE = ADDI thi d_valid = 0 BAT KE btb_valid_nxpc.
//      Day la cach sach nhat de tach predicted_taken khoi trang thai BTB cua pc,
//      nho do co the doi rieng btb_valid_pc ma khong lam xe dich o dang kiem.
//
// BA DIA CHI CHUAN (huan luyen bang duong cap nhat THAT, khong ep gi):
//   TK = 0x100 : BTB hop le + du doan RE      -> hit=1, f_valid=1
//   NT = 0x200 : BTB hop le + du doan KHONG RE -> hit=1, f_valid=0
//   UT = 0x300 : chua bao gio duoc ghi        -> hit=0, f_valid=0
//   Thu tu huan luyen quan trong: TK truoc (ket thuc o chi muc 0xFFF), roi moi
//   den NT (dung chi muc 0), vi nhanh DAU TIEN cua moi dia chi deu ghi
//   local_pht[0] khi lich su con bang 0.
//==============================================================================

class hyb_redirect_base_test extends hyb_carry_base_test;

  localparam bit [31:0] ADDR_TK = 32'h0000_0100;   // idx 64
  localparam bit [31:0] ADDR_NT = 32'h0000_0200;   // idx 128
  localparam bit [31:0] ADDR_UT = 32'h0000_0300;   // idx 192 -- khong bao gio la pc
  localparam bit [6:0]  OPC_BR  = 7'b1100011;
  localparam bit [6:0]  OPC_NOP = 7'b0010011;

  function new(string name, uvm_component parent); super.new(name, parent); endfunction

  // Huan luyen ba dia chi chuan. Goi MOT LAN o dau moi muc.
  protected task automatic setup_addresses();
    bpu_backdoor bd = tb.module_env.backdoor;
    train_predict_taken(ADDR_TK, 24);       // -> BTB hop le, du doan RE
    train_predict_not_taken(ADDR_NT, 8);    // -> BTB hop le, du doan KHONG RE
    chk(bd.read_btb_valid(ADDR_TK[11:2]) === 1'b1, "chuan bi: btb_valid[TK] phai = 1");
    chk(bd.read_btb_valid(ADDR_NT[11:2]) === 1'b1, "chuan bi: btb_valid[NT] phai = 1");
    chk(bd.read_btb_valid(ADDR_UT[11:2]) === 1'b0, "chuan bi: btb_valid[UT] phai = 0");
  endtask

  // Huan luyen lai NT. Bat buoc goi truoc moi pha dung ADDR_NT lam nxpc2, vi
  // BAT KY nhanh moi nao o dia chi la cung ghi local_pht[0] (lich su con 0) va
  // do chinh la o ma du doan cua NT doc -> se bien NT thanh "du doan RE".
  protected task automatic refresh_nt();
    train_predict_not_taken(ADDR_NT, 6);
  endtask

  // Huan luyen lai TK. Bat buoc goi sau bat ky nhanh NOT-TAKEN nao tai ADDR_TK:
  // no lam dich bht[TK] khoi 0xFFF VA keo local_pht[0xFFF] xuong, nen TK khong
  // con "du doan RE". Can du 24 vong (xem ghi chu o train_predict_taken).
  protected task automatic refresh_tk();
    train_predict_taken(ADDR_TK, 24);
  endtask

  // Day MOT nhanh qua ba tang, tra ve quan sat tai F, F+1, F+2.
  //   o[0] = F   : ngo ra cua tang FETCH  (f_valid neu co)
  //   o[2] = F+2 : ngo ra cua tang EXECUTE (flush / correction)
  protected task automatic probe3(input  bit [31:0] pc,
                                  input  bit [31:0] nxpc2,
                                  input  bit        taken,
                                  input  bit [6:0]  opc_at_decode = OPC_NOP,
                                  input  bit [31:0] offset        = 32'h40,
                                  input  bit [31:0] btf           = 32'h40,
                                  input  bit [1:0]  fl_f          = 2'd0,
                                  input  bit [1:0]  fl_d          = 2'd0,
                                  input  bit [1:0]  fl_x          = 2'd0,
                                  input  bit        is_branch     = 1'b1,
                                  output bpu_pipe_obs_t o[3]);
    int base;
    h.idle(4);
    base = h.num_cycles();
    h.push_branch(.pc(pc), .taken(taken), .offset(offset), .opcode(opc_at_decode),
                  .flush_in(fl_f), .halt(1'b0), .btf(btf), .is_branch(is_branch),
                  .ovr_nxpc2(1'b1), .nxpc2(nxpc2));
    h.drain(fl_d, 1'b0, fl_x, 1'b0);
    o[0] = h.obs_at_cycle(base);
    o[1] = h.obs_at_cycle(base + 1);
    o[2] = h.obs_at_cycle(base + 2);
  endtask

  // Kiem rang mot o cua ma tran DA DUNG DUOC dung nhu y dinh, truoc khi doi
  // chieu ngo ra. Neu khong co buoc nay, mot o dung sai canh se "pass" nham.
  protected function void assert_cell(string lbl, bpu_pipe_obs_t o,
                                      bit exp_hit, bit exp_predT);
    chk(o.pred_was_hit    === exp_hit,
        $sformatf("%s: pred_was_hit=%0d, canh dung SAI (can %0d)", lbl, o.pred_was_hit, exp_hit));
    chk(o.predicted_taken === exp_predT,
        $sformatf("%s: predicted_taken=%0d, canh dung SAI (can %0d)", lbl, o.predicted_taken, exp_predT));
  endfunction

endclass : hyb_redirect_base_test


//==============================================================================
// 11.1 redirect_fetch_tier
// Sheet -- Flow: nap BTB tai nxpc2_index va dua bo du doan ve trang thai du doan
//   re; quet nhieu gia tri dia chi dich khac nhau; theo nhanh toi tang execute.
// Sheet -- Pass: bpu_nxpc2 = btb_target_nxpc2 va bpu_nxpc2_valid=1; nhanh nay ve
//   sau cho bpu_flush=0 neu du doan dung, tuc KHONG ton bong bong.
// RTL Ref: bpu_ctrl.v
//==============================================================================
class redirect_fetch_tier_test extends hyb_redirect_base_test;
  `uvm_component_utils(redirect_fetch_tier_test)
  function new(string name, uvm_component parent); super.new(name, parent); endfunction
  function void build_phase(uvm_phase phase);
    test_label = "TEST_11_1 (redirect_fetch_tier)"; super.build_phase(phase);
  endfunction

  task run_phase(uvm_phase phase);
    bpu_backdoor   bd;
    bpu_pipe_obs_t o[3];
    bit [31:0] offs[4];
    bit [31:0] exp_tgt;
    int k;
    super.run_phase(phase);
    bd = tb.module_env.backdoor;
    phase.raise_objection(this, "11_1");
    #100ns;
    setup_addresses();

    //---- PHA A: quet nhieu dia chi dich ------------------------------------
    // Moi vong huan luyen lai TK bang mot offset khac -> btb_target doi theo.
    phase_of("A_sweep_targets");
    offs = '{32'h0000_0040, 32'h0000_0800, 32'hFFFF_FFC0, 32'h0000_0000};
    for (k = 0; k < 4; k++) begin
      repeat (4) drive_branch(ADDR_TK, 1'b1, offs[k]);   // btb_target[TK] = TK + offs
      exp_tgt = ADDR_TK + offs[k];
      chk(bd.read_btb_target(ADDR_TK[11:2]) === exp_tgt,
          $sformatf("chuan bi offset 0x%08h: btb_target[TK]=0x%08h, ky vong 0x%08h",
                    offs[k], bd.read_btb_target(ADDR_TK[11:2]), exp_tgt));
      probe3(.pc(ADDR_TK), .nxpc2(ADDR_TK), .taken(1'b1),
             .opc_at_decode(OPC_NOP), .offset(offs[k]), .o(o));
      `uvm_info(test_label, $sformatf(
        "offset=0x%08h : tai F  valid=%0d nxpc2=0x%08h (ky vong btb_target_nxpc2=0x%08h)",
        offs[k], o[0].bpu_nxpc2_valid, o[0].bpu_nxpc2, exp_tgt), UVM_NONE)
      chk(o[0].bpu_nxpc2_valid === 1'b1,
          $sformatf("offset 0x%08h: bpu_nxpc2_valid tai F != 1", offs[k]));
      chk(o[0].bpu_nxpc2 === exp_tgt,
          $sformatf("offset 0x%08h: bpu_nxpc2=0x%08h tai F, ky vong 0x%08h (btb_target_nxpc2)",
                    offs[k], o[0].bpu_nxpc2, exp_tgt));
    end

    //---- PHA B: du doan dung -> KHONG ton bong bong ------------------------
    phase_of("B_correct_predict_zero_bubble");
    probe3(.pc(ADDR_TK), .nxpc2(ADDR_TK), .taken(1'b1), .opc_at_decode(OPC_NOP), .o(o));
    assert_cell("du doan dung", o[2], .exp_hit(1'b1), .exp_predT(1'b1));
    `uvm_info(test_label, $sformatf({
      "\n=== LOI ICH HYBRID: tang fetch du doan dung -> KHONG bong bong ===\n",
      "  pred_was_hit=1, predicted_taken=1, branch_taken=1 -> bpu_flush=%0d\n",
      "  (ban decode cho 1 bong bong o cung tinh huong nay)\n",
      "=================================================================="},
      o[2].bpu_flush), UVM_NONE)
    chk(o[2].bpu_flush === 2'd0,
        $sformatf("du doan dung: bpu_flush=%0d, ky vong 0 (khong bong bong)", o[2].bpu_flush));

    phase.drop_objection(this, "11_1");
  endtask
endclass : redirect_fetch_tier_test


//==============================================================================
// 11.2 redirect_backstop
// Sheet -- Flow: dat BTB miss tai nxpc voi fetch_opcode=BCC; quet
//   branch_target_fetch voi gia tri duong, am va bang 0.
// Sheet -- Pass: bpu_nxpc2 = nxpc + branch_target_fetch trong ca ba truong hop
//   va bpu_nxpc2_valid=1; chi phi MOT bong bong khi nhanh thuc su re.
// RTL Ref: bpu_ctrl.v
//==============================================================================
class redirect_backstop_test extends hyb_redirect_base_test;
  `uvm_component_utils(redirect_backstop_test)
  function new(string name, uvm_component parent); super.new(name, parent); endfunction
  function void build_phase(uvm_phase phase);
    test_label = "TEST_11_2 (redirect_backstop)"; super.build_phase(phase);
  endfunction

  task run_phase(uvm_phase phase);
    bpu_backdoor   bd;
    bpu_pipe_obs_t o[3];
    bit [31:0] btfs[3];
    bit [31:0] pcs[3];
    bit [31:0] exp;
    int k;
    super.run_phase(phase);
    bd = tb.module_env.backdoor;
    phase.raise_objection(this, "11_2");
    #100ns;
    setup_addresses();

    //---- PHA A: quet branch_target_fetch duong / am / bang 0 --------------
    // Moi lan dung mot pc CHUA tung gap -> btb_valid_nxpc = 0 tai F+1.
    phase_of("A_sweep_btf_sign");
    btfs = '{32'h0000_0040, 32'hFFFF_FFC0, 32'h0000_0000};
    pcs  = '{32'h0000_0400, 32'h0000_0410, 32'h0000_0420};
    for (k = 0; k < 3; k++) begin
      chk(bd.read_btb_valid(pcs[k][11:2]) === 1'b0,
          $sformatf("chuan bi: btb_valid cho pc=0x%08h phai = 0", pcs[k]));
      probe3(.pc(pcs[k]), .nxpc2(ADDR_UT), .taken(1'b1),
             .opc_at_decode(OPC_BR), .offset(32'h40), .btf(btfs[k]), .o(o));
      exp = pcs[k] + btfs[k];        // d_nxpc2 = nxpc + branch_target_fetch
      `uvm_info(test_label, $sformatf(
        "btf=0x%08h : tai F+1 valid=%0d nxpc2=0x%08h (ky vong nxpc+btf=0x%08h)",
        btfs[k], o[1].bpu_nxpc2_valid, o[1].bpu_nxpc2, exp), UVM_NONE)
      chk(o[1].bpu_nxpc2_valid === 1'b1,
          $sformatf("btf=0x%08h: bpu_nxpc2_valid tai F+1 != 1", btfs[k]));
      chk(o[1].bpu_nxpc2 === exp,
          $sformatf("btf=0x%08h: bpu_nxpc2=0x%08h, ky vong 0x%08h (nxpc + btf)",
                    btfs[k], o[1].bpu_nxpc2, exp));
      // backstop chuyen huong theo huong RE; nhanh thuc su re -> mot bong bong
      chk(o[2].bpu_flush === 2'd1,
          $sformatf("btf=0x%08h: bpu_flush=%0d tai F+2, ky vong 1 (BTB miss + re)",
                    btfs[k], o[2].bpu_flush));
    end

    phase.drop_objection(this, "11_2");
  endtask
endclass : redirect_backstop_test


//==============================================================================
// 11.3 redirect_priority_matrix
// Sheet -- Flow: tao bon to hop cua (d_valid, f_valid) voi hai gia tri dich phan
//   biet ro. O (0,0) dung bang cach cho BTB TRUNG tai nxpc2 kem du doan KHONG RE,
//   khi do f_valid=0 va d_valid=0 do btb_valid_nxpc=1.
// Sheet -- Pass: (1,1) va (1,0) cho bpu_nxpc2 = d_nxpc2; (0,1) cho f_nxpc2;
//   (0,0) cho bpu_nxpc2_valid=0 -- xac nhan hybrid da bo han duong pc+4 cua S3.
// RTL Ref: bpu_ctrl.v
//==============================================================================
class redirect_priority_matrix_test extends hyb_redirect_base_test;
  `uvm_component_utils(redirect_priority_matrix_test)
  function new(string name, uvm_component parent); super.new(name, parent); endfunction
  function void build_phase(uvm_phase phase);
    test_label = "TEST_11_3 (redirect_priority_matrix)"; super.build_phase(phase);
  endfunction

  // Dung MOT chu ky co (d_valid, f_valid) theo y muon, roi tra ve quan sat.
  //   B1 day vao truoc -> tai chu ky do B1 nam o tang DECODE (quyet dinh d)
  //   B2 day vao sau   -> tai chu ky do B2 nam o tang FETCH  (quyet dinh f)
  //   Tang EXECUTE de trong (is_branch=0) nen corr_valid = 0.
  task automatic run_cell(input bit want_d, input bit want_f, output bpu_pipe_obs_t o);
    bit [31:0] b1_pc;
    int base;
    // d=1: pc CHUA gap + opcode BCC ; d=0: theo sheet dung pc DA gap + BCC
    b1_pc = want_d ? 32'h0000_0430 : ADDR_TK;
    h.idle(4);
    h.push_branch(.pc(b1_pc), .taken(1'b0), .offset(32'h40), .opcode(OPC_BR),
                  .btf(32'h0000_0044), .is_branch(1'b0),
                  .ovr_nxpc2(1'b1), .nxpc2(ADDR_UT));
    base = h.num_cycles();
    h.push_branch(.pc(32'h0000_0440), .taken(1'b0), .offset(32'h40), .opcode(OPC_NOP),
                  .is_branch(1'b0),
                  .ovr_nxpc2(1'b1), .nxpc2(want_f ? ADDR_TK : ADDR_NT));
    o = h.obs_at_cycle(base);
    h.drain();
  endtask

  task run_phase(uvm_phase phase);
    bpu_pipe_obs_t o;
    bit [31:0] d_tgt, f_tgt;
    bpu_backdoor bd;
    super.run_phase(phase);
    bd = tb.module_env.backdoor;
    phase.raise_objection(this, "11_3");
    #100ns;
    setup_addresses();
    d_tgt = 32'h0000_0430 + 32'h0000_0044;                  // nxpc + btf
    f_tgt = bd.read_btb_target(ADDR_TK[11:2]);              // btb_target_nxpc2

    //---- (1,1) : ca hai tich cuc -> BACKSTOP thang ------------------------
    phase_of("A_d1_f1_backstop_wins");
    run_cell(.want_d(1'b1), .want_f(1'b1), .o(o));
    show("d=1 f=1", o);
    chk(o.bpu_nxpc2_valid === 1'b1, "(1,1): valid != 1");
    chk(o.bpu_nxpc2 === d_tgt,
        $sformatf("(1,1): nxpc2=0x%08h, ky vong d_nxpc2=0x%08h (backstop uu tien hon fetch)",
                  o.bpu_nxpc2, d_tgt));

    //---- (1,0) : chi backstop ---------------------------------------------
    phase_of("B_d1_f0_backstop");
    run_cell(.want_d(1'b1), .want_f(1'b0), .o(o));
    show("d=1 f=0", o);
    chk(o.bpu_nxpc2_valid === 1'b1, "(1,0): valid != 1");
    chk(o.bpu_nxpc2 === d_tgt,
        $sformatf("(1,0): nxpc2=0x%08h, ky vong d_nxpc2=0x%08h", o.bpu_nxpc2, d_tgt));

    //---- (0,1) : chi tang fetch -------------------------------------------
    phase_of("C_d0_f1_fetch");
    run_cell(.want_d(1'b0), .want_f(1'b1), .o(o));
    show("d=0 f=1", o);
    chk(o.bpu_nxpc2_valid === 1'b1, "(0,1): valid != 1");
    chk(o.bpu_nxpc2 === f_tgt,
        $sformatf("(0,1): nxpc2=0x%08h, ky vong f_nxpc2=btb_target_nxpc2=0x%08h",
                  o.bpu_nxpc2, f_tgt));

    //---- (0,0) : khong tang nao -> KHONG chuyen huong ---------------------
    // Xac nhan hybrid da BO HAN duong pc+4 cua truong hop S3 cu.
    phase_of("D_d0_f0_no_redirect");
    run_cell(.want_d(1'b0), .want_f(1'b0), .o(o));
    show("d=0 f=0", o);
    chk(o.bpu_nxpc2_valid === 1'b0,
        "(0,0): valid != 0 -- hybrid phai BO duong chuyen huong pc+4 (S3 cu)");
    chk(o.bpu_nxpc2 === 32'd0,
        $sformatf("(0,0): nxpc2=0x%08h, ky vong 0", o.bpu_nxpc2));

    phase.drop_objection(this, "11_3");
  endtask
endclass : redirect_priority_matrix_test


//==============================================================================
// 10.1 flush_truth_table
// Sheet -- Flow: voi is_branch=0 quet moi trang thai carry-down; voi is_branch=1
//   day nhanh qua du ba tang cho tung to hop (pred_was_hit, predicted_taken,
//   branch_taken); trong nhanh BTB miss con thay doi them btb_valid_pc tai
//   execute de chung minh no KHONG anh huong.
// Sheet -- Pass: is_branch=0 -> 0 moi to hop. pred_was_hit=0: taken=1 cho 1,
//   taken=0 cho 2, khong phu thuoc btb_valid_pc. pred_was_hit=1: predT&actT -> 0
//   (KHONG bong bong, diem khac ban decode); predT&actNT -> 2; predNT&actT -> 2;
//   predNT&actNT -> 0.
// RTL Ref: bpu_ctrl.v
//==============================================================================
class flush_truth_table_test extends hyb_redirect_base_test;
  `uvm_component_utils(flush_truth_table_test)
  function new(string name, uvm_component parent); super.new(name, parent); endfunction
  function void build_phase(uvm_phase phase);
    test_label = "TEST_10_1 (flush_truth_table)"; super.build_phase(phase);
  endfunction

  string tbl;

  // Dung mot o cua bang chan tri.
  //   hit=0 -> nxpc2 = UT ; hit=1 -> nxpc2 = TK (du doan RE) hoac NT (KHONG RE)
  //   predT=1 khi hit=0 : lay tu backstop -> opcode BCC + pc chua gap
  //   predT=0           : opcode ADDI -> d_valid=0 bat ke trang thai BTB cua pc
  task automatic run_cell(input bit hit, input bit predT, input bit actT,
                      input bit [31:0] pc_use,
                      input bit is_br,
                      output bpu_pipe_obs_t o[3]);
    bit [31:0] nx2;
    bit [6:0]  opc;
    nx2 = !hit  ? ADDR_UT : (predT ? ADDR_TK : ADDR_NT);
    opc = (!hit && predT) ? OPC_BR : OPC_NOP;   // chi ca (0,1) moi can backstop
    probe3(.pc(pc_use), .nxpc2(nx2), .taken(actT), .opc_at_decode(opc),
           .offset(32'h40), .btf(32'h40), .is_branch(is_br), .o(o));
  endtask

  task automatic do_cell(bit hit, bit predT, bit actT, bit [31:0] pc_use,
                         bit [1:0] exp_flush, string lbl);
    bpu_pipe_obs_t o[3];
    run_cell(hit, predT, actT, pc_use, 1'b1, o);
    assert_cell(lbl, o[2], .exp_hit(hit), .exp_predT(predT));
    chk(o[2].bpu_flush === exp_flush,
        $sformatf("%s: bpu_flush=%0d, ky vong %0d", lbl, o[2].bpu_flush, exp_flush));
    tbl = {tbl, $sformatf("  |   %0d   |   %0d   |  %0d   |   %0d   | %s\n",
                          hit, predT, actT, o[2].bpu_flush, lbl)};
  endtask

  task run_phase(uvm_phase phase);
    bpu_pipe_obs_t o[3];
    bpu_backdoor   bd;
    super.run_phase(phase);
    bd = tb.module_env.backdoor;
    phase.raise_objection(this, "10_1");
    #100ns;
    setup_addresses();
    tbl = "";

    //---- PHA A: is_branch = 0 -> bpu_flush = 0 trong MOI trang thai --------
    phase_of("A_no_branch_always_zero");
    run_cell(1'b1, 1'b1, 1'b1, ADDR_TK, 1'b0, o);   // carry-down = (hit=1, predT=1)
    chk(o[2].bpu_flush === 2'd0,
        $sformatf("is_branch=0 voi carry(1,1): bpu_flush=%0d, ky vong 0", o[2].bpu_flush));
    run_cell(1'b0, 1'b1, 1'b0, 32'h0000_0450, 1'b0, o);
    chk(o[2].bpu_flush === 2'd0,
        $sformatf("is_branch=0 voi carry(0,1): bpu_flush=%0d, ky vong 0", o[2].bpu_flush));
    run_cell(1'b1, 1'b0, 1'b1, ADDR_NT, 1'b0, o);
    chk(o[2].bpu_flush === 2'd0,
        $sformatf("is_branch=0 voi carry(1,0): bpu_flush=%0d, ky vong 0", o[2].bpu_flush));

    //---- PHA B: nhanh BTB MISS (pred_was_hit = 0) -------------------------
    phase_of("B_btb_miss_rows");
    do_cell(1'b0, 1'b0, 1'b0, 32'h0000_0460, 2'd2, "hit=0 predNT actNT");
    do_cell(1'b0, 1'b0, 1'b1, 32'h0000_0470, 2'd1, "hit=0 predNT actT ");
    do_cell(1'b0, 1'b1, 1'b0, 32'h0000_0480, 2'd2, "hit=0 predT  actNT");
    do_cell(1'b0, 1'b1, 1'b1, 32'h0000_0490, 2'd1, "hit=0 predT  actT ");

    //---- PHA C: btb_valid_pc KHONG anh huong den flush --------------------
    // Lap lai o (hit=0, predNT, actNT) hai lan: mot lan pc CHUA gap
    // (btb_valid_pc=0), mot lan pc DA gap (btb_valid_pc=1). opcode tai decode la
    // ADDI nen d_valid=0 trong ca hai -> chi co btb_valid_pc thay doi.
    phase_of("C_btb_valid_pc_has_no_effect");
    chk(bd.read_btb_valid(32'h0000_04A0 >> 2 & 10'h3FF) === 1'b0,
        "chuan bi: pc=0x4A0 phai chua duoc ghi");
    run_cell(1'b0, 1'b0, 1'b0, 32'h0000_04A0, 1'b1, o);
    chk(o[2].bpu_flush === 2'd2,
        $sformatf("btb_valid_pc=0: bpu_flush=%0d, ky vong 2", o[2].bpu_flush));
    h.idle(1);   // cho lenh ghi BTB cua canh len F+2 dap xuong roi moi doc
    // lan hai: cung pc, gio da duoc ghi boi chinh lan truoc -> btb_valid_pc = 1
    chk(bd.read_btb_valid(32'h0000_04A0 >> 2 & 10'h3FF) === 1'b1,
        "sau lan mot: pc=0x4A0 phai da duoc ghi");
    run_cell(1'b0, 1'b0, 1'b0, 32'h0000_04A0, 1'b1, o);
    chk(o[2].bpu_flush === 2'd2,
        $sformatf("btb_valid_pc=1: bpu_flush=%0d, ky vong VAN 2 (khong phu thuoc btb_valid_pc)",
                  o[2].bpu_flush));

    //---- PHA D: nhanh BTB HIT (pred_was_hit = 1) --------------------------
    phase_of("D_btb_hit_rows");
    refresh_nt();
    do_cell(1'b1, 1'b0, 1'b0, ADDR_NT, 2'd0, "hit=1 predNT actNT");
    do_cell(1'b1, 1'b0, 1'b1, ADDR_NT, 2'd2, "hit=1 predNT actT ");
    refresh_tk();
    do_cell(1'b1, 1'b1, 1'b0, ADDR_TK, 2'd2, "hit=1 predT  actNT");
    refresh_tk();   // hang tren lai TK voi taken=0 -> phai huan luyen lai
    do_cell(1'b1, 1'b1, 1'b1, ADDR_TK, 2'd0, "hit=1 predT  actT ");

    `uvm_info(test_label, {
      "\n=========== BANG CHAN TRI bpu_flush (is_branch = 1) ===========\n",
      "  | hit | predT | actT | flush | o\n",
      "  |-----|-------|------|-------|------------------\n", tbl,
      "  O quan trong nhat: hit=1, predT=1, actT=1 -> flush = 0.\n",
      "  Ban decode cho 1 bong bong o cung tinh huong; hybrid cho 0.\n",
      "==============================================================="}, UVM_NONE)

    phase.drop_objection(this, "10_1");
  endtask
endclass : flush_truth_table_test


//==============================================================================
// 10.2 flush_uses_carry_not_pc
// Sheet -- Flow: dung btb_valid_nxpc2=0 tai F nhung btb_valid_pc=1 tai F+2
//   (entry duoc ghi boi mot nhanh TRUNG CHI MUC xen vao giua); quan sat bpu_flush.
// Sheet -- Pass: bpu_flush theo nhanh BTB MISS (taken thi 1, khong taken thi 2),
//   KHONG theo btb_valid_pc.
// RTL Ref: bpu_ctrl.v
//==============================================================================
class flush_uses_carry_not_pc_test extends hyb_redirect_base_test;
  `uvm_component_utils(flush_uses_carry_not_pc_test)
  function new(string name, uvm_component parent); super.new(name, parent); endfunction
  function void build_phase(uvm_phase phase);
    test_label = "TEST_10_2 (flush_uses_carry_not_pc)"; super.build_phase(phase);
  endfunction

  // X   = 0x7000 -> idx (0x7000>>2)&0x3FF = 0x1C00 & 0x3FF = 0
  // Chon cap dia chi TRUNG CHI MUC de nhanh xen vao ghi dung entry cua X.
  localparam bit [31:0] X_PC    = 32'h0000_04B0;
  localparam bit [31:0] X_ALIAS = 32'h0000_14B0;   // cung chi muc voi X_PC

  task run_phase(uvm_phase phase);
    bpu_backdoor   bd;
    bpu_pipe_obs_t o;
    int base, xidx, aidx;
    super.run_phase(phase);
    bd = tb.module_env.backdoor;
    phase.raise_objection(this, "10_2");
    #100ns;
    setup_addresses();

    xidx = (X_PC    >> 2) & 32'h3FF;
    aidx = (X_ALIAS >> 2) & 32'h3FF;

    phase_of("A_alias_writes_entry_between_F_and_Fplus2");
    chk(xidx == aidx,
        $sformatf("chuan bi: X_PC va X_ALIAS phai TRUNG chi muc (%0d vs %0d)", xidx, aidx));
    // Dam bao entry chua hop le truoc khi bat dau
    chk(bd.read_btb_valid(xidx) === 1'b0,
        $sformatf("chuan bi: btb_valid[%0d] phai = 0 truoc phep do", xidx));

    h.idle(4);
    base = h.num_cycles();
    // F   : X vao tang FETCH voi nxpc2 = X_PC -> btb_valid_nxpc2 = 0 (chua ghi)
    //       opcode tai decode = ADDI -> d_valid = 0 o F+1 -> predicted_taken = 0
    h.push_branch(.pc(X_PC), .taken(1'b1), .offset(32'h40), .opcode(OPC_NOP),
                  .ovr_nxpc2(1'b1), .nxpc2(X_PC));
    // F+1 : nhanh TRUNG CHI MUC thuc thi ngay -> ghi btb[xidx] hop le.
    //       Day chinh la nhanh "xen vao giua" ma sheet mo ta.
    h.push_branch(.pc(X_ALIAS), .taken(1'b1), .offset(32'h40), .opcode(OPC_NOP),
                  .ovr_nxpc2(1'b1), .nxpc2(ADDR_UT), .is_branch(1'b1));
    h.drain();

    o = h.obs_at_cycle(base + 2);       // chinh chu ky F+2 cua nhanh X

    `uvm_info(test_label, $sformatf({
      "\n=== flush lay tu CARRY-DOWN chu khong tu btb_valid_pc ===\n",
      "  Tai F   : btb_valid_nxpc2 = 0 (entry chua duoc ghi)\n",
      "  Tai F+2 : btb_valid_pc    = %0d (nhanh trung chi muc da ghi xen vao giua)\n",
      "            pred_was_hit    = %0d (mang xuong tu F -> phai la 0)\n",
      "            branch_taken    = 1\n",
      "            bpu_flush       = %0d (ky vong 1 = nhanh BTB MISS + re)\n",
      "  Neu flush dung btb_valid_pc thi ket qua se la 0 (du doan dung).\n",
      "========================================================="},
      bd.read_btb_valid(xidx), o.pred_was_hit, o.bpu_flush), UVM_NONE)

    chk(bd.read_btb_valid(xidx) === 1'b1,
        "canh dung SAI: btb_valid_pc tai F+2 phai = 1 (nhanh trung chi muc phai ghi duoc)");
    chk(o.pred_was_hit === 1'b0,
        $sformatf("pred_was_hit=%0d, ky vong 0 (mang xuong tu F, luc do BTB con truot)",
                  o.pred_was_hit));
    chk(o.bpu_flush === 2'd1,
        $sformatf("bpu_flush=%0d, ky vong 1 -- flush phai theo pred_was_hit, KHONG theo btb_valid_pc",
                  o.bpu_flush));

    phase.drop_objection(this, "10_2");
  endtask
endclass : flush_uses_carry_not_pc_test


//==============================================================================
// 12.1 corr_target_matrix
// Sheet -- Flow: quet ma tran (predicted_taken, branch_taken, pred_was_hit), moi
//   o day nhanh qua du ba tang. O taken=1 kem pred_was_hit=0 dung bang cach tao
//   BTB miss tai fetch dong thoi CHAN tang du phong o chu ky F+1.
// Sheet -- Pass: corr_valid=1 chi khi is_branch=1 va predicted_taken khac
//   branch_taken. Dia chi hieu chinh: taken=0 -> pc+4 voi CA HAI gia tri
//   pred_was_hit (khac ban decode dung nxpc+4); taken=1 & hit=1 -> btb_target_pc;
//   taken=1 & hit=0 -> pc + branch_offset (duong MOI cua hybrid).
// RTL Ref: bpu_ctrl.v
//==============================================================================
class corr_target_matrix_test extends hyb_redirect_base_test;
  `uvm_component_utils(corr_target_matrix_test)
  function new(string name, uvm_component parent); super.new(name, parent); endfunction
  function void build_phase(uvm_phase phase);
    test_label = "TEST_12_1 (corr_target_matrix)"; super.build_phase(phase);
  endfunction

  string tbl;

  task run_phase(uvm_phase phase);
    bpu_backdoor   bd;
    bpu_pipe_obs_t o[3];
    bit [31:0] exp, tgt_pc;
    super.run_phase(phase);
    bd = tb.module_env.backdoor;
    phase.raise_objection(this, "12_1");
    #100ns;
    setup_addresses();
    tbl = "";

    //---- PHA A: du doan DUNG -> corr_valid = 0 ---------------------------
    phase_of("A_correct_predict_no_correction");
    probe3(.pc(ADDR_TK), .nxpc2(ADDR_TK), .taken(1'b1), .opc_at_decode(OPC_NOP), .o(o));
    assert_cell("hit=1 predT actT", o[2], 1'b1, 1'b1);
    chk(o[2].bpu_nxpc2_valid === 1'b0,
        $sformatf("du doan dung (predT=actT=1): valid=%0d, ky vong 0 (khong hieu chinh)",
                  o[2].bpu_nxpc2_valid));
    probe3(.pc(ADDR_NT), .nxpc2(ADDR_NT), .taken(1'b0), .opc_at_decode(OPC_NOP), .o(o));
    assert_cell("hit=1 predNT actNT", o[2], 1'b1, 1'b0);
    chk(o[2].bpu_nxpc2_valid === 1'b0,
        $sformatf("du doan dung (predNT=actNT): valid=%0d, ky vong 0", o[2].bpu_nxpc2_valid));

    //---- PHA B: taken = 0 -> pc + 4, voi CA HAI gia tri pred_was_hit ------
    // Diem khac ban decode: co so tinh la pc chu KHONG phai nxpc.
    phase_of("B_not_taken_gives_pc_plus_4");
    // hit = 1 (nxpc2 = TK, du doan RE), thuc te KHONG re
    probe3(.pc(ADDR_TK), .nxpc2(ADDR_TK), .taken(1'b0), .opc_at_decode(OPC_NOP), .o(o));
    assert_cell("hit=1 predT actNT", o[2], 1'b1, 1'b1);
    exp = ADDR_TK + 32'd4;
    chk(o[2].bpu_nxpc2_valid === 1'b1, "hit=1 taken=0: valid != 1");
    chk(o[2].bpu_nxpc2 === exp,
        $sformatf("hit=1 taken=0: nxpc2=0x%08h, ky vong pc+4=0x%08h", o[2].bpu_nxpc2, exp));
    tbl = {tbl, $sformatf("  |  1  |   1   |  0   | 0x%08h | pc+4\n", o[2].bpu_nxpc2)};
    // hit = 0 (nxpc2 = UT), predT lay tu backstop, thuc te KHONG re
    probe3(.pc(32'h0000_04C0), .nxpc2(ADDR_UT), .taken(1'b0), .opc_at_decode(OPC_BR), .o(o));
    assert_cell("hit=0 predT actNT", o[2], 1'b0, 1'b1);
    exp = 32'h0000_04C0 + 32'd4;
    chk(o[2].bpu_nxpc2_valid === 1'b1, "hit=0 taken=0: valid != 1");
    chk(o[2].bpu_nxpc2 === exp,
        $sformatf("hit=0 taken=0: nxpc2=0x%08h, ky vong pc+4=0x%08h", o[2].bpu_nxpc2, exp));
    tbl = {tbl, $sformatf("  |  0  |   1   |  0   | 0x%08h | pc+4\n", o[2].bpu_nxpc2)};

    //---- PHA C: taken = 1, hit = 1 -> btb_target_pc -----------------------
    phase_of("C_taken_hit_gives_btb_target_pc");
    refresh_nt();
    tgt_pc = bd.read_btb_target(ADDR_NT[11:2]);
    probe3(.pc(ADDR_NT), .nxpc2(ADDR_NT), .taken(1'b1), .opc_at_decode(OPC_NOP), .o(o));
    assert_cell("hit=1 predNT actT", o[2], 1'b1, 1'b0);
    chk(o[2].bpu_nxpc2_valid === 1'b1, "hit=1 taken=1: valid != 1");
    chk(o[2].bpu_nxpc2 === tgt_pc,
        $sformatf("hit=1 taken=1: nxpc2=0x%08h, ky vong btb_target_pc=0x%08h",
                  o[2].bpu_nxpc2, tgt_pc));
    tbl = {tbl, $sformatf("  |  1  |   0   |  1   | 0x%08h | btb_target_pc\n", o[2].bpu_nxpc2)};

    //---- PHA D: taken = 1, hit = 0 -> pc + branch_offset (DUONG MOI) ------
    // BTB miss tai fetch (nxpc2 = UT) VA chan tang du phong tai F+1 bang
    // opcode ADDI -> predicted_taken = 0, pred_was_hit = 0.
    phase_of("D_taken_miss_gives_pc_plus_offset");
    probe3(.pc(32'h0000_04D0), .nxpc2(ADDR_UT), .taken(1'b1),
           .opc_at_decode(OPC_NOP), .offset(32'h0000_0084), .o(o));
    assert_cell("hit=0 predNT actT", o[2], 1'b0, 1'b0);
    exp = 32'h0000_04D0 + 32'h0000_0084;
    chk(o[2].bpu_nxpc2_valid === 1'b1, "hit=0 taken=1: valid != 1");
    chk(o[2].bpu_nxpc2 === exp,
        $sformatf("hit=0 taken=1: nxpc2=0x%08h, ky vong pc+branch_offset=0x%08h (DUONG MOI)",
                  o[2].bpu_nxpc2, exp));
    tbl = {tbl, $sformatf("  |  0  |   0   |  1   | 0x%08h | pc+branch_offset (MOI)\n",
                          o[2].bpu_nxpc2)};

    //---- PHA E: is_branch = 0 -> khong bao gio hieu chinh ------------------
    phase_of("E_no_branch_no_correction");
    probe3(.pc(ADDR_TK), .nxpc2(ADDR_TK), .taken(1'b0), .opc_at_decode(OPC_NOP),
           .is_branch(1'b0), .o(o));
    chk(o[2].bpu_nxpc2_valid === 1'b0,
        $sformatf("is_branch=0: valid=%0d, ky vong 0 du carry-down bao du doan RE",
                  o[2].bpu_nxpc2_valid));

    `uvm_info(test_label, {
      "\n======== MA TRAN DIA CHI HIEU CHINH ========\n",
      "  | hit | predT | actT |   corr_nxpc2  | dang\n",
      "  |-----|-------|------|---------------|---------------\n", tbl,
      "  Co so tinh la pc (ban decode dung nxpc).\n",
      "============================================"}, UVM_NONE)

    phase.drop_objection(this, "12_1");
  endtask
endclass : corr_target_matrix_test


//==============================================================================
// 12.2 corr_flush_decoupling      --- MUC DIEU TRA (DesignNotes R3)
// Sheet -- Flow: TH A: tang du phong du doan DUNG, voi pred_was_hit=0,
//   predicted_taken=1 va branch_taken=1. TH B: ep btb_valid_nxpc2=0 tai F va CHAN
//   tang du phong tai F+1, tai execute cap branch_taken=1.
// Sheet -- Pass: TH A cho bpu_flush=1 kem corr_valid=0. TH B cho bpu_flush=1
//   DONG THOI corr_valid=1 va corr_nxpc2 = pc + branch_offset; ghi nhan ket qua
//   va doi chieu voi loi xem MOT bong bong co du hay khong (DesignNotes R3).
// RTL Ref: bpu_ctrl.v
//==============================================================================
class corr_flush_decoupling_test extends hyb_redirect_base_test;
  `uvm_component_utils(corr_flush_decoupling_test)
  function new(string name, uvm_component parent); super.new(name, parent); endfunction
  function void build_phase(uvm_phase phase);
    test_label = "TEST_12_2 (corr_flush_decoupling)"; super.build_phase(phase);
  endfunction

  task run_phase(uvm_phase phase);
    bpu_pipe_obs_t oA[3], oB[3];
    bit [31:0] expB;
    super.run_phase(phase);
    phase.raise_objection(this, "12_2");
    #100ns;
    setup_addresses();

    //---- TH A: backstop da chuyen huong DUNG -> flush=1 nhung KHONG corr ---
    phase_of("A_backstop_correct_flush1_no_corr");
    probe3(.pc(32'h0000_04E0), .nxpc2(ADDR_UT), .taken(1'b1),
           .opc_at_decode(OPC_BR), .o(oA));       // BCC + pc chua gap -> d_valid=1
    assert_cell("TH A", oA[2], .exp_hit(1'b0), .exp_predT(1'b1));
    chk(oA[2].bpu_flush === 2'd1,
        $sformatf("TH A: bpu_flush=%0d, ky vong 1", oA[2].bpu_flush));
    chk(oA[2].bpu_nxpc2_valid === 1'b0,
        $sformatf("TH A: valid=%0d, ky vong 0 (corr_valid=0 vi du doan DUNG)",
                  oA[2].bpu_nxpc2_valid));

    //---- TH B (R3): flush=1 DONG THOI corr_valid=1 ------------------------
    // BTB truot tai F (nxpc2=UT) VA backstop bi chan tai F+1 (opcode ADDI)
    // -> predicted_taken=0, pred_was_hit=0. Cap branch_taken=1 tai execute.
    phase_of("B_R3_flush1_with_correction");
    probe3(.pc(32'h0000_04F0), .nxpc2(ADDR_UT), .taken(1'b1),
           .opc_at_decode(OPC_NOP), .offset(32'h0000_0064), .o(oB));
    assert_cell("TH B", oB[2], .exp_hit(1'b0), .exp_predT(1'b0));
    expB = 32'h0000_04F0 + 32'h0000_0064;

    `uvm_info(test_label, $sformatf({
      "\n=== DIEU TRA DesignNotes R3: flush=1 dong thoi corr_valid=1 ===\n",
      "  Dieu kien tai hien (o muc module):\n",
      "    - tai F   : btb_valid_nxpc2 = 0  (dia chi chua tung duoc ghi vao BTB)\n",
      "    - tai F+1 : tang du phong BI CHAN (o day dung opcode khac BCC; dung\n",
      "                fetch_ready=0 hoac btb_valid_nxpc=1 do trung chi muc cung ra\n",
      "                cung ket qua)\n",
      "    - tai F+2 : is_branch=1, branch_taken=1\n",
      "  Ket qua do duoc:\n",
      "    pred_was_hit    = %0d\n",
      "    predicted_taken = %0d\n",
      "    bpu_flush       = %0d   <- quy tac !pred_was_hit -> taken ? 1 : 2\n",
      "    corr_valid      = %0d   <- mispredict vi predicted_taken != branch_taken\n",
      "    corr_nxpc2      = 0x%08h (ky vong pc + branch_offset = 0x%08h)\n",
      "  => TO HOP NAY TAI HIEN DUOC o muc module.\n",
      "     bpu_flush=1 von dua tren gia dinh 'backstop DA chuyen huong dung o F+1'.\n",
      "     Khi backstop khong kich hoat, duong ong da di TUAN TU, nen viec chuyen\n",
      "     huong tai execute thuong can HAI bong bong chu khong phai mot.\n",
      "     CAU HOI MO (ngoai tam kiem chung muc module): mot bong bong co du de lõi\n",
      "     ap dung duoc bpu_nxpc2 hay khong -- phu thuoc cach lõi dung bpu_flush va\n",
      "     bpu_nxpc2. Can doi chieu RTL lõi de dong R3.\n",
      "=============================================================="},
      oB[2].pred_was_hit, oB[2].predicted_taken, oB[2].bpu_flush,
      oB[2].bpu_nxpc2_valid, oB[2].bpu_nxpc2, expB), UVM_NONE)

    chk(oB[2].bpu_flush === 2'd1,
        $sformatf("TH B: bpu_flush=%0d, ky vong 1 (!pred_was_hit va taken=1)", oB[2].bpu_flush));
    chk(oB[2].bpu_nxpc2_valid === 1'b1,
        $sformatf("TH B: corr_valid=%0d, ky vong 1", oB[2].bpu_nxpc2_valid));
    chk(oB[2].bpu_nxpc2 === expB,
        $sformatf("TH B: corr_nxpc2=0x%08h, ky vong pc+branch_offset=0x%08h",
                  oB[2].bpu_nxpc2, expB));

    phase.drop_objection(this, "12_2");
  endtask
endclass : corr_flush_decoupling_test


//==============================================================================
// 13.1 mux_priority_and_valid
// Sheet -- Flow: tao du TAM to hop cua (corr_valid, d_valid, f_valid) voi ba gia
//   tri dich phan biet; cac to hop co corr_valid doi hoi day nhanh qua du ba
//   tang; bo sung truong hop ngay sau reset va truong hop halt khong co nhanh.
// Sheet -- Pass: bpu_nxpc2 dung theo thu tu uu tien hieu chinh > du phong > fetch
//   trong ca tam to hop; bpu_nxpc2_valid = hop cua ba tin hieu; khi khong nguon
//   nao tich cuc thi valid=0 va bpu_nxpc2 = 32'd0.
// RTL Ref: bpu_ctrl.v
//
// KY THUAT: trong MOT chu ky, ba tang do BA nhanh khac nhau chi phoi --
//   slot EXECUTE -> corr, slot DECODE -> d, slot FETCH -> f. Day ba nhanh lien
//   tiep roi doc quan sat tai chu ky thu ba.
//==============================================================================
class mux_priority_and_valid_test extends hyb_redirect_base_test;
  `uvm_component_utils(mux_priority_and_valid_test)
  function new(string name, uvm_component parent); super.new(name, parent); endfunction
  function void build_phase(uvm_phase phase);
    test_label = "TEST_13_1 (mux_priority_and_valid)"; super.build_phase(phase);
  endfunction

  localparam bit [31:0] PC_CORR_BASE = 32'h0000_0500;
  localparam bit [31:0] PC_D         = 32'h0000_0600;   // chua gap -> d_valid duoc
  bit [31:0] corr_tgt, d_tgt, f_tgt;
  string tbl;

  // Dung mot chu ky co (corr, d, f) theo y muon.
  task automatic run_cell(input int idx, input bit want_c, input bit want_d, input bit want_f,
                      output bpu_pipe_obs_t o);
    bit [31:0] pc_c;
    int base;
    pc_c = PC_CORR_BASE + (idx * 32'h0000_0010);
    h.idle(4);
    // B0: se o tang EXECUTE tai chu ky quan tam.
    //   nxpc2 = UT       -> pred_was_hit = 0, f_valid = 0 cho chinh no
    //   opcode ADDI      -> d_valid = 0 o chu ky decode cua no
    //   => predicted_taken = 0; corr_valid = branch_taken
    h.push_branch(.pc(pc_c), .taken(want_c), .offset(corr_tgt - pc_c),
                  .opcode(OPC_NOP), .is_branch(1'b1),
                  .ovr_nxpc2(1'b1), .nxpc2(ADDR_UT));
    // B1: se o tang DECODE -> quyet dinh d_valid
    h.push_branch(.pc(PC_D), .taken(1'b0), .offset(32'h40),
                  .opcode(want_d ? OPC_BR : OPC_NOP),
                  .btf(d_tgt - PC_D), .is_branch(1'b0),
                  .ovr_nxpc2(1'b1), .nxpc2(ADDR_UT));
    base = h.num_cycles();
    // B2: se o tang FETCH -> quyet dinh f_valid
    h.push_branch(.pc(32'h0000_0610), .taken(1'b0), .offset(32'h40),
                  .opcode(OPC_NOP), .is_branch(1'b0),
                  .ovr_nxpc2(1'b1), .nxpc2(want_f ? ADDR_TK : ADDR_UT));
    o = h.obs_at_cycle(base);
    h.drain();
  endtask

  task automatic do_cell(int idx, bit c, bit d, bit f);
    bpu_pipe_obs_t o;
    bit [31:0] exp;
    bit        exp_v;
    string     src;
    run_cell(idx, c, d, f, o);
    exp_v = c | d | f;
    if      (c) begin exp = corr_tgt; src = "corr";     end
    else if (d) begin exp = d_tgt;    src = "backstop"; end
    else if (f) begin exp = f_tgt;    src = "fetch";    end
    else        begin exp = 32'd0;    src = "none";     end
    chk(o.bpu_nxpc2_valid === exp_v,
        $sformatf("(c=%0d d=%0d f=%0d): valid=%0d, ky vong %0d", c, d, f, o.bpu_nxpc2_valid, exp_v));
    chk(o.bpu_nxpc2 === exp,
        $sformatf("(c=%0d d=%0d f=%0d): nxpc2=0x%08h, ky vong 0x%08h (nguon %s)",
                  c, d, f, o.bpu_nxpc2, exp, src));
    tbl = {tbl, $sformatf("  |  %0d  | %0d | %0d | %0d | 0x%08h | %s\n",
                          c, d, f, o.bpu_nxpc2_valid, o.bpu_nxpc2, src)};
  endtask

  task run_phase(uvm_phase phase);
    bpu_backdoor   bd;
    bpu_pipe_obs_t o;
    int i;
    super.run_phase(phase);
    bd = tb.module_env.backdoor;
    phase.raise_objection(this, "13_1");

    //---- PHA A: ngay sau reset -> khong nguon nao tich cuc -----------------
    phase_of("A_right_after_reset");
    #100ns;
    chk(bd.read_bpu_nxpc2_valid() === 1'b0, "ngay sau reset: bpu_nxpc2_valid != 0");
    chk(bd.read_bpu_nxpc2()       === 32'd0, "ngay sau reset: bpu_nxpc2 != 0");

    setup_addresses();
    corr_tgt = 32'hAAAA_0000;
    d_tgt    = 32'hBBBB_0000;
    f_tgt    = bd.read_btb_target(ADDR_TK[11:2]);
    tbl = "";

    //---- PHA B: du TAM to hop (corr, d, f) --------------------------------
    phase_of("B_eight_combinations");
    for (i = 0; i < 8; i++)
      do_cell(i, i[2], i[1], i[0]);

    `uvm_info(test_label, $sformatf({
      "\n===== MUX: uu tien corr > backstop > fetch =====\n",
      "  | c | d | f | vld |   bpu_nxpc2   | nguon thang\n",
      "  |---|---|---|-----|---------------|-------------\n", "%s",
      "  corr_tgt=0x%08h  d_tgt=0x%08h  f_tgt=0x%08h\n",
      "==============================================="},
      tbl, corr_tgt, d_tgt, f_tgt), UVM_NONE)

    //---- PHA C: halt, khong co nhanh -> khong chuyen huong -----------------
    phase_of("C_halt_no_branch");
    h.idle(4);
    h.idle(3, 2'd0, 1'b1);            // ba chu ky halt=1, khong nhanh
    o = h.obs_at_cycle(h.num_cycles() - 1);
    chk(o.bpu_nxpc2_valid === 1'b0,
        $sformatf("halt khong nhanh: valid=%0d, ky vong 0", o.bpu_nxpc2_valid));
    chk(o.bpu_nxpc2 === 32'd0,
        $sformatf("halt khong nhanh: nxpc2=0x%08h, ky vong 0", o.bpu_nxpc2));

    phase.drop_objection(this, "13_1");
  endtask
endclass : mux_priority_and_valid_test
