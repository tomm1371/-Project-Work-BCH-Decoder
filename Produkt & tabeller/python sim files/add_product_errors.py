import pathlib
import random

# Constants for indexing (after encoding).
ROWS_PER_BLOCK = 256
COLUMNS_PER_BLOCK = 256
CODEWORD_BITS = 256
RANDOM_SEED = 42 # Reproducibility

# Set up paths to files.
script_folder = pathlib.Path(__file__).resolve().parent
project_folder = script_folder.parent
testfiles_folder = (
    project_folder
    / "quartus_bch_product_encoder"
    / "simulation"
    / "modelsim"
    / "testfiles"
)

clean_codewords_path = testfiles_folder / "productEncoderOutput.txt" # Input file with clean codewords.
error_codewords_path = testfiles_folder / "productCodewordsWithErrors.txt" # Output file for codewords with errors.

# Flip a bit in a codeword at the specified spot.
def flip_bit(codeword, bit_index):
    if len(codeword) != CODEWORD_BITS:
        raise ValueError("A product codeword must contain exactly 256 bits.")
    if not 0 <= bit_index < CODEWORD_BITS:
        raise ValueError("The bit index must be between 0 and 255.")

    flipped_bit = "1" if codeword[bit_index] == "0" else "0"
    return codeword[:bit_index] + flipped_bit + codeword[bit_index + 1:]


# Flip bits in the product block with a certain probability to simulate errors.
# Each bit is treated independently, and the total number of errors is counted and returned.
# rng is a random number generator instance.
def add_random_errors(product_block, error_probability, rng):
    
    if not 0 <= error_probability <= 1:
        raise ValueError("The error probability must be between 0 and 1.")
    if len(product_block) != COLUMNS_PER_BLOCK:
        raise ValueError("A product block must contain exactly 256 codewords.")

    noisy_block = []
    error_count = 0
    for codeword in product_block:
        noisy_codeword = codeword

        for bit_index in range(CODEWORD_BITS):
            if rng.random() < error_probability: # rng.random() generates a float in [0.0, 1.0) and we flip the bit if it's less than the error probability.
                noisy_codeword = flip_bit(noisy_codeword, bit_index)
                error_count += 1

        noisy_block.append(noisy_codeword)

    return noisy_block, error_count


# Rectangular burst errors.
# burst_count: number of bursts to introduce.
# burst_height: number of consecutive rows affected by each burst.
# burst_width: number of consecutive columns affected by each burst.
def add_burst_errors(product_block, burst_count, burst_height, burst_width, rng):
    if len(product_block) != COLUMNS_PER_BLOCK:
        raise ValueError("A product block must contain exactly 256 codewords.")
    if burst_count < 0:
        raise ValueError("The burst count cannot be negative.")
    if not 1 <= burst_height <= ROWS_PER_BLOCK:
        raise ValueError("The burst height must be between 1 and 256.")
    if not 1 <= burst_width <= COLUMNS_PER_BLOCK:
        raise ValueError("The burst width must be between 1 and 256.")

    error_positions = set() # set() creates an empty set to store UNIQUE error positions as (row_index, column_index) tuples.

    # For each burst, we randomly select a starting position for the burst
    # within the bounds of the block, ensuring that the entire burst fits within the block dimensions.
    for _ in range(burst_count):
        start_row = rng.randrange(ROWS_PER_BLOCK - burst_height + 1)
        start_column = rng.randrange(COLUMNS_PER_BLOCK - burst_width + 1)

        for row_index in range(start_row, start_row + burst_height):
            for column_index in range(start_column, start_column + burst_width):
                error_positions.add((row_index, column_index)) # We add the position of each bit that should be flipped to the error_positions set. Using a set ensures that we don't count the same bit multiple times if bursts overlap.

    noisy_block = product_block.copy() # We create a copy of the original block to modify, preserving the original data.

    # Finally iterate over each error_position and flip the bit at that position.
    for row_index, column_index in error_positions:
        noisy_block[column_index] = flip_bit(
            noisy_block[column_index],
            row_index
        )

    return noisy_block, len(error_positions)


# Add an exact number of random errors across the block
# The logic is similar to add_random_errors, but now we specify an amount of errors, and not a probability.
# We randomly select unique bit positions across the entire block to flip, ensuring that we introduce exactly the specified number of errors.
def add_exact_random_errors(product_block, error_count, rng):
  
    if len(product_block) != COLUMNS_PER_BLOCK:
        raise ValueError("A product block must contain exactly 256 codewords.")

    maximum_errors = ROWS_PER_BLOCK * COLUMNS_PER_BLOCK

    if not 0 <= error_count <= maximum_errors:
        raise ValueError(f"The error count must be between 0 and {maximum_errors}.")

    # flat_positions is a list of unique integers representing the positions of the bits to flip.
    # We use "sample" to ensure we get positions without replacement, meaning we won't flip the same bit more than once.
    # Also, we choose the positions before flipping, because we want to treat the entire block as it was originally, without counting the newly introduced errors as potential positions for more errors.
    flat_positions = rng.sample(range(maximum_errors), error_count)
    noisy_block = product_block.copy()

    # Finally, we iterate over the selected flat positions, convert them back to row and column indices, and flip the corresponding bits in the noisy block.
    for flat_position in flat_positions:
        row_index = flat_position // COLUMNS_PER_BLOCK
        column_index = flat_position % COLUMNS_PER_BLOCK

        noisy_block[column_index] = flip_bit(
            noisy_block[column_index],
            row_index
        )

    return noisy_block, error_count
