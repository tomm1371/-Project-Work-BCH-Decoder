import csv
import pathlib
import random
import statistics
import matplotlib.pyplot as plt

from add_product_errors import CODEWORD_BITS, add_random_errors
from product_decoder_reference import decode_product_blocks
from generate_product_testdata import generate_product_testdata, output_path
from verify_product_encoder_output import encode_product_block

# Each VHDL data point decodes several product blocks in one simulation.
# A shared seeded random generator creates a different reproducible noise pattern for each block, reducing the required number of ModelSim runs.
BLOCKS_PER_TEST = 1
DATA_SEED = 42
BASE_NOISE_SEED = 1000
TRIALS_PER_POINT = 50

# x-axis (pre-decoding BER)
ERROR_PROBABILITIES = [
   point/10000 for point in range (0,121)
]
ITERATION_COUNTS = [1, 2, 3, 4, 5]


script_folder = pathlib.Path(__file__).resolve().parent
output_folder = script_folder / "statistics_output"
csv_path = output_folder / "python_reference_random_ber_results.csv"
plot_path = output_folder / "python_reference_random_ber.png" # change this value for different experiments to not overwrite existing graph.

# Create the function that creates the clean blocks.
# This is done, so the simulation run time is much smaller. 
# The resulting data should be the same, as the python reference encodes the same way.
def prepare_reference_clean_blocks(blocks, data_seed):
    generate_product_testdata(
        blocks=blocks,
        seed=data_seed,
    )

    input_rows = []
    with open(output_path, "r", encoding="ascii") as input_file:
        input_file.readline()  # Skip header.
        for line in input_file:
            input_rows.append(line.strip())

    return [
        encode_product_block(input_rows[first_row:first_row + 239])
        for first_row in range(0, len(input_rows), 239)
    ]


def count_remaining_bit_errors(clean_blocks, decoded_blocks):
    return sum(
        clean_bit != decoded_bit
        for clean_block, decoded_block in zip(clean_blocks, decoded_blocks)
        for clean_codeword, decoded_codeword in zip(
            clean_block, decoded_block
        )
        for clean_bit, decoded_bit in zip(
            clean_codeword, decoded_codeword
        )
    )


# Central function.
# It is updated from run_vhdl_random_ber_statistics.py to use the Python reference encoder and decoder
# instead of the VHDL simulation.
def run_experiment():
    output_folder.mkdir(exist_ok=True)

    print("Preparing clean Python reference encoder output.")
    clean_blocks = prepare_reference_clean_blocks(
        blocks=BLOCKS_PER_TEST,
        data_seed=DATA_SEED,
    )

    total_bits = len(clean_blocks) * CODEWORD_BITS * CODEWORD_BITS
    results = []

    for error_probability in ERROR_PROBABILITIES:
        for trial_index in range(TRIALS_PER_POINT):
            noise_seed = BASE_NOISE_SEED + trial_index
            random_generator = random.Random(noise_seed)

            # Create the noisy blocks once for this BER and trial.
            # The same error pattern is then used for every iteration count.
            noisy_blocks = []
            total_inserted_errors = 0

            for clean_block in clean_blocks:
                noisy_block, inserted_errors = add_random_errors(
                    clean_block,
                    error_probability,
                    random_generator,
                )
                noisy_blocks.append(noisy_block)
                total_inserted_errors += inserted_errors

            for iterations in ITERATION_COUNTS:
                print(
                    f"Testing p={error_probability:.4f}, "
                    f"{iterations} iteration(s), "
                    f"trial {trial_index + 1}/{TRIALS_PER_POINT}."
                )

                decoded_blocks = decode_product_blocks(
                    noisy_blocks,
                    iterations,
                )

                incorrect_bits = count_remaining_bit_errors(
                    clean_blocks,
                    decoded_blocks,
                )

                incorrect_codewords = sum(
                    clean_codeword != decoded_codeword
                    for clean_block, decoded_block in zip(
                        clean_blocks,
                        decoded_blocks,
                    )
                    for clean_codeword, decoded_codeword in zip(
                        clean_block,
                        decoded_block,
                    )
                )
                # Each entrance in the output list is a dictionary with the following data:
                result_row = {
                    "configured_pre_decode_ber": error_probability,
                    "observed_pre_decode_ber": (total_inserted_errors / total_bits),
                    "post_decode_ber": incorrect_bits / total_bits,
                    "iterations": iterations,
                    "trial": trial_index + 1,
                    "noise_seed": noise_seed,
                    "blocks": len(clean_blocks),
                    "error_model": "random_probability",
                    "decoder_iterations": iterations,
                    "inserted_errors": total_inserted_errors,
                    "success": incorrect_bits == 0,
                    "incorrect_codewords": incorrect_codewords,
                    "incorrect_bits": incorrect_bits,
                }
                results.append(result_row)

    return results


# As with most of the other tests/statistics, the results are written in CSV format based on the dictionary outputs.
def write_results_csv(results):
    fieldnames = [
        "configured_pre_decode_ber",
        "observed_pre_decode_ber",
        "post_decode_ber",
        "iterations",
        "trial",
        "noise_seed",
        "blocks",
        "error_model",
        "decoder_iterations",
        "inserted_errors",
        "success",
        "incorrect_codewords",
        "incorrect_bits",
    ]

    with csv_path.open("w", newline="", encoding="utf-8") as csv_file:
        writer = csv.DictWriter(csv_file, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(results)

    print(f"Saved raw results to: {csv_path}")

# Make the BER graph that matches the format of the statistical model, and the reference model statistics.
def plot_post_decode_ber(results):
    figure, axis = plt.subplots(figsize=(9, 5))
    # For this python version, it is realistic to change the amount of trials_per_point
    # therefore the amount of bits should be calculated accordingly.
    total_bits = BLOCKS_PER_TEST * CODEWORD_BITS * CODEWORD_BITS * TRIALS_PER_POINT
    
    # log(0) is not defined, but since error numbers are integers, we can just define the "perfect correction line"
    # to be at the point when the amount of errors is below 1, meaning that there are 0 errors.
    plot_floor = 0.5 / total_bits 

    for iterations in ITERATION_COUNTS:
        mean_post_decode_ber = []

        for error_probability in ERROR_PROBABILITIES:
            matching_results = [
                result
                for result in results
                if (
                    result["configured_pre_decode_ber"] == error_probability
                    and result["iterations"] == iterations
                )
            ]

            post_decode_values = [
                result["post_decode_ber"]
                for result in matching_results
            ]
            mean_post_decode_ber.append(
                max(statistics.mean(post_decode_values), plot_floor)
            )

        axis.plot(
            ERROR_PROBABILITIES,
            mean_post_decode_ber,
            label=f"{iterations} iteration(s)",
        )

    axis.set_title("Python Reference Product Decoder Random-Error Performance")
    axis.set_xlabel("Configured pre-decoding BER (p)")
    axis.set_ylabel("Mean post-decoding BER")
    axis.set_xscale("linear")
    axis.set_yscale("log")
    axis.grid(True, which="both", alpha=0.5)
    axis.legend()

    figure.tight_layout()
    figure.savefig(plot_path, dpi=200)
    plt.close(figure)

    print(f"Saved BER plot to: {plot_path}")


def main():
    results = run_experiment()
    write_results_csv(results)
    plot_post_decode_ber(results)


if __name__ == "__main__":
    main()
