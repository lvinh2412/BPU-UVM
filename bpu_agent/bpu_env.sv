//------------------------------------------------------------------------------
//
// CLASS: bpu_env
//
//------------------------------------------------------------------------------

class bpu_env extends uvm_env;

  bpu_agent tx_agent;

  `uvm_component_utils(bpu_env)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction : new

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    tx_agent = bpu_agent::type_id::create("tx_agent", this);
  endfunction : build_phase

  function void start_of_simulation_phase(uvm_phase phase);
    `uvm_info(get_type_name(), {"start of simulation for ", get_full_name()}, UVM_HIGH)
  endfunction : start_of_simulation_phase

endclass : bpu_env
