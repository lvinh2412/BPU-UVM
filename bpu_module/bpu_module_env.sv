//------------------------------------------------------------------------------//
// CLASS: bpu_module_env
//
// Vai tro: moi truong muc DUT -- mo hinh tham chieu, scoreboard, coverage, backdoor
//   va toan bo day noi TLM giua chung
//
//------------------------------------------------------------------------------

class bpu_module_env extends uvm_env;

  bpu_reference  reference;
  bpu_scoreboard scoreboard;
  bpu_coverage   coverage;

  // Truy cap trang thai noi bo DUT. Dat o day de test goi duoc qua
  // tb.module_env.backdoor.
  bpu_backdoor   backdoor;

  uvm_analysis_export #(bpu_item) bpu_item_export;

  `uvm_component_utils_begin(bpu_module_env)
  `uvm_component_utils_end

  function new(input string name, input uvm_component parent=null);
    super.new(name, parent);
    bpu_item_export = new("bpu_item_export", this);
  endfunction : new

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    reference  = bpu_reference ::type_id::create("reference",  this);
    scoreboard = bpu_scoreboard::type_id::create("scoreboard", this);
    coverage   = bpu_coverage  ::type_id::create("coverage",   this);
    // La uvm_object chu khong phai component, nen khong co tham so parent
    backdoor   = bpu_backdoor  ::type_id::create("backdoor");
  endfunction : build_phase

  function void connect_phase(uvm_phase phase);
    // item mang CA ngo vao ma mo hinh tham chieu can, LAN ngo ra ma scoreboard
    // kiem, nen phai gui ca hai noi.
    bpu_item_export.connect(reference.item_fifo.analysis_export);
    bpu_item_export.connect(scoreboard.item_fifo.analysis_export);

    reference.expected_port.connect(scoreboard.expected_fifo.analysis_export);
    reference.expected_port.connect(coverage.analysis_export);

    // Coverage con lay mau truc tiep tu trang thai bong, ngoai cai item mang theo
    coverage.ref_handle = reference;
  endfunction : connect_phase

endclass : bpu_module_env
