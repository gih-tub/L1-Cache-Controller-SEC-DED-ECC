//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 11.06.2026 13:05:41
// Design Name: 
// Module Name: ecc_decode
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

module ecc_decode (
    input  logic [31:0] data_in,
    input  logic [6:0]  ecc_in,
    output logic [31:0] data_out,
    output logic        sec_flag,
    output logic        ded_flag
);

    logic [37:0] codeword;  // positions 1-38, index 0-37
    logic [5:0] syndrome; //for binary address of flipped bit
    logic overall;

    always_comb begin   
        //this module takes reference from the sec_ded.py reference model 
    // codeword positions
    int d_idx;
    int data_bits;
    
    codeword = '0;
    d_idx = 0;
    for (int pos = 1; pos <= 38; pos=pos+1) begin
        if ((pos & (pos-1)) != 0) begin
            codeword[pos-1] = data_in[d_idx];
            d_idx = d_idx + 1;
        end
    end
    codeword[0]  = ecc_in[0];
    codeword[1]  = ecc_in[1];
    codeword[3]  = ecc_in[2];
    codeword[7]  = ecc_in[3];
    codeword[15] = ecc_in[4];
    codeword[31] = ecc_in[5];

    //Syndrom compute
    syndrome = '0;
    for(int r=0; r<6; r=r+1) begin
        int parity_pos;
        logic p;
        parity_pos = (1 << r);
        p = 1'b0; 
        for (int pos = 1; pos <= 38; pos=pos+1) begin
    if ((pos & parity_pos) != 0)   // remove the (pos != parity_pos) exclusion
        p ^= codeword[pos-1];
end
        if(p!=0) begin
            syndrome |= parity_pos;
        end
    end

        //overall parity
        overall = ^codeword ^ ecc_in[6];  // XOR with stored overall parity

        //classify
        sec_flag = 1'b0; ded_flag = 1'b0;
        data_out = data_in;
        if (syndrome != 0 && overall == 1) begin
            sec_flag = 1'b1;
            codeword[syndrome-1] ^= 1;
        // corrected data from codeword
         data_bits=0;
           for (int pos = 1; pos <= 38; pos++) begin
            if ((pos & (pos-1)) != 0) begin
                data_out[data_bits] = codeword[pos-1];
                data_bits=data_bits+1;
                end
             end
           end else if (syndrome != 0 && overall == 0) begin
            ded_flag = 1'b1; 
            end 
    end
endmodule