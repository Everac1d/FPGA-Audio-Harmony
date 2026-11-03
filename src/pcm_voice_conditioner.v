// 语音频段监听调理器；所有逻辑均使用 clk（本工程为 50 MHz）。
// 用于减小直流分量、带外嘶声与微弱背景噪声；不负责
// 识别声学反馈、修复损坏的 PCM 数据或消除回声。
//
// 每个有效 PCM16 样本恰好推进下列方程一次，
// 与样本间空闲时钟周期数无关。状态采用有符号 Q8 格式：
//   状态递推公式：d[n] = d[n-1] + floor(3 * (256*x[n] - d[n-1]) / 256)
//   h[n] = 256*x[n] - d[n]
//   状态递推公式：p[n] = p[n-1] + floor((h[n] - p[n-1]) / 2)
//   状态递推公式：q[n] = q[n-1] + floor((p[n] - q[n-1]) / 2)
// 使用算术右移实现向下取整，负数操作数同样如此。
// 高通极点为 253/256：采样率为 48828.125 样本／秒时约对应 91.6 Hz。两个低通
// 极点均为 1/2，级联后的 −3 dB 频率约为 3567 Hz。
// 小数状态可避免反复截断为 PCM16，以及直流估计器停滞。
//
// 门限检测值取 abs(q[n]) 与前次检测值衰减后的较大值；衰减量为
// ceil(envelope/256)。达到 OPEN 时开启；开启后若高于 CLOSE，则重新加载
// 按样本计数的保持期。低于 CLOSE 达 HOLD_SAMPLES 个样本后开始释放。
// 峰值检测、滞回和保持机制用于跨越普通波形的门限交越。
// Q8 增益每个样本上升 4（64 个样本完成起音）、下降 1（256 个样本完成释放），
// 范围限制为 0..256。门限以 PCM16 为单位，而非 Q8 单位。
//
// 流水线：高通 → 低通一级 → 低通二级 → 门限控制 → 输出。若样本在上升沿
// N 被接收，则在上升沿 N+4 后立即产生 out_valid/pcm_out。支持连续
// 多个周期的 in_valid。无效时隙仍沿流水线推进；
// 各级遇到无效时隙时保持其样本状态。当 out_valid 为低时，
// pcm_out 保持不变。同步低有效复位清空所有流水级及全部
// 标量历史状态，包括门限控制状态。不使用 RAM 或派生时钟。
// 最终 Q16 乘积舍入至最近的 PCM 整数，恰好居中时向远离零的方向舍入，随后
// 饱和至 [-32768,32767]；使用宽位有符号乘积防止满幅回绕。
module pcm_voice_conditioner #(
    parameter integer GATE_ENABLE = 1,
    parameter integer GATE_OPEN_THRESHOLD = 128,
    parameter integer GATE_CLOSE_THRESHOLD = 64,
    parameter integer GATE_HOLD_SAMPLES = 4096
) (
    input wire clk,
    input wire rst_n,
    input wire in_valid,
    input wire signed [15:0] pcm_in,
    output reg out_valid,
    output reg signed [15:0] pcm_out
);
    function integer count_bits;
        input integer value;
        integer v;
        begin
            v = value - 1;
            count_bits = 0;
            while (v > 0) begin
                count_bits = count_bits + 1;
                v = v >> 1;
            end
            if (count_bits < 1) count_bits = 1;
        end
    endfunction

    // 支持的参数范围：0 <= CLOSE < OPEN <= 32768；HOLD >= 1。
    localparam integer HOLD_BITS = count_bits(GATE_HOLD_SAMPLES + 1);
    localparam [31:0] OPEN_Q8 = GATE_OPEN_THRESHOLD * 256;
    localparam [31:0] CLOSE_Q8 = GATE_CLOSE_THRESHOLD * 256;

    reg hp_valid, lp1_valid, lp2_valid, scale_valid;
    reg signed [31:0] dc_q8, hp_q8, lp1_q8, lp2_q8;
    reg signed [31:0] scale_sample_q8;
    reg [8:0] scale_gain_q8;
    reg [31:0] envelope_q8;
    reg gate_open;
    reg [HOLD_BITS-1:0] hold_count;
    reg [8:0] gain_q8;

    // 每个滤波级仅包含有限次数的加减运算。
    // 输入先显式进行符号扩展，再移位转换为 Q8。
    wire signed [31:0] input_q8 = $signed({{16{pcm_in[15]}}, pcm_in}) <<< 8;
    wire signed [31:0] dc_error = input_q8 - dc_q8;
    wire signed [31:0] dc_step = (dc_error + (dc_error <<< 1)) >>> 8;
    wire signed [31:0] dc_next = dc_q8 + dc_step;
    wire signed [31:0] hp_next = input_q8 - dc_next;
    wire signed [31:0] lp1_next = lp1_q8 + ((hp_q8 - lp1_q8) >>> 1);
    wire signed [31:0] lp2_next = lp2_q8 + ((lp1_q8 - lp2_q8) >>> 1);

    wire [31:0] magnitude_q8 = lp2_q8[31] ? -lp2_q8 : lp2_q8;
    wire [31:0] envelope_decay = (envelope_q8 + 32'd255) >> 8;
    wire [31:0] envelope_fall = envelope_q8 - envelope_decay;
    wire [31:0] envelope_next = (magnitude_q8 >= envelope_fall) ?
                                magnitude_q8 : envelope_fall;
    reg gate_next;
    reg [HOLD_BITS-1:0] hold_next;
    reg [8:0] gain_next;
    always @* begin
        gate_next = gate_open;
        hold_next = hold_count;
        if (!gate_open) begin
            if (envelope_next >= OPEN_Q8) begin
                gate_next = 1'b1;
                hold_next = GATE_HOLD_SAMPLES;
            end
        end else if (envelope_next > CLOSE_Q8) begin
            hold_next = GATE_HOLD_SAMPLES;
        end else if (hold_count > 1) begin
            hold_next = hold_count - 1'b1;
        end else begin
            hold_next = {HOLD_BITS{1'b0}};
            gate_next = 1'b0;
        end

        gain_next = gain_q8;
        if (gate_next) begin
            if (gain_q8 <= 9'd252) gain_next = gain_q8 + 9'd4;
            else gain_next = 9'd256;
        end else if (gain_q8 != 0) begin
            gain_next = gain_q8 - 1'b1;
        end
    end

    // 32 位 Q8 × 正值的 10 位有符号 Q8 → 42 位有符号 Q16。
    wire signed [41:0] product_q16 = scale_sample_q8 * $signed({1'b0, scale_gain_q8});
    wire signed [41:0] rounded_pcm = product_q16[41] ?
        -(((-product_q16) + 42'sd32768) >>> 16) :
          ((product_q16 + 42'sd32768) >>> 16);

    always @(posedge clk) begin
        if (!rst_n) begin
            hp_valid <= 1'b0;
            lp1_valid <= 1'b0;
            lp2_valid <= 1'b0;
            scale_valid <= 1'b0;
            out_valid <= 1'b0;
            pcm_out <= 16'sd0;
            dc_q8 <= 32'sd0;
            hp_q8 <= 32'sd0;
            lp1_q8 <= 32'sd0;
            lp2_q8 <= 32'sd0;
            scale_sample_q8 <= 32'sd0;
            scale_gain_q8 <= 9'd0;
            envelope_q8 <= 32'd0;
            gate_open <= 1'b0;
            hold_count <= {HOLD_BITS{1'b0}};
            gain_q8 <= 9'd0;
        end else begin
            hp_valid <= in_valid;
            lp1_valid <= hp_valid;
            lp2_valid <= lp1_valid;
            scale_valid <= lp2_valid;
            out_valid <= scale_valid;
            if (in_valid) begin
                dc_q8 <= dc_next;
                hp_q8 <= hp_next;
            end
            if (hp_valid) lp1_q8 <= lp1_next;
            if (lp1_valid) lp2_q8 <= lp2_next;
            if (lp2_valid) begin
                envelope_q8 <= envelope_next;
                gate_open <= gate_next;
                hold_count <= hold_next;
                gain_q8 <= gain_next;
                scale_sample_q8 <= lp2_q8;
                scale_gain_q8 <= GATE_ENABLE ? gain_next : 9'd256;
            end
            if (scale_valid) begin
                if (rounded_pcm > 42'sd32767) pcm_out <= 16'sd32767;
                else if (rounded_pcm < -42'sd32768) pcm_out <= -16'sd32768;
                else pcm_out <= rounded_pcm[15:0];
            end
        end
    end
endmodule
