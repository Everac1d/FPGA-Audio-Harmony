// Independent 16px footer subset of the same OFL Noto Sans SC source.
// Main 24px font, glyph IDs and ROM stay unchanged.
module lcd_cjk16_font(
    input wire clk,
    input wire [7:0] glyph,
    input wire [3:0] row,
    input wire [4:0] column,
    output wire pixel
);
    (* rom_style="block", syn_romstyle="block_rom" *) reg [15:0] rows[0:2047];
    reg [15:0] row_bits;
    reg [4:0] column_q;
    initial $readmemh("src/lcd_cjk16.mem",rows);
    always @(posedge clk)begin
        row_bits<=rows[{glyph[6:0],row}];
        column_q<=column;
    end
    assign pixel=column_q<16 ? row_bits[15-column_q] : 1'b0;
endmodule
