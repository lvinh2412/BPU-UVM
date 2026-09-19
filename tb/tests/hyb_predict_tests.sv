//------------------------------------------------------------------------------
// FILE: tests/hyb_predict_tests.sv
//
//   8.1 predict_mux_nxpc2                  [C] gop 6 test cu (choice/local/global
//                                              _prediction, predict_pc_nxpc,
//                                              predict_pc_equals_nxpc, predict_stable)
//   8.2 predict_index_alignment            [D] moi -- DesignNotes R1, phia du doan
//   9.1 precompute_gating_and_opcode_scope [C] gop precompute_opcode + precompute_flush
//                                              + spec_disabled
//
// Ke thua hyb_redirect_base_test (tests/hyb_redirect_tests.sv) -> include SAU tep do.
//
//==============================================================================
// VI SAO SAU MUC CU DEU SAI TIEN DE
//   Ca sau test cu deu bo lo du doan qua DUONG PC: chung cho bpu_nxpc2 == nxpc+4
//   (hieu chinh "C3" cua ban decode). Ban hybrid khong con ngo ra
//   predict_taken_pc (bpu_predictor.v chi con predict_taken_nxpc2) va
//   duong hieu chinh dung pc+4 chu khong phai nxpc+4 (bpu_ctrl.v). Mo ta
//   dung cua bo chon nam gon trong MOT dong:
//
//       predict_taken_nxpc2 = choice_data_nxpc2[1] ? global_pht_data_nxpc2[1]
//                                                  : local_pht_data_nxpc2[1]
//
//   nen muc moi kiem thang tren dong do.
//
//==============================================================================
// HAI CHE DO QUAN SAT DUNG TRONG TEP NAY
//
//   (1) DUONG THAT -- apply()/observe_at() chi EP CHAN GIAO TIEP.
//       force_predict_inputs ghi de net cua INTERFACE, nen monitor va DUT thay
//       cung mot bo gia tri => reference model van chay dung => SCOREBOARD SONG.
//       Moi pha dung de nang do phu (cp_predict_taken_nxpc2, cp_choice_decision,
//       cp_predictor_agreement, cx_btb_nxpc2_x_predict_nxpc2) BAT BUOC dung che
//       do nay: bon coverpoint do lay mau tu SHADOW STATE cua reference, nen ep
//       bang backdoor vao bang cua DUT khong nang duoc mot phan tram nao.
//
//   (2) CUA SO BACKDOOR -- tables_*() ep them local_pht / global_pht / choice / ghr.
//       Ep bang noi bo thi reference khong nhin thay => se lech. De KHONG phai
//       ha scoreboard xuong INFO, moi cua so backdoor deu chay voi
//         flush_in = 2 (fetch_ready = 0)  va  is_branch = 0
//       => f_valid = d_valid = corr_valid = 0 => ca DUT lan reference deu cho
//       bpu_nxpc2_valid = 0, bpu_nxpc2 = 0, bpu_flush = 0. Khong co o nao lech.
//       Bon thanh ghi carry-down local/global co lech trong cua so (bpu_ctrl.v
//       khong qua fetch_ready), nhung chung chi duoc dung khi is_branch=1; vi vay
//       tables_free() nha ep roi chay them vai chu ky is_branch=0 de duong ong
//       nap lai tu trang thai that TRUOC khi co bat ky nhanh nao.
//       => ca tep nay KHONG can scoreboard_not_applicable.
//==============================================================================


// Anh chup mot chu ky nhin tu tang FETCH.
typedef struct {
  bit        hit;      // btb_valid_nxpc2       (bpu_reg.v)
  bit [1:0]  lp;       // local_pht_data_nxpc2  (bpu_reg.v)
  bit [1:0]  gp;       // global_pht_data_nxpc2 (bpu_reg.v)
  bit [1:0]  ch;       // choice_data_nxpc2     (bpu_reg.v)
  bit        pt;       // predict_taken_nxpc2   (bpu_predictor.v)
  bit [31:0] tgt;      // btb_target_nxpc2      (bpu_reg.v)
  bit        fib;      // fetch_is_branch       (bpu_ctrl.v)
  bit        fr;       // fetch_ready           (bpu_ctrl.v)
  bit        fv;       // f_valid               (bpu_ctrl.v)
  bit        dv;       // d_valid               (bpu_ctrl.v)
  bit        cv;       // corr_valid            (bpu_ctrl.v)
  bit [31:0] outp;     // bpu_nxpc2
  bit        outv;     // bpu_nxpc2_valid
  bit [1:0]  fl;       // bpu_flush
} bpu_fetch_obs_t;


