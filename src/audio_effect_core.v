// 音频算法核心，供原声、变调及和声处理路径集成。
// 此处不处理板级增益、界面、串口、功放或FIFO控制。
// DYNAMIC_CONFIG=0保留复位时锁存的原有参数；使用外接
// 回放界面时，DYNAMIC_CONFIG=1在每次接收样本时捕获一次参数；
// 静音参数切换或暂停期间保留历史数据与相位。
module audio_effect_core #(
    parameter integer RAM_ADDR_BITS=14,
    parameter integer GRAIN_LOG2=13,
    parameter integer GUARD_SAMPLES=32,
    parameter integer DYNAMIC_CONFIG=0,
    parameter integer DUAL_VOICE_ENABLE=0
) (
    input wire clk,rst_n,
    input wire signed [15:0] pcm_in,
    input wire pcm_in_valid,
    input wire [1:0] mode,
    input wire signed [4:0] pitch_semitones,
    output wire signed [15:0] pcm_out,
    output wire pcm_out_valid,
    input wire signed [4:0] pitch_second
);
    wire signed [15:0] first_out;
    wire first_valid;
    wire [1:0] first_mode=((DUAL_VOICE_ENABLE!=0)&&(mode==2'd3)) ? 2'd1 : mode;
    pcm_dual_read_pitch #(.RAM_ADDR_BITS(RAM_ADDR_BITS),.GRAIN_LOG2(GRAIN_LOG2),
        .GUARD_SAMPLES(GUARD_SAMPLES),.DYNAMIC_CONFIG(DYNAMIC_CONFIG)) algorithm (
        .clk(clk),.rst_n(rst_n),.pcm_in(pcm_in),.in_valid(pcm_in_valid),
        .mode(first_mode),.pitch_semitones(pitch_semitones),
        .pcm_out(first_out),.out_valid(first_valid)
    );
    generate if(DUAL_VOICE_ENABLE!=0)begin: dual_voice
        // 第二声部在mode3以外也接收每个输入，因此两组历史数据
        // 与运算流水线共享相同的采样位置和保持状态。
        // 单个算法内部的两个交叉淡化读头仍只构成一个声部；
        // 此独立算法提供第二组变调比率与相位。
        wire signed [15:0] second_out;
        wire second_valid;
        reg job_dual,dual_configured,configured_dual;
        always @(posedge clk)begin
            if(!rst_n)begin job_dual<=1'b0;dual_configured<=1'b0;configured_dual<=1'b0;end
            else if(pcm_in_valid)begin
                dual_configured<=1'b1;
                if(!dual_configured)configured_dual<=(mode==2'd3);
                job_dual<=(DYNAMIC_CONFIG!=0) ? (mode==2'd3) :
                    (dual_configured ? configured_dual : (mode==2'd3));
            end
        end
        pcm_dual_read_pitch #(.RAM_ADDR_BITS(RAM_ADDR_BITS),.GRAIN_LOG2(GRAIN_LOG2),
            .GUARD_SAMPLES(GUARD_SAMPLES),.DYNAMIC_CONFIG(DYNAMIC_CONFIG)) second_algorithm(
            .clk(clk),.rst_n(rst_n),.pcm_in(pcm_in),.in_valid(pcm_in_valid),
            .mode(2'd1),.pitch_semitones(pitch_second),
            .pcm_out(second_out),.out_valid(second_valid));
        wire signed [16:0] sum=$signed({first_out[15],first_out})+
                                $signed({second_out[15],second_out});
        wire signed [16:0] mean=sum/17'sd2;
        assign pcm_out=job_dual ? mean[15:0] : first_out;
        assign pcm_out_valid=first_valid&&second_valid;
    end else begin: single_voice
        assign pcm_out=first_out;
        assign pcm_out_valid=first_valid;
    end endgenerate
endmodule
