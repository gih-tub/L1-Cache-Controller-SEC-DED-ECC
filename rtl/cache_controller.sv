//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 14.06.2026 12:41:11
// Design Name: 
// Module Name: cache_controller
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Revision 0.02 - Update SRAM logic (16.06.2026)
// Additional Comments:
// TODO - integration of AXI4-LITE slave interface
// 
//////////////////////////////////////////////////////////////////////////////////

    module cache_controller
     import cache_pkg::*;
(
    input  logic clk, rst_n,

    // SRAM interface 
    input  logic                  sram_rvalid,
    input  logic                  sram_rdirty,
   
    input  logic [21:0]   sram_rtag,
    input  logic [6:0]   sram_recc  [4],
    input  logic [31:0] sram_rdata [4],
 
    output  logic [5:0] sram_rindex,
    output logic                  sram_we,
    output logic                  sram_wvalid,
    output logic                  sram_wdirty,
    output logic [5:0] sram_windex,
    output logic [21:0]   sram_wtag,
    output logic [6:0]   sram_wecc [4] ,
    output logic [31:0] sram_wdata [4],
    
    // CPU side
    input  logic        cpu_req,      // CPU requests a cache transaction
    input  logic        cpu_write,    // 0 = Read, 1 = Write
    input  logic [31:0] cpu_addr,     // Address from CPU
    input  logic [31:0] cpu_wdata,    // Data from CPU (for writes)
    output logic [31:0] cpu_rdata,    // Data to CPU (for reads)
    output logic        cpu_stall,   // Freeze CPU pipeline on a miss
  
    // Memory side
    output logic                  mem_req,     // Request a line from Main Memory
    output logic                  mem_write,   // 0 = Read line (Refill), 1 = Write line (Evict)
    output logic [31:0]           mem_addr,    // Block address to Main Memory
    output logic [31:0] mem_wdata [4], // Line being evicted (Writeback)
    input  logic                  mem_valid,   // Main Memory says "Data is ready"
    input  logic [31:0] mem_rdata [4],  // New line fetched from Memory
    
    // ECC side
    output logic ecc_sec,
    output logic ecc_ded
    
);
    state_t current_state, next_state;  

    // Cache helpers
    logic hit, dirty_miss;
    assign hit        = sram_rvalid && (sram_rtag == cpu_addr[31:10]);
    assign dirty_miss = !hit && sram_rvalid && sram_rdirty;

    // which word, in offset
    logic [1:0] word_sel;
    assign word_sel = cpu_addr[3:2];  // offset[3:2] → 0,1,2,3
    
    //ecc logic 
    logic [31:0] dec_data;
    logic [6:0] enc_ecc [4];

    
    //for all 4 words
    genvar i;
    generate
        for(i=0;i<4; i=i+1) begin             : ecc_ports
            ecc_encode e1 (.data_in (sram_wdata[i]),.ecc_out (enc_ecc[i])); 
        end
    endgenerate

    ecc_decode d1(sram_rdata[word_sel],sram_recc[word_sel],dec_data ,ecc_sec,ecc_ded);
 
    // next state regs
     always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) current_state <= IDLE;
        else        current_state <= next_state;
    end

    // next state logic
    always_comb begin
        next_state = current_state;  

        case(current_state)
            IDLE: begin
                if (cpu_req) next_state = COMPARE; 
           end
            
            COMPARE: begin
                if (hit) 
                    next_state = DONE; // hit if TAG Match
                else if (dirty_miss) 
                    next_state = WRITEBACK; // dirty miss, if no TAG Match
                else                 
                    next_state = ALLOCATE;  // clean miss, if no TAG Match and line empty or different tag, no writeback
            end 

            WRITEBACK: begin 
                    next_state = ALLOCATE; 
            end

            ALLOCATE: begin
                if(mem_valid)
                    next_state = DONE;
                else 
                    next_state = ALLOCATE;
            end

            DONE: begin
            if (ecc_sec) next_state = SCRUB;
            else          next_state = IDLE;
        end

        SCRUB: begin
            next_state = IDLE ;  //older version didnt include 
        end
    
        default : next_state = IDLE;
        endcase
    end

    always_comb begin
    
    // SRAM Outputs
    sram_rindex = cpu_addr[9:4];  // always track current address
    sram_we      = 1'b0;
    sram_wvalid  = 1'b0;
    sram_wdirty  = 1'b0;
    sram_windex  = '0;
    sram_wtag    = '0;
    sram_wecc    = '{default: '0}; // Resets all 4 array slots
    sram_wdata   = '{default: '0}; // Resets all 4 array slots 
    cpu_rdata  = '0;
    cpu_stall  = 1'b1;   // stall by default, release only on DONE 
    mem_req      = 1'b0;
    mem_write    = 1'b0;
    mem_addr     = 32'h0;
    mem_wdata    = '{default: '0}; // Resets all 4 array slots
    
    case (current_state)
        IDLE:      begin end   

        COMPARE: begin
    if (hit && cpu_write) begin
                sram_we     = 1'b1;
                sram_windex = cpu_addr[9:4];
                sram_wtag   = sram_rtag;
                sram_wvalid = 1'b1;
                sram_wdirty = 1'b1;
                for (int i = 0; i < 4; i++)
                    sram_wdata[i] = (i == word_sel) ? cpu_wdata : sram_rdata[i];
                for (int i = 0; i < 4; i++)
                    sram_wecc[i] = enc_ecc[i];
            end
        end 

        WRITEBACK: begin
            mem_req   = 1'b1; mem_write = 1'b1;
            
            mem_addr = {sram_rtag, cpu_addr[9:4], 4'b0000};  // addr {Old_Tag, Current_Index, Zeros}
            for (int i = 0; i < 4; i++)
                mem_wdata[i] = sram_rdata[i];  // send dirty line to memory
        end 
        ALLOCATE: begin
            mem_req   = 1'b1; // miss, so to fetch from memory
            mem_write = 1'b0; // Reading from memory, not writing
            mem_addr  =  {cpu_addr[31:4], 4'b0000};   // cpu_addr, line-aligned (offset=0)  [offset == 0  because you fetch the whole line not one byte)].
            if (mem_valid) begin
                sram_we     = 1'b1;
                sram_windex = cpu_addr[9:4];  // which line/row, index bits are [9:4]
                sram_wtag   =  cpu_addr[31:10];  // updating new tag, tag bits are [31:10]
                sram_wvalid = 1'b1;
                sram_wdirty = cpu_write; // dirty if write request
                for (int i = 0; i < 4; i++)
                    sram_wdata[i] = (cpu_write &&(i == word_sel)) ? cpu_wdata : mem_rdata[i];  
                    // Write Allocate: Merge CPU write data into the target word slot; fill remaining slots from Main Memory.
                    for (int i = 0; i < 4; i++) begin
                        sram_wecc[i] = enc_ecc[i]; 
                    end

            end
             
        end 
        
        DONE: begin
            cpu_stall = '0; // release cpu_stall
            cpu_rdata =dec_data;   
        end
    endcase
end
endmodule
