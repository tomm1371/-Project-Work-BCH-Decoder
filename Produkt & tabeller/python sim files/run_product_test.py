import pathlib
import random
import subprocess

# Import functions and constants from the error generation script.
from add_product_errors import (
    COLUMNS_PER_BLOCK,
    RANDOM_SEED,
    add_burst_errors,
    add_exact_random_errors,
    add_random_errors,
    clean_codewords_path,
    error_codewords_path,
    CODEWORD_BITS,
)
# import the 2 functions we need to generate and verify the encoded data.
from generate_product_testdata import generate_product_testdata
from verify_product_encoder_output import verify_product_encoder_output

# Updated global variables
# the run time calculations have been moved to independent functions.
BLOCKS = 10
DATA_SEED = 42
NOISE_SEED = RANDOM_SEED
DECODER_ITERATIONS = 3

ERROR_MODEL = "exact_random" # Mode selection. Which error model to use when adding errors. Options: "random_probability", "exact_random", "burst". See the add_product_errors.py script for details on each model.
# Parameters for the error models.
ERROR_COUNT = 300
ERROR_PROBABILITY = 0.01
BURST_COUNT = 1
BURST_HEIGHT = 4
BURST_WIDTH = 8

script_folder = pathlib.Path(__file__).resolve().parent
project_folder = script_folder.parent
modelsim_folder = (
    project_folder
    / "quartus_bch_product_encoder"
    / "simulation"
    / "modelsim"
)
encoder_do_path = modelsim_folder / "run_product_encoder_file_tb.do"
decoder_do_path = modelsim_folder / "run_product_decoder_file_tb.do"
decoder_output_path = modelsim_folder / "testfiles" / "productDecoderOutput.txt"

# Run 1 modelsim DO file (we have 2: one for encoding and one for decoding)
def run_modelsim_script(
        do_path,
        decoder_iterations=None,
        run_time_us=None,                
                        ):
    if not do_path.exists(): # Check if the DO file exists before trying to run it
        raise FileNotFoundError(f"ModelSim script not found: {do_path}")

    # We explicitly set the script_dir variable in the DO file to the path of the modelsim folder
    # because the DO file couldn't find the files needed when the variable was hardcoded in the DO file itself.
    tcl_settings = f"set script_dir {{{modelsim_folder.as_posix()}}}; "
    if decoder_iterations is not None:
        tcl_settings += f"set decoder_iterations {decoder_iterations}; " # in the entity of the decoder TB, iterations is added so we can change it from this script.

    if run_time_us is not None:
        tcl_settings += f"set run_time_us {run_time_us}; " # And the run time of a simulation is something we can also change from this script.

    do_command = (
        tcl_settings
        + f"do {{{do_path.as_posix()}}}; quit -f"
        )

    command = [
        "vsim",
        "-c",
        "-do",
        do_command, # The command runs the .do script and closes ModelSim after the script finishes.
    ]

    # Subprocess is a library that allows us to run external commands from python. Here we use it to run the modelsim command without opening the program's GUI, and we set check=True to raise an error if the command fails
    subprocess.run( 
        command,
        cwd=modelsim_folder,
        check=True,
    )

# This function will read a flat codeword file and group every 256 lines into 1 product block
# i.e. it creates the 256x256 structure of the product code from the flat txt file.
def read_product_blocks(file_path):
    codewords = []

    with open(file_path, "r", encoding="ascii") as input_file:
        for line in input_file:
            codeword = line.strip()

            if len(codeword) != CODEWORD_BITS:
                raise ValueError(
                    f"Expected a {CODEWORD_BITS}-bit codeword, got {len(codeword)} bits."
                )

            codewords.append(codeword) # codewords is a flat list of all the codewords in the file, we will later group them into blocks.

    # This catches a truncated or incomplete VHDL output file. It usually wont happen, but it might if the encoder TB is stopped before it is done
    # Or if the txt file is directly tampered with by a user.
    if len(codewords) % COLUMNS_PER_BLOCK != 0:
        raise ValueError("The file does not contain a whole number of product blocks.") 

    product_blocks = []

    # Group the codewords into blocks.
    # Each element in product_blocks is then a list of 256 codewords, each 256 bits long.
    for first_codeword in range(0, len(codewords), COLUMNS_PER_BLOCK):
        product_block = codewords[
            first_codeword:first_codeword + COLUMNS_PER_BLOCK
        ]
        product_blocks.append(product_block)

    return product_blocks

