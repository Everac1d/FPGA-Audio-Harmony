// Diagnostic clock only: 50 MHz / 16 / 64 = 48.828125 kHz.
// All internal logic runs on clk. No generated clock is used internally.
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
    // Four 50 MHz cycles (80 ns) after the external BCLK rising edge.
    // This allows the two input synchronizer registers to settle.
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
