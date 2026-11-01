"""Offline R3/R4/R5/R6 and atomically paired D3 status analysis; no serial I/O."""
import argparse,json,re
from pathlib import Path
MAX_LONG_SAMPLES=14648438
VERSION_PROTOCOL={
    0x32501:'3',0x32502:'3',0x32503:'3',0x32601:'3',0x32701:'3',0x32901:'3',0x33001:'3',
    0x33002:'4',0x33003:'4',0x33101:'4',0x33102:'4',0x33103:'4',0x33104:'5',0x33105:'6',0x33106:'6',0x33107:'6',0x33109:'6'}
RE=re.compile(r'R(?P<protocol>[3456]) V=(?P<V>[0-9A-F]{8}) S=(?P<S>[01]) M=(?P<M>[0-2]) A=(?P<A>[0-3]) N=(?P<N>[01][0-9A-F]) H=(?P<H>[0-9A-F]{1,2}) T=(?P<T>[0-9AB]) L=(?P<L>[0-9A-F]{6,8}) P=(?P<P>[0-9A-F]{6,8}) D=(?P<D>[01]) E=(?P<E>[01]) F=(?P<F>[01]) I=(?P<I>[01]) U=(?P<U>[0-9A-F]{8}) O=(?P<O>[0-9A-F]{8})(?: X=(?P<X>[0-9A-F]{4}))?(?: Q=(?P<Q>[01][0-9A-F]) C=(?P<C>[01]))?$')
FAILURE_RE=re.compile(r'D3 V=(?P<V>00032503|00032601|00032701|00032901|00033001|00033002|00033003|00033101|00033102|00033103|00033104|00033105|00033106|00033107|00033109) J=(?P<J>[0-9A-F]) B=(?P<B>[01][0-9A-F]{7}) W=(?P<W>[0-9A-F]{64}) R=(?P<R>[0-9A-F]{64})$')
STATES=['DDR_WAIT','EMPTY','RECORDING','SAVING','READY','PREFETCH','PREROLL','PLAYING','TAIL','DRAIN','ERROR','PAUSED']
GAINS={0:1,2:1.5,4:2,5:2.5,6:3}
ERRORS=['NONE','BOOT_TIMEOUT','READY_LOST','RESPONSE_TIMEOUT','CALIB_OR_RESET_LOST','UI_TRANSACTION_TIMEOUT','READ_END_MISSING','SELFTEST_MISMATCH','INVALID_STATE']
def decode(line):
    m=RE.search(line.strip())
    if not m:return None
    protocol=m['protocol']
    d={k:int(v,16) for k,v in m.groupdict().items() if v is not None and k!='protocol'}
    if d['V'] not in VERSION_PROTOCOL:raise ValueError('Different firmware version in status log')
    if VERSION_PROTOCOL[d['V']]!=protocol:raise ValueError('Firmware/status protocol mismatch')
    fine=protocol!='3';voices=protocol in ('5','6');long_clip=protocol=='6'
    if voices!=('Q' in d and 'C' in d):raise ValueError('Missing or unexpected second voice fields')
    if d['A']==3 and protocol!='5':raise ValueError('Fourth effect is only valid in historical R5 firmware')
    if fine:
        if len(m['H'])!=2 or not 10<=d['H']<=30:raise ValueError('Fine gain out of range')
    elif len(m['H'])!=1 or d['H'] not in GAINS or d['T']>10:raise ValueError('Legacy gain/state out of range')
    if (d['V']>=0x32502)!=('X' in d):raise ValueError('Diagnostic fields do not match firmware version')
    digits=8 if long_clip else 6
    if len(m['L'])!=digits or len(m['P'])!=digits:raise ValueError('Sample counter width does not match protocol')
    limit=MAX_LONG_SAMPLES if long_clip else 1464844
    if d['L']>limit or d['P']>limit:raise ValueError('Clip position out of range')
    expected_length=115 if long_clip else (111 if protocol=='5' else (102 if protocol=='4' else (94 if d['V']==0x32501 else 101)))
    if len(m.group(0))!=expected_length:raise ValueError('Status packet length mismatch')
    semitones=d['N']-32 if d['N']&16 else d['N']
    if not -12<=semitones<=12:raise ValueError('First pitch out of range')
    d.update(Protocol='R'+protocol,State=STATES[d['T']],Semitones=semitones,Gain=d['H']/10 if fine else GAINS[d['H']],
        RecordSeconds=d['L']/48828.125,PlaySeconds=d['P']/48828.125,MaxSamples=limit)
    if voices:
        second=d['Q']-32 if d['Q']&16 else d['Q']
        if not -12<=second<=12:raise ValueError('Second pitch out of range')
        d.update(SecondSemitones=second,SelectedVoice=d['C']+1)
    if 'X' in d:
        code=d['X']>>12
        d.update(DDRErrorCode=code,DDRError=ERRORS[code] if code<len(ERRORS) else 'UNKNOWN',DDRBridgeState=(d['X']>>8)&15,
            PLLLocked=bool(d['X']&1),CalibrationDone=bool(d['X']&2),UIResetReleased=bool(d['X']&4),UIClockActive=bool(d['X']&8),
            PLLStop=bool(d['X']&16),DDRReset=bool(d['X']&32),CalibrationSoftTimeout=bool(d['X']&64))
    return d
