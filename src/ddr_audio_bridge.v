// 50MHz音频域与DDR3 IP用户域之间的邮箱，
// 同一时刻仅允许一笔未完成事务；多位邮箱数据保持不变，直到
// 同步后的翻转标志得到确认，不对数据逐位采样。
// 物理DDR3为x32、BL8、用户位宽256：应用地址每拍递增8。
// 本模块用于应用接口测试与桥接，不实现DDR物理层。
module ddr_audio_bridge #(
    parameter integer TIMEOUT_CYCLES = 25000000,
    parameter integer BOOT_TIMEOUT_CYCLES = 250000000
) (
    input wire clk, rst_n,
    output wire ready,
    output reg error,
    // clk域诊断：状态为周期握手获取的一致用户接口
    // 快照；error_code锁存首个故障，直到全局复位。
    output wire [3:0] debug_state,
    output reg [3:0] error_code,
    // 首个自检不匹配信息，保持稳定直至全局复位；位于clk域，格式为：
    // 字段：{index[3:0], address[28:0], expected[255:0], actual[255:0]}。
    output reg [544:0] failure_snapshot,
    input wire req_valid, req_write,
    input wire [28:0] req_addr,
    input wire [255:0] req_wdata,
    output wire req_ready,
    output reg rsp_valid,
    output reg [255:0] rsp_rdata,
    input wire ui_clk, ui_rst_n, calib_done,
    output wire [2:0] cmd,
    output wire cmd_en,
    output wire [28:0] addr,
    output wire [255:0] wdata,
    output wire wr_data_en, wr_data_end,
    output wire [31:0] wr_data_mask,
    input wire cmd_ready, wr_data_rdy,
    input wire [255:0] rd_data,
    input wire rd_data_valid, rd_data_end
);
    (* ASYNC_REG="TRUE", syn_preserve=1 *) reg audio_reset_meta, audio_reset_sync;
    (* ASYNC_REG="TRUE", syn_preserve=1 *) reg ui_reset_meta, ui_reset_sync;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin audio_reset_meta<=0;audio_reset_sync<=0;end
        else begin audio_reset_meta<=1;audio_reset_sync<=audio_reset_meta;end
    end
    always @(posedge ui_clk or negedge rst_n) begin
        if(!rst_n) begin ui_reset_meta<=0;ui_reset_sync<=0;end
        else begin ui_reset_meta<=1;ui_reset_sync<=ui_reset_meta;end
    end

    reg a_request_toggle, a_write, a_busy;
    reg [28:0] a_addr;
    reg [255:0] a_data;
    reg u_ack_toggle, u_ready, u_error;
    // 从置位u_error的同一用户接口时钟边沿起保持稳定，直至全局复位。
    // 同步后的u_error用于限定clk域中成组数据的捕获时机。
    reg [3:0] u_error_code;
    reg [544:0] u_failure_snapshot;
    reg failure_captured;
    reg [3:0] state,test_index;
    reg [255:0] u_response;
    (* ASYNC_REG="TRUE", syn_preserve=1 *) reg ack_meta,ack_sync,ready_meta,ready_sync,error_meta,error_sync;
    (* ASYNC_REG="TRUE", syn_preserve=1 *) reg request_meta,request_sync;
    reg ever_ready;
    reg [31:0] boot_watchdog, audio_watchdog;
    // 诊断邮箱独立于音频请求，因此即使尚未就绪，启动与自检
    // 状态仍可观察；数据持续保持，直到clk域读取已确认快照后
    // 发出下一次请求。
    reg diagnostic_request, diagnostic_ack;
    reg [3:0] diagnostic_mailbox, diagnostic_snapshot;
    (* ASYNC_REG="TRUE", syn_preserve=1 *) reg diagnostic_request_meta,diagnostic_request_sync;
    (* ASYNC_REG="TRUE", syn_preserve=1 *) reg diagnostic_ack_meta,diagnostic_ack_sync;
    assign debug_state=diagnostic_snapshot;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin diagnostic_ack_meta<=0;diagnostic_ack_sync<=0;end
        else begin diagnostic_ack_meta<=diagnostic_ack;diagnostic_ack_sync<=diagnostic_ack_meta;end
    end
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin diagnostic_request<=0;diagnostic_snapshot<=0;end
        else if(!audio_reset_sync) begin diagnostic_request<=0;diagnostic_snapshot<=0;end
        else if(diagnostic_ack_sync==diagnostic_request) begin
            diagnostic_snapshot<=diagnostic_mailbox;
            diagnostic_request<=!diagnostic_request;
        end
    end
    always @(posedge ui_clk or negedge rst_n) begin
        if(!rst_n) begin diagnostic_request_meta<=0;diagnostic_request_sync<=0;end
        else begin diagnostic_request_meta<=diagnostic_request;diagnostic_request_sync<=diagnostic_request_meta;end
    end
    always @(posedge ui_clk or negedge rst_n) begin
        if(!rst_n) begin diagnostic_mailbox<=0;diagnostic_ack<=0;end
        else if(!ui_reset_sync) begin diagnostic_mailbox<=0;diagnostic_ack<=0;end
        else if(diagnostic_request_sync!=diagnostic_ack) begin
            diagnostic_mailbox<=state;diagnostic_ack<=diagnostic_request_sync;
        end
    end
    assign ready=ready_sync && !error && !error_sync && audio_reset_sync;
    assign req_ready=ready && !a_busy;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            ack_meta<=0;ack_sync<=0;ready_meta<=0;ready_sync<=0;error_meta<=0;error_sync<=0;
        end else begin
            ack_meta<=u_ack_toggle;ack_sync<=ack_meta;
            ready_meta<=u_ready;ready_sync<=ready_meta;
            error_meta<=u_error;error_sync<=error_meta;
        end
    end
    // u_failure_snapshot与u_error在同一用户接口时钟边沿写入；
    // 两级错误同步器限定成组数据的捕获时机，随后源端
    // 数据在FAULT状态保持不变，直至全局复位。
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin failure_snapshot<=0;failure_captured<=0;end
        else if(!audio_reset_sync) begin failure_snapshot<=0;failure_captured<=0;end
        else if(error_sync && error_code==4'd7 && !failure_captured) begin
            failure_snapshot<=u_failure_snapshot;failure_captured<=1;
        end
    end
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            a_request_toggle<=0;a_write<=0;a_addr<=0;a_data<=0;a_busy<=0;
            rsp_valid<=0;rsp_rdata<=0;error<=0;error_code<=0;ever_ready<=0;
            boot_watchdog<=0;audio_watchdog<=0;
        end else if(!audio_reset_sync) begin
            a_request_toggle<=0;a_write<=0;a_addr<=0;a_data<=0;a_busy<=0;
            rsp_valid<=0;rsp_rdata<=0;error<=0;error_code<=0;ever_ready<=0;
            boot_watchdog<=0;audio_watchdog<=0;
        end else begin
            rsp_valid<=0;
            if(ready_sync) begin ever_ready<=1;boot_watchdog<=0;end
            else if(!error) begin
                if(boot_watchdog<BOOT_TIMEOUT_CYCLES-1) boot_watchdog<=boot_watchdog+1'b1;
            end
            // 控制器或用户时钟丢失、复位变化时，不得在已有有效录音的情况下
            // 悄然重新启动自检。
            // 就绪状态同时下降时，按错误优先级保留用户接口的具体原因；
            // u_error_code为稳定邮箱，仅在同沿有效标志
            // 通过两级触发器同步后采样。
            if(!error) begin
                if(error_sync) begin error<=1;error_code<=u_error_code;end
                else if(ever_ready && !ready_sync) begin error<=1;error_code<=4'd2;end
                else if(a_busy && ack_sync!=a_request_toggle && audio_watchdog>=TIMEOUT_CYCLES-1)
                    begin error<=1;error_code<=4'd3;end
                else if(!ready_sync && boot_watchdog>=BOOT_TIMEOUT_CYCLES-1)
                    begin error<=1;error_code<=4'd1;end
            end
            if(error || error_sync || (ever_ready && !ready_sync)) begin
                a_busy<=0;
            end else if(req_valid && req_ready) begin
                a_write<=req_write;a_addr<=req_addr;a_data<=req_wdata;
                a_request_toggle<=!a_request_toggle;a_busy<=1;audio_watchdog<=0;
            end else if(a_busy) begin
                if(ack_sync==a_request_toggle) begin
                    rsp_rdata<=u_response;rsp_valid<=1;a_busy<=0;audio_watchdog<=0;
                end else if(audio_watchdog>=TIMEOUT_CYCLES-1) begin
                    a_busy<=0;
                end else audio_watchdog<=audio_watchdog+1'b1;
            end
        end
    end
    always @(posedge ui_clk or negedge rst_n) begin
        if(!rst_n) begin request_meta<=0;request_sync<=0;end
        else begin request_meta<=a_request_toggle;request_sync<=request_meta;end
    end

    localparam [3:0] BOOT=0,TEST_WRITE=1,TEST_READ_CMD=2,TEST_READ_DATA=3,
        IDLE=4,USER_WRITE=5,USER_READ_CMD=6,USER_READ_DATA=7,FAULT=8;
    reg request_seen,cmd_sent,data_sent;
    reg [28:0] job_addr;
    reg [255:0] job_data;
    reg [31:0] ui_watchdog;
    // 十六个地址点跨越约3.93MB，并使用不同的低位
    // 偏移；先写完所有模式再回读，以检测这些地址之间的别名，
    // 以及各测试点的数据错误与地址错误。
    function [28:0] test_address;
        input [3:0] index;
        begin test_address={9'd0,index,16'd0}+{22'd0,index,3'd0};end
    endfunction
    function [255:0] test_pattern;
        input [3:0] index;
        integer lane;
        begin
            for(lane=0;lane<8;lane=lane+1)
                test_pattern[lane*32 +: 32]=32'h96a53cc3 ^ {4{~index,index}} ^ (32'h01020408<<lane);
        end
    endfunction
    wire issue_write=(state==TEST_WRITE || state==USER_WRITE);
    wire issue_read=(state==TEST_READ_CMD || state==USER_READ_CMD);
    wire app_enabled=ui_reset_sync && ui_rst_n && calib_done && !u_error;
    // 与Gowin参考用户接口的写事务一致：仅当命令与写数据接口
    // 同时就绪时，才在同一用户接口时钟拍发起事务。
    // 此兼容性候选实现不能证明物理DDR工作正确。
    wire joint_write=app_enabled && issue_write && cmd_ready && wr_data_rdy;
    assign cmd=issue_write ? 3'b000 : 3'b001;
    // 此原生IP使用使能脉冲，而非在满状态期间持续保持的有效信号。
    // 内部满标志存在延迟，在外部就绪信号刚下降后仍可能接收额外使能，
    // 因此读命令与写命令均需进行门控。
    assign cmd_en=joint_write || (app_enabled && issue_read && cmd_ready && !cmd_sent);
    assign addr=job_addr;
    assign wdata=job_data;
    assign wr_data_en=joint_write;
    assign wr_data_end=wr_data_en;
    assign wr_data_mask=32'd0;
    wire command_accept=cmd_en && cmd_ready;
    wire write_accept=wr_data_en && wr_data_rdy;
    wire write_complete=command_accept && write_accept;
    wire read_return=rd_data_valid &&
        ((state==TEST_READ_DATA || state==USER_READ_DATA) || (issue_read && command_accept));
    always @(posedge ui_clk or negedge rst_n) begin
        if(!rst_n) begin
            state<=BOOT;test_index<=0;request_seen<=0;cmd_sent<=0;data_sent<=0;
            job_addr<=0;job_data<=0;ui_watchdog<=0;u_ready<=0;u_error<=0;u_error_code<=0;
            u_ack_toggle<=0;u_response<=0;u_failure_snapshot<=0;
        end else if(!ui_reset_sync) begin
            state<=BOOT;test_index<=0;request_seen<=0;cmd_sent<=0;data_sent<=0;
            job_addr<=0;job_data<=0;ui_watchdog<=0;u_ready<=0;u_error<=0;u_error_code<=0;
            u_ack_toggle<=0;u_response<=0;u_failure_snapshot<=0;
        end else if(state==FAULT) begin
            u_error<=1;u_ready<=0;
        end else if(state!=BOOT && (!ui_rst_n || !calib_done)) begin
            state<=FAULT;u_error<=1;u_ready<=0;u_error_code<=4'd4;
        end else if(state!=BOOT && state!=IDLE && ui_watchdog>=TIMEOUT_CYCLES-1) begin
            state<=FAULT;u_error<=1;u_ready<=0;u_error_code<=4'd5;
        end else begin
            if(state!=BOOT && state!=IDLE) ui_watchdog<=ui_watchdog+1'b1;
            else ui_watchdog<=0;
            case(state)
                BOOT: if(ui_rst_n && calib_done) begin
                    test_index<=0;job_addr<=test_address(0);job_data<=test_pattern(0);
                    cmd_sent<=0;data_sent<=0;ui_watchdog<=0;state<=TEST_WRITE;
                end
                TEST_WRITE,USER_WRITE: begin
                    if(command_accept) cmd_sent<=1;
                    if(write_accept) data_sent<=1;
                    if(write_complete) begin
                        cmd_sent<=0;data_sent<=0;ui_watchdog<=0;
                        if(state==USER_WRITE) begin
                            u_response<=0;u_ack_toggle<=request_seen;state<=IDLE;
                        end else if(test_index==15) begin
                            test_index<=0;job_addr<=test_address(0);state<=TEST_READ_CMD;
                        end else begin
                            test_index<=test_index+1'b1;
                            job_addr<=test_address(test_index+1'b1);job_data<=test_pattern(test_index+1'b1);
                        end
                    end
                end
                TEST_READ_CMD,USER_READ_CMD: begin
                    if(command_accept) begin
                        cmd_sent<=1;
                        state<=(state==TEST_READ_CMD) ? TEST_READ_DATA : USER_READ_DATA;
                    end
                end
                TEST_READ_DATA,USER_READ_DATA: begin end
                IDLE: if(request_sync!=request_seen) begin
                    request_seen<=request_sync;job_addr<=a_addr;job_data<=a_data;
                    cmd_sent<=0;data_sent<=0;ui_watchdog<=0;
                    state<=a_write ? USER_WRITE : USER_READ_CMD;
                end
                default: begin state<=FAULT;u_error<=1;u_ready<=0;u_error_code<=4'd8;end
            endcase
            if(read_return) begin
                cmd_sent<=0;data_sent<=0;ui_watchdog<=0;
                if(!rd_data_end) begin state<=FAULT;u_error<=1;u_ready<=0;u_error_code<=4'd6;end
                else if(state==USER_READ_CMD || state==USER_READ_DATA) begin
                    u_response<=rd_data;u_ack_toggle<=request_seen;state<=IDLE;
                end else if(rd_data!=test_pattern(test_index)) begin
                    state<=FAULT;u_error<=1;u_ready<=0;u_error_code<=4'd7;
                    u_failure_snapshot<={test_index,job_addr,test_pattern(test_index),rd_data};
                end else if(test_index==15) begin
                    u_ready<=1;state<=IDLE;
                end else begin
                    test_index<=test_index+1'b1;job_addr<=test_address(test_index+1'b1);
                    state<=TEST_READ_CMD;
                end
            end
        end
    end
endmodule