//==============================================================================
// BASE cho lo 2: them mot nguyen thuy lai theo CHU KY va mot ham chup.
//==============================================================================
class hyb_fetch_base_test extends hyb_redirect_base_test;

  // Dia chi trung tinh dung cho cac chan khong phai doi tuong do. Ba chi muc
  // 1020/1021/1022 trung voi khe trong cua bpu_pipe_helper, nen khong bao gio
  // va cham voi ADDR_TK / ADDR_NT / ADDR_UT.
  localparam bit [31:0] NEU_PC    = 32'h0000_0FF0;   // idx 1020
  localparam bit [31:0] NEU_NXPC  = 32'h0000_0FF4;   // idx 1021
  localparam bit [31:0] NEU_NXPC2 = 32'h0000_0FF8;   // idx 1022

  virtual bpu_if pvif;

  function new(string name, uvm_component parent); super.new(name, parent); endfunction

  function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    // connect_phase cua UVM chay tu duoi len, nen agent da gan monitor.vif xong.
    pvif = tb.bpu.tx_agent.monitor.vif;
  endfunction

  //--------------------------------------------------------------------------
  // apply -- lai DUNG MOT chu ky bang duong ep chan giao tiep.
  //
  //   Dat gia tri tai canh XUONG (giong bpu_if::drive_bpu_input) roi
  //   tra ve o GIUA chu ky. Tai thoi diem tra ve:
  //     - moi thanh ghi VAN giu gia tri cua chu ky nay (canh len ke tiep chua toi)
  //     - moi ngo ra to hop DA phan anh bo ngo vao vua dat
  //   Day dung la diem nhin ma bpu_pipe_helper dung, va cung la gia tri monitor
  //   se lay mau tai canh len ke tiep.
  //--------------------------------------------------------------------------
  protected task automatic apply(input bit [31:0] pc,
                                 input bit [31:0] nxpc,
                                 input bit [31:0] nxpc2,
                                 input bit [6:0]  opcode,
                                 input bit [31:0] btf       = 32'h0,
                                 input bit [1:0]  flush_in  = 2'd0,
                                 input bit        halt      = 1'b0,
                                 input bit        is_branch = 1'b0,
                                 input bit        taken     = 1'b0,
                                 input bit [31:0] offset    = 32'h0);
    @(negedge pvif.clock);
    tb.module_env.backdoor.force_predict_inputs(
        .pc(pc), .nxpc(nxpc), .fetch_opcode(opcode), .branch_target_fetch(btf),
        .flush_in(flush_in), .halt(halt), .nxpc2(nxpc2), .is_branch(is_branch),
        .branch_taken(taken), .branch_offset(offset));
    #1ns;
  endtask

  //--------------------------------------------------------------------------
  // apply_now -- dat bo ngo vao NGAY LAP TUC, khong cho canh xuong.
  //   Chi dung khi phai doi ngo vao trong CUNG nua chu ky voi mot su kien bat
  //   dong bo (vd: vua assert rst_n giua chu ky va phai ngung phat lenh truoc
  //   canh len ke tiep). Moi truong hop khac dung apply().
  //--------------------------------------------------------------------------
  protected task automatic apply_now(input bit [31:0] pc,
                                     input bit [31:0] nxpc,
                                     input bit [31:0] nxpc2,
                                     input bit [6:0]  opcode,
                                     input bit [31:0] btf       = 32'h0,
                                     input bit [1:0]  flush_in  = 2'd0,
                                     input bit        halt      = 1'b0,
                                     input bit        is_branch = 1'b0,
                                     input bit        taken     = 1'b0,
                                     input bit [31:0] offset    = 32'h0);
    tb.module_env.backdoor.force_predict_inputs(
        .pc(pc), .nxpc(nxpc), .fetch_opcode(opcode), .branch_target_fetch(btf),
        .flush_in(flush_in), .halt(halt), .nxpc2(nxpc2), .is_branch(is_branch),
        .branch_taken(taken), .branch_offset(offset));
    #0.1ns;
  endtask

  protected task automatic apply_now_idle();
    apply_now(.pc(NEU_PC), .nxpc(NEU_NXPC), .nxpc2(NEU_NXPC2), .opcode(OPC_NOP));
  endtask

  // Lai n chu ky nghi trung tinh (khong nhanh, fetch tier tat vi nxpc2 trung tinh).
  protected task automatic apply_idle(int n = 1, bit [1:0] flush_in = 2'd0);
    repeat (n) apply(.pc(NEU_PC), .nxpc(NEU_NXPC), .nxpc2(NEU_NXPC2),
                     .opcode(OPC_NOP), .flush_in(flush_in));
  endtask

  // Tra bus lai cho driver. LUON goi truoc khi dung lai drive_branch()/helper --
  // force la sticky, khong nha thi moi kich thich sau deu bi ghi de.
  protected task automatic bus_free();
    tb.module_env.backdoor.release_predict_inputs();
    repeat (3) @(negedge pvif.clock);
    #1ns;
  endtask

  //--------------------------------------------------------------------------
  // reset_by_force -- assert rst_n bang cach ep net cua clock_and_reset_if.
  //   Can thiet vi clock_and_reset_if chi lai duoc `reset` tai canh len clk
  //   (always @(posedge clock)), nen mot sequence khong the assert giua chu ky.
  //
  //   Cung la cach DUY NHAT de mot muc dung lai canh nhieu lan trong cung mot
  //   lan chay: cac chuoi huan luyen (vong "1 re + 10 khong re", nhanh dau tai
  //   dia chi la ghi THANG WT nho btb_valid_pc=0, ...) chi cho dung ket qua khi
  //   xuat phat tu trang thai sach. Goi lai chung tren mot may da co trang thai
  //   se ra canh khac -- xem ghi chu o build_scene() cua nhom 6.
  //--------------------------------------------------------------------------
  protected task automatic reset_by_force(int n_cycles = 3);
    bpu_backdoor bd = tb.module_env.backdoor;
    bd.force_tb_reset(1'b1);
    repeat (n_cycles) @(negedge pvif.clock);
    bd.release_tb_reset();
    repeat (3) @(negedge pvif.clock);
    h.reset_pipe();
    #50ns;
  endtask

  //--------------------------------------------------------------------------
  // snap -- chup toan bo diem quan sat cua chu ky hien tai.
  //--------------------------------------------------------------------------
  protected function automatic bpu_fetch_obs_t snap();
    bpu_backdoor bd = tb.module_env.backdoor;
    bpu_fetch_obs_t o;
    o.hit  = bd.read_btb_valid_nxpc2();
    o.lp   = bd.read_local_pht_data_nxpc2();
    o.gp   = bd.read_global_pht_data_nxpc2();
    o.ch   = bd.read_choice_data_nxpc2();
    o.pt   = bd.read_predict_taken_nxpc2();
    o.tgt  = bd.read_btb_target_nxpc2();
    o.fib  = bd.read_fetch_is_branch();
    o.fr   = bd.read_fetch_ready();
    o.fv   = bd.read_f_valid();
    o.dv   = bd.read_d_valid();
    o.cv   = bd.read_corr_valid();
    o.outp = bd.read_bpu_nxpc2();
    o.outv = bd.read_bpu_nxpc2_valid();
    o.fl   = bd.read_bpu_flush();
    return o;
  endfunction

  //--------------------------------------------------------------------------
  // observe_at -- giu nxpc2 tai mot dia chi trong hai chu ky roi chup.
  //   Chay o DUONG THAT (khong ep bang noi bo) nen day cung la nguon lay mau
  //   cho cp_predict_taken_nxpc2 / cp_choice_decision / cp_predictor_agreement /
  //   cx_btb_nxpc2_x_predict_nxpc2 -- ca bon deu co iff(btb_valid_nxpc2).
  //--------------------------------------------------------------------------
  protected task automatic observe_at(input bit [31:0] nxpc2,
                                      input bit [1:0]  flush_in,
                                      output bpu_fetch_obs_t o);
    apply(.pc(NEU_PC), .nxpc(NEU_NXPC), .nxpc2(nxpc2), .opcode(OPC_NOP),
          .flush_in(flush_in));
    apply(.pc(NEU_PC), .nxpc(NEU_NXPC), .nxpc2(nxpc2), .opcode(OPC_NOP),
          .flush_in(flush_in));
    o = snap();
  endtask

  protected function void show_fetch(string tag, bit [31:0] nxpc2, bpu_fetch_obs_t o);
    `uvm_info(test_label, $sformatf(
      "%-30s nxpc2=0x%08h | hit=%0d local=%0d(%02b) global=%0d(%02b) choice=%0d(%02b) => predT=%0d | tgt=0x%08h out=0x%08h vld=%0d",
      tag, nxpc2, o.hit, o.lp[1], o.lp, o.gp[1], o.gp, o.ch[1], o.ch, o.pt,
      o.tgt, o.outp, o.outv), UVM_NONE)
  endfunction

  //--------------------------------------------------------------------------
  // Kiem tien de cua mot canh dung o tang fetch TRUOC khi doi chieu ket luan.
  // Cung tinh than voi assert_cell() cua lo 1, nhung cho ba bit dau vao bo chon.
  //--------------------------------------------------------------------------
  //==========================================================================
  // CUA SO BACKDOOR -- dat bang noi bo, roi TRA LAI dung gia tri cu.
  //
  //   BAY: ghi thang vao BIEN (reg) khong tu khoi phuc. Gia tri da ghi nam lai
  //   cho toi lan gan thu tuc ke tiep, ma bpu_reg.v moi chu ky chi gan lai DUNG
  //   MOT phan tu (chi muc theo pc: bpu_reg.v). Mot o bi ghi
  //   de se giu gia tri do gan nhu vinh vien -> bang cua DUT lech han so voi
  //   shadow state cua reference va scoreboard bao sai tu do ve sau. GHR cung
  //   vay: dong "ghr <= ghr" chi chep lai chinh gia tri da ghi.
  //
  //   Vi vay moi lan dat deu di qua bd_set_* de nho gia tri goc, va
  //   bd_restore_all() ghi NGUOC ve gia tri goc khi ket thuc -- luc do bien giu
  //   lai dung gia tri cu va he thong tro ve dong bo.
  //
  //   DEPOSIT chu khong force: suot cua so nay flush_in = 2 va is_branch = 0
  //   (xem bd_window_open), nen khong co lenh ghi nao cua DUT vao btb /
  //   local_bht / local_pht / global_pht / choice / ghr. Khong co gi de chan,
  //   va deposit chay duoc tren ca hai trinh mo phong.
  //==========================================================================
  protected int       sv_l_i[$];   protected bit [1:0] sv_l_v[$];
  protected int       sv_g_i[$];   protected bit [1:0] sv_g_v[$];
  protected int       sv_c_i[$];   protected bit [1:0] sv_c_v[$];
  protected bit       sv_ghr_used; protected bit [9:0] sv_ghr_v;

  // Mo cua so backdoor: dua bus ve trang thai IM LANG TRUOC khi cham vao bang.
  //   Neu ep bang trong khi bus con giu vector cua pha truoc (nxpc2 tro toi mot
  //   o BTB hop le va flush_in=0) thi DUNG MOT chu ky se co f_valid cua DUT khac
  //   f_valid cua reference -> scoreboard bao lech mot lan.
  //   nxpc2 trung tinh (BTB truot) VA flush_in=2 -> f_valid=0 o ca hai phia du
  //   bang co bi ep the nao.
  protected task automatic bd_window_open();
    apply(.pc(NEU_PC), .nxpc(NEU_NXPC), .nxpc2(NEU_NXPC2), .opcode(OPC_NOP),
          .flush_in(2'd2));
  endtask

  protected task automatic bd_set_local_pht(int idx, bit [1:0] v);
    bpu_backdoor bd = tb.module_env.backdoor;
    if (!(idx inside {sv_l_i})) begin
      sv_l_i.push_back(idx); sv_l_v.push_back(bd.read_local_pht(idx));
    end
    bd.deposit_local_pht(idx, v);
  endtask

  protected task automatic bd_set_global_pht(int idx, bit [1:0] v);
    bpu_backdoor bd = tb.module_env.backdoor;
    if (!(idx inside {sv_g_i})) begin
      sv_g_i.push_back(idx); sv_g_v.push_back(bd.read_global_pht(idx));
    end
    bd.deposit_global_pht(idx, v);
  endtask

  protected task automatic bd_set_choice(int idx, bit [1:0] v);
    bpu_backdoor bd = tb.module_env.backdoor;
    if (!(idx inside {sv_c_i})) begin
      sv_c_i.push_back(idx); sv_c_v.push_back(bd.read_choice(idx));
    end
    bd.deposit_choice(idx, v);
  endtask

  protected task automatic bd_set_ghr(bit [9:0] v);
    bpu_backdoor bd = tb.module_env.backdoor;
    if (!sv_ghr_used) begin sv_ghr_used = 1'b1; sv_ghr_v = bd.read_ghr(); end
    bd.deposit_ghr(v);
  endtask

  protected task automatic bd_restore_all();
    bpu_backdoor bd = tb.module_env.backdoor;
    foreach (sv_l_i[i]) begin bd.deposit_local_pht(sv_l_i[i], sv_l_v[i]); end
    foreach (sv_g_i[i]) begin bd.deposit_global_pht(sv_g_i[i], sv_g_v[i]); end
    foreach (sv_c_i[i]) begin bd.deposit_choice(sv_c_i[i], sv_c_v[i]); end
    if (sv_ghr_used) begin bd.deposit_ghr(sv_ghr_v); sv_ghr_used = 1'b0; end
    sv_l_i.delete(); sv_l_v.delete();
    sv_g_i.delete(); sv_g_v.delete();
    sv_c_i.delete(); sv_c_v.delete();
    // Bon thanh ghi carry-down local/global da lech trong cua so (bpu_ctrl.v
    // khong qua fetch_ready); chay them vai chu ky is_branch=0 de chung nap lai
    // tu trang thai THAT truoc khi co bat ky nhanh nao.
    apply_idle(4);
  endtask

  // Kiem lai rang cua so backdoor da tra bang ve dung nhu truoc. Goi sau
  // bd_restore_all() o nhung muc con chay tiep bang duong that.
  protected function void check_restored(int lidx, int gidx, int cidx,
                                         bit [1:0] l0, bit [1:0] g0, bit [1:0] c0, bit [9:0] ghr0);
    bpu_backdoor bd = tb.module_env.backdoor;
    chk(bd.read_local_pht(lidx)  === l0,
        $sformatf("khoi phuc: local_pht[0x%03h]=%02b, ky vong %02b", lidx, bd.read_local_pht(lidx), l0));
    chk(bd.read_global_pht(gidx) === g0,
        $sformatf("khoi phuc: global_pht[%0d]=%02b, ky vong %02b", gidx, bd.read_global_pht(gidx), g0));
    chk(bd.read_choice(cidx)     === c0,
        $sformatf("khoi phuc: choice[%0d]=%02b, ky vong %02b", cidx, bd.read_choice(cidx), c0));
    chk(bd.read_ghr()            === ghr0,
        $sformatf("khoi phuc: ghr=0x%03h, ky vong 0x%03h", bd.read_ghr(), ghr0));
  endfunction

  protected function void assert_fetch_cell(string lbl, bpu_fetch_obs_t o,
                                            bit exp_hit, bit exp_l, bit exp_g, bit exp_c);
    chk(o.hit   === exp_hit, $sformatf("%s: btb_valid_nxpc2=%0d, canh dung SAI (can %0d)",
                                       lbl, o.hit, exp_hit));
    chk(o.lp[1] === exp_l,   $sformatf("%s: local_pht_data_nxpc2[1]=%0d, canh dung SAI (can %0d)",
                                       lbl, o.lp[1], exp_l));
    chk(o.gp[1] === exp_g,   $sformatf("%s: global_pht_data_nxpc2[1]=%0d, canh dung SAI (can %0d)",
                                       lbl, o.gp[1], exp_g));
    chk(o.ch[1] === exp_c,   $sformatf("%s: choice_data_nxpc2[1]=%0d, canh dung SAI (can %0d)",
                                       lbl, o.ch[1], exp_c));
  endfunction

endclass : hyb_fetch_base_test


//==============================================================================
// 8.1 predict_mux_nxpc2
//
// Sheet -- Flow: ep du tam to hop cua ba bit (choice_data_nxpc2[1],
//   local_pht_data_nxpc2[1], global_pht_data_nxpc2[1]); voi moi nhanh chon, thay
//   doi nxpc2 va GHR de xac nhan dung nguon du lieu; pha cuoi giu nguyen ngo vao
//   va chay 50 chu ky.
// Sheet -- Pass: predict_taken_nxpc2 dung bang chan tri trong ca tam to hop; khi
//   choice[1]=0 ngo ra bam local_pht_data_nxpc2[1], khi choice[1]=1 bam
//   global_pht_data_nxpc2[1]; lich su hoac GHR khac nhau cho du doan khac nhau;
//   ngo ra khong doi trong 50 chu ky nghi.
// RTL Ref: bpu_predictor.v
//==============================================================================
class predict_mux_nxpc2_test extends hyb_fetch_base_test;
  `uvm_component_utils(predict_mux_nxpc2_test)
  function new(string name, uvm_component parent); super.new(name, parent); endfunction
  function void build_phase(uvm_phase phase);
    test_label = "TEST_8_1 (predict_mux_nxpc2)"; super.build_phase(phase);
  endfunction

  // Dia chi phu cho pha A: mot vong "1 re + 10 khong re" tai mot dia chi la.
  //   - nhanh DAU tai dia chi la co btb_valid_pc=0, nen bpu_predictor.v ghi
  //     THANG WT vao local_pht[0] -> keo bit local cua moi dia chi co
  //     local_bht = 0 (nhu ADDR_NT) len 1;
  //   - 10 nhanh khong re sau do dua GHR ve 0 va ghi vao local_pht[1,2,4,...,512],
  //     KHONG cham local_pht[0] nua, cung khong cham chi muc 64/128.
  //   Nho vay tach duoc bit local khoi bit global tai ADDR_NT ma van chay hoan
  //   toan bang duong cap nhat that -- khong ep gi, scoreboard van song.
  localparam bit [31:0] ADDR_W = 32'h0000_0800;   // idx 512

  protected task automatic warm_local_zero_entry();
    drive_branch(ADDR_W, 1'b1, 32'h40);
    repeat (10) drive_branch(ADDR_W, 1'b0, 32'h40);
  endtask

  task run_phase(uvm_phase phase);
    bpu_backdoor    bd;
    bpu_fetch_obs_t o, o2;
    bit [11:0] lidx_tk, lidx_nt;
    int        gidx_tk, gidx_nt, gidx_skew;
    int        cidx_tk, cidx_nt;
    bit [1:0]  sav_l_tk, sav_l_nt, sav_g_tk, sav_c_tk;
    bit [9:0]  sav_ghr;
    bit        c, l, g, expp;
    int        k;
    bit [31:0] hold_out;
    bit        hold_v, hold_pt;
    bit [1:0]  hold_fl;
    string     tbl;

    super.run_phase(phase);
    bd = tb.module_env.backdoor;
    phase.raise_objection(this, "8_1");
    #100ns;

    //=========================================================================
    // PHA A: bo chon tren DUONG THAT.
    //   Bon coverpoint co iff(btb_valid_nxpc2) lay mau tu shadow state cua
    //   reference, nen chi pha nay moi nang duoc chung. Khong ep gi o day.
    //=========================================================================
    phase_of("A_real_path_mux");
    setup_addresses();          // TK: 24 nhanh re ; NT: 6 nhanh khong re

    // A1 -- ADDR_TK : choice[1]=0 => bam LOCAL, va o day local != global,
    //       nen day la bang chung "choice=0 chon local" tren duong that.
    observe_at(ADDR_TK, 2'd0, o);
    show_fetch("A1 TK choice=0 -> local", ADDR_TK, o);
    assert_fetch_cell("A1 TK", o, .exp_hit(1'b1), .exp_l(1'b1), .exp_g(1'b0), .exp_c(1'b0));
    chk(o.pt === 1'b1, $sformatf("A1 TK: predict_taken_nxpc2=%0d, ky vong 1 (= local[1])", o.pt));

    // A2 -- ADDR_NT : choice[1]=1 => bam GLOBAL (luc nay local == global == 0)
    observe_at(ADDR_NT, 2'd0, o);
    show_fetch("A2 NT choice=1 -> global", ADDR_NT, o);
    assert_fetch_cell("A2 NT", o, .exp_hit(1'b1), .exp_l(1'b0), .exp_g(1'b0), .exp_c(1'b1));
    chk(o.pt === 1'b0, $sformatf("A2 NT: predict_taken_nxpc2=%0d, ky vong 0 (= global[1])", o.pt));

    // A3 -- nang rieng local_pht[0] len 1 (ADDR_NT co local_bht=0 nen doc o do)
    //       trong khi bit global cua ADDR_NT van bang 0
    //       => choice[1]=1 VA local != global: bo chon phai bo local, lay global.
    bus_free();
    warm_local_zero_entry();
    observe_at(ADDR_NT, 2'd0, o);
    show_fetch("A3 NT choice=1, local!=global", ADDR_NT, o);
    assert_fetch_cell("A3 NT", o, .exp_hit(1'b1), .exp_l(1'b1), .exp_g(1'b0), .exp_c(1'b1));
    chk(o.pt === 1'b0, $sformatf(
        "A3 NT: predict_taken_nxpc2=%0d, ky vong 0 -- choice[1]=1 phai bam GLOBAL(0) chu khong phai LOCAL(1)",
        o.pt));

    // A4 -- ADDR_TK sau vong ham: choice[1]=0 va local == global == 1
    observe_at(ADDR_TK, 2'd0, o);
    show_fetch("A4 TK choice=0, local==global", ADDR_TK, o);
    assert_fetch_cell("A4 TK", o, .exp_hit(1'b1), .exp_l(1'b1), .exp_g(1'b1), .exp_c(1'b0));
    chk(o.pt === 1'b1, $sformatf("A4 TK: predict_taken_nxpc2=%0d, ky vong 1", o.pt));

    `uvm_info(test_label, {
      "\n=== PHA A (duong that) da cham du bon diem lay mau co iff(btb_valid_nxpc2) ===\n",
      "  predict_T (A1,A4) / predict_NT (A2,A3)\n",
      "  agree     (A2,A4) / disagree   (A1,A3)\n",
      "  use_local (A1,A4) / use_global (A2,A3)\n",
      "==========================================================================="}, UVM_NONE)

    //=========================================================================
    // PHA B: bang chan tri day du 8 to hop (cua so backdoor).
    //   Suot cua so: flush_in = 2 (fetch_ready=0) va is_branch = 0, nen
    //   f_valid = d_valid = corr_valid = 0 o CA DUT lan reference -> ngo ra deu
    //   bang 0 -> khong o nao lech -> scoreboard van la checker hop le.
    //=========================================================================
    phase_of("B_truth_table_8");
    bd_window_open();
    cidx_tk = ADDR_TK[11:2];
    cidx_nt = ADDR_NT[11:2];
    lidx_tk = bd.read_local_bht(cidx_tk);   // chi muc local_pht doc tai nxpc2=TK
    lidx_nt = bd.read_local_bht(cidx_nt);
    gidx_tk = cidx_tk;                      // GHR bi ep ve 0 => chi muc = nxpc2_index
    gidx_nt = cidx_nt;
    gidx_skew = cidx_tk ^ 10'h155;          // chi muc global khi GHR = 0x155
    sav_l_tk = bd.read_local_pht(lidx_tk);
    sav_l_nt = bd.read_local_pht(lidx_nt);
    sav_g_tk = bd.read_global_pht(gidx_tk);
    sav_c_tk = bd.read_choice(cidx_tk);
    sav_ghr  = bd.read_ghr();
    chk(bd.read_btb_valid(cidx_tk) === 1'b1,
        "chuan bi B: btb_valid[TK] phai = 1 thi moi doc duoc du doan tai nxpc2");
    chk(lidx_tk !== lidx_nt, $sformatf(
        "chuan bi B: local_bht[TK]=0x%03h va local_bht[NT]=0x%03h phai KHAC nhau thi pha C moi tach duoc hai o",
        lidx_tk, lidx_nt));

    bd_set_ghr(10'd0);
    tbl = "\n=== 8.1 BANG CHAN TRI predict_taken_nxpc2 (bpu_predictor.v) ===\n";
    tbl = {tbl, "   choice[1]  local[1]  global[1] | ky vong | do duoc | nguon\n"};
    tbl = {tbl, "   ------------------------------------------------------------\n"};
    for (k = 0; k < 8; k++) begin
      c = k[2]; l = k[1]; g = k[0];
      expp = c ? g : l;
      bd_set_choice    (cidx_tk, c ? `WT : `WNT);
      bd_set_local_pht (lidx_tk, l ? `ST : `SNT);
      bd_set_global_pht(gidx_tk, g ? `ST : `SNT);
      observe_at(ADDR_TK, 2'd2, o);
      chk(o.ch[1] === c && o.lp[1] === l && o.gp[1] === g, $sformatf(
          "to hop %0d: canh dung SAI -- doc lai duoc choice=%0d local=%0d global=%0d (can %0d/%0d/%0d)",
          k, o.ch[1], o.lp[1], o.gp[1], c, l, g));
      chk(o.pt === expp, $sformatf(
          "to hop (choice=%0d local=%0d global=%0d): predict_taken_nxpc2=%0d, ky vong %0d",
          c, l, g, o.pt, expp));
      chk(o.outv === 1'b0, $sformatf(
          "to hop (choice=%0d local=%0d global=%0d): bpu_nxpc2_valid=%0d, ky vong 0 (fetch_ready=0)",
          c, l, g, o.outv));
      tbl = {tbl, $sformatf("       %0d          %0d         %0d     |    %0d    |    %0d    | %-6s%s\n",
                            c, l, g, expp, o.pt, c ? "global" : "local",
                            (o.pt === expp) ? "" : "   <== SAI")};
    end
    tbl = {tbl, "   ------------------------------------------------------------\n"};
    tbl = {tbl, "   Ket luan: bo chon la MUX 2->1 thuan; choice[1] la chan chon, khong\n"};
    tbl = {tbl, "   co dieu kien nao khac xen vao (khong phu thuoc btb_valid_nxpc2).\n"};
    tbl = {tbl, "================================================================"};
    `uvm_info(test_label, tbl, UVM_NONE)

    //=========================================================================
    // PHA C: nhanh chon LOCAL -- doi nxpc2 doi ket qua, doi GHR thi KHONG.
    //=========================================================================
    phase_of("C_source_local");
    bd_set_choice    (cidx_tk, `WNT);    // choice[1] = 0 o ca hai chi muc
    bd_set_choice    (cidx_nt, `WNT);
    bd_set_local_pht (lidx_tk, `ST);     // local tai TK = 1
    bd_set_local_pht (lidx_nt, `SNT);    // local tai NT = 0
    bd_set_global_pht(gidx_tk, `SNT);
    bd_set_global_pht(gidx_nt, `SNT);

    observe_at(ADDR_TK, 2'd2, o);
    observe_at(ADDR_NT, 2'd2, o2);
    `uvm_info(test_label, $sformatf(
      "C nguon LOCAL: nxpc2=TK -> local_pht[0x%03h]=%02b predT=%0d ; nxpc2=NT -> local_pht[0x%03h]=%02b predT=%0d",
      lidx_tk, o.lp, o.pt, lidx_nt, o2.lp, o2.pt), UVM_NONE)
    chk(o.pt === 1'b1 && o2.pt === 1'b0, $sformatf(
        "C: doi nxpc2 phai doi du doan khi choice[1]=0 (do duoc %0d va %0d, ky vong 1 va 0)",
        o.pt, o2.pt));

    // GHR chi doi chi muc GLOBAL -> nhanh local phai tro
    bd_set_ghr(10'h155);
    observe_at(ADDR_TK, 2'd2, o2);
    chk(o2.pt === 1'b1, $sformatf(
        "C: doi GHR (0x000 -> 0x155) khong duoc lam doi du doan khi choice[1]=0, do duoc %0d", o2.pt));
    bd_set_ghr(10'd0);

    //=========================================================================
    // PHA D: nhanh chon GLOBAL -- doi GHR doi ket qua, doi nxpc2 cung doi.
    //=========================================================================
    phase_of("D_source_global");
    bd_set_choice    (cidx_tk, `WT);     // choice[1] = 1 o ca hai chi muc
    bd_set_choice    (cidx_nt, `WT);
    bd_set_local_pht (lidx_tk, `ST);     // local = 1 o ca hai: neu bam local se ra 1
    bd_set_local_pht (lidx_nt, `ST);
    bd_set_global_pht(gidx_tk,   `ST);   // ghr=0     -> doc o nay
    bd_set_global_pht(gidx_skew, `SNT);  // ghr=0x155 -> doc o nay
    bd_set_global_pht(gidx_nt,   `SNT);

    bd_set_ghr(10'd0);
    observe_at(ADDR_TK, 2'd2, o);
    bd_set_ghr(10'h155);
    observe_at(ADDR_TK, 2'd2, o2);
    `uvm_info(test_label, $sformatf(
      "D nguon GLOBAL: ghr=0x000 -> global_pht[%0d]=%02b predT=%0d ; ghr=0x155 -> global_pht[%0d]=%02b predT=%0d (local[1]=1 o ca hai)",
      gidx_tk, o.gp, o.pt, gidx_skew, o2.gp, o2.pt), UVM_NONE)
    chk(o.pt === 1'b1 && o2.pt === 1'b0, $sformatf(
        "D: doi GHR phai doi du doan khi choice[1]=1 (do duoc %0d va %0d, ky vong 1 va 0)", o.pt, o2.pt));
    chk(o2.lp[1] === 1'b1,
        "D: local[1] phai van bang 1 khi GHR doi -- neu khong thi phep do khong tach duoc hai nguon");

    bd_set_ghr(10'd0);
    observe_at(ADDR_NT, 2'd2, o2);
    chk(o2.pt === 1'b0, $sformatf(
        "D: doi nxpc2 phai doi du doan khi choice[1]=1, do duoc %0d (ky vong 0)", o2.pt));

    // Tra bang ve dung gia tri cu roi kiem lai -- xem ghi chu o bd_restore_all().
    bd_restore_all();
    check_restored(lidx_tk, gidx_tk, cidx_tk, sav_l_tk, sav_g_tk, sav_c_tk, sav_ghr);
    chk(bd.read_local_pht(lidx_nt) === sav_l_nt, $sformatf(
        "khoi phuc: local_pht[0x%03h]=%02b, ky vong %02b", lidx_nt, bd.read_local_pht(lidx_nt), sav_l_nt));

    //=========================================================================
    // PHA E: on dinh -- giu nguyen ngo vao 50 chu ky, ngo ra khong duoc doi.
    //   Thay cho predict_stable_test cu: test do chi doc lai bon o trang thai o
    //   extract_phase, khong he giu ngo vao co dinh va khong kiem ngo ra.
    //=========================================================================
    phase_of("E_stable_50_cycles");
    apply(.pc(NEU_PC), .nxpc(NEU_NXPC), .nxpc2(ADDR_TK), .opcode(OPC_NOP), .flush_in(2'd0));
    o        = snap();
    hold_out = o.outp;  hold_v = o.outv;  hold_pt = o.pt;  hold_fl = o.fl;
    `uvm_info(test_label, $sformatf(
      "E: giu nguyen ngo vao (nxpc2=ADDR_TK) -- moc: predT=%0d bpu_nxpc2=0x%08h vld=%0d flush=%0d",
      hold_pt, hold_out, hold_v, hold_fl), UVM_NONE)
    chk(hold_v === 1'b1,
        "E: moc phai co bpu_nxpc2_valid=1 (BTB trung + du doan re) thi phep do moi co nghia");
    for (k = 0; k < 50; k++) begin
      apply(.pc(NEU_PC), .nxpc(NEU_NXPC), .nxpc2(ADDR_TK), .opcode(OPC_NOP), .flush_in(2'd0));
      o = snap();
      if (o.pt !== hold_pt || o.outp !== hold_out || o.outv !== hold_v || o.fl !== hold_fl)
        chk(1'b0, $sformatf(
          "E: chu ky %0d doi ngo ra du ngo vao khong doi: predT=%0d nxpc2=0x%08h vld=%0d flush=%0d",
          k, o.pt, o.outp, o.outv, o.fl));
    end
    chk(bd.read_btb_valid(cidx_tk) === 1'b1, "E: 50 chu ky nghi da xoa btb_valid[TK]");
    chk(bd.read_local_bht(cidx_tk) === lidx_tk,
        "E: 50 chu ky nghi da lam doi local_bht[TK] du is_branch = 0");
    chk(bd.read_ghr() === sav_ghr,
        $sformatf("E: 50 chu ky nghi da lam doi GHR (0x%03h -> 0x%03h)", sav_ghr, bd.read_ghr()));

    bus_free();
    phase.drop_objection(this, "8_1");
  endtask
endclass : predict_mux_nxpc2_test


//==============================================================================
// 8.2 predict_index_alignment
//
// Sheet -- Flow: dat hai dia chi nxpc2 trung bit [11:2] nhung khac bit cao (cach
//   nhau boi so cua 4 KB); quan sat du doan va btb_valid_nxpc2.
// Sheet -- Pass: hai dia chi trung chi muc cho cung ket qua du doan va cung trang
//   thai BTB, xac nhan hien tuong trung chi muc do KHONG co truong tag
//   (doi chieu DesignNotes R1).
// RTL Ref: bpu_reg.v
//==============================================================================
class predict_index_alignment_test extends hyb_fetch_base_test;
  `uvm_component_utils(predict_index_alignment_test)
  function new(string name, uvm_component parent); super.new(name, parent); endfunction
  function void build_phase(uvm_phase phase);
    test_label = "TEST_8_2 (predict_index_alignment)"; super.build_phase(phase);
  endfunction

  task run_phase(uvm_phase phase);
    bpu_backdoor    bd;
    bpu_fetch_obs_t base_o, o;
    bpu_pipe_obs_t  p0[3], p1[3];
    bit [31:0] alias_a[5];
    bit [31:0] miss_a;
    string     s;
    int        k;

    super.run_phase(phase);
    bd = tb.module_env.backdoor;
    phase.raise_objection(this, "8_2");
    #100ns;

    //---- PHA A: huan luyen mot dia chi -------------------------------------
    phase_of("A_train_base");
    setup_addresses();
    chk(bd.read_btb_valid(ADDR_TK[11:2])  === 1'b1, "chuan bi: btb_valid[TK] phai = 1");
    chk(bd.read_btb_target(ADDR_TK[11:2]) === (ADDR_TK + 32'h40),
        $sformatf("chuan bi: btb_target[TK]=0x%08h, ky vong 0x%08h",
                  bd.read_btb_target(ADDR_TK[11:2]), ADDR_TK + 32'h40));

    //---- PHA B: nam dia chi trung pc[11:2], cach nhau boi so 4 KB ----------
    // 0x100 / 0x1100 / 0x2100 / 0x3100 / 0xFFFF_F100 -- tat ca deu co [11:2]=64.
    phase_of("B_alias_4KB_multiples");
    alias_a = '{32'h0000_0100, 32'h0000_1100, 32'h0000_2100,
                32'h0000_3100, 32'hFFFF_F100};
    observe_at(alias_a[0], 2'd0, base_o);
    show_fetch("B moc (nxpc2 = 0x100)", alias_a[0], base_o);
    chk(base_o.hit === 1'b1, "B: moc phai co btb_valid_nxpc2=1 thi phep so sanh moi co nghia");

    s = "\n=== 8.2 TRUNG CHI MUC KHI KHONG CO TRUONG TAG (DesignNotes R1, phia du doan) ===\n";
    s = {s, "   nxpc2        [11:2]  btb_valid  btb_target   local  global  choice  predT\n"};
    s = {s, "   -----------------------------------------------------------------------\n"};
    for (k = 0; k < 5; k++) begin
      observe_at(alias_a[k], 2'd0, o);
      s = {s, $sformatf("   0x%08h   %4d       %0d      0x%08h    %0d      %0d       %0d      %0d\n",
                        alias_a[k], alias_a[k][11:2], o.hit, o.tgt,
                        o.lp[1], o.gp[1], o.ch[1], o.pt)};
      chk(alias_a[k][11:2] === alias_a[0][11:2],
          $sformatf("chuan bi B: 0x%08h khong trung [11:2] voi moc", alias_a[k]));
      chk(o.hit === base_o.hit,
          $sformatf("B 0x%08h: btb_valid_nxpc2=%0d khac moc %0d", alias_a[k], o.hit, base_o.hit));
      chk(o.tgt === base_o.tgt,
          $sformatf("B 0x%08h: btb_target_nxpc2=0x%08h khac moc 0x%08h",
                    alias_a[k], o.tgt, base_o.tgt));
      chk(o.lp === base_o.lp,
          $sformatf("B 0x%08h: local_pht_data_nxpc2=%02b khac moc %02b (chi muc local_bht[nxpc2] cung trung)",
                    alias_a[k], o.lp, base_o.lp));
      chk(o.gp === base_o.gp,
          $sformatf("B 0x%08h: global_pht_data_nxpc2=%02b khac moc %02b", alias_a[k], o.gp, base_o.gp));
      chk(o.ch === base_o.ch,
          $sformatf("B 0x%08h: choice_data_nxpc2=%02b khac moc %02b", alias_a[k], o.ch, base_o.ch));
      chk(o.pt === base_o.pt,
          $sformatf("B 0x%08h: predict_taken_nxpc2=%0d khac moc %0d", alias_a[k], o.pt, base_o.pt));
    end
    s = {s, "   -----------------------------------------------------------------------\n"};
    s = {s, "   Nam dia chi cach nhau boi so 4 KB deu cho CUNG mot ket qua: BTB khong\n"};
    s = {s, "   luu tag (bpu_reg.v) va ca ba chi muc du doan (local_bht[nxpc2],\n"};
    s = {s, "   nxpc2 ^ ghr, choice[nxpc2]) deu chi lay pc[11:2].\n"};
    s = {s, "==========================================================================="};
    `uvm_info(test_label, s, UVM_NONE)

    //---- PHA C: doi chung -- dia chi KHAC [11:2] phai truot ----------------
    // Neu thieu pha nay thi pha B co the "dung" chi vi moi dia chi deu trung.
    phase_of("C_negative_control");
    miss_a = 32'h0000_0104;                       // idx 65, chua bao gio duoc ghi
    chk(miss_a[11:2] !== alias_a[0][11:2], "chuan bi C: dia chi doi chung phai khac [11:2]");
    observe_at(miss_a, 2'd0, o);
    show_fetch("C doi chung (0x104, idx 65)", miss_a, o);
    chk(o.hit === 1'b0,
        $sformatf("C: btb_valid_nxpc2=%0d tai 0x104 (idx 65), ky vong 0 -- phep so o pha B khong duoc vacuous", o.hit));

    //---- PHA D: he qua that -- dia chi la CHIEM duoc duong chuyen huong ----
    phase_of("D_alias_hijacks_redirect");
    bus_free();
    probe3(.pc(32'h0000_0B00), .nxpc2(32'h0000_0100), .taken(1'b1),
           .opc_at_decode(OPC_NOP), .o(p0));
    probe3(.pc(32'h0000_0B00), .nxpc2(32'h0000_3100), .taken(1'b1),
           .opc_at_decode(OPC_NOP), .o(p1));
    `uvm_info(test_label, $sformatf({
      "\n=== 8.2 pha D: dia chi la o tang fetch chiem duoc duong chuyen huong ===\n",
      "  nxpc2 = 0x00000100 -> tai F: vld=%0d nxpc2=0x%08h\n",
      "  nxpc2 = 0x00003100 -> tai F: vld=%0d nxpc2=0x%08h  (cach 0x100 dung 12 KB)\n",
      "  Bo doan re toi mot dia chi CHUA TUNG duoc ghi, vi BTB tra loi theo chi muc.\n",
      "====================================================================="},
      p0[0].bpu_nxpc2_valid, p0[0].bpu_nxpc2,
      p1[0].bpu_nxpc2_valid, p1[0].bpu_nxpc2), UVM_NONE)
    chk(p0[0].bpu_nxpc2_valid === 1'b1, "D: moc 0x100 phai lam f_valid=1");
    chk(p1[0].bpu_nxpc2_valid === p0[0].bpu_nxpc2_valid,
        $sformatf("D: 0x3100 cho bpu_nxpc2_valid=%0d, moc 0x100 cho %0d",
                  p1[0].bpu_nxpc2_valid, p0[0].bpu_nxpc2_valid));
    chk(p1[0].bpu_nxpc2 === p0[0].bpu_nxpc2,
        $sformatf("D: 0x3100 cho bpu_nxpc2=0x%08h, moc 0x100 cho 0x%08h",
                  p1[0].bpu_nxpc2, p0[0].bpu_nxpc2));

    phase.drop_objection(this, "8_2");
  endtask
endclass : predict_index_alignment_test


//==============================================================================
// 9.1 precompute_gating_and_opcode_scope
//
// Sheet -- Flow: quet toan bo 128 gia tri fetch_opcode; quet flush_in qua ca bon
//   gia tri {0,1,2,3}; voi moi to hop, giu dieu kien cua tang fetch tich cuc
//   (BTB hit tai nxpc2 va predict T) roi quan sat f_valid va d_valid; theo tiep
//   toi execute cho truong hop opcode khac BCC voi is_branch=0.
// Sheet -- Pass: fetch_is_branch=1 duy nhat tai opcode 7'b1100011; fetch_ready=1
//   chi voi flush_in thuoc {0,1}, ca 2 va 3 deu cho 0. flush_in thuoc {2,3}:
//   f_valid = d_valid = 0. Opcode khac BCC: d_valid=0 nhung f_valid VAN co the
//   bang 1 vi f_valid khong kiem opcode; khi do tai execute is_branch=0 nen
//   bpu_flush=0 va corr_valid=0 (ghi nhan, doi chieu DesignNotes R1).
// RTL Ref: bpu_ctrl.v
//==============================================================================
class precompute_gating_and_opcode_scope_test extends hyb_fetch_base_test;
  `uvm_component_utils(precompute_gating_and_opcode_scope_test)
  function new(string name, uvm_component parent); super.new(name, parent); endfunction
  function void build_phase(uvm_phase phase);
    test_label = "TEST_9_1 (precompute_gating_and_opcode_scope)"; super.build_phase(phase);
  endfunction

  task run_phase(uvm_phase phase);
    bpu_backdoor    bd;
    bpu_fetch_obs_t o;
    bpu_fetch_obs_t oF, oD, oX;
    bit [31:0] fresh_nxpc;
    bit [31:0] exp_tgt;
    int op, fl, k;
    int n_is_branch;
    bit [6:0]  opv;
    bit        exp_fib, exp_fr, exp_fv, exp_dv;
    string     s;

    super.run_phase(phase);
    bd = tb.module_env.backdoor;
    phase.raise_objection(this, "9_1");
    #100ns;

    setup_addresses();
    fresh_nxpc = 32'h0000_0B00;                  // idx 704, chua bao gio duoc ghi
    exp_tgt    = bd.read_btb_target(ADDR_TK[11:2]);
    chk(bd.read_btb_valid(ADDR_TK[11:2]) === 1'b1, "chuan bi: btb_valid[TK] phai = 1");
    chk(bd.read_btb_valid(fresh_nxpc[11:2]) === 1'b0,
        "chuan bi: btb_valid tai nxpc phai = 0 thi backstop moi lai duoc");

    //=========================================================================
    // PHA A: quet du 128 gia tri fetch_opcode
    //   Dieu kien tang fetch giu TICH CUC suot pha (nxpc2 = ADDR_TK, flush_in=0)
    //   => f_valid phai bang 1 voi MOI opcode. Day chinh la pham vi tac dung
    //      hep cua fetch_is_branch (bpu_ctrl.v khong kiem opcode).
    //=========================================================================
    phase_of("A_opcode_sweep_128");
    n_is_branch = 0;
    for (op = 0; op < 128; op++) begin
      opv = op[6:0];
      apply(.pc(NEU_PC), .nxpc(fresh_nxpc), .nxpc2(ADDR_TK), .opcode(opv),
            .btf(32'h40), .flush_in(2'd0));
      apply(.pc(NEU_PC), .nxpc(fresh_nxpc), .nxpc2(ADDR_TK), .opcode(opv),
            .btf(32'h40), .flush_in(2'd0));
      o = snap();
      exp_fib = (opv === 7'b1100011);
      if (o.fib) n_is_branch++;
      chk(o.fib === exp_fib,
          $sformatf("opcode 0x%02h: fetch_is_branch=%0d, ky vong %0d", opv, o.fib, exp_fib));
      chk(o.dv === exp_fib,
          $sformatf("opcode 0x%02h: d_valid=%0d, ky vong %0d (BTB truot tai nxpc, fetch_ready=1)",
                    opv, o.dv, exp_fib));
      chk(o.fv === 1'b1,
          $sformatf("opcode 0x%02h: f_valid=%0d, ky vong 1 -- tang fetch KHONG kiem opcode (bpu_ctrl.v)",
                    opv, o.fv));
    end
    chk(n_is_branch === 1,
        $sformatf("A: fetch_is_branch=1 tai %0d/128 opcode, ky vong dung 1 (chi 7'b1100011)", n_is_branch));
    `uvm_info(test_label, $sformatf(
      "A: quet 128 opcode -- fetch_is_branch=1 dung %0d lan (tai 7'b1100011); f_valid=1 o CA 128 gia tri",
      n_is_branch), UVM_NONE)

    //=========================================================================
    // PHA B: quet du BON gia tri flush_in x hai opcode
    //   SVA cua bpu_if da duoc noi de gia tri 3 lai duoc:
    //   RTL xu ly 3 y het 2 (bpu_ctrl.v), nen 3 la ngo vao hop le phai phu.
    //=========================================================================
    phase_of("B_flush_sweep_4");
    s = "\n=== 9.1 PHAM VI CUA fetch_ready (bpu_ctrl.v) ===\n";
    s = {s, "   flush_in  opcode  fetch_ready  f_valid  d_valid  bpu_nxpc2_valid\n"};
    s = {s, "   ---------------------------------------------------------------\n"};
    for (fl = 0; fl < 4; fl++) begin
      for (k = 0; k < 2; k++) begin
        opv     = (k == 0) ? OPC_BR : OPC_NOP;
        exp_fr  = (fl == 0) || (fl == 1);
        exp_fv  = exp_fr;                                  // BTB trung + du doan re
        exp_dv  = exp_fr && (opv === OPC_BR);
        apply(.pc(NEU_PC), .nxpc(fresh_nxpc), .nxpc2(ADDR_TK), .opcode(opv),
              .btf(32'h40), .flush_in(fl[1:0]));
        apply(.pc(NEU_PC), .nxpc(fresh_nxpc), .nxpc2(ADDR_TK), .opcode(opv),
              .btf(32'h40), .flush_in(fl[1:0]));
        o = snap();
        s = {s, $sformatf("      %0d      %s       %0d          %0d        %0d           %0d\n",
                          fl, (k == 0) ? "BCC " : "ADDI", o.fr, o.fv, o.dv, o.outv)};
        chk(o.fr === exp_fr,
            $sformatf("flush_in=%0d: fetch_ready=%0d, ky vong %0d", fl, o.fr, exp_fr));
        chk(o.fv === exp_fv,
            $sformatf("flush_in=%0d opcode=0x%02h: f_valid=%0d, ky vong %0d", fl, opv, o.fv, exp_fv));
        chk(o.dv === exp_dv,
            $sformatf("flush_in=%0d opcode=0x%02h: d_valid=%0d, ky vong %0d", fl, opv, o.dv, exp_dv));
        if (fl >= 2) begin
          chk(o.fv === 1'b0 && o.dv === 1'b0,
              $sformatf("flush_in=%0d: ky vong f_valid=d_valid=0, do duoc %0d/%0d", fl, o.fv, o.dv));
          chk(o.outv === 1'b0,
              $sformatf("flush_in=%0d: bpu_nxpc2_valid=%0d, ky vong 0", fl, o.outv));
        end
      end
    end
    s = {s, "   ---------------------------------------------------------------\n"};
    s = {s, "   flush_in = 3 duoc xu ly Y HET 2: ca hai deu cho fetch_ready = 0.\n"};
    s = {s, "======================================================="};
    `uvm_info(test_label, s, UVM_NONE)

    //=========================================================================
    // PHA C: pham vi cua opcode -- DesignNotes R1 nhin tu phia CHUYEN HUONG
    //   Ba chu ky lien tiep, mo phong dung mot lenh KHONG PHAI nhanh di qua ba
    //   tang trong khi tang fetch van doan re cho no:
    //     F   : nxpc2 = ADDR_TK  (BTB trung + du doan re), opcode tai decode = ADDI
    //     F+1 : nxpc  = ADDR_TK
    //     F+2 : pc    = ADDR_TK, is_branch = 0  (execute biet no khong phai nhanh)
    //=========================================================================
    phase_of("C_opcode_scope_to_execute");
    apply_idle(4);

    // --- chu ky F ---
    apply(.pc(NEU_PC), .nxpc(NEU_NXPC), .nxpc2(ADDR_TK), .opcode(OPC_NOP),
          .btf(32'h40), .flush_in(2'd0));
    oF = snap();
    chk(oF.fib === 1'b0, $sformatf("C(F): fetch_is_branch=%0d, ky vong 0 (opcode = ADDI)", oF.fib));
    chk(oF.dv  === 1'b0, $sformatf("C(F): d_valid=%0d, ky vong 0 (opcode khac BCC)", oF.dv));
    chk(oF.fv  === 1'b1,
        $sformatf("C(F): f_valid=%0d, ky vong 1 -- tang fetch KHONG kiem opcode", oF.fv));
    chk(oF.outv === 1'b1, $sformatf("C(F): bpu_nxpc2_valid=%0d, ky vong 1", oF.outv));
    chk(oF.outp === exp_tgt,
        $sformatf("C(F): bpu_nxpc2=0x%08h, ky vong 0x%08h (btb_target_nxpc2)", oF.outp, exp_tgt));

    // --- chu ky F+1 ---
    apply(.pc(NEU_PC), .nxpc(ADDR_TK), .nxpc2(NEU_NXPC2), .opcode(OPC_NOP),
          .btf(32'h40), .flush_in(2'd0));
    oD = snap();
    chk(oD.dv === 1'b0, $sformatf("C(F+1): d_valid=%0d, ky vong 0", oD.dv));

    // --- chu ky F+2 : lenh toi execute voi is_branch = 0 ---
    apply(.pc(ADDR_TK), .nxpc(NEU_NXPC), .nxpc2(NEU_NXPC2), .opcode(OPC_NOP),
          .btf(32'h0), .flush_in(2'd0), .halt(1'b0), .is_branch(1'b0));
    oX = snap();
    `uvm_info(test_label, $sformatf({
      "\n=== 9.1 PHA C -- DesignNotes R1 nhin tu phia CHUYEN HUONG ===\n",
      "  Tang fetch da doan re cho mot lenh KHONG PHAI nhanh:\n",
      "    F   : fetch_is_branch=%0d  d_valid=%0d  f_valid=%0d  -> bpu_nxpc2_valid=%0d, bpu_nxpc2=0x%08h\n",
      "    F+2 : is_branch=0 tai execute -> predicted_taken=%0d  bpu_flush=%0d  corr_valid=%0d\n",
      "  Ket luan: bpu_ctrl.v KHONG kiem opcode, nen tang fetch chuyen huong\n",
      "  duoc cho moi lenh co BTB trung tai nxpc2. Tang execute KHONG the sua sai\n",
      "  do, vi ca bpu_flush lan corr_valid deu bi is_branch=0 chan lai -> khong flush,\n",
      "  khong correction. Chuyen huong sai o day chi co the do tang fetch tu\n",
      "  tranh bang mot truong tag, thu ma BTB hien khong co.\n",
      "======================================================="},
      oF.fib, oF.dv, oF.fv, oF.outv, oF.outp,
      bd.read_predicted_taken(), oX.fl, oX.cv), UVM_NONE)
    chk(bd.read_predicted_taken() === 1'b1,
        $sformatf("C(F+2): predicted_taken=%0d, ky vong 1 -- quyet dinh cua tang fetch phai xuong toi execute",
                  bd.read_predicted_taken()));
    chk(oX.fl === 2'd0,
        $sformatf("C(F+2): bpu_flush=%0d, ky vong 0 (is_branch=0 chan bpu_ctrl.v)", oX.fl));
    chk(oX.cv === 1'b0,
        $sformatf("C(F+2): corr_valid=%0d, ky vong 0 (is_branch=0 chan bpu_ctrl.v)", oX.cv));
    chk(oX.outv === 1'b0,
        $sformatf("C(F+2): bpu_nxpc2_valid=%0d, ky vong 0", oX.outv));

    bus_free();
    phase.drop_objection(this, "9_1");
  endtask
endclass : precompute_gating_and_opcode_scope_test
