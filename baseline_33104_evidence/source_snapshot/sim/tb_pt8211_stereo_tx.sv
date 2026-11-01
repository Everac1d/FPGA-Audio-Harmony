`timescale 1ns/1ps

// 独立数外部 BCLK 上升/下降沿，按 PT8211 右对齐格式解码。
// 参考值来自预定测试向量，不读取发送器的锁存寄存器或输出作为参考。
module tb_pt8211_stereo_tx;
    reg clk = 0;
    always #10 clk = ~clk;
    reg rst_n = 0;
    reg [1:0] divider = 0;
    reg [5:0] bit_pos = 0;
    wire bclk = divider[1];
    wire fall_ce = (divider == 3);
    reg signed [15:0] pcm_left = 0, pcm_right = 0;
    wire HP_WS, HP_DIN, frame_ce;
    pt8211_stereo_tx dut (
        .clk(clk), .rst_n(rst_n), .fall_ce(fall_ce), .bit_pos(bit_pos),
        .pcm_left(pcm_left), .pcm_right(pcm_right),
        .HP_WS(HP_WS), .HP_DIN(HP_DIN), .frame_ce(frame_ce)
    );

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            divider <= 0;
            bit_pos <= 0;
        end else begin
            divider <= divider + 1'b1;
            if (fall_ce) bit_pos <= bit_pos + 1'b1;
        end
    end

    function [15:0] expected_left(input integer n);
        begin
            case (n % 8)
                0: expected_left = 0;
                1: expected_left = 16'h1234;
                2: expected_left = 16'h8000;
                3: expected_left = 16'h7fff;
                4: expected_left = 0;
                5: expected_left = 16'hffff;
                6: expected_left = 16'h55aa;
                7: expected_left = 0;
            endcase
        end
    endfunction
    function [15:0] expected_right(input integer n);
        begin
            case (n % 8)
                0: expected_right = 0;
                1: expected_right = 16'hfedc;
                2: expected_right = 0;
                3: expected_right = 0;
                4: expected_right = 16'h8000;
                5: expected_right = 0;
                6: expected_right = 16'haa55;
                7: expected_right = 16'h7fff;
            endcase
        end
    endfunction

    integer ext_pos = 0, frame_number = 0;
    integer decoded_frames = 0, checked_bits = 0, checked_padding = 0;
    integer frame_pulses = 0, resets = 0, stability_checks = 0;
    reg [15:0] right_shift = 0, left_shift = 0;
    reg prior_ws = 0, prior_din = 0;
    reg expected_bit;

    // 在每帧锁存边界前提供测试向量，其余时刻不断改变输入。
    // 如果发送器错误地直接读取输入或在半帧重新锁存，解码会失败。
    always @(negedge clk) begin
        if (!rst_n) begin
            pcm_left = 16'h7fff;
            pcm_right = 16'h8000;
        end else if ((divider == 3) && (ext_pos == 63)) begin
            pcm_left = expected_left(frame_number + 1);
            pcm_right = expected_right(frame_number + 1);
        end else begin
            pcm_left = 16'h9753 ^ ($time >> 2);
            pcm_right = 16'h2468 ^ ($time >> 3);
        end
    end

    // frame_ce 必须只出现在外部计数所确定的整帧边界。
    always @(posedge clk) begin
        if (rst_n) begin
            if (frame_ce !== ((divider == 3) && (ext_pos == 63)))
                $fatal(1, "frame_ce boundary mismatch ext_pos=%0d", ext_pos);
            if (frame_ce) frame_pulses = frame_pulses + 1;
            prior_ws = HP_WS;
            prior_din = HP_DIN;
            if (!fall_ce) begin
                #1;
                if (HP_WS !== prior_ws || HP_DIN !== prior_din)
                    $fatal(1, "serial outputs changed outside falling BCLK enable");
                stability_checks = stability_checks + 1;
            end
        end
    end

    always @(negedge bclk or negedge rst_n) begin
        if (!rst_n) begin
            ext_pos = 0;
            frame_number = 0;
            left_shift = 0;
            right_shift = 0;
        end else begin
            if (ext_pos == 63) begin
                ext_pos = 0;
                frame_number = frame_number + 1;
            end else ext_pos = ext_pos + 1;
        end
    end

    always @(posedge bclk) begin
        if (rst_n) begin
            #1;
            if (HP_WS !== (ext_pos >= 32))
                $fatal(1, "WS mismatch frame=%0d pos=%0d", frame_number, ext_pos);
            if ((ext_pos % 32) < 16) begin
                if (HP_DIN !== 0)
                    $fatal(1, "nonzero right-justified padding frame=%0d pos=%0d", frame_number, ext_pos);
                checked_padding = checked_padding + 1;
            end else begin
                if (ext_pos < 32) begin
                    expected_bit = (expected_right(frame_number) >> (31 - ext_pos)) & 1;
                    right_shift = {right_shift[14:0], HP_DIN};
                end else begin
                    expected_bit = (expected_left(frame_number) >> (63 - ext_pos)) & 1;
                    left_shift = {left_shift[14:0], HP_DIN};
                end
                if (HP_DIN !== expected_bit)
                    $fatal(1, "PCM mismatch frame=%0d pos=%0d got=%b expected=%b", frame_number, ext_pos, HP_DIN, expected_bit);
                checked_bits = checked_bits + 1;
            end
            if (ext_pos == 31 && right_shift !== expected_right(frame_number))
                $fatal(1, "right decode mismatch frame=%0d", frame_number);
            if (ext_pos == 63) begin
                if (left_shift !== expected_left(frame_number))
                    $fatal(1, "left decode mismatch frame=%0d", frame_number);
                decoded_frames = decoded_frames + 1;
            end
        end
    end

    task reset_midstream;
        begin
            @(negedge clk);
            #3 rst_n = 0;
            #1;
            if (HP_WS !== 0 || HP_DIN !== 0)
                $fatal(1, "asynchronous reset did not mute serial outputs");
            repeat (5) @(negedge clk);
            #2 rst_n = 1;
            resets = resets + 1;
        end
    endtask

    initial begin
        #1;
        // 建立真实的复位边沿，初始帧在第一次 frame_ce 前必须保持零。
        rst_n = 1;
        #2 rst_n = 0;
        repeat (4) @(negedge clk);
        #2 rst_n = 1;
        wait (decoded_frames >= 18);
        wait (ext_pos == 20);
        reset_midstream();
        wait (decoded_frames >= 36);
        wait (ext_pos == 51);
        reset_midstream();
        wait (decoded_frames >= 54);
        if (frame_pulses < 51 || checked_bits < 1700 || checked_padding < 1700 || resets != 2)
            $fatal(1, "insufficient coverage frames=%0d pulses=%0d bits=%0d padding=%0d resets=%0d", decoded_frames, frame_pulses, checked_bits, checked_padding, resets);
        $display("PASS PT8211_STEREO: frames=%0d payload_bits=%0d padding_bits=%0d frame_ce=%0d resets=%0d stable_checks=%0d", decoded_frames, checked_bits, checked_padding, frame_pulses, resets, stability_checks);
        $display("PASS PT8211_STEREO_COVERAGE: distinct_left_right, left_only, right_only, signed_boundaries, midframe_input_changes, reset_padding");
        $finish;
    end
    initial begin
        #1000000;
        $fatal(1, "PT8211 stereo timeout");
    end
endmodule
