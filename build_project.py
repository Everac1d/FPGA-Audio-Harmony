from pathlib import Path
import argparse,hashlib,json,re,shutil,subprocess,sys,stat,ctypes,xml.etree.ElementTree as ET
from datetime import datetime,timezone
ROOT=Path(__file__).parent
EXPECTED_CASES=['tb_ring_softlow', 'tb_harmony_tuned_engine', 'tb_algorithm_components', 'tb_algorithm_core', 'tb_clip_5min', 'tb_clip_capacity', 'tb_clip_controller', 'tb_clip_pause', 'tb_ddr_bridge', 'tb_dual_engine', 'tb_dual_lcd', 'tb_dual_panel', 'tb_dual_status_uart', 'tb_dual_voice_core', 'tb_dual_voice_spectrum', 'tb_dynamic_config', 'tb_external_controls', 'tb_external_engine', 'tb_external_engine_default', 'tb_fine_gain', 'tb_harmony_engine', 'tb_harmony_lcd', 'tb_harmony_panel', 'tb_harmony_spectrum', 'tb_lcd_boot_diagnostics', 'tb_lcd_dashboard', 'tb_lcd_fine_scan', 'tb_lcd_snapshot', 'tb_lcd_static_footer', 'tb_lcd_timing', 'tb_long_status_uart', 'tb_mode_ring', 'tb_panel_diag_chord', 'tb_pcm_voice_conditioner', 'tb_pt8211_stereo_tx', 'tb_record_engine', 'tb_record_engine_default', 'tb_record_fault_isolation', 'tb_record_keys', 'tb_record_status', 'tb_record_status_fine', 'tb_record_top_startup', 'tb_ring_calibration', 'tb_ring_calibration_lcd', 'tb_ring_gate_margin', 'tb_six_gain', 'tb_unified_harmony_core']
if sys.flags.optimize:raise RuntimeError('Do not use python -O')
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest().upper()
def read(p):return json.loads(p.read_text(encoding='utf-8-sig'))
def write(p,d):p.write_text(json.dumps(d,indent=2,ensure_ascii=False)+'\n',encoding='utf-8')
def inputs():
    ps=list((ROOT/'src').glob('*'))+list((ROOT/'constraints').glob('*'))
    for pattern in ('*.py','*.ps1','*.gprj','*.tcl'):ps+=list(ROOT.glob(pattern))
    ps+=[ROOT/f.attrib['path'] for f in ET.parse(ROOT/'audio_lcd_record_b.gprj').findall('.//File')]
    ps+=[ROOT/'ip/generate_ip.tcl',ROOT/'ip/ipgen.gprj']
    ps+=[p for p in (ROOT/'ip').rglob('*.ipc') if 'temp' not in p.parts]
    return {p.relative_to(ROOT).as_posix():sha(p) for p in sorted(ps) if p.is_file()}
def check(h):
    for p,v in h.items():assert sha(ROOT/p)==v,'Stale input/output '+p
