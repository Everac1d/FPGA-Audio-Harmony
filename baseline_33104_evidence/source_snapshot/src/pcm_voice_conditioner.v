// Voice-band monitor conditioner; all logic uses clk (50 MHz in this project).
// This reduces DC, out-of-band hiss and quiet background noise. It does not
// identify acoustic feedback, repair corrupt PCM, or perform echo cancellation.
//
// Each valid PCM16 sample advances these equations exactly once, irrespective
// of the number of idle clk cycles between samples. State is signed Q8:
//   d[n] = d[n-1] + floor(3 * (256*x[n] - d[n-1]) / 256)
//   h[n] = 256*x[n] - d[n]
//   p[n] = p[n-1] + floor((h[n] - p[n-1]) / 2)
//   q[n] = q[n-1] + floor((p[n] - q[n-1]) / 2)
// Arithmetic right shifts implement floor, including for negative operands.
// HP pole 253/256: approximately 91.6 Hz at 48828.125 samples/s. Two LP
// poles 1/2 have a combined -3 dB frequency of approximately 3567 Hz.
// Fractional state avoids repeated PCM16 truncation and DC-estimator stalling.
//
// Gate detector is the peak of abs(q[n]) and its previous value decayed by
// ceil(envelope/256). Opening requires >= OPEN; once open, > CLOSE reloads a
// sample-counted hold. Below CLOSE for HOLD_SAMPLES then starts the release.
// This peak detector, hysteresis and hold bridge ordinary waveform crossings.
// Q8 gain rises by 4 per sample (64-sample attack), falls by 1 (256 release),
// and is bounded 0..256. Thresholds are PCM16 units, not Q8 units.
//
// Pipeline: HP -> LP1 -> LP2 -> gate -> output. A sample accepted at rising
// edge N produces out_valid/pcm_out immediately after edge N+4. Consecutive
// in_valid cycles are supported. Invalid slots advance through the pipeline;
// each stage's sample state holds on its invalid slots. pcm_out holds whenever
// out_valid is low. Synchronous active-low reset flushes every stage and all
// scalar history, including the gate. There is no RAM and no generated clock.
// Final Q16 product rounds to nearest PCM integer, ties away from zero, then
// saturates to [-32768,32767]. Wide signed product prevents rail wraparound.
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

    // Supported parameters: 0 <= CLOSE < OPEN <= 32768; HOLD >= 1.
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

    // Each filter stage contains a bounded number of add/subtract operations.
    // Input is explicitly sign extended before shifting to Q8.
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

    // 32-bit Q8 * positive 10-bit signed Q8 -> 42-bit signed Q16.
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
