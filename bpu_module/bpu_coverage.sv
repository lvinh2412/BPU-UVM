//------------------------------------------------------------------------------
//
// CLASS: bpu_coverage
//
// Vai tro: coverage chuc nang cho BPU -- 30 coverpoint va 28 cross trong mot
//   covergroup, lay mau mot lan moi chu ky tu expected_item
//
//------------------------------------------------------------------------------

class bpu_coverage extends uvm_subscriber #(bpu_expected_item);

   `uvm_component_utils(bpu_coverage)

   bpu_reference ref_handle;

   // Chep thang tu expected_item
   bit [31:0] s_pc;
   bit [31:0] s_nxpc;
   bit [6:0]  s_fetch_opcode;
   bit [1:0]  s_flush_in;
   bit        s_halt;
   bit        s_is_branch;
   bit        s_branch_taken;
   bit [31:0] s_branch_offset;
   bit        s_fetch_is_branch;
   bit        s_predict_taken_nxpc2;
   bit        s_btb_valid_pc;
   bit        s_btb_valid_nxpc;
   bit        s_btb_valid_nxpc2;
   bit        s_corr_valid;
   bit        s_bpu_nxpc2_valid;
   bit [1:0]  s_bpu_flush;

   // Tinh lai trong write()
   bit [9:0]  s_pc_region;        // pc[31:22]
   bit        s_choice_decision;  // choice[nxpc2][1]: 1=dung global, 0=dung local
   bit        s_predictor_agree;  // hai bit du doan tho tai nxpc2 co giong nhau?
   int        s_local_bht_ones;   // dem bit 1, de chia lich su 12 bit thanh 5 bin
   int        s_ghr_ones;         // dem bit 1, tuong tu cho GHR 10 bit
   bit [1:0]  s_outcome;          // 0=dung_NT 1=dung_T 2=sai_T_NT 3=sai_NT_T
   bit        s_fetch_ready;
   bit        s_f_valid;          // dieu kien tang fetch
   bit        s_d_valid;          // dieu kien tang du phong
   bit [1:0]  s_redirect_tier;    // tang thang MUX: 0=khong 1=fetch 2=du phong 3=hieu chinh
   bit [1:0]  s_corr_kind;        // 0=khong 1=khong_re(pc+4) 2=re_trung 3=re_truot

   // Thanh ghi carry-down nhu execute nhin thay, doc tu reference
   bit        s_predicted_taken;  // front-end co bi chuyen huong cho nhanh nay?
   bit        s_pred_was_hit;     // luc fetch co thong tin BTB khong?
   bit        s_carry_local;      // local da du doan gi luc fetch
   bit        s_carry_global;     // global da du doan gi luc fetch
   bit        s_carry_agree;

   // Noi dung cac bang tai PC dang lay mau, doc tu reference
   bit [1:0]  s_local_pht;
   bit [1:0]  s_global_pht;
   bit [1:0]  s_choice;
   bit [11:0] s_local_bht;
   bit [9:0]  s_ghr;
   bit [31:0] s_btb_target;

   //==========================================================================
   // COVERGROUP: cg_bpu
   //==========================================================================
   covergroup cg_bpu;
      option.per_instance = 1;
      option.name         = "cg_bpu";

      //-----------------------------------------------------------------------
      // Ngo vao
      //-----------------------------------------------------------------------
      cp_is_branch:        coverpoint s_is_branch {
         bins no_branch  = {1'b0};
         bins is_branch  = {1'b1};
      }

      cp_branch_taken:     coverpoint s_branch_taken iff (s_is_branch) {
         bins not_taken  = {1'b0};
         bins taken      = {1'b1};
      }

      cp_fetch_is_branch:  coverpoint s_fetch_is_branch {
         bins not_branch = {1'b0};
         bins is_branch  = {1'b1};
      }

      // fetch_ready chi nhan 0 va 1, nen 2 lan 3 deu nghia la "chua san sang". Vi
      // vay 3 la ngo vao HOP LE phai phu, khong phai illegal bin.
      cp_flush_in:         coverpoint s_flush_in {
         bins ready_0    = {2'd0};
         bins ready_1    = {2'd1};
         bins not_ready_2 = {2'd2};
         bins not_ready_3 = {2'd3};
      }

      cp_fetch_ready:      coverpoint s_fetch_ready {
         bins not_ready  = {1'b0};
         bins ready      = {1'b1};
      }

      cp_halt:             coverpoint s_halt {
         bins running    = {1'b0};
         bins halted     = {1'b1};
      }

      cp_branch_offset_sign: coverpoint s_branch_offset iff (s_is_branch) {
         bins zero       = {32'h0};
         bins negative   = {[32'h8000_0000 : 32'hFFFF_FFFF]};
         bins positive   = {[32'h0000_0001 : 32'h7FFF_FFFF]};
      }

      cp_pc_region:        coverpoint s_pc_region {
         bins low_mem    = {[10'h000 : 10'h0FF]};
         bins mid_mem    = {[10'h100 : 10'h2FF]};
         bins high_mem   = {[10'h300 : 10'h3FF]};
      }

      //-----------------------------------------------------------------------
      // BTB
      //-----------------------------------------------------------------------
      cp_btb_valid_pc:     coverpoint s_btb_valid_pc {
         bins miss       = {1'b0};
         bins hit        = {1'b1};
      }

      cp_btb_valid_nxpc:   coverpoint s_btb_valid_nxpc {
         bins miss       = {1'b0};
         bins hit        = {1'b1};
      }

      cp_btb_target_value: coverpoint s_btb_target iff (s_btb_valid_pc) {
         bins zero       = {32'h0};
         bins low_addr   = {[32'h0000_0004 : 32'h0000_FFFC]};
         bins mid_addr   = {[32'h0001_0000 : 32'h7FFF_FFFC]};
         bins high_addr  = {[32'h8000_0000 : 32'hFFFF_FFFF]};
      }

      //-----------------------------------------------------------------------
      // Trang thai bo du doan, tai PC phia execute
      //-----------------------------------------------------------------------
      cp_local_pht_state:  coverpoint s_local_pht {
         bins SNT = {2'b00};
         bins WNT = {2'b01};
         bins WT  = {2'b10};
         bins ST  = {2'b11};
      }

      cp_global_pht_state: coverpoint s_global_pht {
         bins SNT = {2'b00};
         bins WNT = {2'b01};
         bins WT  = {2'b10};
         bins ST  = {2'b11};
      }

      cp_choice_state:     coverpoint s_choice {
         bins SNT = {2'b00};
         bins WNT = {2'b01};
         bins WT  = {2'b10};
         bins ST  = {2'b11};
      }

      cp_local_bht_history: coverpoint s_local_bht_ones {
         bins all_zero  = {0};
         bins few_ones  = {[1:4]};
         bins half_ones = {[5:7]};
         bins many_ones = {[8:11]};
         bins all_ones  = {12};
      }

      cp_ghr_value:        coverpoint s_ghr_ones {
         bins all_zero  = {0};
         bins few_ones  = {[1:3]};
         bins balanced  = {[4:6]};
         bins many_ones = {[7:9]};
         bins all_ones  = {10};
      }

      //-----------------------------------------------------------------------
      // Quyet dinh du doan. Tat ca deu o phia nxpc2 -- do la CHO DUY NHAT RTL sinh
      // ra du doan. Execute khong du doan lai, no dung nhom carry-down ben duoi.
      //-----------------------------------------------------------------------
      // Chi co y nghia khi BTB trung tai nxpc2, vi do la dieu kien chan tang fetch
      cp_predict_taken_nxpc2: coverpoint s_predict_taken_nxpc2 iff (s_btb_valid_nxpc2) {
         bins predict_NT = {1'b0};
         bins predict_T  = {1'b1};
      }

      cp_btb_valid_nxpc2:  coverpoint s_btb_valid_nxpc2 {
         bins miss       = {1'b0};
         bins hit        = {1'b1};
      }

      cp_choice_decision:    coverpoint s_choice_decision iff (s_btb_valid_nxpc2) {
         bins use_local   = {1'b0};
         bins use_global  = {1'b1};
      }

      cp_predictor_agreement: coverpoint s_predictor_agree iff (s_btb_valid_nxpc2) {
         bins disagree    = {1'b0};
         bins agree       = {1'b1};
      }

      //-----------------------------------------------------------------------
      // Duong carry-down -- cai ma execute thuc su dem ra so, tuc quyet dinh luc
      // fetch cua chinh nhanh dang duoc giai quyet.
      //-----------------------------------------------------------------------
      cp_pred_was_hit:       coverpoint s_pred_was_hit {
         bins miss_at_fetch = {1'b0};
         bins hit_at_fetch  = {1'b1};
      }

      cp_predicted_taken:    coverpoint s_predicted_taken {
         bins not_redirected = {1'b0};
         bins redirected     = {1'b1};
      }

      cp_carry_local:        coverpoint s_carry_local {
         bins local_NT = {1'b0};
         bins local_T  = {1'b1};
      }

      cp_carry_global:       coverpoint s_carry_global {
         bins global_NT = {1'b0};
         bins global_T  = {1'b1};
      }

      // disagree chinh la dieu kien cho phep cap nhat choice
      cp_carry_agreement:    coverpoint s_carry_agree {
         bins disagree = {1'b0};
         bins agree    = {1'b1};
      }

      cp_flush_value:        coverpoint s_bpu_flush {
         bins no_flush    = {2'd0};
         bins flush_1     = {2'd1};
         bins flush_2     = {2'd2};
         illegal_bins illegal_3 = {2'd3};
      }

      cp_bpu_nxpc2_valid:    coverpoint s_bpu_nxpc2_valid {
         bins invalid     = {1'b0};
         bins valid       = {1'b1};
      }

      // Tang nao thang MUX ngo ra (uu tien: hieu chinh > du phong > fetch)
      cp_redirect_tier:      coverpoint s_redirect_tier {
         bins none        = {2'd0};
         bins fetch       = {2'd1};
         bins backstop    = {2'd2};
         bins correction  = {2'd3};
      }

      // Dung dia chi hieu chinh nao trong ba kieu
      cp_corr_case:          coverpoint s_corr_kind {
         bins none        = {2'd0};
         bins not_taken   = {2'd1};   // pc + 4
         bins taken_hit   = {2'd2};   // btb_target_pc
         bins taken_miss  = {2'd3};   // pc + branch_offset
      }

      cp_outcome:            coverpoint s_outcome iff (s_is_branch && s_pred_was_hit) {
         bins correct_NT     = {2'd0};
         bins correct_T      = {2'd1};
         bins mispredict_T_NT = {2'd2};
         bins mispredict_NT_T = {2'd3};
      }

      //-----------------------------------------------------------------------
      // CAC CROSS
      //
      //-----------------------------------------------------------------------
      cx_branch_x_halt:            cross cp_is_branch,    cp_halt;
      cx_branch_x_flush_in:        cross cp_is_branch,    cp_flush_in;

      // cp_branch_taken co iff(s_is_branch) nen khong bao gio lay mau khi
      // no_branch, moi o <no_branch,*> deu khong the toi.
      cx_branch_x_taken:           cross cp_is_branch,    cp_branch_taken {
         ignore_bins u_nobranch = binsof(cp_is_branch.no_branch);
      }
      cx_fetch_x_flush_in:         cross cp_fetch_is_branch, cp_flush_in;

      // Nhanh nay da duoc huan luyen vao BTB chua?
      cx_btb_pc_x_branch:          cross cp_btb_valid_pc, cp_is_branch;
      // Tang du phong co the kich hoat khong?
      cx_btb_nxpc_x_fetch_branch:  cross cp_btb_valid_nxpc, cp_fetch_is_branch;

      // Trang thai tung bo du doan doi chieu voi ket qua that
      cx_local_pht_x_taken:        cross cp_local_pht_state,  cp_branch_taken;
      cx_global_pht_x_taken:       cross cp_global_pht_state, cp_branch_taken;
      cx_choice_x_taken:           cross cp_choice_state,     cp_branch_taken;
      cx_choice_decision_x_agree:  cross cp_choice_decision,  cp_predictor_agreement;

      // Du 8 o cua quyet dinh flush
      cx_flush_truth_table:        cross cp_pred_was_hit, cp_predicted_taken,
                                         cp_branch_taken;

      // Ca hai coverpoint deu chi la ham cua corr_valid: hieu chinh thang MUX dung
      // khi corr_valid = 1, va s_corr_kind khac none cung dung khi corr_valid = 1.
      // Chung luon di cung nhau, nen 10 o ma chung mau thuan se doi hoi corr_valid
      // vua bang 0 vua bang 1. Con lai 6 o kha thi.
      cx_tier_x_corr:              cross cp_redirect_tier,    cp_corr_case {
         ignore_bins u_corr_without_kind =
            binsof(cp_redirect_tier.correction) && binsof(cp_corr_case.none);
         ignore_bins u_kind_without_corr =
            (binsof(cp_redirect_tier.none)  || binsof(cp_redirect_tier.fetch) ||
             binsof(cp_redirect_tier.backstop)) &&
            (binsof(cp_corr_case.not_taken) || binsof(cp_corr_case.taken_hit) ||
             binsof(cp_corr_case.taken_miss));
      }
      // bpu_flush bi ep ve 0 khi !is_branch, nen no_branch chi ghep duoc voi
      // no_flush.
      cx_flush_x_branch:           cross cp_flush_value,      cp_is_branch {
         ignore_bins u_flush_nobranch =
            binsof(cp_is_branch.no_branch) &&
            (binsof(cp_flush_value.flush_1) || binsof(cp_flush_value.flush_2));
      }
      cx_flush_x_predicted_taken:  cross cp_flush_value,      cp_predicted_taken;
      cx_pc_region_x_btb:          cross cp_pc_region,        cp_btb_valid_pc;

      // Hai bo du doan doi nhau, va tung bo doi voi nguon lich su cua chinh no
      // (gshare qua GHR, hai muc qua BHT)
      cx_local_pht_x_global_pht:   cross cp_local_pht_state,  cp_global_pht_state;
      cx_ghr_x_global_pht:         cross cp_ghr_value,        cp_global_pht_state;
      cx_bht_x_local_pht:          cross cp_local_bht_history, cp_local_pht_state;

      cx_flush_in_x_fetch:         cross cp_flush_in,         cp_fetch_is_branch;
      // Cuoi cung bo nao xu ly loai nhanh nao
      cx_choice_decision_x_outcome: cross cp_choice_decision, cp_outcome;

      // Hieu chinh chi kich hoat khi du doan sai, ma du doan sai thi flush luon la
      // 1 hoac 2, nen <correction,no_flush> khong the xay ra.
      cx_tier_x_flush:             cross cp_redirect_tier,    cp_flush_value {
         ignore_bins u_corr_noflush =
            binsof(cp_redirect_tier.correction) && binsof(cp_flush_value.no_flush);
      }
      // cp_predict_taken_nxpc2 co iff(s_btb_valid_nxpc2) nen <miss,*> khong the toi.
      cx_btb_nxpc2_x_predict_nxpc2: cross cp_btb_valid_nxpc2, cp_predict_taken_nxpc2 {
         ignore_bins u_miss = binsof(cp_btb_valid_nxpc2.miss);
      }

      // fetch_ready chan f_valid va d_valid nhung KHONG chan cac duong carry-down,
      // nen phai quan sat ba tin hieu nay o dang to hop.
      cx_gating_scope:             cross cp_fetch_ready, cp_fetch_is_branch,
                                         cp_btb_valid_nxpc2;

      // Du 8 o cua phep cap nhat choice, lai boi cac bit carry-down
      cx_choice_update_table:      cross cp_carry_local, cp_carry_global,
                                         cp_branch_taken;
      cx_choice_x_carry_agree:     cross cp_choice_state,     cp_carry_agreement;

      // Bao gom truong hop trung-ma-khong-chuyen-huong: BTB co o do nhung
      // tournament van du doan KHONG RE
      cx_predicted_x_hit:          cross cp_predicted_taken,  cp_pred_was_hit;

      // halt phai DONG BANG duong carry-down chu khong duoc xoa
      cx_halt_x_predicted_taken:   cross cp_halt,             cp_predicted_taken;
      cx_pc_region_x_tier:         cross cp_pc_region,        cp_redirect_tier;

   endgroup : cg_bpu

   function new(string name, uvm_component parent);
      super.new(name, parent);
      cg_bpu = new();
   endfunction : new

   //==========================================================================
   // write -- moi chu ky mot expected_item: tinh lai cac bien dan xuat roi lay mau
   // covergroup dung mot lan
   //==========================================================================
   function void write(bpu_expected_item t);
      s_pc                 = t.pc;
      s_nxpc               = t.nxpc;
      s_fetch_opcode       = t.fetch_opcode;
      s_flush_in           = t.flush_in;
      s_halt               = t.halt;
      s_is_branch          = t.is_branch;
      s_branch_taken       = t.branch_taken;
      s_branch_offset      = t.branch_offset;
      s_predict_taken_nxpc2 = t.predict_taken_nxpc2;
      s_btb_valid_pc       = t.btb_valid_pc;
      s_btb_valid_nxpc     = t.btb_valid_nxpc;
      s_btb_valid_nxpc2    = t.btb_valid_nxpc2;
      s_corr_valid         = t.corr_valid;
      s_bpu_nxpc2_valid    = t.expected_bpu_nxpc2_valid;
      s_bpu_flush          = t.expected_bpu_flush;

      // --- Tinh lai dieu kien hai tang, giong bpu_ctrl.v ---
      s_fetch_is_branch    = (t.fetch_opcode == BPU_OPCODE_BRANCH);
      s_pc_region          = t.pc[31:22];
      s_fetch_ready        = (t.flush_in == 2'd0) || (t.flush_in == 2'd1);
      s_f_valid            = t.btb_valid_nxpc2 && t.predict_taken_nxpc2 && s_fetch_ready;
      s_d_valid            = s_fetch_is_branch && !t.btb_valid_nxpc && s_fetch_ready;

      s_redirect_tier      = t.corr_valid ? 2'd3 :
                             s_d_valid    ? 2'd2 :
                             s_f_valid    ? 2'd1 : 2'd0;

      // --- Thanh ghi carry-down, van dang giu gia tri cua chu ky nay ---
      if (ref_handle != null) begin
         s_predicted_taken = ref_handle.cd_steer;
         s_pred_was_hit    = ref_handle.cd_hit;
         s_carry_local     = ref_handle.cd_local_b;
         s_carry_global    = ref_handle.cd_global_b;
         s_carry_agree     = (s_carry_local == s_carry_global);
      end

      // --- Dung dia chi hieu chinh nao ---
      if (!t.corr_valid)          s_corr_kind = 2'd0;
      else if (!t.branch_taken)   s_corr_kind = 2'd1;   // pc + 4
      else if (s_pred_was_hit)    s_corr_kind = 2'd2;   // btb_target_pc
      else                        s_corr_kind = 2'd3;   // pc + branch_offset

      // --- Dung hay sai, cham theo quyet dinh mang xuong tu fetch ---
      if (s_predicted_taken == t.branch_taken)
         s_outcome = t.branch_taken ? 2'd1 : 2'd0;      // correct
      else
         s_outcome = s_predicted_taken ? 2'd2 : 2'd3;   // mispredict

      // --- Noi dung cac bang bong tai PC nay ---
      if (ref_handle != null) begin
         s_local_pht       = ref_handle.read_local_pht_pc(t.pc);
         s_global_pht      = ref_handle.read_global_pht_pc(t.pc);
         s_choice          = ref_handle.read_choice_pc(t.pc);
         s_local_bht       = ref_handle.read_local_bht_pc(t.pc);
         s_ghr             = ref_handle.read_ghr();
         s_btb_target      = ref_handle.read_btb_target_pc(t.pc);
         s_local_bht_ones  = $countones(s_local_bht);
         s_ghr_ones        = $countones(s_ghr);
         // Hai dong nay doc phia nxpc2, noi tournament thuc su dien ra
         s_choice_decision = ref_handle.choice[ref_handle.get_nxpc2_index(t.nxpc2)][1];
         s_predictor_agree = (ref_handle.read_local_pht_bit_nxpc2(t.nxpc2) ==
                              ref_handle.read_global_pht_bit_nxpc2(t.nxpc2));
      end

      cg_bpu.sample();
   endfunction : write

   //==========================================================================
   // report_phase -- in chi tiet tung coverpoint va tung cross ra log, de xem duoc
   // so lieu ma khong can cong cu doc coverage database
   //==========================================================================
   protected function string cp_line(string nm, real c);
      return $sformatf("  %-32s %6.2f%%\n", nm, c);
   endfunction

   function void report_phase(uvm_phase phase);
      real   cov;
      string s;
      super.report_phase(phase);
      cov = cg_bpu.get_inst_coverage();

      s = "\n========================= BPU Coverage Report =========================\n";
      s = {s, $sformatf("  cg_bpu overall                   %6.2f%%\n", cov)};
      s = {s, "  ---- COVERPOINTS (30) ------------------------------------------\n"};
      s = {s, cp_line("cp_is_branch",            cg_bpu.cp_is_branch.get_coverage())};
      s = {s, cp_line("cp_branch_taken",         cg_bpu.cp_branch_taken.get_coverage())};
      s = {s, cp_line("cp_fetch_is_branch",      cg_bpu.cp_fetch_is_branch.get_coverage())};
      s = {s, cp_line("cp_flush_in (4 bin)",     cg_bpu.cp_flush_in.get_coverage())};
      s = {s, cp_line("cp_fetch_ready [NEW]",    cg_bpu.cp_fetch_ready.get_coverage())};
      s = {s, cp_line("cp_halt",                 cg_bpu.cp_halt.get_coverage())};
      s = {s, cp_line("cp_branch_offset_sign",   cg_bpu.cp_branch_offset_sign.get_coverage())};
      s = {s, cp_line("cp_pc_region",            cg_bpu.cp_pc_region.get_coverage())};
      s = {s, cp_line("cp_btb_valid_pc",         cg_bpu.cp_btb_valid_pc.get_coverage())};
      s = {s, cp_line("cp_btb_valid_nxpc",       cg_bpu.cp_btb_valid_nxpc.get_coverage())};
      s = {s, cp_line("cp_btb_valid_nxpc2",      cg_bpu.cp_btb_valid_nxpc2.get_coverage())};
      s = {s, cp_line("cp_btb_target_value",     cg_bpu.cp_btb_target_value.get_coverage())};
      s = {s, cp_line("cp_local_pht_state",      cg_bpu.cp_local_pht_state.get_coverage())};
      s = {s, cp_line("cp_global_pht_state",     cg_bpu.cp_global_pht_state.get_coverage())};
      s = {s, cp_line("cp_choice_state",         cg_bpu.cp_choice_state.get_coverage())};
      s = {s, cp_line("cp_local_bht_history 12b",cg_bpu.cp_local_bht_history.get_coverage())};
      s = {s, cp_line("cp_ghr_value",            cg_bpu.cp_ghr_value.get_coverage())};
      s = {s, cp_line("cp_predict_taken_nxpc2",  cg_bpu.cp_predict_taken_nxpc2.get_coverage())};
      s = {s, cp_line("cp_choice_decision",      cg_bpu.cp_choice_decision.get_coverage())};
      s = {s, cp_line("cp_predictor_agreement",  cg_bpu.cp_predictor_agreement.get_coverage())};
      s = {s, cp_line("cp_pred_was_hit [NEW]",   cg_bpu.cp_pred_was_hit.get_coverage())};
      s = {s, cp_line("cp_predicted_taken [NEW]",cg_bpu.cp_predicted_taken.get_coverage())};
      s = {s, cp_line("cp_carry_local [NEW]",    cg_bpu.cp_carry_local.get_coverage())};
      s = {s, cp_line("cp_carry_global [NEW]",   cg_bpu.cp_carry_global.get_coverage())};
      s = {s, cp_line("cp_carry_agreement [NEW]",cg_bpu.cp_carry_agreement.get_coverage())};
      s = {s, cp_line("cp_flush_value",          cg_bpu.cp_flush_value.get_coverage())};
      s = {s, cp_line("cp_bpu_nxpc2_valid",      cg_bpu.cp_bpu_nxpc2_valid.get_coverage())};
      s = {s, cp_line("cp_redirect_tier [NEW]",  cg_bpu.cp_redirect_tier.get_coverage())};
      s = {s, cp_line("cp_corr_case (4 bin)",    cg_bpu.cp_corr_case.get_coverage())};
      s = {s, cp_line("cp_outcome",              cg_bpu.cp_outcome.get_coverage())};
      s = {s, "  ---- CROSSES (28) ----------------------------------------------\n"};
      s = {s, cp_line("cx_branch_x_halt",        cg_bpu.cx_branch_x_halt.get_coverage())};
      s = {s, cp_line("cx_branch_x_flush_in",    cg_bpu.cx_branch_x_flush_in.get_coverage())};
      s = {s, cp_line("cx_branch_x_taken",       cg_bpu.cx_branch_x_taken.get_coverage())};
      s = {s, cp_line("cx_fetch_x_flush_in",     cg_bpu.cx_fetch_x_flush_in.get_coverage())};
      s = {s, cp_line("cx_btb_pc_x_branch",      cg_bpu.cx_btb_pc_x_branch.get_coverage())};
      s = {s, cp_line("cx_btb_nxpc_x_fetch_branch", cg_bpu.cx_btb_nxpc_x_fetch_branch.get_coverage())};
      s = {s, cp_line("cx_local_pht_x_taken",    cg_bpu.cx_local_pht_x_taken.get_coverage())};
      s = {s, cp_line("cx_global_pht_x_taken",   cg_bpu.cx_global_pht_x_taken.get_coverage())};
      s = {s, cp_line("cx_choice_x_taken",       cg_bpu.cx_choice_x_taken.get_coverage())};
      s = {s, cp_line("cx_choice_decision_x_agree", cg_bpu.cx_choice_decision_x_agree.get_coverage())};
      s = {s, cp_line("cx_flush_truth_table [NEW]", cg_bpu.cx_flush_truth_table.get_coverage())};
      s = {s, cp_line("cx_tier_x_corr [NEW]",    cg_bpu.cx_tier_x_corr.get_coverage())};
      s = {s, cp_line("cx_flush_x_branch",       cg_bpu.cx_flush_x_branch.get_coverage())};
      s = {s, cp_line("cx_flush_x_predicted_taken [NEW]", cg_bpu.cx_flush_x_predicted_taken.get_coverage())};
      s = {s, cp_line("cx_pc_region_x_btb",      cg_bpu.cx_pc_region_x_btb.get_coverage())};
      s = {s, cp_line("cx_local_pht_x_global_pht", cg_bpu.cx_local_pht_x_global_pht.get_coverage())};
      s = {s, cp_line("cx_ghr_x_global_pht",     cg_bpu.cx_ghr_x_global_pht.get_coverage())};
      s = {s, cp_line("cx_bht_x_local_pht",      cg_bpu.cx_bht_x_local_pht.get_coverage())};
      s = {s, cp_line("cx_flush_in_x_fetch",     cg_bpu.cx_flush_in_x_fetch.get_coverage())};
      s = {s, cp_line("cx_choice_decision_x_outcome", cg_bpu.cx_choice_decision_x_outcome.get_coverage())};
      s = {s, cp_line("cx_tier_x_flush",         cg_bpu.cx_tier_x_flush.get_coverage())};
      s = {s, cp_line("cx_btb_nxpc2_x_predict_nxpc2", cg_bpu.cx_btb_nxpc2_x_predict_nxpc2.get_coverage())};
      s = {s, cp_line("cx_gating_scope [NEW]",   cg_bpu.cx_gating_scope.get_coverage())};
      s = {s, cp_line("cx_choice_update_table [NEW]", cg_bpu.cx_choice_update_table.get_coverage())};
      s = {s, cp_line("cx_choice_x_carry_agree [NEW]", cg_bpu.cx_choice_x_carry_agree.get_coverage())};
      s = {s, cp_line("cx_predicted_x_hit [NEW]", cg_bpu.cx_predicted_x_hit.get_coverage())};
      s = {s, cp_line("cx_halt_x_predicted_taken [NEW]", cg_bpu.cx_halt_x_predicted_taken.get_coverage())};
      s = {s, cp_line("cx_pc_region_x_tier [NEW]", cg_bpu.cx_pc_region_x_tier.get_coverage())};
      s = {s, "======================================================================="};

      `uvm_info(get_type_name(), s, UVM_LOW)
   endfunction : report_phase

endclass : bpu_coverage
