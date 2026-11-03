// 独立的 256 槽 OFL Noto 子集，原有 LCD 字体资源保持不变。
module lcd_harmony_cjk24_font(input wire clk,input wire [7:0] glyph,
    input wire [4:0] row,column,output wire pixel);
    (* rom_style="block", syn_romstyle="block_rom" *) reg [23:0] rows[0:8191];
    reg [23:0] row_bits;reg [4:0] column_q;
    initial $readmemh("src/lcd_harmony_cjk24.mem",rows);
    always @(posedge clk)begin row_bits<=rows[{glyph,row}];column_q<=column;end
    assign pixel=column_q<24 ? row_bits[23-column_q]:1'b0;
endmodule
