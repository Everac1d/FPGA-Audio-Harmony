"""Fresh LCD-only checks while unrelated integration files are being edited."""
from pathlib import Path
import ctypes,hashlib,json,os,re,subprocess,time

ROOT=Path(__file__).resolve().parents[1]
ICARUS=ROOT.parents[1]/'06_tools/icarus/ucrt64'
CASES={
    'tb_lcd_dashboard':['lcd_dashboard','lcd_cjk24_font'],
    'tb_lcd_snapshot':['lcd_status_snapshot'],
    'tb_lcd_fine_scan':['audio_lcd_display','lcd_dashboard','lcd_cjk24_font','lcd_status_snapshot','lcd_rgb_timing'],
}
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest().upper()
def complete(p):
    if not p.exists():return False
    m=re.search(rb'\n:file_names (\d+);\r?\n(.*)\Z',p.read_bytes(),re.S)
    return bool(m and len(m[2].strip().splitlines())==int(m[1]) and all(x.strip().endswith(b'";') for x in m[2].strip().splitlines()))
def main():
    ctypes.windll.kernel32.SetErrorMode(0x8003)
    owned=[]
    try:
        for drive,target in [('Q:',ROOT),('S:',ICARUS)]:
            if Path(drive+'/').exists():raise RuntimeError('Drive already occupied: '+drive)
            subprocess.run(['subst',drive,str(target)],check=True);owned.append(drive)
        os.chdir('Q:/')
        out=Path('sim/results');out.mkdir(exist_ok=True);(out/'tmp').mkdir(exist_ok=True)
        env=dict(os.environ,PATH='S:\\bin;'+os.environ['PATH'],TMP='Q:/sim/results/tmp',TEMP='Q:/sim/results/tmp',TMPDIR='Q:/sim/results/tmp')
        for case,modules in CASES.items():
            files=[Path('src')/(x+'.v') for x in modules]+[Path('sim')/(case+'.sv')]
            inputs=files+[Path('src/lcd_cjk24.mem'),Path('src/lcd_ui_text.vh'),Path('sim/run_lcd_fine_independent.py')]
            hashes={p.as_posix():sha(p) for p in inputs}
            output=out/(case+'_independent.vvp');codes=[];artifacts=[]
            for attempt in range(1,6):
                result=subprocess.run([r'S:\bin\iverilog.exe','-B',r'S:\lib\ivl','-g2012','-gstrict-expr-width','-Wall','-s',case,'-o',str(output)]+list(map(str,files)),env=env,stdout=subprocess.PIPE,stderr=subprocess.STDOUT)
                (out/(case+'_independent_compile'+str(attempt)+'.log')).write_bytes(result.stdout)
                codes.append(result.returncode);artifacts.append(result.returncode==0 and complete(output))
                if artifacts[-1]:break
                if result.returncode not in (0,3221225477,3221226356,-1073741819,-1073740940):
                    raise RuntimeError(result.stdout.decode(errors='replace'))
            if not artifacts[-1]:raise RuntimeError('Incomplete compile '+case)
            started=time.time()
            result=subprocess.run([r'S:\bin\vvp.exe','-M',r'S:\lib\ivl',str(output)],env=env,stdout=subprocess.PIPE,stderr=subprocess.STDOUT)
            (out/(case+'_independent.log')).write_bytes(result.stdout)
            print(result.stdout.decode(errors='replace'),flush=True)
            assert result.returncode==0 and b'PASS' in result.stdout,case+' failed'
            assert hashes=={p.as_posix():sha(p) for p in inputs},case+' inputs changed'
            report=dict(Passed=True,Case=case,CompileExitCodes=codes,CompileArtifactsComplete=artifacts,ExecutableComplete=True,RuntimeExitCode=0,Seconds=time.time()-started,SourceHashes=hashes,Summary=[x for x in result.stdout.decode().splitlines() if x.startswith('PASS')],HardwareValidated=False)
            (out/('validation_'+case+'_independent.json')).write_text(json.dumps(report,indent=2)+'\n',encoding='utf-8')
        print('PASS LCD_FINE_INDEPENDENT cases=3',flush=True)
    finally:
        os.chdir(str(ROOT))
        for drive in reversed(owned):subprocess.run(['subst',drive,'/D'],check=True)
if __name__=='__main__':main()