# This function will write the blocks back to a flat file, with one codeword per line
# It is used after errors are introduced to write the noisy codewords back to a file that can be fed into the decoder testbench.
def write_product_blocks(file_path, product_blocks):
    with open(file_path, "w", encoding="ascii") as output_file:
        for product_block in product_blocks:
            for codeword in product_block:
                output_file.write(codeword + "\n")



# Updated add_errors_to_blocks function.
# Now we make it general and parameter-based, so it is usable for statistical testing with many runs and different models.
# Main difference is, that error_model, noise_seed and error_count are now arguements, and not read from the global variables at the top of the file.
# The function takes in the clean blocks, the error model to use, and the parameters for that error model, and returns the noisy blocks with errors added according to the specified model.
def add_errors_to_blocks(
    clean_blocks,
    error_model,
    noise_seed,
    error_count=0,
    error_probability=0.0,
    burst_count=0,
    burst_height=1,
    burst_width=1,
    verbose=True, # verbose mode means that the function will print out how many errors were added to each block (mostly for testing and debug. Should be turned off for large runs).
):
    random_generator = random.Random(noise_seed)

    noisy_blocks = []
    total_error_count = 0

    for block_index, clean_block in enumerate(clean_blocks, start=1): # We use enumerate to keep track of the block index. Note that we start from 1, even though most other logic is 0-indexed.
        if error_model == "random_probability":
            noisy_block, block_error_count = add_random_errors(
                clean_block,
                error_probability,
                random_generator,
            )

        elif error_model == "burst":
            noisy_block, block_error_count = add_burst_errors(
                clean_block,
                burst_count,
                burst_height,
                burst_width,
                random_generator,
            )

        elif error_model == "exact_random":
            noisy_block, block_error_count = add_exact_random_errors(
                clean_block,
                error_count,
                random_generator,
            )

        else:
            raise ValueError(f"Unknown error model: {error_model}")

        noisy_blocks.append(noisy_block)
        total_error_count += block_error_count

        if verbose:
            print(f"Block {block_index}: inserted {block_error_count} errors.")

    return noisy_blocks, total_error_count


# This function checks the output of the decoder against the codewords BEFORE errors are added
# This is the main "testing" function, as it is the one that verifies the decoder directly.
# Updated version: Now it returns a dictionary with the results of the verification.
# This is useful, because we want to make statistical tests with many runs, and the results should be well structured and easily accessible.
def verify_decoder_output(clean_blocks, decoded_blocks, verbose=True):
    if len(decoded_blocks) != len(clean_blocks):
        if verbose:
            print(
                f"FAIL: expected {len(clean_blocks)} decoded block(s), "
                f"but got {len(decoded_blocks)}."
            )
        return {
            "success": False,
            "incorrect_codewords": None,
            "incorrect_bits": None,
        }

    incorrect_codewords = 0
    incorrect_bits = 0

    # Iterate thorugh the clean and decoded blocks and compare them bit by bit. 
    # We count how many codewords & bits are incorrect, and we print the results (if verbose is True).
    for block_index, (clean_block, decoded_block) in enumerate(
        zip(clean_blocks, decoded_blocks),
        start=1,
    ):
        for codeword_index, (clean_codeword, decoded_codeword) in enumerate(
            zip(clean_block, decoded_block),
            start=1,
        ):
            if clean_codeword != decoded_codeword:
                incorrect_codewords += 1

                for clean_bit, decoded_bit in zip(
                    clean_codeword,
                    decoded_codeword,
                ):
                    if clean_bit != decoded_bit:
                        incorrect_bits += 1

                if verbose:
                    print(
                        f"Mismatch in block {block_index}, "
                        f"codeword {codeword_index}."
                    )

    success = incorrect_codewords == 0

    if verbose:
        if success:
            print("PASS: Product decoder restored every clean codeword.")
        else:
            print(
                f"FAIL: {incorrect_codewords} codeword(s) and "
                f"{incorrect_bits} bit(s) differ."
            )

    return {
        "success": success,
        "incorrect_codewords": incorrect_codewords,
        "incorrect_bits": incorrect_bits,
    }

