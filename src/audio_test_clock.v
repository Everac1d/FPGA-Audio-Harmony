// 仅用于诊断的时钟：50MHz / 16 / 64 = 48.828125kHz。
// 所有内部逻辑均由clk驱动，内部不使用派生时钟。
module audio_test_clock (
    input wire clk,
    input wire rst_n,
    output wire bclk,
    output wire mic_ws,
    output wire fall_ce,
    output wire rx_sample_ce,
    output wire [5:0] bit_pos
);
    reg [3:0] divider = 4'd0;
    reg [5:0] position = 6'd0;
    assign bclk = divider[3];
    assign mic_ws = position[5];
    assign fall_ce = (divider == 4'd15);
    // 位于外部BCLK上升沿之后四个50MHz周期处，即80纳秒之后。
    // 由此为两级输入同步寄存器留出稳定时间。
    assign rx_sample_ce = (divider == 4'd11);
    assign bit_pos = position;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            divider <= 4'd0;
            position <= 6'd0;
        end else begin
            divider <= divider + 1'b1;
            if (fall_ce) position <= position + 1'b1;
        end
    end
endmodule
