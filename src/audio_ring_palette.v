// Display-only selection from committed audio states in the 50 MHz domain.
// Mask bits are RGB; sound-level scaling remains in sk9822_ring.
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
                2'd1:color_mask_rgb=3'b101; // pitch: magenta
                2'd2:color_mask_rgb=3'b110; // harmony: yellow
                2'd3:color_mask_rgb=3'b010; // two independent shifted voices: green
                default:color_mask_rgb=3'b011; // original: baseline cyan
            endcase
        end
    end
endmodule
