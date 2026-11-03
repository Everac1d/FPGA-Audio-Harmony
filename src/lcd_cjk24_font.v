// FPGA 音频 LCD 的 24 像素中日韩字形子集；位图衍生自 OFL Noto Sans SC。
// 字体来源与许可见 docs/fonts/FONT_SOURCE_AND_LICENSE.md 和 docs/fonts/OFL.txt。
// 同步推断 ROM：128 个字形槽，每槽 32 行，每行 24 位。
// 字形编号与初始化字节由工具生成，不使用手工索引。
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
