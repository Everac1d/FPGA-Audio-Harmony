cd [file dirname [info script]]
open_project audio_lcd_record_b.gprj
set_option -top_module audio_record_ddr_top
set_option -output_base_name audio_lcd_record_b
set_option -user_code 00032601
run pnr
exit
