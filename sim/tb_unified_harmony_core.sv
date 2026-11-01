`timescale 1ns/1ps
// Independent Q20/granular and fixed-dry model, plus frozen 28 RTL comparisons.
module tb_unified_harmony_core;
    reg clk=0;always #10 clk=~clk;
    reg rst_n=0,valid=0;
    reg signed [15:0] pcm=0;
    reg [1:0] mode=0;
    reg signed [4:0] pitch=0,pitch2=0,legacy_pitch=0;
    wire signed [15:0] out,static_out,normal_out,dual_out,harmony_out;
    wire out_valid,static_valid,normal_valid,dual_valid,harmony_valid;
    audio_harmony_core #(.RAM_ADDR_BITS(8),.GRAIN_LOG2(6),.GUARD_SAMPLES(4),.DYNAMIC_CONFIG(1)) dut(
        .clk(clk),.rst_n(rst_n),.pcm_in(pcm),.pcm_in_valid(valid),.mode(mode),
        .pitch_semitones(pitch),.pitch_second(pitch2),.pcm_out(out),.pcm_out_valid(out_valid));
    audio_harmony_core #(.RAM_ADDR_BITS(8),.GRAIN_LOG2(6),.GUARD_SAMPLES(4),.DYNAMIC_CONFIG(0)) static_dut(
        .clk(clk),.rst_n(rst_n),.pcm_in(pcm),.pcm_in_valid(valid),.mode(mode),
        .pitch_semitones(pitch),.pitch_second(pitch2),.pcm_out(static_out),.pcm_out_valid(static_valid));
    audio_effect_core #(.RAM_ADDR_BITS(8),.GRAIN_LOG2(6),.GUARD_SAMPLES(4),.DYNAMIC_CONFIG(1)) old_normal(
        .clk(clk),.rst_n(rst_n),.pcm_in(pcm),.pcm_in_valid(valid),.mode(mode),
        .pitch_semitones(pitch),.pitch_second(pitch2),.pcm_out(normal_out),.pcm_out_valid(normal_valid));
    audio_effect_core #(.RAM_ADDR_BITS(8),.GRAIN_LOG2(6),.GUARD_SAMPLES(4),.DYNAMIC_CONFIG(1),.DUAL_VOICE_ENABLE(1)) old_dual(
        .clk(clk),.rst_n(rst_n),.pcm_in(pcm),.pcm_in_valid(valid),.mode(2'd3),
        .pitch_semitones(pitch),.pitch_second(pitch2),.pcm_out(dual_out),.pcm_out_valid(dual_valid));
    audio_effect_core #(.RAM_ADDR_BITS(8),.GRAIN_LOG2(6),.GUARD_SAMPLES(4),.DYNAMIC_CONFIG(1)) old_harmony(
        .clk(clk),.rst_n(rst_n),.pcm_in(pcm),.pcm_in_valid(valid),.mode(2'd2),
        .pitch_semitones(legacy_pitch),.pitch_second(5'sd0),.pcm_out(harmony_out),.pcm_out_valid(harmony_valid));
    integer history[0:3][0:255];longint phase[0:3];
    integer expected[0:19999],expected_static[0:19999],due[0:19999];
    integer expected_mode[0:19999],expected_first[0:19999],expected_second[0:19999];
    bit compatibility[0:19999],unity[0:19999],phase_difference[0:19999];
    integer head=0,tail=0,cycle=0,sample_index=0,fill=0,startup=0;
    integer static_mode=0,static_pitch=0,static_second=0;
    bit static_configured=0;
    integer n,q,orientation,v,k,x,m,p,s,gap,y1,y2,sy1,sy2,first_mode,want,want_static;
    integer checked=0,compat_samples=0,compat_unity=0,normal_exact=0,dual_exact=0;
    integer zero_zero=0,zero_zero_different_phase=0,holds=0,invalid_silent=0,static_samples=0;
    reg [624:0] pairs_seen=0;
    reg [3:0] modes_seen=0;
    reg [31:0] random_state=32'h2931c4e7;
    function integer round_shift(input longint value,input integer shift);
        longint result;
        begin
            if(value<0)result=-(((-value)+(64'sd1<<(shift-1)))>>>shift);
            else result=(value+(64'sd1<<(shift-1)))>>>shift;
            if(result>32767)round_shift=32767;
            else if(result< -32768)round_shift=-32768;
            else round_shift=result;
        end
    endfunction
    task voice_model(input integer voice,input integer xx,input integer mm,input integer pp,output integer yy);
        integer wr,filled,gain,ratio,a0,a1,b0,b1,aligned,a,b,t,w,mixed;
        longint other,position_a,position_b,frac_a,frac_b,value,square,curve,wet;
        begin
            if(pp>12)pp=12;if(pp< -12)pp=-12;
            ratio=$rtoi((2.0**(pp/12.0))*1048576.0+0.5);
            wr=sample_index%256;filled=(fill>=70);
            gain=filled ? ((startup<32768)?startup+256:32768):0;
            other=phase[voice]^33554432;
            position_a=wr*64'sd1048576-4*64'sd1048576-phase[voice];
            position_b=wr*64'sd1048576-4*64'sd1048576-other;
            frac_a=position_a&1048575;frac_b=position_b&1048575;
            if(filled)begin
                a0=history[voice][(position_a>>>20)&255];a1=history[voice][((position_a>>>20)+1)&255];
                b0=history[voice][(position_b>>>20)&255];b1=history[voice][((position_b>>>20)+1)&255];
                aligned=history[voice][(wr-36)&255];
            end else begin a0=0;a1=0;b0=0;b1=0;aligned=0;end
            a=round_shift(a0*64'sd1048576+(a1-a0)*frac_a,20);
            b=round_shift(b0*64'sd1048576+(b1-b0)*frac_b,20);
            t=((phase[voice]>=33554432)?67108864-phase[voice]:phase[voice])>>>10;
            square=(t*64'sd1*t)>>>15;curve=(square*(98304-2*t))>>>15;w=curve;
            value=a*64'sd1*w+b*64'sd1*(32768-w);wet=round_shift(value,15);
            case(mm)
                0:begin mixed=xx;gain=32768;end
                1:mixed=wet;
                2:mixed=(aligned+wet)/2;
                3:mixed=aligned;
                default:mixed=0;
            endcase
            yy=round_shift(mixed*64'sd1*gain,15);
            history[voice][wr]=xx;
            phase[voice]=(phase[voice]+1048576-ratio)&67108863;
        end
    endtask
    task reset_session;
        begin
            @(negedge clk);rst_n=0;valid=0;mode=0;pitch=0;pitch2=0;
            head=0;tail=0;sample_index=0;fill=0;startup=0;static_configured=0;
            for(v=0;v<4;v=v+1)begin
                phase[v]=0;for(k=0;k<256;k=k+1)history[v][k]=0;
            end
            repeat(4)@(negedge clk);rst_n=1;
        end
    endtask
    task send_sample(input integer xx,input integer mm,input integer pp,input integer qq,input integer idle_clocks,input bit compat);
        bit different;
        begin
            different=(phase[0]!=phase[1]);
            first_mode=(mm==2) ? ((pp==0)?3:1):mm;
            voice_model(0,xx,first_mode,pp,y1);voice_model(1,xx,(qq==0)?3:1,qq,y2);
            want=(mm==2)?(y1+y2)/2:((mm==0||mm==1)?y1:0);
            if(!static_configured)begin
                static_mode=mm;static_pitch=pp;static_second=qq;static_configured=1;
            end
            first_mode=(static_mode==2)?((static_pitch==0)?3:1):static_mode;
            voice_model(2,xx,first_mode,static_pitch,sy1);
            voice_model(3,xx,(static_second==0)?3:1,static_second,sy2);
            want_static=(static_mode==2)?(sy1+sy2)/2:((static_mode==0||static_mode==1)?sy1:0);
            sample_index=sample_index+1;
            startup=(fill>=70)?((startup<32768)?startup+256:32768):0;
            if(fill<70)fill=fill+1;
            @(negedge clk);pcm=xx;mode=mm;pitch=pp;pitch2=qq;
            legacy_pitch=(pp==0)?qq:pp;valid=1;
            expected[tail]=want;expected_static[tail]=want_static;due[tail]=cycle+18;
            expected_mode[tail]=mm;expected_first[tail]=pp;expected_second[tail]=qq;
            compatibility[tail]=compat;unity[tail]=(startup==32768);phase_difference[tail]=different;
            tail=tail+1;
            @(negedge clk);valid=0;
            // Public controls change while a job is busy. The accepted sample
            // must still use the original public effect and per-voice routing.
            mode=3-mm;pitch=-pp;pitch2=-qq;legacy_pitch=12;
            repeat(idle_clocks-2)@(negedge clk);
        end
    endtask
    always @(posedge clk)begin
        cycle=cycle+1;#1;
        if(rst_n)begin
            if(out_valid!==static_valid||out_valid!==normal_valid||out_valid!==dual_valid||out_valid!==harmony_valid)
                $fatal(1,"pipeline/voice valid disagreement cycle%0d",cycle);
            if(head<tail&&cycle==due[head])begin
                if(out_valid!==1||$signed(out)!==expected[head])
                    $fatal(1,"independent model sample%0d cycle%0d got%0d want%0d valid%b m%0d p%0d q%0d",head,cycle,$signed(out),expected[head],out_valid,expected_mode[head],expected_first[head],expected_second[head]);
                if($signed(static_out)!==expected_static[head])$fatal(1,"static reset-latched model got%0d want%0d",$signed(static_out),expected_static[head]);
                static_samples=static_samples+1;
                if(expected_mode[head]<2)begin
                    if(out!==normal_out)$fatal(1,"normal mode changed from28 m%0d",expected_mode[head]);
                    normal_exact=normal_exact+1;
                end
                if(expected_mode[head]==2&&expected_first[head]!=0&&expected_second[head]!=0)begin
                    if(out!==dual_out)$fatal(1,"two nonzero voices changed from28 dual result");
                    dual_exact=dual_exact+1;
                end
                if(expected_mode[head]==2&&expected_first[head]==0&&expected_second[head]==0)begin
                    if(dut.first_out!==dut.second_out||out!==dut.first_out)$fatal(1,"zero voices must share fixed aligned dry regardless old phase");
                    zero_zero=zero_zero+1;
                    if(phase_difference[head])zero_zero_different_phase=zero_zero_different_phase+1;
                end
                if(expected_mode[head]==3)begin
                    if(out!==16'sd0)$fatal(1,"illegal fourth effect must be silent");invalid_silent=invalid_silent+1;
                end
                if(compatibility[head])begin
                    if(($signed(out)-$signed(harmony_out)>1)||($signed(harmony_out)-$signed(out)>1))
                        $fatal(1,"old 0/p harmony startup differs>1LSB p%0d q%0d new%0d old%0d",expected_first[head],expected_second[head],$signed(out),$signed(harmony_out));
                    compat_samples=compat_samples+1;
                    if(unity[head])begin
                        if(out!==harmony_out)$fatal(1,"old0/p unity harmony not exact");compat_unity=compat_unity+1;
                    end
                end
                checked=checked+1;head=head+1;
            end else if(out_valid)$fatal(1,"missing/extra/late output cycle%0d",cycle);
        end
    end
    initial begin
        // Fresh 0/p and p/0 are equivalent to the original dry+shifted harmony.
        for(orientation=0;orientation<2;orientation=orientation+1)begin
            for(q=-12;q<=12;q=q+1)begin
                reset_session;
                for(n=0;n<400;n=n+1)begin
                    random_state=random_state^(random_state<<13);random_state=random_state^(random_state>>17);random_state=random_state^(random_state<<5);
                    case(n%17)0:x=-32768;1:x=32767;2:x=-1;default:x=$signed(random_state[15:0]);endcase
                    send_sample(x,2,orientation?q:0,orientation?0:q,32,1);
                end
                repeat(40)@(negedge clk);if(head!=tail)$fatal(1,"compat pending output");
            end
        end
        // Static mode0/1/illegal3 must ignore all later public changes.
        for(m=0;m<4;m=m+1)if(m!=2)begin
            reset_session;
            for(n=0;n<300;n=n+1)send_sample((n%2)?32767:-32768,n==0?m:(n%4),n==0?-7:(n%25)-12,n==0?5:12-(n%25),32,0);
            repeat(40)@(negedge clk);if(head!=tail)$fatal(1,"static pending output");
        end
        reset_session;
        for(n=0;n<12000;n=n+1)begin
            random_state=random_state^(random_state<<13);random_state=random_state^(random_state>>17);random_state=random_state^(random_state<<5);
            case(n%31)0:x=-32768;1:x=32767;2:x=-1;3:x=0;default:x=$signed(random_state[15:0]);endcase
            m=(n<2500)?2:((n/19)%4);p=((n%625)/25)-12;s=(n%25)-12;
            if(m==2)pairs_seen[(p+12)*25+s+12]=1;modes_seen[m]=1;
            gap=32+(random_state[4:0]);if(n%101==0)begin gap=gap+2048;holds=holds+1;end
            send_sample(x,m,p,s,gap,0);
        end
        repeat(40)@(negedge clk);
        if(head!=tail||dut.algorithm.fault||dut.second_algorithm.fault||static_dut.algorithm.fault||static_dut.second_algorithm.fault)$fatal(1,"pending output/core busy fault");
        if(dut.algorithm.fill_count!=70||dut.second_algorithm.fill_count!=70||dut.algorithm.write_address!=(12000%256)||dut.second_algorithm.write_address!=(12000%256))$fatal(1,"history reset/skip");
        if(pairs_seen!={625{1'b1}}||modes_seen!=4'hf||zero_zero_different_phase==0||normal_exact==0||dual_exact==0||invalid_silent==0)$fatal(1,"coverage incomplete");
        $display("PASS UNIFIED_HARMONY_CORE independent_samples=%0d static_samples=%0d all625pairs old_zero_pitch_equiv=%0d unity_exact=%0d normal01_exact=%0d nonzero_dual28_exact=%0d zero_zero=%0d zero_after_different_phase=%0d invalid3_silent=%0d holds=%0d valid17 no_skip history_preserved",checked,static_samples,compat_samples,compat_unity,normal_exact,dual_exact,zero_zero,zero_zero_different_phase,invalid_silent,holds);
        $finish;
    end
    initial begin #300000000;$fatal(1,"watchdog");end
endmodule
