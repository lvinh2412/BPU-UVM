//------------------------------------------------------------------------------
//
// CLASS: bpu_driver
//
// Vai tro: lai ca 10 ngo vao cua DUT, moi chu ky mot item
//
//------------------------------------------------------------------------------

class bpu_driver extends uvm_driver #(bpu_item);

  int num_sent;

  virtual interface bpu_if vif;

  `uvm_component_utils_begin(bpu_driver)
    `uvm_field_int(num_sent, UVM_ALL_ON)
  `uvm_component_utils_end

  function new (string name, uvm_component parent);
    super.new(name, parent);
  endfunction : new

  function void connect_phase(uvm_phase phase);
    if (!bpu_vif_config::get(this,"","vif", vif))
      `uvm_error("NOVIF",{"virtual interface must be set for: ",get_full_name(),".vif"})
  endfunction: connect_phase

  function void start_of_simulation_phase(uvm_phase phase);
    `uvm_info(get_type_name(), {"start of simulation for ", get_full_name()}, UVM_HIGH)
  endfunction : start_of_simulation_phase

  task run_phase(uvm_phase phase);
    fork
      get_and_drive();
      reset_signals();
    join
  endtask : run_phase

  task get_and_drive();
    bit item_arrived;   // bat tay giua watchdog va get_next_item

    @(posedge vif.reset);
    @(negedge vif.reset);
    `uvm_info(get_type_name(), "Reset dropped", UVM_MEDIUM)
    forever begin
      item_arrived = 1'b0;
      fork
        begin : park_watchdog
          @(negedge vif.clock);
          if (!item_arrived) begin
            vif.park_bus();
            `uvm_info(get_type_name(), "item stream dry - parking execute bus", UVM_HIGH)
          end
        end
      join_none

      seq_item_port.get_next_item(req);
      item_arrived = 1'b1;

      `uvm_info(get_type_name(), $sformatf("Driving item :\n%s", req.sprint()), UVM_MEDIUM)

      fork
        vif.drive_bpu_input(req.halt, req.fetch_opcode, req.branch_target_fetch,
                            req.nxpc, req.nxpc2, req.pc, req.flush_in,
                            req.is_branch, req.branch_taken, req.branch_offset);
        // Tach nhanh de transaction duoc mo dung luc interface bat dau lai, nho vay
        // ban ghi tren song trung khop voi chan tin hieu
        @(posedge vif.drvstart) void'(begin_tr(req, "Driver_BPU_Item"));
      join

      end_tr(req);
      num_sent++;
      seq_item_port.item_done();
    end
  endtask : get_and_drive

  // bpu_reset() cho toi khi reset len, roi xoa ngo vao va huy lan lai dang do
  task reset_signals();
    forever
      vif.bpu_reset();
  endtask : reset_signals

  function void report_phase(uvm_phase phase);
    `uvm_info(get_type_name(), $sformatf("Report: BPU driver sent %0d items", num_sent), UVM_LOW)
  endfunction : report_phase

endclass : bpu_driver
