// 模式 0：当前原声逐位直通；模式 1：效果声；模式 2：（对齐原声＋效果声）／2。
// 使用有符号 17 位求和，除法向零截断，随后应用 Q15 启动包络。
// 模式 3 为固定延迟对齐的原声，并应用相同启动包络；通过饱和处理和对称舍入避免符号回绕。
// 每个时钟输入一个样本；输出延迟为两个时钟沿。
module pcm_harmony_voice_mixer (
    input wire clk,rst_n,in_valid,
    input wire [1:0] mode,
    input wire signed [15:0] direct_dry,aligned_dry,wet,
    input wire [15:0] wet_gain_q15,
    output reg signed [15:0] pcm_out,
    output reg out_valid
);
    reg [1:0] valid_pipe;
    reg signed [16:0] mix_value;
    reg [15:0] gain;
    reg signed [33:0] scaled;
    wire signed [16:0] sum = $signed({aligned_dry[15],aligned_dry})+
                                  $signed({wet[15],wet});
    function signed [15:0] saturated_q15;
        input signed [33:0] value;
        reg signed [33:0] result;
        begin
            if(value < 0) result = -(((-value)+34'sd16384) >>> 15);
            else result = (value+34'sd16384) >>> 15;
            if(result > 32767) saturated_q15=16'sh7fff;
            else if(result < -32768) saturated_q15=16'sh8000;
            else saturated_q15=result[15:0];
        end
    endfunction
    always @(posedge clk) begin
        if(!rst_n) begin
            valid_pipe<=0;out_valid<=0;pcm_out<=0;mix_value<=0;gain<=0;scaled<=0;
        end else begin
            valid_pipe<={valid_pipe[0],in_valid};
            out_valid<=valid_pipe[1];
            if(in_valid) begin
                gain <= (mode==0) ? 16'd32768 :
                    ((wet_gain_q15>16'd32768) ? 16'd32768 : wet_gain_q15);
                case(mode)
                    0:mix_value<=$signed({direct_dry[15],direct_dry});
                    1:mix_value<=$signed({wet[15],wet});
                    2:mix_value<=sum/17'sd2;
                    3:mix_value<=$signed({aligned_dry[15],aligned_dry});
                    default:mix_value<=0;
                endcase
            end
            if(valid_pipe[0]) scaled<=mix_value*$signed({1'b0,gain});
            if(valid_pipe[1]) pcm_out<=saturated_q15(scaled);
        end
    end
endmodule