def decode_failure(line):
    m=FAILURE_RE.search(line.strip())
    if not m:return None
    index=int(m['J'],16);address=int(m['B'],16);expected=int(m['W'],16);actual=int(m['R'],16)
    xor=expected^actual
    return dict(UserCode='0x%08X'%int(m['V'],16),TestIndex=index,AppWordAddress=address,ExpectedHex=m['W'],ActualHex=m['R'],
        HasMismatch=bool(xor),DifferingBits=xor.bit_count(),Bad32BitLanes=[i for i in range(8) if (xor>>(32*i))&0xffffffff],
        ActualAllZero=actual==0,ActualAllOnes=actual==(1<<256)-1,AddressMatchesTestIndex=address==index*65544)
def analyze(text):
    records=[];diagnostics=[];ignored=0
    for line in text.splitlines():
        d=decode(line)
        if d is None:
            failure=decode_failure(line)
            if failure is None:ignored+=1
            else:diagnostics.append(failure)
        else:records.append(d)
    if not records:raise ValueError('No complete R3/R4/R5/R6 snapshots')
    return dict(UserCode='0x%08X'%records[-1]['V'],VersionsSeen=sorted(set('0x%08X'%d['V'] for d in records)),Snapshots=len(records),
        FailureSnapshots=len(diagnostics),LatestFailure=diagnostics[-1] if diagnostics else None,IgnoredLines=ignored,
        StatesSeen=sorted(set(d['State'] for d in records)),DDRReadySeen=any(d['D'] for d in records),StorageFaultSeen=any(d['E'] for d in records),
        QueueUnderflowSeen=any(d['U'] for d in records),QueueOverflowSeen=any(d['O'] for d in records),FullClipSeen=any(d['F'] for d in records),
        MaxRecordSamples=max(d['L'] for d in records),Latest=records[-1],HardwareAcceptance=False,
        Meaning='Snapshot summary only; physical DDR, hearing, head/tail, repeatability and reset evidence require operator acceptance.')
def selftest():
    line='R3 V=00032501 S=1 M=1 A=2 N=14 H=6 T=7 L=165A0C P=000025 D=1 E=0 F=1 I=1 U=00000000 O=00000000'
    d=decode(line);assert d['Semitones']==-12 and d['Gain']==3 and d['L']==1464844
    d=analyze('2026-10-25 12:00:00.000 '+line+'\npartial\n');assert d['Snapshots']==1 and d['IgnoredLines']==1 and not d['StorageFaultSeen']
    assert decode('AP M=1') is None
    new=line.replace('00032501','00032502')+' X=740F'
    d=decode(new);assert d['DDRError']=='SELFTEST_MISMATCH' and d['DDRBridgeState']==4 and d['UIClockActive'] and d['CalibrationDone']
    d=decode(new[:-4]+'1041');assert d['DDRError']=='BOOT_TIMEOUT' and d['CalibrationSoftTimeout'] and not d['CalibrationDone']
    assert analyze(line+'\n'+new)['VersionsSeen']==['0x00032501','0x00032502']
    latest=new.replace('00032502','00032503')
    failure='D3 V=00032503 J=5 B=00050028 W='+('01234567'*8)+' R='+('01234567'*7)+'01234566'
    f=decode_failure(failure);assert f['HasMismatch'] and f['DifferingBits']==1 and f['Bad32BitLanes']==[0] and f['AddressMatchesTestIndex']
    d=analyze(latest+'\n'+failure);assert d['FailureSnapshots']==1 and d['IgnoredLines']==0 and d['UserCode']=='0x00032503'
    assert decode_failure(failure[:-1]) is None
    current=analyze(latest.replace('00032503','00032701')+'\n'+failure.replace('00032503','00032701'))
    assert current['UserCode']=='0x00032701' and current['LatestFailure']['UserCode']=='0x00032701'
    combined=analyze(latest.replace('00032503','00032901')+'\n'+failure.replace('00032503','00032901'))
    assert combined['UserCode']=='0x00032901' and combined['LatestFailure']['UserCode']=='0x00032901'
    for bad in (line.replace('00032501','00022402'),line.replace('L=165A0C','L=1FFFFF'),line.replace('00032501','00032502'),line+' X=0000'):
        try:decode(bad)
        except ValueError:pass
        else:raise AssertionError('Invalid record accepted')
    chinese=analyze(latest.replace('00032503','00033001')+'\n'+failure.replace('00032503','00033001'))
    assert chinese['UserCode']=='0x00033001' and chinese['LatestFailure']['UserCode']=='0x00033001'
    for gain in range(10,31):
        fine=latest.replace('R3','R4').replace('00032503','00033002').replace('H=6',f'H={gain:02X}').replace('T=7','T=B')
        d=analyze(fine+'\n'+failure.replace('00032503','00033002'))
        assert d['Latest']['Gain']==gain/10 and d['Latest']['State']=='PAUSED' and d['Latest']['Protocol']=='R4'
    for bad in (fine.replace('H=1E','H=1F'),fine.replace('R4','R3'),fine.replace('00033002','00033001')):
        try:decode(bad)
        except ValueError:pass
        else:raise AssertionError('Invalid fine gain protocol accepted')
    static=analyze(fine.replace('00033002','00033003'))
    assert static['UserCode']=='0x00033003' and static['Latest']['Gain']==3
    for a in range(-12,13):
        for b in range(-12,13):
            dual=fine.replace('R4','R5').replace('00033002','00033104').replace('A=2','A=3')
            dual=re.sub(r'N=[01][0-9A-F]',f'N={a&31:02X}',dual)+f' Q={b&31:02X} C=1'
            d=decode(dual);assert d['Semitones']==a and d['SecondSemitones']==b and d['SelectedVoice']==2
    for bad in (dual.replace('N=0C','N=0D'),dual.replace('Q=0C','Q=13'),dual.replace('R5','R4'),dual.replace('00033104','00033103')):
        try:decode(bad)
        except ValueError:pass
        else:raise AssertionError('Invalid dual packet accepted')
    _r6_selftest()
    print('PASS R3_STATUS_TOOLS version signed_pitch gain lengths timestamp malformed empty reject')

