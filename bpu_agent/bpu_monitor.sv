//------------------------------------------------------------------------------
//
// CLASS: bpu_monitor
//
// Vai tro: phat DUNG mot item moi chu ky clock, mang ca 10 ngo vao lan 3 ngo ra
//   cua DUT trong chu ky do
//
//------------------------------------------------------------------------------

class bpu_monitor extends uvm_monitor;

  bpu_item pkt;

  int num_pkt_col;

  uvm_analysis_port#(bpu_item) item_collected_port;

  virtual interface bpu_if vif;

  `uvm_component_utils_begin(bpu_monitor)
    `uvm_field_int(num_pkt_col, UVM_ALL_ON)
  `uvm_component_utils_end

  function new (string name, uvm_component parent);
    super.new(name, parent);
    item_collected_port = new("item_collected_port",this);
  endfunction : new

  function void connect_phase(uvm_phase phase);
    if (!bpu_vif_config::get(this, get_full_name(),"vif", vif))
      `uvm_error("NOVIF",{"virtual interface must be set for: ",get_full_name(),".vif"})
  endfunction: connect_phase

  task run_phase(uvm_phase phase);
    // Chua lay mau gi cho toi khi thay tron mot chu ky reset, de gia tri X luc
    // thoi diem 0 khong bao gio toi duoc mo hinh tham chieu
    @(posedge vif.reset)
    @(negedge vif.reset)
    `uvm_info(get_type_name(), "Detected Reset Done", UVM_MEDIUM)
    forever begin
      pkt = bpu_item::type_id::create("pkt", this);

      // Ben trong co @(posedge clock), nen vong lap chay dung mot lan moi chu ky va
      // moi lan cho ra mot anh chup day du
      vif.sample_bpu_all(pkt.halt, pkt.fetch_opcode, pkt.branch_target_fetch,
                         pkt.nxpc, pkt.nxpc2, pkt.pc, pkt.flush_in,
                         pkt.is_branch, pkt.branch_taken, pkt.branch_offset,
                         pkt.bpu_nxpc2, pkt.bpu_nxpc2_valid, pkt.bpu_flush);

      void'(begin_tr(pkt, "Monitor_BPU_Item"));
      end_tr(pkt);

      `uvm_info(get_type_name(), $sformatf("Item Collected :\n%s", pkt.sprint()), UVM_HIGH)
      item_collected_port.write(pkt);
      num_pkt_col++;
    end
  endtask : run_phase

  function void report_phase(uvm_phase phase);
    `uvm_info(get_type_name(), $sformatf("Report: BPU Monitor Collected %0d Items", num_pkt_col), UVM_LOW)
  endfunction : report_phase

endclass : bpu_monitor
