//------------------------------------------------------------------------------
// FILE: tests/hyb_pht_ghr_tests.sv
//
//   4.1 local_bht_shift_12b        [B]
//   4.2 local_pht_counter_and_init [A] gop local_pht_counter + miss_to_hit
//                                       + phan init PHT cua btb_revisit
//   4.3 pshare_index_two_stage     [B] them pha doc lap pc / nxpc2
//   4.4 local_pht_rw_all_4096      [B] quet 12 bit thay vi 6 bit
//   5.1 gshare_index_and_skew      [B] them so hai chi muc + do lech N2
//   5.2 global_pht_counter_and_init[A] gop global_pht_counter + global_pht_init
//   7.1 ghr_shift_gate_shared      [B] gop ba test ghr_*, them hai bien
//
// Ke thua hyb_base_test (tests/hyb_btb_tests.sv) -> phai `include SAU tep do.
//------------------------------------------------------------------------------


//==============================================================================
// 4.1 local_bht_shift_12b
//
// Sheet -- Flow: phat mot mau tai pc=0x100 va mot mau khac tai pc=0x200 xen ke;
//   doc bang lich su bang backdoor sau moi buoc.
// Sheet -- Pass: bang lich su dich dung theo mau; bit cu nhat bi day ra sau 12
//   lan dich (KHONG phai 6); lich su tai PC con lai khong thay doi.
// RTL Ref: bpu_predictor.v ; bpu_reg.v
//==============================================================================
class local_bht_shift_12b_test extends hyb_base_test;
  `uvm_component_utils(local_bht_shift_12b_test)
  function new(string name, uvm_component parent); super.new(name, parent); endfunction

  function void build_phase(uvm_phase phase);
    test_label = "TEST_4_1 (local_bht_shift_12b)";
    select_clock();
    super.build_phase(phase);
  endfunction

  task run_phase(uvm_phase phase);
    bpu_backdoor bd;
    bit pat_a[8]  = '{1'b1,1'b1,1'b1,1'b0,1'b1,1'b1,1'b0,1'b1};
    bit pat_b[6]  = '{1'b0,1'b1,1'b0,1'b0,1'b1,1'b0};
    int k;
    super.run_phase(phase);
    bd = tb.module_env.backdoor;
    phase.raise_objection(this, "4_1");
    #100ns;

    //---- PHA A: dich dung theo mau, doc lap theo tung PC -------------------
    //   0x100 (idx 64) : 1,1,1,0,1,1,0,1  -> 0000_1110_1101 = 12'h0ED
    //   0x200 (idx 128): 0,1,0,0,1,0      -> 0000_0001_0010 = 12'h012
    //   Hai mau phat XEN KE de chung minh hai lich su doc lap.
    phase_of("A_shift_and_independence");
    for (k = 0; k < 8; k++) begin
      drive_branch(32'h0000_0100, pat_a[k]);
      if (k < 6) drive_branch(32'h0000_0200, pat_b[k]);
    end
    chk(bd.read_local_bht(64)  === 12'h0ED,
        $sformatf("local_bht[64]=0x%03h, ky vong 0x0ED (8 lan dich, 12 bit khong mat bit)",
                  bd.read_local_bht(64)));
    chk(bd.read_local_bht(128) === 12'h012,
        $sformatf("local_bht[128]=0x%03h, ky vong 0x012 (doc lap theo PC)",
                  bd.read_local_bht(128)));

    //---- PHA B: bit cu nhat bi day ra sau DUNG 12 lan dich -----------------
    //   Ep lich su ve 0, roi phat 1 nhanh TAKEN va 11 nhanh NOT-TAKEN.
    //   Sau 12 lan dich: bit 1 nam o bit[11] -> 12'h800 (VAN con trong bang).
    //   Sau lan dich thu 13   : bit 1 bi day ra -> 12'h000.
    //   Neu bang chi rong 6 bit thi ngay sau 6 lan dich da la 0 -> test fail.
    phase_of("B_oldest_bit_drops_at_12");
    bd.deposit_local_bht(300, 12'h000);   // pc=0x4B0 -> idx 300
    drive_branch(32'h0000_04B0, 1'b1);            // dich 1: 0x001
    chk(bd.read_local_bht(300) === 12'h001,
        $sformatf("sau 1 dich: 0x%03h, ky vong 0x001", bd.read_local_bht(300)));
    for (k = 0; k < 5; k++) drive_branch(32'h0000_04B0, 1'b0);     // dich 2..6
    chk(bd.read_local_bht(300) === 12'h020,
        $sformatf("sau 6 dich: 0x%03h, ky vong 0x020 -- neu 0x000 thi bang chi rong 6 bit",
                  bd.read_local_bht(300)));
    for (k = 0; k < 5; k++) drive_branch(32'h0000_04B0, 1'b0);     // dich 7..11
    chk(bd.read_local_bht(300) === 12'h400,
        $sformatf("sau 11 dich: 0x%03h, ky vong 0x400", bd.read_local_bht(300)));
    drive_branch(32'h0000_04B0, 1'b0);                             // dich 12
    chk(bd.read_local_bht(300) === 12'h800,
        $sformatf("sau 12 dich: 0x%03h, ky vong 0x800 (bit cu nhat VAN o bit[11])",
                  bd.read_local_bht(300)));
    drive_branch(32'h0000_04B0, 1'b0);                             // dich 13
    chk(bd.read_local_bht(300) === 12'h000,
        $sformatf("sau 13 dich: 0x%03h, ky vong 0x000 (bit cu nhat DA bi day ra)",
                  bd.read_local_bht(300)));

    phase.drop_objection(this, "4_1");
  endtask
endclass : local_bht_shift_12b_test


//==============================================================================
// 4.2 local_pht_counter_and_init
//
// Sheet -- Flow: phat nhanh dau tien tai mot pc chua tung gap (BTB miss), sau do
//   lap lai cung pc de tao BTB hit; tiep tuc bang chuoi taken/not-taken phu moi
//   chuyen trang thai, ke ca co vuot qua ST va SNT.
// Sheet -- Pass: lan gap dau: PHT = WT bat ke branch_taken. Cac lan sau: bo dem
//   theo dung chuoi SNT-WNT-WT-ST va giu nguyen khi da bao hoa o hai dau.
// RTL Ref: bpu_predictor.v
//==============================================================================
class local_pht_counter_and_init_test extends hyb_base_test;
  `uvm_component_utils(local_pht_counter_and_init_test)
  function new(string name, uvm_component parent); super.new(name, parent); endfunction

  function void build_phase(uvm_phase phase);
    test_label = "TEST_4_2 (local_pht_counter_and_init)";
    select_clock();
    super.build_phase(phase);
  endfunction

  // mot nhanh roi kiem local_pht[idx]
  task automatic step(bit [31:0] pc, bit tk, int idx, bit [1:0] exp, string lbl);
    bpu_backdoor bd = tb.module_env.backdoor;
    drive_branch(pc, tk);
    chk(bd.read_local_pht(idx) === exp,
        $sformatf("%s: local_pht[%0d]=2'b%02b, ky vong 2'b%02b",
                  lbl, idx, bd.read_local_pht(idx), exp));
  endtask

  task run_phase(uvm_phase phase);
    bpu_backdoor bd;
    super.run_phase(phase);
    bd = tb.module_env.backdoor;
    phase.raise_objection(this, "4_2");
    #100ns;

    //---- PHA A: lan gap dau (BTB miss) -> WT du branch_taken = 0 -----------
    // pc=0x100 chua tung gap. Nhanh NOT-taken de chung minh init khong phu
    // thuoc branch_taken. Vi not-taken nen local_bht[64] van = 0 -> ca hai lan
    // deu dung chi muc 0.
    phase_of("A_init_WT_on_miss");
    drive_branch(32'h0000_0100, 1'b0);
    chk(bd.read_local_pht(0) === `WT,
        $sformatf("lan gap dau: local_pht[0]=2'b%02b, ky vong WT 2'b10 (init bat ke taken)",
                  bd.read_local_pht(0)));

    //---- PHA B: lan gap thu hai (BTB hit) -> cap nhat bo dem ---------------
    phase_of("B_update_on_hit");
    drive_branch(32'h0000_0100, 1'b0);
    chk(bd.read_local_pht(0) === `WNT,
        $sformatf("lan gap hai: local_pht[0]=2'b%02b, ky vong WNT (WT--)", bd.read_local_pht(0)));

    //---- PHA C: init WT tai mot chi muc KHAC (tu btb_revisit cu) -----------
    // pc=0x700 (idx 448) chua gap, nhanh TAKEN -> local_pht[0] da bi dung, nen
    // ghim lich su ve mot chi muc rieng de tach biet.
    phase_of("C_init_WT_other_index");
    bd.deposit_local_bht(448, 12'd100);
    bd.deposit_local_pht(100, `SNT);
    drive_branch(32'h0000_0700, 1'b1);  // BTB miss tai idx 448 -> init WT
    chk(bd.read_local_pht(100) === `WT,
        $sformatf("init chi muc 100: 2'b%02b, ky vong WT", bd.read_local_pht(100)));

    //---- PHA D: phu MOI chuyen trang thai + hai bien bao hoa ---------------
    // Ghim local_bht[64]=0 (chan dich) va ep BTB hit -> moi nhanh cap nhat
    // dung local_pht[0] theo bo dem bao hoa.
    phase_of("D_all_transitions_and_saturation");
    // local_bht[64] phai GIU 0 suot 8 nhanh: moi lan cap nhat RTL ghi lich su
    // da dich vao local_bht[64] (bpu_reg.v Local BHT write), nen neu chi deposit
    // mot lan thi chi muc se roi khoi 0 ngay tu nhanh thu hai va pha D khong con
    // quan sat duoc mot bo dem duy nhat. Day la truong hop (b) -- BUOC phai
    // force, va vi la phan tu mang khong goi ten nen pha D chay duoc tren
    // Xcelium chu KHONG chay duoc tren Questa (vsim-16133).
    bd.force_local_bht(64, 12'd0);
    // BTB thi deposit du: RTL chi bao gio ghi btb_valid[64] <= 1'b1, khong bao
    // gio xoa, nen "hit" van con nguyen ma khong can chan lenh ghi.
    bd.deposit_btb(64, 1'b1, 32'h0000_0140);
    bd.deposit_local_pht(0, `SNT);
    step(32'h0000_0100, 1'b1, 0, `WNT, "len 1: SNT->WNT");
    step(32'h0000_0100, 1'b1, 0, `WT,  "len 2: WNT->WT");
    step(32'h0000_0100, 1'b1, 0, `ST,  "len 3: WT->ST");
    step(32'h0000_0100, 1'b1, 0, `ST,  "bao hoa tren: ST->ST (khong tran)");
    step(32'h0000_0100, 1'b0, 0, `WT,  "xuong 1: ST->WT");
    step(32'h0000_0100, 1'b0, 0, `WNT, "xuong 2: WT->WNT");
    step(32'h0000_0100, 1'b0, 0, `SNT, "xuong 3: WNT->SNT");
    step(32'h0000_0100, 1'b0, 0, `SNT, "bao hoa duoi: SNT->SNT (khong muon)");

    bd.release_local_bht(64);
    phase.drop_objection(this, "4_2");
  endtask
endclass : local_pht_counter_and_init_test


//==============================================================================
// 4.3 pshare_index_two_stage
//
// Sheet -- Flow: phat chuoi tai pc=0x100 roi tao cung gia tri lich su tai
//   pc=0x200; quan sat chi muc o chu ky co ghi dong thoi; sau do dat pc va nxpc2
//   tro hai chi muc co lich su khac nhau trong cung mot chu ky.
// Sheet -- Pass: chi muc PHT bang local_bht[pc_index] hien tai va lan ghi dung
//   lich su CU; hai PC co cung lich su tro vao cung entry; local_pht_data_pc va
//   local_pht_data_nxpc2 dung hai chi muc khac nhau va co the khac gia tri trong
//   cung chu ky.
// RTL Ref: bpu_reg.v
//==============================================================================
class pshare_index_two_stage_test extends hyb_base_test;
  `uvm_component_utils(pshare_index_two_stage_test)
  function new(string name, uvm_component parent); super.new(name, parent); endfunction

  function void build_phase(uvm_phase phase);
    test_label = "TEST_4_3 (pshare_index_two_stage)";
    select_clock();
    super.build_phase(phase);
  endfunction

  function void end_of_elaboration_phase(uvm_phase phase);
    super.end_of_elaboration_phase(phase);
    scoreboard_not_applicable(
      "phai ghim local_bht/local_pht de co hai lich su khac nhau tai pc va nxpc2 trong cung chu ky");
  endfunction

  local function bit [1:0] rd2(string sig);
    uvm_hdl_data_t v;
    if (!uvm_hdl_read({"bpu_hw_top.dut.", sig}, v))
      `uvm_error(test_label, $sformatf("khong doc duoc bpu_hw_top.dut.%s", sig))
    return v[1:0];
  endfunction

  local function bit [11:0] rd_idx(string sig);
    uvm_hdl_data_t v;
    if (!uvm_hdl_read({"bpu_hw_top.dut.u_bpu_reg.", sig}, v))
      `uvm_error(test_label, $sformatf("khong doc duoc u_bpu_reg.%s", sig))
    return v[11:0];
  endfunction

  task run_phase(uvm_phase phase);
    bpu_backdoor bd;
    super.run_phase(phase);
    bd = tb.module_env.backdoor;
    phase.raise_objection(this, "4_3");
    #100ns;

    //---- PHA A: lan ghi dung lich su CU ------------------------------------
    // bht[64]=5, BTB miss -> nhanh taken ghi WT vao pht[5] (chi muc CU),
    // sau do bht dich 5 -> 11; pht[11] phai con nguyen.
    phase_of("A_write_uses_old_history");
    bd.deposit_btb(64, 1'b0, 32'h0);
    bd.deposit_local_bht(64, 12'd5);
    drive_branch(32'h0000_0100, 1'b1);
    chk(bd.read_local_pht(5)  === `WT,
        $sformatf("pht[5]=2'b%02b, ky vong WT (ghi tai chi muc CU 5)", bd.read_local_pht(5)));
    chk(bd.read_local_pht(11) === `SNT,
        $sformatf("pht[11]=2'b%02b, ky vong SNT (chi muc MOI khong duoc ghi)",
                  bd.read_local_pht(11)));
    chk(bd.read_local_bht(64) === 12'h00B,
        $sformatf("bht[64]=0x%03h, ky vong 0x00B (5 dich trai + 1)", bd.read_local_bht(64)));

    //---- PHA B: hai PC cung lich su -> cung entry --------------------------
    phase_of("B_same_history_same_entry");
    // Deposit du: moi PC chi duoc lai DUNG MOT nhanh trong pha nay, va lan ghi
    // cua RTL doc lich su TRUOC canh len, tuc dung gia tri vua dat. Lich su co
    // dich sau do cung khong con anh huong gi.
    bd.deposit_local_bht(64,  12'd20);    // chi muc cho pc=0x100
    bd.deposit_local_bht(128, 12'd20);    // chi muc cho pc=0x200
    bd.deposit_btb(64,  1'b1, 32'h0000_0140);
    bd.deposit_btb(128, 1'b1, 32'h0000_0240);
    bd.deposit_local_pht(20, `SNT);
    drive_branch(32'h0000_0100, 1'b1);    // cap nhat qua pc thu nhat
    chk(bd.read_local_pht(20) === `WNT,
        $sformatf("pht[20]=2'b%02b, ky vong WNT (dung chung entry qua pc1)",
                  bd.read_local_pht(20)));
    drive_branch(32'h0000_0200, 1'b1);    // pc thu hai cung lich su -> cung entry
    chk(bd.read_local_pht(20) === `WT,
        $sformatf("pht[20]=2'b%02b, ky vong WT (pc2 cung lich su cap nhat cung entry)",
                  bd.read_local_pht(20)));

    //---- PHA C (MOI): duong doc phia pc va phia nxpc2 DOC LAP --------------
    // Dat pc va nxpc2 tro hai chi muc co LICH SU khac nhau va gia tri PHT khac
    // nhau trong CUNG mot chu ky.
    //   pc    = 0x100 -> bht[64]  = 0x111 -> local_pht[0x111] = ST
    //   nxpc2 = 0x200 -> bht[128] = 0x222 -> local_pht[0x222] = SNT
    phase_of("C_pc_vs_nxpc2_independent");
    // Pha C chi DOC duong to hop: force_predict_inputs giu is_branch = 0 nen
    // khong co lenh ghi nao vao bang trong cua so nay -> deposit la du.
    bd.deposit_local_bht(64,  12'h111);
    bd.deposit_local_bht(128, 12'h222);
    bd.deposit_local_pht(12'h111, `ST);
    bd.deposit_local_pht(12'h222, `SNT);
    bd.force_predict_inputs(.pc(32'h0000_0100), .nxpc(32'h0000_0FF4),
                            .fetch_opcode(7'b0010011),
                            .branch_target_fetch(32'h0),
                            .flush_in(2'b00), .halt(1'b0),
                            .nxpc2(32'h0000_0200));
    #2ns;
    chk(rd_idx("local_pht_index_pc")    === 12'h111,
        $sformatf("local_pht_index_pc=0x%03h, ky vong 0x111", rd_idx("local_pht_index_pc")));
    chk(rd_idx("local_pht_index_nxpc2") === 12'h222,
        $sformatf("local_pht_index_nxpc2=0x%03h, ky vong 0x222", rd_idx("local_pht_index_nxpc2")));
    chk(rd_idx("local_pht_index_pc") !== rd_idx("local_pht_index_nxpc2"),
        "hai chi muc BANG nhau -- duong doc pc va nxpc2 khong doc lap");
    chk(rd2("local_pht_data_pc")    === `ST,
        $sformatf("local_pht_data_pc=2'b%02b, ky vong ST", rd2("local_pht_data_pc")));
    chk(rd2("local_pht_data_nxpc2") === `SNT,
        $sformatf("local_pht_data_nxpc2=2'b%02b, ky vong SNT", rd2("local_pht_data_nxpc2")));
    chk(rd2("local_pht_data_pc") !== rd2("local_pht_data_nxpc2"),
        "hai gia tri BANG nhau -- khong chung minh duoc tinh doc lap trong cung chu ky");

    bd.release_predict_inputs();
    phase.drop_objection(this, "4_3");
  endtask
endclass : pshare_index_two_stage_test


//==============================================================================
// 4.4 local_pht_rw_all_4096
//
// Sheet -- Flow: dung backdoor ep local_bht de quet chi muc h = 0..4095 (hoac
//   quet mot tap dai dien kem bien luan), ghi roi doc lai tung entry.
// Sheet -- Pass: moi local_pht[h] ghi va doc doc lap; khong entry nao bi gop do
//   cat bit chi muc.
// RTL Ref: bpu_reg.v
//
// Chien luoc HAI PHA:
//   A. DINH DIA CHI (addressing) -- quet DAY DU 4096 chi muc bang duong ghi
//      that cua DUT: ghim bht=h, dat pht[h]=SNT, phat 1 nhanh taken, kiem
//      pht[h]==WNT. Day la phep kiem manh nhat: neu chi muc bi cat bit thi
//      entry h>=64 se khong bao gio doi.
//   B. DOC LAP LUU TRU -- ghi 4096 gia tri phan biet roi doc lai, bao dam khong
//      entry nao de len entry khac.
//==============================================================================
class local_pht_rw_all_4096_test extends hyb_base_test;
  `uvm_component_utils(local_pht_rw_all_4096_test)
  function new(string name, uvm_component parent); super.new(name, parent); endfunction

  function void build_phase(uvm_phase phase);
    test_label = "TEST_4_4 (local_pht_rw_all_4096)";
    select_clock();
    super.build_phase(phase);
  endfunction

  task run_phase(uvm_phase phase);
    bpu_backdoor bd;
    int h, n_bad;
    super.run_phase(phase);
    bd = tb.module_env.backdoor;
    phase.raise_objection(this, "4_4");
    #100ns;

    //---- PHA A: quet DU 4096 chi muc qua duong ghi that -------------------
    phase_of("A_addressing_sweep_4096");
    bd.deposit_btb(64, 1'b1, 32'h0000_0140);     // BTB hit -> di duong cap nhat
    n_bad = 0;
    for (h = 0; h < 4096; h++) begin
      // Dat lai chi muc o DAU moi vong va chi lai DUNG MOT nhanh sau do, nen
      // deposit du: lan ghi cua RTL doc local_bht[64] truoc canh len, tuc gia
      // tri vua dat. Lich su dich sau canh do se bi ghi de o vong ke tiep.
      bd.deposit_local_bht(64, h[11:0]);         // 12 bit -- truoc B1 la h[5:0]
      bd.deposit_local_pht(h, `SNT);
      drive_branch(32'h0000_0100, 1'b1);         // pht[h]: SNT -> WNT
      if (bd.read_local_pht(h) !== `WNT) begin
        n_bad++;
        if (n_bad <= 5)
          chk(1'b0, $sformatf("pht[%0d]=2'b%02b, ky vong WNT (entry khong toi duoc / bi cat bit)",
                              h, bd.read_local_pht(h)));
      end
    end
    `uvm_info(test_label, $sformatf("quet dinh dia chi 4096 entry: sai = %0d", n_bad), UVM_LOW)
    if (n_bad > 5)
      chk(1'b0, $sformatf("tong cong %0d/4096 entry khong toi duoc (chi in 5 dau)", n_bad));

    //---- PHA B: doc lap luu tru tren ca 4096 entry -------------------------
    // Ghi roi doc lai trong 0 thoi gian mo phong: khong canh len nao xen vao.
    phase_of("B_storage_independence_4096");
    for (h = 0; h < 4096; h++) bd.deposit_local_pht(h, h[1:0]);
    n_bad = 0;
    for (h = 0; h < 4096; h++)
      if (bd.read_local_pht(h) !== h[1:0]) begin
        n_bad++;
        if (n_bad <= 5)
          chk(1'b0, $sformatf("luu tru: pht[%0d]=2'b%02b, ky vong 2'b%02b",
                              h, bd.read_local_pht(h), h[1:0]));
      end
    `uvm_info(test_label, $sformatf("kiem doc lap luu tru 4096 entry: sai = %0d", n_bad), UVM_LOW)
    if (n_bad > 5)
      chk(1'b0, $sformatf("tong cong %0d/4096 entry khong doc lap (chi in 5 dau)", n_bad));

    phase.drop_objection(this, "4_4");
  endtask
endclass : local_pht_rw_all_4096_test


//==============================================================================
// 5.1 gshare_index_and_skew
//
// Sheet -- Flow: nap truoc cac entry; dat pc khac nxpc2 trong cung chu ky va so
//   hai chi muc; dich GHR bang chuoi nhanh lien tiep; ghi nhan chi muc dung cho
//   du doan va chi muc dung cho cap nhat cua CUNG mot nhanh.
// Sheet -- Pass: global_pc_index = pc_index XOR ghr va global_nxpc2_index =
//   nxpc2_index XOR ghr, cung mot ghr tai moi thoi diem; cung mot dia chi doc ra
//   entry khac nhau khi GHR thay doi; xac nhan carry-down chi mang xuong BIT du
//   doan chu khong mang chi muc, nen hai chi muc cua cung mot nhanh co the khac
//   nhau (doi chieu DesignNotes N2).
// RTL Ref: bpu_reg.v ; bpu_ctrl.v
//==============================================================================
class gshare_index_and_skew_test extends hyb_base_test;
  `uvm_component_utils(gshare_index_and_skew_test)
  bpu_pipe_helper h;
  function new(string name, uvm_component parent); super.new(name, parent); endfunction

  function void build_phase(uvm_phase phase);
    test_label = "TEST_5_1 (gshare_index_and_skew)";
    select_clock();
    super.build_phase(phase);
    h = bpu_pipe_helper::type_id::create("h");
  endfunction

  function void end_of_elaboration_phase(uvm_phase phase);
    super.end_of_elaboration_phase(phase);
    scoreboard_not_applicable(
      "phai ghim GHR va global_pht de co dinh chi muc gshare khi so hai duong doc");
  endfunction

  function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    h.connect(tb.bpu.tx_agent.sequencer, tb.module_env.backdoor);
  endfunction

  local function bit [9:0] rd_gidx(string sig);
    uvm_hdl_data_t v;
    if (!uvm_hdl_read({"bpu_hw_top.dut.u_bpu_reg.", sig}, v))
      `uvm_error(test_label, $sformatf("khong doc duoc u_bpu_reg.%s", sig))
    return v[9:0];
  endfunction

  task run_phase(uvm_phase phase);
    bpu_backdoor bd;
    bit [9:0] ghr_F, ghr_X, pred_idx, upd_idx;
    super.run_phase(phase);
    bd = tb.module_env.backdoor;
    phase.raise_objection(this, "5_1");
    #100ns;

    //---- PHA A: cung pc, GHR khac -> entry khac ----------------------------
    phase_of("A_index_is_pc_xor_ghr");
    bd.deposit_btb(64, 1'b1, 32'h0000_0140);
    // ghr o day PHAI la force: chi muc gshare la pc_index^ghr, va ca muc nay chi
    // co nghia neu ghr dung bang gia tri neu ra tai canh cap nhat. Neu de RTL
    // dich ghr thi entry khao sat se troi. Duong vo huong -> chay ca hai tool.
    bd.force_ghr(10'd0);
    bd.deposit_global_pht(64, `SNT);
    drive_branch(32'h0000_0100, 1'b1);
    chk(bd.read_global_pht(64) === `WNT,
        $sformatf("ghr=0: global_pht[64]=2'b%02b, ky vong WNT (chi muc 64^0)",
                  bd.read_global_pht(64)));
    bd.force_ghr(10'h020);
    bd.deposit_global_pht(96, `SNT);
    drive_branch(32'h0000_0100, 1'b1);            // CUNG pc, ghr khac
    chk(bd.read_global_pht(96) === `WNT,
        $sformatf("ghr=0x20: global_pht[96]=2'b%02b, ky vong WNT (chi muc 64^0x20)",
                  bd.read_global_pht(96)));

    //---- PHA B (MOI): hai chi muc pc / nxpc2 trong CUNG mot chu ky ---------
    phase_of("B_pc_vs_nxpc2_index_same_cycle");
    bd.force_ghr(10'h0A5);
    bd.force_predict_inputs(.pc(32'h0000_0100), .nxpc(32'h0000_0FF4),
                            .fetch_opcode(7'b0010011),
                            .branch_target_fetch(32'h0),
                            .flush_in(2'b00), .halt(1'b0),
                            .nxpc2(32'h0000_0300));
    #2ns;
    chk(rd_gidx("global_pc_index")    === (10'd64  ^ 10'h0A5),
        $sformatf("global_pc_index=0x%03h, ky vong 0x%03h (64 XOR ghr)",
                  rd_gidx("global_pc_index"), (10'd64 ^ 10'h0A5)));
    chk(rd_gidx("global_nxpc2_index") === (10'd192 ^ 10'h0A5),
        $sformatf("global_nxpc2_index=0x%03h, ky vong 0x%03h (192 XOR ghr)",
                  rd_gidx("global_nxpc2_index"), (10'd192 ^ 10'h0A5)));
    chk(rd_gidx("global_pc_index") !== rd_gidx("global_nxpc2_index"),
        "hai chi muc gshare BANG nhau -- khong tach duoc duong du doan va duong cap nhat");
    bd.release_predict_inputs();
    bd.release_ghr();

    //---- PHA C (MOI): DO LECH chi muc giua luc du doan F va luc cap nhat F+2
    // DesignNotes N2. Dung helper 1.1 de day nhanh qua ba tang.
    // Chuoi 5 nhanh sat nhau P0..P4 tai cac PC khac nhau, deu TAKEN:
    //   push P2 -> chu ky F cua P2, luc do P0 dang o EXECUTE  -> doc ghr(F)
    //   push P3 -> P1 o EXECUTE (GHR da dich 1 lan)
    //   push P4 -> P2 o EXECUTE (GHR da dich 2 lan)          -> doc ghr(F+2)
    // ghr doc ngay sau khi push tra ve = gia tri DANG dung trong chu ky do
    // (thanh ghi, doc o vung active truoc NBA).
    phase_of("C_predict_vs_update_index_skew");
    h.reset_pipe();
    h.push_branch(.pc(32'h0000_0800), .taken(1'b1));   // P0
    h.push_branch(.pc(32'h0000_0900), .taken(1'b1));   // P1
    h.push_branch(.pc(32'h0000_0A00), .taken(1'b1),    // P2 -- nhanh quan tam
                  .ovr_nxpc2(1'b1), .nxpc2(32'h0000_0A00));
    ghr_F = bd.read_ghr();                             // GHR trong chu ky F cua P2
    h.push_branch(.pc(32'h0000_0B00), .taken(1'b1));   // P3
    h.push_branch(.pc(32'h0000_0C00), .taken(1'b1));   // P4
    ghr_X = bd.read_ghr();                             // GHR trong chu ky F+2 cua P2
    h.drain();

    pred_idx = 10'd640 ^ ghr_F;   // 0xA00 >> 2 = 640 ; doc du doan tai nxpc2
    upd_idx  = 10'd640 ^ ghr_X;   // cung dia chi, nhung cap nhat tai F+2

    `uvm_info(test_label, $sformatf(
      "N2: ghr(F)=0x%03h -> chi muc du doan=%0d ; ghr(F+2)=0x%03h -> chi muc cap nhat=%0d",
      ghr_F, pred_idx, ghr_X, upd_idx), UVM_NONE)

    chk(ghr_X === {ghr_F[7:0], 2'b11},
        $sformatf("ghr(F+2)=0x%03h, ky vong 0x%03h (dich 2 lan, hai nhanh taken)",
                  ghr_X, {ghr_F[7:0], 2'b11}));
    chk(pred_idx !== upd_idx,
        $sformatf("chi muc du doan = chi muc cap nhat = %0d -- khong dung duoc do lech N2", pred_idx));

    phase.drop_objection(this, "5_1");
  endtask
endclass : gshare_index_and_skew_test


//==============================================================================
// 5.2 global_pht_counter_and_init
//
// Sheet -- Flow: ep GHR co dinh bang backdoor; phat nhanh dau tien tai pc chua
//   tung gap, sau do lap lai de tao BTB hit; tiep tuc bang chuoi taken/not-taken
//   phu moi chuyen trang thai.
// Sheet -- Pass: lan gap dau PHT = WT; cac lan sau bo dem theo dung
//   SNT-WNT-WT-ST va bao hoa o hai dau.
// RTL Ref: bpu_predictor.v
//==============================================================================
class global_pht_counter_and_init_test extends hyb_base_test;
  `uvm_component_utils(global_pht_counter_and_init_test)
  function new(string name, uvm_component parent); super.new(name, parent); endfunction

  function void build_phase(uvm_phase phase);
    test_label = "TEST_5_2 (global_pht_counter_and_init)";
    select_clock();
    super.build_phase(phase);
  endfunction

  task automatic step(bit tk, bit [1:0] exp, string lbl);
    bpu_backdoor bd = tb.module_env.backdoor;
    drive_branch(32'h0000_0100, tk);
    chk(bd.read_global_pht(64) === exp,
        $sformatf("%s: global_pht[64]=2'b%02b, ky vong 2'b%02b",
                  lbl, bd.read_global_pht(64), exp));
  endtask

  task run_phase(uvm_phase phase);
    bpu_backdoor bd;
    super.run_phase(phase);
    bd = tb.module_env.backdoor;
    phase.raise_objection(this, "5_2");
    #100ns;

    // ghr=0 co dinh -> chi muc = 64 xuyen suot (dong thoi chan dich GHR).
    // Truong hop (b): phai force, khong the deposit -- muc nay lai hang chuc
    // nhanh va moi nhanh deu dich GHR. Vo huong nen chay ca hai tool.
    bd.force_ghr(10'd0);

    //---- PHA A: lan gap dau (BTB miss) -> WT du branch_taken = 0 -----------
    phase_of("A_init_WT_on_miss");
    bd.deposit_btb(64, 1'b0, 32'h0);
    drive_branch(32'h0000_0100, 1'b0);
    chk(bd.read_global_pht(64) === `WT,
        $sformatf("lan gap dau: global_pht[64]=2'b%02b, ky vong WT (bat ke taken)",
                  bd.read_global_pht(64)));

    //---- PHA B: lan gap thu hai (BTB hit) -> cap nhat bo dem ---------------
    phase_of("B_update_on_hit");
    drive_branch(32'h0000_0100, 1'b0);
    chk(bd.read_global_pht(64) === `WNT,
        $sformatf("lan gap hai: global_pht[64]=2'b%02b, ky vong WNT", bd.read_global_pht(64)));

    //---- PHA C: phu MOI chuyen trang thai + hai bien bao hoa ---------------
    phase_of("C_all_transitions_and_saturation");
    bd.deposit_btb(64, 1'b1, 32'h0000_0140);
    bd.deposit_global_pht(64, `SNT);
    step(1'b1, `WNT, "len 1: SNT->WNT");
    step(1'b1, `WT,  "len 2: WNT->WT");
    step(1'b1, `ST,  "len 3: WT->ST");
    step(1'b1, `ST,  "bao hoa tren: ST->ST");
    step(1'b0, `WT,  "xuong 1: ST->WT");
    step(1'b0, `WNT, "xuong 2: WT->WNT");
    step(1'b0, `SNT, "xuong 3: WNT->SNT");
    step(1'b0, `SNT, "bao hoa duoi: SNT->SNT");

    bd.release_ghr();
    phase.drop_objection(this, "5_2");
  endtask
endclass : global_pht_counter_and_init_test


//==============================================================================
// 7.1 ghr_shift_gate_shared
//
// Sheet -- Flow: Pha A: phat mot mau phuc tap, sau do chuoi toan taken va chuoi
//   toan not-taken de cham hai bien. Pha B: chay 20 chu ky khong nhanh, roi phat
//   nhanh voi btb_valid_pc=0 va =1. Pha C: phat nhanh tai nhieu PC khac nhau va
//   quan sat GHR theo thu tu thoi gian.
// Sheet -- Pass: GHR dich trai va chen branch_taken vao bit[0]; bit[9] bi day ra
//   sau 10 lan dich; dat duoc hai gia tri bien 10'h000 va 10'h3FF. GHR giu nguyen
//   khi is_branch=0 va dich khi is_branch=1 bat ke branch_taken hay btb_valid_pc.
//   Doc tai PC bat ky deu dung chung mot GHR.
// RTL Ref: bpu_predictor.v ; bpu_reg.v
//==============================================================================
class ghr_shift_gate_shared_test extends hyb_base_test;
  `uvm_component_utils(ghr_shift_gate_shared_test)
  function new(string name, uvm_component parent); super.new(name, parent); endfunction

  function void build_phase(uvm_phase phase);
    test_label = "TEST_7_1 (ghr_shift_gate_shared)";
    select_clock();
    super.build_phase(phase);
  endfunction

  task run_phase(uvm_phase phase);
    bpu_backdoor bd;
    bit pat[14] = '{1'b1,1'b1,1'b1,1'b1,
                    1'b1,1'b0,1'b1,1'b1,1'b0,1'b0,1'b1,1'b0,1'b1,1'b0};
    bit tseq[10] = '{1'b1,1'b0,1'b1,1'b1,1'b0,1'b0,1'b1,1'b0,1'b1,1'b1};
    int k;
    super.run_phase(phase);
    bd = tb.module_env.backdoor;
    phase.raise_objection(this, "7_1");
    #100ns;

    //---- PHA A1: dich trai, chen bit[0], sau 10 lan day bit[9] ra ----------
    // 14 nhanh; 4 bit dau bi day ra, 10 bit cuoi con lai = 0x2CA
    phase_of("A1_shift_depth10");
    for (k = 0; k < 14; k++) drive_branch(32'h0000_0100, pat[k]);
    chk(bd.read_ghr() === 10'h2CA,
        $sformatf("ghr=0x%03h, ky vong 0x2CA (10 bit cuoi theo thu tu dich)", bd.read_ghr()));

    //---- PHA A2: cham hai bien 10'h3FF va 10'h000 -------------------------
    phase_of("A2_both_boundaries");
    for (k = 0; k < 10; k++) drive_branch(32'h0000_0100, 1'b1);
    chk(bd.read_ghr() === 10'h3FF,
        $sformatf("ghr=0x%03h sau 10 nhanh taken, ky vong bien tren 0x3FF", bd.read_ghr()));
    for (k = 0; k < 10; k++) drive_branch(32'h0000_0100, 1'b0);
    chk(bd.read_ghr() === 10'h000,
        $sformatf("ghr=0x%03h sau 10 nhanh not-taken, ky vong bien duoi 0x000", bd.read_ghr()));

    //---- PHA B1: giu nguyen khi is_branch=0 -------------------------------
    phase_of("B1_hold_on_non_branch");
    drive_branch(32'h0000_0100, 1'b1);            // ghr = 0x001
    chk(bd.read_ghr() === 10'h001,
        $sformatf("ghr=0x%03h, ky vong 0x001 truoc khi nghi", bd.read_ghr()));
    idle_cycles(20);
    chk(bd.read_ghr() === 10'h001,
        $sformatf("ghr=0x%03h sau 20 chu ky khong nhanh, ky vong GIU 0x001", bd.read_ghr()));

    //---- PHA B2: dich khong phu thuoc btb_valid_pc VA branch_taken --------
    // 0x300 (idx 192) chua tung gap -> btb_valid_pc = 0
    phase_of("B2_shift_independent_of_btb_and_taken");
    chk(bd.read_btb_valid(192) === 1'b0, "chuan bi: btb_valid[192] phai = 0");
    drive_branch(32'h0000_0300, 1'b0);            // BTB miss + not-taken
    chk(bd.read_ghr() === 10'h002,
        $sformatf("ghr=0x%03h, ky vong 0x002 (van dich du BTB miss va not-taken)", bd.read_ghr()));
    chk(bd.read_btb_valid(192) === 1'b1, "sau nhanh: btb_valid[192] phai = 1");
    drive_branch(32'h0000_0300, 1'b0);            // BTB hit + not-taken
    chk(bd.read_ghr() === 10'h004,
        $sformatf("ghr=0x%03h, ky vong 0x004 (dich khi BTB hit)", bd.read_ghr()));
    drive_branch(32'h0000_0300, 1'b1);            // BTB hit + taken
    chk(bd.read_ghr() === 10'h009,
        $sformatf("ghr=0x%03h, ky vong 0x009", bd.read_ghr()));

    //---- PHA C: GHR dung chung cho moi PC ---------------------------------
    // 10 nhanh tai 10 PC KHAC NHAU; GHR cuoi chi phu thuoc THU TU THOI GIAN.
    phase_of("C_shared_across_pcs");
    for (k = 0; k < 10; k++) drive_branch(32'h0000_0100, 1'b0);   // dua ve 0x000
    chk(bd.read_ghr() === 10'h000, "chuan bi pha C: ghr phai ve 0x000");
    for (k = 0; k < 10; k++)
      drive_branch((k + 1) << 8, tseq[k]);        // 0x100, 0x200, ... 0xA00
    chk(bd.read_ghr() === 10'h2CB,
        $sformatf("ghr=0x%03h, ky vong 0x2CB (thu tu thoi gian, doc lap PC)", bd.read_ghr()));

    phase.drop_objection(this, "7_1");
  endtask
endclass : ghr_shift_gate_shared_test
