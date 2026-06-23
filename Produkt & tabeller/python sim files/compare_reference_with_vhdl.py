from add_product_errors import (
    CODEWORD_BITS,
    add_ordered_errors,
    create_error_order,
    error_codewords_path,
)
from product_decoder_reference import decode_product_blocks
from run_product_test import (
    decoder_do_path,
    decoder_output_path,
    prepare_clean_blocks,
    read_product_blocks,
    run_modelsim_script,
    write_product_blocks,
)


BLOCKS = 1
DATA_SEED = 42
NOISE_SEED = 1000
ERROR_COUNT = 249
DECODER_ITERATIONS = 1
EXPECT_FULL_CORRECTION = True

# Add the same deterministic ordered error pattern to every test block.
# It will give each block its own seed, but it will always be the same.
# For a particular block, the error pattern is ALWAYS the first error_count positions from the same error_order.
# This matters, because we can change error_count, and it wont change the "pattern" of errors, making it reproduceable
# ultimately making us able to find the number of errors (for a fixed seed) that is the threshold value
def make_ordered_noisy_blocks(clean_blocks, error_count):
    noisy_blocks = []
    total_inserted_errors = 0

    for block_index, clean_block in enumerate(clean_blocks):
        error_order = create_error_order(
            NOISE_SEED + block_index,
        )

        noisy_block, inserted_errors = add_ordered_errors(
            clean_block,
            error_order,
            error_count,
        )

        noisy_blocks.append(noisy_block)
        total_inserted_errors += inserted_errors

    return noisy_blocks, total_inserted_errors

# Decode all noisy blocks with the VHDL product decoder in ModelSim.
def decode_blocks_with_vhdl(noisy_blocks, decoder_iterations):
    decoder_run_time_us = 100 + (30 * len(noisy_blocks) * decoder_iterations)

    write_product_blocks(
        error_codewords_path,
        noisy_blocks,
    )

    run_modelsim_script(
        decoder_do_path,
        decoder_iterations=decoder_iterations,
        run_time_us=decoder_run_time_us,
    )

    return read_product_blocks(decoder_output_path)

# Verify that Python and VHDL produced identical decoded product blocks.
# Check if there is a mismatch of codewords
# if there is, we will find the block, codeword and which bit in that codeword is different
def verify_python_matches_vhdl(
    python_decoded_blocks,
    vhdl_decoded_blocks,
):
    if len(python_decoded_blocks) != len(vhdl_decoded_blocks):
        raise AssertionError(
            "Python and VHDL returned different numbers of product blocks."
        )

    for block_index, (python_block, vhdl_block) in enumerate(
        zip(python_decoded_blocks, vhdl_decoded_blocks)
    ):
        for codeword_index, (python_codeword, vhdl_codeword) in enumerate(
            zip(python_block, vhdl_block)
        ):
            if python_codeword != vhdl_codeword:
                differing_vhdl_bits = [
                    CODEWORD_BITS - 1 - string_index
                    for string_index, (python_bit, vhdl_bit) in enumerate(
                        zip(python_codeword, vhdl_codeword)
                    )
                    if python_bit != vhdl_bit
                ]

                raise AssertionError(
                    f"Python/VHDL mismatch in block {block_index}, "
                    f"output codeword {codeword_index}, "
                    f"VHDL bits {differing_vhdl_bits}."
                )

    print("PASS: Python and VHDL decoded outputs are identical.")


def run_threshold_case(
    clean_blocks,
    error_count,
    decoder_iterations,
    expect_full_correction,
):
    noisy_blocks, total_inserted_errors = make_ordered_noisy_blocks(
        clean_blocks,
        error_count,
    )
    print(f"Inserted {total_inserted_errors} deterministic errors.")

    print("Decoding with the Python reference model.")
    python_decoded_blocks = decode_product_blocks(
        noisy_blocks,
        decoder_iterations,
    )

    print("Decoding with the VHDL ModelSim simulation.")
    vhdl_decoded_blocks = decode_blocks_with_vhdl(
        noisy_blocks,
        decoder_iterations,
    )

    verify_python_matches_vhdl(
        python_decoded_blocks,
        vhdl_decoded_blocks,
    )

    full_correction = python_decoded_blocks == clean_blocks
    if full_correction != expect_full_correction:
        expected_result = "full correction" if expect_full_correction else "failure"
        actual_result = "full correction" if full_correction else "failure"
        raise AssertionError(
            f"Expected {expected_result}, but observed {actual_result}."
        )

    result_text = "full correction" if full_correction else "expected failure"
    print(f"PASS: Both implementations agree on {result_text}.")

    return {
        "error_count": error_count,
        "decoder_iterations": decoder_iterations,
        "expected_full_correction": expect_full_correction,
        "full_correction": full_correction,
    }


def main():
    print("Preparing one clean product block.")
    clean_blocks = prepare_clean_blocks(
        blocks=BLOCKS,
        data_seed=DATA_SEED,
    )

    run_threshold_case(
        clean_blocks,
        ERROR_COUNT,
        DECODER_ITERATIONS,
        EXPECT_FULL_CORRECTION,
    )


if __name__ == "__main__":
    main()
