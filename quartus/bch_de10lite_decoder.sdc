# Replace "clk" with your actual clock port name
create_clock -name clk -period 20.000 [get_ports {clk}]

# If you have any PLLs for clock generation
derive_pll_clocks

# Apply standard clock uncertainty
derive_clock_uncertainty

# Basic I/O constraints (adjust values based on your external logic)
set_input_delay -clock clk -max 4.000 [all_inputs]
set_input_delay -clock clk -min 2.000 [all_inputs]
set_output_delay -clock clk -max 4.000 [all_outputs]
set_output_delay -clock clk -min 2.000 [all_outputs]