"""Re-elaborate unchanged tests and retain the exact 32901 runtime evidence.

The VVP filename table and module scopes describe the elaborated design;
Icarus -M includes unused command-line inputs and is deliberately not used.
No simulation runtime is claimed for a reused case in the current release.
"""
from pathlib import Path
import argparse
import ctypes
import difflib
import hashlib
import json
import os
import re
import subprocess
import time
from run import complete_program

ROOT=Path(__file__).resolve().parent.parent
REFERENCE=ROOT/'sim/reference_32901'
FRESH_CASES={'tb_lcd_dashboard','tb_lcd_boot_diagnostics','tb_record_top_startup'}
FORBIDDEN_REUSE={'src/audio_record_ddr_top.v','src/audio_lcd_display.v',
    'src/lcd_dashboard.v','src/lcd_font5x7.v','src/lcd_cjk24_font.v'}


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest().upper()


def read(path):
    return json.loads(path.read_text(encoding='utf-8-sig'))


def write(path,value):
    path.write_text(json.dumps(value,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')


def relative(path):
    return path.relative_to(ROOT).as_posix()


def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('--icarus',required=True)
    args=parser.parse_args()
    os.chdir(ROOT)
    ctypes.windll.kernel32.SetErrorMode(0x8003)
    out=Path('sim/results/reuse_32901');out.mkdir(parents=True,exist_ok=True)
    (out/'tmp').mkdir(exist_ok=True)
    origin=read(REFERENCE/'ORIGINAL_MANIFEST.json')
    assert origin['UserCode']=='0x00032901'
    original_runner=(REFERENCE/'run.py').read_text(encoding='utf-8-sig')
    current_runner=Path('sim/run.py').read_text(encoding='utf-8-sig')
    old_line="inputs=sources+[Path('sim')/(case+'.sv'),Path('sim/run.py')]+sorted(Path('sim/fixtures').glob('*'))"
    new_line="inputs=sources+sorted(Path('src').glob('*.mem'))+sorted(Path('src').glob('*.vh'))+[Path('sim')/(case+'.sv'),Path('sim/run.py')]+sorted(Path('sim/fixtures').glob('*'))"
    assert original_runner.count(old_line)==1
    assert current_runner==original_runner.replace(old_line,new_line), 'Runner changed beyond adding asset hashes'
    assert sha(REFERENCE/'run.py')==origin['Files']['sim/run.py']
    runner_diff=''.join(difflib.unified_diff(original_runner.splitlines(True),current_runner.splitlines(True),
        fromfile='32901/sim/run.py',tofile='33001/sim/run.py'))
    (out/'runner_hash_collection_only.diff').write_text(runner_diff,encoding='utf-8')
    # Unused modules may not introduce a global macro/nettype/timescale change
    # that silently affects an otherwise unchanged, elaborated source file.
    global_directives=[]
    directive=re.compile(r'^\s*`(define|undef|undefineall|default_nettype|resetall|timescale|celldefine|endcelldefine|begin_keywords|end_keywords)\b',re.M)
    for path in sorted(Path('src').glob('*')):
        if path.suffix not in ('.v','.vh'):
            continue
        text=path.read_text(encoding='utf-8-sig')
        if directive.search(text):
            global_directives.append(path.as_posix())
    assert not global_directives,'Global source directives require explicit review: '+str(global_directives)
    lib=str(Path(args.icarus).parent/'lib/ivl')
    env=dict(os.environ)
    env.update(PATH=args.icarus+';'+env['PATH'],LANG='C',LC_ALL='C',
        TMP=str(out/'tmp'),TEMP=str(out/'tmp'),TMPDIR=str(out/'tmp'))
    all_sources=sorted(Path('src').glob('*.v'))
    asset_hashes={p.as_posix():sha(p) for p in sorted(Path('src').glob('*')) if p.is_file()}
    candidates=sorted(p.stem for p in Path('sim').glob('tb_*.sv'))
    assert len(candidates)==19 and FRESH_CASES.issubset(candidates)
    reused=[]
    for case in candidates:
        if case in FRESH_CASES:
            continue
        original_report=REFERENCE/'results'/('validation_'+case+'.json')
        original_log=REFERENCE/'results'/(case+'.log')
        assert sha(original_report)==origin['Files']['sim/results/'+original_report.name]
        assert sha(original_log)==origin['Files']['sim/results/'+original_log.name]
        old=read(original_report)
        assert old['Passed'] and old['ExecutableComplete'] and old['RuntimeExitCode']==0
        assert 'PASS' in original_log.read_text(encoding='utf-8-sig')
        binary=out/(case+'.vvp')
        command=[str(Path(args.icarus)/'iverilog.exe'),'-B',lib,'-g2012','-gstrict-expr-width',
            '-Wall','-s',case,'-o',str(binary)]+list(map(str,all_sources))+['sim/'+case+'.sv']
        attempts=[];started=time.monotonic()
        for attempt in range(1,6):
            result=subprocess.run(command,env=env,stdout=subprocess.PIPE,stderr=subprocess.STDOUT)
            attempts.append(result.returncode)
            (out/(case+f'_compile{attempt}.log')).write_bytes(result.stdout)
            if result.returncode==0 and complete_program(binary):
                break
            if result.returncode not in (0,3221225477,3221226356,-1073741819,-1073740940):
                raise RuntimeError(result.stdout.decode(errors='replace'))
        assert result.returncode==0 and complete_program(binary), 'Incomplete elaboration '+case
        executable=binary.read_text(encoding='utf-8-sig')
        footer=re.search(r'\n:file_names (\d+);\r?\n(.*)\Z',executable,re.S)
        assert footer is not None
        filenames=re.findall(r'^\s*"(.*)";\s*$',footer[2],re.M)
        assert len(filenames)==int(footer[1])
        dependencies=sorted({Path(name.replace('\\','/')).as_posix() for name in filenames
            if name not in {'N/A','<interactive>','-'}})
        assert not FORBIDDEN_REUSE.intersection(dependencies),'Changed UI/top appears in '+case
        assert 'sim/'+case+'.sv' in dependencies
        scopes=[line for line in executable.splitlines() if '.scope module,' in line]
        assert scopes
        for name in dependencies:
            assert name in old['SourceHashes'], 'Dependency absent in original report: '+name
            assert sha(Path(name))==old['SourceHashes'][name], 'Elaborated source changed: '+name
        fixture_paths=sorted(Path('sim/fixtures').glob('*'))
        for path in fixture_paths:
            assert sha(path)==old['SourceHashes'][path.as_posix()]
        assert sha(Path('sim/'+case+'.sv'))==old['SourceHashes']['sim/'+case+'.sv']
        scope_path=out/(case+'_elaboration.txt')
        scope_path.write_text('\n'.join(scopes)+'\n\n:file_names '+footer[1]+';\n'+footer[2],encoding='utf-8')
        proof=dict(Passed=True,Case=case,ReusedFromUserCode='0x00032901',
            Method='Current complete Icarus VVP module scopes and elaborated filename table; exact source/test/fixture hash comparison',
            ElaboratedDependencies=dependencies,ElaboratedModules=scopes,
            ElaborationArtifactPath=binary.as_posix(),ElaborationArtifactSHA256=sha(binary),
            ScopeExtractPath=scope_path.as_posix(),ScopeExtractSHA256=sha(scope_path),
            CompilerArguments=command,CompileExitCodes=attempts,CompileComplete=True,
            CurrentCompileSeconds=time.monotonic()-started,RuntimeExecutedThisRelease=False,
            OriginalReportPath=relative(original_report),OriginalReportSHA256=sha(original_report),
            OriginalLogPath=relative(original_log),OriginalLogSHA256=sha(original_log),
            OriginalRunnerPath=relative(REFERENCE/'run.py'),OriginalRunnerSHA256=sha(REFERENCE/'run.py'),
            CurrentRunnerPath='sim/run.py',CurrentRunnerSHA256=sha(Path('sim/run.py')),
            RunnerChange='Only add src/*.mem and src/*.vh to recorded input hashes; compile/runtime commands unchanged',
            RunnerDiffPath=(out/'runner_hash_collection_only.diff').as_posix(),
            RunnerDiffSHA256=sha(out/'runner_hash_collection_only.diff'),
            GlobalSourceDirectives=[],DependencyHashes={name:sha(Path(name)) for name in dependencies},
            FixtureHashes={p.as_posix():sha(p) for p in fixture_paths})
        proof_path=out/(case+'_dependency_proof.json');write(proof_path,proof)
        checked=[Path(name) for name in dependencies]+fixture_paths+[Path('sim/run.py')]
        current=dict(old)
        current.update(ReusedFromUserCode='0x00032901',ReusedFrom32901=True,
            RuntimeExecutedThisRelease=False,OriginalRuntimeSeconds=old['Seconds'],
            OriginalReportPath=relative(original_report),OriginalReportSHA256=sha(original_report),
            OriginalLogPath=relative(original_log),OriginalLogSHA256=sha(original_log),
            DependencyProofPath=proof_path.as_posix(),DependencyProofSHA256=sha(proof_path),
            SourceHashes={p.as_posix():sha(p) for p in sorted(set(checked))},
            CurrentElaborationCompileExitCodes=attempts,CurrentElaborationComplete=True)
        write(Path('sim/results')/('validation_'+case+'.json'),current)
        reused.append(dict(Case=case,OriginalReportSHA256=sha(original_report),
            DependencyProofPath=proof_path.as_posix(),DependencyProofSHA256=sha(proof_path),
            DependencyCount=len(dependencies),RuntimeExecutedThisRelease=False))
        print('PASS REUSE_32901 '+case+' elaborated_files='+str(len(dependencies)),flush=True)
    assert asset_hashes=={p.as_posix():sha(p) for p in sorted(Path('src').glob('*')) if p.is_file()},'Source/assets changed during reuse audit'
    report=dict(Passed=True,BaselineUserCode='0x00032901',CandidateUserCode='0x00033001',
        FreshCases=sorted(FRESH_CASES),ReusedCases=[d['Case'] for d in reused],ReuseCount=len(reused),
        ReusedRuntimeIsExplicit=True,SourceAssetsStable=True,
        OriginalManifestPath=relative(REFERENCE/'ORIGINAL_MANIFEST.json'),
        OriginalManifestSHA256=sha(REFERENCE/'ORIGINAL_MANIFEST.json'),
        AuditScriptPath='sim/audit_reuse_32901.py',AuditScriptSHA256=sha(Path('sim/audit_reuse_32901.py')),
        RunnerChangeDiffPath=(out/'runner_hash_collection_only.diff').as_posix(),
        RunnerChangeDiffSHA256=sha(out/'runner_hash_collection_only.diff'),Records=reused)
    write(Path('sim/results/REGRESSION_REUSE_AUDIT.json'),report)
    print('PASS REGRESSION_REUSE_AUDIT reused='+str(len(reused))+' fresh_required='+str(len(FRESH_CASES)),flush=True)


if __name__=='__main__':
    main()
