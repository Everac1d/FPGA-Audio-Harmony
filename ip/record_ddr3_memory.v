// DDR3 音频存储物理封装；PLL 和 DDR3 核已按 B 版器件重新生成。
module record_ddr3_memory (
    input clk50,
    input rst_n,
    output ui_clk,
    output ui_rst_n,
    output calib_done,
    output reg init_error,
    // clk50 域状态快照：[0] PLL 锁定；[1] 初始化完成；[2] UI 复位已释放。
    // [3] UI 时钟活动；[4] pll_stop；[5] ddr_rst；[6] 软初始化超时；[7] 固定为 0。
    output wire [7:0] debug_status,
    output cmd_ready,
    input [2:0] cmd,
    input cmd_en,
    input [28:0] addr,
    output wr_data_rdy,
    input [255:0] wr_data,
    input wr_data_en,
    input wr_data_end,
    input [31:0] wr_data_mask,
    output [255:0] rd_data,
    output rd_data_valid,
    output rd_data_end,
    output memory_clk,
    output memory_clkn,
    output memory_cke,
    output memory_cs_n,
    output memory_cas_n,
    output memory_ras_n,
    output memory_we_n,
    output memory_reset_n,
    output memory_odt,
    output [14:0] memory_addr,
    output [2:0] memory_bank,
    inout [31:0] memory_dq,
    inout [3:0] memory_dqs,
    inout [3:0] memory_dqs_n,
    output [3:0] memory_dm
);
    wire memory_clk_400;
    wire pll_lock;
    wire pll_stop;
    wire ddr_rst;
    wire init_done;
    wire unused_sr_ack, unused_ref_ack;
    (* ASYNC_REG="TRUE", syn_preserve=1 *) reg [2:0] reset50_release;
    (* ASYNC_REG="TRUE", syn_preserve=1 *) reg [2:0] ui_reset_release;
    (* ASYNC_REG="TRUE", syn_preserve=1 *) reg [1:0] init_sync;
    reg [27:0] init_timeout_count;
    (* ASYNC_REG="TRUE", syn_preserve=1 *) reg [1:0] lock_sync,ui_run_sync,stop_sync,ddr_reset_sync;
    (* ASYNC_REG="TRUE", syn_preserve=1 *) reg [1:0] heartbeat_sync;
    reg [11:0] ui_heartbeat_divider;
    reg ui_heartbeat, heartbeat_seen,ui_clock_active;
    // 诊断计数器必须在校准完成或 UI 复位释放之前就开始运行。
    // 为其单独设置异步置位、与 UI 时钟同步释放的复位；
    // 不要复用依赖 DDR 校准完成的 ui_rst_n。
    (* ASYNC_REG="TRUE", syn_preserve=1 *) reg [1:0] ui_heartbeat_release;
    reg [15:0] heartbeat_age;
    wire core_rst_n = reset50_release[2];
    wire ui_async_reset = !core_rst_n || !pll_lock || ddr_rst || !init_done;
    assign calib_done = init_done;
    assign ui_rst_n = ui_reset_release[2];
    assign debug_status={1'b0,init_error,ddr_reset_sync[1],stop_sync[1],
        ui_clock_active,ui_run_sync[1],init_sync[1],lock_sync[1]};

    // 先在 UI 时钟域分频，再通过单个翻转信号跨域。此逻辑在
    // UI 复位或校准期间仍保持运行，因此检测的是时钟活动，
    // 而非控制器就绪状态；每 4096 个 UI 时钟周期翻转一次。
    always @(posedge ui_clk or negedge rst_n) begin
        if(!rst_n) ui_heartbeat_release<=2'b00;
        else ui_heartbeat_release<={ui_heartbeat_release[0],1'b1};
    end
    always @(posedge ui_clk or negedge ui_heartbeat_release[1]) begin
        if(!ui_heartbeat_release[1]) begin ui_heartbeat_divider<=0;ui_heartbeat<=0;end
        else if(ui_heartbeat_divider==12'hfff) begin
            ui_heartbeat_divider<=0;ui_heartbeat<=!ui_heartbeat;
        end else ui_heartbeat_divider<=ui_heartbeat_divider+1'b1;
    end
    // 所有对外报告的状态位均属于 clk50 域。若持续 1 ms 没有翻转，
    // 时钟活动标志便失效；时钟停在高电平的情况也能被检测。
    always @(posedge clk50 or negedge rst_n) begin
        if(!rst_n) begin
            lock_sync<=0;ui_run_sync<=0;stop_sync<=0;ddr_reset_sync<=0;heartbeat_sync<=0;
            heartbeat_seen<=0;heartbeat_age<=16'd49999;ui_clock_active<=0;
        end else begin
            lock_sync<={lock_sync[0],pll_lock};ui_run_sync<={ui_run_sync[0],ui_rst_n};
            stop_sync<={stop_sync[0],pll_stop};ddr_reset_sync<={ddr_reset_sync[0],ddr_rst};
            heartbeat_sync<={heartbeat_sync[0],ui_heartbeat};
            if(heartbeat_sync[1]!=heartbeat_seen) begin
                heartbeat_seen<=heartbeat_sync[1];heartbeat_age<=0;ui_clock_active<=1;
            end else if(heartbeat_age<16'd49999) heartbeat_age<=heartbeat_age+1'b1;
            else ui_clock_active<=0;
        end
    end

    Record_DDR3_PLL u_pll (
        .clkin(clk50), .init_clk(clk50), .reset(!core_rst_n),
        .enclk0(1'b1), .enclk1(1'b1), .enclk2(pll_stop),
        .clkout0(), .clkout1(), .clkout2(memory_clk_400),
        .lock(pll_lock)
    );
    // 存储器时钟为 400 MHz，用户接口分频比为 1:4，即 100 MHz。
    Record_DDR3_Core u_ddr3 (
        .clk(clk50), .memory_clk(memory_clk_400), .pll_lock(pll_lock),
        .pll_stop(pll_stop), .rst_n(core_rst_n), .clk_out(ui_clk),
        .ddr_rst(ddr_rst), .init_calib_complete(init_done),
        .cmd_ready(cmd_ready), .cmd(cmd), .cmd_en(cmd_en), .addr(addr),
        .wr_data_rdy(wr_data_rdy), .wr_data(wr_data),
        .wr_data_en(wr_data_en), .wr_data_end(wr_data_end),
        .wr_data_mask(wr_data_mask), .rd_data(rd_data),
        .rd_data_valid(rd_data_valid), .rd_data_end(rd_data_end),
        .sr_req(1'b0), .ref_req(1'b0), .sr_ack(unused_sr_ack),
        .ref_ack(unused_ref_ack), .burst(1'b1),
        .O_ddr_clk(memory_clk), .O_ddr_clk_n(memory_clkn),
        .O_ddr_cke(memory_cke), .O_ddr_cs_n(memory_cs_n),
        .O_ddr_cas_n(memory_cas_n), .O_ddr_ras_n(memory_ras_n),
        .O_ddr_we_n(memory_we_n), .O_ddr_reset_n(memory_reset_n),
        .O_ddr_odt(memory_odt), .O_ddr_addr(memory_addr),
        .O_ddr_ba(memory_bank), .IO_ddr_dq(memory_dq),
        .IO_ddr_dqs(memory_dqs), .IO_ddr_dqs_n(memory_dqs_n),
        .O_ddr_dqm(memory_dm)
    );
    // DDR3 IP 要求 rst_n 的释放与其 50 MHz 时钟同步。
    always @(posedge clk50 or negedge rst_n)
        if (!rst_n) reset50_release <= 3'b000;
        else reset50_release <= {reset50_release[1:0],1'b1};

    // 复位异步置位，并在 DDR UI 时钟域同步释放。
    always @(posedge ui_clk or posedge ui_async_reset)
        if (ui_async_reset) ui_reset_release <= 3'b000;
        else ui_reset_release <= {ui_reset_release[1:0],1'b1};

    // 校准超时由独立的 50 MHz 板载时钟计时。
    // 该标志仅用于诊断；超时后仍允许校准成功。
    always @(posedge clk50 or negedge rst_n)
        if (!rst_n) begin
            init_sync <= 2'b00;
            init_timeout_count <= 28'd0;
            init_error <= 1'b0;
        end else begin
            init_sync <= {init_sync[0],init_done};
            if (init_sync[1]) begin
                init_timeout_count <= 28'd0;
                init_error <= 1'b0;
            end else if (init_timeout_count < 28'd149999999) begin
                init_timeout_count <= init_timeout_count + 1'b1;
            end else init_error <= 1'b1;
        end
endmodule

