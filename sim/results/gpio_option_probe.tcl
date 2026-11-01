puts "PROBE use_cpu_as_gpio"
if {[catch {set_option -use_cpu_as_gpio 1} response]} {puts "FAIL $response";exit 1} else {puts "PASS set_option -use_cpu_as_gpio 1"}
puts "PROBE use_sspi_as_gpio"
if {[catch {set_option -use_sspi_as_gpio 1} response]} {puts "FAIL $response";exit 1} else {puts "PASS set_option -use_sspi_as_gpio 1"}
exit
