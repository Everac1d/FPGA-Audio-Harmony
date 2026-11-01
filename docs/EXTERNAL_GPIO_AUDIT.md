# 外接面板配置复用引脚核对

核对日期：2026-10-30。目标器件保持 GW5AST-LV138PG484AC1/I0 / GW5AST-138B。本记录为本地原理图、官方安装手册及EDA命令检查，不代表外接面板已经上板验收。

## 配置复用要求

当前图中的10路外接输入不与原音频、LCD或DDR活动端口重复。其中特别需要释放以下配置脚：

|外接输入|管脚|配置别名|需要启用的工程选项|
|---|---|---|---|
|按键1|Y21|SSPI_CS_N|`set_option -use_sspi_as_gpio 1`|
|旋钮2 CLK|U21|D05/SI|`set_option -use_sspi_as_gpio 1`|
|旋钮1 SW|AB20|DOUT_CSO_B|`set_option -use_cpu_as_gpio 1`|

AB20属于CPU组的CSO_B复用，亦有串行级联DOUT功能，不能仅凭名字包含SPI就以MSPI选项代替。JTAG、READY、DONE和RECONFIG_N保持专用。本次没有启用JTAG GPIO复用。

## 依据

- 本地官方手册：`D:\Gowin\Gowin_V1.9.12.04_x64\Programmer\doc\EN\UG704-1.0.7E_Arora Ⅴ 138K&75K FPGA Product Programming and Configuration Guide.pdf`（UG704-1.0.7E，Arora V 138K/75K专用编程配置指南）。PDF第18页/正文10(70)说明DOUT/CSO_B功能；第19—20页/正文11—12(70)的表3-5列出CPU PORT和SSPI PORT，以及成功配置后才转为GPIO的规则。
- 既有管脚报告与SOM管脚名称相符：Y21=SSPI_CS_N、AB20=DOUT_CSO_B、U21=D05/SI。不能将旧工程报告中的AB20配置输出状态当作新工程已经释放。
- Gowin V1.9.12.04的`set_option -help`实际包含`-use_cpu_as_gpio`、`-use_sspi_as_gpio`；独立只读探针中两条命令均返回PASS。探针未打开工程、未编译、未下载或读取串口/JTAG。脚本和结果在`sim/results/gpio_option_probe.tcl`及同名`.log`。

## 构建后仍须核对

最终PNR报告必须确认10路均为输入、固定到接线图对应管脚、AB20不再作为配置DOUT输出，以及121个物理管脚无重分配。最终编译、Setup/Hold/Recovery/Removal四类时序另由构建验证记录给出。

配置完成前，这些脚仍承担配置功能。上电和下载期间先不要按外接按键或旋转/按下旋钮，待新工程启动后操作。本次没有改变接线、供电或板上跳帽。
