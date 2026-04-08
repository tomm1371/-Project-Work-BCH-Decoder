# ModelSim simulation script template
# Place in sim/ and run from the ModelSim Tcl console:
#   do sim/simulate.do

# Create and map the work library
vlib work
vmap work work

# Compile VHDL source files
vcom -2008 ../src/bch_decoder.vhd

# Compile testbench
vcom -2008 ../tb/bch_decoder_tb.vhd

# Start simulation (replace 'bch_decoder_tb' with your testbench entity name)
vsim work.bch_decoder_tb

# Add all signals to the wave window
add wave -recursive *

# Run simulation
run -all
