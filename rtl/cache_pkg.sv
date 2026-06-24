package cache_pkg;
  
    
parameter CACHE_SIZE   = 1024;
parameter LINE_SIZE    = 16;
parameter WORD_SIZE    = 4;
parameter DATA_WIDTH   = 32;
parameter ADDR_WIDTH   = 32;


parameter WORDS_LINE   = LINE_SIZE / WORD_SIZE;
parameter NUM_LINES    = CACHE_SIZE / LINE_SIZE;

parameter OFFSET_BITS  = 4;   // log2(LINE_SIZE)
parameter INDEX_BITS   = 6;   // log2(NUM_LINES)
parameter TAG_BITS     = ADDR_WIDTH - INDEX_BITS - OFFSET_BITS;
// ECC: 7 bits per 32-bit word (6 Hamming + 1 overall parity)
parameter ECC_BITS     = 7;

    // FSM state one-hot encoding 
    typedef enum logic [7:0] {
        IDLE      = 6'b000001,
        COMPARE   = 6'b000010,
        WRITEBACK = 6'b000100,
        ALLOCATE  = 6'b001000,
        DONE      = 6'b010000,
        SCRUB     = 6'b100000
    } state_t;

endpackage