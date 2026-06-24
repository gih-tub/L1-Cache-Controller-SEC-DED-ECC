//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 11.06.2026 09:34:17
// Design Name: 
// Module Name: ecc_encode
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
//
//////////////////////////////////////////////////////////////////////////////////

module ecc_encode (
    input  logic [31:0] data_in,
    output logic [6:0]  ecc_out
);
    logic [37:0] codeword;  // positions 1-38, index 0-37

 always_comb begin
    int d_idx;
    int parity_pos;
    logic p;
    logic p_overall;

    // codeword positions
    codeword = '0;
    d_idx = 0;
    for (int pos = 1; pos <= 38; pos=pos+1) begin
        if ((pos & (pos-1)) != 0) begin
            codeword[pos-1] = data_in[d_idx];
            d_idx = d_idx + 1;
        end
    end

    // Parity
    for (int r = 0; r < 6; r=r+1) begin
        parity_pos = (1 << r);
        p = 1'b0;
        for (int pos = 1; pos <= 38; pos=pos+1) begin
            if ((pos != parity_pos) && ((pos & parity_pos) != 0))
                p ^= codeword[pos-1];
        end
        codeword[parity_pos-1] = p;
    end

    // Overall parity
    p_overall = 1'b0;
    for (int i = 0; i < 38; i=i+1)
        p_overall ^= codeword[i];

    // Pack ECC output [p1,p2,p4,p8,p16,p32,p_overall]
    ecc_out[0] = codeword[0];    // p1  at position 1
    ecc_out[1] = codeword[1];    // p2  at position 2
    ecc_out[2] = codeword[3];    // p4  at position 4
    ecc_out[3] = codeword[7];    // p8  at position 8
    ecc_out[4] = codeword[15];   // p16 at position 16
    ecc_out[5] = codeword[31];   // p32 at position 32
    ecc_out[6] = p_overall;
end
endmodule
