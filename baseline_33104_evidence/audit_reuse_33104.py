"""Re-elaborate unchanged 33104 cases; retain, never re-label, old runtime.

Scope source locations and parameter signatures, recursive include hashes,
fixtures and the exact runner are compared against the frozen 28 release.
The complete filename table alone is not treated as a dependency list.
"""
from pathlib import Path
import argparse,ctypes,hashlib,json,os,re,shutil,subprocess,time

FRESH_OLD=set()
FORBIDDEN={'src/audio_record_ddr_top.v'}
SPECIAL={'N/A','<interactive>','-'}
GLOBAL=re.compile(r'^\s*`(define|undef|undefineall|default_nettype|resetall|timescale|celldefine|endcelldefine|begin_keywords|end_keywords)\b',re.M)

def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest().upper()
def read(p):return json.loads(p.read_text(encoding='utf-8-sig'))
def write(p,d):p.parent.mkdir(parents=True,exist_ok=True);p.write_text(json.dumps(d,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
def norm(s):return Path(s.replace('\\','/')).as_posix().removeprefix('./')
def rel(p,root):return p.relative_to(root).as_posix()
def complete_program(p):
    if not p.is_file():return False
    m=re.search(rb'\n:file_names (\d+);\r?\n(.*)\Z',p.read_bytes(),re.S)
    return bool(m and len(m[2].strip().splitlines())==int(m[1]) and
        all(x.strip().startswith(b'"') and x.strip().endswith(b'";') for x in m[2].strip().splitlines()))

def parse_vvp(p):
    assert complete_program(p),'Incomplete VVP '+str(p)
    # VPI loader paths in old Windows artifacts can contain OEM/ANSI bytes;
    # elaborated project filenames and scope metadata below are ASCII.
    text=p.read_text(encoding='utf-8-sig',errors='surrogateescape')
    footer=re.search(r'\n:file_names (\d+);\r?\n(.*)\Z',text,re.S)
    names=[norm(s) if s not in SPECIAL else s for s in re.findall(r'^\s*"(.*)";\s*$',footer[2],re.M)]
    assert len(names)==int(footer[1])
    entries={};current=None;raw=[];dependencies=set()
    for line in text.splitlines():
        m=re.match(r'^(S_[0-9A-Fa-f]+) \.scope ([^,]+), "([^"]*)" "([^"]*)" (.*);$',line)
        if m:
            ident,kind,inst,typ,tail=m.groups();parts=tail.split(',')
            first=re.match(r'\s*(\d+)\s+(\d+)',parts[0]);assert first,line
            first_index,first_line=map(int,first.groups())
            definition=re.match(r'\s*(\d+)\s+(\d+)',parts[1]) if len(parts)>1 else None
            def_index,def_line=map(int,definition.groups()) if definition else (first_index,first_line)
            parent_ids=re.findall(r'\bS_[0-9A-Fa-f]+\b',tail)
            parent=parent_ids[-1] if parent_ids else None
            e=dict(Kind=kind,Instance=inst,Type=typ,Parent=parent,
                InstantiationSource=names[first_index],InstantiationLine=first_line,
                DefinitionSource=names[def_index],DefinitionLine=def_line,Parameters=[])
            entries[ident]=e;current=ident;raw.append(line)
            for idx in (first_index,def_index):
                if names[idx] not in SPECIAL:dependencies.add(names[idx])
        elif '.param/' in line:
            m=re.search(r'\.param/([^ ]+) "([^"]+)" (\d+) (\d+) (\d+), (.*?);(?:.*)$',line)
            assert m and current,line
            kind,name,signed,file_id,line_number,value=m.groups()
            source=names[int(file_id)]
            if source not in SPECIAL:dependencies.add(source)
            entries[current]['Parameters'].append(dict(Kind=kind,Name=name,Signed=int(signed),
                Source=source,Line=int(line_number),Value=value))
            raw.append(line)
    def path(ident,seen=None):
        seen=set() if seen is None else seen
        assert ident not in seen;seen.add(ident)
        e=entries[ident]
        return (path(e['Parent'],seen)+'.' if e['Parent'] else '')+e['Instance']
    signatures=[]
    for ident,e in entries.items():
        if e['Kind']=='package' and e['DefinitionSource'] in SPECIAL:continue
        record={k:v for k,v in e.items() if k!='Parent'}
        record['Path']=path(ident)
        record['Parameters']=sorted(record['Parameters'],key=lambda p:(p['Name'],p['Source'],p['Line']))
        signatures.append(record)
    signatures.sort(key=lambda e:(e['Path'],e['Kind'],e['DefinitionSource'],e['DefinitionLine']))
    assert any(e['Kind']=='module' for e in signatures)
    version=re.search(r'^:ivl_version (.*);$',text,re.M)
    return dict(CompilerStamp=version[1],Dependencies=sorted(dependencies),Scopes=signatures,
                FilenameTable=names,RawScopeAndParameters=raw)

def include_closure(root,dependencies):
    done=set();todo=list(dependencies)
    while todo:
        name=norm(todo.pop())
        if name in done:continue
        p=root/name;assert p.is_file(),'Missing elaborated source '+name
        done.add(name)
        if p.suffix not in ('.v','.vh','.sv'):continue
        content=p.read_text(encoding='utf-8-sig')
        assert '$system' not in content,'External dynamic fixture discovery requires review '+name
        for included in re.findall(r'^\s*`include\s+"([^"]+)"',content,re.M):
            included=norm(included)
            choices=[root/included,p.parent/included]
            found=next((q for q in choices if q.is_file()),None)
            assert found is not None,'Missing include '+included
            # Native simulator include search has no -I flag: cwd, then source.
            todo.append(found.relative_to(root).as_posix())
    return sorted(done)


def static_readmem_assets(root,deps):
    found=set()
    for name in deps:
        p=root/name
        if p.suffix not in ('.v','.vh','.sv'):continue
        s=p.read_text(encoding='utf-8-sig')
        s=re.sub(r'/\*.*?\*/|//[^\n]*','',s,flags=re.S)
        calls=re.findall(r'\$readmem[hb]\s*\(',s)
        names=re.findall(r'\$readmem[hb]\s*\(\s*"([^"\n]+)"',s)
        assert len(calls)==len(names),'Dynamic readmem path requires fresh review '+name
        for asset in names:
            asset=norm(asset);assert (root/asset).is_file(),'Missing readmem asset '+asset
            found.add(asset)
    return sorted(found)

def main():
    ap=argparse.ArgumentParser();ap.add_argument('--candidate',required=True);ap.add_argument('--code',required=True)
    ap.add_argument('--baseline');ap.add_argument('--manifest');ap.add_argument('--freeze');ap.add_argument('--icarus',required=True)
    a=ap.parse_args();project=Path(__file__).resolve().parents[2]
    root=Path(a.candidate);base=Path(a.baseline) if a.baseline else project/'01_当前工程/audio_dual_pitch_b_20261031'
    manifest_path=Path(a.manifest) if a.manifest else project/'03_协作交接/28_独立双变调_33104_20261031/MANIFEST_33104.json'
    freeze_path=Path(a.freeze) if a.freeze else Path(__file__).parent/'BASELINE_33104.json'
    assert root.is_absolute() and base.is_absolute()
    code=a.code if a.code.startswith('0x') else '0x'+a.code
    manifest=read(manifest_path);assert manifest['UserCode']=='0x00033104'
    released=manifest['Files'];frozen=read(freeze_path)
    os.chdir(root);ctypes.windll.kernel32.SetErrorMode(0x8003)
    reference=Path('baseline_33104_evidence');reference.mkdir(exist_ok=True)
    for src,name in ((manifest_path,'ORIGINAL_RELEASE_MANIFEST.json'),(freeze_path,'ORIGINAL_WORKING_MANIFEST.json')):
        shutil.copy2(src,reference/name)
    shutil.copy2(Path(__file__).resolve(),reference/'audit_reuse_33104.py')
    out=Path('sim/results/reuse_33104');out.mkdir(parents=True,exist_ok=True);(out/'tmp').mkdir(exist_ok=True)
    old_cases=sorted(Path(n).stem for n in frozen if Path(n).parent.as_posix()=='sim' and Path(n).name.startswith('tb_') and n.endswith('.sv'))
    assert len(old_cases)==36
    assert sha(Path('sim/run.py'))==sha(base/'sim/run.py')==released['sim/run.py']==frozen['sim/run.py'],'Runner changed'
    assets=sorted(n for n in released if n.startswith('src/') and Path(n).suffix in ('.mem','.vh'))
    fixtures=sorted(n for n in released if n.startswith('sim/fixtures/'))
    all_sources=sorted(Path('src').glob('*.v'))
    directives=[p.as_posix() for p in sorted(Path('src').glob('*')) if p.is_file() and p.suffix in ('.v','.vh') and GLOBAL.search(p.read_text(encoding='utf-8-sig'))]
    assert not directives,'Global preprocessor directive changes need review '+str(directives)
    lib=str(Path(a.icarus).parent/'lib/ivl');env=dict(os.environ)
    env.update(PATH=a.icarus+';'+env['PATH'],LANG='C',LC_ALL='C',TMP=str(out/'tmp'),TEMP=str(out/'tmp'),TMPDIR=str(out/'tmp'))
    reused=[];fresh=[];snapshot=set()
    for case in old_cases:
        rn='sim/results/validation_'+case+'.json';ln='sim/results/'+case+'.log';vn='sim/results/'+case+'.vvp'
        for n in (rn,ln):
            assert n in released and n in frozen and sha(base/n)==released[n]==frozen[n],'Old runtime provenance '+n
        assert vn in frozen and sha(base/vn)==frozen[vn],'Old executable provenance '+vn
        old=read(base/rn)
        assert old['Passed'] and old['ExecutableComplete'] and old['RuntimeExitCode']==0 and not old.get('ReusedFromUserCode')
        assert 'PASS' in (base/ln).read_text(encoding='utf-8-sig')
        old_elab=parse_vvp(base/vn)
        binary=out/(case+'.vvp');attempts=[];artifacts=[];started=time.monotonic()
        command=[str(Path(a.icarus)/'iverilog.exe'),'-B',lib,'-g2012','-gstrict-expr-width','-Wall','-s',case,'-o',str(binary)]+list(map(str,all_sources))+['sim/'+case+'.sv']
        compile_logs=[]
        for attempt in range(1,6):
            result=subprocess.run(command,env=env,stdout=subprocess.PIPE,stderr=subprocess.STDOUT)
            attempts.append(result.returncode);artifacts.append(result.returncode==0 and complete_program(binary))
            log=out/(case+f'_compile{attempt}.log');log.write_bytes(result.stdout);compile_logs.append(log)
            if artifacts[-1]:break
            if result.returncode not in (0,3221225477,3221226356,-1073741819,-1073740940):raise RuntimeError(result.stdout.decode(errors='replace'))
        assert artifacts[-1],'Incomplete current executable '+case
        cur=parse_vvp(binary);deps=include_closure(Path('.'),cur['Dependencies']);old_deps=include_closure(base,old_elab['Dependencies'])
        reasons=[]
        if cur['CompilerStamp']!=old_elab['CompilerStamp']:reasons.append('CompilerStampChanged')
        if cur['Scopes']!=old_elab['Scopes']:reasons.append('ElaboratedScopesOrParametersChanged')
        if deps!=old_deps:reasons.append('RecursiveDependencyClosureChanged')
        if FORBIDDEN.intersection(deps):reasons.append('ChangedActualTopElaborated')
        used=set(deps)|set(assets)|set(fixtures)|{'sim/run.py'}
        try:
            extra=static_readmem_assets(Path('.'),deps);old_extra=static_readmem_assets(base,old_deps)
            if extra!=old_extra:reasons.append('StaticReadmemAssetSetChanged')
            used.update(extra)
        except AssertionError as exc:reasons.append(str(exc));extra=[]
        for name in sorted(used):
            if name not in released or name not in frozen or not Path(name).is_file():reasons.append('UnreleasedOrMissingDependency:'+name)
            elif sha(Path(name))!=released[name] or sha(base/name)!=released[name] or frozen[name]!=released[name]:reasons.append('DependencyChanged:'+name)
        extract=out/(case+'_elaboration.json')
        write(extract,dict(Current=cur,Original=old_elab,CurrentDependencyClosure=deps,OriginalDependencyClosure=old_deps,
            Note='Filename indices resolved to source paths; scopes/parameters and recursive includes drive dependencies, not the complete filename table'))
        if reasons:
            fresh.append(dict(Case=case,Reasons=sorted(set(reasons)),CurrentExecutable=binary.as_posix()))
            print('FRESH_REQUIRED '+case+' '+','.join(sorted(set(reasons))),flush=True);continue
        checked={n:sha(Path(n)) for n in sorted(used)};original_sources={}
        for n,h in checked.items():
            if n in old['SourceHashes']:
                assert old['SourceHashes'][n]==h;original_sources[n]='original runtime report + working freeze + released manifest'
            else:original_sources[n]='working freeze + released manifest + original VVP scopes + recursive include/static asset closure (old runner omitted included TB body)'
        snapshot.update(used)
        original_paths={}
        for n,key in ((rn,'Report'),(ln,'Log'),(vn,'Executable')):
            dst=reference/'results'/Path(n).name;dst.parent.mkdir(exist_ok=True);shutil.copy2(base/n,dst)
            original_paths['Original'+key+'Path']=dst.as_posix();original_paths['Original'+key+'SHA256']=sha(dst)
        for log in compile_logs:shutil.copy2(log,Path('sim/results')/log.name)
        shutil.copy2(base/ln,Path(ln))
        proof=dict(Passed=True,Case=case,ReusedFromUserCode='0x00033104',CandidateUserCode=code,
            RuntimeExecutedThisRelease=False,OriginalRuntimeSeconds=old['Seconds'],DependencyHashes=checked,
            OriginalDependencyHashSources=original_sources,ElaboratedDependencies=deps,StaticReadmemAssets=extra,
            ConservativelyFrozenOldAssets=assets,ConservativelyFrozenOldFixtures=fixtures,GlobalSourceDirectives=[],
            Method='Actual complete new VVP; original/current scope+parameter signatures; recursive TB includes; literal readmems; frozen/released source/asset/fixture/runner bytes',
            CurrentExecutablePath=binary.as_posix(),CurrentExecutableSHA256=sha(binary),
            ElaborationExtractPath=extract.as_posix(),ElaborationExtractSHA256=sha(extract),
            OriginalReleaseManifestPath=(reference/'ORIGINAL_RELEASE_MANIFEST.json').as_posix(),OriginalReleaseManifestSHA256=sha(reference/'ORIGINAL_RELEASE_MANIFEST.json'),
            OriginalWorkingManifestPath=(reference/'ORIGINAL_WORKING_MANIFEST.json').as_posix(),OriginalWorkingManifestSHA256=sha(reference/'ORIGINAL_WORKING_MANIFEST.json'),
            CompileExitCodes=attempts,CompileArtifactsComplete=artifacts,CompilerArguments=command,
            CurrentElaborationSeconds=time.monotonic()-started,**original_paths)
        pp=out/(case+'_dependency_proof.json');write(pp,proof)
        report=dict(old);report.update(ReusedFromUserCode='0x00033104',RuntimeExecutedThisRelease=False,Seconds=0.0,
            OriginalRuntimeSeconds=old['Seconds'],SourceHashes=checked,CompileExitCodes=attempts,CompileArtifactsComplete=artifacts,
            ExecutableComplete=True,CurrentElaborationComplete=True,CurrentElaborationSeconds=proof['CurrentElaborationSeconds'],
            OriginalReportPath=proof['OriginalReportPath'],OriginalReportSHA256=proof['OriginalReportSHA256'],
            OriginalLogPath=proof['OriginalLogPath'],OriginalLogSHA256=proof['OriginalLogSHA256'],DependencyProofPath=pp.as_posix(),DependencyProofSHA256=sha(pp))
        write(Path(rn),report)
        reused.append(dict(Case=case,DependencyCount=len(deps),DependencyProofPath=pp.as_posix(),DependencyProofSHA256=sha(pp),RuntimeExecutedThisRelease=False))
        print('PASS REUSE_33104 '+case+' dependencies='+str(len(deps)),flush=True)
    for n in sorted(snapshot):
        dst=reference/'source_snapshot'/n;dst.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(base/n,dst)
    for n in snapshot:assert sha(Path(n))==released[n]==sha(base/n),'Input changed during audit '+n
    result=dict(Passed=True,BaselineUserCode='0x00033104',CandidateUserCode=code,ReuseCount=len(reused),ReusedCases=[d['Case'] for d in reused],
        FreshOldCasesRequired=[d['Case'] for d in fresh],FreshReasons=fresh,AdditionalNewCasesRequireFreshRuntime=True,
        ReusedRuntimeIsExplicit=True,SourceSnapshotFiles=len(snapshot),Records=reused,
        OriginalReleaseManifestSHA256=sha(reference/'ORIGINAL_RELEASE_MANIFEST.json'),OriginalWorkingManifestSHA256=sha(reference/'ORIGINAL_WORKING_MANIFEST.json'),
        AuditScriptSHA256=sha(Path(__file__)),HardwareValidated=False)
    write(Path('sim/results/REGRESSION_REUSE_33104.json'),result)
    print('PASS REGRESSION_REUSE_33104 reused='+str(len(reused))+' fresh_old='+str([d['Case'] for d in fresh]),flush=True)

if __name__=='__main__':main()
