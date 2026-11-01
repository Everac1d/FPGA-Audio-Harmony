"""Repeat the UART wire-protocol regression with the LCD release identity."""
from pathlib import Path
import argparse
import ctypes
import hashlib
import json
import os
import subprocess
from run import complete_program

ROOT = Path(__file__).resolve().parent.parent


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest().upper()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--icarus', required=True)
    args = parser.parse_args()
    ctypes.windll.kernel32.SetErrorMode(0x8003)
    os.chdir(ROOT)
    out=Path('sim/results/lcd_uart_version')
    out.mkdir(parents=True,exist_ok=True)
    (out/'tmp').mkdir(exist_ok=True)
    template=Path('sim/tb_record_status.sv')
    bench=template.read_text(encoding='utf-8')
    bench=bench.replace('module tb_record_status;', 'module tb_lcd_uart_version;')
    bench=bench.replace('.REPORT_CYCLES(REPORT)) dut (',
        ".REPORT_CYCLES(REPORT),.USER_CODE(32'h00033001)) dut (")
    bench=bench.replace('00032503','00033001').replace('PASS tb_record_status','PASS LCD_UART_VERSION')
    bench_path=out/'tb_lcd_uart_version.sv'
    bench_path.write_text(bench,encoding='utf-8')
    sources=[Path('src/record_status_uart.v'),bench_path]
    inputs=sources+[template,Path('sim/check_lcd_uart_version.py'),Path('sim/run.py')]
    hashes={str(p):sha(p) for p in inputs}
    lib=str(Path(args.icarus).parent/'lib/ivl')
    env=dict(os.environ)
    env.update(PATH=args.icarus+';'+env['PATH'],LANG='C',LC_ALL='C',
        TMP=str(out/'tmp'),TEMP=str(out/'tmp'),TMPDIR=str(out/'tmp'))
    binary=out/'lcd_uart_version.vvp'
    command=[str(Path(args.icarus)/'iverilog.exe'),'-B',lib,'-g2012',
        '-gstrict-expr-width','-Wall','-s','tb_lcd_uart_version','-o',str(binary)]+list(map(str,sources))
    attempts=[]
    for attempt in range(1,6):
        result=subprocess.run(command,env=env,stdout=subprocess.PIPE,stderr=subprocess.STDOUT)
        attempts.append(result.returncode)
        (out/f'compile{attempt}.log').write_bytes(result.stdout)
        if result.returncode==0 and complete_program(binary):
            break
        if result.returncode not in (0,3221225477,3221226356,-1073741819,-1073740940):
            raise RuntimeError(result.stdout.decode(errors='replace'))
    if result.returncode or not complete_program(binary):
        raise RuntimeError('Native compiler crashed or truncated executable repeatedly')
    result=subprocess.run([str(Path(args.icarus)/'vvp.exe'),'-M',lib,str(binary)],
        env=env,stdout=subprocess.PIPE,stderr=subprocess.STDOUT)
    (out/'run.log').write_bytes(result.stdout)
    summary=result.stdout.decode(errors='replace')
    print(summary,flush=True)
    assert result.returncode==0 and 'PASS LCD_UART_VERSION' in summary,'LCD UART version regression failed'
    assert hashes=={str(p):sha(p) for p in inputs},'UART regression inputs changed'
    report=dict(Passed=True,UserCode='0x00033001',WireProtocol='R3/D3',
        BytesChecked=801,CompileExitCodes=attempts,SourceHashes=hashes,
        Summary=[line for line in summary.splitlines() if line.startswith('PASS')],
        HardwareValidated=False,SerialPortOpened=False)
    (out/'LCD_UART_VERSION.json').write_text(json.dumps(report,indent=2)+'\n',encoding='utf-8')


if __name__=='__main__':
    main()
