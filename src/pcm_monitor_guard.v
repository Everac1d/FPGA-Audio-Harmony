// 仅对输出侧进行保护，原始麦克风及核心 PCM 数据保持不变。
// 持续进行三级时钟流水准备以供发送器使用；帧状态每帧推进一次。
// 本板到达帧边界时，队首数据已提前超过 100 个时钟周期稳定。
// 时钟沿 N 输入的数据在时钟沿 N+2 后出现在输出端（三级寄存器）。
// PIPELINE_ENABLE=0 时保留组合参考实现，供原有回归测试使用。
// Q8 增益每帧渐变 1/256；Q8 包络在 256 帧（5.243 毫秒）内完成淡化。
// 原有目标增益：H0=1 倍，H2=1.5 倍，H4=2 倍，H5=2.5 倍，H6=3 倍。
// FINE_GAIN 以十分之一倍为单位，范围 10..30，舍入至最近的 Q8 单位。其他编码
// 保守映射到单位增益；端点 1 倍和 3 倍仍可精确表示。
// 软拐点：|x|<=8192 时保持不变；超过拐点时采用 8192+(|x|-8192)/4。
// 此处理限制过载能量，不执行声学回声或反馈抵消。
module pcm_monitor_guard #(
    parameter integer PROTECTION_ENABLE = 1,
    parameter integer SMOOTH_ENABLE = 1,
    parameter integer PIPELINE_ENABLE = 1,
    parameter integer FINE_GAIN = 0
) (
    input wire clk, rst_n, frame_ce,
    input wire [1:0] active_mode, requested_mode,
    input wire source_ready,
    input wire [4:0] gain_index,
    input wire signed [15:0] pcm_in,
    output wire signed [15:0] pcm_out,
    output wire switch_ready,
    output wire would_clip,
    output wire limiting,
    output wire [8:0] fade_level
);
    reg [8:0] envelope = 0;
    // 保留既有增益寄存器位宽；Q8 格式中的三倍增益为 768。
    reg [11:0] gain_q8 = 12'd256;
    function [11:0] gain_target_q8;
        input [4:0] index;
        begin
            if(FINE_GAIN!=0)begin
                // round(index * 256 / 10)；通过常量查找表缩短 50 MHz
                // 目标增益路径，避免综合出除法器。
                case(index)
                    5'd10:gain_target_q8=12'd256;
                    5'd11:gain_target_q8=12'd282;
                    5'd12:gain_target_q8=12'd307;
                    5'd13:gain_target_q8=12'd333;
                    5'd14:gain_target_q8=12'd358;
                    5'd15:gain_target_q8=12'd384;
                    5'd16:gain_target_q8=12'd410;
                    5'd17:gain_target_q8=12'd435;
                    5'd18:gain_target_q8=12'd461;
                    5'd19:gain_target_q8=12'd486;
                    5'd20:gain_target_q8=12'd512;
                    5'd21:gain_target_q8=12'd538;
                    5'd22:gain_target_q8=12'd563;
                    5'd23:gain_target_q8=12'd589;
                    5'd24:gain_target_q8=12'd614;
                    5'd25:gain_target_q8=12'd640;
                    5'd26:gain_target_q8=12'd666;
                    5'd27:gain_target_q8=12'd691;
                    5'd28:gain_target_q8=12'd717;
                    5'd29:gain_target_q8=12'd742;
                    5'd30:gain_target_q8=12'd768;
                    default:gain_target_q8=12'd256;
                endcase
            end else case (index)
                3'd0: gain_target_q8 = 12'd256;
                3'd1: gain_target_q8 = 12'd256;
                3'd2: gain_target_q8 = 12'd384;
                3'd3: gain_target_q8 = 12'd256;
                3'd4: gain_target_q8 = 12'd512;
                3'd5: gain_target_q8 = 12'd640;
                3'd6: gain_target_q8 = 12'd768;
                3'd7: gain_target_q8 = 12'd256;
                default: gain_target_q8 = 12'd256;
            endcase
        end
    endfunction
    wire [11:0] requested_gain = gain_target_q8(gain_index);
    assign fade_level = SMOOTH_ENABLE ? envelope : 9'd256;
    assign switch_ready = !SMOOTH_ENABLE || envelope == 0;
    always @(posedge clk) begin
        if (!rst_n) begin envelope <= 0; gain_q8 <= 256; end
        else if (frame_ce) begin
            if (gain_q8 < requested_gain) gain_q8 <= gain_q8 + 1'b1;
            else if (gain_q8 > requested_gain) gain_q8 <= gain_q8 - 1'b1;
            if (requested_mode != active_mode) begin
                if (envelope != 0) envelope <= envelope - 1'b1;
            end else if (source_ready && active_mode != 0) begin
                if (envelope < 256) envelope <= envelope + 1'b1;
            end else envelope <= 0;
        end
    end
    reg signed [31:0] product, scaled, magnitude, shaped, faded;
    reg signed [31:0] gain_value;
    always @* begin
        // 测试音使用固定增益，但共用模式切换淡化；操作数显式声明为有符号数。
        gain_value = (active_mode == 2) ? 32'sd256 :
                     (SMOOTH_ENABLE ? $signed({20'd0,gain_q8}) : $signed({20'd0,requested_gain}));
        product = $signed(pcm_in) * gain_value;
        scaled = product / 32'sd256; // 正负数均向零截断
        magnitude = (scaled < 0) ? -scaled : scaled;
        shaped = magnitude;
        if (PROTECTION_ENABLE && active_mode == 1 && magnitude > 8192)
            shaped = 8192 + ((magnitude - 8192) / 4);
        if (scaled < 0) shaped = -shaped;
        if (shaped > 32767) shaped = 32767;
        if (shaped < -32768) shaped = -32768;
        faded = SMOOTH_ENABLE ? ((shaped * $signed({23'd0,envelope})) / 256) : shaped;
    end
    wire raw_clip = source_ready && active_mode == 1 && (scaled > 32767 || scaled < -32768);
    wire raw_limit = source_ready && active_mode == 1 && PROTECTION_ENABLE && magnitude > 8192;
    generate if (!PIPELINE_ENABLE) begin : combinational_reference
        assign pcm_out = source_ready ? faded[15:0] : 16'sd0;
        assign would_clip = raw_clip;
        assign limiting = raw_limit;
    end else begin : registered_output
        reg signed [31:0] scaled_1;
        reg [8:0] fade_1, fade_2;
        reg [1:0] mode_1;
        reg ready_1, ready_2, clip_1, clip_2, clip_3, limit_1, limit_2, limit_3;
        reg signed [15:0] shaped_2, output_3;
        reg signed [31:0] abs_1, shape_1;
        wire signed [31:0] faded_2 = ($signed(shaped_2) * $signed({23'd0,fade_2})) / 32'sd256;
        always @* begin
            abs_1 = scaled_1 < 0 ? -scaled_1 : scaled_1;
            shape_1 = abs_1;
            if (PROTECTION_ENABLE && mode_1 == 1 && abs_1 > 8192)
                shape_1 = 8192 + ((abs_1 - 8192) / 4);
            if (scaled_1 < 0) shape_1 = -shape_1;
            if (shape_1 > 32767) shape_1 = 32767;
            if (shape_1 < -32768) shape_1 = -32768;
        end
        always @(posedge clk) begin
            if (!rst_n) begin
                scaled_1 <= 0; mode_1 <= 0; fade_1 <= 0; fade_2 <= 0;
                ready_1 <= 0; ready_2 <= 0; shaped_2 <= 0; output_3 <= 0;
                clip_1 <= 0; clip_2 <= 0; clip_3 <= 0;
                limit_1 <= 0; limit_2 <= 0; limit_3 <= 0;
            end else begin
                scaled_1 <= scaled;
                mode_1 <= active_mode;
                fade_1 <= SMOOTH_ENABLE ? envelope : 9'd256;
                ready_1 <= source_ready; clip_1 <= raw_clip; limit_1 <= raw_limit;
                shaped_2 <= shape_1[15:0];
                fade_2 <= fade_1; ready_2 <= ready_1;
                clip_2 <= clip_1; limit_2 <= limit_1;
                output_3 <= ready_2 ? faded_2[15:0] : 16'sd0;
                clip_3 <= clip_2; limit_3 <= limit_2;
            end
        end
        assign pcm_out = output_3;
        assign would_clip = clip_3;
        assign limiting = limit_3;
    end endgenerate
endmodule
