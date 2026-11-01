// PT8211-S: 16 位右对齐输入，每声道 32 个 BCLK。
// WS=0 为右声道，WS=1 为左声道；各槽最后 16 位依次发送 MSB..LSB。
// 两个样本在同一 frame_ce 锁存，避免半帧更新造成左右声道不同步。
module pt8211_stereo_tx (
    input wire clk,
    input wire rst_n,
    input wire fall_ce,
    input wire [5:0] bit_pos,
    input wire signed [15:0] pcm_left,
    input wire signed [15:0] pcm_right,
    output reg HP_WS = 1'b0,
    output reg HP_DIN = 1'b0,
    output wire frame_ce
);
    reg [15:0] frame_left = 16'd0;
    reg [15:0] frame_right = 16'd0;
    wire [5:0] next_pos = bit_pos + 6'd1;

    // 与原单声道发送器保持相同的帧边界，输出队列可在此边沿弹出。
    assign frame_ce = fall_ce && (bit_pos == 6'd63);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            frame_left <= 16'd0;
            frame_right <= 16'd0;
            HP_WS <= 1'b0;
            HP_DIN <= 1'b0;
        end else if (fall_ce) begin
            if (bit_pos == 6'd63) begin
                frame_left <= pcm_left;
                frame_right <= pcm_right;
            end
            // WS 在旧槽 LSB 的上升沿采样结束后才切换。
            HP_WS <= next_pos[5];
            if (next_pos[4:0] >= 5'd16) begin
                if (next_pos[5])
                    HP_DIN <= frame_left[5'd31 - next_pos[4:0]];
                else
                    HP_DIN <= frame_right[5'd31 - next_pos[4:0]];
            end else begin
                HP_DIN <= 1'b0;
            end
        end
    end
endmodule