def _long_line(version=0x33105,n=-12,q=12,gain=30,record=MAX_LONG_SAMPLES,play=2097153,voice=1,algorithm=2):
    return f'R6 V={version:08X} S=1 M=1 A={algorithm:X} N={n&31:02X} H={gain:02X} T=B L={record:08X} P={play:08X} D=1 E=0 F=1 I=1 U=00000000 O=00000000 X=040F Q={q&31:02X} C={voice}'
def _r6_selftest():
    checks=0
    for version in (0x33105,0x33106,0x33107,0x33109):
        for gain in range(10,31):
            for count in (0,1,1464844,2097151,2097152,2097153,8388608,MAX_LONG_SAMPLES):
                d=decode(_long_line(version,gain=gain,record=count,play=count))
                assert d['Protocol']=='R6' and d['L']==count and d['P']==count and d['Gain']==gain/10 and d['MaxSamples']==MAX_LONG_SAMPLES
                checks+=1
        for n in range(-12,13):
            for q in range(-12,13):
                d=decode(_long_line(version,n,q));assert d['Semitones']==n and d['SecondSemitones']==q and d['SelectedVoice']==2
                checks+=1
        failure=f'D3 V={version:08X} J=5 B=00050028 W='+('0'*64)+' R='+('0'*63)+'1'
        d=analyze('2026-10-31 12:34:56.000 '+_long_line(version)+'\n'+failure)
        assert d['FailureSnapshots']==1 and d['LatestFailure']['UserCode']==f'0x{version:08X}' and d['MaxRecordSamples']==MAX_LONG_SAMPLES
        checks+=1
    good=_long_line()
    bad=[good.replace('L=00DF8476','L=00DF8477'),good.replace('P=00200001','P=FFFFFFFF'),
         good.replace('L=00DF8476','L=F1234567'),good.replace('L=00DF8476','L=0DF8476'),
         good.replace('L=00DF8476','L=DF8476'),good.replace('R6','R5'),good.replace('00033105','00033104'),
         good.replace('00033105','00033108'),good.replace('H=1E','H=1F'),good.replace('H=1E','H=09'),
         good.replace('H=1E','H=E'),good.replace('N=14','N=13'),good.replace('N=14','N=0D'),
         good.replace('Q=0C','Q=13'),good.replace('Q=0C','Q=0D'),good.replace('C=1','C=2'),
         good.replace('A=2','A=3'),good.replace('T=B','T=C'),good[:-1]]
    for packet in bad:
        try:d=decode(packet)
        except ValueError:pass
        else:assert d is None,'Invalid R6 accepted '+packet
        checks+=1
    assert len(good)==115 and len(good+'\r\n')==117
    print(f'PASS R6_STATUS_TOOLS checks={checks} versions33105_33106_33107_33109 counter32 old21bit_boundaries max5min signed25 gain21 malformed_range_length_protocol_reject no_serial')
if __name__=='__main__':
    ap=argparse.ArgumentParser();ap.add_argument('log',nargs='?');ap.add_argument('--output');ap.add_argument('--self-test',action='store_true');a=ap.parse_args()
    if a.self_test:selftest()
    else:
        if not a.log:ap.error('log path required')
        data=analyze(Path(a.log).read_text(encoding='utf-8-sig'));s=json.dumps(data,ensure_ascii=False,indent=2);print(s)
        if a.output:Path(a.output).write_text(s+'\n',encoding='utf-8')
