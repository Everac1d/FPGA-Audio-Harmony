`timescale 1ns/1ps
module tb_lcd_snapshot;
    reg clk=0;always #10 clk=~clk;
    reg rst_n=0,frame_start=0;
    reg source=0;reg [1:0] active_mode=0,algorithm_mode=0;
    reg signed [4:0] pitch=0;reg [4:0] gain_index=10;reg [3:0] rec_state=0;
    reg record_valid=0,record_full=0,storage_fault=0,ddr_ready=0;
    reg [15:0] ddr_diag=0;
    reg [20:0] record_progress=0,record_samples=0,play_samples=0;
    wire source_o;wire [1:0] active_mode_o,algorithm_mode_o;
    wire signed [4:0] pitch_o;wire [4:0] gain_index_o;wire [3:0] rec_state_o;
    wire record_valid_o,record_full_o,storage_fault_o,ddr_ready_o;
    wire [15:0] ddr_diag_o;
    wire [11:0] rec_centis,total_centis,play_centis;wire [8:0] progress_pixels;
    lcd_status_snapshot dut(.*);
    integer checks=0,cases=0,i,j,n,pending_latency;
    reg [38:0] expected_status=0;
    reg [11:0] expected_rec=0,expected_total=0,expected_play=0;
    reg [8:0] expected_pixels=0;
    reg [83:0] old_front;
    reg [31:0] random_state=32'hca395d8f;
    longint unsigned safe_rec,safe_total,safe_play,ratio;
    task check(input bit ok,input [511:0] message);
        begin checks=checks+1;if(ok!==1'b1)begin
            $display("FAIL LCD_SNAPSHOT %0s case=%0d rec=%0d total=%0d play=%0d pixels=%0d",message,cases,rec_centis,total_centis,play_centis,progress_pixels);$fatal(1);end end
    endtask
    function [83:0] front;
        front={source_o,active_mode_o,algorithm_mode_o,pitch_o,gain_index_o,rec_state_o,
            record_valid_o,record_full_o,storage_fault_o,ddr_ready_o,ddr_diag_o,
            rec_centis,total_centis,play_centis,progress_pixels};
    endfunction
    task pulse;
        begin @(negedge clk);frame_start=1;@(negedge clk);frame_start=0;end
    endtask
    task expect_front;
        begin
            check({source_o,active_mode_o,algorithm_mode_o,pitch_o,gain_index_o,rec_state_o,
                record_valid_o,record_full_o,storage_fault_o,ddr_ready_o,ddr_diag_o}===expected_status,"frame status atomically published");
            check(rec_centis===expected_rec&&total_centis===expected_total&&play_centis===expected_play,"independent 64-bit sample-to-centisecond reference");
            check(progress_pixels===expected_pixels,"independent bounded progress ratio");
        end
    endtask
    task run_case(input integer progress,input integer total,input integer played,
        input bit valid,input [3:0] state,input integer pitch_value);
        begin
            @(negedge clk);
            source=random_state[0];active_mode=random_state[2:1];algorithm_mode=random_state[4:3];
            pitch=pitch_value;gain_index=10+cases%21;rec_state=state;
            record_valid=valid;record_full=random_state[8];storage_fault=random_state[9];
            ddr_ready=random_state[10];ddr_diag=random_state[31:16];
            record_progress=progress;record_samples=total;play_samples=played;
            pulse;expect_front;
            old_front=front();
            expected_status={source,active_mode,algorithm_mode,pitch,gain_index,rec_state,
                record_valid,record_full,storage_fault,ddr_ready,ddr_diag};
            safe_rec=progress>1464844?1464844:progress;
            safe_total=total>1464844?1464844:total;
            safe_play=played>safe_total?safe_total:played;
            if(!valid)begin safe_total=0;safe_play=0;end
            expected_rec=(safe_rec*1024)/500000;
            expected_total=(safe_total*1024)/500000;
            expected_play=(safe_play*1024)/500000;
            if(expected_rec>3000)expected_rec=3000;
            if(expected_total>3000)expected_total=3000;
            if(expected_play>3000)expected_play=3000;
            if(state==2||state==3)ratio=safe_rec*432/1464844;
            else if(((state>=5&&state<=9)||state==11)&&safe_total!=0)ratio=safe_play*432/safe_total;
            else ratio=0;
            expected_pixels=ratio>432?432:ratio;
            pending_latency=0;
            // Disturb every source field while the restoring divider is busy.
            // A premature frame pulse must neither publish nor replace the job.
            for(j=0;j<140;j=j+1)begin
                @(negedge clk);
                random_state={random_state[30:0],random_state[31]^random_state[21]^random_state[1]^random_state[0]};
                {source,active_mode,algorithm_mode,pitch,gain_index,rec_state,
                    record_valid,record_full,storage_fault,ddr_ready,ddr_diag}={random_state,random_state[6:0]};
                record_progress=random_state[20:0];record_samples=~random_state[20:0];play_samples=random_state[31:11];
                frame_start=(j==8);
                #1;check(front()===old_front,"no mid-frame update while inputs change");
                if(dut.busy)pending_latency=pending_latency+1;
            end
            frame_start=0;
            check(dut.ready&&!dut.busy,"four sequential divisions complete before next frame");
            check(pending_latency>=125&&pending_latency<=132,"bounded sequential conversion latency");
            cases=cases+1;
        end
    endtask
    initial begin
        repeat(5)@(negedge clk);rst_n=1;
        run_case(0,0,0,0,0,0);
        run_case(1464844,1464844,1464844,1,2,-12);
        run_case(1464844,1464844,1464844,1,7,12);
        run_case(2097151,2097151,2097151,1,3,-8);
        run_case(48828,100,2097151,1,5,-4);
        run_case(100,0,100,1,7,4);
        run_case(100,100,100,0,7,8);
        run_case(48828,48828,0,1,4,0);
        run_case(48828,1464844,732422,1,11,-1);
        for(i=0;i<100;i=i+1)begin
            random_state={random_state[30:0],random_state[31]^random_state[21]^random_state[1]^random_state[0]};
            run_case(random_state[20:0],{random_state[10:0],random_state[31:22]},
                {random_state[6:0],random_state[31:18]},random_state[9],i%12,(i%25)-12);
        end
        pulse;expect_front;
        @(negedge clk);rst_n=0;repeat(3)@(negedge clk);
        check(front()===84'd0,"global reset clears entire display snapshot");
        $display("PASS LCD_SNAPSHOT checks=%0d cases=%0d busy_input_changes frame_atomic_publication sequential_division centiseconds saturation zero_division signed_pitch25 gain21 paused_progress reset",checks,cases);
        $finish;
    end
    initial begin #1000000;$fatal(1,"LCD snapshot timeout");end
endmodule
