//------------------------------------------------------------------------------
// MODULE: bpu_hw_top
//
//------------------------------------------------------------------------------

module bpu_hw_top;

  // Do clkgen va clk_rst_if ben duoi lai
  logic [31:0]  clock_period;
  logic         run_clock;
  logic         clock;
  logic         reset;

  // Toan bo chan cua BPU: 10 ngo vao (phia fetch + phia execute) va 3 ngo ra
  bpu_if bpu_if(clock, reset);

  clock_and_reset_if clk_rst_if(
    .clock(clock),
    .reset(reset),
    .run_clock(run_clock),
    .clock_period(clock_period)
  );

  clkgen clkgen (
    .clock(clock),
    .run_clock(run_clock),
    .clock_period(clock_period)
  );

  bpu_top dut(
    .clk                 (clock),
    .rst_n               (clk_rst_if.rst_n),
    .halt                (bpu_if.halt),
    // Phia fetch
    .fetch_opcode        (bpu_if.fetch_opcode),
    .branch_target_fetch (bpu_if.branch_target_fetch),
    .nxpc                (bpu_if.nxpc),
    .nxpc2               (bpu_if.nxpc2),
    .pc                  (bpu_if.pc),
    .flush_in            (bpu_if.flush_in),
    // Phia execute
    .is_branch           (bpu_if.is_branch),
    .branch_taken        (bpu_if.branch_taken),
    .branch_offset       (bpu_if.branch_offset),
    // Ngo ra do ve bpu_if, noi monitor lay mau
    .bpu_nxpc2           (bpu_if.bpu_nxpc2),
    .bpu_nxpc2_valid     (bpu_if.bpu_nxpc2_valid),
    .bpu_flush           (bpu_if.bpu_flush)
  );

`ifdef BPU_PIN_TRACE
  integer bpu_trace_fd;
  integer bpu_trace_cyc = 0;
  initial bpu_trace_fd = $fopen("pin_trace.txt", "w");
  always @(posedge clock) begin
    if (clk_rst_if.rst_n === 1'b1) begin
      bpu_trace_cyc = bpu_trace_cyc + 1;
      $fdisplay(bpu_trace_fd,
        "%0d %b %h %h %h %h %h %h %b %b %h %h %b %h",
        bpu_trace_cyc,
        dut.halt, dut.fetch_opcode, dut.branch_target_fetch,
        dut.nxpc, dut.nxpc2, dut.pc, dut.flush_in,
        dut.is_branch, dut.branch_taken, dut.branch_offset,
        dut.bpu_nxpc2, dut.bpu_nxpc2_valid, dut.bpu_flush);
    end
  end
`endif

endmodule
