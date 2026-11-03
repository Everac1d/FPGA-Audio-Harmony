// 新增的显示专用电平计；有符号运行时余量不影响音频PCM。
// 仅用于显示的512样本PCM幅度绝对值均值，绝不修改音频。
// 复位后保持安静两秒；最初128个完整窗口
// 在48.828125kHz下约为1.34秒，用于测量基线，期间保持灯环熄灭。
// 门限=max(NOISE_FLOOR,2*baseline+CALIBRATION_MARGIN)，上限为65535。
// 默认余量24供独立模块使用，集成配置可通过参数覆盖。
// 可选的有符号运行时调整保持亮度曲线不变。
// 超出门限的幅度到亮度采用较宽范围的分段线性锚点：
// 幅度:亮度为0:0、128:8、512:32、1024:56、2048:96、4096:144、8192:200、16384:255。
// 超过16384时饱和；插值使用常数移位与乘积。
// 上升响应占一个10.49毫秒窗口；衰减时每个窗口减少max(level/8,8)，
// 并限制到目标值；满亮度在0.26秒内衰减至熄灭。
// -32768按无符号幅度32768处理；每个候选音源
// 使用独立电平计，防止切换音源时混用校准结果。
// 窗口累加、校准及调试均值保留原采样时序。
// 仅对亮度计算进行流水处理：窗口在边沿N完成并锁存
// 均值、下限及校准快照；N+1计算超出量，N+2映射曲线，
// N+3更新亮度；此3时钟周期延迟（50MHz下为60纳秒）截断原有
// PCM -> 绝对值 -> 求和 -> 下限 -> 曲线 -> 衰减时序路径。
// 流水线各级随clk推进，独立于pcm_valid；支持连续有效
// 样本及连续窗口，复位会清空所有流水级。
module audio_ring_cal_meter #(
    parameter integer WINDOW_LOG2 = 9,
    parameter integer NOISE_FLOOR = 64,
    parameter integer CALIBRATION_LOG2 = 7,
    parameter integer CALIBRATION_MARGIN = 24,
    parameter integer LIVE_CALIBRATION = 0
) (
    input wire clk,
    input wire rst_n,
    input wire signed [15:0] pcm,
    input wire pcm_valid,
    input wire signed [12:0] calibration_margin,
    output reg [7:0] level,
    output wire [15:0] noise_floor,
    output reg [15:0] mean_level
);
    localparam integer COUNT_WIDTH = (WINDOW_LOG2 < 1) ? 1 : WINDOW_LOG2;
    localparam integer ACC_WIDTH = 16 + WINDOW_LOG2;
    localparam integer WINDOW_SAMPLES = (1 << WINDOW_LOG2);
    localparam integer CAL_COUNT_WIDTH = (CALIBRATION_LOG2 < 1) ? 1 : CALIBRATION_LOG2;
    localparam integer CAL_ACC_WIDTH = 16 + CALIBRATION_LOG2;
    localparam integer CALIBRATION_WINDOWS = (1 << CALIBRATION_LOG2);
    reg [COUNT_WIDTH-1:0] sample_count;
    reg [ACC_WIDTH-1:0] magnitude_sum;
    reg [CAL_COUNT_WIDTH-1:0] calibration_count;
    reg [CAL_ACC_WIDTH-1:0] baseline_sum;
    reg calibrated;
    wire [15:0] magnitude = pcm[15] ? (~pcm + 16'd1) : pcm;
    wire [ACC_WIDTH-1:0] next_sum = magnitude_sum + magnitude;
    wire [15:0] mean_abs = next_sum[ACC_WIDTH-1:WINDOW_LOG2];
    wire [CAL_ACC_WIDTH-1:0] next_baseline_sum = baseline_sum + mean_abs;
    wire [15:0] baseline = next_baseline_sum[CAL_ACC_WIDTH-1:CALIBRATION_LOG2];
    reg [15:0] calibrated_baseline;
    wire signed [18:0] margin = (LIVE_CALIBRATION!=0) ?
        {{6{calibration_margin[12]}},calibration_margin} : CALIBRATION_MARGIN;
    wire signed [18:0] measured_gate = $signed({2'b00,calibrated_baseline,1'b0})+margin;
    wire [15:0] bounded_gate = measured_gate < NOISE_FLOOR ? NOISE_FLOOR :
        (measured_gate > 19'sd65535 ? 16'hffff : measured_gate[15:0]);
    assign noise_floor=calibrated ? bounded_gate : NOISE_FLOOR;
    reg window_valid, window_calibrated;
    reg [15:0] window_floor;
    reg excess_valid, excess_calibrated;
    reg [15:0] excess;
    reg target_valid, target_calibrated;
    reg [7:0] target;
    wire [16:0] above_floor = {1'b0,mean_level} - {1'b0,window_floor};
    function [7:0] amplitude_curve;
        input [15:0] amplitude;
        reg [23:0] product;
        begin
            if (amplitude < 16'd512) amplitude_curve = amplitude >> 4;
            else if (amplitude < 16'd1024) begin
                product = (amplitude-16'd512) * 24'd3;
                amplitude_curve = 8'd32 + (product >> 6);
            end else if (amplitude < 16'd2048) begin
                product = (amplitude-16'd1024) * 24'd5;
                amplitude_curve = 8'd56 + (product >> 7);
            end else if (amplitude < 16'd4096) begin
                product = (amplitude-16'd2048) * 24'd3;
                amplitude_curve = 8'd96 + (product >> 7);
            end else if (amplitude < 16'd8192) begin
                product = (amplitude-16'd4096) * 24'd7;
                amplitude_curve = 8'd144 + (product >> 9);
            end else if (amplitude < 16'd16384) begin
                product = (amplitude-16'd8192) * 24'd55;
                amplitude_curve = 8'd200 + (product >> 13);
            end else amplitude_curve = 8'd255;
        end
    endfunction
    wire [7:0] release_step = (level[7:3] < 5'd8) ? 8'd8 :
                              {3'd0,level[7:3]};
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sample_count <= {COUNT_WIDTH{1'b0}};
            magnitude_sum <= {ACC_WIDTH{1'b0}};
            level <= 8'd0;
            calibration_count <= {CAL_COUNT_WIDTH{1'b0}};
            baseline_sum <= {CAL_ACC_WIDTH{1'b0}};
            calibrated <= 1'b0;
            calibrated_baseline <= 16'd0;
            mean_level <= 16'd0;
            window_valid <= 1'b0;
            window_calibrated <= 1'b0;
            window_floor <= NOISE_FLOOR;
            excess_valid <= 1'b0;
            excess_calibrated <= 1'b0;
            excess <= 16'd0;
            target_valid <= 1'b0;
            target_calibrated <= 1'b0;
            target <= 8'd0;
        end else begin
            window_valid <= pcm_valid && (sample_count == WINDOW_SAMPLES-1);
            excess_valid <= window_valid;
            target_valid <= excess_valid;
            if (window_valid) begin
                excess <= (mean_level <= window_floor) ? 16'd0 : above_floor[15:0];
                excess_calibrated <= window_calibrated;
            end
            if (excess_valid) begin
                target <= amplitude_curve(excess);
                target_calibrated <= excess_calibrated;
            end
            if (target_valid) begin
                if (!target_calibrated) level <= 8'd0;
                else if (target >= level) level <= target;
                else if ((level-target) > release_step)
                    level <= level-release_step;
                else level <= target;
            end
            if (pcm_valid) begin
                if (sample_count == WINDOW_SAMPLES-1) begin
                    sample_count <= {COUNT_WIDTH{1'b0}};
                    magnitude_sum <= {ACC_WIDTH{1'b0}};
                    mean_level <= mean_abs;
                    window_floor <= noise_floor;
                    window_calibrated <= calibrated;
                    if (!calibrated) begin
                        baseline_sum <= next_baseline_sum;
                        if (calibration_count == CALIBRATION_WINDOWS-1) begin
                            calibrated <= 1'b1;
                            calibrated_baseline <= baseline;
                        end else calibration_count <= calibration_count + 1'b1;
                    end
                end else begin
                    sample_count <= sample_count + 1'b1;
                    magnitude_sum <= next_sum;
                end
            end
        end
    end
endmodule
