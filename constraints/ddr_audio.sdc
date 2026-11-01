# audio_speaker.sdc provides clk_50m on the board input clk (20 ns).
# Retain the physical relationship through PLL CLKOUT2 and the DDR divider.
create_generated_clock -name ddr_mem400 -source [get_ports {clk}] -multiply_by 8 [get_pins {u_memory/u_pll/u_pll_0/PLL_inst/CLKOUT2}]
create_generated_clock -name ddr_ui100 -source [get_pins {u_memory/u_pll/u_pll_0/PLL_inst/CLKOUT2}] -divide_by 4 [get_pins {u_memory/u_ddr3/gw3_top/u_ddr_phy_top/fclkdiv/CLKOUT}]

# Only the first stage of each toggle/status synchronizer is asynchronous.
# The subsequent stage remains timed at its destination frequency.
set_false_path -to [get_regs {u_bridge/request_meta* u_bridge/ack_meta* u_bridge/ready_meta* u_bridge/error_meta*}]
set_false_path -to [get_regs {u_memory/init_sync_0_s0}]
set_false_path -to [get_regs {u_memory/u_pll/u_pll_init/locksig_0_s0}]
# Diagnostic toggle synchronizers and sampled physical status: first stage only.
set_false_path -to [get_regs {u_bridge/diagnostic_request_meta* u_bridge/diagnostic_ack_meta*}]
set_false_path -to [get_regs {u_memory/lock_sync_0_s0 u_memory/ui_run_sync_0_s0 u_memory/stop_sync_0_s0 u_memory/ddr_reset_sync_0_s0 u_memory/heartbeat_sync_0_s0}]
# Diagnostic mailboxes hold the payload until the synchronized ack is sampled.
set_max_delay -from [get_regs {u_bridge/diagnostic_mailbox*}] -to [get_regs {u_bridge/diagnostic_snapshot*}] 20.000
set_max_delay -from [get_regs {u_bridge/u_error_code*}] -to [get_regs {u_bridge/error_code*}] 20.000
set_false_path -hold -from [get_regs {u_bridge/diagnostic_mailbox*}] -to [get_regs {u_bridge/diagnostic_snapshot*}]
set_false_path -hold -from [get_regs {u_bridge/u_error_code*}] -to [get_regs {u_bridge/error_code*}]
# First failure is held in the UI domain after error assertion until reset.
# Capture only after the same error flag crosses the two-stage synchronizer.
set_max_delay -from [get_regs {u_bridge/u_failure_snapshot*}] -to [get_regs {u_bridge/failure_snapshot*}] 20.000
set_false_path -hold -from [get_regs {u_bridge/u_failure_snapshot*}] -to [get_regs {u_bridge/failure_snapshot*}]

# Stable-data mailbox: payload is held unchanged until the round-trip ack.
# Require the entire request to settle within one 100 MHz UI period, before
# the synchronized request toggle can cause a capture two or more cycles later.
set_max_delay -from [get_regs {u_bridge/a_data*}] -to [get_regs {u_bridge/job_data*}] 10.000
set_max_delay -from [get_regs {u_bridge/a_addr*}] -to [get_regs {u_bridge/job_addr*}] 10.000
set_max_delay -from [get_regs {u_bridge/a_write*}] -to [get_regs {u_bridge/state*}] 10.000
# Return payload is captured only after the synchronized ack reaches audio.
set_max_delay -from [get_regs {u_bridge/u_response*}] -to [get_regs {u_bridge/rsp_rdata*}] 20.000

# Handshake mailboxes are not captured at arbitrary coincident clock edges.
# Keep the explicit setup/maximum-delay bounds above, and waive hold only
# for these exact stable payload paths (CE waits for synchronized toggles).
set_false_path -hold -from [get_regs {u_bridge/a_data*}] -to [get_regs {u_bridge/job_data*}]
set_false_path -hold -from [get_regs {u_bridge/a_addr*}] -to [get_regs {u_bridge/job_addr*}]
set_false_path -hold -from [get_regs {u_bridge/a_write*}] -to [get_regs {u_bridge/state*}]
set_false_path -hold -from [get_regs {u_bridge/u_response*}] -to [get_regs {u_bridge/rsp_rdata*}]

# The official DDR3 reference excludes all inter-clock relationships. Here
# only its initialization/calibration paths are excluded; DDR data paths
# and each clock's synchronous logic continue to be analyzed.
# DLL STEP is a calibration result, not synchronous 400 MHz sample data.
set_false_path -through [get_pins {u_memory/u_ddr3/gw3_top/u_ddr_phy_top/u_dll/STEP*}] -to [get_regs {u_memory/u_ddr3/gw3_top/u_ddr_phy_top/dll_step_base*}]
# DQS HOLD and IDES CALIB are training controls, held through calibration.
set_false_path -from [get_regs {u_memory/u_ddr3/gw3_top/u_ddr_phy_top/u_ddr_init/read_rclksel_conf*}]
set_false_path -from [get_pins {u_memory/u_ddr3/gw3_top/u_ddr_phy_top/u_ddr_init/hold_gen?0?.hold_i_s0/Q u_memory/u_ddr3/gw3_top/u_ddr_phy_top/u_ddr_init/hold_gen?1?.hold_i_s0/Q u_memory/u_ddr3/gw3_top/u_ddr_phy_top/u_ddr_init/hold_gen?2?.hold_i_s0/Q u_memory/u_ddr3/gw3_top/u_ddr_phy_top/u_ddr_init/hold_gen?3?.hold_i_s0/Q}]
set_false_path -from [get_pins {u_memory/u_ddr3/gw3_top/u_ddr_phy_top/u_ddr_phy_wds/data_lane_gen?0?.u_ddr_phy_data_lane/u_ddr_phy_data_io/ides_calib_d_s0/Q u_memory/u_ddr3/gw3_top/u_ddr_phy_top/u_ddr_phy_wds/data_lane_gen?1?.u_ddr_phy_data_lane/u_ddr_phy_data_io/ides_calib_d_s0/Q u_memory/u_ddr3/gw3_top/u_ddr_phy_top/u_ddr_phy_wds/data_lane_gen?2?.u_ddr_phy_data_lane/u_ddr_phy_data_io/ides_calib_d_s0/Q u_memory/u_ddr3/gw3_top/u_ddr_phy_top/u_ddr_phy_wds/data_lane_gen?3?.u_ddr_phy_data_lane/u_ddr_phy_data_io/ides_calib_d_s0/Q}]
# IP's reset sequencer asserts asynchronous resets on DDR IO primitives.
set_false_path -from [get_regs {u_memory/u_ddr3/gw3_top/u_ddr_phy_top/ddr_rsti_reg_2_s0}] -to [get_clocks {ddr_mem400 ddr_ui100}]
# Exact IP initialization-status crossings found in the timing report; only hold is waived.
set_false_path -hold -from [get_regs {u_memory/u_ddr3/gw3_top/u_ddr_phy_top/u_init_rmove_mod/sys_reset_ch_?_s0}] -to [get_regs {u_memory/u_ddr3/gw3_top/u_ddr_phy_top/ddr_sync/recalib_s_0_s0}]
set_false_path -hold -from [get_regs {u_memory/u_ddr3/gw3_top/u_ddr_phy_top/ddr_init_internal_r_s0}] -to [get_regs {u_memory/u_ddr3/gw3_top/u_ddr_phy_top/wloadn_3_s0}]

