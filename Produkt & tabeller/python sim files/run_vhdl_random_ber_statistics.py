import csv
import pathlib
import statistics

import matplotlib.pyplot as plt

from add_product_errors import CODEWORD_BITS
from run_product_test import (
    prepare_clean_blocks,
    run_decoder_test,
)


# Each VHDL data point decodes several product blocks in one simulation.
# A shared seeded random generator creates a different reproducible noise pattern for each block, reducing the required number of ModelSim runs.
BLOCKS_PER_TEST = 5
DATA_SEED = 42
BASE_NOISE_SEED = 1000
TRIALS_PER_POINT = 1

# x-axis (pre-decoding BER)
ERROR_PROBABILITIES = [
    0.000,
    0.001,
    0.002,
    0.003,
    0.0035,
    0.0040,
    0.0045,
    0.0050,
    0.0055,
    0.0060,
    0.0065,
    0.0070,
    0.0075,
    0.0080,
    0.0085,
    0.0090,
    0.0095,
    0.0100,
    0.0105,
    0.0110,
    0.0120,
]
ITERATION_COUNTS = [1, 2, 3, 4, 5]


script_folder = pathlib.Path(__file__).resolve().parent
output_folder = script_folder / "statistics_output"
csv_path = output_folder / "vhdl_random_ber_results.csv"
plot_path = output_folder / "vhdl_random_ber.png" # change this value for different experiments to not overwrite existing graph.


# Central function.
def run_experiment():
    output_folder.mkdir(exist_ok=True)

    print("Preparing clean encoder output.")
    # Use the function from the run_product_test.py file
    # Remember that this function creates 5 239x239 input data matrices, encodes them and then returns BLOCKS_PER_TEST 256x256 encoded product blocks.
    clean_blocks = prepare_clean_blocks(
        blocks=BLOCKS_PER_TEST,
        data_seed=DATA_SEED,
        verbose=True,
    )
    total_bits = len(clean_blocks) * CODEWORD_BITS * CODEWORD_BITS
    results = []

    for error_probability in ERROR_PROBABILITIES:
        for trial_index in range(TRIALS_PER_POINT):
            # Each BER has five different product blocks and five different error patterns.
            # For one trial, the same patterns are created for every probability and iteration count.
            # Therefore, increasing p can only add errors to each block, but not change the overall pattern.
            # This still is an uncertainty in the model, because a singluar error can be the difference in the iterative behavior of a product decoder
            # but it still minimises the effect that other parameters have on a simulation, other than iteration count.
            noise_seed = BASE_NOISE_SEED + trial_index # trial_index is added here, so we can change the amount of trials that should be run for each BER, resulting in unique error seeds for each trial.

            for iterations in ITERATION_COUNTS:
                print(
                    f"Testing p={error_probability:.3f}, "
                    f"{iterations} iteration(s), "
                    f"trial {trial_index + 1}/{TRIALS_PER_POINT}."
                )

                result = run_decoder_test(
                    clean_blocks,
                    error_model="random_probability",
                    decoder_iterations=iterations,
                    noise_seed=noise_seed,
                    error_probability=error_probability,
                    verbose=False,
                )

                result_row = {
                    "configured_pre_decode_ber": error_probability,
                    "observed_pre_decode_ber": result["inserted_errors"] / total_bits,
                    "post_decode_ber": result["incorrect_bits"] / total_bits,
                    "iterations": iterations,
                    "trial": trial_index + 1,
                    "noise_seed": noise_seed,
                }
                result_row.update(result)
                results.append(result_row)

    return results # Returns a list of result dictionaries.


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
    total_bits = BLOCKS_PER_TEST * CODEWORD_BITS * CODEWORD_BITS
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

    axis.set_title("VHDL Product Decoder Random-Error Performance")
    axis.set_xlabel("Configured pre-decoding BER (p)")
    axis.set_ylabel("Mean post-decoding BER")
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
