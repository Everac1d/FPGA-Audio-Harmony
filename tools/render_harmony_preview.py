"""Convert complete actual harmony/calibration RTL PPM frames to PNG."""
from pathlib import Path
from PIL import Image
ROOT=Path(__file__).resolve().parents[1]
NAMES=['lcd_harmony_live','lcd_harmony_clip','lcd_ring_cal_live','lcd_ring_cal_clip']
def main():
    out=ROOT/'docs/lcd_previews';out.mkdir(exist_ok=True)
    for name in NAMES:
        with Image.open(ROOT/'sim/results'/(name+'.ppm')) as picture:
            assert picture.size==(480,272)
            picture.convert('RGB').save(out/(name+'.png'))
    print('PASS HARMONY_PREVIEWS actual_RTL_frames=4 native480x272 no_separate_UI_model')
if __name__=='__main__':main()
