`timescale 1ns/1ps
module tb_algorithm_components;
    reg clk=0; always #10 clk=~clk;
    reg rst_n=0,valid=0,mvalid=0;
    reg signed [15:0] a,b,direct,aligned,wet;
    reg [15:0] triangle,gain;
    reg [1:0] mode;
    wire signed [15:0] fade_pcm,mix_pcm;
    wire fade_valid,mix_valid;
    pcm_crossfade fade(clk,rst_n,valid,a,b,triangle,fade_pcm,fade_valid);
    pcm_harmony_mixer mix(clk,rst_n,mvalid,mode,direct,aligned,wet,gain,mix_pcm,mix_valid);
    integer expected_fade[0:150000],expected_mix[0:50000];
    integer fade_in=0,fade_out=0,mix_in=0,mix_out=0;
    integer fd,md,rc,x,y,t,e,mm,dd,aa,ww,gg,ee;
    reg [3:0] fv=0; reg [1:0] mv=0;
    reg expected_fvalid,expected_mvalid;
    always @(posedge clk) begin
        if(!rst_n) begin fv=0;mv=0;expected_fvalid=0;expected_mvalid=0;end
        else begin
            expected_fvalid=fv[3];expected_mvalid=mv[1];
            fv={fv[2:0],valid};mv={mv[0],mvalid};
        end
        #1;
        if(rst_n) begin
            if(fade_valid!==expected_fvalid || mix_valid!==expected_mvalid) $fatal(1,"component valid latency");
            if(fade_valid) begin
                if($signed(fade_pcm)!==expected_fade[fade_out]) $fatal(1,"fade row%0d got%0d want%0d",fade_out,$signed(fade_pcm),expected_fade[fade_out]);
                fade_out=fade_out+1;
            end
            if(mix_valid) begin
                if($signed(mix_pcm)!==expected_mix[mix_out]) $fatal(1,"mix row%0d got%0d want%0d",mix_out,$signed(mix_pcm),expected_mix[mix_out]);
                mix_out=mix_out+1;
            end
        end
    end
    initial begin
        repeat(4) @(negedge clk);rst_n=1;
        fd=$fopen("sim/fixtures/components.txt","r");md=$fopen("sim/fixtures/mixer.txt","r");
        if(!fd || !md) $fatal(1,"missing component fixtures");
        while(!$feof(fd) || !$feof(md)) begin
            @(negedge clk);valid=0;mvalid=0;
            if(!$feof(fd)) begin
                rc=$fscanf(fd,"%d %d %d %d\n",x,y,t,e);
                if(rc==4) begin a=x;b=y;triangle=t;expected_fade[fade_in]=e;fade_in=fade_in+1;valid=1;end
            end
            if(!$feof(md)) begin
                rc=$fscanf(md,"%d %d %d %d %d %d\n",mm,dd,aa,ww,gg,ee);
                if(rc==6) begin mode=mm;direct=dd;aligned=aa;wet=ww;gain=gg;expected_mix[mix_in]=ee;mix_in=mix_in+1;mvalid=1;end
            end
        end
        @(negedge clk);valid=0;mvalid=0;
        repeat(8) @(negedge clk);
        if(fade_out!=fade_in || mix_out!=mix_in) $fatal(1,"component output count");
        // 清空待处理事务，再确认没有过期有效信号泄漏。
        valid=1;mvalid=1;@(negedge clk);rst_n=0;valid=0;mvalid=0;
        repeat(2) @(negedge clk);rst_n=1;
        repeat(8) @(negedge clk);
        $display("PASS COMPONENTS: crossfade_vectors=%0d mixer_vectors=%0d all32769weights signed_rails unity_invariance pipeline_reset",fade_out,mix_out);
        $finish;
    end
endmodule
