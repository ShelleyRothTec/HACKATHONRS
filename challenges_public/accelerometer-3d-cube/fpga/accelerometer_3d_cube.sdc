# Timing Constraints for Accelerometer 3D Cube Project

# Main clock constraint
create_clock -name clk50 -period 20.0 [get_ports {MAX10_CLK1_50}]

# Relax constraints on asynchronous inputs
set_input_delay -clock clk50 -max 5 [get_ports {SW* KEY*}]
set_input_delay -clock clk50 -min 0 [get_ports {SW* KEY*}]

# Output delays
set_output_delay -clock clk50 -max 5 [get_ports {LEDR* HEX* ARDUINO_IO*}]
set_output_delay -clock clk50 -min -2 [get_ports {LEDR* HEX* ARDUINO_IO*}]
