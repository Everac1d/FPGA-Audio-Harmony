`timescale 1ns/1ps
module tb_pcm_voice_conditioner;
    localparam real FS = 48828.125;
    localparam real PI = 3.14159265358979323846;
    reg clk = 0;
    always #10 clk = ~clk;
    reg rst_n = 0, in_valid = 0;
    reg signed [15:0] pcm_in = 0;
    wire out_valid, bypass_valid;
    wire signed [15:0] pcm_out, bypass_out;
    pcm_voice_conditioner dut (.*);
    pcm_voice_conditioner #(.GATE_ENABLE(0)) bypass (
        .clk(clk), .rst_n(rst_n), .in_valid(in_valid), .pcm_in(pcm_in),
        .out_valid(bypass_valid), .pcm_out(bypass_out));

    // Independent identical streams: one contiguous, one with arbitrary gaps.
    reg parity_reset_n = 0, a_valid = 0, b_valid = 0;
    reg signed [15:0] a_in = 0, b_in = 0;
    wire a_out_valid, b_out_valid;
    wire signed [15:0] a_out, b_out;
    pcm_voice_conditioner parity_a (.clk(clk), .rst_n(parity_reset_n),
        .in_valid(a_valid), .pcm_in(a_in), .out_valid(a_out_valid), .pcm_out(a_out));
    pcm_voice_conditioner parity_b (.clk(clk), .rst_n(parity_reset_n),
        .in_valid(b_valid), .pcm_in(b_in), .out_valid(b_out_valid), .pcm_out(b_out));
    integer a_result[0:511], b_result[0:511], a_count = 0, b_count = 0;
    integer recorded[0:16383], record_count = 0;
    reg record_enable = 0;
    integer measured_count = 0, measure_warm = 0, measure_length = 0;
    real measured_power = 0.0;
    reg measure_enable = 0;
    reg [4:0] expected_valid = 0;
    reg signed [15:0] last_out = 0, last_bypass = 0;
    integer checked_cycles = 0;
    always @(posedge clk) begin
        if (!rst_n) expected_valid = 0;
        else expected_valid = {expected_valid[3:0], in_valid};
        #1;
        checked_cycles = checked_cycles + 1;
        if (out_valid !== expected_valid[4] || bypass_valid !== expected_valid[4])
            $fatal(1, "valid latency/count mismatch at cycle %0d", checked_cycles);
        if ((^{out_valid, pcm_out, bypass_valid, bypass_out}) === 1'bx)
            $fatal(1, "unknown output at cycle %0d: %b %h %b %h", checked_cycles,
                out_valid, pcm_out, bypass_valid, bypass_out);
        if (rst_n && !out_valid && (pcm_out !== last_out || bypass_out !== last_bypass))
            $fatal(1, "output changed on invalid slot");
        last_out = pcm_out;
        last_bypass = bypass_out;
        if (record_enable && bypass_valid) begin
            recorded[record_count] = bypass_out;
            record_count = record_count + 1;
        end
        if (measure_enable && bypass_valid) begin
            if (measured_count >= measure_warm && measured_count < measure_warm + measure_length)
                measured_power = measured_power + real'(bypass_out) * real'(bypass_out);
            measured_count = measured_count + 1;
        end
        if (parity_reset_n && a_out_valid) begin
            if (a_count >= 512) $fatal(1, "extra contiguous output");
            a_result[a_count] = a_out;
            a_count = a_count + 1;
        end
        if (parity_reset_n && b_out_valid) begin
            if (b_count >= 512) $fatal(1, "extra gapped output");
            b_result[b_count] = b_out;
            b_count = b_count + 1;
        end
    end

    task tick(input integer sample, input bit valid);
        @(negedge clk);
        pcm_in = sample;
        in_valid = valid;
        @(posedge clk); #2;
    endtask
    task reset_main;
        @(negedge clk); rst_n = 0; in_valid = 0;
        repeat (2) begin @(posedge clk); #2; end
        if (pcm_out !== 0 || bypass_out !== 0 || dut.gain_q8 !== 0 ||
            dut.envelope_q8 !== 0 || dut.hold_count !== 0 || dut.gate_open !== 0 ||
            dut.dc_q8 !== 0 || dut.lp1_q8 !== 0 || dut.lp2_q8 !== 0)
            $fatal(1, "reset did not clear scalar history");
        @(negedge clk); rst_n = 1;
    endtask
    task flush;
        repeat (7) tick(0, 0);
    endtask
    task tone(input real frequency);
        integer n, s;
        real omega, pole, hp, lp, expected, measured, measured_db, expected_db;
        reset_main();
        measure_warm = 4096;
        measure_length = 32768;
        measured_count = 0;
        measured_power = 0;
        measure_enable = 1;
        for (n = 0; n < measure_warm + measure_length; n = n + 1) begin
            s = $rtoi(12000.0 * $sin(2.0 * PI * frequency * n / FS));
            tick(s, 1);
        end
        flush();
        measure_enable = 0;
        if (measured_count != measure_warm + measure_length)
            $fatal(1, "tone output count %0d", measured_count);
        omega = 2.0 * PI * frequency / FS;
        pole = 253.0 / 256.0;
        // Independent z-domain transfer function; not a copy of RTL recurrence.
        hp = pole * $sqrt((2.0 - 2.0 * $cos(omega)) /
                         (1.0 + pole*pole - 2.0*pole*$cos(omega)));
        lp = 0.25 / (1.25 - $cos(omega));
        expected = hp * lp;
        measured = $sqrt(measured_power / measure_length) / (12000.0 / $sqrt(2.0));
        measured_db = 20.0 * $ln(measured) / $ln(10.0);
        expected_db = 20.0 * $ln(expected) / $ln(10.0);
        $display("RESPONSE Hz=%0.1f measured=%0.4f dB analytic=%0.4f dB", frequency, measured_db, expected_db);
        if (measured_db > expected_db + 0.03 || measured_db < expected_db - 0.03)
            $fatal(1, "frequency response differs from independent transfer function");
    endtask

    integer n, i, j, s, old_gain, new_gain, release_steps, open_edges;
    integer negative_saturations, positive_saturations;
    initial begin
        reset_main();
        // Explicit mixed valids and reset while all pipeline stages are busy.
        for (n = 0; n < 35; n = n + 1) tick((n * 1901) - 30000, (n % 5) != 1);
        reset_main();
        repeat (16) tick(0, 1);
        flush();
        if (pcm_out !== 0 || bypass_out !== 0) $fatal(1, "stale audio after reset");
        $display("PASS reset midstream, latency, hold-on-invalid and no X");

        // A finite input sequence must be identical with and without valid gaps.
        @(negedge clk); parity_reset_n = 1;
        i = 0; j = 0;
        for (n = 0; n < 4096; n = n + 1) begin
            @(negedge clk);
            a_valid = i < 512;
            if (a_valid) begin
                a_in = ((i * 7919 + 37) % 65536) - 32768;
                i = i + 1;
            end
            b_valid = j < 512 && ((n % 7) == 0 || (n % 7) == 1);
            if (b_valid) begin
                b_in = ((j * 7919 + 37) % 65536) - 32768;
                j = j + 1;
            end
            @(posedge clk); #2;
        end
        if (a_count != 512 || b_count != 512) $fatal(1, "parity stream lost samples");
        for (n = 0; n < 512; n = n + 1)
            if (a_result[n] !== b_result[n]) $fatal(1, "gap changed sample %0d", n);
        $display("PASS 512 consecutive versus irregular valid-gap samples: exact parity");

        reset_main();
        for (n = 0; n < 4000; n = n + 1) tick(20000, 1);
        flush();
        if (bypass_out < -2 || bypass_out > 2) $fatal(1, "positive DC not rejected");
        $display("DC +20000 final=%0d PCM", bypass_out);
        for (n = 0; n < 4000; n = n + 1) tick(-30000, 1);
        flush();
        if (bypass_out < -2 || bypass_out > 2) $fatal(1, "negative DC not rejected");
        $display("DC -30000 final=%0d PCM", bypass_out);
        tone(100.0); tone(300.0); tone(1000.0); tone(3000.0);
        tone(6000.0); tone(10000.0); tone(18000.0);

        reset_main();
        for (n = 0; n < 4096; n = n + 1) begin
            tick($rtoi(40.0 * $sin(2.0*PI*1000.0*n/FS)), 1);
            if (pcm_out !== 0 || dut.gate_open !== 0 || dut.gain_q8 !== 0)
                $fatal(1, "subthreshold noise opened gate");
        end
        $display("PASS subthreshold 40-PCM sine remains muted");
        reset_main();
        old_gain = 0; open_edges = 0;
        for (n = 0; n < 24000; n = n + 1) begin
            tick($rtoi(300.0 * $sin(2.0*PI*100.0*n/FS)), 1);
            new_gain = dut.gain_q8;
            if (new_gain > old_gain) begin
                if (new_gain - old_gain != 4) $fatal(1, "attack step not 4/256");
                open_edges = open_edges + 1;
            end
            old_gain = new_gain;
            if (n > 1000 && (dut.gate_open !== 1 || dut.gain_q8 != 256))
                $fatal(1, "gate chatters across low-frequency zero crossings");
        end
        if (open_edges != 64) $fatal(1, "attack length is not 64 samples");
        old_gain = dut.gain_q8; release_steps = 0;
        for (n = 0; n < 7000; n = n + 1) begin
            tick(0, 1);
            new_gain = dut.gain_q8;
            if (n < 4090 && new_gain != 256) $fatal(1, "hold ended too early");
            if (new_gain < old_gain) begin
                if (old_gain - new_gain != 1) $fatal(1, "release step not 1/256");
                release_steps = release_steps + 1;
            end
            old_gain = new_gain;
            if (n > 6500 && pcm_out !== 0) $fatal(1, "silence tail did not settle to zero");
        end
        if (release_steps != 256 || dut.gate_open !== 0 || dut.gain_q8 !== 0)
            $fatal(1, "release failed to return to silence");
        $display("PASS 64-sample attack, 100-Hz nonchatter, >=4096 hold, 256-sample release");

        reset_main();
        record_count = 0; record_enable = 1;
        repeat (1200) tick(32767, 1);
        repeat (1200) tick(-32768, 1);
        repeat (128) tick(32767, 1);
        flush(); record_enable = 0;
        if (record_count != 2528) $fatal(1, "rail test sample count");
        negative_saturations = 0; positive_saturations = 0;
        for (n = 0; n < 64; n = n + 1) begin
            if (recorded[1200+n] > 0) $fatal(1, "negative rail transition wrapped positive");
            if (recorded[2400+n] < 0) $fatal(1, "positive rail transition wrapped negative");
            if (recorded[1200+n] == -32768) negative_saturations = negative_saturations + 1;
            if (recorded[2400+n] == 32767) positive_saturations = positive_saturations + 1;
        end
        if (negative_saturations == 0 || positive_saturations == 0)
            $fatal(1, "signed saturation was not exercised");
        reset_main();
        for (n = 0; n < 8192; n = n + 1) begin
            tick((n % 2) ? -32768 : 32767, 1);
            if (n > 100 && (bypass_out < -5000 || bypass_out > 5000))
                $fatal(1, "alternating rail rejection failed");
        end
        flush();
        $display("PASS signed rails, both saturation polarities, alternating full-scale input");
        $display("ALL pcm_voice_conditioner TESTS PASSED (%0d clock cycles)", checked_cycles);
        $finish;
    end
endmodule
