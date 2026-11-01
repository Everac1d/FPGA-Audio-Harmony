"""Run changed LCD cases; native Icarus retries use distinct output names."""
from pathlib import Path
import argparse,ctypes,json,os,subprocess,time
from run import complete_program,sha

ROOT=Path(__file__).resolve().parent.parent
def main():
    ap=argparse.ArgumentParser();ap.add_argument('--icarus',required=True);ap.add_argument('cases',nargs='+');a=ap.parse_args()
    ctypes.windll.kernel32.SetErrorMode(0x8003);os.chdir(ROOT)
    out=Path('sim/results');(out/'tmp').mkdir(exist_ok=True)
    env=dict(os.environ);env.update(PATH=a.icarus+';'+env['PATH'],LANG='C',LC_ALL='C',LC_CTYPE='C',
        TMP='sim/results/tmp',TEMP='sim/results/tmp',TMPDIR='sim/results/tmp')
    lib=str(Path(a.icarus).parent/'lib/ivl');sources=sorted(Path('src').glob('*.v'))
    for case in a.cases:
        inputs=sources+sorted(Path('src').glob('*.mem'))+sorted(Path('src').glob('*.vh'))
        inputs+=sorted(Path('sim').glob('tb_*.sv'))+sorted(Path('sim/fixtures').glob('*'))
        inputs+=[Path('sim/run.py'),Path('sim/run_cn_checks.py')]
        hashes={p.as_posix():sha(p) for p in inputs};attempts=[];complete=[]
        for attempt in range(1,13):
            binary=out/(case+'_cn'+('_x'*attempt)+'.vvp')
            p=subprocess.run([str(Path(a.icarus)/'iverilog.exe'),'-B',lib,'-g2012','-gstrict-expr-width',
                '-Wall','-s',case,'-o',str(binary)]+list(map(str,sources))+['sim/'+case+'.sv'],
                env=env,stdout=subprocess.PIPE,stderr=subprocess.STDOUT)
            (out/(case+f'_compile_cn{attempt}.log')).write_bytes(p.stdout)
            attempts.append(p.returncode);complete.append(p.returncode==0 and complete_program(binary))
            if complete[-1]:break
            if p.returncode not in (0,3221225477,3221226356,-1073741819,-1073740940):
                raise RuntimeError(p.stdout.decode(errors='replace'))
        assert complete[-1],f'Native compiler failed {case}: {attempts}'
        started=time.time()
        p=subprocess.run([str(Path(a.icarus)/'vvp.exe'),'-M',lib,str(binary)],env=env,
            stdout=subprocess.PIPE,stderr=subprocess.STDOUT)
        (out/(case+'.log')).write_bytes(p.stdout);result=p.stdout.decode(errors='replace');print(result,flush=True)
        assert p.returncode==0 and 'PASS' in result,case
        assert hashes=={name:sha(ROOT/name) for name in hashes},'Inputs changed'
        record=dict(Passed=True,Case=case,CompileExitCodes=attempts,CompileArtifactsComplete=complete,
            ExecutableComplete=True,RuntimeExitCode=p.returncode,Seconds=time.time()-started,
            SourceHashes=hashes,Runner='sim/run_cn_checks.py',HardwareValidated=False,
            Summary=[line for line in result.splitlines() if line.startswith(('PASS','MEASURE'))])
        (out/('validation_'+case+'.json')).write_text(json.dumps(record,indent=2)+'\n')
    print('PASS CHANGED LCD CASES',flush=True)
if __name__=='__main__':main()
