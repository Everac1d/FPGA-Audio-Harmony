// 保存一段易失性的原始 PCM16 录音；所有端口均属于音频时钟域。
// DDR 请求采用 256 位 BL8 传输，地址以 32 位 DDR 字为单位。
// 仅在最后一次部分或完整突发传输完成后提交元数据。
module pcm_clip_controller #(
    parameter integer MAX_SAMPLES = 1464844,
    parameter integer PREROLL_SAMPLES = 8866,
    parameter integer TAIL_SAMPLES = 8994,
    parameter integer DRAIN_SAMPLES = 512,
    // 原有候选实现保留停止／重新开始语义；外部控制
    // 候选实现支持在精确播放位置暂停，并提供独立的重新开始命令。
    parameter integer ENHANCED_PLAYBACK = 0
) (
    input wire clk,rst_n,sample_tick,
    input wire signed [15:0] mic_pcm,
    input wire record_toggle,play_toggle,abort_play,
    input wire play_hold,play_restart,
    input wire storage_ready,storage_error,
    output wire req_valid,req_write,
    output wire [28:0] req_addr,
    output wire [255:0] req_wdata,
    input wire req_ready,rsp_valid,
    input wire [255:0] rsp_rdata,
    output wire signed [15:0] play_pcm,
    output reg [3:0] rec_state,
    output reg [20:0] record_samples,play_samples,
    output wire [20:0] record_progress,
    output wire record_valid,record_full,play_active,
    output wire play_paused,
    output reg fault
);
    localparam WAIT_DDR=0,EMPTY=1,RECORD=2,FLUSH=3,READY=4,
               PREFETCH=5,PREROLL=6,PLAY=7,TAIL=8,DRAIN=9,ERROR=10,PAUSED=11;
    reg [3:0] resume_state;
    reg restart_pending,record_pending;
    reg [20:0] captured;
    reg [255:0] pack,pending_data;
    reg [3:0] pack_count,lane;
    reg pending_write,transaction_active,transaction_write;
    reg [28:0] pending_address,next_write_address;
    reg [17:0] read_requested;
    reg [255:0] read_blocks[0:1];
    reg write_pointer,read_pointer;
    reg [1:0] block_count;
    reg [15:0] silence_count;
    reg clip_committed;
    wire [17:0] total_blocks=({1'b0,record_samples}+22'd15)>>4;
    wire playback_read=(rec_state==PREFETCH || rec_state==PREROLL || rec_state==PLAY);
    wire read_request=playback_read && read_requested<total_blocks && block_count<2;
    assign req_valid=storage_ready && !fault && !transaction_active &&
                     (pending_write || read_request);
    assign req_write=pending_write;
    assign req_addr=pending_write ? pending_address : {8'd0,read_requested,3'b000};
    assign req_wdata=pending_data;
    wire request_taken=req_valid && req_ready;
    wire read_done=rsp_valid && transaction_active && !transaction_write;
    wire enhanced_command=(ENHANCED_PLAYBACK!=0) &&
                          (play_toggle || play_restart || record_toggle || abort_play);
    wire playback_tick=sample_tick && ((ENHANCED_PLAYBACK==0) ||
                       (!play_hold && !enhanced_command));
    wire active_state=rec_state>=PREFETCH && rec_state<=DRAIN;
    wire pop_block=rec_state==PLAY && playback_tick && block_count!=0 &&
                   (lane==15 || play_samples+1'b1==record_samples);
    wire capture=rec_state==RECORD && sample_tick && !record_toggle && !abort_play;
    wire final_sample=(captured+1'b1==MAX_SAMPLES);
    reg [255:0] pack_with_sample;
    always @* begin
        pack_with_sample=pack;
        pack_with_sample[pack_count*16 +:16]=mic_pcm;
    end
    assign play_pcm=(rec_state==PLAY && block_count!=0) ?
                    $signed(read_blocks[read_pointer][lane*16 +:16]) : 16'sd0;
    assign record_valid=clip_committed && !fault;
    assign record_progress=(rec_state==RECORD || rec_state==FLUSH) ? captured : record_samples;
    assign record_full=record_valid && record_samples==MAX_SAMPLES;
    assign play_paused=(ENHANCED_PLAYBACK!=0) && rec_state==PAUSED;
    assign play_active=(rec_state>=PREROLL && rec_state<=DRAIN) || play_paused;
    always @(posedge clk) begin
        if(!rst_n) begin
            rec_state<=WAIT_DDR;record_samples<=0;play_samples<=0;captured<=0;
            pack<=0;pack_count<=0;pending_write<=0;pending_data<=0;
            pending_address<=0;next_write_address<=0;transaction_active<=0;
            transaction_write<=0;read_requested<=0;write_pointer<=0;
            read_pointer<=0;block_count<=0;lane<=0;silence_count<=0;
            clip_committed<=0;fault<=0;resume_state<=PREFETCH;restart_pending<=0;record_pending<=0;
        end else if(storage_error || fault) begin
            rec_state<=ERROR;fault<=1;clip_committed<=0;pending_write<=0;restart_pending<=0;record_pending<=0;
        end else begin
            if(request_taken) begin
                transaction_active<=1;transaction_write<=req_write;
                if(req_write) pending_write<=0;
                else read_requested<=read_requested+1'b1;
            end
            if(rsp_valid && transaction_active) transaction_active<=0;
            if(read_done) begin
                read_blocks[write_pointer]<=rsp_rdata;
                write_pointer<=~write_pointer;
            end
            if(pop_block) begin read_pointer<=~read_pointer;lane<=0;end
            case({read_done,pop_block})
                2'b10:block_count<=block_count+1'b1;
                2'b01:block_count<=block_count-1'b1;
                default:;
            endcase
            case(rec_state)
                WAIT_DDR:if(storage_ready) rec_state<=EMPTY;
                EMPTY,READY:begin
                    if(((ENHANCED_PLAYBACK==0) || !abort_play) &&
                       (record_toggle || ((ENHANCED_PLAYBACK!=0) && record_pending)) &&
                       storage_ready && !transaction_active && !pending_write) begin
                        // 按设计，重新录音会覆盖唯一一段已有录音。
                        rec_state<=RECORD;record_samples<=0;captured<=0;play_samples<=0;
                        clip_committed<=0;pack<=0;pack_count<=0;next_write_address<=0;
                        block_count<=0;read_pointer<=0;write_pointer<=0;restart_pending<=0;record_pending<=0;
                    end else if(((ENHANCED_PLAYBACK==0) || !abort_play) &&
                                (play_toggle || ((ENHANCED_PLAYBACK!=0) && restart_pending)) &&
                                record_valid && record_samples!=0 && !transaction_active) begin
                        rec_state<=PREFETCH;play_samples<=0;read_requested<=0;lane<=0;
                        block_count<=0;read_pointer<=0;write_pointer<=0;silence_count<=0;restart_pending<=0;
                    end
                end
                RECORD:begin
                    if(record_toggle || abort_play) begin
                        rec_state<=FLUSH;
                        if(pack_count!=0) begin
                            if(pending_write && !request_taken) fault<=1;
                            else begin
                                pending_write<=1;pending_data<=pack;
                                pending_address<=next_write_address;
                                next_write_address<=next_write_address+29'd8;
                                pack_count<=0;pack<=0;
                            end
                        end
                    end else if(capture) begin
                        captured<=captured+1'b1;
                        pack<=pack_with_sample;pack_count<=pack_count+1'b1;
                        if(pack_count==15 || final_sample) begin
                            if(pending_write && !request_taken) fault<=1;
                            else begin
                                pending_write<=1;pending_data<=pack_with_sample;
                                pending_address<=next_write_address;
                                next_write_address<=next_write_address+29'd8;
                                pack<=0;pack_count<=0;
                            end
                        end
                        if(final_sample) rec_state<=FLUSH;
                    end
                end
                FLUSH:if(!pending_write && !transaction_active && !request_taken) begin
                    record_samples<=captured;clip_committed<=(captured!=0);
                    rec_state<=(captured!=0) ? READY : EMPTY;
                end
                PREFETCH:begin
                    if(block_count==2 || (total_blocks==1 && block_count==1)) begin
                        rec_state<=PREROLL;silence_count<=0;
                    end
                end
                PREROLL:if(playback_tick) begin
                    if(silence_count==PREROLL_SAMPLES-1) begin rec_state<=PLAY;silence_count<=0;end
                    else silence_count<=silence_count+1'b1;
                end
                PLAY:if(playback_tick) begin
                    if(block_count==0) fault<=1;
                    else begin
                        play_samples<=play_samples+1'b1;
                        if(lane!=15) lane<=lane+1'b1;
                        if(play_samples+1'b1==record_samples) begin
                            rec_state<=TAIL;silence_count<=0;
                        end
                    end
                end
                TAIL:if(playback_tick) begin
                    if(silence_count==TAIL_SAMPLES-1) begin rec_state<=DRAIN;silence_count<=0;end
                    else silence_count<=silence_count+1'b1;
                end
                DRAIN:if(playback_tick) begin
                    if(silence_count==DRAIN_SAMPLES-1) rec_state<=READY;
                    else silence_count<=silence_count+1'b1;
                end
                PAUSED:if(ENHANCED_PLAYBACK==0)begin rec_state<=ERROR;fault<=1;end
                default:begin rec_state<=ERROR;fault<=1;end
            endcase
            // 停止或修改参数时保留录音数据。开始另一操作前，等待尚未完成的
            // 读取结束；新操作启动时丢弃旧读取结果的有效标志。
            if(ENHANCED_PLAYBACK==0)begin
                if((abort_play || play_toggle || record_toggle) && active_state)
                    rec_state<=READY;
            end else begin
                // 刚停止播放时，仍可能有一次旧 DDR 读取尚未完成。
                // 因此应记住新命令，直至旧响应接收完毕，
                // 避免无提示地丢失短按事件。
                if((rec_state==EMPTY || rec_state==READY) && record_toggle &&
                   (transaction_active || pending_write))begin
                    record_pending<=1;restart_pending<=0;
                end else if(rec_state==READY && play_toggle && !record_pending &&
                            record_valid && transaction_active)begin
                    restart_pending<=1;
                end
                // 重新开始时先结束旧会话。尚未返回的 DDR 数据
                // 正常接收，再由后续新会话的启动流程丢弃；
                // 旧响应绝不能成为新会话的第零块数据。
                if(abort_play)begin
                    restart_pending<=0;record_pending<=0;
                    if(active_state || play_paused)rec_state<=READY;
                end else if(record_toggle && (active_state || play_paused))begin
                    rec_state<=READY;restart_pending<=0;record_pending<=0;
                end else if(play_restart && !record_toggle && !record_pending && record_valid &&
                   (active_state || play_paused || rec_state==READY))begin
                    rec_state<=READY;restart_pending<=1;record_pending<=0;
                end else if(play_toggle && !record_toggle && active_state)begin
                    resume_state<=rec_state;rec_state<=PAUSED;
                end else if(play_toggle && !record_toggle && play_paused)begin
                    rec_state<=resume_state;
                end
            end
        end
    end
endmodule
