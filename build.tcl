cd [file dirname [info script]]
open_project audio_lcd_record_b.gprj
set_option -top_module audio_record_ddr_top
set_option -output_base_name audio_lcd_record_b
set_option -verilog_std v2001
set_option -bit_compress 1
set_option -user_code 00033109
set_option -timing_driven 1
set_option -opt_goal timing
set_option -place_option 3
set_option -route_option 2
set_option -use_sspi_as_gpio 1
set_option -use_cpu_as_gpio 1
run all
exit
