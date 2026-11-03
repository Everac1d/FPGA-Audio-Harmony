# audio_speaker.sdc 为板载输入 clk 定义 clk_50m 时钟，周期为 20 ns。
# 保留 PLL CLKOUT2 与 DDR 分频器之间的物理时钟关系。
create_generated_clock -name ddr_mem400 -source [get_ports {clk}] -multiply_by 8 [get_pins {u_memory/u_pll/u_pll_0/PLL_inst/CLKOUT2}]
create_generated_clock -name ddr_ui100 -source [get_pins {u_memory/u_pll/u_pll_0/PLL_inst/CLKOUT2}] -divide_by 4 [get_pins {u_memory/u_ddr3/gw3_top/u_ddr_phy_top/fclkdiv/CLKOUT}]

# 每个翻转或状态同步器中，仅第一级按异步路径处理。
# 后续级仍按目标时钟频率进行时序分析。
set_false_path -to [get_regs {u_bridge/request_meta* u_bridge/ack_meta* u_bridge/ready_meta* u_bridge/error_meta*}]
set_false_path -to [get_regs {u_memory/init_sync_0_s0}]
set_false_path -to [get_regs {u_memory/u_pll/u_pll_init/locksig_0_s0}]
# 诊断翻转同步器及物理状态采样：仅对第一级设置例外。
set_false_path -to [get_regs {u_bridge/diagnostic_request_meta* u_bridge/diagnostic_ack_meta*}]
set_false_path -to [get_regs {u_memory/lock_sync_0_s0 u_memory/ui_run_sync_0_s0 u_memory/stop_sync_0_s0 u_memory/ddr_reset_sync_0_s0 u_memory/heartbeat_sync_0_s0}]
# 诊断邮箱保持数据不变，直到采样到同步后的确认信号。
set_max_delay -from [get_regs {u_bridge/diagnostic_mailbox*}] -to [get_regs {u_bridge/diagnostic_snapshot*}] 20.000
set_max_delay -from [get_regs {u_bridge/u_error_code*}] -to [get_regs {u_bridge/error_code*}] 20.000
set_false_path -hold -from [get_regs {u_bridge/diagnostic_mailbox*}] -to [get_regs {u_bridge/diagnostic_snapshot*}]
set_false_path -hold -from [get_regs {u_bridge/u_error_code*}] -to [get_regs {u_bridge/error_code*}]
# 错误触发后，在 UI 域保存首次故障信息，直到复位。
# 仅在对应错误标志经过两级同步器后，才采集故障信息。
set_max_delay -from [get_regs {u_bridge/u_failure_snapshot*}] -to [get_regs {u_bridge/failure_snapshot*}] 20.000
set_false_path -hold -from [get_regs {u_bridge/u_failure_snapshot*}] -to [get_regs {u_bridge/failure_snapshot*}]

# 稳定数据邮箱：在往返握手确认完成前，数据始终保持不变。
# 要求整个请求在一个 100 MHz UI 时钟周期内稳定，早于
# 同步后的请求翻转在两个或更多周期后触发数据采集的时刻。
set_max_delay -from [get_regs {u_bridge/a_data*}] -to [get_regs {u_bridge/job_data*}] 10.000
set_max_delay -from [get_regs {u_bridge/a_addr*}] -to [get_regs {u_bridge/job_addr*}] 10.000
set_max_delay -from [get_regs {u_bridge/a_write*}] -to [get_regs {u_bridge/state*}] 10.000
# 返回数据仅在同步后的确认信号到达音频域后采集。
set_max_delay -from [get_regs {u_bridge/u_response*}] -to [get_regs {u_bridge/rsp_rdata*}] 20.000

