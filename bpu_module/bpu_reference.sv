//------------------------------------------------------------------------------
//
// CLASS: bpu_reference
//
// Vai tro: mo hinh chinh xac theo chu ky cua bpu_top
//
//------------------------------------------------------------------------------

class bpu_reference extends uvm_component;

   `uvm_component_utils(bpu_reference)

   // Carry-down cua quyet dinh o fetch
   bit cd_fetch_steer;
   bit cd_fetch_hit;
   bit cd_steer;
   bit cd_hit;

   // Cung mot thanh ghi dich cho hai bit du doan local/global tho, dung de cap
   // nhat choice.
   bit cd_fetch_local;
   bit cd_fetch_global;
   bit cd_local_b;
   bit cd_global_b;

   bit choice_local_carry;
   bit choice_global_carry;

   `include "bpu_reference_state.sv"
   `include "bpu_reference_predictor.sv"
   `include "bpu_reference_ctrl.sv"

   // item_fifo     : mot quan sat chu ky, tu monitor
   // expected_port : ngo ra ky vong, gui sang scoreboard
   uvm_tlm_analysis_fifo #(bpu_item)          item_fifo;
   uvm_analysis_port     #(bpu_expected_item) expected_port;

   virtual clock_and_reset_if rst_vif;

   //==========================================================================
   // Bo dem thong ke, in o report_phase
   //==========================================================================
   int total_cycles;
   int total_branches;
   int mispredicts;
   int btb_hits_at_branch;
   int btb_misses_at_branch;
   int choice_used_global;
   int choice_used_local;
   int local_correct_count;
   int global_correct_count;
   int flush_count [3];           // [0]=khong flush, [1]=1 bong bong, [2]=2 bong bong
   int spec_case_count [4];       // [0]=khong, [1]=tang fetch, [2]=tang du phong
   int corr_case_count [4];       // [0]=khong, [1]=co hieu chinh
   int max_consecutive_flush;     // chuoi flush lien tiep dai nhat
   int cur_consecutive_flush;     // bo dem chay cho max_consecutive_flush
   int bimodal_correct_count;     // moc so sanh cho tournament

   function new (string name = "bpu_reference", uvm_component parent = null);
      super.new(name, parent);
   endfunction : new

   function void build_phase(uvm_phase phase);
      super.build_phase(phase);

      item_fifo     = new("item_fifo",     this);
      expected_port = new("expected_port", this);

      if (!uvm_config_db#(virtual clock_and_reset_if)::get(
             this, "", "rst_vif", rst_vif))
         `uvm_warning("BPU_REF",
            "No clock_and_reset_if vif found in config_db (key: 'rst_vif'). reset_handler disabled.")
   endfunction : build_phase
   
   task run_phase(uvm_phase phase);
      super.run_phase(phase);
      `uvm_info("BPU_REF", "run_phase: launching reset_handler and main_loop", UVM_MEDIUM)
      fork
         reset_handler();
         main_loop();
      join_none
   endtask : run_phase

   task reset_handler();
      if (rst_vif == null) return;
      forever begin
         @(negedge rst_vif.rst_n);
         `uvm_info("BPU_REF",
                   "rst_n asserted - resetting shadow state",
                   UVM_MEDIUM)
         reset_state();
      end
   endtask : reset_handler

   // Mot vong lap = mot chu ky DUT. Monitor phat dung mot item moi chu ky, mang
   // ca 10 ngo vao lan 3 ngo ra, nen khong con phep ghep doi hai luong.
   task main_loop();
      bpu_item it;
      forever begin
         item_fifo.get(it);
         compute_expected(it);
         apply_update(it);
      end
   endtask : main_loop

   // Day thanh ghi dich carry-down di mot chu ky. Gan tang duoi truoc tang tren,
   // nen mot gia tri phai qua hai lan goi moi toi duoc execute.
   function void tick_carry_down(bit f_valid,
                                 bit btb_valid_nxpc2_val,
                                 bit d_valid,
                                 bit halt,
                                 bit local_pht_bit_nxpc2,
                                 bit global_pht_bit_nxpc2);
      if (!halt) begin
         cd_steer       = cd_fetch_steer | d_valid;   // gop tang du phong, giong RTL
         cd_hit         = cd_fetch_hit;
         cd_fetch_steer = f_valid;
         cd_fetch_hit   = btb_valid_nxpc2_val;

         cd_local_b      = cd_fetch_local;
         cd_global_b     = cd_fetch_global;
         cd_fetch_local  = local_pht_bit_nxpc2;
         cd_fetch_global = global_pht_bit_nxpc2;
      end
   endfunction : tick_carry_down

   function void compute_expected(bpu_item it);
      bpu_expected_item exp;
      // Tang fetch
      bit        f_valid;
      bit [31:0] f_nxpc2;
      // Tang du phong o decode
      bit        d_valid;
      bit [31:0] d_nxpc2;
      // Gia tri toi execute qua duong carry-down
      bit        btb_valid_nxpc2_val;
      bit        predicted_taken;
      bit        pred_was_hit;
      // Hai bit du doan tho tai nxpc2, vao duong carry-down trong chu ky nay
      bit        local_pht_bit_nxpc2;
      bit        global_pht_bit_nxpc2;
      // Ngo ra
      bit [1:0]  flush_val;
      bit        corr_valid;
      bit [31:0] corr_nxpc2;
      bit        out_valid;
      bit [31:0] out_nxpc2;
      // Ma hoa truong hop, dung cho thong ke
      bit [1:0]  spec_case;
      bit [1:0]  corr_case;

      exp = bpu_expected_item::type_id::create("exp");

      exp.pc                  = it.pc;
      exp.nxpc                = it.nxpc;
      exp.fetch_opcode        = it.fetch_opcode;
      exp.branch_target_fetch = it.branch_target_fetch;
      exp.flush_in            = it.flush_in;
      exp.halt                = it.halt;
      exp.is_branch           = it.is_branch;
      exp.branch_taken        = it.branch_taken;
      exp.branch_offset       = it.branch_offset;

      // === BUOC 1: doc trang thai cua CHU KY NAY (trang thai cu, truoc tick va ghi) ===
      compute_fetch_tier(it.nxpc2, it.flush_in, f_valid, f_nxpc2);
      compute_backstop(it.nxpc, it.fetch_opcode, it.flush_in, it.branch_target_fetch,
                       d_valid, d_nxpc2);
      btb_valid_nxpc2_val = read_btb_valid_nxpc2(it.nxpc2);
      local_pht_bit_nxpc2  = read_local_pht_bit_nxpc2(it.nxpc2);
      global_pht_bit_nxpc2 = read_global_pht_bit_nxpc2(it.nxpc2);

      // === BUOC 2: cai duong carry-down dua toi execute ngay bay gio ===
      predicted_taken = cd_steer;
      pred_was_hit    = cd_hit;
      // Luu lai cho apply_update(), no chay sau khi BUOC 7 da tick
      choice_local_carry  = cd_local_b;
      choice_global_carry = cd_global_b;

      // === BUOC 3: tinh ngo ra ===
      flush_val = compute_flush(it.is_branch, pred_was_hit, predicted_taken, it.branch_taken);
      compute_correction(it.pc, it.branch_taken, it.branch_offset, pred_was_hit,
                         predicted_taken, it.is_branch, corr_valid, corr_nxpc2);
      compute_output_mux(corr_valid, corr_nxpc2, d_valid, d_nxpc2, f_valid, f_nxpc2,
                         out_valid, out_nxpc2);

      spec_case = f_valid ? 2'd1 : (d_valid ? 2'd2 : 2'd0);
      corr_case = corr_valid ? 2'd1 : 2'd0;

      // === BUOC 4: dien vao expected item ===
      exp.expected_bpu_nxpc2       = out_nxpc2;
      exp.expected_bpu_nxpc2_valid = out_valid;
      exp.expected_bpu_flush       = flush_val;
      exp.spec_valid               = f_valid || d_valid;
      exp.corr_valid               = corr_valid;
      exp.spec_case                = spec_case;
      exp.corr_case                = corr_case;
      // Scoreboard khong kiem cac truong nay -- chi de coverage va xem song
      exp.nxpc2                    = it.nxpc2;
      exp.predict_taken_pc         = predict_taken_pc(it.pc);
      exp.predict_taken_nxpc       = predict_taken_nxpc(it.nxpc);
      exp.predict_taken_nxpc2      = predict_taken_nxpc2(it.nxpc2);
      exp.btb_valid_pc             = read_btb_valid_pc(it.pc);
      exp.btb_valid_nxpc           = read_btb_valid_nxpc(it.nxpc);
      exp.btb_valid_nxpc2          = btb_valid_nxpc2_val;

      // === BUOC 5: thong ke (cung tren trang thai cu, truoc apply_update) ===
      update_statistics(it, exp);

      // === BUOC 6: phat di ===
      expected_port.write(exp);

      `uvm_info("BPU_REF",
                $sformatf("compute_expected: pc=%08h nxpc2=%08h is_branch=%0d taken=%0d pred_taken=%0d pred_hit=%0d => out=%08h valid=%0d flush=%0d f=%0d d=%0d corr=%0d",
                          it.pc, it.nxpc2, it.is_branch, it.branch_taken,
                          predicted_taken, pred_was_hit,
                          out_nxpc2, out_valid, flush_val,
                          f_valid, d_valid, corr_valid),
                UVM_HIGH)

      // === BUOC 7: tick duong carry-down, san sang cho chu ky sau ===
      tick_carry_down(f_valid, btb_valid_nxpc2_val, d_valid, it.halt,
                      local_pht_bit_nxpc2, global_pht_bit_nxpc2);
   endfunction : compute_expected

   //==========================================================================
   // apply_update -- nhung lenh ghi ma DUT chot o posedge nay
   //
   // RTL chan moi lenh ghi bang (wr_en && !halt), va moi wr_en deu la is_branch.
   //
   // Phai chup chi muc TRUOC lenh ghi dau tien: local_pht lay chi muc tu local_bht
   // va global_pht tu ghr, ma o day cac lenh ghi chay LAN LUOT chu khong cung roi
   // vao mot canh clock. Vi vay dung write_*_raw(), nhan san chi muc.
   //==========================================================================
   function void apply_update(bpu_item it);
      bit [9:0]  pc_idx;
      bit [11:0] lpht_idx;
      bit [9:0]  gpht_idx;
      bit [31:0] new_btb_target;
      bit [11:0] new_bht;
      bit [1:0]  new_local_pht;
      bit [1:0]  new_global_pht;
      bit [1:0]  new_choice;
      bit [9:0]  new_ghr;
      bit        choice_should_write;

      if (it.halt) return;
      if (!it.is_branch) return;

      // --- Chup chi muc truoc khi bat ky lenh ghi nao dien ra ---
      pc_idx   = get_pc_index(it.pc);
      lpht_idx = get_local_pht_index_pc(it.pc);   // doc local_bht
      gpht_idx = get_global_pht_index_pc(it.pc);  // doc ghr

      // --- Tinh moi gia tri moi tu trang thai cu ---
      new_btb_target      = compute_btb_wr_target(it.pc, it.branch_offset);
      new_bht             = compute_local_bht_wr_data(it.pc, it.branch_taken);
      new_local_pht       = compute_local_pht_wr_data(it.pc, it.branch_taken);
      new_global_pht      = compute_global_pht_wr_data(it.pc, it.branch_taken);
      choice_should_write = compute_choice_should_write(it.pc, choice_local_carry, choice_global_carry);
      new_choice          = compute_choice_wr_data(it.pc, it.branch_taken, choice_local_carry, choice_global_carry);
      new_ghr             = compute_ghr_wr_data(it.branch_taken);

      // --- Ghi that; chi muc da co dinh nen thu tu khong con quan trong ---
      write_btb_raw       (pc_idx,   new_btb_target);
      write_local_bht_raw (pc_idx,   new_bht);
      write_local_pht_raw (lpht_idx, new_local_pht);
      write_global_pht_raw(gpht_idx, new_global_pht);
      write_ghr_raw       (new_ghr);
      if (choice_should_write)
         write_choice_raw(pc_idx, new_choice);

      `uvm_info("BPU_REF",
                $sformatf("apply_update: pc=0x%08h taken=%0d offset=0x%08h => btb_target=0x%08h bht=0x%02h ghr=0x%03h%s",
                          it.pc, it.branch_taken, it.branch_offset,
                          new_btb_target, new_bht, new_ghr,
                          choice_should_write ? $sformatf(" choice=%0d", new_choice) : ""),
                UVM_HIGH)
   endfunction : apply_update

   //==========================================================================
   // update_statistics -- so lieu cho report_phase
   //   Chay tren dung trang thai cu ma compute_expected dung, nen moi nhanh duoc
   //   cham diem theo dung bo dem da du doan no.
   //==========================================================================
   function void update_statistics(bpu_item it,
                                   bpu_expected_item exp);
      bit [1:0] cur_choice;
      bit [1:0] cur_local_pht;
      bit [1:0] cur_global_pht;

      total_cycles++;

      flush_count    [exp.expected_bpu_flush]++;
      spec_case_count[exp.spec_case]++;
      corr_case_count[exp.corr_case]++;

      if (exp.expected_bpu_flush != 2'd0) begin
         cur_consecutive_flush++;
         if (cur_consecutive_flush > max_consecutive_flush)
            max_consecutive_flush = cur_consecutive_flush;
      end else begin
         cur_consecutive_flush = 0;
      end

      if (it.is_branch && !it.halt) begin
         total_branches++;

         if (exp.btb_valid_pc) btb_hits_at_branch++;
         else                  btb_misses_at_branch++;

         // bpu_flush == 2 la cach RTL ma hoa "du doan sai"
         if (exp.expected_bpu_flush == 2'd2)
            mispredicts++;

         // Tournament da hoi ben nao
         cur_choice = read_choice_pc(it.pc);
         if (cur_choice[1]) choice_used_global++;
         else               choice_used_local++;

         // Neu chay rieng thi tung ben dung sai the nao
         cur_local_pht  = read_local_pht_pc(it.pc);
         cur_global_pht = read_global_pht_pc(it.pc);
         if (cur_local_pht [1] == it.branch_taken) local_correct_count++;
         if (cur_global_pht[1] == it.branch_taken) global_correct_count++;

         // Moc bimodal: mot bo dem 2 bit cho moi PC, khong dung lich su gi.
         // Cham diem truoc roi moi cap nhat, giong hai bo tren.
         if (bimodal_pht[get_pc_index(it.pc)][1] == it.branch_taken) bimodal_correct_count++;
         bimodal_pht[get_pc_index(it.pc)] = update_counter(bimodal_pht[get_pc_index(it.pc)], it.branch_taken);
      end
   endfunction : update_statistics

   function void report_phase(uvm_phase phase);
      real mispredict_rate;
      real btb_hit_rate;
      real local_acc;
      real global_acc;

      super.report_phase(phase);

      mispredict_rate = (total_branches > 0) ?
                        (100.0 * mispredicts          / total_branches) : 0.0;
      btb_hit_rate    = (total_branches > 0) ?
                        (100.0 * btb_hits_at_branch   / total_branches) : 0.0;
      local_acc       = (total_branches > 0) ?
                        (100.0 * local_correct_count  / total_branches) : 0.0;
      global_acc      = (total_branches > 0) ?
                        (100.0 * global_correct_count / total_branches) : 0.0;

      `uvm_info("BPU_REF", $sformatf({
         "\n========================= BPU Reference Model Statistics =========================\n",
         "  Total cycles            : %0d\n",
         "  Total branches          : %0d\n",
         "  BTB hits / misses       : %0d / %0d  (hit rate: %0.2f%%)\n",
         "  Mispredictions          : %0d  (rate: %0.2f%%)\n",
         "  Choice used global/local: %0d / %0d\n",
         "  Local  predictor correct: %0d  (accuracy: %0.2f%%)\n",
         "  Global predictor correct: %0d  (accuracy: %0.2f%%)\n",
         "  Flush counts            : [0]=%0d  [1]=%0d  [2]=%0d\n",
         "  Speculation cases       : S1=%0d  S2=%0d  S3=%0d  (none=%0d)\n",
         "  Correction  cases       : C1=%0d  C2=%0d  C3=%0d  (none=%0d)\n",
         "==================================================================================="},
         total_cycles, total_branches,
         btb_hits_at_branch, btb_misses_at_branch, btb_hit_rate,
         mispredicts, mispredict_rate,
         choice_used_global, choice_used_local,
         local_correct_count,  local_acc,
         global_correct_count, global_acc,
         flush_count[0], flush_count[1], flush_count[2],
         spec_case_count[1], spec_case_count[2], spec_case_count[3], spec_case_count[0],
         corr_case_count[1], corr_case_count[2], corr_case_count[3], corr_case_count[0]
      ), UVM_LOW)
   endfunction : report_phase

endclass : bpu_reference