def check_pins():
    csts=[ROOT/f.attrib['path'] for f in ET.parse(ROOT/'audio_lcd_record_b.gprj').findall('.//File') if f.attrib['type']=='file.cst']
    assert len(csts)==1,'Gowin uses one effective CST; provide a single combined file'
    text='\n'.join(l.split('//')[0] for l in csts[0].read_text(encoding='utf-8-sig').splitlines())
    expected={n:[v.strip() for v in loc.split(',')] for n,loc in re.findall(r'IO_LOC\s+"([^"]+)"\s+([^;]+);',text)}
    html=(ROOT/'impl/pnr/audio_lcd_record_b.pin.html').read_text(encoding='utf-8',errors='replace')
    actual={}
    for row in re.findall(r'<tr[^>]*>(.*?)</tr>',html,re.S):
        cells=[re.sub('<[^>]+>','',v).strip() for v in re.findall(r'<t[dh][^>]*>(.*?)</t[dh]>',row,re.S)]
        if len(cells)>7 and cells[0] in expected:actual[cells[0]]=cells
    checked={}
    for n,pins in expected.items():
        assert n in actual,'Pin report missing '+n
        row=actual[n];assert row[2].split('/')[0]==pins[0] and row[3]=='Y','Wrong/unfixed pin '+n+' '+str(row[:4])
        checked[n]=pins[0]
        if len(pins)==2:
            mate=row[1]
            pattern=r'<td class="label">'+re.escape(mate)+r'</td>'
            matching=[]
            for r in re.findall(r'<tr[^>]*>(.*?)</tr>',html,re.S):
                cs=[re.sub('<[^>]+>','',v).strip() for v in re.findall(r'<t[dh][^>]*>(.*?)</t[dh]>',r,re.S)]
                if len(cs)>3 and cs[0]==mate:matching.append(cs)
            assert len(matching)==1 and matching[0][2].split('/')[0]==pins[1] and matching[0][3]=='Y','Differential mate mismatch '+mate
            checked[mate]=pins[1]
    assert len(set(checked.values()))==len(checked),'Pin conflict'
    panel={'button_n[0]':'Y21','button_n[1]':'AB21','button_n[2]':'AA20','button_n[3]':'AA19',
           'enc_gain_sw_n':'AB20','enc_gain_dt':'AA21','enc_gain_clk':'AB22',
           'enc_pitch_sw_n':'T18','enc_pitch_dt':'R17','enc_pitch_clk':'U21'}
    assert len(checked)==121,'Expected 121 physical pins'
    for name,pin in panel.items():
        assert checked[name]==pin
        assert 'in' in [c.lower() for c in actual[name]],'Panel pin is not input '+name
    assert '-use_sspi_as_gpio 1' in (ROOT/'build.tcl').read_text()
    assert '-use_cpu_as_gpio 1' in (ROOT/'build.tcl').read_text()
    write(ROOT/'docs/PIN_VALIDATION.json',dict(Passed=True,CheckedPhysicalPins=len(checked),Pins=checked,ConstraintFile=csts[0].relative_to(ROOT).as_posix(),PinReportSHA256=sha(ROOT/'impl/pnr/audio_lcd_record_b.pin.html')))
    return len(checked)
def compile(gowin):
    before=inputs();started=datetime.now(timezone.utc);ctypes.windll.kernel32.SetErrorMode(0x8003)
    with (ROOT/'build.log').open('w',encoding='utf-8') as log:
        p=subprocess.Popen([gowin,'build.tcl'],cwd=ROOT,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True,encoding='utf-8',errors='replace',creationflags=subprocess.CREATE_NO_WINDOW)
        for line in p.stdout:log.write(line);log.flush();print(line,end='',flush=True)
        code=p.wait()
    assert code==0 and not re.search(r'ERROR\s*\(', (ROOT/'build.log').read_text(encoding='utf-8')),'Native compile failed'
    assert inputs()==before,'Inputs changed during compile'
    outputs={}
    for n in ('impl/pnr/audio_lcd_record_b.fs','impl/pnr/audio_lcd_record_b.tr','impl/pnr/audio_lcd_record_b.pin.html','impl/pnr/audio_lcd_record_b.rpt.txt','build.log'):
        p=ROOT/n;assert p.is_file() and p.stat().st_mtime>=started.timestamp()-2,'Missing/stale '+n
        outputs[n]=sha(p)
    write(ROOT/'docs/COMPILE_CHECKPOINT.json',dict(ExitCode=code,StartedUtc=started.isoformat(),SourceHashes=before,OutputHashes=outputs))
    print('COMPILE COMPLETE; finalize checks still required',flush=True)
