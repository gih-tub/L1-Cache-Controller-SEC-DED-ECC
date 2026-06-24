//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 10.06.2026 16:22:53
// Design Name: 
// Module Name: sram_model
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Revision 0.02 - ECC encode decode changes
// Additional Comments:
//
//////////////////////////////////////////////////////////////////////////////////
module sram_model
 import cache_pkg::*;
(
    input logic clk, rst_n,   

//Write ports = we + windex + wtag + wvalid + wdirty + wdata[4] + wecc[4]
    input logic we, wvalid,wdirty,
    input logic [INDEX_BITS-1:0] windex,
    input logic [TAG_BITS-1:0] wtag,
    input logic [ECC_BITS-1:0] wecc[WORDS_LINE], //[WORDS_LINE]=4
    input logic [DATA_WIDTH-1:0] wdata[WORDS_LINE],
    
    //fault ports - for tb purposs
    input logic        fault_en,
input logic [5:0]  fault_index,
input logic [1:0]  fault_word,
input logic [4:0]  fault_bit,

//Read ports
    output logic rvalid, rdirty,
    input  logic [INDEX_BITS-1:0] rindex,
    output logic [TAG_BITS-1:0] rtag,
    output logic [ECC_BITS-1:0] recc[WORDS_LINE],
    output logic [DATA_WIDTH-1:0] rdata[WORDS_LINE]
    );  

    //Arrays
    logic [TAG_BITS-1:0] tag_array [NUM_LINES];    //1bit-64 lines
    logic valid_array[NUM_LINES];    //1bit-64 lines
    logic dirty_array[NUM_LINES];    //1bit-64 lines
    logic [DATA_WIDTH-1:0] data_array [NUM_LINES][WORDS_LINE]; // 32bit-64 lines x 4 words
    logic [ECC_BITS-1:0] ecc_array  [NUM_LINES][WORDS_LINE];  // 7bit-64 lines x 4 words

// Sequential Write
always_ff @(posedge clk) begin
    if (!rst_n) begin 
        valid_array <= '{default:0};
        dirty_array <= '{default:0}; 
        tag_array  <= '{default:0};  
        data_array   <='{default:0}; 
        ecc_array   <= '{default:0};  
            end 
    else if (fault_en)
    data_array[fault_index][fault_word][fault_bit] <= ~data_array[fault_index][fault_word][fault_bit];
    else if (we) begin
        tag_array[windex]   <= wtag;
        valid_array[windex] <= wvalid;
        dirty_array[windex] <= wdirty;

        for (int j = 0; j < WORDS_LINE; j = j + 1) begin
        data_array[windex][j] <= wdata[j];  // Write word j into column j of row windex
        ecc_array[windex][j]  <= wecc[j];   // Write ecc j into column j of row windex
        end
    end
end 

// Combinational Read
always_comb begin  
    rtag   = tag_array[rindex];
    rvalid = valid_array[rindex];
    rdirty = dirty_array[rindex];  
    for (int i = 0; i < WORDS_LINE; i++) begin  
        rdata[i] = data_array[rindex][i]; // Pull from row rindex, column i
        recc[i]  = ecc_array[rindex][i];  // Pull from row rindex, column i
    end
end
endmodule
 