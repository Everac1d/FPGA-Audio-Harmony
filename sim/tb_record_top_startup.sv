`timescale 1ns/1ps
// Real top/bridge/audio with only the physical DDR wrapper replaced.
// Verifies on-demand start, soft timeout recovery, strict selftest, clip
// retention across source switch and full reset. Not a physical PHY model.
module tb_record_top_startup;
    reg clk=0;always #10 clk=~clk;
    reg rst_n=0,key_gain_n=1;
    reg [3:0] button_n=4'b1111;
    reg enc_gain_sw_n=1,enc_gain_clk=1,enc_gain_dt=1;
    reg enc_pitch_sw_n=1,enc_pitch_clk=1,enc_pitch_dt=1;
    reg [3:0] mic_sd=0;
    wire mic_bclk,mic_ws,HP_BCK,HP_WS,HP_DIN,PA_EN,WS2812,uart_tx,led_ck,led_da;
    wire memory_clk,memory_clkn,memory_cke,memory_cs_n,memory_cas_n;
    wire memory_ras_n,memory_we_n,memory_reset_n,memory_odt;
    wire [14:0] memory_addr;wire [2:0] memory_bank;
    wire [31:0] memory_dq;wire [3:0] memory_dqs,memory_dqs_n,memory_dm;
    wire LCD_CLK,LCD_HSYNC,LCD_VSYNC,LCD_DE,LCD_BL;
    wire [5:0] LCD_R,LCD_G,LCD_B;
    audio_record_ddr_top dut(.*);
    defparam dut.u_audio.POR_CYCLES=8;
    defparam dut.u_audio.STARTUP_FRAMES=3;
    defparam dut.u_audio.DEBOUNCE_CYCLES=3;
    defparam dut.u_audio.LONG_PRESS_CYCLES=24;
    defparam dut.u_audio.LONG_RESET_CYCLES=48;
    defparam dut.u_audio.ENCODER_FILTER_CYCLES=3;
    defparam dut.u_audio.MAX_SAMPLES=128;
    defparam dut.u_audio.UART_REPORT_CYCLES=1000000;
    defparam dut.u_bridge.BOOT_TIMEOUT_CYCLES=5000;
    integer checks=0,cycles=0,soft_checks=0,saved_length=0;
    task check(input bit condition,input [511:0] message);
        begin checks=checks+1;if(condition!==1'b1)begin
            $display("FAIL %0s cycle=%0d rec=%0d",message,cycles,dut.u_audio.rec_state);$fatal(1);end end
    endtask
    task clocks(input integer n);begin repeat(n)begin @(posedge clk);#1;end end endtask
    task frames(input integer n);
        integer k;begin k=0;while(k<n)begin @(posedge clk);if(dut.u_audio.frame_ce)k=k+1;end @(negedge clk);end
    endtask
    task chord;
        begin @(negedge clk);button_n[0]=0;
            repeat(9)@(negedge clk);button_n[0]=1;repeat(12)@(negedge clk);end
    endtask
    task solo;
        begin @(negedge clk);button_n[2]=0;repeat(9)@(negedge clk);button_n[2]=1;repeat(12)@(negedge clk);end
    endtask
    task wait_state(input integer wanted,input integer limit);
        integer n;begin n=0;while(dut.u_audio.rec_state!=wanted && n<limit)begin frames(1);n=n+1;end
            check(dut.u_audio.rec_state==wanted,"bounded recorder state transition");end
    endtask
    always @(posedge clk)cycles=cycles+1;
    initial begin
        clocks(4);@(negedge clk);rst_n=1;wait(dut.u_audio.mic_ready);clocks(100);
        check(dut.u_audio.meter.CALIBRATION_MARGIN == -1500 && dut.u_audio.ring_calibration_margin == -1500,"production fixed margin -1500");
        check(!dut.audio_source && !dut.storage_started && !dut.storage_run_n,"live boot leaves DDR disabled");
        check(!memory_reset_n && !dut.calib_done && !dut.bridge_ready,"DDR wrapper held reset in live standby");
        check(!dut.u_audio.storage_fault && dut.u_audio.rec_state==0 && dut.u_audio.ddr_diag==0,"no false standby fault");
        fork
            begin
                wait(dut.storage_run_n);wait(dut.u_memory.init_error);
                check(!dut.calib_done && !dut.bridge_ready,"soft timeout precedes calibration");
                while(!dut.calib_done)begin @(negedge clk);
                    check(!dut.u_audio.storage_fault && !dut.u_audio.ddr_error,"soft timeout is diagnostic only");
                    check(dut.u_audio.rec_state==0,"recorder waits without sticky error");
                    check(dut.u_audio.ddr_diag==={dut.bridge_error_code,dut.bridge_debug_state,dut.memory_debug},"top diagnostic concatenation");
                    soft_checks=soft_checks+1;
                end
                wait_state(1,5);clocks(24);
                check(dut.bridge_ready && !dut.bridge_error,"late calibration passes hard deadline");
                check(dut.u_memory.writes==16 && dut.u_memory.reads==16,"sixteen selftest locations");
                check(dut.u_audio.ddr_diag===16'h040f,"ready diagnostic word");
                check(dut.u_audio.reporter.ddr_diag===16'h040f && dut.u_audio.reporter.ddr_failure===545'd0,"top diagnostic and failure wiring");
            end
            begin chord;end
        join
        check(dut.audio_source && dut.storage_started,"first clip request starts DDR");
        solo;wait_state(2,5);frames(40);solo;wait_state(4,10);
        saved_length=dut.u_audio.record_samples;
        check(dut.u_audio.record_valid && saved_length>=40,"raw clip committed for retention test");
        chord;frames(5);
        check(!dut.audio_source && dut.storage_started && dut.storage_run_n && dut.calib_done,"return live keeps DDR refreshing");
        check(dut.u_audio.record_valid && dut.u_audio.record_samples==saved_length,"return live retains clip metadata");
        check(dut.bridge_ready && !dut.bridge_error,"return live does not rerun or clear DDR");
        @(negedge clk);button_n[0]=0;clocks(64);button_n[0]=1;
        wait(!dut.system_rst_n);clocks(8);
        check(!dut.storage_started && !dut.storage_run_n && !memory_reset_n,"external key1 long reset disables DDR");
        check(!dut.u_audio.record_valid,"global reset invalidates prior clip");
        check(soft_checks>100 && cycles<180000,"meaningful bounded startup coverage");
        $display("PASS RECORD_TOP_STARTUP checks=%0d soft_cycles=%0d cycles=%0d saved_samples=%0d on_demand_DDR selftest16 soft_timeout_no_hard_fault late_calibration_empty clip_retained reset top_diag",checks,soft_checks,cycles,saved_length);
        $finish;
    end
    initial begin #3000000;$fatal(1,"timeout RECORD_TOP_STARTUP");end
endmodule

// Test-only DDR app-port wrapper: deterministic soft timeout then successful
// calibration, with an ideal BL8 memory response. The production GPRJ never
// includes this file and uses the actual B-version encrypted IP wrapper.
module record_ddr3_memory(
    input clk50,rst_n,
    output reg ui_clk=0,
    output reg ui_rst_n=0,calib_done=0,init_error=0,
    output wire [7:0] debug_status,
    output wire cmd_ready,
    input [2:0] cmd,input cmd_en,input [28:0] addr,
    output wire wr_data_rdy,input [255:0] wr_data,
    input wr_data_en,wr_data_end,input [31:0] wr_data_mask,
    output reg [255:0] rd_data=0,
    output reg rd_data_valid=0,rd_data_end=0,
    output wire memory_clk,memory_clkn,memory_cke,memory_cs_n,memory_cas_n,
    output wire memory_ras_n,memory_we_n,memory_reset_n,memory_odt,
    output wire [14:0] memory_addr,output wire [2:0] memory_bank,
    inout wire [31:0] memory_dq,inout wire [3:0] memory_dqs,memory_dqs_n,
    output wire [3:0] memory_dm
);
    initial begin #3;forever #5 ui_clk=~ui_clk;end
    integer phase_count=0,writes=0,reads=0;
    reg [255:0] storage[0:511];
    function integer location(input [28:0] a);
        location={a[19:16],a[7:3]};
    endfunction
    assign debug_status=!rst_n ? 8'h00 : (calib_done ? 8'h0f : (init_error ? 8'h49 : 8'h09));
    assign cmd_ready=calib_done;
    assign wr_data_rdy=calib_done;
    assign memory_clk=ui_clk;assign memory_clkn=!ui_clk;
    assign memory_cke=calib_done;assign memory_reset_n=rst_n;
    assign memory_cs_n=1;assign memory_cas_n=1;assign memory_ras_n=1;assign memory_we_n=1;
    assign memory_odt=0;assign memory_addr=0;assign memory_bank=0;assign memory_dm=0;
    assign memory_dq=32'bz;assign memory_dqs=4'bz;assign memory_dqs_n=4'bz;
    always @(posedge clk50 or negedge rst_n)begin
        if(!rst_n)begin phase_count<=0;ui_rst_n<=0;calib_done<=0;init_error<=0;end
        else begin
            phase_count<=phase_count+1;
            if(phase_count==64)init_error<=1;
            if(phase_count==512)begin ui_rst_n<=1;calib_done<=1;init_error<=0;end
        end
    end
    always @(posedge ui_clk)begin
        if(!rst_n)begin writes<=0;reads<=0;rd_data<=0;rd_data_valid<=0;rd_data_end<=0;end
        else begin
            rd_data_valid<=0;rd_data_end<=0;
            if(cmd_en && cmd_ready)begin
                if(addr[2:0]!==3'd0)$fatal(1,"unaligned startup app address");
                if(cmd==0)begin
                    if(!wr_data_en || !wr_data_end || wr_data_mask!==0)$fatal(1,"startup BL8 write handshake");
                    storage[location(addr)]<=wr_data;writes<=writes+1;
                end else if(cmd==1)begin
                    rd_data<=storage[location(addr)];rd_data_valid<=1;rd_data_end<=1;reads<=reads+1;
                end else $fatal(1,"unsupported startup app command");
            end
        end
    end
endmodule
