# FPGA 实时变调与和声系统

基于 Tang Mega 138K / Gowin GW5AST-138B 的实时音频工程，支持原声、变调、双声部和声、DDR 原始音频录放、中文 LCD 显示和灯环音量反馈。

当前提交对应 **33 号工程（余量 −1500）**，设计版本 **`0x00033109`**，原始工程日期 **2026-11-01**。[完整工程原包](releases/FPGA-Audio-Harmony-33109-20261101.zip)保留原交付包的全部 **703 个文件**，与原始 ZIP 逐字节一致。源码、约束、文档和验证资料也在仓库中展开，方便直接查看。

## 查看与下载

| 内容 | 入口 |
| --- | --- |
| 完整工程下载（包含全部源码、位流和验证资料） | [FPGA-Audio-Harmony-33109-20261101.zip](releases/FPGA-Audio-Harmony-33109-20261101.zip) |
| 完整操作说明 | [README_先读.md](README_先读.md) |
| Gowin 工程 | [audio_lcd_record_b.gprj](audio_lcd_record_b.gprj) |
| RTL 源码 | [src/](src/) |
| 引脚与时序约束 | [constraints/](constraints/) |
| IP 与厂商参考文件 | [ip/](ip/) / [vendor/](vendor/) |
| 烧录文件下载（解压后得到 `.fs` 及校验信息） | [33_harmony_5min_margin_m1500_B.zip](ready_to_program/33_harmony_5min_margin_m1500_B.zip) |
| 位流构建信息 | [BUILD_INFO.json](ready_to_program/BUILD_INFO.json) |
| 使用、接线与上板复测说明 | [使用与上板验证](docs/使用与上板验证.md) |
| 软件验证范围与结果 | [软件验证](docs/软件验证.md) |
| 仿真与验证资料 | [sim/](sim/) / [docs/](docs/) |
| 原交付文件校验清单 | [SHA256SUMS.txt](SHA256SUMS.txt) / [MANIFEST_00033109.json](MANIFEST_00033109.json) |

**推荐直接下载上表的完整工程原包**：打开文件页面，点击 **Download raw**（下载原始文件），完整解压后用 Gowin 打开根目录的 `audio_lcd_record_b.gprj`。重建步骤与本机工具路径配置见[使用与上板验证](docs/使用与上板验证.md)。

单个 `.fs` 位流约 39 MB，仓库以 ZIP 形式提供；完整原包内仍保留原来的 `ready_to_program/` 和 `impl/pnr/` 两处 `.fs` 文件。若使用 **Code → Download ZIP** 或 `git clone` 获取仓库，另解压其中 `releases/` 下的完整工程原包后，再使用原校验清单核对全部 703 个文件。

## 主要功能

- 三种音效：原声、变调、和声。和声包含两个可独立设置的声部。
- 半音范围 −12～+12，步进 1；增益 1.0～3.0 倍，步进 0.1。
- 原始 16 位 PCM 最长约 5 分钟录音，存储于板载 DDR，支持播放、暂停、继续和从头重播。
- 回放时可调整音效和半音，录音在断电或全局复位后失效。
- 中文 LCD 状态与操作提示，按键和旋钮交互，以及随模式变化的灯环反馈。
- 本版灯环校准余量固定为 −1500，门限随启动校准基线计算。

器件为 **GW5AST-138B / GW5AST-LV138PG484AC1/I0**，顶层为 `audio_record_ddr_top`。启动默认实时静音；首次操作、接线和烧录请按完整操作说明进行。

## 版本与验证记录

本次上传保留交付包内的源码、位流、报告和历史验证证据，不重新编译或修改设计逻辑。包内记录的 47 项报告包括本版实际运行及经依赖与哈希审核的历史复用，具体范围见[软件验证](docs/软件验证.md)。33 号位流的实板、完整五分钟边界和听音结果仍需按包内复测说明确认。

位流 SHA-256：

```text
8A577D06C4037933807A0D05FB2EB6CA57CD9FA2A9F360C88DE4E5A05C9F2749
```

第三方 IP、字体与参考资料的来源和许可说明保留在原目录中。

完整工程原包 SHA-256：

```text
53E6E0A2D5D7FC464D2097E756BD6C40B5F5EF1AF4F2FE0E787E0FD80A445E76
```
