// 只读LCD前端，不连接音频使能、复位或DDR端口。
module audio_lcd_display #(
    parameter integer BACKLIGHT_ENABLE=0,
    parameter integer TEST_PATTERN=0,
    parameter integer FINE_GAIN=0
)(
    input wire clk,rst_n,source,test_pattern_en,
    input wire [1:0] active_mode,algorithm_mode,
    input wire signed [4:0] pitch,
    input wire [4:0] gain_index,
    input wire [3:0] rec_state,
    input wire record_valid,record_full,storage_fault,ddr_ready,
    input wire [15:0] ddr_diag,
    input wire [20:0] record_progress,record_samples,play_samples,
    output wire LCD_CLK,LCD_HSYNC,LCD_VSYNC,LCD_DE,LCD_BL,
    output wire [5:0] LCD_R,LCD_G,LCD_B
);
    wire [9:0] x;wire [8:0] y;wire frame_start;
    wire s_source,s_valid,s_full,s_fault,s_ddr;
    wire [1:0] s_mode,s_algorithm;
    wire signed [4:0] s_pitch;
    wire [4:0] s_gain;wire [3:0] s_state;wire [15:0] s_diag;
    wire [11:0] rec_centis,total_centis,play_centis;wire [8:0] progress_pixels;
    wire [17:0] rgb;
    lcd_status_snapshot snapshot(.clk(clk),.rst_n(rst_n),.frame_start(frame_start),
        .source(source),.active_mode(active_mode),.algorithm_mode(algorithm_mode),
        .pitch(pitch),.gain_index(gain_index),.rec_state(rec_state),
        .record_valid(record_valid),.record_full(record_full),.storage_fault(storage_fault),
        .ddr_ready(ddr_ready),.ddr_diag(ddr_diag),.record_progress(record_progress),
        .record_samples(record_samples),.play_samples(play_samples),
        .source_o(s_source),.active_mode_o(s_mode),.algorithm_mode_o(s_algorithm),
        .pitch_o(s_pitch),.gain_index_o(s_gain),.rec_state_o(s_state),.record_valid_o(s_valid),
        .record_full_o(s_full),.storage_fault_o(s_fault),.ddr_ready_o(s_ddr),.ddr_diag_o(s_diag),
        .rec_centis(rec_centis),.total_centis(total_centis),.play_centis(play_centis),
        .progress_pixels(progress_pixels));
    lcd_dashboard #(.FINE_GAIN(FINE_GAIN)) dashboard(.clk(clk),.x(x),.y(y),.source(s_source),.active_mode(s_mode),
        .algorithm_mode(s_algorithm),.pitch(s_pitch),.gain_index(s_gain),.rec_state(s_state),
        .record_valid(s_valid),.record_full(s_full),.storage_fault(s_fault),.ddr_ready(s_ddr),
        .ddr_diag(s_diag),.rec_centis(rec_centis),.total_centis(total_centis),
        .play_centis(play_centis),.progress_pixels(progress_pixels),.rgb(rgb));
    lcd_rgb_timing #(.BACKLIGHT_ENABLE(BACKLIGHT_ENABLE),.TEST_PATTERN(TEST_PATTERN)) timing(
        .clk(clk),.rst_n(rst_n),.test_pattern_en(test_pattern_en),
        .pixel_rgb(rgb),.x(x),.y(y),.frame_start(frame_start),
        .LCD_CLK(LCD_CLK),.LCD_HSYNC(LCD_HSYNC),.LCD_VSYNC(LCD_VSYNC),.LCD_DE(LCD_DE),
        .LCD_BL(LCD_BL),.LCD_R(LCD_R),.LCD_G(LCD_G),.LCD_B(LCD_B));
endmodule
