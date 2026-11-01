`timescale 1ns/1ps
// Behavioral app-port model. Does not claim DDR PHY/calibration validation.
module tb_ddr_bridge;
    reg clk=0,ui_clk=0,ui_clock_running=1;
    always #10 clk=~clk;
    initial begin #3;forever #5 if(ui_clock_running) ui_clk=~ui_clk;end
    reg rst_n=0,ui_rst_n=0,calib_done=0;
    reg req_valid=0,req_write=0;
    reg [28:0] req_addr=0;
    reg [255:0] req_wdata=0;
    wire ready,error,req_ready,rsp_valid;
    wire [3:0] debug_state,error_code;
    wire [544:0] failure_snapshot;
    wire [255:0] rsp_rdata;
    wire [2:0] cmd;
    wire cmd_en,wr_data_en,wr_data_end;
    wire [28:0] addr;
    wire [255:0] wdata;
    wire [31:0] wr_data_mask;
    reg cmd_ready=0,wr_data_rdy=0,rd_data_valid=0,rd_data_end=0;
    reg [255:0] rd_data=0;
    reg stall_cmd=0,stall_data=0,stall_read=0,corrupt_read=0,bad_end=0;
    reg opposite_ready=0;
    reg [3:0] corrupt_index=5;
    reg [255:0] corrupt_mask=256'd1<<73;
    ddr_audio_bridge #(.TIMEOUT_CYCLES(200),.BOOT_TIMEOUT_CYCLES(2000)) dut(.*);
    // Full low 4MB, including every address bit used by the 30-second clip.
    reg [255:0] memory[0:131071];
    reg [31:0] random_state=32'h39c5ab17;
    reg pending_read=0;
    reg [28:0] read_address;
    integer read_delay=0,commands=0,writes=0,reads=0,responses=0,requests=0;
    integer joint_writes=0,cmd_only_ready_cycles=0,data_only_ready_cycles=0;
    integer external_commands=0,external_writes=0,cmd_delayed_full_accepts=0,data_delayed_full_accepts=0;
    // Model the native IP's one-cycle app enable/data registers and delayed
    // internal full qualification. Using !external_ready as full simplifies
    // the native Almost_Full registers, but deliberately preserves acceptance
    // in the cycle after ready falls; it is not ordinary valid && ready.
    reg app_en_d=0,write_en_d=0;
    reg [2:0] app_cmd_d;
    reg [28:0] app_addr_d;
    reg [255:0] write_data_d;
    reg full_r=1,full_rr=1,data_full_r=1;
    reg [2:0] command_queue[0:127];
    reg [28:0] address_queue[0:127];
    reg [255:0] data_queue[0:127];
    integer command_head=0,command_tail=0,data_head=0,data_tail=0;
    function integer mem_index(input [28:0] a);
        mem_index=a[19:3];
    endfunction
    function [28:0] test_location(input [3:0] index);
        test_location=29'd65544*index;
    endfunction
    function [255:0] expected_pattern(input [3:0] index);
        integer lane;reg [7:0] index_byte;
        begin
            index_byte={~index,index};
            for(lane=0;lane<8;lane=lane+1)
                expected_pattern[lane*32+:32]=32'h96a53cc3 ^
                    ({24'd0,index_byte}*32'h01010101) ^ (32'h01020408<<lane);
        end
    endfunction
    wire command_fire=app_en_d && !(full_r && full_rr);
    wire write_fire=write_en_d && !(data_full_r && !wr_data_rdy);
    always @(posedge ui_clk) begin
        if(!rst_n || !ui_rst_n) begin
            cmd_ready<=0;wr_data_rdy<=0;rd_data_valid<=0;rd_data_end<=0;rd_data<=0;
            pending_read<=0;
            commands<=0;writes<=0;reads<=0;random_state<=32'h39c5ab17;
            joint_writes<=0;cmd_only_ready_cycles<=0;data_only_ready_cycles<=0;
            external_commands<=0;external_writes<=0;cmd_delayed_full_accepts<=0;data_delayed_full_accepts<=0;
            app_en_d<=0;write_en_d<=0;app_cmd_d<=0;app_addr_d<=0;write_data_d<=0;
            full_r<=1;full_rr<=1;data_full_r<=1;
            command_head=0;command_tail=0;data_head=0;data_tail=0;
        end else begin
            if(cmd_en && !cmd_ready)$fatal(1,"native command enable must be low while external ready is low");
            if((cmd_en && cmd==0)!==wr_data_en)
                $fatal(1,"write command/data valid must be issued together");
            if(wr_data_en && (!cmd_ready || !wr_data_rdy || !wr_data_end))
                $fatal(1,"joint write launched without both ready or end");
            if(dut.state==1 && cmd_ready && !wr_data_rdy)cmd_only_ready_cycles<=cmd_only_ready_cycles+1;
            if(dut.state==1 && !cmd_ready && wr_data_rdy)data_only_ready_cycles<=data_only_ready_cycles+1;
            if(cmd_en)external_commands<=external_commands+1;
            if(wr_data_en)external_writes<=external_writes+1;
            app_en_d<=cmd_en;app_cmd_d<=cmd;app_addr_d<=addr;
            write_en_d<=wr_data_en && wr_data_end;write_data_d<=wdata;
            full_r<=!cmd_ready;full_rr<=full_r;data_full_r<=!wr_data_rdy;
            random_state<={random_state[30:0],random_state[31]^random_state[21]^random_state[1]^random_state[0]};
            cmd_ready<=calib_done && !stall_cmd && random_state[0];
            wr_data_rdy<=calib_done && !stall_data &&
                (opposite_ready ? !random_state[0] : random_state[7]);
            rd_data_valid<=0;rd_data_end<=0;
            if(command_fire) begin
                commands<=commands+1;
                if(!cmd_ready)cmd_delayed_full_accepts<=cmd_delayed_full_accepts+1;
                if(app_addr_d[2:0]!=0) $fatal(1,"unaligned BL8 app address");
                if(app_addr_d>=29'h100000) $fatal(1,"DDR test address outside low 4MB model");
                if(command_tail>=128)$fatal(1,"native model command queue exhausted");
                command_queue[command_tail]=app_cmd_d;address_queue[command_tail]=app_addr_d;
                command_tail=command_tail+1;
            end
            if(write_fire) begin
                if(wr_data_mask!=0) $fatal(1,"write mask invalid");
                if(!wr_data_rdy)data_delayed_full_accepts<=data_delayed_full_accepts+1;
                if(data_tail>=128)$fatal(1,"native model write-data queue exhausted");
                data_queue[data_tail]=write_data_d;data_tail=data_tail+1;
                joint_writes<=joint_writes+1;
            end
            // Execute commands in order, pairing writes with the oldest data.
            // Queueing avoids overwriting a previous payload at a back-to-back
            // pipeline boundary and also exposes duplicate native enables.
            if(!pending_read && command_head<command_tail)begin
                if(command_queue[command_head]==0)begin
                    if(data_head<data_tail)begin
                        memory[mem_index(address_queue[command_head])]<=data_queue[data_head];
                        command_head=command_head+1;data_head=data_head+1;writes<=writes+1;
                    end
                end else if(command_queue[command_head]==1)begin
                    pending_read<=1;read_address<=address_queue[command_head];
                    read_delay<=1+random_state[6:4];reads<=reads+1;command_head=command_head+1;
                end else $fatal(1,"unexpected DDR command");
            end
            if(pending_read && !stall_read) begin
                if(read_delay==0) begin
                    rd_data<=memory[mem_index(read_address)] ^
                        ((corrupt_read && read_address==test_location(corrupt_index)) ? corrupt_mask : 256'd0);
                    rd_data_valid<=1;rd_data_end<=!bad_end;pending_read<=0;
                end else read_delay<=read_delay-1;
            end
        end
    end
    always @(posedge clk) begin
        if(!rst_n) begin responses<=0;requests<=0;end
        else begin
            if(req_valid && req_ready) requests<=requests+1;
            if(rsp_valid) responses<=responses+1;
            if(error && (ready || req_ready)) $fatal(1,"error must lock ready low");
        end
    end
    task restart;
        begin
            @(negedge clk);rst_n=0;ui_rst_n=0;calib_done=0;req_valid=0;
            ui_clock_running=1;
            stall_cmd=0;stall_data=0;stall_read=0;corrupt_read=0;bad_end=0;opposite_ready=0;
            corrupt_index=5;corrupt_mask=256'd1<<73;
            repeat(8) @(negedge clk);
            if(failure_snapshot!==0)$fatal(1,"global reset did not clear first mismatch snapshot");
            rst_n=1;ui_rst_n=1;
            repeat(8) @(negedge clk);
            calib_done=1;
        end
    endtask
    task wait_ready;
        integer timeout;
        begin
            timeout=0;
            while(!ready && !error && timeout<2000) begin @(negedge clk);timeout=timeout+1;end
            if(!ready || error) $fatal(1,"DDR startup failed timeout=%0d state=%0d",timeout,dut.state);
            if(writes!=16 || reads!=16) $fatal(1,"selftest coverage writes=%0d reads=%0d",writes,reads);
        end
    endtask
    task wait_error(input integer expected_code);
        integer timeout;
        begin
            timeout=0;
            while(!error && timeout<2500) begin @(negedge clk);timeout=timeout+1;end
            if(!error || ready || req_ready) $fatal(1,"expected sticky error");
            repeat(20) @(negedge clk);
            if(!error || ready || req_ready) $fatal(1,"error did not remain latched");
            if(error_code!==expected_code[3:0]) $fatal(1,"wrong cause code got=%0d expected=%0d",error_code,expected_code);
            if(expected_code!=7 && failure_snapshot!==0)$fatal(1,"non-mismatch error populated mismatch snapshot");
            // Cause must retain the first error even after a different failure.
            calib_done=0;repeat(10) @(negedge clk);
            if(error_code!==expected_code[3:0]) $fatal(1,"first cause overwritten");
            if(ui_clock_running && debug_state!==4'd8 && expected_code!=2)
                $fatal(1,"fault state snapshot absent got=%0d",debug_state);
        end
    endtask
    task transact(input bit wr,input [28:0] a,input [255:0] d,output [255:0] response);
        integer timeout;
        begin
            @(negedge clk);req_valid=1;req_write=wr;req_addr=a;req_wdata=d;
            timeout=0;
            while(!req_ready && timeout<1000) begin @(negedge clk);timeout=timeout+1;end
            if(!req_ready) $fatal(1,"no request acceptance");
            @(negedge clk);req_valid=0;
            timeout=0;
            while(!rsp_valid && !error && timeout<1000) begin @(negedge clk);timeout=timeout+1;end
            if(!rsp_valid || error) $fatal(1,"no transaction response");
            response=rsp_rdata;
            @(negedge clk);
        end
    endtask
    integer i,block_index;
    reg [255:0] payload,result;
    reg [544:0] first_failure;
    initial begin
        restart;
        // Each ready can remain high while the other is low. No command or
        // data may escape until the controller offers a common write beat.
        opposite_ready=1;repeat(40)@(negedge ui_clk);
        if(commands!=0 || writes!=0 || ready || error)$fatal(1,"opposite ready levels must not accept half writes");
        opposite_ready=0;stall_cmd=1;repeat(40)@(negedge ui_clk);
        if(commands!=0 || writes!=0 || error)$fatal(1,"long command backpressure lost joint-write atomicity");
        stall_cmd=0;stall_data=1;repeat(40)@(negedge ui_clk);
        if(commands!=0 || writes!=0 || error)$fatal(1,"long data backpressure lost joint-write atomicity");
        stall_data=0;wait_ready;
        if(cmd_only_ready_cycles<10 || data_only_ready_cycles<10)$fatal(1,"opposite-ready write coverage missing");
        for(i=0;i<32;i=i+1) begin
            payload={8{32'hca570000+i}} ^ (256'd1<<(i*7));
            // Spread 64 transactions across the entire 91,553-block clip
            // range, explicitly including first and final partial blocks.
            block_index=(i==0)?0:((i==1)?91552:((i*3191+85741)%91553));
            transact(1,block_index*8,payload,result);
            transact(0,block_index*8,0,result);
            if(result!==payload) $fatal(1,"mailbox data mismatch block=%0d",block_index);
        end
        repeat(10) @(negedge clk);
        if(responses!=64 || requests!=64) $fatal(1,"one response per request failed %0d/%0d",responses,requests);
        if(joint_writes!=48 || writes!=48)$fatal(1,"joint-write count/selftest16 plus mailbox32 mismatch");
        if(external_commands!=96 || commands!=96 || external_writes!=48)
            $fatal(1,"native delayed-full model duplicated/dropped command or write enables");
        if(cmd_delayed_full_accepts==0 || data_delayed_full_accepts==0)
            $fatal(1,"native acceptance after external ready fell was not exercised");
        // Random ready waveforms are deterministic/reproducible.
        repeat(12) @(negedge clk);
        if(debug_state!==4'd4 || error_code!==0) $fatal(1,"ready diagnostic snapshot invalid");
        calib_done=0;wait_error(4);
        calib_done=1;repeat(50) @(negedge clk);
        if(!error) $fatal(1,"calibration return cleared sticky fault");
        restart;corrupt_read=1;wait_error(7);
        first_failure={4'd5,test_location(5),expected_pattern(5),expected_pattern(5)^(256'd1<<73)};
        if(failure_snapshot!==first_failure)$fatal(1,"index5 single-bit first mismatch metadata differs");
        // Later input activity and calibration loss must not replace any of
        // the captured 545 bits or the first error cause.
        corrupt_index=9;corrupt_mask=~256'd0;rd_data=~rd_data;calib_done=1;
        repeat(30)@(negedge clk);
        if(failure_snapshot!==first_failure || error_code!=7)$fatal(1,"first mismatch snapshot changed after fault");
        restart;corrupt_read=1;
        corrupt_mask=256'h8000000100000002000000040000000800000010000000200000004000000080;
        first_failure={4'd5,test_location(5),expected_pattern(5),expected_pattern(5)^corrupt_mask};
        wait_error(7);
        if(failure_snapshot!==first_failure)$fatal(1,"index5 multi-lane full expected/actual snapshot differs");
        restart;stall_cmd=1;wait_error(5);
        restart;stall_data=1;wait_error(5);
        restart;wait_ready;stall_read=1;
        @(negedge clk);req_valid=1;req_write=0;req_addr=0;
        @(negedge clk);req_valid=0;
        wait_error(5);
        restart;bad_end=1;wait_error(6);
        // No ui clock activity is required for the audio-domain boot watchdog.
        @(negedge clk);rst_n=0;ui_rst_n=0;calib_done=0;ui_clock_running=0;
        repeat(8) @(negedge clk);rst_n=1;wait_error(1);
        restart;wait_ready;
        // A running system whose user clock stops must time out in the audio
        // domain; no returning UI edge is needed to make the audio fail closed.
        @(negedge clk);ui_clock_running=0;req_valid=1;req_write=0;req_addr=0;
        @(negedge clk);req_valid=0;wait_error(3);
        restart;wait_ready;
        // User-domain reset loss is fatal after readiness, even if calibration
        // later returns; global reset is the only recovery operation.
        @(negedge clk);ui_rst_n=0;wait_error(4);
        restart;wait_ready;
        // An unexpected ready loss without a UI error flag has its own code.
        force dut.u_ready=1'b0;wait_error(2);release dut.u_ready;
        restart;wait_ready;
        // Illegal FSM encoding is distinct from bus timeout/corruption.
        @(negedge ui_clk);force dut.state=4'hf;
        @(negedge ui_clk);release dut.state;wait_error(8);
        restart;wait_ready;
        if(error_code!==0) $fatal(1,"global reset did not clear cause");
        $display("PASS DDR_BRIDGE: selftest16 mailbox64_joint_write native_delayed_full_strobes clip_address_range91553 opposite_ready long_backpressure calibration_drop index5_singlebit_multilane full545bit_snapshot corruption cmd_timeout data_timeout read_timeout bad_end boot_timeout stopped_ui_clock ui_reset recovery diagnostic_codes1_8 coherent_state first_fault_sticky");
        $finish;
    end
    initial begin #2000000;$fatal(1,"testbench timeout");end
endmodule
