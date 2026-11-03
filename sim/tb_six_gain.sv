`timescale 1ns/1ps
// 数值参考模型使用有符号整数运算，独立于被测模块信号。
// 遍历全部有符号 PCM16 值及五个可选增益目标，同时覆盖启用和
// 关闭保护两种情况，并同时检查组合实现和三级流水实现。
module tb_six_gain;
    reg clk = 0;
    always #5 clk = ~clk;
    reg rst_n = 0;
    reg [1:0] active_mode = 1, requested_mode = 1;
    reg source_ready = 1;
    reg [2:0] gain_index = 0;
    reg signed [15:0] pcm_in = 0;
    wire signed [15:0] protected_comb, protected_pipe, plain_comb, plain_pipe;
    wire pc, pl, ppc, ppl, nc, nl, npc, npl;
    pcm_monitor_guard #(.SMOOTH_ENABLE(0),.PIPELINE_ENABLE(0)) u_pc(
        .clk(clk),.rst_n(rst_n),.frame_ce(1'b0),.active_mode(active_mode),
        .requested_mode(requested_mode),.source_ready(source_ready),
        .gain_index(gain_index),.pcm_in(pcm_in),.pcm_out(protected_comb),
        .would_clip(pc),.limiting(pl),.switch_ready(),.fade_level());
    pcm_monitor_guard #(.SMOOTH_ENABLE(0),.PIPELINE_ENABLE(1)) u_pp(
        .clk(clk),.rst_n(rst_n),.frame_ce(1'b0),.active_mode(active_mode),
        .requested_mode(requested_mode),.source_ready(source_ready),
        .gain_index(gain_index),.pcm_in(pcm_in),.pcm_out(protected_pipe),
        .would_clip(ppc),.limiting(ppl),.switch_ready(),.fade_level());
    pcm_monitor_guard #(.PROTECTION_ENABLE(0),.SMOOTH_ENABLE(0),.PIPELINE_ENABLE(0)) u_nc(
        .clk(clk),.rst_n(rst_n),.frame_ce(1'b0),.active_mode(active_mode),
        .requested_mode(requested_mode),.source_ready(source_ready),
        .gain_index(gain_index),.pcm_in(pcm_in),.pcm_out(plain_comb),
        .would_clip(nc),.limiting(nl),.switch_ready(),.fade_level());
    pcm_monitor_guard #(.PROTECTION_ENABLE(0),.SMOOTH_ENABLE(0),.PIPELINE_ENABLE(1)) u_np(
        .clk(clk),.rst_n(rst_n),.frame_ce(1'b0),.active_mode(active_mode),
        .requested_mode(requested_mode),.source_ready(source_ready),
        .gain_index(gain_index),.pcm_in(pcm_in),.pcm_out(plain_pipe),
        .would_clip(npc),.limiting(npl),.switch_ready(),.fade_level());

    reg srst = 0, frame_ce = 0, sready = 0;
    reg [1:0] smode = 0, srequest = 0;
    reg [2:0] sindex = 0;
    reg signed [15:0] spcm = 0;
    wire signed [15:0] smooth_comb, smooth_pipe;
    wire sc, sl, spc, spl, switch_ready;
    wire [8:0] fade_level;
    pcm_monitor_guard #(.PIPELINE_ENABLE(0)) u_sc(
        .clk(clk),.rst_n(srst),.frame_ce(frame_ce),.active_mode(smode),
        .requested_mode(srequest),.source_ready(sready),.gain_index(sindex),
        .pcm_in(spcm),.pcm_out(smooth_comb),.would_clip(sc),.limiting(sl),
        .switch_ready(switch_ready),.fade_level(fade_level));
    pcm_monitor_guard #(.PIPELINE_ENABLE(1)) u_sp(
        .clk(clk),.rst_n(srst),.frame_ce(frame_ce),.active_mode(smode),
        .requested_mode(srequest),.source_ready(sready),.gain_index(sindex),
        .pcm_in(spcm),.pcm_out(smooth_pipe),.would_clip(spc),.limiting(spl),
        .switch_ready(),.fade_level());

    function automatic integer gain_target(input integer index);
        begin
            case(index)
                0: gain_target=256; 2: gain_target=384;
                4: gain_target=512; 5: gain_target=640;
                6: gain_target=768;
                default: gain_target=256;
            endcase
        end
    endfunction

    // 有符号整数除法向零截断；饱和处理位于
    // 软拐点处理之后、模式淡变之前，包含启用保护时的 3 倍正负极限。
    function automatic [17:0] math_sample(
        input integer sample, input integer gain, input integer envelope,
        input integer mode, input integer ready, input integer protect);
        integer amplified, absolute, compressed, value, clip_flag, limit_flag;
        begin
            amplified = (sample * ((mode == 2) ? 256 : gain)) / 256;
            absolute = (amplified < 0) ? -amplified : amplified;
            clip_flag = ready && mode == 1 && (amplified > 32767 || amplified < -32768);
            limit_flag = ready && mode == 1 && protect && absolute > 8192;
            compressed = limit_flag ? 8192 + (absolute - 8192) / 4 : absolute;
            // 整形计算本身不依赖 ready。
            if (protect && mode == 1 && absolute > 8192)
                compressed = 8192 + (absolute - 8192) / 4;
            if (amplified < 0) compressed = -compressed;
            if (compressed > 32767) compressed = 32767;
            if (compressed < -32768) compressed = -32768;
            value = ready ? (compressed * envelope) / 256 : 0;
            math_sample = {clip_flag[0],limit_flag[0],value[15:0]};
        end
    endfunction

    reg [17:0] pqueue0=0, pqueue1=0, nqueue0=0, nqueue1=0;
    reg [17:0] squeue0=0, squeue1=0;
    integer static_samples=0, smooth_samples=0;
    integer model_gain=256, model_envelope=0;

    task automatic static_tick(input integer index, input integer sample,
                               input integer mode, input integer ready);
        reg [17:0] expected_p, expected_n;
        begin
            @(negedge clk);
            gain_index=index; pcm_in=sample; active_mode=mode;
            requested_mode=mode; source_ready=ready;
            expected_p=math_sample(sample,gain_target(index),256,mode,ready,1);
            expected_n=math_sample(sample,gain_target(index),256,mode,ready,0);
            #1;
            if ({pc,pl,protected_comb} !== expected_p || {nc,nl,plain_comb} !== expected_n)
                $fatal(1,"static combinational mismatch index=%0d sample=%0d mode=%0d got=%h/%h expected=%h/%h",
                    index,sample,mode,{pc,pl,protected_comb},{nc,nl,plain_comb},expected_p,expected_n);
            @(posedge clk); #1;
            if ({ppc,ppl,protected_pipe} !== pqueue1 || {npc,npl,plain_pipe} !== nqueue1)
                $fatal(1,"static pipeline mismatch sample=%0d got=%h/%h expected=%h/%h",
                    static_samples,{ppc,ppl,protected_pipe},{npc,npl,plain_pipe},pqueue1,nqueue1);
            pqueue1=pqueue0; pqueue0=expected_p;
            nqueue1=nqueue0; nqueue0=expected_n;
            static_samples=static_samples+1;
        end
    endtask

    task automatic smooth_tick(input integer index, input integer sample,
        input integer mode, input integer request, input integer ready, input integer ce);
        reg [17:0] expected;
        integer target;
        begin
            @(negedge clk);
            sindex=index; spcm=sample; smode=mode; srequest=request;
            sready=ready; frame_ce=ce;
            expected=math_sample(sample,model_gain,model_envelope,mode,ready,1);
            #1;
            if ({sc,sl,smooth_comb} !== expected)
                $fatal(1,"smooth combinational mismatch tick=%0d gain=%0d envelope=%0d got=%h expected=%h",
                    smooth_samples,model_gain,model_envelope,{sc,sl,smooth_comb},expected);
            @(posedge clk); #1;
            if ({spc,spl,smooth_pipe} !== squeue1)
                $fatal(1,"smooth pipeline mismatch tick=%0d got=%h expected=%h",smooth_samples,{spc,spl,smooth_pipe},squeue1);
            squeue1=squeue0; squeue0=expected;
            if (ce) begin
                target=gain_target(index);
                if (model_gain < target) model_gain=model_gain+1;
                else if (model_gain > target) model_gain=model_gain-1;
                if (request != mode) begin
                    if (model_envelope != 0) model_envelope=model_envelope-1;
                end else if (ready && mode != 0) begin
                    if (model_envelope < 256) model_envelope=model_envelope+1;
                end else model_envelope=0;
            end
            if (u_sc.gain_q8 !== model_gain[11:0] || u_sp.gain_q8 !== model_gain[11:0] ||
                fade_level !== model_envelope[8:0] || switch_ready !== (model_envelope == 0))
                $fatal(1,"smooth state mismatch tick=%0d target=%0d gain=%0d/%0d fade=%0d/%0d",
                    smooth_samples,gain_target(index),u_sc.gain_q8,model_gain,fade_level,model_envelope);
            smooth_samples=smooth_samples+1;
        end
    endtask

    task automatic smooth_reset;
        begin
            @(negedge clk);
            srst=0; smode=0; srequest=0; sready=0; frame_ce=0; sindex=0; spcm=0;
            repeat(3) begin
                @(posedge clk); #1;
                if (smooth_pipe !== 0 || spc !== 0 || spl !== 0 || fade_level !== 0)
                    $fatal(1,"reset did not clear smooth pipeline/fade");
            end
            model_gain=256; model_envelope=0; squeue0=0; squeue1=0;
            @(negedge clk); srst=1;
        end
    endtask

    integer index, sample, k;
    integer active_indices[0:4];
    initial begin
        active_indices[0]=0;active_indices[1]=2;active_indices[2]=4;active_indices[3]=5;active_indices[4]=6;
        repeat(4) @(posedge clk);
        @(negedge clk); rst_n=1;
        // 以静音启动参考比对，使不计入检查的释放边沿为零。
        source_ready=0;
        for(index=0; index<5; index=index+1)
            for(sample=-32768; sample<=32767; sample=sample+1)
                static_tick(active_indices[index],sample,1,1);
        // 任意增益索引及正负极限处，测试音均必须保持 1 倍增益。
        for(index=0; index<5; index=index+1) begin
            static_tick(active_indices[index],-32768,2,1);
            static_tick(active_indices[index],32767,2,1);
            static_tick(active_indices[index],8193,2,1);
            static_tick(active_indices[index],32767,1,0);
        end
        // 保留的 H1/H3/H7 不得保留旧增益值；检查两种
        // 极性、小幅样本和诊断测试音是否均回退到 1 倍增益。
        for(index=1;index<8;index=index+2) begin
            if(index!=5) begin
                static_tick(index,-32768,1,1); static_tick(index,32767,1,1);
                static_tick(index,-1,1,1); static_tick(index,1,1,1);
                static_tick(index,32767,2,1);
            end
        end
        static_tick(0,0,1,0); static_tick(0,0,1,0); static_tick(0,0,1,0);

        smooth_reset();
        // 1 倍到 3 倍：即使其间仅时钟运行、帧事件暂停，也恰需 512 次帧事件。
        for(k=0;k<512;k=k+1)
            smooth_tick(6,(k[0] ? -32768 : 32767),1,1,1,1);
        if(model_gain != 768 || model_envelope != 256) $fatal(1,"1x->3x endpoint");
        repeat(20) smooth_tick(0,32767,1,1,1,0);
        if(model_gain != 768) $fatal(1,"gain advanced without frame_ce");
        // 3 倍到 1 倍同样恰需 512 次帧事件。
        for(k=0;k<512;k=k+1) smooth_tick(0,-32768,1,1,1,1);
        if(model_gain != 256) $fatal(1,"3x->1x endpoint");
        // 音源失效通过相同的三级流水线立即关闭输出，
        // 并在下一次帧事件清除包络。
        repeat(5) smooth_tick(6,32767,1,1,0,0);
        smooth_tick(6,32767,1,1,0,1);
        if(model_envelope != 0) $fatal(1,"source loss fade reset");
        repeat(256) smooth_tick(6,32767,1,1,1,1);
        // 模式切换必须先淡出到零，随后测试音使用固定 1 倍增益。
        repeat(256) smooth_tick(6,-32768,1,2,1,1);
        if(model_envelope != 0 || !switch_ready) $fatal(1,"mode fade endpoint");
        repeat(256) smooth_tick(6,-32768,2,2,1,1);
        repeat(10) smooth_tick(6,32767,2,2,1,1);
        // 覆盖非零样本处理中途发生的静音、音源失效和复位。
        smooth_tick(6,32767,0,0,0,1);
        smooth_tick(6,32767,1,1,1,1);
        smooth_reset();
        repeat(256) smooth_tick(0,20000,1,1,1,1);
        if(model_gain != 256 || model_envelope != 256) $fatal(1,"default unity recovery");
        repeat(3) smooth_tick(0,0,1,1,0,1);
        $display("PASS expanded_gain exhaustive_pcm_gain_pairs=327680 static_samples=%0d smooth_samples=%0d numerical_checks=%0d all_5_selectable_gains_reserved_unity_fallback_rails_pipeline_slew_hold_tone_source_loss_reset",
            static_samples,smooth_samples,static_samples*4+smooth_samples*2);
        $finish;
    end
endmodule
