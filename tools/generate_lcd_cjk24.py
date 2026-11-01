"""Generate the small LCD glyph subset from an installed OFL Noto font.

No TTF/TTC is copied into the project. Run from any directory with Python
and Pillow; --check verifies checked-in ROM/text assets are reproducible.
"""
from pathlib import Path
from struct import unpack_from
import argparse
import hashlib
import json
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
TEXTS = {
    'TITLE': '音频特效',
    'LIVE': '实时',
    'CLIP': '录放',
    'MUTED': '静音',
    'MIC': '麦克风',
    'TONE': '测试音',
    'UNKNOWN': '未知',
    'EFFECT': '音效',
    'ORIGINAL': '原声',
    'PITCH': '变调',
    'HARMONY': '和声',
    'SEMITONE': '半音',
    'GAIN': '增益',
    'TIMES': '倍',
    'STATUS': '状态',
    'LIVE_IDLE': '实时待命',
    'LIVE_RUNNING': '实时运行',
    'DDR_STANDBY': '内存待机',
    'DDR_READY': '内存就绪',
    'DDR_INIT': '内存初始化',
    'EMPTY': '待录',
    'RECORDING': '录音中',
    'SAVING': '保存中',
    'READY': '录音就绪',
    'PREPARE': '播放准备',
    'WARMUP': '音效预热',
    'PLAYING': '播放中',
    'TAIL': '音效尾音',
    'DRAIN': '输出排空',
    'FAULT': '存储故障',
    'RECORD': '录音',
    'TOTAL': '总长',
    'PLAY': '播放',
    'SECONDS': '秒',
    'FULL': '录满30秒',
    'ERROR_CODE': '故障码',
    'RESET': '长按键1复位',
    'H_LIVE_A': '键1切模式 键2切音效',
    'H_LIVE_B': '旋1调增益 旋2调半音',
    'H_CLIP_A': '键3录音 键4播放',
    'H_RECORD_A': '键3结束录音',
    'H_PLAY_A': '键4暂停 键2切音效',
    'H_CLIP_B': '旋1调增益 旋2调半音',
    'H_COMMON_A': '旋1按下切声音',
    'H_COMMON_B': '旋2按下半音归零',
    'H_FAULT_A': '存储故障  实时音频仍可使用',
    'H_FAULT_B': '记故障码 长按键1复位',
    'H_WAIT_A': '内存初始化  请稍候',
    'H_WAIT_B': '键1回实时 长按2秒复位',
    'H_SAVING_A': '正在保存录音  请稍候',
    'H_SAVING_B': '保存完成后按键4播放',
    'PAUSED': '已暂停',
    'H_PAUSED_A': '键4继续 长按键4重播',
    'H_CLIP_HELP_A': '旋2按下半音归零',
    'H_CLIP_HELP_B': '长按键4从头播放',
    'H_MAINT_A': '键1切模式 长按2秒复位',
    'H_MAINT_B': '键2切音效 键3录音/结束',
    'H_MAINT_LIVE_B': '键2切音效 旋2按下归零',
    'DUAL': '双变调',
    'VOICE_EDIT': '声部>短按选择',
}


