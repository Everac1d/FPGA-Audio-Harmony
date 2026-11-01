// Standard I2S microphone: 24 signed data bits in a 32-BCLK slot.
// Slot position 0 is the I2S delay bit; positions 1..24 are MSB..LSB.
module mic_i2s_rx (
    input wire clk,
    input wire rst_n,
    input wire mic_sd,
    input wire sample_ce,
    input wire [5:0] bit_pos,
    output reg signed [15:0] pcm_left = 16'sd0,
    output reg signed [15:0] pcm_right = 16'sd0,
    output reg left_valid = 1'b0,
    output reg right_valid = 1'b0
);
    // The data is asynchronous to the 50 MHz system clock, even though its
    // bit clock is generated locally. Sample well after the BCLK rising edge.
    (* syn_preserve = 1, ASYNC_REG = "TRUE" *) reg sd_meta = 1'b0;
    (* syn_preserve = 1, ASYNC_REG = "TRUE" *) reg sd_sync = 1'b0;
    reg [23:0] shift_data = 24'd0;
    wire [23:0] complete_word = {shift_data[22:0], sd_sync};
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sd_meta <= 1'b0;
            sd_sync <= 1'b0;
            shift_data <= 24'd0;
            pcm_left <= 16'sd0;
            pcm_right <= 16'sd0;
            left_valid <= 1'b0;
            right_valid <= 1'b0;
        end else begin
            sd_meta <= mic_sd;
            sd_sync <= sd_meta;
            left_valid <= 1'b0;
            right_valid <= 1'b0;
            if (sample_ce && (bit_pos[4:0] >= 5'd1) &&
                             (bit_pos[4:0] <= 5'd24)) begin
                shift_data <= complete_word;
                if (bit_pos[4:0] == 5'd24) begin
                    if (!bit_pos[5]) begin
                        pcm_left <= complete_word[23:8];
                        left_valid <= 1'b1;
                    end else begin
                        pcm_right <= complete_word[23:8];
                        right_valid <= 1'b1;
                    end
                end
            end
        end
    end
endmodule
