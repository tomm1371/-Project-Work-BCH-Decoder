# ModelSim simulation script for the BCH decoder project.
# Run from the ModelSim Tcl console.

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

# Everything before the compilation is the same
# as it was for the encoder DO file.
# The difference lies only with what files should be compiled, and in what order.

# Compile the BCH decoder's lookup tables and helper modules.
vcom -2008 [file join $source_dir a_to_log_a_tabel.vhd]
vcom -2008 [file join $source_dir a_to_a_pow3_tabel.vhd]
vcom -2008 [file join $source_dir log_A_to_log_rootsOfA_tabel.vhd]
vcom -2008 [file join $source_dir one_hot_encoder.vhd]
vcom -2008 [file join $source_dir syndrome_calculator.vhd]

# Compile the BCH component decoder.
vcom -2008 [file join $source_dir decoder.vhd]

# Compile the product decoder and its file-based testbench.
vcom -2008 [file join $source_dir product_decoder.vhd]
vcom -2008 [file join $source_dir product_decoder_file_tb.vhd]

# In the decoder TB, the run time should vary with amount of iterations
# The amount of iterations is controlled from the python script
# We keep some default values in case none are set in the python script.
if {![info exists decoder_iterations]} {
    set decoder_iterations 3
}

if {![info exists run_time_us]} {
    set run_time_us 1000
}

vsim -gITERATIONS=$decoder_iterations work.product_decoder_file_tb

run $run_time_us us