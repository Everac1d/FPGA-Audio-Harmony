`timescale 1ns/1ps
module tb_algorithm_core;
    reg clk=0;always #10 clk=~clk;
    reg rst_n=0,valid=0;
    reg signed [15:0] pcm=0;
    reg [1:0] mode=0;reg signed [4:0] pitch=0;
    wire signed [15:0] out;wire out_valid;
    audio_effect_core #(.RAM_ADDR_BITS(9),.GRAIN_LOG2(7),.GUARD_SAMPLES(8)) dut(
        .clk(clk),.rst_n(rst_n),.pcm_in(pcm),.pcm_in_valid(valid),.mode(mode),
        .pitch_semitones(pitch),.pcm_out(out),.pcm_out_valid(out_valid),.pitch_second(5'sd0));
    integer fd,rc,reset_row,mm,pp,x,want,gap;
    integer expected[0:170000],due[0:170000];
    integer head=0,tail=0,cycle=0,reset_count=0;
    reg checking=1;
    always @(posedge clk) begin
        cycle=cycle+1;
        #1;
        if(checking && rst_n) begin
            if(head<tail && cycle==due[head]) begin
                if(out_valid!==1 || $signed(out)!==expected[head])
                    $fatal(1,"core row%0d cycle%0d valid%b got%0d expected%0d",head,cycle,out_valid,$signed(out),expected[head]);
                head=head+1;
            end else if(out_valid) $fatal(1,"unexpected valid cycle%0d",cycle);
        end
    end
    initial begin
        repeat(4) @(negedge clk);rst_n=1;
        fd=$fopen("sim/fixtures/core_reference.txt","r");if(!fd) $fatal(1,"missing core fixture");
        while(!$feof(fd)) begin
            rc=$fscanf(fd,"%d %d %d %d %d %d\n",reset_row,mm,pp,x,want,gap);
            if(rc==6) begin
                if(reset_row) begin
                    if(head!=tail) $fatal(1,"pending output before segment reset");
                    @(negedge clk);rst_n=0;valid=0;
                    repeat(2) @(negedge clk);rst_n=1;reset_count=reset_count+1;
                end
                @(negedge clk);mode=mm;pitch=pp;pcm=x;valid=1;
                expected[tail]=want;due[tail]=cycle+18;tail=tail+1;
                @(negedge clk);valid=0;
                repeat(gap-2) @(negedge clk);
            end
        end
        repeat(40) @(negedge clk);
        if(head!=tail) $fatal(1,"missing core output");
        // Reset cancels a RAM transaction halfway through its pipeline.
        checking=0;valid=1;@(negedge clk);valid=0;
        repeat(6) @(negedge clk);rst_n=0;
        repeat(2) @(negedge clk);rst_n=1;
        repeat(24) begin @(negedge clk);if(out_valid) $fatal(1,"stale valid after reset");end
        // Documented out-of-contract burst: fault mutes until a reset.
        mode=0;pcm=12345;valid=1;@(negedge clk);valid=1;@(negedge clk);valid=0;
        repeat(25) begin @(negedge clk);if(out_valid && out!=0) $fatal(1,"busy input not muted");end
        if(!dut.algorithm.fault) $fatal(1,"missing busy fault");
        rst_n=0;repeat(2) @(negedge clk);rst_n=1;
        mode=0;pcm=-23456;valid=1;@(negedge clk);valid=0;
        repeat(17) @(negedge clk);
        if(!out_valid || $signed(out)!=-23456) $fatal(1,"fault reset recovery");
        $display("PASS CORE: independent_vectors=%0d resets=%0d Q20 all25pitches clamp invalidmode livecontrols_ignored multiwrap gap32_to1024 valid17 reset_pending busy_mute_recover",head,reset_count);
        $finish;
    end
endmodule
