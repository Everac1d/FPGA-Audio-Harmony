// Separate 256-slot true16px OFL Noto subset; no 24px downsampling.
module lcd_harmony_cjk16_font(input wire clk,input wire [7:0] glyph,
    input wire [3:0] row,input wire [4:0] column,output wire pixel);
    (* rom_style="block", syn_romstyle="block_rom" *) reg [15:0] rows[0:4095];
    reg [15:0] row_bits;reg [4:0] column_q;
    initial $readmemh("src/lcd_harmony_cjk16.mem",rows);
    always @(posedge clk)begin row_bits<=rows[{glyph,row}];column_q<=column;end
    assign pixel=column_q<16 ? row_bits[15-column_q]:1'b0;
endmodule
