"""Generate separate OFL Noto glyph ROMs for the long-clip harmony UI.

Original 128-slot font files and all their IDs remain untouched. Production
fonts use 256 slots with an 8-bit glyph ID plus one right-half token bit.
"""
from pathlib import Path
import argparse,hashlib,json
from PIL import Image,ImageDraw,ImageFont
from generate_lcd_cjk24 import TEXTS,font_names
from generate_lcd_cjk16 import FOOTERS
ROOT=Path(__file__).resolve().parents[1]
MAIN={'RING':'灯环','MARGIN':'余量','GATE':'门限','MEAN':'均值','RING_EDIT':'灯环调节','FULL':'录满'}
HELP={
    'LIVE_0':'键1切实时/录放 长按2秒复位',
    'LIVE_1':'键2切原声/变调/和声',
    'LIVE_2':'旋1转调增益 按下切麦克风/静音',
    'LIVE_3':'旋2转调半音 短按归零/选声部 长按2秒归零',
    'CLIP_0':'键1切实时/录放 长按2秒复位 键2切音效',
    'CLIP_1':'键3录音/结束 键4播放/暂停/继续',
    'CLIP_2':'旋1转调增益 旋2转调半音',
    'CLIP_3':'旋2短按归零/选声部 长按2秒归零 键4长按重播',
    'TUNE_LIVE_0':'键1切实时/录放 长按2秒复位',
    'TUNE_LIVE_1':'键2切原声/变调/和声',
    'TUNE_LIVE_2':'旋1转调增益/灯环 长按2秒切换 按下切麦克风/静音',
    'TUNE_LIVE_3':'旋2转调半音 短按归零/选声部 长按2秒归零',
    'TUNE_CLIP_0':'键1切实时/录放 长按2秒复位 键2切音效',
    'TUNE_CLIP_1':'键3录音/结束 键4播放/暂停/继续',
    'TUNE_CLIP_2':'旋1转调增益/灯环 长按2秒切换 旋2转调半音',
    'TUNE_CLIP_3':'旋2短按归零/选声部 长按2秒归零 键4长按重播',
}
def tokens(text,ids,cells):
    out=[]
    for ch in text:
        out.append(ids[ch])
        if ord(ch)>=128:out.append(256+ids[ch])
    assert len(out)<=cells,(text,len(out),cells)
    return out+[0]*(cells-len(out))
def main():
    ap=argparse.ArgumentParser();ap.add_argument('--font',default='C:/Windows/Fonts/NotoSansSC-VF.ttf');ap.add_argument('--check',action='store_true');a=ap.parse_args()
    raw=Path(a.font).read_bytes();names=font_names(raw);assert 'Open Font License' in names.get('13','')
    seed=' 0123456789+-.?/:ABCDEF'+''.join(TEXTS.values())+''.join(FOOTERS.values())
    chars=list(dict.fromkeys(seed+''.join(MAIN.values())+''.join(HELP.values())));assert len(chars)<=256
    ids={ch:i for i,ch in enumerate(chars)};outputs={};manifest={}
    for size,slots,stride,width in ((24,256,32,24),(16,256,16,16)):
        font=ImageFont.truetype(a.font,size);font.set_variation_by_axes([650]);rows=[0]*(slots*stride);glyphs=[]
        atlas=Image.new('RGB',(16*size*2,((len(chars)+15)//16)*(size*2+16)),'#101820');pen=ImageDraw.Draw(atlas)
        for n,ch in enumerate(chars):
            box=font.getbbox(ch);w,h=box[2]-box[0],box[3]-box[1];cell=size//2 if ord(ch)<128 else size
            ink=Image.new('L',(max(w,1),max(h,1)),0);ImageDraw.Draw(ink).text((-box[0],-box[1]),ch,font=font,fill=255)
            if ink.width>cell or ink.height>size:ink=ink.resize((min(cell,ink.width),min(size,ink.height)),Image.Resampling.LANCZOS)
            mask=ink.point(lambda v:255 if v>=112 else 0).convert('1');glyph=Image.new('1',(size,size),0);glyph.paste(mask,((cell-mask.width)//2,(size-mask.height)//2))
            assert ch==' ' or glyph.getbbox(),ch
            for y in range(size):
                bits=0
                for x in range(size):bits=(bits<<1)|bool(glyph.getpixel((x,y)))
                rows[n*stride+y]=bits
            glyphs.append(dict(ID=n,Character=ch,CellWidth=cell,InkBounds=glyph.getbbox()))
            tile=Image.new('RGB',(size,size),'#101820');tile.paste('white',(0,0),glyph)
            left=(n%16)*size*2;top=(n//16)*(size*2+16);atlas.paste(tile.resize((size*2,size*2),Image.Resampling.NEAREST),(left,top));pen.text((left+1,top+size*2),str(n),fill='white')
        data=''.join(f'{r:0{width//4}x}\n' for r in rows);outputs[ROOT/f'src/lcd_harmony_cjk{size}.mem']=data
        manifest[str(size)]=dict(Glyphs=glyphs,Slots=256,Rows=slots*stride,RowBits=width,ROM_SHA256=hashlib.sha256(data.encode()).hexdigest().upper())
        if not a.check:
            (ROOT/'docs/fonts').mkdir(exist_ok=True);atlas.save(ROOT/f'docs/fonts/harmony_glyph{size}_atlas.png')
    header=['// Generated harmony UI tokens, 8-bit glyph IDs plus bit8 right half.']
    for name,text in MAIN.items():
        ts=tokens(text,ids,37);header += [f'// {name}: {text}',f'localparam integer HN_{name}={sum(1 if ord(ch)<128 else 2 for ch in text)};',f'localparam [332:0] HT_{name}={{'+','.join(f"9'd{v}" for v in ts)+'};']
    for name,text in HELP.items():
        ts=tokens(text,ids,56);header += [f'// {name}: {text}',f'localparam [503:0] HF_{name}={{'+','.join(f"9'd{v}" for v in ts)+'};']
    outputs[ROOT/'src/lcd_harmony_text.vh']='\n'.join(header)+'\n'
    for p,data in outputs.items():
        if a.check:assert p.read_text(encoding='utf-8')==data,p
        else:p.write_text(data,encoding='utf-8',newline='\n')
    if not a.check:
        doc=dict(SourceFamily=names.get('1'),SourceSHA256=hashlib.sha256(raw).hexdigest().upper(),SubsetName='FPGA Audio Harmony LCD CJK24 and CJK16 Subsets',License='SIL OFL 1.1; original name metadata and OFL.txt retained',GlyphCount=len(chars),OriginalFilesUntouched=True,Main=MAIN,FixedFooters=HELP,Bitmaps=manifest)
        (ROOT/'docs/fonts/HARMONY_FONT_MANIFEST.json').write_text(json.dumps(doc,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    print('PASS HARMONY_FONT glyphs='+str(len(chars))+' slots256 originals_untouched=1 main24 footer16')
if __name__=='__main__':main()
