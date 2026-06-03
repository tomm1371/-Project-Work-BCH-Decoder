# ModelSim simulation script for the BCH encoder project.
# Run from the ModelSim Tcl console with:
#   do sim/simulate.do

# Resolve the project directories robustly (no user-specific paths).
# If this script is sourced in a way that makes [info script] empty,
# fall back to the current working directory (`pwd`).
set info_script [info script]
if {$info_script == ""} {
	puts "simulate.do: info script is empty; using current working directory as script_dir"
	set script_dir [pwd]
} else {
	set script_dir [file dirname [file normalize $info_script]]
}
set script_dir [file normalize $script_dir]
set project_root [file dirname $script_dir]

puts "simulate.do: info_script=$info_script"
puts "simulate.do: script_dir=$script_dir"
puts "simulate.do: project_root=$project_root"

# Sanity-check expected files and warn early (helps debugging path issues)
set f_gf_mod $project_root/src/encoder/gf_mod_256.vhd
set f_bch_enc $project_root/src/encoder/bch_encoder_256.vhd
set f_tb $script_dir/bch_encoder_tb_256.vhd
if {![file exists $f_gf_mod]} {
	puts "WARNING: expected file not found: $f_gf_mod"
}
if {![file exists $f_bch_enc]} {
	puts "WARNING: expected file not found: $f_bch_enc"
}
if {![file exists $f_tb]} {
	puts "WARNING: expected testbench not found: $f_tb"
}

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
vcom -2008 $project_root/src/encoder/gf_mod_256.vhd
vcom -2008 $project_root/src/encoder/bch_encoder_256.vhd

# Compile testbench
vcom -2008 $script_dir/bch_encoder_tb_256.vhd

# Start simulation
vsim work.bch_encoder_tb_256

# Add all signals to the wave window in hex
add wave -radix hex -recursive *

# Run simulation for a fixed time
run 5200 ns
