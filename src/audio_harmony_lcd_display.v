// 只读LCD前端，不连接音频使能、复位或DDR端口。
module audio_harmony_lcd_display #(
    parameter integer BACKLIGHT_ENABLE=0,
    parameter integer TEST_PATTERN=0,
    parameter integer FINE_GAIN=0,
    parameter integer MAX_SAMPLES=14648438,RING_TUNE_ENABLE=0
)(
    input wire clk,rst_n,source,test_pattern_en,
    input wire [1:0] active_mode,algorithm_mode,
    input wire signed [4:0] pitch,pitch_second,
    input wire pitch_voice,
    input wire [4:0] gain_index,
    input wire [3:0] rec_state,
    input wire record_valid,record_full,storage_fault,ddr_ready,
    input wire [15:0] ddr_diag,
    input wire [31:0] record_progress,record_samples,play_samples,
    input wire ring_tuning,
    input wire signed [12:0] ring_calibration_margin,
    input wire [15:0] ring_noise_floor,ring_mean_level,
    output wire LCD_CLK,LCD_HSYNC,LCD_VSYNC,LCD_DE,LCD_BL,
    output wire [5:0] LCD_R,LCD_G,LCD_B
);
    wire [9:0] x;wire [8:0] y;wire frame_start;
    wire s_source,s_valid,s_full,s_fault,s_ddr;
    wire [1:0] s_mode,s_algorithm;
    wire signed [4:0] s_pitch,s_pitch_second;wire s_pitch_voice;
    wire [4:0] s_gain;wire [3:0] s_state;wire [15:0] s_diag;
    wire [15:0] rec_centis,total_centis,play_centis;
    wire s_ring_tuning;wire signed [12:0] s_ring_margin;wire [15:0] s_ring_floor,s_ring_mean;wire [8:0] progress_pixels;
    wire [17:0] rgb;
    lcd_harmony_status_snapshot #(.MAX_SAMPLES(MAX_SAMPLES)) snapshot(.clk(clk),.rst_n(rst_n),.frame_start(frame_start),
        .source(source),.active_mode(active_mode),.algorithm_mode(algorithm_mode),
        .pitch(pitch),.pitch_second(pitch_second),.pitch_voice(pitch_voice),.gain_index(gain_index),.rec_state(rec_state),
        .record_valid(record_valid),.record_full(record_full),.storage_fault(storage_fault),
        .ddr_ready(ddr_ready),.ddr_diag(ddr_diag),.record_progress(record_progress),
        .record_samples(record_samples),.play_samples(play_samples),
        .ring_tuning(ring_tuning),.ring_calibration_margin(ring_calibration_margin),.ring_noise_floor(ring_noise_floor),.ring_mean_level(ring_mean_level),
        .source_o(s_source),.active_mode_o(s_mode),.algorithm_mode_o(s_algorithm),
        .pitch_o(s_pitch),.pitch_second_o(s_pitch_second),.pitch_voice_o(s_pitch_voice),.gain_index_o(s_gain),.rec_state_o(s_state),.record_valid_o(s_valid),
        .record_full_o(s_full),.storage_fault_o(s_fault),.ddr_ready_o(s_ddr),.ddr_diag_o(s_diag),
        .rec_centis(rec_centis),.total_centis(total_centis),.play_centis(play_centis),
        .progress_pixels(progress_pixels),
        .ring_tuning_o(s_ring_tuning),.ring_calibration_margin_o(s_ring_margin),.ring_noise_floor_o(s_ring_floor),.ring_mean_level_o(s_ring_mean));
    lcd_harmony_dashboard #(.FINE_GAIN(FINE_GAIN),.MAX_SAMPLES(MAX_SAMPLES),.RING_TUNE_ENABLE(RING_TUNE_ENABLE)) dashboard(.clk(clk),.x(x),.y(y),.source(s_source),.active_mode(s_mode),
        .algorithm_mode(s_algorithm),.pitch(s_pitch),.pitch_second(s_pitch_second),.pitch_voice(s_pitch_voice),.gain_index(s_gain),.rec_state(s_state),
        .record_valid(s_valid),.record_full(s_full),.storage_fault(s_fault),.ddr_ready(s_ddr),
        .ddr_diag(s_diag),.rec_centis(rec_centis),.total_centis(total_centis),
        .play_centis(play_centis),.progress_pixels(progress_pixels),
        .ring_tuning(s_ring_tuning),.ring_calibration_margin(s_ring_margin),.ring_noise_floor(s_ring_floor),.ring_mean_level(s_ring_mean),.rgb(rgb));
    lcd_rgb_timing #(.BACKLIGHT_ENABLE(BACKLIGHT_ENABLE),.TEST_PATTERN(TEST_PATTERN)) timing(
        .clk(clk),.rst_n(rst_n),.test_pattern_en(test_pattern_en),
        .pixel_rgb(rgb),.x(x),.y(y),.frame_start(frame_start),
        .LCD_CLK(LCD_CLK),.LCD_HSYNC(LCD_HSYNC),.LCD_VSYNC(LCD_VSYNC),.LCD_DE(LCD_DE),
        .LCD_BL(LCD_BL),.LCD_R(LCD_R),.LCD_G(LCD_G),.LCD_B(LCD_B));
endmodule
