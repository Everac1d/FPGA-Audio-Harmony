"""Compile/run actual external-control LCD RTL and save native-resolution previews."""
from pathlib import Path
import argparse, ctypes, hashlib, json, os, re, subprocess, time
from PIL import Image, ImageDraw
ROOT = Path(__file__).absolute().parent.parent

def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest().upper()

def complete(path):
    if not path.is_file():
        return False
    match = re.search(rb'\n:file_names (\d+);\r?\n(.*)\Z', path.read_bytes(), re.S)
    if not match:
        return False
    lines = match[2].strip().splitlines()
    return len(lines) == int(match[1]) and all(line.strip().startswith(b'"') and line.strip().endswith(b'";') for line in lines)

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--icarus', required=True)
    a = ap.parse_args()
    ctypes.windll.kernel32.SetErrorMode(0x8003)
    os.chdir(ROOT)
    out = Path('sim/results')
    out.mkdir(exist_ok=True)
    (out / 'tmp').mkdir(exist_ok=True)
    sources = [Path('src/lcd_dashboard.v'), Path('src/lcd_cjk24_font.v')]
    inputs = sources + [Path('src/lcd_cjk24.mem'), Path('src/lcd_ui_text.vh'),
        Path('sim/tb_lcd_dashboard.sv'), Path('sim/run_lcd_external_checks.py'),
        Path('tools/generate_lcd_cjk24.py')]
    hashes = {p.as_posix(): sha(p) for p in inputs}
    env = dict(os.environ)
    env.update(PATH=a.icarus+';'+env['PATH'], LANG='C', LC_ALL='C', LC_CTYPE='C',
        TMP='sim/results/tmp', TEMP='sim/results/tmp', TMPDIR='sim/results/tmp')
    lib = str(Path(a.icarus).parent / 'lib/ivl')
    attempts, full = [], []
    for attempt in range(1, 13):
        binary = out / ('tb_lcd_external_' + 'x'*attempt + '.vvp')
        p = subprocess.run([str(Path(a.icarus)/'iverilog.exe'), '-B', lib, '-g2012',
            '-gstrict-expr-width', '-Wall', '-s', 'tb_lcd_dashboard', '-o', str(binary)] +
            list(map(str, sources)) + ['sim/tb_lcd_dashboard.sv'], env=env,
            stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        (out / f'tb_lcd_external_compile{attempt}.log').write_bytes(p.stdout)
        attempts.append(p.returncode)
        full.append(p.returncode == 0 and complete(binary))
        if full[-1]:
            break
        if p.returncode not in (0, 3221225477, 3221226356, -1073741819, -1073740940):
            raise RuntimeError(p.stdout.decode(errors='replace'))
    assert full[-1], f'Native compile failed or truncated: {attempts}'
    started = time.time()
    p = subprocess.run([str(Path(a.icarus)/'vvp.exe'), '-M', lib, str(binary)], env=env,
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    (out/'tb_lcd_external.log').write_bytes(p.stdout)
    result = p.stdout.decode(errors='replace')
    print(result, flush=True)
    assert p.returncode == 0 and 'PASS LCD dashboard external:' in result, 'RTL test failed'
    assert hashes == {name: sha(ROOT/name) for name in hashes}, 'Inputs changed during run'
    previews = ['lcd_cn_live_muted', 'lcd_ext_live_controls', 'lcd_cn_initializing',
        'lcd_cn_recording', 'lcd_cn_ready_full', 'lcd_cn_playback', 'lcd_ext_paused',
        'lcd_cn_help_source', 'lcd_ext_help_reset', 'lcd_cn_fault']
    destination = Path('docs/lcd_external_previews')
    destination.mkdir(exist_ok=True)
    sheet = Image.new('RGB', (960, 5*296), '#202830')
    pen = ImageDraw.Draw(sheet)
    for index, name in enumerate(previews):
        picture = Image.open(out/(name+'.ppm')).convert('RGB')
        assert picture.size == (480, 272)
        picture.save(destination/(name+'.png'))
        x, y = (index%2)*480, (index//2)*296
        sheet.paste(picture, (x, y+24))
        pen.text((x+8,y+6), name, fill='white')
    sheet.save(destination/'lcd_external_overview.png')
    record = dict(Passed=True, Case='tb_lcd_dashboard_external', CompileExitCodes=attempts,
        CompileArtifactsComplete=full, ExecutableComplete=True, RuntimeExitCode=p.returncode,
        Seconds=time.time()-started, SourceHashes=hashes, Runner='sim/run_lcd_external_checks.py',
        HardwareValidated=False, PreviewOrigin='Actual lcd_dashboard RTL pixels, PPM to PNG only',
        Previews=previews, OutputHashes={str(path).replace('\\','/'):sha(path) for path in sorted(destination.glob('*.png'))},
        Summary=[line for line in result.splitlines() if line.startswith(('PASS', 'MEASURE'))])
    (out/'validation_tb_lcd_dashboard_external.json').write_text(json.dumps(record, indent=2)+'\n', encoding='utf-8')
    print('PASS EXTERNAL LCD CASE: 10 native-resolution RTL previews', flush=True)

if __name__ == '__main__':
    main()
