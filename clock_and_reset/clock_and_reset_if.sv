//------------------------------------------------------------------------------
// FILE: clock_and_reset_if.sv
//
// Vai tro: sinh reset va dieu khien clkgen, kem mot bo dem chu ky dung chung
//
//------------------------------------------------------------------------------

interface clock_and_reset_if  (
    input  bit          clock,
    output bit          reset,
    output bit          rst_n,                  
           bit          run_clock = 0,
           logic [31:0] clock_period = 10 );

  int reset_delay;
  int clock_cycles_to_count;
  bit clock_cycle_count_reached=0;

  // Cuc tinh reset ma DUT can
  assign rst_n = ~reset;

  `ifdef IXCOM_UXE
    initial $ixc_ctrl("tb_export","start_clock");
    initial $ixc_ctrl("tb_export","count_clocks");
    initial $ixc_ctrl("tb_export","get_current_cycle_count");
    initial $export_event(clock_and_reset_if.clock_cycle_count_reached);
  `endif

  ///////////////////////////////////////
  // Sinh clock va reset                //
  ///////////////////////////////////////
  task start_clock(
    input int input_clock_period, input_reset_delay,
    input bit input_run_clock
  );
    run_clock    = input_run_clock;
    clock_period = input_clock_period;
    reset_delay  = input_reset_delay;
  endtask

  // Reset len trong reset_delay chu ky roi ha. Luu y no duoc lai TU mot canh clock,
  // nen sequence chi co the danh thuc no dung tai canh clock.
  always @(posedge clock) begin
    if (reset_delay > 0) begin
      reset <= 1'b1;
      reset_delay--;
    end
    else begin
      reset <= 1'b0;
    end
  end

  /////////////////////////////////////////////////
  // Dem chu ky clock (cho timeout, cho xa   //
  // du lieu, ...)                           //
  /////////////////////////////////////////////////
  task count_clocks(input int new_count);
    // +1 de bo dem dung duoc 0 lam trang thai nghi ma van bao dung o chu ky cuoi
    // duoc yeu cau, khong som mot nhip
    clock_cycles_to_count = new_count + 1;
  endtask

  task get_current_cycle_count(output int cycles_counted);
    if (clock_cycles_to_count != 0) begin
      cycles_counted = clock_cycles_to_count - 1;
    end
    else begin
      cycles_counted = 0;
    end
  endtask

  always @(posedge clock) begin
    if (clock_cycles_to_count != 0) begin
      clock_cycles_to_count--;
    end
    if (clock_cycles_to_count == 1) begin
        clock_cycle_count_reached = ~clock_cycle_count_reached;
    end
  end

endinterface
