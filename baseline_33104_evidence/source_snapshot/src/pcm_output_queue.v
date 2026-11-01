// PCM 回放队列：用有效脉冲接收样本，在 DAC 帧边界消费一个样本。
// 所有信号均属于 clk 时钟域；frame_ce 是单周期使能，不是另一路时钟。
module pcm_output_queue #(
    parameter ADDR_WIDTH = 4,
    parameter PREFILL_SAMPLES = 2,
    // 0 保留原队列行为；非零时在每次队首改变后留出处理流水线准备时间。
    parameter HEAD_SETUP_CYCLES = 0
) (
    input  wire                       clk,
    input  wire                       rst_n,
    input  wire                       flush,
    input  wire signed [15:0]         pcm_in,
    input  wire                       in_valid,
    input  wire                       frame_ce,
    output wire signed [15:0]         pcm_head,
    output wire                       head_valid,
    output reg                        started,
    output wire [ADDR_WIDTH:0]         level,
    output reg  [31:0]                accepted_count,
    output reg  [31:0]                played_count,
    output reg  [31:0]                underflow_count,
    output reg  [31:0]                overflow_count
);
    localparam DEPTH = (1 << ADDR_WIDTH);
    localparam [ADDR_WIDTH:0] DEPTH_COUNT = DEPTH;
    localparam [ADDR_WIDTH:0] PREFILL_COUNT = PREFILL_SAMPLES;
    localparam integer SETUP_WIDTH = (HEAD_SETUP_CYCLES < 2) ? 1 :
                                     $clog2(HEAD_SETUP_CYCLES + 1);

    // rst_n 与 flush 均同步采样，允许顶层使用同域启动条件生成 rst_n。
    // 小队列用寄存器实现；不复位 RAM 内容，仅复位其有效范围。
    // 异步读使 TX 能在 frame_ce 的同一上升沿锁存队首。
    (* syn_ramstyle = "registers" *) reg signed [15:0] samples [0:DEPTH-1];
    reg [ADDR_WIDTH-1:0] read_ptr;
    reg [ADDR_WIDTH-1:0] write_ptr;
    reg [ADDR_WIDTH:0] used_count;
    reg [SETUP_WIDTH-1:0] head_setup_count;

    wire empty = (used_count == 0);
    wire full = (used_count == DEPTH_COUNT);
    wire take_sample = frame_ce && head_valid;
    // 满时若同拍出队，腾出的位置允许接收一个新样本。
    wire put_sample = in_valid && (!full || take_sample);

    assign level = used_count;
    wire head_prepared = (HEAD_SETUP_CYCLES == 0) ||
                         (head_setup_count >= HEAD_SETUP_CYCLES);
    assign head_valid = started && !empty && head_prepared;
    // 有准备窗口时提前暴露原始队首，供下游流水线预热；只有 head_valid 允许消费。
    // 参数为 0 时连预填阶段的数据端口行为也与原实现相同。
    assign pcm_head = (HEAD_SETUP_CYCLES == 0) ?
                      (head_valid ? samples[read_ptr] : 16'sd0) :
                      (!empty ? samples[read_ptr] : 16'sd0);

    always @(posedge clk) begin
        if (!rst_n) begin
            read_ptr <= {ADDR_WIDTH{1'b0}};
            write_ptr <= {ADDR_WIDTH{1'b0}};
            used_count <= {(ADDR_WIDTH+1){1'b0}};
            head_setup_count <= {SETUP_WIDTH{1'b0}};
            started <= 1'b0;
            accepted_count <= 32'd0;
            played_count <= 32'd0;
            underflow_count <= 32'd0;
            overflow_count <= 32'd0;
        end else if (flush) begin
            read_ptr <= {ADDR_WIDTH{1'b0}};
            write_ptr <= {ADDR_WIDTH{1'b0}};
            used_count <= {(ADDR_WIDTH+1){1'b0}};
            head_setup_count <= {SETUP_WIDTH{1'b0}};
            started <= 1'b0;
            accepted_count <= 32'd0;
            played_count <= 32'd0;
            underflow_count <= 32'd0;
            overflow_count <= 32'd0;
        end else begin
            // 在达到阈值后的下一拍启动；运行后即使短暂读空也不退出启动状态。
            if (!started && (used_count >= PREFILL_COUNT))
                started <= 1'b1;

            // 出队后的新队首、空队列刚写入的队首均从 0 开始准备。
            // 写队尾不影响已有队首；满队列同拍读写也必须重新准备新队首。
            if (empty || take_sample)
                head_setup_count <= {SETUP_WIDTH{1'b0}};
            else if ((HEAD_SETUP_CYCLES != 0) && !head_prepared)
                head_setup_count <= head_setup_count + 1'b1;

            if (put_sample) begin
                samples[write_ptr] <= pcm_in;
                write_ptr <= write_ptr + 1'b1;
                accepted_count <= accepted_count + 1'b1;
            end
            if (take_sample) begin
                read_ptr <= read_ptr + 1'b1;
                played_count <= played_count + 1'b1;
            end

            case ({put_sample, take_sample})
                2'b10: used_count <= used_count + 1'b1;
                2'b01: used_count <= used_count - 1'b1;
                default: used_count <= used_count;
            endcase

            // 预填阶段不记欠载；未准备好的帧也记欠载，队首保留到后续帧。
            // 空时同拍收到的数据留待后续帧，不做旁路。
            if (frame_ce && started && !head_valid && (underflow_count != 32'hffffffff))
                underflow_count <= underflow_count + 1'b1;
            if (in_valid && !put_sample && (overflow_count != 32'hffffffff))
                overflow_count <= overflow_count + 1'b1;
        end
    end
endmodule
