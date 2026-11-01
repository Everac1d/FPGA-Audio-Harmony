`timescale 1ns/1ps
// Capacity/address/PCM test: the REAL shipping 30-second sample limit is used.
// Only sample spacing and zero-roll durations are accelerated. This does not
// measure real audio timing, DSP tail length, DDR PHY behavior, or board sound.
module tb_clip_capacity;
    localparam integer CAPACITY=1464844;
    localparam integer BLOCKS=(CAPACITY+15)/16;
    localparam integer LAST_ADDRESS=(BLOCKS-1)*8;
    localparam integer PRE=7,POST=9,DRAIN=3;
    reg clk=0;
    always #10 clk=~clk;
    reg rst_n=0,record_toggle=0,play_toggle=0,abort_play=0;
    reg storage_ready=1,storage_error=0;
    reg [3:0] tick_divider=0;
    always @(posedge clk) begin
        if(!rst_n) tick_divider<=0;
        else tick_divider<=tick_divider+1'b1;
    end
    wire sample_tick=(tick_divider==15);
    integer capture_index=0;
    reg [31:0] sample_seed=32'hc7a48e31;
    function automatic signed [15:0] expected_sample(input integer index,input [31:0] seed);
        reg [31:0] mixed;
        begin
            mixed=(index*32'h045d9f3b) ^ (index>>11) ^ seed;
            expected_sample=mixed[15:0]^mixed[31:16];
        end
    endfunction
    wire signed [15:0] mic_pcm=expected_sample(capture_index,sample_seed);
    wire req_valid,req_write,req_ready,rsp_valid;
    wire [28:0] req_addr;
    wire [255:0] req_wdata;
    reg [255:0] rsp_rdata=0;
    reg response=0;
    wire signed [15:0] play_pcm;
    wire [3:0] rec_state;
    wire [20:0] record_samples,record_progress,play_samples;
    wire record_valid,record_full,play_active,fault;
    pcm_clip_controller #(.MAX_SAMPLES(CAPACITY),.PREROLL_SAMPLES(PRE),
        .TAIL_SAMPLES(POST),.DRAIN_SAMPLES(DRAIN)) dut(
        .clk(clk),.rst_n(rst_n),.sample_tick(sample_tick),.mic_pcm(mic_pcm),
        .record_toggle(record_toggle),.play_toggle(play_toggle),.abort_play(abort_play),
        .storage_ready(storage_ready),.storage_error(storage_error),
        .req_valid(req_valid),.req_write(req_write),.req_addr(req_addr),.req_wdata(req_wdata),
        .req_ready(req_ready),.rsp_valid(rsp_valid),.rsp_rdata(rsp_rdata),
        .play_pcm(play_pcm),.rec_state(rec_state),.record_samples(record_samples),
        .play_samples(play_samples),.record_progress(record_progress),.record_valid(record_valid),
        .record_full(record_full),.play_active(play_active),.fault(fault));

    reg [255:0] memory[0:BLOCKS-1];
    reg busy=0,job_write;
    reg [28:0] job_address;
    reg [255:0] job_data;
    reg [4:0] delay_count=0;
    reg [31:0] random_state=32'h7985be21;
    integer writes_requested=0,writes_completed=0,reads_requested=0,reads_completed=0;
    integer next_write_block=0,next_read_block=0;
    integer highest_write_address=0,highest_read_address=0;
    assign req_ready=!busy && !response && (random_state[0] || random_state[1]);
    assign rsp_valid=response;
    always @(posedge clk) begin
        response<=0;
        if(!rst_n) begin
            busy<=0;delay_count<=0;random_state<=32'h7985be21;
        end else begin
            random_state<={random_state[30:0],random_state[31]^random_state[21]^random_state[1]^random_state[0]};
            if(req_valid && req_ready) begin
                if(req_addr[2:0]!=0 || req_addr>LAST_ADDRESS)
                    $fatal(1,"30-second DDR address outside aligned clip range: %0d",req_addr);
                busy<=1;job_write<=req_write;job_address<=req_addr;job_data<=req_wdata;
                delay_count<=2+(random_state[8:4]%13);
                if(req_write) begin
                    if(req_addr!=next_write_block*8)
                        $fatal(1,"nonsequential/duplicate write address got=%0d expected=%0d",req_addr,next_write_block*8);
                    next_write_block<=next_write_block+1;writes_requested<=writes_requested+1;
                    if(req_addr>highest_write_address)highest_write_address<=req_addr;
                end else begin
                    if(req_addr!=next_read_block*8)
                        $fatal(1,"nonsequential/duplicate read address got=%0d expected=%0d",req_addr,next_read_block*8);
                    next_read_block<=next_read_block+1;reads_requested<=reads_requested+1;
                    if(req_addr>highest_read_address)highest_read_address<=req_addr;
                end
            end else if(busy) begin
                if(delay_count==0) begin
                    if(job_write) begin
                        memory[job_address>>3]<=job_data;writes_completed<=writes_completed+1;
                    end else begin
                        rsp_rdata<=memory[job_address>>3];reads_completed<=reads_completed+1;
                    end
                    response<=1;busy<=0;
                end else delay_count<=delay_count-1'b1;
            end
        end
    end

    reg check_playback=0;
    integer checked_index=0,total_compared=0,pre_count=0,post_count=0,drain_count=0;
    always @(posedge clk) begin
        if(rst_n && fault) $fatal(1,"unexpected clip fault state=%0d captured=%0d position=%0d",rec_state,record_progress,play_samples);
        if(rst_n && rec_state==2 && sample_tick && !record_toggle && !abort_play) begin
            if(record_progress!=capture_index) $fatal(1,"record progress mismatch at %0d",capture_index);
            capture_index<=capture_index+1;
        end
        if(rst_n && check_playback && sample_tick) begin
            case(rec_state)
                6:begin
                    if(play_pcm!==16'sd0)$fatal(1,"nonzero preroll");
                    pre_count<=pre_count+1;
                end
                7:begin
                    if(checked_index>=record_samples)$fatal(1,"extra stale sample beyond recorded length");
                    if(play_samples!=checked_index)$fatal(1,"play progress skipped/duplicated at %0d",checked_index);
                    if(play_pcm!==expected_sample(checked_index,sample_seed))
                        $fatal(1,"bit exact capacity mismatch index=%0d expected=%0d actual=%0d",checked_index,expected_sample(checked_index,sample_seed),play_pcm);
                    checked_index<=checked_index+1;total_compared<=total_compared+1;
                end
                8:begin
                    if(play_pcm!==16'sd0)$fatal(1,"nonzero tail");
                    post_count<=post_count+1;
                end
                9:begin
                    if(play_pcm!==16'sd0)$fatal(1,"nonzero drain");
                    drain_count<=drain_count+1;
                end
                default:;
            endcase
        end
    end
    task command(input integer which);
        begin
            @(negedge clk);
            while(sample_tick) @(negedge clk);
            record_toggle=(which==0);play_toggle=(which==1);abort_play=(which==2);
            @(negedge clk);record_toggle=0;play_toggle=0;abort_play=0;
        end
    endtask
    task await_ready;
        integer timeout;
        begin
            timeout=0;
            while(rec_state!=4 && rec_state!=1) begin
                @(negedge clk);timeout=timeout+1;
                if(timeout>2000)$fatal(1,"flush/stop timeout state=%0d",rec_state);
            end
            while(dut.transaction_active || busy || response) @(negedge clk);
        end
    endtask
    task start_record(input [31:0] seed);
        begin
            @(negedge clk);sample_seed=seed;capture_index=0;next_write_block=0;
            command(0);
            if(rec_state!=2 || record_valid)$fatal(1,"new capture not started/old clip still valid");
        end
    endtask
    task start_play;
        begin
            @(negedge clk);next_read_block=0;checked_index=0;
            pre_count=0;post_count=0;drain_count=0;check_playback=1;
            command(1);
            if(rec_state!=5)$fatal(1,"playback did not enter prefetch");
        end
    endtask
    task finish_play(input integer count);
        integer timeout;
        begin
            timeout=0;
            while(rec_state!=4) begin
                @(negedge clk);timeout=timeout+1;
                if(timeout>(count+PRE+POST+DRAIN+100)*16)$fatal(1,"playback length timeout state=%0d",rec_state);
            end
            check_playback=0;
            if(checked_index!=count || play_samples!=count || pre_count!=PRE || post_count!=POST || drain_count!=DRAIN)
                $fatal(1,"playback length/roll mismatch pcm=%0d pos=%0d pre=%0d tail=%0d drain=%0d",checked_index,play_samples,pre_count,post_count,drain_count);
            await_ready;
        end
    endtask
    integer full_reads_before,full_writes_before,short_writes_before,abort_length;
    initial begin
        repeat(6)@(negedge clk);rst_n=1;
        repeat(6)@(negedge clk);
        if(rec_state!=1 || record_valid)$fatal(1,"expected empty after reset");
        full_writes_before=writes_completed;
        start_record(32'hc7a48e31);
        while(rec_state==2) @(negedge clk);
        if(rec_state!=3 || record_valid || capture_index!=CAPACITY)$fatal(1,"automatic full stop/commit boundary");
        await_ready;
        if(record_samples!=CAPACITY || record_progress!=CAPACITY || !record_valid || !record_full)
            $fatal(1,"30-second committed metadata invalid len=%0d",record_samples);
        if(writes_completed-full_writes_before!=BLOCKS || next_write_block!=BLOCKS || highest_write_address!=LAST_ADDRESS)
            $fatal(1,"30-second write coverage mismatch blocks=%0d max_addr=%0d",writes_completed-full_writes_before,highest_write_address);
        if(memory[BLOCKS-1][255:192]!==64'd0)$fatal(1,"30-second partial final block padding not zero");
        if(memory[BLOCKS-1][191:176]!==expected_sample(CAPACITY-1,sample_seed))$fatal(1,"last recorded sample lost");
        $display("MEASURE CLIP_CAPACITY capture_samples=%0d blocks=%0d last_app_address=%0d valid_last_lanes=12 zero_last_lanes=4 bytes=%0d actual_duration_s=30.00000512",CAPACITY,BLOCKS,LAST_ADDRESS,CAPACITY*2);
        full_reads_before=reads_completed;
        start_play;finish_play(CAPACITY);
        if(reads_completed-full_reads_before!=BLOCKS || highest_read_address!=LAST_ADDRESS)
            $fatal(1,"30-second read coverage mismatch reads=%0d max_addr=%0d",reads_completed-full_reads_before,highest_read_address);
        $display("MEASURE CLIP_CAPACITY full_bit_exact_samples=%0d read_blocks=%0d",checked_index,reads_completed-full_reads_before);

        // A source/configuration abort retains the full recording, including
        // its committed length, even when a prefetch is still in flight.
        start_play;
        while(checked_index<23) @(negedge clk);
        command(2);check_playback=0;abort_length=checked_index;await_ready;
        if(!record_valid || !record_full || record_samples!=CAPACITY || abort_length<23 || abort_length>=CAPACITY)
            $fatal(1,"source abort deleted/changed full recording");

        // Short destructive overwrite must hide the old 30-second tail and
        // zero the partial last block; the new clip is replayed twice exactly.
        short_writes_before=writes_completed;
        start_record(32'h1982fa5d);
        while(capture_index<37) @(negedge clk);
        command(0);await_ready;
        if(record_samples!=37 || !record_valid || record_full || writes_completed-short_writes_before!=3)
            $fatal(1,"short overwrite metadata/burst count incorrect");
        if(memory[2][255:80]!==176'd0)$fatal(1,"short overwrite exposed stale final-block lanes");
        start_play;finish_play(37);
        start_play;finish_play(37);
        if(writes_requested!=writes_completed || reads_requested!=reads_completed)
            $fatal(1,"unanswered storage operation at test end");
        $display("PASS CLIP_CAPACITY: max_samples=%0d full_bit_exact_samples=%0d total_bit_exact_samples=%0d full_blocks=%0d final_address=%0d source_abort_preserved short_overwrite=37 repeat_short=2 accelerated_tick_clocks=16 reduced_roll_only",CAPACITY,CAPACITY,total_compared,BLOCKS,LAST_ADDRESS);
        $finish;
    end
    initial begin #(64'd3000000000);$fatal(1,"capacity test watchdog");end
endmodule
