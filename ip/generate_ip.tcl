cd [file dirname [info script]]
open_project ipgen.gprj
create_ipc -name ddr3 -module_name Record_DDR3_Core -file_name record_ddr3_core -dir ddr3 -force
set_property -dict {CONFIG.User_Interface Controller CONFIG.Memory_Clock 400 CONFIG.CLK_Ratio 1:4 CONFIG.Dq_Width 32 CONFIG.Dram_Width 16 CONFIG.Row_Address 15 CONFIG.Column_Address 10 CONFIG.Bank_Address 3 CONFIG.CAS_Latency 6 CONFIG.CW_Latency 5 CONFIG.tRP_Period 15000 CONFIG.tRCD_Period 15000 CONFIG.tRRD_Period 10000 CONFIG.tCKE_Period 10000 CONFIG.tRFC_Period 260000 CONFIG.OUTPUT_DRV HIGH CONFIG.SIM false} [get_ips Record_DDR3_Core]
report_property [get_ips Record_DDR3_Core]
generate_target [get_ips Record_DDR3_Core]
create_ipc -name clock_plladv -module_name Record_DDR3_PLL -file_name record_ddr3_pll -dir pll -force
set_property -dict {CONFIG.General_Mode true CONFIG.CLKIN_FREQ 50 CONFIG.CLKOUT0_FREQ 400 CONFIG.CLKOUT1_FREQ 50 CONFIG.CLKOUT1_EN true CONFIG.CLKOUT2_FREQ 400 CONFIG.CLKOUT2_EN true CONFIG.LOCK_EN true CONFIG.PLL_Reset true CONFIG.Clock_Enable_Ports true} [get_ips Record_DDR3_PLL]
report_property [get_ips Record_DDR3_PLL]
generate_target [get_ips Record_DDR3_PLL]
set ideRoot [file normalize [file join [file dirname [info nameofexecutable]] ..]]
file copy -force [file join $ideRoot ipcore PLL_ADV data PLL pll_init.v] pll/pll_init.v
rm_file src/pll_init.v
add_file pll/pll_init.v
saveto ipgen.gprj
exit
