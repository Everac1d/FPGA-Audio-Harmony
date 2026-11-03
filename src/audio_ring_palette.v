// 在50MHz时钟域内根据已提交音频状态选择颜色，仅用于显示。
// 掩码位序为RGB；音量到亮度的缩放仍由sk9822_ring完成。
module audio_ring_palette(
    input wire active_source,
    input wire [1:0] active_algorithm_mode,
    input wire [1:0] active_mode,
    input wire [3:0] rec_state,
    input wire ddr_ready,
    input wire storage_fault,
    output reg [2:0] color_mask_rgb
);
    always @* begin
        if(active_source && storage_fault)color_mask_rgb=3'b100;
        else if(active_source && !ddr_ready)color_mask_rgb=3'b001;
        else if(rec_state==4'd2 || rec_state==4'd3)color_mask_rgb=3'b100;
        else if(!active_source && active_mode==2'd2)color_mask_rgb=3'b001;
        else begin
            case(active_algorithm_mode)
                2'd1:color_mask_rgb=3'b101; // 变调：品红色
                2'd2:color_mask_rgb=3'b110; // 和声：黄色
                2'd3:color_mask_rgb=3'b010; // 两个独立变调声部：绿色
                default:color_mask_rgb=3'b011; // 原声：基线青色
            endcase
        end
    end
endmodule
