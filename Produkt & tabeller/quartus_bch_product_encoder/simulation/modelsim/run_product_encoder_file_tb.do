# ModelSim simulation script for the BCH encoder project.
# Run from the ModelSim Tcl console with:
#   do sim/simulate.do

# Locate this script and the Quartus project relative to it.
 # Save the folder that this .do file is in.
# Use a caller-supplied directory when Python starts ModelSim (the earlier method to set the directory didnt work when trying to run this directly from python).
# This way, python will set the variable.
if {![info exists script_dir]} {
    set script_dir [file normalize [file dirname [info script]]]
}

 # Save the quartus-project folder (this is 2 levels "up")
set quartus_project_dir [file normalize [file join $script_dir .. ..]]
 # set the path to the src-folder that contains all the VHDL files.
set source_dir [file join $quartus_project_dir src]
 # make this folder the PWD for ModelSim.
cd $script_dir 

# Create a local modelsim.ini so vmap does not try to write into the
# installation directory under C:\intelFPGA_lite.
if {![file exists modelsim.ini]} {
	vmap -c
}

# Remove VHDL files compiled by an earlier run.
if {[file exists work]} {
    vdel -lib work -all
}

# Create an empty work library for this run.
vlib work
vmap work work

# Compile the BCH component encoder and its dependency.
# [file join ...] builds the full path from source_dir and the filename
# even when the project path contains spaces.
vcom -2008 [file join $source_dir gf_mod_256.vhd]
vcom -2008 [file join $source_dir encoder.vhd]

# Compile the product encoder.
vcom -2008 [file join $source_dir product_encoder_v2.vhd]

# Compile the file-based product encoder testbench.
vcom -2008 [file join $source_dir product_encoder_file_tb.vhd]

# Start the product encoder file testbench.
vsim work.product_encoder_file_tb

# The waveform is not needed for the file-based test.
# Python will inspect productEncoderOutput.txt afterwards.

# Run long enough for the current 10 product blocks to finish.
# I think 100 microseconds is enough.
# update: it wasn't. 150 microseconds was enough.
# update: this should be variable. It is now controlled from the amount of blocks specified in the python script.
# Still has a default value.
if {![info exists run_time_us]} {
    set run_time_us 150
}

run $run_time_us us