from pathlib import Path
import argparse,os,subprocess,hashlib,json,ctypes,time,re
ROOT=Path(__file__).parent.parent
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest().upper()
def complete_program(p):
    # This Windows Icarus build can exit zero after truncating the VVP file.
    # Validate the complete filename-table footer before running any test.
    if not p.is_file():return False
    m=re.search(rb'\n:file_names (\d+);\r?\n(.*)\Z',p.read_bytes(),re.S)
    if not m:return False
    lines=m[2].strip().splitlines()
    return len(lines)==int(m[1]) and all(x.strip().startswith(b'"') and x.strip().endswith(b'";') for x in lines)
def main():
    ap=argparse.ArgumentParser();ap.add_argument('--icarus',required=True);ap.add_argument('cases',nargs='*');a=ap.parse_args()
    ctypes.windll.kernel32.SetErrorMode(0x8003)
    os.chdir(ROOT);out=Path('sim/results');out.mkdir(exist_ok=True);(out/'tmp').mkdir(exist_ok=True)
    env=dict(os.environ);env.update(PATH=a.icarus+';'+env['PATH'],LANG='C',LC_ALL='C',TMP='sim/results/tmp',TEMP='sim/results/tmp',TMPDIR='sim/results/tmp')
    lib=str(Path(a.icarus).parent/'lib/ivl');sources=[Path(n) for n in ['src/audio_harmony_core.v','src/pcm_harmony_read_pitch.v','src/pcm_harmony_voice_mixer.v','src/pcm_crossfade.v']]
    cases=a.cases or ['tb_harmony_spectrum']
    for case in cases:
        inputs=sources+[Path('sim')/(case+'.sv'),Path('sim/run_harmony_spectrum.py')]
        hashes={p.as_posix():sha(p) for p in inputs};attempts=[];artifacts=[];output=out/(case+'.vvp')
        cmd=[str(Path(a.icarus)/'iverilog.exe'),'-B',lib,'-g2012','-gstrict-expr-width','-Wall','-s',case,'-o',str(output)]+list(map(str,sources))+['sim/'+case+'.sv']
        for attempt in range(1,6):
            result=subprocess.run(cmd,env=env,stdout=subprocess.PIPE,stderr=subprocess.STDOUT)
            (out/(case+'_compile'+str(attempt)+'.log')).write_bytes(result.stdout)
            attempts.append(result.returncode)
            artifacts.append(result.returncode==0 and complete_program(output))
            if artifacts[-1]:break
            if result.returncode==0:
                with (out/(case+'_compile'+str(attempt)+'.log')).open('ab') as f:f.write(b'\nINCOMPLETE VVP artifact: retrying native compiler\n')
                continue
            if result.returncode not in (3221225477,3221226356,-1073741819,-1073740940):raise RuntimeError(result.stdout.decode(errors='replace'))
        if result.returncode or not artifacts[-1]:raise RuntimeError('Repeated native compiler crash/truncation '+case)
        started=time.time();result=subprocess.run([str(Path(a.icarus)/'vvp.exe'),'-M',lib,str(output)],env=env,stdout=subprocess.PIPE,stderr=subprocess.STDOUT)
        (out/(case+'.log')).write_bytes(result.stdout);s=result.stdout.decode(errors='replace');print(s,flush=True)
        if result.returncode or 'PASS' not in s:raise RuntimeError('Failed '+case)
        assert hashes=={p.as_posix():sha(p) for p in inputs},'Simulation inputs changed'
        doc=dict(Passed=True,Case=case,CompileExitCodes=attempts,CompileArtifactsComplete=artifacts,ExecutableComplete=True,RuntimeExitCode=result.returncode,Seconds=time.time()-started,SourceHashes=hashes,Summary=[l for l in s.splitlines() if l.startswith(('PASS','MEASURE'))],HardwareValidated=False)
        (out/('validation_'+case+'.json')).write_text(json.dumps(doc,indent=2)+'\n',encoding='utf-8')
    print('PASS SIMULATION cases='+str(len(cases)),flush=True)
if __name__=='__main__':main()
