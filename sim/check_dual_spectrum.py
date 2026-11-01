"""Independent narrow-band Goertzel check on actual production-grain RTL PCM."""
from pathlib import Path
import math,json,hashlib
ROOT=Path(__file__).resolve().parent.parent
rows=[list(map(int,l.split())) for l in (ROOT/'sim/results/dual_voice_spectrum.txt').read_text().splitlines()]
assert len(rows)==32768
fs=48828.125
signals=[[r[c] for r in rows] for c in range(3)]
window=[0.5-0.5*math.cos(2*math.pi*i/(len(rows)-1)) for i in range(len(rows))]
signals=[[x*w for x,w in zip(s,window)] for s in signals]
def power(s,f):
    coefficient=2*math.cos(2*math.pi*f/fs)
    a=b=0.0
    for x in s:a,b=x+coefficient*a-b,a
    return a*a+b*b-coefficient*a*b
expected=[440*2**(4/12),440*2**(7/12)]
peaks=[]
for i,f in enumerate(expected):
    grid=range(round(f)-12,round(f)+13)
    peak=max(grid,key=lambda g:power(signals[i],g))
    assert abs(peak-f)<3,(i,peak,f)
    p=power(signals[i],peak)
    assert p>100*power(signals[i],440),(i,'original tone dominates')
    assert p>25*power(signals[i],expected[1-i]),(i,'voice separation')
    assert power(signals[2],peak)>10*power(signals[2],440),'mixed output missing shifted voice'
    peaks.append(peak)
result=dict(Passed=True,Source='actual RTL tb_dual_voice_spectrum PCM',GrainSamples=8192,
    SampleRateHz=fs,InputHz=440,PitchSemitones=[4,7],ExpectedVoiceHz=expected,
    MeasuredPeakHz=peaks,OutputSamples=len(rows),Analysis='Hann-windowed Goertzel, 1 Hz local grid',
    HardwareValidated=False,
    InputPCM_SHA256=hashlib.sha256((ROOT/'sim/results/dual_voice_spectrum.txt').read_bytes()).hexdigest().upper(),
    AnalyzerSHA256=hashlib.sha256(Path(__file__).read_bytes()).hexdigest().upper(),
    RuntimeValidationSHA256=hashlib.sha256((ROOT/'sim/results/validation_tb_dual_voice_spectrum.json').read_bytes()).hexdigest().upper())
(ROOT/'sim/results/DUAL_VOICE_SPECTRUM_VALIDATION.json').write_text(json.dumps(result,indent=2)+'\n',encoding='utf-8')
print('PASS DUAL_SPECTRUM_ANALYSIS actual_RTL_samples=32768 expected='+str(expected)+' peaks='+str(peaks))
