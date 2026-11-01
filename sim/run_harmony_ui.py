"""Run the new panel/display tests with their explicit source dependency set.

This avoids treating unrelated, concurrently edited audio RTL as a runtime
input. All actual modules, recursive test includes, ROMs, text headers and the
runner are hashed before execution and rechecked after it.
"""
from pathlib import Path
import argparse,ctypes,hashlib,json,os,re,subprocess,time
ROOT=Path(__file__).resolve().parents[1]
DISPLAY=['audio_harmony_lcd_display.v','lcd_harmony_status_snapshot.v','lcd_harmony_dashboard.v','lcd_harmony_cjk24_font.v','lcd_harmony_cjk16_font.v','lcd_rgb_timing.v']
ASSETS=['src/lcd_ui_text.vh','src/lcd_harmony_text.vh','src/lcd_harmony_cjk24.mem','src/lcd_harmony_cjk16.mem']
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest().upper()
def complete(p):
    if not p.exists():return False
    m=re.search(rb'\n:file_names (\d+);\r?\n(.*)\Z',p.read_bytes(),re.S)
    return bool(m and len(m[2].strip().splitlines())==int(m[1]) and all(x.strip().startswith(b'"') and x.strip().endswith(b'";') for x in m[2].strip().splitlines()))
def main():
    ap=argparse.ArgumentParser();ap.add_argument('--icarus',required=True);ap.add_argument('cases',nargs='+');a=ap.parse_args()
    os.chdir(ROOT);ctypes.windll.kernel32.SetErrorMode(0x8003);out=Path('sim/results');out.mkdir(exist_ok=True);(out/'tmp').mkdir(exist_ok=True)
    lib=str(Path(a.icarus).parent/'lib/ivl');env=dict(os.environ);env.update(PATH=a.icarus+';'+env['PATH'],LANG='C',LC_ALL='C',TMP='sim/results/tmp',TEMP='sim/results/tmp',TMPDIR='sim/results/tmp')
    for case in a.cases:
        names=['audio_harmony_controls.v','audio_external_controls.v'] if case=='tb_harmony_panel' else DISPLAY
        sources=['src/'+n for n in names];assets=[] if case=='tb_harmony_panel' else ASSETS
        tests=['sim/'+case+'.sv']
        if case=='tb_ring_calibration_lcd':tests+=['sim/tb_harmony_lcd.sv']
        inputs=sources+assets+tests+['sim/run_harmony_ui.py'];hashes={n:sha(ROOT/n) for n in inputs}
        binary=out/(case+'.vvp');attempts=[];artifacts=[]
        command=[str(Path(a.icarus)/'iverilog.exe'),'-B',lib,'-g2012','-gstrict-expr-width','-Wall','-s',case,'-o',str(binary)]+sources+[tests[0]]
        for attempt in range(1,6):
            result=subprocess.run(command,env=env,stdout=subprocess.PIPE,stderr=subprocess.STDOUT);attempts.append(result.returncode);artifacts.append(result.returncode==0 and complete(binary))
            (out/(case+'_compile'+str(attempt)+'.log')).write_bytes(result.stdout)
            if artifacts[-1]:break
            if result.returncode not in (0,3221225477,3221226356,-1073741819,-1073740940):raise RuntimeError(result.stdout.decode(errors='replace'))
        assert artifacts[-1],'Incomplete native VVP '+case
        started=time.time();result=subprocess.run([str(Path(a.icarus)/'vvp.exe'),'-M',lib,str(binary)],env=env,stdout=subprocess.PIPE,stderr=subprocess.STDOUT)
        (out/(case+'.log')).write_bytes(result.stdout);text=result.stdout.decode(errors='replace');print(text,flush=True)
        assert result.returncode==0 and 'PASS' in text,'Runtime failed '+case
        assert hashes=={n:sha(ROOT/n) for n in inputs},'Actual test input changed '+case
        report=dict(Passed=True,Case=case,CompileExitCodes=attempts,CompileArtifactsComplete=artifacts,ExecutableComplete=True,RuntimeExitCode=0,Seconds=time.time()-started,
            SourceHashes=hashes,CompiledSources=sources,DependencyMethod='Explicit module source set plus recursive test include and ROM/header inputs',
            Summary=[s for s in text.splitlines() if s.startswith(('PASS','MEASURE'))],HardwareValidated=False)
        (out/('validation_'+case+'.json')).write_text(json.dumps(report,indent=2)+'\n',encoding='utf-8')
    print('PASS HARMONY_UI_SIM cases='+str(len(a.cases)),flush=True)
if __name__=='__main__':main()
