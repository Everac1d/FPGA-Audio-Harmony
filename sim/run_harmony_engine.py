"""Focused real-I2S/DAC/DDR integration regression for the harmony engine."""
from pathlib import Path
import argparse,ctypes,hashlib,json,os,re,subprocess,time
ROOT=Path(__file__).resolve().parents[1]
SOURCES=['audio_harmony_engine.v','audio_harmony_controls.v','audio_external_controls.v','audio_record_keys.v',
    'audio_test_clock.v','mic_array_pcm.v','mic_i2s_rx.v','pcm_long_clip_controller.v','audio_harmony_core.v',
    'pcm_harmony_read_pitch.v','pcm_harmony_voice_mixer.v','pcm_crossfade.v','pcm_voice_conditioner.v',
    'pcm_output_queue.v','pcm_monitor_guard.v','pt8211_stereo_tx.v','audio_ring_cal_meter.v',
    'audio_ring_palette.v','sk9822_ring.v','status_ws2812.v','record_long_status_uart.v']
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest().upper()
def complete(p):
    if not p.exists():return False
    match=re.search(rb'\n:file_names (\d+);\r?\n(.*)\Z',p.read_bytes(),re.S)
    return bool(match and len(match[2].strip().splitlines())==int(match[1]) and all(line.strip().startswith(b'"') and line.strip().endswith(b'";') for line in match[2].strip().splitlines()))
def main():
    ap=argparse.ArgumentParser();ap.add_argument('--icarus',required=True);args=ap.parse_args()
    os.chdir(ROOT);ctypes.windll.kernel32.SetErrorMode(0x8003);out=Path('sim/results');out.mkdir(exist_ok=True);(out/'tmp').mkdir(exist_ok=True)
    lib=str(Path(args.icarus).parent/'lib/ivl');env=dict(os.environ);env.update(PATH=args.icarus+';'+env['PATH'],LANG='C',LC_ALL='C',TMP='sim/results/tmp',TEMP='sim/results/tmp',TMPDIR='sim/results/tmp')
    case='tb_harmony_engine';sources=['src/'+name for name in SOURCES];inputs=sources+['sim/'+case+'.sv','sim/run_harmony_engine.py'];hashes={name:sha(ROOT/name) for name in inputs}
    binary=out/(case+'.vvp');attempts=[];artifacts=[]
    command=[str(Path(args.icarus)/'iverilog.exe'),'-B',lib,'-g2012','-gstrict-expr-width','-Wall','-s',case,'-o',str(binary)]+sources+['sim/'+case+'.sv']
    for attempt in range(1,6):
        result=subprocess.run(command,env=env,stdout=subprocess.PIPE,stderr=subprocess.STDOUT);attempts.append(result.returncode);artifacts.append(result.returncode==0 and complete(binary))
        (out/(case+'_compile'+str(attempt)+'.log')).write_bytes(result.stdout)
        if artifacts[-1]:break
        if result.returncode not in (0,3221225477,3221226356,-1073741819,-1073740940):raise RuntimeError(result.stdout.decode(errors='replace'))
    assert artifacts[-1],'Incomplete native VVP'
    started=time.time();result=subprocess.run([str(Path(args.icarus)/'vvp.exe'),'-M',lib,str(binary)],env=env,stdout=subprocess.PIPE,stderr=subprocess.STDOUT)
    (out/(case+'.log')).write_bytes(result.stdout);output=result.stdout.decode(errors='replace');print(output,flush=True)
    assert result.returncode==0 and 'PASS HARMONY_ENGINE' in output,'Runtime failed'
    assert hashes=={name:sha(ROOT/name) for name in inputs},'Actual engine test input changed'
    report=dict(Passed=True,Case=case,CompileExitCodes=attempts,CompileArtifactsComplete=artifacts,ExecutableComplete=True,RuntimeExitCode=0,Seconds=time.time()-started,SourceHashes=hashes,
        CompiledSources=sources,DependencyMethod='Explicit module/source closure, standalone TB and exact runner; no external fixture or ROM',Summary=[s for s in output.splitlines() if s.startswith(('PASS','MEASURE'))],HardwareValidated=False)
    (out/('validation_'+case+'.json')).write_text(json.dumps(report,indent=2)+'\n',encoding='utf-8')
    print('PASS HARMONY_ENGINE_SIM cases=1',flush=True)
if __name__=='__main__':main()
