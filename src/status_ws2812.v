// 板载单颗WS2812，颜色顺序GRB，在50MHz时钟下以100Hz刷新。
module status_ws2812 (
    input wire clk,
    input wire rst_n,
    input wire [23:0] color_grb,
    output reg WS2812 = 1'b0
);
    reg [18:0] refresh_count = 19'd0;
    reg [23:0] frame_data = 24'd0;
    reg [4:0] bit_index = 5'd23;
    reg [5:0] bit_tick = 6'd0;
    reg busy = 1'b0;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            refresh_count <= 19'd0;
            frame_data <= 24'd0;
            bit_index <= 5'd23;
            bit_tick <= 6'd0;
            busy <= 1'b0;
            WS2812 <= 1'b0;
        end else begin
            refresh_count <= (refresh_count == 19'd499999) ? 19'd0 : refresh_count + 1'b1;
            if (refresh_count == 19'd0) begin
                frame_data <= color_grb;
                bit_index <= 5'd23;
                bit_tick <= 6'd0;
                busy <= 1'b1;
                WS2812 <= 1'b0;
            end else if (busy) begin
                WS2812 <= (bit_tick < (frame_data[bit_index] ? 6'd40 : 6'd20));
                if (bit_tick == 6'd62) begin
                    bit_tick <= 6'd0;
                    if (bit_index == 5'd0) busy <= 1'b0;
                    else bit_index <= bit_index - 1'b1;
                end else bit_tick <= bit_tick + 1'b1;
            end else WS2812 <= 1'b0;
        end
    end
endmodule