def font_names(data):
    result = {}
    for table in range(unpack_from('>H', data, 4)[0]):
        tag, _, offset, _ = unpack_from('>4sIII', data, 12 + 16 * table)
        if tag != b'name':
            continue
        count, start = unpack_from('>HH', data, offset + 2)
        for index in range(count):
            platform, _, _, name_id, size, pos = unpack_from('>HHHHHH', data, offset + 6 + 12 * index)
            if name_id in (0, 1, 2, 5, 8, 9, 11, 13, 14):
                text = data[offset + start + pos:offset + start + pos + size].decode('utf-16be' if platform in (0, 3) else 'latin1')
                result.setdefault(str(name_id), text)
    return result


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--font', default='C:/Windows/Fonts/NotoSansSC-VF.ttf')
    ap.add_argument('--check', action='store_true')
    args = ap.parse_args()
    source = Path(args.font).read_bytes()
    names = font_names(source)
    if 'Open Font License' not in names.get('13', ''):
        raise RuntimeError('Font metadata must identify SIL Open Font License; use OFL Noto Sans SC')
    chars = list(dict.fromkeys(' 0123456789+-.?/:ABCDEF' + ''.join(TEXTS.values())))
    if len(chars) > 128:
        raise RuntimeError('Glyph subset exceeds 128 slots')
    glyph_ids = {char: index for index, char in enumerate(chars)}
    font = ImageFont.truetype(args.font, 24)
    font.set_variation_by_axes([650])
    rows = [0] * 4096
    glyph_info = []
    tiles = Image.new('RGB', (16 * 48, ((len(chars) + 15) // 16) * 64), '#101820')
    pen = ImageDraw.Draw(tiles)
    for glyph_id, char in enumerate(chars):
        box = font.getbbox(char)
        width, height = box[2] - box[0], box[3] - box[1]
        cell_width = 12 if ord(char) < 128 else 24
        canvas = Image.new('L', (max(width, 1), max(height, 1)), 0)
        ImageDraw.Draw(canvas).text((-box[0], -box[1]), char, font=font, fill=255)
        # Preserve 24px Chinese glyphs; Latin is condensed only horizontally
        # into a 12px half-cell, retaining the original ~19px ink height.
        if width > cell_width:
            canvas = canvas.resize((cell_width, canvas.height), Image.Resampling.LANCZOS)
        glyph = Image.new('1', (24, 24), 0)
        mask = canvas.point(lambda value: 255 if value >= 112 else 0).convert('1')
        glyph.paste(mask, ((cell_width - mask.width) // 2, (24 - mask.height) // 2))
        for row in range(24):
            bits = 0
            for col in range(24):
                bits = (bits << 1) | bool(glyph.getpixel((col, row)))
            rows[glyph_id * 32 + row] = bits
        bbox = glyph.getbbox()
        if char != ' ' and not bbox:
            raise RuntimeError(f'Empty glyph {char}')
        glyph_info.append(dict(id=glyph_id, character=char, unicode=f'U+{ord(char):04X}',
                               cell_width=cell_width, ink_bounds=bbox))
        left, top = (glyph_id % 16) * 48, (glyph_id // 16) * 64
        preview = Image.new('RGB', (24, 24), '#101820')
        preview.paste('#ffffff', (0, 0), glyph)
        tiles.paste(preview.resize((48, 48), Image.Resampling.NEAREST), (left, top))
        pen.text((left + 2, top + 49), str(glyph_id), fill='white')
    header = ['// Generated by tools/generate_lcd_cjk24.py; do not hand edit.',
              '// Each token: bit8=right Chinese half, bits7:0=glyph ID.',
              'localparam integer LCD_TEXT_CELLS=37;']
    for char in chars:
        if ord(char) < 128:
            header.append(f"localparam [7:0] G_U{ord(char):04X}=8'd{glyph_ids[char]};")
    for name, text in TEXTS.items():
        tokens = []
        for char in text:
            tokens.append(glyph_ids[char])
            if ord(char) >= 128:
                tokens.append(256 + glyph_ids[char])
        if len(tokens) > 37:
            raise RuntimeError(f'{name} exceeds 37 half-cells: {text}')
        header.append(f'// {name}: {text} ({len(tokens)} half-cells)')
        header.append(f'localparam integer N_{name}={len(tokens)};')
        tokens += [0] * (37 - len(tokens))
        header.append(f"localparam [332:0] T_{name}={{" + ','.join(f"9'd{token}" for token in tokens) + '};')
    outputs = {
        ROOT / 'src/lcd_cjk24.mem': ''.join(f'{row:06x}\n' for row in rows),
        ROOT / 'src/lcd_ui_text.vh': '\n'.join(header) + '\n',
    }
    for path, content in outputs.items():
        if args.check:
            assert path.read_text(encoding='utf-8') == content, f'Generated asset differs: {path}'
        else:
            path.write_text(content, encoding='utf-8', newline='\n')
    out = ROOT / 'docs/fonts'
    out.mkdir(parents=True, exist_ok=True)
    metadata = dict(SubsetName='FPGA Audio LCD CJK24 Subset', SourceFamily=names.get('1'),
                    SourceSHA256=hashlib.sha256(source).hexdigest().upper(), SourceNameMetadata=names,
                    FontSize=24, Weight=650, BinaryThreshold=112, GlyphCount=len(chars),
                    Glyphs=glyph_info, Rows=4096, RowWidth=24,
                    ROM_SHA256=hashlib.sha256(outputs[ROOT / 'src/lcd_cjk24.mem'].encode()).hexdigest().upper())
    if not args.check:
        (out / 'GLYPH_MANIFEST.json').write_text(json.dumps(metadata, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
        tiles.save(out / 'glyph_atlas.png')
    print(f'PASS CJK24 subset: {len(chars)} glyphs, 4096x24-bit ROM; full font not copied')


if __name__ == '__main__':
    main()
