//------------------------------------------------------------------------------
//
// CLASS: bpu_sequencer
//
// phan phoi item giua sequence va driver
//
//------------------------------------------------------------------------------

class bpu_sequencer extends uvm_sequencer #(bpu_item);

  bpu_item  item;

  `uvm_component_utils(bpu_sequencer)

  function new(string name, uvm_component parent);
    super.new(name, parent);     // important!!
  endfunction

  function void start_of_simulation_phase(uvm_phase phase);
    `uvm_info(get_type_name(), {"start of simulation for ", get_full_name()}, UVM_HIGH)
  endfunction : start_of_simulation_phase

endclass : bpu_sequencer
