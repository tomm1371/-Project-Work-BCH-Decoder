# BCH Decoder — VHDL Project (Quartus + ModelSim)

A VHDL implementation of a BCH (Bose–Chaudhuri–Hocquenghem) error-correcting code decoder, targeting Intel/Altera FPGAs and developed with Quartus Prime and ModelSim.

---

## Folder Structure

```
.
├── src/top       # Top-level VHDL source files (.vhd)
├───── /encoder   # Encoder entities
├───── /decoder   # Decoder entities
├───── /LUT       # Lookup tables for decoder
├───── /data      # bitdata used for en-/decoder in vhd format
├── sim/          # Testbenches (*_tb.vhd) andModelSim .do simulation scripts
├── quartus/      # Quartus project files (.qpf, .qsf)
└── README.md
```

## Getting Started

### Quartus Prime

1. Open Quartus Prime and select **File → Open Project**.
2. Navigate to `quartus/bch_decoder.qpf`.
3. Update `quartus/bch_decoder.qsf` with your target device and pin assignments.
4. Compile the project (**Processing → Start Compilation**).

### ModelSim Simulation

1. Open ModelSim and set the working directory to the project root.
2. Update "project directories", in .do file, to mach local path
3. In the Tcl console, run:
   ```tcl
   do sim/encode.do
   do sim/encode.do
   ```
4. The script compiles the design and testbench, opens the wave window, and runs the simulation.

---

### Python Tools
Varius python tools, used to generate and format data for both ModelSim and Quartus, and for comparing results.

   ```
   generate_testdata.py             # Generate randomData for encoder
   add_errors_to_data.py            # add random errors to data
   txt_to_rom.py                    # Convert txt document to vhd format for FPGA
   compareTestDataToDecodedData.py  # compare two txt files
   ```