# This function prepares the clean blocks by running the encoder and verifying the output.
# It is used as the first step in the main test (and can be used to independently test the encoder).
# The main reason for making this a seperate function is, that the statistics script will work on the same clean data
# and therefore we shouldn't make the simulation do the encoding for each run.
def prepare_clean_blocks(blocks, data_seed, verbose=True):
    encoder_run_time_us = 50 + (15 * blocks)
    if verbose:
        print("Generating product input data.")
    generate_product_testdata(blocks=blocks, seed=data_seed)
    if verbose:
        print("Running the product encoder simulation.")

    run_modelsim_script(
        encoder_do_path,
        run_time_us=encoder_run_time_us,
        )

    if verbose:
        print("Verifying the product encoder output.")

    if not verify_product_encoder_output():
        raise RuntimeError("Product encoder verification failed.")
    return read_product_blocks(clean_codewords_path)

# Updated test logic. Now we create a generic function that returns a dictionary
# it is changed from being 1 simulation, to being a generic function that can be ran,
# because the statistics script needs a function. The old version required the script to be ran for each simulation run.
# Since the encoding part is in its own seperate function, now we just do:
# 1: Add erros with the chosen error model and parameters
# 2: Output the errorneous codewords to the decoder input files
# 3: run the decoder modelsim TB
# 4: Read the decoders outputfile
# 5: Compare codeword for codeword, bit for bit.
# 6: Output as a dictionary with some meta data.
# Again remember to not use "verbose" for long simulation runs in the statistic scripts.
def run_decoder_test(
    clean_blocks,
    error_model,
    decoder_iterations,
    noise_seed,
    error_count=0,
    error_probability=0.0,
    burst_count=0,
    burst_height=1,
    burst_width=1,
    verbose=True,
):
    decoder_run_time_us = (
        100 + (30 * len(clean_blocks) * decoder_iterations)
    )
    if verbose:
        print(f"Adding {error_model} errors.")
    noisy_blocks, total_error_count = add_errors_to_blocks(
        clean_blocks,
        error_model,
        noise_seed,
        error_count=error_count,
        error_probability=error_probability,
        burst_count=burst_count,
        burst_height=burst_height,
        burst_width=burst_width,
        verbose=verbose,
    )

    write_product_blocks(error_codewords_path, noisy_blocks)

    if verbose:
        print(f"Total inserted errors: {total_error_count}.")
        print("Running the product decoder simulation.")
    run_modelsim_script(
        decoder_do_path,
        decoder_iterations=decoder_iterations,
        run_time_us=decoder_run_time_us,
    )

    decoded_blocks = read_product_blocks(decoder_output_path)

    if verbose:
        print("Verifying the product decoder output.")
    result = verify_decoder_output(
        clean_blocks,
        decoded_blocks,
        verbose=verbose,
    )

    result["blocks"] = len(clean_blocks)
    result["error_model"] = error_model
    result["decoder_iterations"] = decoder_iterations
    result["inserted_errors"] = total_error_count

    return result


# Single simulation run should still be doable from this file.
def main():
    clean_blocks = prepare_clean_blocks(
        blocks=BLOCKS,
        data_seed=DATA_SEED,
    )

    result = run_decoder_test(
        clean_blocks,
        error_model=ERROR_MODEL,
        decoder_iterations=DECODER_ITERATIONS,
        noise_seed=NOISE_SEED,
        error_count=ERROR_COUNT,
        error_probability=ERROR_PROBABILITY,
        burst_count=BURST_COUNT,
        burst_height=BURST_HEIGHT,
        burst_width=BURST_WIDTH,
    )

    if not result["success"]:
        raise RuntimeError("Product decoder verification failed.")

    print("PASS: The complete product-code test passed.")


# To run one test, change the global variables at the top of this file, and execute the script.
if __name__ == "__main__":
    main()