def finalize():
    cp=read(ROOT/'docs/COMPILE_CHECKPOINT.json');assert inputs()==cp['SourceHashes'],'Compile inputs changed';check(cp['OutputHashes'])
    checked_pins=check_pins()
    records=[]
    assert {p.stem for p in (ROOT/'sim').glob('tb_*.sv')}==set(EXPECTED_CASES),'Missing/extra regression case'
    for p in sorted((ROOT/'sim').glob('tb_*.sv')):
        d=read(ROOT/'sim/results'/('validation_'+p.stem+'.json'))
        assert d['Passed'] and d['Case']==p.stem and d['RuntimeExitCode']==0 and 0 in d['CompileExitCodes']
        assert d['ExecutableComplete'] and d['CompileArtifactsComplete'][-1],'Incomplete native simulator executable'
        assert 'sim/'+p.name in d['SourceHashes'],'Test source not hashed'
        if d.get('ReusedFromUserCode'):
            assert d['ReusedFromUserCode']=='0x00033104','Unexpected regression provenance'
            for path_key,hash_key in (('OriginalReportPath','OriginalReportSHA256'),('DependencyProofPath','DependencyProofSHA256')):
                saved=ROOT/d[path_key]
                assert saved.is_file() and sha(saved)==d[hash_key],'Invalid reuse evidence '+path_key
        if d.get('ReusedFromUserCode'):
            proof=read(ROOT/d['DependencyProofPath'])
            assert proof['Passed'] and not proof['RuntimeExecutedThisRelease']
            for path_key,hash_key in (('OriginalLogPath','OriginalLogSHA256'),):
                assert sha(ROOT/d[path_key])==d[hash_key]
            check(proof['DependencyHashes'])
        check(d['SourceHashes']);records.append(d)
    tools=subprocess.run([sys.executable,'-X','utf8',str(ROOT/'analyze_status.py'),'--self-test'],stdout=subprocess.PIPE,stderr=subprocess.STDOUT)
    (ROOT/'sim/results/status_tools.log').write_bytes(tools.stdout)
    assert tools.returncode==0 and b'PASS R3_STATUS_TOOLS' in tools.stdout,'Status tool failed'
    tr=(ROOT/'impl/pnr/audio_lcd_record_b.tr').read_text(encoding='utf-8',errors='replace')
    for k in ('Setup','Hold'):assert re.search(r'<Numbers of '+k+r' Violated Endpoints>:\s*0\b',tr),k+' timing violation'
    assert 'clk_50m' in tr and 'ddr_ui100' in tr,'Missing audio/UI clock timing coverage'
    constraints=re.findall(r'^\s+TC_\S+\s+(Actived|Inactived)\b',tr,re.M)
    assert constraints and set(constraints)=={'Actived'},'Inactive timing constraint'
    slacks={}
    for k in ('Setup','Hold','Recovery','Removal'):
        section=tr.rsplit(k+' Paths Table',1)[-1]
        m=re.search(r'^\s+1\s+(-?[\d.]+)\s+',section,re.M)
        assert m and float(m[1])>=0,k+' worst slack failed'
        slacks[k+'MinSlackNs']=float(m[1])
    fs=ROOT/'impl/pnr/audio_lcd_record_b.fs';head=fs.open(encoding='ascii').read(2000)
    assert '//UserCode: 0x00033109' in head and '//Device Version: B' in head and '//Compress: ON' in head
    target=ROOT/'ready_to_program/33_harmony_5min_margin_m1500_B.fs'
    if target.exists():target.chmod(target.stat().st_mode|stat.S_IWRITE)
    shutil.copy2(fs,target)
    output_paths=[]
    for d in records:
        output_paths += [ROOT/'sim/results'/(d['Case']+'.log'),ROOT/'sim/results'/('validation_'+d['Case']+'.json')]
        output_paths += sorted((ROOT/'sim/results').glob(d['Case']+'_compile*.log'))
    output_paths += [ROOT/'sim/results/status_tools.log']
    summary=dict(Passed=True,Cases=[x['Case'] for x in records],Records=records,
        FreshCases=[x['Case'] for x in records if not x.get('ReusedFromUserCode') and not x.get('SharedCurrentExecutionFrom')],
        SharedCurrentCases=[x['Case'] for x in records if x.get('SharedCurrentExecutionFrom')],
        ReusedUnchangedCases=[x['Case'] for x in records if x.get('ReusedFromUserCode')],
        OutputHashes={p.relative_to(ROOT).as_posix():sha(p) for p in output_paths},HardwareValidated=False)
    write(ROOT/'sim/results/SIMULATION_VALIDATION.json',summary)
    info=dict(File=target.name,UserCode='0x00033109',Device='GW5AST-138B',Part='GW5AST-LV138PG484AC1/I0',SHA256=sha(target),ClockHz=50000000,SampleRateHz=48828.125,MAXSamples=14648438,MaxSeconds=14648438/48828.125,ClipBytes=29296876,Storage='Onboard DDR3 x32 / 400MHz / UI100MHz / BL8',RawPCM=True,Volatile=True,DefaultMuted=True,DefaultGain=1,SelectableGainFactors=[x/10 for x in range(10,31)],UIPresets=list(range(-12,13)),SourceHashes=cp['SourceHashes'],SimulationManifestSHA256=sha(ROOT/'sim/results/SIMULATION_VALIDATION.json'),InternalSetupViolations=0,InternalHoldViolations=0,StorageFaultIsolatedToClip=True,DDROnDemand=True,KeepDDRRunningAfterFirstClip=True,OutputGainFrameLatched=True,PairedDDRWriteHandshake=True,ReadyGatedDDRCommands=True,FirstFailureSnapshot=True,DiagnosticProtocol='R4+D3 atomic pair (104+164 bytes); H is tenths gain',HardwareValidated=False,DDRPhysicalValidated=False,ListeningValidated=False,LCDPanelVerified=False,BacklightEnabled=True,CH569IsolationRequired=True)
    info['ModeColorRing']=True
    info['LCDDiagnosticBootKey']='Hold KEY2 while releasing KEY1; release KEY2 after startup'
    info['BaselineLCDUserCode']='0x00032901'
    info['ChineseLCD']=True
    info['ExternalPanel']='4 buttons + 2 pressable quadrature encoders; pin map in docs'
    info['ExternalGainTenths']=list(range(10,31))
    info['GainStep']=0.1
    info['PitchStepSemitones']=1
    info['PauseResume']=True
    info['PlaybackEffectChangesContinue']=True
    info['ConfigurationGPIOOptions']=['use_sspi_as_gpio','use_cpu_as_gpio']
    info['BaselineChineseUserCode']='0x00033001'
    info['HardwareValidated']=False
    info['MinimumCharacterHeightPixels']=16
    info['MainCharacterHeightPixels']=24
    info['FooterCharacterHeightPixels']=16
    info['FooterLines']=4
    info['FooterPages']=['live','record_playback']
    info['FooterTimedRotation']=False
    info['BaselineUserReportedAccepted']='User reports29 harmony5min and30 calibration work; 33 margin -1500 awaits board test'
    info['Scope']='Derived from31 with only fixed ring margin -1500; all audio and low-level brightness retained'
    info['DiagnosticProtocol']='R6+D3 atomic pair (117+164 bytes); L/P32bit8hex; H tenths gain; N/Q signed5; C voice0/1'
    info['RecordCapacityMinutes']=5
    info['AllocatedClipBytes']=29296896
    info['ClipBlocks']=915528
    info['FinalClipAppWordAddress']=7324216
    info['FinalValidLanes']=6
    info['UnifiedHarmony']=True
    info['PublicAlgorithms']=['original','pitch','harmony']
    info['HarmonyDefaultSemitones']=[0,0]
    info['ZeroHarmonyVoiceUsesAlignedDry']=True
    info['SampleCounterBits']=32
    info['LCDFixedPointDividendBits']=40
    info['LCDTimeFormat']='MM:SS.cc'
    info['RuntimeRingCalibration']=False
    info['RuntimeRingMarginRange']=[-4096,4095]
    info['RuntimeRingMarginSlowStep']=1
    info['RuntimeRingMarginFastStep']=16
    info['SharedCurrentSimulationCases']=summary['SharedCurrentCases']
    info['FreshSimulationCases']=summary['FreshCases']
    info['ReusedUnchangedSimulationCases']=summary['ReusedUnchangedCases']
    info['BaselineRingUserCode']='0x00032701'
    info['RingCalibrationMargin']=-1500
    info['RingLowLevelGlobalBrightness']={'BelowLevel64':'4+(level>>4)','Level64AndAbove':8,'RGB':'level>>1','MinimumLitBrightnessRatioTo29':0.5}
    info['RingNoiseFloorMinimum']=64
    info['HiddenToneGesture']='Live: hold both encoder switches 2 seconds, release both'
    info['AcousticFeedbackAlgorithmChanged']=False
    info['DualIndependentVoices']=True
    info['TimingReportSHA256']=sha(ROOT/'impl/pnr/audio_lcd_record_b.tr')
    info['CheckedPhysicalPins']=checked_pins
    info['ClockFmaxMHz']={n:float(v) for n,v in re.findall(r'(clk_50m|ddr_ui100|ddr_mem400)\s+[\d.]+\(MHz\)\s+([\d.]+)\(MHz\)',tr)}
    write(ROOT/'ready_to_program/BUILD_INFO.json',info)
    rpt=(ROOT/'impl/pnr/audio_lcd_record_b.rpt.txt').read_text(encoding='utf-8',errors='replace')
    resources={}
    for k in ('Logic','Register','I/O Port','BSRAM','DSP'):
        m=re.search(r'^\s*'+re.escape(k)+r'\s*\|\s*([^|]+)\|',rpt,re.M)
        assert m,'Missing resource '+k
        resources[k]=m[1].strip()
    codes=sorted(set(re.findall(r'WARN\s*\(([^)]+)\)',(ROOT/'build.log').read_text(encoding='utf-8'))))
    write(ROOT/'docs/构建复核.json',dict(Passed=True,UserCode=info['UserCode'],FS=target.name,FS_SHA256=info['SHA256'],
        CheckedPhysicalPins=checked_pins,GlobalSetupViolations=0,GlobalHoldViolations=0,ClockFmaxMHz=info['ClockFmaxMHz'],
        Slacks=slacks,Resources=resources,ActiveTimingConstraints=len(constraints),WarningCodes=codes,
        WarningsReview=dict(EX3073='Review any unused read-only diagnostic outputs; LCD uses active audio status.',
            EX3791='Bounded key counters, unchanged baseline arithmetic/display widths, native PLL init widths; numerical and UI regressions required.',
            PR1014='Retained generic-routing warning on clk_d. Check PRIMARY/HCLK clock routing and STA; physical DDR remains unvalidated.',
            UserCacheLog='Chinese user-path sh.log may fail; native exit, fresh FS and full build.log plus STA are checked.'),
        HardwareValidated=False,DDRPhysicalValidated=False,ListeningValidated=False,LCDPanelVerified=False,BacklightEnabled=True,CH569IsolationRequired=True))
    (ROOT/'ready_to_program/SHA256SUMS.txt').write_text(info['SHA256']+'  '+target.name+'\n',encoding='ascii')
    write(ROOT/'docs/FINAL_VALIDATION.json',dict(Passed=True,Build=info,SimulationCases=summary['Cases'],HardwareValidated=False))
    print('READY '+info['UserCode']+' '+target.name,flush=True)
if __name__=='__main__':
    ap=argparse.ArgumentParser();ap.add_argument('action',choices=['build','compile','finalize']);ap.add_argument('--gowin',required=True);a=ap.parse_args()
    if a.action in ('build','compile'):compile(a.gowin)
    if a.action in ('build','finalize'):finalize()
