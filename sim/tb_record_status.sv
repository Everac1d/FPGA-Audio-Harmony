`timescale 1ns/1ps
module tb_record_status;
    localparam integer CLKS=4,REPORT=5000;
    reg clk=0;always #5 clk=~clk;
    reg rst_n=0,source=1;
    reg [1:0] live_mode=2,algorithm_mode=2;
    reg signed [4:0] pitch_semitones=-12;
    reg [2:0] gain_index=6;
    reg [3:0] rec_state=3;
    reg [20:0] record_samples=21'h165A5A,play_samples=21'h0ABCDE;
    reg ddr_ready=1,storage_error=0,record_full=1,mic_ready=1;
    reg [31:0] queue_underflow_count=32'h12345678,queue_overflow_count=32'h9ABCDEF0;
    reg [15:0] ddr_diag=16'h740F;
    reg [544:0] ddr_failure={4'hA,29'h01234567,
        256'h0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF,
        256'hFEDCBA9876543210FEDCBA9876543210FEDCBA9876543210FEDCBA9876543210};
    wire uart_tx;
    integer checks=0,byte_count=0;
    reg [823:0] line,expected;
    reg [1311:0] failure_line,expected_failure;
    record_status_uart #(.CLK_HZ(4000),.BAUD(1000),.REPORT_CYCLES(REPORT),.USER_CODE(32'h00032901)) dut (
        .clk(clk),.rst_n(rst_n),.source(source),.live_mode(live_mode),.algorithm_mode(algorithm_mode),
        .pitch_semitones(pitch_semitones),.gain_index(gain_index),.rec_state(rec_state),
        .record_samples(record_samples),.play_samples(play_samples),.ddr_ready(ddr_ready),
        .storage_error(storage_error),.ddr_diag(ddr_diag),.ddr_failure(ddr_failure),.record_full(record_full),.mic_ready(mic_ready),
        .queue_underflow_count(queue_underflow_count),.queue_overflow_count(queue_overflow_count),.uart_tx(uart_tx)
    );
    task check(input bit condition,input [511:0] message);
        begin checks=checks+1;if(!condition) begin $display("FAIL %0s",message);$fatal(1);end end
    endtask
    task clocks(input integer count);
        begin repeat(count) begin @(posedge clk);#1;end end
    endtask
    task receive_byte(output reg [7:0] value);
        integer bit_number;
        begin
            @(negedge uart_tx);clocks(CLKS/2);
            check(uart_tx===0,"8N1 start bit");
            for(bit_number=0;bit_number<8;bit_number=bit_number+1) begin
                clocks(CLKS);value[bit_number]=uart_tx;
            end
            clocks(CLKS);check(uart_tx===1,"8N1 stop bit");byte_count=byte_count+1;
        end
    endtask
    task receive_line;
        integer byte_number;reg[7:0] value;
        begin
            line=0;
            for(byte_number=0;byte_number<103;byte_number=byte_number+1) begin
                receive_byte(value);line[(102-byte_number)*8+:8]=value;
            end
            failure_line=0;
            for(byte_number=0;byte_number<164;byte_number=byte_number+1) begin
                receive_byte(value);failure_line[(163-byte_number)*8+:8]=value;
            end
        end
    endtask
    initial begin
        clocks(3);check(uart_tx===1,"reset idle high");@(negedge clk);rst_n=1;
        fork
            begin
                // Mutate every field while the first line is still on the wire.
                @(negedge uart_tx);clocks(40);@(negedge clk);
                source=0;live_mode=0;algorithm_mode=1;pitch_semitones=4;gain_index=2;rec_state=2;
                record_samples=1;play_samples=0;ddr_ready=0;storage_error=1;record_full=0;mic_ready=0;
                queue_underflow_count=1;queue_overflow_count=2;
                ddr_diag=16'h1041;
                ddr_failure=0;
            end
            begin
                receive_line;
                expected={"R3 V=00032901 S=1 M=2 A=2 N=14 H=6 T=3 L=165A5A P=0ABCDE D=1 E=0 F=1 I=1 U=12345678 O=9ABCDEF0 X=740F",8'h0d,8'h0a};
                if(line!==expected) $display("ACTUAL [%0s] EXPECTED [%0s]",line,expected);
                check(line===expected,"first complete line/version/negative pitch/atomic snapshot");
                expected_failure={"D3 V=00032901 J=A B=01234567 W=0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF R=FEDCBA9876543210FEDCBA9876543210FEDCBA9876543210FEDCBA9876543210",8'h0d,8'h0a};
                check(failure_line===expected_failure,"first full512bit failure snapshot atomic with R3");
                receive_line;
                expected={"R3 V=00032901 S=0 M=0 A=1 N=04 H=2 T=2 L=000001 P=000000 D=0 E=1 F=0 I=0 U=00000001 O=00000002 X=1041",8'h0d,8'h0a};
                if(line!==expected) $display("ACTUAL [%0s] EXPECTED [%0s]",line,expected);
                check(line===expected,"second line reflects new snapshot and positive pitch");
                expected_failure={"D3 V=00032901 J=0 B=00000000 W=",{64{"0"}}," R=",{64{"0"}},8'h0d,8'h0a};
                check(failure_line===expected_failure,"second failure snapshot reflects zeros after update");
            end
        join
        // Reset during a byte must force idle high and discard the partial line.
        @(negedge uart_tx);clocks(3);@(negedge clk);rst_n=0;#1;
        check(uart_tx===1,"reset during transmission immediately idle");
        source=1;live_mode=3;algorithm_mode=3;pitch_semitones=-4;gain_index=7;rec_state=15;
        record_samples=21'h1FFFFF;play_samples=21'h1FFFFF;
        ddr_ready=1;storage_error=1;record_full=1;mic_ready=1;
        queue_underflow_count=32'hFFFFFFFF;queue_overflow_count=32'hFFFFFFFF;
        ddr_diag=16'hFFFF;
        ddr_failure={545{1'b1}};
        clocks(4);@(negedge clk);rst_n=1;
        receive_line;
        expected={"R3 V=00032901 S=1 M=3 A=3 N=1C H=7 T=F L=1FFFFF P=1FFFFF D=1 E=1 F=1 I=1 U=FFFFFFFF O=FFFFFFFF X=FFFF",8'h0d,8'h0a};
        if(line!==expected) $display("ACTUAL [%0s] EXPECTED [%0s]",line,expected);
        check(line===expected,"reset restarts packet at R3 with exact field widths");
        expected_failure={"D3 V=00032901 J=F B=1FFFFFFF W=",{64{"F"}}," R=",{64{"F"}},8'h0d,8'h0a};
        check(failure_line===expected_failure,"reset restarts D3 and preserves full address/data widths");
        check(byte_count==801,"complete atomic pair byte counts");
        $display("PASS tb_record_status checks=%0d bytes=%0d",checks,byte_count);$finish;
    end
    initial begin #1000000;$fatal(1,"timeout tb_record_status");end
endmodule
