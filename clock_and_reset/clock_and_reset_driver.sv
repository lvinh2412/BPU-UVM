

//------------------------------------------------------------------------------
// CLASS: clock_and_reset_driver
//
// Vai tro: nhan item. goi star_clock va dem chu ky
//
//------------------------------------------------------------------------------

class clock_and_reset_driver extends uvm_driver #(clock_and_reset_sequence_item);

  `uvm_component_utils(clock_and_reset_driver)

  clock_and_reset_sequence_item      item_to_queue;
  clock_and_reset_sequence_item      count_clocks_request_queue[$];

  virtual clock_and_reset_if  vif;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
  
    super.build_phase(phase);
  
  endfunction

  function void connect_phase(uvm_phase phase);
  
    if(!clock_and_reset_vif_config::get(this, "", "vif", vif))
        `uvm_error(get_type_name(), $sformatf("virtual interface must be set for: %s vif", get_full_name()))
  
  endfunction
  
  task run_phase(uvm_phase phase);
  
    fork
      issue_count_clocks_response();
    join_none;
  
    forever begin
      seq_item_port.get(req);
      if (req.clock_cycles_to_count == 0) begin
        if (req.clock_period < 2) begin
          `uvm_fatal(get_type_name(), $sformatf("clock_period must be greater than 1, clock_period = %0d",
                     req.clock_period))
        end
        vif.start_clock(req.clock_period, req.reset_delay, req.run_clock);
      end
      else begin
        queue_count_clock_requests(req);
      end
    end
  
  endtask
  
  // Khi co yeu cau dem moi: tim cho chen vao hang doi va tinh gia tri phai nap cho
  // bo dem cua interface
  task queue_count_clock_requests(
    input clock_and_reset_sequence_item clock_count_req);
  
    // Clone truoc, de item nam trong hang doi khong bi sua tu ben ngoai
    item_to_queue = clock_and_reset_sequence_item::type_id::create("item_to_queue");
    $cast(item_to_queue,clock_count_req.clone());
    item_to_queue.set_id_info(clock_count_req);
  
    if ( count_clocks_request_queue.size() == 0 ) begin
      // Yeu cau dau tien: xep vao hang doi va khoi dong bo dem cua interface
      item_to_queue.clock_cycles_to_count = clock_count_req.clock_cycles_to_count;
      vif.count_clocks(item_to_queue.clock_cycles_to_count);
  
      `uvm_info(get_type_name(),
                $sformatf("New delay of %0d arrived, starting delay counter",
                          item_to_queue.clock_cycles_to_count), UVM_LOW)
  
      count_clocks_request_queue.push_front(item_to_queue);
    end
    else begin
      // Chen yeu cau vao hang doi
      int total_clock_cycles_to_count = 0;
      int current_cycle_count;
  
      // Ghi thoi gian con lai truoc lan het gio ke tiep vao item dau hang
      vif.get_current_cycle_count(current_cycle_count);
      count_clocks_request_queue[0].clock_cycles_to_count = current_cycle_count;
  
      if(item_to_queue.clock_cycles_to_count < current_cycle_count) begin
        // So dem nho hon thi dua len dau hang va nap lai bo dem
        count_clocks_request_queue.push_front(item_to_queue);
        count_clocks_request_queue[1].clock_cycles_to_count = current_cycle_count - item_to_queue.clock_cycles_to_count;
        vif.count_clocks(item_to_queue.clock_cycles_to_count);
  
        `uvm_info(get_type_name(),
                  $sformatf("New shorter than current count of %0d arrived, starting delay counter",
                             item_to_queue.clock_cycles_to_count), UVM_LOW)
      end else if(item_to_queue.clock_cycles_to_count == current_cycle_count) begin
        // Trung so dem: chen len dau voi do tre tuong doi bang 0
        item_to_queue.clock_cycles_to_count = 0;
        count_clocks_request_queue.push_front(item_to_queue);
      end else begin
        // Chen vao giua hang doi
        for (int index=0; index<count_clocks_request_queue.size();index++) begin
          if (item_to_queue.clock_cycles_to_count >
                total_clock_cycles_to_count &&
                item_to_queue.clock_cycles_to_count <
                total_clock_cycles_to_count +
                count_clocks_request_queue[index].clock_cycles_to_count
             ) begin
            // Tru tong so dem dung truoc, chen vao, roi tru so vua chen ra khoi
            // item ke tiep
            item_to_queue.clock_cycles_to_count -= total_clock_cycles_to_count;
            count_clocks_request_queue.insert(index, item_to_queue);
            count_clocks_request_queue[index+1].clock_cycles_to_count -=
                               item_to_queue.clock_cycles_to_count;
            break;
          end else if(index == count_clocks_request_queue.size()-1) begin
            // Da toi item cuoi
            if(item_to_queue.clock_cycles_to_count < count_clocks_request_queue[$].clock_cycles_to_count) begin
              // So dem nho hon thi chen truoc item cuoi
              item_to_queue.clock_cycles_to_count -= total_clock_cycles_to_count;
              count_clocks_request_queue.insert(index,item_to_queue);
              count_clocks_request_queue[$].clock_cycles_to_count -= item_to_queue.clock_cycles_to_count;
            end else begin
              // So dem lon hon thi day xuong cuoi hang
              total_clock_cycles_to_count += count_clocks_request_queue[index].clock_cycles_to_count;
              item_to_queue.clock_cycles_to_count -= total_clock_cycles_to_count;
              count_clocks_request_queue.push_back(item_to_queue);
            end
            break;
          end
          total_clock_cycles_to_count += count_clocks_request_queue[index].clock_cycles_to_count;
        end
      end
    end
    for (int index=0; index<count_clocks_request_queue.size();index++) begin
      `uvm_info(get_type_name(),
                $sformatf("count_clocks_request_queue[%0d].clock_cycles_to_count = %0d", index,
                          count_clocks_request_queue[index].clock_cycles_to_count),
                UVM_HIGH)
    end
  
  endtask
  
  
  // Khi su kien clock_cycle_count_reached toi: tra response cho item ma bo dem vua
  // dem xong, roi nap bo dem cho item ke tiep trong hang doi
  task issue_count_clocks_response();
  
    clock_and_reset_sequence_item  rsp_item_to_return;
    forever begin
      // Dung o day cho toi khi bo dem hien tai het gio
      @(vif.clock_cycle_count_reached);
      `uvm_info(get_type_name(),
                "Delay counter reached 0 returning an item from the count_clocks_request_queue",UVM_HIGH)
  
      rsp_item_to_return = count_clocks_request_queue.pop_front();
      seq_item_port.put(rsp_item_to_return);
      if (count_clocks_request_queue.size() != 0) begin
        do begin
          if (count_clocks_request_queue[0].clock_cycles_to_count != 0) begin
            // Hen lich cho lan dem ke tiep
            vif.count_clocks(count_clocks_request_queue[0].clock_cycles_to_count);
            `uvm_info(get_type_name(), $sformatf("Next queued delay of %0d, starting delay counter", count_clocks_request_queue[0].clock_cycles_to_count), UVM_HIGH)
          end
          else begin
            // So dem bang 0 thi tra response ngay, khong can cho
            `uvm_info(get_type_name(), "Got a zero clock_cycles_to_count item from count_clocks_request_queue", UVM_HIGH)
            rsp_item_to_return = count_clocks_request_queue.pop_front();
            seq_item_port.put(rsp_item_to_return);
          end
        end while (count_clocks_request_queue.size() != 0 && rsp_item_to_return.clock_cycles_to_count == 0);
      end
    end
  endtask
  
  
  function void report_phase(uvm_phase phase);
  
    int number_of_must_happen_counts = 0;
    // Con yeu cau dem chua duoc phuc vu luc ket thuc mo phong thi ghi nhan lai
    if (count_clocks_request_queue.size() != 0) begin
      `uvm_info(get_type_name(), "count_clocks_request_queue wasn't empty - checking to see if any 'must happen' flags were set", UVM_LOW)
      // Cai nao co co "must happen" ma chua chay thi do la loi
      for (int item=0;item< count_clocks_request_queue.size();item++) begin
        if (count_clocks_request_queue[item].cycle_count_must_happen == 1) begin
          number_of_must_happen_counts++;
        end
      end
      if (number_of_must_happen_counts > 0) begin
        `uvm_error(get_type_name(), $sformatf("There were %0d clock counts with the 'must happen' flag set at the end of simulation", number_of_must_happen_counts))
      end
    end
  
  endfunction 

endclass

