"""Compare the LCD candidate with the frozen 32901 top, clock by clock.

Uses two instances of the deterministic application-port DDR wrapper from
tb_record_top_startup. This is an RTL integration test, not a PHY model.
"""
from pathlib import Path
import argparse
import ctypes
import hashlib
import json
import os
import re
import subprocess
import time

ROOT = Path(__file__).resolve().parent.parent


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest().upper()


def complete_program(path):
    if not path.is_file():
        return False
    footer = re.search(rb'\n:file_names (\d+);\r?\n(.*)\Z', path.read_bytes(), re.S)
    if footer is None:
        return False
    lines = footer[2].strip().splitlines()
    return len(lines) == int(footer[1]) and all(
        line.strip().startswith(b'"') and line.strip().endswith(b'";') for line in lines
    )


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--icarus', required=True)
    parser.add_argument('--baseline', default=str(ROOT/'sim/reference_32901'))
    args = parser.parse_args()
    baseline = Path(args.baseline).resolve()
    ctypes.windll.kernel32.SetErrorMode(0x8003)
    os.chdir(ROOT)
    out = Path('sim/results/lcd_cn_equivalence')
    out.mkdir(parents=True, exist_ok=True)
    (out/'tmp').mkdir(exist_ok=True)
    generated = []
    for filename, module_name in [
        ('audio_record_ddr_top.v', 'audio_record_ddr_top'),
        ('audio_record_engine.v', 'audio_record_engine'),
        ('record_status_uart.v', 'record_status_uart'),
    ]:
        text = (baseline/'src'/filename).read_text(encoding='utf-8')
        text = re.sub(r'\b'+module_name+r'\b', module_name+'_baseline', text)
        if module_name == 'audio_record_ddr_top':
            text = re.sub(r'\baudio_record_engine\b', 'audio_record_engine_baseline', text)
        if module_name == 'audio_record_engine':
            text = re.sub(r'\brecord_status_uart\b', 'record_status_uart_baseline', text)
        path = out/(module_name+'_baseline.v')
        path.write_text(text, encoding='utf-8')
        generated.append(path)

    bench = (ROOT/'sim/tb_record_top_startup.sv').read_text(encoding='utf-8')
    bench = bench.replace('module tb_record_top_startup;', 'module tb_lcd_top_equivalence;')
    bench = bench.replace('initial begin #3000000;', 'initial begin #90000000;')
    bench = bench.replace('cycles<150000', 'cycles<1700000')
    bench = bench.replace('clocks(100);', 'clocks(1000100);', 1)
    bench = bench.replace('PASS RECORD_TOP_STARTUP', 'PASS LCD_TOP_EQUIVALENCE')
    bench = bench.replace('    audio_record_ddr_top dut(.*);', '''    audio_record_ddr_top dut(.*);
    wire ref_mic_bclk,ref_mic_ws,ref_HP_BCK,ref_HP_WS,ref_HP_DIN,ref_PA_EN;
    wire ref_WS2812,ref_uart_tx,ref_led_ck,ref_led_da;
    wire ref_memory_clk,ref_memory_clkn,ref_memory_cke,ref_memory_cs_n;
    wire ref_memory_cas_n,ref_memory_ras_n,ref_memory_we_n,ref_memory_reset_n,ref_memory_odt;
    wire [14:0] ref_memory_addr;wire [2:0] ref_memory_bank;
    wire [31:0] ref_memory_dq;wire [3:0] ref_memory_dqs,ref_memory_dqs_n,ref_memory_dm;
    wire ref_LCD_CLK,ref_LCD_HSYNC,ref_LCD_VSYNC,ref_LCD_DE,ref_LCD_BL;
    wire [5:0] ref_LCD_R,ref_LCD_G,ref_LCD_B;
    audio_record_ddr_top_baseline reference(
        .clk(clk),.rst_n(rst_n),.key_mode_n(key_mode_n),.key_gain_n(key_gain_n),.mic_sd(mic_sd),
        .mic_bclk(ref_mic_bclk),.mic_ws(ref_mic_ws),.HP_BCK(ref_HP_BCK),.HP_WS(ref_HP_WS),
        .HP_DIN(ref_HP_DIN),.PA_EN(ref_PA_EN),.WS2812(ref_WS2812),.uart_tx(ref_uart_tx),
        .led_ck(ref_led_ck),.led_da(ref_led_da),.memory_clk(ref_memory_clk),
        .memory_clkn(ref_memory_clkn),.memory_cke(ref_memory_cke),.memory_cs_n(ref_memory_cs_n),
        .memory_cas_n(ref_memory_cas_n),.memory_ras_n(ref_memory_ras_n),.memory_we_n(ref_memory_we_n),
        .memory_reset_n(ref_memory_reset_n),.memory_odt(ref_memory_odt),.memory_addr(ref_memory_addr),
        .memory_bank(ref_memory_bank),.memory_dq(ref_memory_dq),.memory_dqs(ref_memory_dqs),
        .memory_dqs_n(ref_memory_dqs_n),.memory_dm(ref_memory_dm),
        .LCD_CLK(ref_LCD_CLK),.LCD_HSYNC(ref_LCD_HSYNC),.LCD_VSYNC(ref_LCD_VSYNC),
        .LCD_DE(ref_LCD_DE),.LCD_BL(ref_LCD_BL),.LCD_R(ref_LCD_R),.LCD_G(ref_LCD_G),.LCD_B(ref_LCD_B));
    // Small-window equivalence exercises audible live output quickly.
    // The separate unchanged tb_record_engine_default uses the full window.
    defparam dut.u_audio.RAM_ADDR_BITS=8;
    defparam dut.u_audio.GRAIN_LOG2=6;
    defparam reference.u_audio.RAM_ADDR_BITS=8;
    defparam reference.u_audio.GRAIN_LOG2=6;
    defparam reference.u_audio.POR_CYCLES=8;
    defparam reference.u_audio.STARTUP_FRAMES=3;
    defparam reference.u_audio.DEBOUNCE_CYCLES=3;
    defparam reference.u_audio.LONG_PRESS_CYCLES=24;
    defparam reference.u_audio.MAX_SAMPLES=128;
    defparam reference.u_audio.UART_REPORT_CYCLES=1000000;
    defparam reference.u_bridge.BOOT_TIMEOUT_CYCLES=5000;
    integer equivalent_cycles=0,lcd_rising_edges=0,lcd_active_pixels=0,diagnostic_pixels=0;
    integer audio_ticks=0,app_requests=0,unmuted_frames=0,switch_wait=0;
    reg [5:0] mic_position=0;
    integer mic_frame=0;
    reg [23:0] microphone_word;
    always @(negedge mic_bclk)begin
        if(!dut.u_audio.run_n)begin mic_position=0;mic_frame=0;mic_sd=0;end
        else begin
            if(mic_position==63)mic_frame=mic_frame+1;
            mic_position=mic_position+1'b1;
            microphone_word=(((mic_frame%64)-32)*256)<<8;
            #2;
            mic_sd=(mic_position[4:0]>=1&&mic_position[4:0]<=24)?
                {4{microphone_word[24-mic_position[4:0]]}}:4'd0;
        end
    end
    always @(posedge LCD_CLK)begin
        lcd_rising_edges=lcd_rising_edges+1;
        if(LCD_DE)lcd_active_pixels=lcd_active_pixels+1;
        if(LCD_DE&&dut.lcd_test_mode)diagnostic_pixels=diagnostic_pixels+1;
    end
    always @(posedge clk)begin
        #2;
        if({LCD_CLK,LCD_HSYNC,LCD_VSYNC,LCD_DE,LCD_BL,dut.lcd_test_mode,dut.board_run_n} !==
           {ref_LCD_CLK,ref_LCD_HSYNC,ref_LCD_VSYNC,ref_LCD_DE,ref_LCD_BL,reference.lcd_test_mode,reference.board_run_n})
            $fatal(1,"Chinese UI changed LCD timing/backlight/diagnostic selection at cycle %0d",equivalent_cycles);
        if(dut.lcd_test_mode && {LCD_R,LCD_G,LCD_B}!=={ref_LCD_R,ref_LCD_G,ref_LCD_B})
            $fatal(1,"Chinese UI changed diagnostic RGB at cycle %0d",equivalent_cycles);
        if({mic_bclk,mic_ws,HP_BCK,HP_WS,HP_DIN,PA_EN,WS2812,led_ck,led_da} !==
           {ref_mic_bclk,ref_mic_ws,ref_HP_BCK,ref_HP_WS,ref_HP_DIN,ref_PA_EN,ref_WS2812,ref_led_ck,ref_led_da})
            $fatal(1,"LCD changed an audio/control output at cycle %0d",equivalent_cycles);
        if({memory_clk,memory_clkn,memory_cke,memory_cs_n,memory_cas_n,memory_ras_n,memory_we_n,
            memory_reset_n,memory_odt,memory_addr,memory_bank,memory_dq,memory_dqs,memory_dqs_n,memory_dm} !==
           {ref_memory_clk,ref_memory_clkn,ref_memory_cke,ref_memory_cs_n,ref_memory_cas_n,ref_memory_ras_n,
            ref_memory_we_n,ref_memory_reset_n,ref_memory_odt,ref_memory_addr,ref_memory_bank,
            ref_memory_dq,ref_memory_dqs,ref_memory_dqs_n,ref_memory_dm})
            $fatal(1,"LCD changed an external DDR output at cycle %0d",equivalent_cycles);
        if({dut.req_valid,dut.req_write,dut.req_addr,dut.req_wdata,dut.cmd,dut.cmd_en,dut.wr_en,dut.wr_end,dut.addr,dut.wr_data} !==
           {reference.req_valid,reference.req_write,reference.req_addr,reference.req_wdata,reference.cmd,
            reference.cmd_en,reference.wr_en,reference.wr_end,reference.addr,reference.wr_data})
            $fatal(1,"LCD changed DDR request/command/data at cycle %0d",equivalent_cycles);
        if({dut.audio_source,dut.u_audio.active_mode,dut.u_audio.active_algorithm_mode,
            dut.u_audio.active_pitch_semitones,dut.u_audio.gain_index,dut.u_audio.rec_state,
            dut.u_audio.record_valid,dut.u_audio.record_samples,dut.u_audio.record_progress,
            dut.u_audio.play_samples,dut.u_audio.storage_fault} !==
           {reference.audio_source,reference.u_audio.active_mode,reference.u_audio.active_algorithm_mode,
            reference.u_audio.active_pitch_semitones,reference.u_audio.gain_index,reference.u_audio.rec_state,
            reference.u_audio.record_valid,reference.u_audio.record_samples,reference.u_audio.record_progress,
            reference.u_audio.play_samples,reference.u_audio.storage_fault})
            $fatal(1,"LCD changed audio/recorder state at cycle %0d",equivalent_cycles);
        equivalent_cycles=equivalent_cycles+1;
        if(dut.u_audio.rx_valid)audio_ticks=audio_ticks+1;
        if(dut.req_valid&&dut.req_ready)app_requests=app_requests+1;
        if(dut.u_audio.frame_ce&&!PA_EN)unmuted_frames=unmuted_frames+1;
    end
''')
    bench = bench.replace('        fork', '''        solo;frames(160);
        check(dut.u_audio.active_mode==1 && !PA_EN,"live microphone path active during equivalence");
        solo;switch_wait=0;
        while(dut.u_audio.active_mode!=2&&switch_wait<600)begin frames(1);switch_wait=switch_wait+1;end
        frames(40);check(dut.u_audio.active_mode==2,"test-tone path active during equivalence");
        solo;switch_wait=0;
        while(dut.u_audio.active_mode!=0&&switch_wait<600)begin frames(1);switch_wait=switch_wait+1;end
        frames(10);check(dut.u_audio.active_mode==0,"return to mute before clip test");
        fork''', 1)
    bench = bench.replace('        $finish;', '''        // The original startup test ends with rst_n low. Use legal keys to
        // check that the shared 32901 diagnostic latch and bars still work.
        @(negedge clk);key_mode_n=1;key_gain_n=0;rst_n=1;
        wait(dut.board_run_n);clocks(8);
        check(dut.lcd_test_mode&&reference.lcd_test_mode,"KEY2 held during KEY1 release selects bars in both versions");
        @(negedge clk);key_gain_n=1;clocks(900906);
        check(diagnostic_pixels>=130560,"complete diagnostic frame compared including color data");
        @(negedge clk);rst_n=0;clocks(8);
        @(negedge clk);rst_n=1;wait(dut.board_run_n);clocks(16);
        check(!dut.lcd_test_mode&&!reference.lcd_test_mode,"ordinary reset restores dashboard selection");
        check(!dut.audio_source&&!dut.storage_started,"diagnostic boot never starts recording DDR");
        check(lcd_rising_edges>150150 && lcd_active_pixels>=130560,"LCD scans a complete active frame during comparison");
        check(equivalent_cycles>1000000 && audio_ticks>1000 && app_requests>0,"substantial clock and storage coverage");
        check(unmuted_frames>20,"nontrivial enabled microphone/test-tone output coverage");
        $display("PASS LCD_EQUIVALENCE_DETAIL compared_cycles=%0d audio_ticks=%0d DDR_app_requests=%0d LCD_pixels=%0d LCD_active=%0d unmuted_frames=%0d diagnostic_pixels=%0d UART_version_is_intentionally_different",
            equivalent_cycles,audio_ticks,app_requests,lcd_rising_edges,lcd_active_pixels,unmuted_frames,diagnostic_pixels);
        $finish;''', 1)
    bench_path = out/'tb_lcd_top_equivalence.sv'
    bench_path.write_text(bench, encoding='utf-8')
    sources = sorted(Path('src').glob('*.v')) + generated + [bench_path]
    baseline_inputs = [baseline/'src/audio_record_ddr_top.v', baseline/'src/audio_record_engine.v',
        baseline/'src/record_status_uart.v']
    frozen_names = {p.name for p in baseline_inputs}
    reference_manifest = baseline/'SOURCE_HASHES.json'
    if reference_manifest.is_file():
        baseline_inputs.append(reference_manifest)
        original_hashes = json.loads(reference_manifest.read_text(encoding='utf-8-sig'))['SourceHashes']
    else:
        original_hashes = {p.name:sha(p) for p in (baseline/'src').glob('*.v')}
    allowed_rendering_changes={'lcd_dashboard.v','lcd_font5x7.v'}
    candidate_top=Path('src/audio_record_ddr_top.v').read_text(encoding='utf-8-sig')
    baseline_top=(baseline/'src/audio_record_ddr_top.v').read_text(encoding='utf-8-sig')
    assert candidate_top.count("32'h00033001")==1
    assert candidate_top.replace("32'h00033001","32'h00032901")==baseline_top, 'Top changed beyond the release identity'
    for name,digest in original_hashes.items():
        if name in allowed_rendering_changes:
            continue
        path = baseline/'src'/name if name in frozen_names else Path('src')/name
        assert sha(path) == digest, 'Frozen/shared 32901 source changed: '+name
        if name in {'audio_record_engine.v','record_status_uart.v'}:
            assert sha(Path('src')/name)==digest, 'Engine/UART changed beyond permitted rendering scope: '+name
    font_assets=sorted(Path('src').glob('*.mem'))+sorted(Path('src').glob('*.vh'))
    tracked = sources + baseline_inputs + font_assets + [Path('sim/run_lcd_cn_equivalence.py')]
    hashes = {str(p): sha(p) for p in tracked}
    env = dict(os.environ)
    env.update(PATH=args.icarus+';'+env['PATH'],LANG='C',LC_ALL='C',
        TMP=str(out/'tmp'), TEMP=str(out/'tmp'), TMPDIR=str(out/'tmp'))
    lib = str(Path(args.icarus).parent/'lib/ivl')
    binary = out/'lcd_top_equivalence.vvp'
    command = [str(Path(args.icarus)/'iverilog.exe'), '-B', lib, '-g2012',
        '-gstrict-expr-width','-Wall','-s','tb_lcd_top_equivalence','-o',str(binary)] + list(map(str,sources))
    attempts=[]
    for attempt in range(1, 13):
        binary=out/('lcd_equivalence_cn'+('_x'*attempt)+'.vvp')
        command[command.index('-o')+1]=str(binary)
        result = subprocess.run(command,env=env,stdout=subprocess.PIPE,stderr=subprocess.STDOUT)
        attempts.append(result.returncode)
        (out/f'compile{attempt}.log').write_bytes(result.stdout)
        if result.returncode == 0 and complete_program(binary):
            break
        if result.returncode not in (0,3221225477,3221226356,-1073741819,-1073740940):
            raise RuntimeError(result.stdout.decode(errors='replace'))
    if result.returncode or not complete_program(binary):
        raise RuntimeError('Native compiler crashed or truncated executable repeatedly')
    started = time.monotonic()
    result = subprocess.run([str(Path(args.icarus)/'vvp.exe'),'-M',lib,str(binary)],
        env=env,stdout=subprocess.PIPE,stderr=subprocess.STDOUT)
    summary=result.stdout.decode(errors='replace')
    (out/'run.log').write_bytes(result.stdout)
    print(summary,flush=True)
    if result.returncode or 'PASS LCD_EQUIVALENCE_DETAIL' not in summary:
        raise RuntimeError('LCD equivalence failed')
    assert hashes == {str(p):sha(p) for p in tracked}, 'Inputs changed during equivalence run'
    report=dict(Passed=True,BaselineUserCode='0x00032901',CandidateUserCode='0x00033001',
        Compared='Audio/control/ring pins, DDR pins, application requests, native commands/data, recorder state, LCD timing/backlight/diagnostic latch, diagnostic RGB frame',
        UARTCompared=False,UARTReason='The candidate carries the new version identity.',
        PhysicalDDRModeled=False,HardwareValidated=False,CompileExitCodes=attempts,
        SharedSourceHashesMatch32901=True,TopIdentityOnlyChange=True,
        AllowedRenderingChanges=sorted(allowed_rendering_changes),OriginalSourceHashes=original_hashes,
        Seconds=time.monotonic()-started,SourceHashes=hashes,
        Summary=[line for line in summary.splitlines() if line.startswith('PASS')])
    (out/'LCD_CN_EQUIVALENCE.json').write_text(json.dumps(report,indent=2)+'\n',encoding='utf-8')


if __name__ == '__main__':
    main()
