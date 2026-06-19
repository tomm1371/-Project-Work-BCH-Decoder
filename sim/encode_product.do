# ModelSim simulation script for the BCH encoder project.
# Run from the ModelSim Tcl console with:
#   do sim/simulate.do

# Resolve the project directories explicitly.
set project_root C:/Users/Tommy/Documents/-Project-Work-BCH-Decoder
# set project_root C:/Users/david/Desktop/-Project-Work-BCH-Decoder
set script_dir $project_root/sim

cd $script_dir

# Create a local modelsim.ini so vmap does not try to write into the
# installation directory under C:\intelFPGA_lite.
if {![file exists modelsim.ini]} {
	vmap -c
}

# Create and map the work library
vlib work
vmap work work

# Compile design files
vcom -2008 $project_root/src/encoder/encoder.vhd
vcom -2008 $project_root/src/encoder/encoder_product.vhd


# Compile testbench
vcom -2008 $script_dir/encoder_product_tb.vhd

# Start simulation
vsim work.bch_encoder_tb_256

# hide full names
quietly WaveActivateNextPane {} 0
configure wave -namecolwidth 200
configure wave -signalnamewidth 1

# Add all signals to the wave window in hex
add wave -radix hex -recursive *

# Run simulation for a fixed time
run 55000 ns
