# BCH Decoder — VHDL Project (Quartus + ModelSim)

A VHDL implementation of a BCH (Bose–Chaudhuri–Hocquenghem) error-correcting code decoder, targeting Intel/Altera FPGAs and developed with Quartus Prime lite and ModelSim.

---

## Folder Structure

``` text
Project-Work-BCH-Decoder/
├───qar/       # archived vhdl project, ready to compile (.qar)
│
├───src/        # VHDL source files (.vhd)
│   ├───top/      # Top-level entities
│   ├───encoder/  # Encoder entities
│   ├───decoder/  # Decoder entities
│   ├───LUT/      # Lookup tables for decoder
│   └───data/     # bitdata used for en-/decoder
│
├───sim/       # ModelSim test benches (*_tb.vhd) andModelSim (.do) simulation scripts
│   ├───TestFiles/   # testdata as binary for ModelSim (.txt)
│   └───ImageTesting/# testdata, for working with images (.txt)
│
├───Produkt & tabeller/ # Product en- and decoder, including relevant python scripts
│
├───quartus/   # Quartus project files (.qpf, .qsf)
│
├───tools/     # Python scripts, used to build vhd or process data (.py)
└───README.md
```

## Getting Started

### Quartus Prime

1. Open `qar/encoder.qar` or `decoder.qar`
2. Compile the project (**Processing → Start Compilation**).
3. Program to a DE10-lite FPGA

---

### ModelSim Simulation

1. Open ModelSim and set the working directory to the project root.
2. Update "project directories", in .do file, to match local path
3. In the Tcl console, run either:

   ```tcl
   do sim/encode.do
   do sim/decode.do
   ```

4. The script compiles the design and test bench, opens the wave window, and runs the simulation.

---

### Python Tools
Varius python tools, used to generate and format data for both ModelSim and Quartus, and for comparing results.

   ```
   generate_testdata.py             # Generate randomData for encoder
   add_errors_to_data.py            # add random errors to data
   txt_to_rom.py                    # Convert txt document to vhd format for FPGA
   compareTestDataToDecodedData.py  # compare two txt files
   product_decoder_reference.py     # Python reference model for decoder
   ```