# 握手邮箱不会在任意重合的时钟边沿采集数据。
# 保留上方明确的建立时间与最大延时约束，仅对
# 这些明确的数据稳定路径豁免保持时间检查；CE 等待同步后的翻转信号。
set_false_path -hold -from [get_regs {u_bridge/a_data*}] -to [get_regs {u_bridge/job_data*}]
set_false_path -hold -from [get_regs {u_bridge/a_addr*}] -to [get_regs {u_bridge/job_addr*}]
set_false_path -hold -from [get_regs {u_bridge/a_write*}] -to [get_regs {u_bridge/state*}]
set_false_path -hold -from [get_regs {u_bridge/u_response*}] -to [get_regs {u_bridge/rsp_rdata*}]

# 官方 DDR3 参考工程排除了所有时钟间关系；此处
# 仅排除初始化和校准路径；DDR 数据路径
# 及各时钟域的同步逻辑仍继续进行时序分析。
# DLL STEP 是校准结果，并非按 400 MHz 同步采样的数据。
set_false_path -through [get_pins {u_memory/u_ddr3/gw3_top/u_ddr_phy_top/u_dll/STEP*}] -to [get_regs {u_memory/u_ddr3/gw3_top/u_ddr_phy_top/dll_step_base*}]
# DQS HOLD 和 IDES CALIB 是训练控制信号，在校准期间保持不变。
set_false_path -from [get_regs {u_memory/u_ddr3/gw3_top/u_ddr_phy_top/u_ddr_init/read_rclksel_conf*}]
set_false_path -from [get_pins {u_memory/u_ddr3/gw3_top/u_ddr_phy_top/u_ddr_init/hold_gen?0?.hold_i_s0/Q u_memory/u_ddr3/gw3_top/u_ddr_phy_top/u_ddr_init/hold_gen?1?.hold_i_s0/Q u_memory/u_ddr3/gw3_top/u_ddr_phy_top/u_ddr_init/hold_gen?2?.hold_i_s0/Q u_memory/u_ddr3/gw3_top/u_ddr_phy_top/u_ddr_init/hold_gen?3?.hold_i_s0/Q}]
set_false_path -from [get_pins {u_memory/u_ddr3/gw3_top/u_ddr_phy_top/u_ddr_phy_wds/data_lane_gen?0?.u_ddr_phy_data_lane/u_ddr_phy_data_io/ides_calib_d_s0/Q u_memory/u_ddr3/gw3_top/u_ddr_phy_top/u_ddr_phy_wds/data_lane_gen?1?.u_ddr_phy_data_lane/u_ddr_phy_data_io/ides_calib_d_s0/Q u_memory/u_ddr3/gw3_top/u_ddr_phy_top/u_ddr_phy_wds/data_lane_gen?2?.u_ddr_phy_data_lane/u_ddr_phy_data_io/ides_calib_d_s0/Q u_memory/u_ddr3/gw3_top/u_ddr_phy_top/u_ddr_phy_wds/data_lane_gen?3?.u_ddr_phy_data_lane/u_ddr_phy_data_io/ides_calib_d_s0/Q}]
# IP 复位序列器向 DDR IO 原语施加异步复位。
set_false_path -from [get_regs {u_memory/u_ddr3/gw3_top/u_ddr_phy_top/ddr_rsti_reg_2_s0}] -to [get_clocks {ddr_mem400 ddr_ui100}]
# 针对时序报告中确认的 IP 初始化状态跨域路径，仅豁免保持时间检查。
set_false_path -hold -from [get_regs {u_memory/u_ddr3/gw3_top/u_ddr_phy_top/u_init_rmove_mod/sys_reset_ch_?_s0}] -to [get_regs {u_memory/u_ddr3/gw3_top/u_ddr_phy_top/ddr_sync/recalib_s_0_s0}]
set_false_path -hold -from [get_regs {u_memory/u_ddr3/gw3_top/u_ddr_phy_top/ddr_init_internal_r_s0}] -to [get_regs {u_memory/u_ddr3/gw3_top/u_ddr_phy_top/wloadn_3_s0}]

