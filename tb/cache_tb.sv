`timescale 1ns/1ps

module cache_tb_reference;
    import cache_pkg::*; 
    
     int test_num   = 0;
     
    logic clk = 0;
    logic rst_n;
    
    logic        cpu_req, cpu_write;
    logic [31:0] cpu_addr, cpu_wdata, cpu_rdata;
    logic        cpu_stall;

    logic        mem_req, mem_write, mem_valid;
    logic [31:0] mem_addr;
    logic [31:0] mem_wdata[4], mem_rdata[4];

    logic ecc_sec, ecc_ded;
    
    logic                  sram_we, sram_wvalid, sram_wdirty;
    logic [5:0]            sram_windex, sram_rindex;
    logic [21:0]           sram_wtag, sram_rtag;
    logic [6:0]            sram_wecc[4], sram_recc[4];
    logic [31:0]           sram_wdata[4], sram_rdata[4];
    logic                  sram_rvalid, sram_rdirty;

    logic       fault_en;
    logic [5:0] fault_index;
    logic [1:0] fault_word;
    logic [4:0] fault_bit;
    
    cache_controller dut (
        .clk(clk), .rst_n(rst_n),
        .cpu_req(cpu_req), .cpu_write(cpu_write),
        .cpu_addr(cpu_addr), .cpu_wdata(cpu_wdata),
        .cpu_rdata(cpu_rdata), .cpu_stall(cpu_stall),
        .mem_req(mem_req), .mem_write(mem_write), .mem_valid(mem_valid),
        .mem_addr(mem_addr), .mem_wdata(mem_wdata), .mem_rdata(mem_rdata),
        .ecc_sec(ecc_sec), .ecc_ded(ecc_ded),
        .sram_rvalid(sram_rvalid), .sram_rdirty(sram_rdirty),
        .sram_rtag(sram_rtag), .sram_recc(sram_recc), .sram_rdata(sram_rdata),
        .sram_rindex(sram_rindex),
        .sram_we(sram_we), .sram_wvalid(sram_wvalid), .sram_wdirty(sram_wdirty),
        .sram_windex(sram_windex), .sram_wtag(sram_wtag),
        .sram_wecc(sram_wecc), .sram_wdata(sram_wdata)
    );

    sram_model u_sram (
        .clk(clk), .rst_n(rst_n),
        .we(sram_we), .wvalid(sram_wvalid), .wdirty(sram_wdirty),
        .windex(sram_windex), .wtag(sram_wtag),
        .wecc(sram_wecc), .wdata(sram_wdata),
        .fault_en(fault_en), .fault_index(fault_index),
        .fault_word(fault_word), .fault_bit(fault_bit),
        .rvalid(sram_rvalid), .rdirty(sram_rdirty),
        .rindex(sram_rindex), .rtag(sram_rtag),
        .recc(sram_recc), .rdata(sram_rdata)
    );
    always #5 clk = ~clk;
    
    logic [31:0] backing_mem[bit [31:0]];

    function automatic logic [31:0] mem_read_word(logic [31:0] addr);
        if (backing_mem.exists(addr))
            return backing_mem[addr];
        else
            return 32'h0;
    endfunction

    always_ff @(posedge clk) begin
        mem_valid <= 1'b0;
        if (mem_req) begin
            if (mem_write) begin
                for (int i = 0; i < 4; i++)
                    backing_mem[mem_addr + i*4] = mem_wdata[i];
            end else begin
                for (int i = 0; i < 4; i++)
                    mem_rdata[i] <= mem_read_word(mem_addr + i*4);
            end
            mem_valid <= 1'b1;
        end
    end
 
    // Reference model state (this was implemented similar to the refeence model)
    typedef struct {
        logic        valid;
        logic        dirty;
        logic [21:0] tag;
        logic [31:0] data[4];
    } ref_line_t;

    ref_line_t ref_lines[64];

    function automatic void ref_init();
        for (int i = 0; i < 64; i++) begin
            ref_lines[i].valid = 0;
            ref_lines[i].dirty = 0;
            ref_lines[i].tag   = 0;
            for (int j = 0; j < 4; j++) ref_lines[i].data[j] = 0;
        end
    endfunction

    // Returns expected (data, hit) for a read - mirrors CacheModel.read()
    function automatic void ref_read(logic [31:0] addr,
                                      output logic [31:0] exp_data,
                                      output logic        exp_hit);
        logic [21:0] tag;
        logic [5:0]  idx;
        logic [1:0]  wsel;
        tag  = addr[31:10];
        idx  = addr[9:4];
        wsel = addr[3:2];

        exp_hit = ref_lines[idx].valid && (ref_lines[idx].tag == tag);

        if (!exp_hit) begin
            // writeback if dirty
            if (ref_lines[idx].valid && ref_lines[idx].dirty) begin
                for (int i = 0; i < 4; i++)
                    backing_mem[{ref_lines[idx].tag, idx, 4'b0} + i*4] = ref_lines[idx].data[i];
            end
            // fill
            ref_lines[idx].valid = 1;
            ref_lines[idx].dirty = 0;
            ref_lines[idx].tag   = tag;
            for (int i = 0; i < 4; i++)
                ref_lines[idx].data[i] = mem_read_word({tag, idx, 4'b0} + i*4);
        end

        exp_data = ref_lines[idx].data[wsel];
    endfunction

    // Updates ref model for a write - mirrors CacheModel.write()
    function automatic void ref_write(logic [31:0] addr, logic [31:0] data,
                                       output logic exp_hit);
        logic [21:0] tag;
        logic [5:0]  idx;
        logic [1:0]  wsel;
        tag  = addr[31:10];
        idx  = addr[9:4];
        wsel = addr[3:2];

        exp_hit = ref_lines[idx].valid && (ref_lines[idx].tag == tag);

        if (!exp_hit) begin
            if (ref_lines[idx].valid && ref_lines[idx].dirty) begin
                for (int i = 0; i < 4; i++)
                    backing_mem[{ref_lines[idx].tag, idx, 4'b0} + i*4] = ref_lines[idx].data[i];
            end
            ref_lines[idx].valid = 1;
            ref_lines[idx].dirty = 0;
            ref_lines[idx].tag   = tag;
            for (int i = 0; i < 4; i++)
                ref_lines[idx].data[i] = mem_read_word({tag, idx, 4'b0} + i*4);
        end

        ref_lines[idx].data[wsel] = data;
        ref_lines[idx].dirty      = 1;
    endfunction 
    
    // Counters Scoreboard
    int pass_count = 0;
    int fail_count = 0;

//Tasks
    task automatic drive_read(logic [31:0] addr, output logic [31:0] got_data,
                               output logic got_sec, output logic got_ded);
        @(posedge clk);
        cpu_req   = 1; cpu_write = 0; cpu_addr = addr;
        @(posedge clk);
        while (cpu_stall) @(posedge clk);
        // current_state == DONE on this edge 
        got_data = cpu_rdata;
        got_sec  = ecc_sec;
        got_ded  = ecc_ded;
        cpu_req  = 0;
        @(posedge clk);
    endtask

    task automatic drive_write(logic [31:0] addr, logic [31:0] data);
        @(posedge clk);
        cpu_req = 1; cpu_write = 1; cpu_addr = addr; cpu_wdata = data;
        @(posedge clk);
        while (cpu_stall) @(posedge clk);
        cpu_req = 0;
        @(posedge clk);
    endtask

    task automatic inject_single_fault(logic [5:0] line, logic [1:0] word, logic [4:0] bit_pos);
        fault_index = line; fault_word = word; fault_bit = bit_pos;
        fault_en = 1'b1;
        @(posedge clk);
        fault_en = 1'b0;
    endtask

    task automatic inject_double_fault(logic [5:0] line, logic [1:0] word,
                                        logic [4:0] bit0, logic [4:0] bit1);
        inject_single_fault(line, word, bit0);
        inject_single_fault(line, word, bit1);
    endtask
    
    task automatic verify_writeback(logic [31:0] evict_addr, logic [31:0] expected[4]);
    for (int i = 0; i < 4; i++) begin
        if (backing_mem[evict_addr + i*4] !== expected[i]) begin
            $error("WRITEBACK MISMATCH word%0d addr=%08h: got %08h exp %08h",
                    i, evict_addr + i*4, backing_mem[evict_addr+i*4], expected[i]);
            fail_count++;
        end else begin
            $display("[WRITEBACK_CHECK] word%0d addr=%08h = %08h -- OK",
                      i, evict_addr + i*4, expected[i]);
        end
    end
endtask
 
    // Scoreboard check tasks 
    task automatic check_read(string name, logic [31:0] addr,
                               logic exp_sec_allowed = 0, logic exp_ded_allowed = 0);
        logic [31:0] exp_data, got_data;
        logic        exp_hit, got_sec, got_ded;

        ref_read(addr, exp_data, exp_hit);
        drive_read(addr, got_data, got_sec, got_ded);

        if (got_ded && exp_ded_allowed) begin
            // data undefined when DED - only check the flag
            $display("[%-20s] addr=%08h DED detected (data not checked) -- PASS", name, addr);
            pass_count++;
        end else if (got_data === exp_data) begin
            $display("[%-20s] addr=%08h data=%08h (exp=%08h) sec=%b ded=%b -- PASS",
                      name, addr, got_data, exp_data, got_sec, got_ded);
            pass_count++;
        end else begin
            $display("[%-20s] addr=%08h data=%08h (exp=%08h) sec=%b ded=%b -- FAIL",
                      name, addr, got_data, exp_data, got_sec, got_ded);
            fail_count++;
        end
    endtask

    task automatic check_write(string name, logic [31:0] addr, logic [31:0] data);
        logic exp_hit;
        ref_write(addr, data, exp_hit);
        drive_write(addr, data);
        // Write correctness verified indirectly via subsequent reads
        $display("[%-20s] addr=%08h data=%08h written (exp_hit=%b)", name, addr, data, exp_hit);
    endtask
    
  

// ASSERTIONS

    // 1. SEC and DED mutually exclusive
    a_sec_ded_excl: assert property (
        @(posedge clk) disable iff (!rst_n)
        !(ecc_sec && ecc_ded)
    ) else $error("[A1] SEC and DED asserted simultaneously");

    // 2. WRITEBACK -> ALLOCATE in exactly one cycle
    a_wb_to_alloc: assert property (
        @(posedge clk) disable iff (!rst_n)
        (dut.current_state == WRITEBACK) |-> ##1 (dut.current_state == ALLOCATE)
    ) else $error("[A2] WRITEBACK not followed by ALLOCATE");

    // 3. DONE only reachable from COMPARE (hit) or ALLOCATE (miss resolved)
    a_done_legal_pred: assert property (
        @(posedge clk) disable iff (!rst_n)
        (dut.current_state == DONE) |->
        ($past(dut.current_state) == COMPARE || $past(dut.current_state) == ALLOCATE)
    ) else $error("[A3] DONE reached from illegal predecessor state");

    // 4. cpu_stall asserted whenever FSM busy
    a_stall_while_busy: assert property (
        @(posedge clk) disable iff (!rst_n)
        (dut.current_state inside {COMPARE, WRITEBACK, ALLOCATE}) |-> cpu_stall
    ) else $error("[A4] cpu_stall low while FSM busy");

    // 5. No deadlock - ALLOCATE resolves to DONE within bounded cycles
    a_no_deadlock: assert property (
        @(posedge clk) disable iff (!rst_n)
        (dut.current_state == ALLOCATE) |-> ##[1:8] (dut.current_state == DONE)
    ) else $error("[A5] ALLOCATE did not resolve to DONE within 8 cycles");

    // 6. cpu_rdata stable while cpu_stall is high (no garbage glitches on bus)
    a_rdata_stable_while_stalled: assert property (
        @(posedge clk) disable iff (!rst_n)
        (cpu_stall && $past(cpu_stall)) |-> ($stable(cpu_rdata) || cpu_rdata === 'x)
    ) else $error("[A6] cpu_rdata glitched while stalled");

    // 7. one-hot state encoding check
    logic [5:0] current_state_bits;
    assign current_state_bits = dut.current_state;
    a_state_onehot: assert property (
        @(posedge clk) disable iff (!rst_n)
        $onehot(current_state_bits)
    ) else $error("[A7] current_state is not one-hot");
 

    
    // Covergroups 
    covergroup cg_fsm @(posedge clk);
        option.per_instance = 1;
        cp_state: coverpoint dut.current_state {
    bins idle      = {IDLE};
    bins compare   = {COMPARE};
    bins writeback = {WRITEBACK};
    bins allocate  = {ALLOCATE};
    bins done      = {DONE};
    bins scrub     = {SCRUB};  
}
        cp_trans: coverpoint dut.current_state {
            bins hit_path    = (COMPARE => DONE);
            bins clean_miss  = (COMPARE => ALLOCATE);
            bins dirty_miss  = (COMPARE => WRITEBACK);
            bins wb_to_alloc = (WRITEBACK => ALLOCATE);
            bins alloc_done  = (ALLOCATE => DONE);
            bins done_idle   = (DONE => IDLE);
            bins idle_compare= (IDLE => COMPARE);
        }
    endgroup

    covergroup cg_ecc @(posedge clk);
        option.per_instance = 1;
        cp_ecc: coverpoint {ecc_sec, ecc_ded} {
            bins no_error  = {2'b00};
            bins sec_error = {2'b10};
            bins ded_error = {2'b01};
            illegal_bins illegal = {2'b11};
        }
    endgroup

    covergroup cg_ops @(posedge clk);
        option.per_instance = 1;
        cp_rw: coverpoint cpu_write iff (cpu_req && !cpu_stall) {
            bins rd = {0};
            bins wr = {1};
        }
    endgroup

    cg_fsm fsm_cg = new();
    cg_ecc ecc_cg = new();
    cg_ops ops_cg = new();
 
    // Continuous monitor 
    always @(posedge clk) begin
        if (rst_n && dut.current_state == DONE) begin
            $display("[MONITOR] t=%0t state=DONE addr=%08h rdata=%08h sec=%b ded=%b stall=%b",
                      $time, cpu_addr, cpu_rdata, ecc_sec, ecc_ded, cpu_stall);
        end
    end

//Main initial block
    initial begin
        rst_n = 0;
        cpu_req = 0; cpu_write = 0; cpu_addr = 0; cpu_wdata = 0;
        fault_en = 0; fault_index = 0; fault_word = 0; fault_bit = 0;
        ref_init();

        repeat(2) @(posedge clk);
        rst_n = 1;
        repeat(2) @(posedge clk);

        $display("\n TESTS:");

        // 1. old read miss
        check_read("T1_cold_read_miss", 32'h00000010);

        // 2. read hit
        check_read("T2_read_hit", 32'h00000010);

        // 3. write hit -> dirty
        check_write("T3_write_hit", 32'h00000010, 32'hCAFEF00D);

        // 4. read-back confirms write landed
        check_read("T4_readback_after_write", 32'h00000010);

       /*// 5. dirty eviction - same index, different tag
        check_read("T5_dirty_eviction", 32'h00000410);*/
        
        // 5. dirty eviction - same index, different tag
        check_read("T5_dirty_eviction", 32'h00000410);
        // Explicit writeback check - word0 should be CAFEF00D, rest 0
        begin
            logic [31:0] expected[4];
            expected[0] = 32'hCAFEF00D;
            expected[1] = 32'h00000000;
            expected[2] = 32'h00000000;
            expected[3] = 32'h00000000;
            verify_writeback(32'h00000010, expected);
        end
        // 6. write miss -> allocate + merge
        check_write("T6_write_miss", 32'h00000020, 32'hABCD1234);
        check_read("T6_readback", 32'h00000020);

        $display("\n===== FAULT INJECTION TESTS =====");

        /*
        // 7. single-bit fault -> SEC
        inject_single_fault(6'd2, 2'd0, 5'd5);
        check_read("T7_single_fault_SEC", 32'h00000020); */
        // 7. single-bit fault -> SEC correction verified
        inject_single_fault(6'd2, 2'd0, 5'd5);
        begin
            logic [31:0] got; logic sec, ded;
            drive_read(32'h00000020, got, sec, ded);
            if (!sec) begin
                $error("T7: SEC did not fire");
                fail_count++;
            end else if (got !== 32'hABCD1234) begin
                $error("T7: SEC correction wrong: got %08h exp abcd1234", got);
                fail_count++;
            end else begin
                $display("[T7_single_fault_SEC     ] SEC fired, data correctly corrected to %08h -- PASS", got);
                pass_count++;
            end
            test_num++;
        end
        

        // 8. double-bit fault -> DED
        check_read("T8_setup", 32'h00000030);
        inject_double_fault(6'd3, 2'd0, 5'd2, 5'd9);
        check_read("T8_double_fault_DED", 32'h00000030, .exp_ded_allowed(1));

        $display("\n===== EDGE CASES =====");

        // 9. write to index 0 then evict via different tag, then re-read original
        check_write("T9a_fill_idx0", 32'h00000000, 32'h11111111);
        check_read("T9b_evict_idx0", 32'h00000400);   // index 0, tag 1
        check_read("T9c_revisit_idx0", 32'h00000000); // should re-fetch from mem (written back earlier)
        
        repeat(5) @(posedge clk);

        $display("\n========================================");
        $display("RESULT: %0d PASS / %0d FAIL", pass_count, fail_count);
        $display("FSM coverage: %0.2f%%", fsm_cg.get_coverage());
        $display("ECC coverage: %0.2f%%", ecc_cg.get_coverage());
        $display("OPS coverage: %0.2f%%", ops_cg.get_coverage());
        $display("========================================");

        if (fail_count == 0)
            $display("OVERALL: PASS");
        else
            $display("OVERALL: FAIL"); 
        $finish;
    end 
endmodule
