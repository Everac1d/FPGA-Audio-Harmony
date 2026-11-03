// 标准 I2S 麦克风：每个 32 个 BCLK 的时隙中包含 24 位有符号数据。
// 时隙位置 0 是 I2S 延迟位；位置 1..24 依次对应最高位至最低位。
module mic_i2s_rx (
    input wire clk,
    input wire rst_n,
    input wire mic_sd,
    input wire sample_ce,
    input wire [5:0] bit_pos,
    output reg signed [15:0] pcm_left = 16'sd0,
    output reg signed [15:0] pcm_right = 16'sd0,
    output reg left_valid = 1'b0,
    output reg right_valid = 1'b0
);
    // 尽管位时钟由本地生成，数据相对于 50 MHz 系统时钟仍然是异步的。
    // 在 BCLK 上升沿之后留出充分时间再进行采样。
    (* syn_preserve = 1, ASYNC_REG = "TRUE" *) reg sd_meta = 1'b0;
    (* syn_preserve = 1, ASYNC_REG = "TRUE" *) reg sd_sync = 1'b0;
    reg [23:0] shift_data = 24'd0;
    wire [23:0] complete_word = {shift_data[22:0], sd_sync};
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sd_meta <= 1'b0;
            sd_sync <= 1'b0;
            shift_data <= 24'd0;
            pcm_left <= 16'sd0;
            pcm_right <= 16'sd0;
            left_valid <= 1'b0;
            right_valid <= 1'b0;
        end else begin
            sd_meta <= mic_sd;
            sd_sync <= sd_meta;
            left_valid <= 1'b0;
            right_valid <= 1'b0;
            if (sample_ce && (bit_pos[4:0] >= 5'd1) &&
                             (bit_pos[4:0] <= 5'd24)) begin
                shift_data <= complete_word;
                if (bit_pos[4:0] == 5'd24) begin
                    if (!bit_pos[5]) begin
                        pcm_left <= complete_word[23:8];
                        left_valid <= 1'b1;
                    end else begin
                        pcm_right <= complete_word[23:8];
                        right_valid <= 1'b1;
                    end
                end
            end
        end
    end
endmodule
