# 中文点阵字库来源与许可

本项目分发的字体资源名称为 **FPGA Audio LCD CJK24 Subset** 和 **FPGA Audio LCD CJK16 Footer Subset**。主信息采用123个字形的24像素点阵，固定底部提示采用124个字形的16像素点阵，不包含系统TTF/TTC文件，也不安装字体。原有 `lcd_font5x7.v` 不再被中文dashboard实例化。

生成输入为本机已安装 `C:/Windows/Fonts/NotoSansSC-VF.ttf`，字体family为Noto Sans SC；字体name表中的版权为 `© 2014-2021 Adobe (http://www.adobe.com/), with Reserved Font Name 'Source'.`。该本地字体name表第13项明确声明 **SIL Open Font License, Version 1.1**，第14项指向OFL。原字体文件完整SHA256、版本和相关name表原文保存在 `GLYPH_MANIFEST.json`，不假定其字节与某个在线发行文件相同。

一手项目与许可来源：

- [Noto CJK字体官方仓库](https://github.com/notofonts/noto-cjk)
- [Noto Sans CJK的SIL OFL许可原文](https://github.com/notofonts/noto-cjk/blob/main/Sans/LICENSE)

本点阵子集作为字体格式转换产物，随附并继续使用SIL OFL 1.1；完整许可及原版权声明见 `OFL.txt`。派生资源使用上述独立名称，没有采用保留名称Source作为派生字体名。工程自身其他RTL的许可不因此变更。原作者名称只用于说明来源。

## 可复现生成

```powershell
python tools/generate_lcd_cjk24.py
python tools/generate_lcd_cjk24.py --check
python tools/generate_lcd_cjk16.py
python tools/generate_lcd_cjk16.py --check
```

依赖Python、Pillow及具有OFL许可元数据的Noto Sans SC可变字体。可通过 `--font` 指定合法安装位置；若字体不同，manifest的输入哈希与生成点阵也会不同。脚本仅读取该字体，不复制或分发完整字体文件，且会检查其name表是否声明Open Font License。

生成资产：`src/lcd_cjk24.mem` 为4096×24bit的同步ROM初始化数据；`src/lcd_ui_text.vh` 保存由同一脚本生成的字形索引和文本token，避免手工索引错位。`src/lcd_cjk24_font.v` 以相对路径读取ROM，工程根目录为构建/仿真的当前工作目录。交付和仿真输入哈希应包含 `.v`、`.vh`、`.mem`。

字形以24px、weight650生成二值点阵，中文使用24×24格，实际墨迹高度最小20px；数字和十六进制字母使用12×24半格，实际墨迹高度最小18px。ASCII只在水平方向适配12px宽度，没有压低字高。`glyph_atlas.png` 为2倍最近邻放大的全字库预览，可核对缺字、字形位置和笔画。

当前底部操作提示改用独立16像素点阵，中文16×16、数字8×16，实际中文墨迹高14～16像素、数字墨迹高12像素；与主信息的24像素字形相互独立。四行高对比白色提示分别位于y=204..219、221..236、238..253、255..270，最底部y=271保留背景，不裁掉末行。完整LCD画面预览来自实际RTL仿真扫描，再转换为PNG，并非单独用Python重画页面。

## 外接控件版本更新

33002的历史版本采用两行三页轮播帮助。当前33104沿用33003的固定提示设计，取消轮播，仅由实时／录放音源选择两组固定四行提示，所有操作一次列出，不因录音、回放、暂停、保存或故障而换页。主区状态与故障信息继续更新。

28号为双变调追加必要字形和文本，主字体ROM及`lcd_ui_text.vh`据此重新生成；前117个原字形ID及其24px点阵保持顺序和字节，新主区字形追加在末尾，总数123。新 `src/lcd_cjk16.mem` 为2048×16bit同步ROM，由 `src/lcd_cjk16_font.v` 读取；`src/lcd_footer_text.vh`保存56个半字格宽的固定提示。新增16px生成器沿用原字形ID，在123个主字形之后追加“转”（ID123），总数124，不重排已有主区字形。16px点阵直接从同一OFL字体以16px生成，没有抽样或缩放24px点阵；少数字形16px字体自身17px外沿通过一次像素适配完整放入16行，避免截笔画。

16px资源的输入字体哈希、字形边界和ROM哈希见 `GLYPH16_MANIFEST.json`，全字形预览见 `glyph16_atlas.png`。该子集继续使用同一SIL OFL 1.1许可和原版权声明。
