// Display-only 512-sample mean absolute PCM amplitude; never modifies audio.
// Keep quiet for two seconds after reset. The first 128 complete windows
// (~1.34 s at 48.828125 kHz) measure baseline, with the display held dark.
// Gate=max(NOISE_FLOOR,2*baseline+CALIBRATION_MARGIN), clamped to 65535.
// The default margin 32 preserves legacy instances. The external-panel top
// selects 24 for a small display-only sensitivity change; floor stays 64.
// Broad, piecewise-linear excess-amplitude -> brightness anchors:
// 0:0,128:8,512:32,1024:56,2048:96,4096:144,8192:200,16384:255.
// Values above 16384 saturate. Interpolation uses constant shifts/products.
// Attack takes one 10.49 ms window; release removes max(level/8,8) per
// window, clamped to target. Full brightness decays to dark within 0.26 s.
// -32768 is handled as unsigned magnitude 32768. Run a separate meter for
// each candidate audio source so switching source does not mix calibrations.
// Window accumulation/calibration and debug mean retain their sample timing.
// Brightness alone is pipelined: a window completed at edge N captures its
// mean/floor/calibration snapshot; N+1 computes excess, N+2 maps the curve,
// and N+3 updates level. This 3-clk delay (60 ns at 50 MHz) breaks the former
// PCM -> absolute value -> sum -> floor -> curve -> release timing path.
// Pipeline slots advance on clk, independently of pcm_valid; consecutive valid
// samples and back-to-back windows are supported, and reset flushes all slots.
module audio_level_meter #(
    parameter integer WINDOW_LOG2 = 9,
    parameter integer NOISE_FLOOR = 64,
    parameter integer CALIBRATION_LOG2 = 7,
    parameter integer CALIBRATION_MARGIN = 32
) (
    input wire clk,
    input wire rst_n,
    input wire signed [15:0] pcm,
    input wire pcm_valid,
    output reg [7:0] level,
    output reg [15:0] noise_floor,
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
    wire [16:0] measured_gate = ({1'b0,baseline} << 1) + CALIBRATION_MARGIN;
    wire [15:0] bounded_gate = (measured_gate > 17'd65535) ? 16'hffff :
                               measured_gate[15:0];
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
            noise_floor <= NOISE_FLOOR;
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
                            noise_floor <= (bounded_gate < NOISE_FLOOR) ?
                                            NOISE_FLOOR : bounded_gate;
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
