// 基于22402的录放与实时候选方案双键界面，所有信号均使用clk。
// 当前操作的所有按键均释放后，才会发出命令。
// 这也允许在长按第一个键之后再加入第二个键，
// 避免误触发单键命令；组合操作会抑制两个单键命令。
// 长按组合要求消抖后的两个按键同时保持低电平达LONG_PRESS_CYCLES个时钟。
// 短按组合仅在录放模式下播放或停止；长按组合切换音源。
module audio_record_keys #(
    parameter integer DEBOUNCE_CYCLES = 1000000,
    parameter integer LONG_PRESS_CYCLES = 40000000
) (
    input wire clk,
    input wire rst_n,
    input wire key_mode_n,
    input wire key_gain_n,
    output reg record_source,
    output reg [1:0] live_mode,
    output reg [2:0] gain_index,
    output reg [1:0] algorithm_mode,
    output reg signed [4:0] pitch_semitones,
    output reg record_toggle,
    output reg play_toggle,
    output reg source_changed
);
    (* syn_preserve = 1, ASYNC_REG = "TRUE" *) reg mode_meta, mode_sync;
    (* syn_preserve = 1, ASYNC_REG = "TRUE" *) reg gain_meta, gain_sync;
    reg mode_stable, gain_stable;
    reg [31:0] mode_debounce, gain_debounce;
    always @(posedge clk) begin
        if (!rst_n) begin
            mode_meta <= 1; mode_sync <= 1; mode_stable <= 1;
            gain_meta <= 1; gain_sync <= 1; gain_stable <= 1;
            mode_debounce <= 0; gain_debounce <= 0;
        end else begin
            mode_meta <= key_mode_n; mode_sync <= mode_meta;
            gain_meta <= key_gain_n; gain_sync <= gain_meta;
            if (mode_sync == mode_stable) mode_debounce <= 0;
            else if (mode_debounce == DEBOUNCE_CYCLES - 1) begin
                mode_stable <= mode_sync; mode_debounce <= 0;
            end else mode_debounce <= mode_debounce + 1'b1;
            if (gain_sync == gain_stable) gain_debounce <= 0;
            else if (gain_debounce == DEBOUNCE_CYCLES - 1) begin
                gain_stable <= gain_sync; gain_debounce <= 0;
            end else gain_debounce <= gain_debounce + 1'b1;
        end
    end

    reg gesture_active, saw_mode, saw_gain;
    reg mode_long, gain_long, chord_long;
    reg [31:0] mode_held, gain_held, chord_held;
    reg [2:0] pitch_preset;
    wire both_released = mode_stable && gain_stable;
    wire both_pressed = !mode_stable && !gain_stable;

    always @(posedge clk) begin
        if (!rst_n) begin
            record_source <= 0; live_mode <= 0; gain_index <= 0;
            algorithm_mode <= 0; pitch_semitones <= 0; pitch_preset <= 0;
            record_toggle <= 0; play_toggle <= 0; source_changed <= 0;
            gesture_active <= 0; saw_mode <= 0; saw_gain <= 0;
            mode_long <= 0; gain_long <= 0; chord_long <= 0;
            mode_held <= 0; gain_held <= 0; chord_held <= 0;
        end else begin
            record_toggle <= 0; play_toggle <= 0; source_changed <= 0;
            if (both_released) begin
                if (gesture_active) begin
                    if (saw_mode && saw_gain) begin
                        if (chord_long) begin
                            record_source <= !record_source;
                            live_mode <= 0;
                            source_changed <= 1;
                        end else if (record_source) play_toggle <= 1;
                    end else if (saw_mode) begin
                        if (mode_long)
                            algorithm_mode <= (algorithm_mode == 2) ? 0 : algorithm_mode + 1'b1;
                        else if (record_source) record_toggle <= 1;
                        else live_mode <= (live_mode == 2) ? 0 : live_mode + 1'b1;
                    end else if (saw_gain) begin
                        if (gain_long) begin
                            pitch_preset <= (pitch_preset == 6) ? 0 : pitch_preset + 1'b1;
                            case (pitch_preset)
                                0: pitch_semitones <= 5'sd4;
                                1: pitch_semitones <= 5'sd8;
                                2: pitch_semitones <= 5'sd12;
                                3: pitch_semitones <= -5'sd4;
                                4: pitch_semitones <= -5'sd8;
                                5: pitch_semitones <= -5'sd12;
                                default: pitch_semitones <= 5'sd0;
                            endcase
                        end else begin
                            case (gain_index)
                                0: gain_index <= 2;
                                2: gain_index <= 4;
                                4: gain_index <= 5;
                                5: gain_index <= 6;
                                default: gain_index <= 0;
                            endcase
                        end
                    end
                end
                gesture_active <= 0; saw_mode <= 0; saw_gain <= 0;
                mode_long <= 0; gain_long <= 0; chord_long <= 0;
                mode_held <= 0; gain_held <= 0; chord_held <= 0;
            end else begin
                gesture_active <= 1;
                if (!mode_stable) begin
                    saw_mode <= 1;
                    if (!mode_long) begin
                        if (mode_held == LONG_PRESS_CYCLES - 1) mode_long <= 1;
                        else mode_held <= mode_held + 1'b1;
                    end
                end
                if (!gain_stable) begin
                    saw_gain <= 1;
                    if (!gain_long) begin
                        if (gain_held == LONG_PRESS_CYCLES - 1) gain_long <= 1;
                        else gain_held <= gain_held + 1'b1;
                    end
                end
                if (both_pressed && !chord_long) begin
                    if (chord_held == LONG_PRESS_CYCLES - 1) chord_long <= 1;
                    else chord_held <= chord_held + 1'b1;
                end else if (!both_pressed) chord_held <= 0;
            end
        end
    end
endmodule
