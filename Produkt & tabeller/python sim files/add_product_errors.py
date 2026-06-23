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


# Create one reproducible ordering of every bit position in a product block.
# The first E positions in this order define the error pattern with E errors.
# This is used to find the empirical error threshhold for one fixed seed
# i.e. the transition between full decoding and failure.
def create_error_order(seed):
    maximum_errors = ROWS_PER_BLOCK * COLUMNS_PER_BLOCK

    error_order = list(range(maximum_errors))
    random_generator = random.Random(seed)
    random_generator.shuffle(error_order)

    return error_order # It returns a fixed permutation of all 65536 bit positions.

# This function will flip the first error_count positions from the fixed permutation
# that is calculated from the function create_error_order.
def add_ordered_errors(product_block, error_order, error_count):
    maximum_errors = ROWS_PER_BLOCK * COLUMNS_PER_BLOCK

    if len(product_block) != COLUMNS_PER_BLOCK:
        raise ValueError("A product block must contain exactly 256 codewords.")
    if len(error_order) != maximum_errors:
        raise ValueError("The error order must contain exactly 65,536 positions.")
    if not 0 <= error_count <= maximum_errors:
        raise ValueError(f"The error count must be between 0 and {maximum_errors}.")

    noisy_block = product_block.copy()

    for flat_position in error_order[:error_count]:
        row_index = flat_position // COLUMNS_PER_BLOCK
        column_index = flat_position % COLUMNS_PER_BLOCK

        noisy_block[column_index] = flip_bit(
            noisy_block[column_index],
            row_index,
        )

    return noisy_block, error_count



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


# Sequential burst errors in the serialized product-codeword stream.
# burst_count: number of non-overlapping bursts to introduce.
# burst_length: number of consecutive errors in each burst.
def add_burst_errors(product_block, burst_count, burst_length, rng):
    if len(product_block) != COLUMNS_PER_BLOCK:
        raise ValueError("A product block must contain exactly 256 codewords.")
    if burst_count < 0:
        raise ValueError("The burst count cannot be negative.")
    total_bits = COLUMNS_PER_BLOCK * CODEWORD_BITS
    if not 1 <= burst_length <= total_bits:
        raise ValueError(
            f"The burst length must be between 1 and {total_bits}."
        )
    if burst_count * burst_length > total_bits:
        raise ValueError("The requested bursts do not fit within one product block.")

    # Calculate non-overlapping intervals of burst_length bits. 
    # The transformed start positions makes sure that each burst has a random location but still has the specified number of consecutive errors
    remaining_gap_bits = total_bits - (burst_count * burst_length)
    compressed_positions = sorted(
        rng.sample(
            range(remaining_gap_bits + burst_count),
            burst_count,
        )
    )
    burst_starts = [
        compressed_position + burst_index * (burst_length - 1)
        for burst_index, compressed_position in enumerate(compressed_positions)
    ]

    noisy_block = product_block.copy()
    for start_position in burst_starts:
        for flat_position in range(start_position, start_position + burst_length):
            codeword_index = flat_position // CODEWORD_BITS
            bit_index = flat_position % CODEWORD_BITS
            noisy_block[codeword_index] = flip_bit(
                noisy_block[codeword_index],
                bit_index,
            )

    return noisy_block, burst_count * burst_length


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
