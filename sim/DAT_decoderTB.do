# ModelSim simulation script for the BCH encoder project.
# Run from the ModelSim Tcl console with:
#   do sim/DAT_decoderTB.do

# Resolve the project directories explicitly.
# set project_root C:/Users/Tommy/Documents/-Project-Work-BCH-Decoder
set project_root C:/Users/david/Desktop/-Project-Work-BCH-Decoder
set script_dir $project_root/sim

cd $script_dir

# Create a local modelsim.ini so vmap does not try to write into the
# installation directory under C:\intelFPGA_lite.
if {![file exists modelsim.ini]} {
	vmap -c
}

#proc call_python {p_r} {
#	set python C:/Users/david/AppData/Local/Microsoft/WindowsApps/python3.11.exe
#    set output [exec $python $p_r/src/TestFiles/test.py]
#	#set output [exec $p_r/src/TestFiles/test.py]
#    puts $output
#}

# Create and map the work library
vlib work
vmap work work

# Compile design files
vcom -2008 $project_root/src/decoder/one_hot_encoder.vhd
vcom -2008 $project_root/src/LUT/a_to_log_a_tabel.vhd
vcom -2008 $project_root/src/LUT/a_to_a_pow3_tabel.vhd
vcom -2008 $project_root/src/LUT/log_A_to_log_rootsOfA_tabel.vhd
vcom -2008 $project_root/src/decoder/syndrome_calculator.vhd
vcom -2008 $project_root/src/decoder/decoder.vhd

# Compile testbench
vcom -2008 $script_dir/decoder_tb.vhd

# Start simulation
vsim work.decoder_tb

# Add all signals to the wave window
add wave -recursive *

# Run simulation
run 6000ns

# call_python {$project_root}