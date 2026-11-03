`timescale 1ns/1ps
module tb_long_status_uart;
    localparam integer CLKS=4,REPORT=5000;
    reg clk=0;always #5 clk=~clk;
    reg rst_n=0,source=1;
    reg [1:0] live_mode=2,algorithm_mode=2;
    reg signed [4:0] pitch_semitones=-12,pitch_second=7;
    reg pitch_voice=0;
    reg [4:0] gain_index=30;
    reg [3:0] rec_state=3;
    reg [31:0] record_samples=32'h00DF8476,play_samples=32'h00200001;
    reg ddr_ready=1,storage_error=0,record_full=1,mic_ready=1;
    reg [31:0] queue_underflow_count=32'h12345678,queue_overflow_count=32'h9ABCDEF0;
    reg [15:0] ddr_diag=16'h740F;
    reg [544:0] ddr_failure={4'hA,29'h01234567,
        256'h0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF,
        256'hFEDCBA9876543210FEDCBA9876543210FEDCBA9876543210FEDCBA9876543210};
    wire uart_tx,uart_tx_debug;
    integer checks=0,byte_count=0,debug_byte_count=0,fd,debug_fd;
    reg [935:0] line,expected;
    reg [1311:0] failure_line,expected_failure;
    reg [935:0] debug_line;
    reg [1311:0] debug_failure_line;
    record_long_status_uart #(.CLK_HZ(4000),.BAUD(1000),.REPORT_CYCLES(REPORT),
        .USER_CODE(32'h00033105)) dut (.*);
    record_long_status_uart #(.CLK_HZ(4000),.BAUD(1000),.REPORT_CYCLES(REPORT),
        .USER_CODE(32'h00033106)) debug_dut(.uart_tx(uart_tx_debug),.*);
    task check(input bit condition,input [511:0] message);
        begin checks=checks+1;if(condition!==1'b1)begin $display("FAIL %0s",message);$fatal(1);end end
    endtask
    task clocks(input integer count);begin repeat(count)begin @(posedge clk);#1;end end endtask
    task receive_byte(output reg [7:0] value,output reg [7:0] debug_value);
        integer bit_number;
        begin
            @(negedge uart_tx);clocks(CLKS/2);check(uart_tx===0,"8N1 start bit");
            check(uart_tx_debug===0,"debug version aligned 8N1 start bit");
            for(bit_number=0;bit_number<8;bit_number=bit_number+1)begin
                clocks(CLKS);value[bit_number]=uart_tx;debug_value[bit_number]=uart_tx_debug;
            end
            clocks(CLKS);check(uart_tx===1,"8N1 stop bit");byte_count=byte_count+1;
            check(uart_tx_debug===1,"debug version 8N1 stop bit");debug_byte_count=debug_byte_count+1;
        end
    endtask
    task receive_pair;
        integer byte_number;reg [7:0] value,debug_value;
        begin
            line=0;debug_line=0;
            for(byte_number=0;byte_number<117;byte_number=byte_number+1)begin
                receive_byte(value,debug_value);line[(116-byte_number)*8+:8]=value;
                debug_line[(116-byte_number)*8+:8]=debug_value;
            end
            failure_line=0;debug_failure_line=0;
            for(byte_number=0;byte_number<164;byte_number=byte_number+1)begin
                receive_byte(value,debug_value);failure_line[(163-byte_number)*8+:8]=value;
                debug_failure_line[(163-byte_number)*8+:8]=debug_value;
            end
            $fwrite(fd,"%0s%0s",line,failure_line);
            $fwrite(debug_fd,"%0s%0s",debug_line,debug_failure_line);
        end
    endtask
    task check_debug_pair;
        reg [935:0] debug_expected;
        reg [1311:0] debug_expected_failure;
        begin
            debug_expected=expected;debug_expected[(116-12)*8+:8]="6";
            debug_expected_failure=expected_failure;debug_expected_failure[(163-12)*8+:8]="6";
            check(debug_line===debug_expected,"33106 actual serial R6 has correct version and all atomic fields");
            check(debug_failure_line===debug_expected_failure,"33106 paired D3 has matching version and snapshot");
        end
    endtask
    initial begin
        fd=$fopen("sim/results/long_status_uart_packets.txt","wb");check(fd!=0,"UART evidence file opened");
        debug_fd=$fopen("sim/results/long_debug_status_uart_packets.txt","wb");check(debug_fd!=0,"debug UART evidence file opened");
        clocks(3);check(uart_tx===1,"reset idle high");@(negedge clk);rst_n=1;
        fork
            begin
                // 发送 R6 时同时改变两个新增字段，不得
                // 影响该行后缀或随后与之原子配对的 D3。
                @(negedge uart_tx);clocks(40);@(negedge clk);
                source=0;live_mode=0;algorithm_mode=2;pitch_semitones=4;pitch_second=-12;pitch_voice=1;
                gain_index=11;rec_state=11;record_samples=32'h00800000;play_samples=32'h007FFFFF;
                ddr_ready=0;storage_error=1;record_full=0;mic_ready=0;
                queue_underflow_count=1;queue_overflow_count=2;ddr_diag=16'h1041;ddr_failure=0;
            end
            begin
                receive_pair;
                expected={"R6 V=00033105 S=1 M=2 A=2 N=14 H=1E T=3 L=00DF8476 P=00200001 D=1 E=0 F=1 I=1 U=12345678 O=9ABCDEF0 X=740F Q=07 C=0",8'h0d,8'h0a};
                if(line!==expected)$display("ACTUAL [%0s] EXPECTED [%0s]",line,expected);
                check(line===expected,"117-byte R6 uses one atomic snapshot including Q and C");
                expected_failure={"D3 V=00033105 J=A B=01234567 W=0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF R=FEDCBA9876543210FEDCBA9876543210FEDCBA9876543210FEDCBA9876543210",8'h0d,8'h0a};
                check(failure_line===expected_failure,"D3 shares first R6 snapshot despite input mutation");
                check_debug_pair;
                receive_pair;
                expected={"R6 V=00033105 S=0 M=0 A=2 N=04 H=0B T=B L=00800000 P=007FFFFF D=0 E=1 F=0 I=0 U=00000001 O=00000002 X=1041 Q=14 C=1",8'h0d,8'h0a};
                if(line!==expected)$display("ACTUAL [%0s] EXPECTED [%0s]",line,expected);
                check(line===expected,"second R6 reports new negative second pitch and editor selection");
                expected_failure={"D3 V=00033105 J=0 B=00000000 W=",{64{"0"}}," R=",{64{"0"}},8'h0d,8'h0a};
                check(failure_line===expected_failure,"second D3 reflects new snapshot");
                check_debug_pair;
            end
        join
        @(negedge uart_tx);clocks(3);@(negedge clk);rst_n=0;#1;
        check(uart_tx===1,"reset interrupts byte and returns idle high");
        source=1;live_mode=1;algorithm_mode=2;pitch_semitones=-4;pitch_second=-1;pitch_voice=1;
        gain_index=30;rec_state=7;record_samples=32'hF1234567;play_samples=32'h89ABCDEF;
        ddr_ready=1;storage_error=1;record_full=1;mic_ready=1;
        queue_underflow_count=32'hFFFFFFFF;queue_overflow_count=32'hFFFFFFFF;ddr_diag=16'hFFFF;ddr_failure={545{1'b1}};
        clocks(4);@(negedge clk);rst_n=1;receive_pair;
        expected={"R6 V=00033105 S=1 M=1 A=2 N=1C H=1E T=7 L=F1234567 P=89ABCDEF D=1 E=1 F=1 I=1 U=FFFFFFFF O=FFFFFFFF X=FFFF Q=1F C=1",8'h0d,8'h0a};
        check(line===expected,"reset restarts R6 with exact widths and second pitch sign extension");
        expected_failure={"D3 V=00033105 J=F B=1FFFFFFF W=",{64{"F"}}," R=",{64{"F"}},8'h0d,8'h0a};
        check(failure_line===expected_failure,"reset restarts D3 and keeps full failure payload");
        check_debug_pair;
        check(byte_count==843&&debug_byte_count==843,"three 281-byte atomic pairs received for each firmware");$fclose(fd);$fclose(debug_fd);
        $display("PASS LONG_STATUS_UART checks=%0d bytes=%0d debug_bytes=%0d pairs_each=3 R6_bytes=117 D3_bytes=164 versions33105_33106 atomic_all_fields counts_above21bit full32bit_raw negative_pitch_second reset",checks,byte_count,debug_byte_count);
        $finish;
    end
    initial begin #1000000;$fatal(1,"dual UART timeout");end
endmodule
