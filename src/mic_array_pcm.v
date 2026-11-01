// 七路数字麦克风采集。每路 I2S 数据线包含左、右两个 32 bit 时隙。
// D0/D1/D2 各有两颗外围麦克风，D3 只有右时隙的中央麦克风。
// average_pcm 仅用于七路等权平均对照，并不代表完成降噪或波束形成。
module mic_array_pcm (
    input wire clk,
    input wire rst_n,
    input wire [3:0] mic_sd,
    input wire sample_ce,
    input wire [5:0] bit_pos,
    input wire mic_ready,
    output reg signed [15:0] central_pcm = 16'sd0,
    output reg signed [15:0] average_pcm = 16'sd0,
    output reg [111:0] channels_pcm = 112'd0,
    output reg frame_valid = 1'b0
);
    wire signed [15:0] left_pcm [0:3];
    wire signed [15:0] right_pcm [0:3];
    wire [3:0] left_valid;
    wire [3:0] right_valid;
    genvar lane;
    generate
        for (lane = 0; lane < 4; lane = lane + 1) begin : g_rx
            mic_i2s_rx receiver (
                .clk(clk), .rst_n(rst_n), .mic_sd(mic_sd[lane]),
                .sample_ce(sample_ce), .bit_pos(bit_pos),
                .pcm_left(left_pcm[lane]), .pcm_right(right_pcm[lane]),
                .left_valid(left_valid[lane]), .right_valid(right_valid[lane])
            );
        end
    endgenerate

    // 每项先显式符号扩展，避免中间加法按 16 bit 截断。
    // 七路 16 bit 的和完全落在有符号 19 bit 范围内。
    wire signed [18:0] sum_pcm =
        $signed({{3{left_pcm[0][15]}}, left_pcm[0]}) +
        $signed({{3{right_pcm[0][15]}}, right_pcm[0]}) +
        $signed({{3{left_pcm[1][15]}}, left_pcm[1]}) +
        $signed({{3{right_pcm[1][15]}}, right_pcm[1]}) +
        $signed({{3{left_pcm[2][15]}}, left_pcm[2]}) +
        $signed({{3{right_pcm[2][15]}}, right_pcm[2]}) +
        $signed({{3{right_pcm[3][15]}}, right_pcm[3]});
    wire signed [18:0] mean_pcm = sum_pcm / 19'sd7;
    reg left_seen = 1'b0;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            central_pcm <= 16'sd0;
            average_pcm <= 16'sd0;
            channels_pcm <= 112'd0;
            frame_valid <= 1'b0;
            left_seen <= 1'b0;
        end else begin
            frame_valid <= 1'b0;
            if (!mic_ready) begin
                central_pcm <= 16'sd0;
                average_pcm <= 16'sd0;
                channels_pcm <= 112'd0;
                left_seen <= 1'b0;
            end else begin
                if (&left_valid) left_seen <= 1'b1;
                // 接收器在前一时钟沿更新右时隙；此处读取的是本帧新值。
                // ready 在右时隙中途变高时，先等待下一次完整左/右帧。
                if ((&right_valid) && left_seen) begin
                    central_pcm <= right_pcm[3];
                    average_pcm <= mean_pcm[15:0];
                    channels_pcm <= {right_pcm[3], right_pcm[2], left_pcm[2],
                                     right_pcm[1], left_pcm[1],
                                     right_pcm[0], left_pcm[0]};
                    frame_valid <= 1'b1;
                    left_seen <= 1'b0;
                end
            end
        end
    end
endmodule
