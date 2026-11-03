// 硬件：GW5AST-LV138PG484AC1/I0 B版与Tang Mega NEO Dock 31004底板。
module audio_record_ddr_top #(
    // 用户已确认学校配发的面板与此开发板兼容。
    parameter integer LCD_BACKLIGHT_ENABLE=1,
    parameter integer LCD_TEST_PATTERN=0,
    parameter integer RING_TUNE_ENABLE=0
)(
    input wire clk,rst_n,key_gain_n,
    input wire [3:0] button_n,
    input wire enc_gain_sw_n,enc_gain_clk,enc_gain_dt,
    input wire enc_pitch_sw_n,enc_pitch_clk,enc_pitch_dt,
    input wire[3:0] mic_sd,
    output wire mic_bclk,mic_ws,HP_BCK,HP_WS,HP_DIN,PA_EN,WS2812,uart_tx,led_ck,led_da,
    output wire memory_clk,memory_clkn,memory_cke,memory_cs_n,memory_cas_n,
    output wire memory_ras_n,memory_we_n,memory_reset_n,memory_odt,
    output wire[14:0] memory_addr,output wire[2:0] memory_bank,
    inout wire[31:0] memory_dq,inout wire[3:0] memory_dqs,memory_dqs_n,
    output wire[3:0] memory_dm,
    output wire LCD_CLK,LCD_HSYNC,LCD_VSYNC,LCD_DE,LCD_BL,
    output wire [5:0] LCD_R,LCD_G,LCD_B
);
    // 外接复位操作的脉冲展宽独立于被复位的子系统，
    // 因此界面自身复位不会缩短全局复位脉冲。
    wire external_reset_request;
    reg [7:0] external_reset_count=0;
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)external_reset_count<=0;
        else if(external_reset_request)external_reset_count<=8'hff;
        else if(external_reset_count!=0)external_reset_count<=external_reset_count-1'b1;
    end
    wire system_rst_n=rst_n && external_reset_count==0;
    (* ASYNC_REG="TRUE" *) reg board_reset_meta=0,board_reset_sync=0;
    reg [15:0] board_por=0;
    reg board_run_n=0;
    // 仅用于显示的诊断选择：按住KEY2并释放KEY1以
    // 锁存彩条；正常按KEY1复位可返回仪表界面。
    (* ASYNC_REG="TRUE" *) reg lcd_key_gain_meta=1,lcd_key_gain_sync=1;
    reg lcd_test_mode=0;
    always @(posedge clk or negedge system_rst_n)begin
        if(!system_rst_n)begin
            lcd_key_gain_meta<=1;lcd_key_gain_sync<=1;lcd_test_mode<=0;
        end else begin
            lcd_key_gain_meta<=key_gain_n;lcd_key_gain_sync<=lcd_key_gain_meta;
            if(!board_reset_sync)lcd_test_mode<=0;
            else if(!board_run_n && board_por==16'hfffe)
                lcd_test_mode<=!lcd_key_gain_sync;
        end
    end
    always @(posedge clk or negedge system_rst_n)begin
        if(!system_rst_n)begin board_reset_meta<=0;board_reset_sync<=0;end
        else begin board_reset_meta<=1;board_reset_sync<=board_reset_meta;end
    end
    always @(posedge clk or negedge system_rst_n)begin
        if(!system_rst_n)begin board_por<=0;board_run_n<=0;end
        else if(!board_reset_sync)begin board_por<=0;board_run_n<=0;end
        else if(!board_run_n)begin
            if(board_por==16'hffff)board_run_n<=1;
            else board_por<=board_por+1'b1;
        end
    end
    // 实时基线不使用DDR；首次请求录放模式前，保持其400MHz PHY/PLL复位，
    // 随后持续刷新存储器，直到按下KEY1复位。
    // 返回实时模式不得丢弃已经保存的录音。
    wire audio_source;
    reg storage_started=0;
    always @(posedge clk or negedge system_rst_n)begin
        if(!system_rst_n)storage_started<=0;
        else if(!board_run_n)storage_started<=0;
        else if(audio_source)storage_started<=1;
    end
    wire storage_run_n=board_run_n && storage_started;
    wire ui_clk,ui_rst_n,calib_done,init_error,bridge_ready,bridge_error;
    wire [7:0] memory_debug;
    wire [3:0] bridge_debug_state,bridge_error_code;
    wire [544:0] bridge_failure;
    wire[2:0] cmd;wire cmd_en,cmd_ready,wr_data_rdy,wr_en,wr_end,rd_valid,rd_end;
    wire[28:0] addr;wire[255:0] wr_data,rd_data;wire[31:0] mask;
    wire req_valid,req_write,req_ready,rsp_valid;wire[28:0] req_addr;
    wire[255:0] req_wdata,rsp_rdata;
    record_ddr3_memory u_memory(.clk50(clk),.rst_n(storage_run_n),.ui_clk(ui_clk),.ui_rst_n(ui_rst_n),
        .calib_done(calib_done),.init_error(init_error),.debug_status(memory_debug),.cmd_ready(cmd_ready),.cmd(cmd),
        .cmd_en(cmd_en),.addr(addr),.wr_data_rdy(wr_data_rdy),.wr_data(wr_data),
        .wr_data_en(wr_en),.wr_data_end(wr_end),.wr_data_mask(mask),.rd_data(rd_data),
        .rd_data_valid(rd_valid),.rd_data_end(rd_end),.memory_clk(memory_clk),.memory_clkn(memory_clkn),
        .memory_cke(memory_cke),.memory_cs_n(memory_cs_n),.memory_cas_n(memory_cas_n),
        .memory_ras_n(memory_ras_n),.memory_we_n(memory_we_n),.memory_reset_n(memory_reset_n),
        .memory_odt(memory_odt),.memory_addr(memory_addr),.memory_bank(memory_bank),
        .memory_dq(memory_dq),.memory_dqs(memory_dqs),.memory_dqs_n(memory_dqs_n),.memory_dm(memory_dm));
    ddr_audio_bridge u_bridge(.clk(clk),.rst_n(storage_run_n),.ready(bridge_ready),.error(bridge_error),
        .debug_state(bridge_debug_state),.error_code(bridge_error_code),
        .failure_snapshot(bridge_failure),
        .req_valid(req_valid),.req_write(req_write),.req_addr(req_addr),.req_wdata(req_wdata),
        .req_ready(req_ready),.rsp_valid(rsp_valid),.rsp_rdata(rsp_rdata),
        .ui_clk(ui_clk),.ui_rst_n(ui_rst_n),.calib_done(calib_done),.cmd(cmd),.cmd_en(cmd_en),
        .addr(addr),.wdata(wr_data),.wr_data_en(wr_en),.wr_data_end(wr_end),.wr_data_mask(mask),
        .cmd_ready(cmd_ready),.wr_data_rdy(wr_data_rdy),.rd_data(rd_data),
        .rd_data_valid(rd_valid),.rd_data_end(rd_end));
    wire [1:0] lcd_mode,lcd_algorithm;
    wire signed [4:0] lcd_pitch,lcd_pitch_second;wire lcd_pitch_voice;
    wire [4:0] lcd_gain;wire [3:0] lcd_rec_state;
    wire [31:0] lcd_record_samples,lcd_record_progress,lcd_play_samples;
    wire lcd_ring_tuning;wire signed [12:0] lcd_ring_margin;
    wire [15:0] lcd_ring_floor,lcd_ring_mean;
    wire lcd_record_valid,lcd_record_full,lcd_fault;
    audio_harmony_engine_tuned #(.STATUS_USER_CODE(32'h00033109),.MAX_SAMPLES(14648438),.RING_TUNE_ENABLE(RING_TUNE_ENABLE),.EXTERNAL_CONTROLS(1),.ENHANCED_PLAYBACK(1),.DUAL_VOICE_ENABLE(1)) u_audio(
        .clk(clk),.rst_n(board_run_n),.key_mode_n(1'b1),.key_gain_n(1'b1),
        .button_n(button_n),.enc_gain_sw_n(enc_gain_sw_n),.enc_gain_clk(enc_gain_clk),.enc_gain_dt(enc_gain_dt),
        .enc_pitch_sw_n(enc_pitch_sw_n),.enc_pitch_clk(enc_pitch_clk),.enc_pitch_dt(enc_pitch_dt),
        .soft_reset_request(external_reset_request),
        .active_source(audio_source),
        .active_algorithm_mode(lcd_algorithm),.active_pitch_semitones(lcd_pitch),.active_pitch_second(lcd_pitch_second),.display_pitch_voice(lcd_pitch_voice),
        .gain_index(lcd_gain),.rec_state(lcd_rec_state),.record_samples(lcd_record_samples),
        .record_progress(lcd_record_progress),.play_samples(lcd_play_samples),
        .record_valid(lcd_record_valid),.record_full(lcd_record_full),.storage_fault(lcd_fault),
        .display_active_mode(lcd_mode),.display_switching(),
        .ring_tuning(lcd_ring_tuning),.ring_calibration_margin(lcd_ring_margin),
        .ring_noise_floor(lcd_ring_floor),.ring_mean_level(lcd_ring_mean),
        .mic_sd(mic_sd),.mic_bclk(mic_bclk),.mic_ws(mic_ws),.HP_BCK(HP_BCK),.HP_WS(HP_WS),
        .HP_DIN(HP_DIN),.PA_EN(PA_EN),.WS2812(WS2812),.uart_tx(uart_tx),.led_ck(led_ck),.led_da(led_da),
        // 封装模块的3秒超时仅用于诊断；桥接模块负责
        // 5秒启动期限，并在存储器验证通过后才置就绪。
        .ddr_ready(bridge_ready),.ddr_error(bridge_error),
        .ddr_diag({bridge_error_code,bridge_debug_state,memory_debug}),
        .ddr_failure(bridge_failure),
        .req_valid(req_valid),.req_write(req_write),.req_addr(req_addr),.req_wdata(req_wdata),
        .req_ready(req_ready),.rsp_valid(rsp_valid),.rsp_rdata(rsp_rdata));
    audio_harmony_lcd_display #(.BACKLIGHT_ENABLE(LCD_BACKLIGHT_ENABLE),.TEST_PATTERN(LCD_TEST_PATTERN),.FINE_GAIN(1),.RING_TUNE_ENABLE(RING_TUNE_ENABLE)) u_lcd(
        .clk(clk),.rst_n(board_run_n),.test_pattern_en(lcd_test_mode),
        .source(audio_source),.active_mode(lcd_mode),
        .ring_tuning(lcd_ring_tuning),.ring_calibration_margin(lcd_ring_margin),
        .ring_noise_floor(lcd_ring_floor),.ring_mean_level(lcd_ring_mean),
        .algorithm_mode(lcd_algorithm),.pitch(lcd_pitch),.pitch_second(lcd_pitch_second),.pitch_voice(lcd_pitch_voice),.gain_index(lcd_gain),
        .rec_state(lcd_rec_state),.record_valid(lcd_record_valid),.record_full(lcd_record_full),
        .storage_fault(lcd_fault),.ddr_ready(bridge_ready),
        .ddr_diag({bridge_error_code,bridge_debug_state,memory_debug}),
        .record_progress(lcd_record_progress),.record_samples(lcd_record_samples),
        .play_samples(lcd_play_samples),.LCD_CLK(LCD_CLK),.LCD_HSYNC(LCD_HSYNC),
        .LCD_VSYNC(LCD_VSYNC),.LCD_DE(LCD_DE),.LCD_BL(LCD_BL),
        .LCD_R(LCD_R),.LCD_G(LCD_G),.LCD_B(LCD_B));
endmodule
