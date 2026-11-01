// External panel A: four active-low buttons and two quadrature encoders.
// All asynchronous contacts are synchronized and filtered in the 50MHz domain.
// No contact is used as a clock. Button commands are dispatched on release.
module audio_external_controls #(
    parameter integer DEBOUNCE_CYCLES=1000000,
    parameter integer LONG_RESET_CYCLES=100000000,
    parameter integer LONG_REPLAY_CYCLES=40000000,
    parameter integer LONG_DIAG_CYCLES=100000000,
    parameter integer LONG_PITCH_CYCLES=100000000,
    parameter integer DUAL_VOICE_ENABLE=0,
    parameter integer ENCODER_FILTER_CYCLES=50000,
    parameter integer GAIN_REVERSE=0,
    parameter integer PITCH_REVERSE=0
) (
    input wire clk,rst_n,
    input wire [3:0] button_n,
    input wire enc_gain_sw_n,enc_gain_clk,enc_gain_dt,
    input wire enc_pitch_sw_n,enc_pitch_clk,enc_pitch_dt,
    output reg record_source,
    output reg [1:0] live_mode,
    // Tenths of unity: 10=1.0x .. 30=3.0x.
    output reg [4:0] gain_index,
    output reg [1:0] algorithm_mode,
    output wire signed [4:0] pitch_semitones,
    output reg signed [4:0] pitch_second,
    output reg pitch_voice,
    output reg record_toggle,play_toggle,play_restart,source_changed,reset_request
);
    wire [5:0] contacts={enc_pitch_sw_n,enc_gain_sw_n,button_n};
    // Normal effects keep their own pitch. Entering/leaving dual voice never
    // overwrites any of the three pitch settings or the selected dual voice.
    reg signed [4:0] normal_pitch,dual_first;
    wire dual_selected=(DUAL_VOICE_ENABLE!=0) && algorithm_mode==2'd3;
    assign pitch_semitones=dual_selected ? dual_first : normal_pitch;
    (* syn_preserve=1, ASYNC_REG="TRUE" *) reg [5:0] contact_meta,contact_sync;
    reg [5:0] contact_stable,contact_previous;
    reg [31:0] debounce_count[0:5];
    integer i;
    always @(posedge clk) begin
        if(!rst_n) begin
            contact_meta<=6'b111111;contact_sync<=6'b111111;
            contact_stable<=6'b111111;contact_previous<=6'b111111;
            for(i=0;i<6;i=i+1)debounce_count[i]<=0;
        end else begin
            contact_meta<=contacts;contact_sync<=contact_meta;
            contact_previous<=contact_stable;
            for(i=0;i<6;i=i+1) begin
                if(contact_sync[i]==contact_stable[i])debounce_count[i]<=0;
                else if(debounce_count[i]>=DEBOUNCE_CYCLES-1)begin
                    contact_stable[i]<=contact_sync[i];debounce_count[i]<=0;
                end else debounce_count[i]<=debounce_count[i]+1'b1;
            end
        end
    end
    wire [5:0] released=contact_stable & ~contact_previous;
    // A diagnostic chord owns both SW releases, even if it is too short or
    // cancelled. Require continuous debounced overlap, then wait until BOTH
    // shafts have been released. A source change cancels until both are up.
    wire diag_both_down=!contact_stable[4] && !contact_stable[5];
    wire diag_both_up=contact_stable[4] && contact_stable[5];
    reg diag_session,diag_qualified,diag_cancelled;
    reg [31:0] diag_held;
    wire diag_block=diag_session || diag_both_down;
    wire diag_enter=diag_session && diag_qualified && !diag_cancelled &&
        diag_both_up && !record_source && !released[0];
    always @(posedge clk)begin
        if(!rst_n)begin
            diag_session<=0;diag_qualified<=0;diag_cancelled<=0;diag_held<=0;
        end else if(diag_session)begin
            if(record_source || released[0])diag_cancelled<=1;
            if(diag_both_up)begin
                diag_session<=0;diag_qualified<=0;diag_cancelled<=0;diag_held<=0;
            end else if(!diag_both_down)begin
                diag_held<=0;
                if(!diag_qualified)diag_cancelled<=1;
            end else if(!diag_qualified && !diag_cancelled && !record_source && !released[0])begin
                if(diag_held>=LONG_DIAG_CYCLES-1)diag_qualified<=1;
                else diag_held<=diag_held+1'b1;
            end
        end else if(diag_both_down)begin
            diag_session<=1;diag_held<=1;
            diag_qualified<=(LONG_DIAG_CYCLES<=1);
            diag_cancelled<=record_source || released[0];
        end
    end
    reg [31:0] reset_held,replay_held,pitch_held;
    reg reset_long,replay_long,pitch_long;
    always @(posedge clk)begin
        if(!rst_n)begin
            reset_held<=0;replay_held<=0;reset_long<=0;replay_long<=0;
            pitch_held<=0;pitch_long<=0;
        end else begin
            if(contact_stable[0])begin reset_held<=0;reset_long<=0;end
            else if(!reset_long)begin
                if(reset_held>=LONG_RESET_CYCLES-1)reset_long<=1;
                else reset_held<=reset_held+1'b1;
            end
            if(contact_stable[3])begin replay_held<=0;replay_long<=0;end
            else if(!replay_long)begin
                if(replay_held>=LONG_REPLAY_CYCLES-1)replay_long<=1;
                else replay_held<=replay_held+1'b1;
            end
            if(contact_stable[5] || diag_block)begin pitch_held<=0;pitch_long<=0;end
            else if(!pitch_long)begin
                if(pitch_held>=LONG_PITCH_CYCLES-1)pitch_long<=1;
                else pitch_held<=pitch_held+1'b1;
            end
        end
    end
    wire gain_up,gain_down,pitch_up,pitch_down;
    audio_panel_encoder #(.FILTER_CYCLES(ENCODER_FILTER_CYCLES),.REVERSE(GAIN_REVERSE)) gain_encoder(
        .clk(clk),.rst_n(rst_n),.contact_clk(enc_gain_clk),.contact_dt(enc_gain_dt),
        .step_up(gain_up),.step_down(gain_down));
    audio_panel_encoder #(.FILTER_CYCLES(ENCODER_FILTER_CYCLES),.REVERSE(PITCH_REVERSE)) pitch_encoder(
        .clk(clk),.rst_n(rst_n),.contact_clk(enc_pitch_clk),.contact_dt(enc_pitch_dt),
        .step_up(pitch_up),.step_down(pitch_down));
    always @(posedge clk)begin
        if(!rst_n)begin
            record_source<=0;live_mode<=0;gain_index<=5'd10;
            algorithm_mode<=0;normal_pitch<=0;dual_first<=5'sd4;
            pitch_second<=5'sd7;pitch_voice<=0;
            record_toggle<=0;play_toggle<=0;play_restart<=0;
            source_changed<=0;reset_request<=0;
        end else begin
            record_toggle<=0;play_toggle<=0;play_restart<=0;
            source_changed<=0;reset_request<=0;
            if(released[0] && reset_long)reset_request<=1;
            else begin
                if(released[0])begin
                    record_source<=!record_source;live_mode<=0;source_changed<=1;
                end else if(diag_enter)live_mode<=2;
                else if(released[4] && !record_source && !diag_block)
                    live_mode<=(live_mode==0) ? 1 : 0;
                if(released[1])begin
                    if(DUAL_VOICE_ENABLE!=0)algorithm_mode<=algorithm_mode+1'b1;
                    else algorithm_mode<=(algorithm_mode==2) ? 0 : algorithm_mode+1'b1;
                end
                if(released[2] && record_source)record_toggle<=1;
                if(released[3] && record_source)begin
                    if(replay_long)play_restart<=1;
                    else play_toggle<=1;
                end
                if(gain_up && gain_index<5'd30)gain_index<=gain_index+5'd1;
                else if(gain_down && gain_index>5'd10)gain_index<=gain_index-5'd1;
                if(released[5] && !diag_block)begin
                    if(dual_selected)begin
                        if(pitch_long)begin
                            if(pitch_voice)pitch_second<=0;
                            else dual_first<=0;
                        end else pitch_voice<=!pitch_voice;
                    end else normal_pitch<=0;
                end else if(dual_selected)begin
                    if(pitch_voice)begin
                        if(pitch_up && pitch_second<5'sd12)pitch_second<=pitch_second+5'sd1;
                        else if(pitch_down && pitch_second> -5'sd12)pitch_second<=pitch_second-5'sd1;
                    end else begin
                        if(pitch_up && dual_first<5'sd12)dual_first<=dual_first+5'sd1;
                        else if(pitch_down && dual_first> -5'sd12)dual_first<=dual_first-5'sd1;
                    end
                end else begin
                    if(pitch_up && normal_pitch<5'sd12)normal_pitch<=normal_pitch+5'sd1;
                    else if(pitch_down && normal_pitch> -5'sd12)normal_pitch<=normal_pitch-5'sd1;
                end
            end
        end
    end
endmodule

// One output event per complete 11 -> 01 -> 00 -> 10 -> 11 cycle.
// The reverse sequence decrements. Reversals cancel partial travel; a diagonal
// transition discards the partial cycle and waits for the 11 anchor again.
// The common 4-edge/full-pulse mechanical encoder is expected. REVERSE changes
// the electrical direction without changing the panel parameter semantics.
module audio_panel_encoder #(
    parameter integer FILTER_CYCLES=50000,
    parameter integer REVERSE=0
) (
    input wire clk,rst_n,contact_clk,contact_dt,
    output reg step_up,step_down
);
    (* syn_preserve=1, ASYNC_REG="TRUE" *) reg [1:0] phase_meta,phase_sync;
    reg [1:0] candidate,stable,previous;
    reg [31:0] filter_count;
    reg signed [3:0] travel;
    reg armed,filtered_once,decoder_initialized;
    reg signed [3:0] delta;
    reg legal;
    always @*begin
        delta=0;legal=1;
        case({previous,stable})
            4'b1101,4'b0100,4'b0010,4'b1011:delta=1;
            4'b1110,4'b1000,4'b0001,4'b0111:delta=-1;
            default:legal=0;
        endcase
    end
    always @(posedge clk)begin
        if(!rst_n)begin
            phase_meta<=2'b11;phase_sync<=2'b11;candidate<=2'b11;
            stable<=2'b11;previous<=2'b11;filter_count<=0;
            travel<=0;armed<=0;filtered_once<=0;decoder_initialized<=0;
            step_up<=0;step_down<=0;
        end else begin
            phase_meta<={contact_clk,contact_dt};phase_sync<=phase_meta;
            step_up<=0;step_down<=0;
            // Filter the whole phase pair so two independently delayed contacts
            // cannot manufacture a legal transition out of an illegal jump.
            if(phase_sync!=candidate)begin
                candidate<=phase_sync;filter_count<=1;
                if(FILTER_CYCLES<=1)begin stable<=phase_sync;filtered_once<=1;end
            end else if(candidate!=stable || !filtered_once)begin
                if(filter_count>=FILTER_CYCLES-1)begin
                    stable<=candidate;filter_count<=0;filtered_once<=1;
                end
                else filter_count<=filter_count+1'b1;
            end else filter_count<=0;
            if(!decoder_initialized && filtered_once)begin
                // Learn the real phase after reset. A held/partly turned shaft
                // must reach 11 before a new complete cycle can count.
                previous<=stable;travel<=0;armed<=(stable==2'b11);decoder_initialized<=1;
            end else if(decoder_initialized && stable!=previous)begin
                previous<=stable;
                if(!armed)begin
                    travel<=0;
                    if(stable==2'b11)armed<=1;
                end else if(!legal)begin
                    travel<=0;armed<=(stable==2'b11);
                end else if(stable==2'b11)begin
                    if(travel+delta==4'sd4)begin
                        if(REVERSE)step_down<=1;else step_up<=1;
                    end else if(travel+delta== -4'sd4)begin
                        if(REVERSE)step_up<=1;else step_down<=1;
                    end
                    travel<=0;
                end else travel<=travel+delta;
            end
        end
    end
endmodule
