// FPGA Audio LCD CJK24 Subset; bitmap derivative of OFL Noto Sans SC.
// See docs/fonts/FONT_SOURCE_AND_LICENSE.md and docs/fonts/OFL.txt.
// Synchronous inferred ROM: 128 glyph slots x 32 rows x 24 bits.
// Glyph IDs and initialization bytes are generated, not hand indexed.
module lcd_cjk24_font(
    input wire clk,
    input wire [7:0] glyph,
    input wire [4:0] row,column,
    output wire pixel
);
    (* rom_style="block", syn_romstyle="block_rom" *) reg [23:0] rows[0:4095];
    reg [23:0] row_bits;
    reg [4:0] column_q;
    initial $readmemh("src/lcd_cjk24.mem",rows);
    always @(posedge clk)begin
        row_bits<=rows[{glyph[6:0],row}];
        column_q<=column;
    end
    assign pixel=column_q<24 ? row_bits[23-column_q] : 1'b0;
endmodule
