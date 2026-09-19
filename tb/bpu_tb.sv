//------------------------------------------------------------------------------
//
// CLASS: bpu_tb
//
// Vai tro: moi truong muc cao nhat -- UVC clock/reset, UVC tin hieu BPU, va
//   module env muc DUT
//
//
//------------------------------------------------------------------------------

class bpu_tb extends uvm_env;

  `uvm_component_utils(bpu_tb)

  clock_and_reset_env clock_and_reset;
  bpu_env             bpu;          // toan bo chan cua BPU
  bpu_module_env      module_env;   // reference, scoreboard, coverage, backdoor

  function new (string name, uvm_component parent=null);
    super.new(name, parent);
  endfunction : new

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);

    clock_and_reset = clock_and_reset_env::type_id::create("clock_and_reset", this);

    bpu = bpu_env::type_id::create("bpu", this);

    module_env = bpu_module_env::type_id::create("module_env", this);

  endfunction : build_phase

  function void connect_phase(uvm_phase phase);

    // module_env se phan phoi tiep cho reference, scoreboard va coverage
    bpu.tx_agent.monitor.item_collected_port.connect(module_env.bpu_item_export);

  endfunction : connect_phase

endclass : bpu_tb
