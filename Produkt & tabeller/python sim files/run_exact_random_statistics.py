import csv
import pathlib
import statistics

import matplotlib.pyplot as plt

from run_product_test import (
    prepare_clean_blocks,
    run_decoder_test,
)


BLOCKS_PER_TEST = 1
DATA_SEED = 42
BASE_NOISE_SEED = 1000 # Seeds are shared across iteration counts for the same error count and trial.

ERROR_COUNTS = [0, 100, 200, 300, 400, 500, 750, 1000]
ITERATION_COUNTS = [1, 2, 3, 4, 5]

TRIALS_PER_POINT = 1 # only try once pr. parameter set.


script_folder = pathlib.Path(__file__).resolve().parent
output_folder = script_folder / "statistics_output"
csv_path = output_folder / "exact_random_results.csv" # change this for different experiments, so the same file is not overwritten.
success_plot_path = output_folder / "exact_random_success_rate.png"
bit_error_plot_path = output_folder / "exact_random_remaining_bits.png"


# Run 1 experiment and return 1 dictionary for each simulation.
def run_experiment():
    output_folder.mkdir(exist_ok=True)

    print("Preparing clean encoder output.")
    clean_blocks = prepare_clean_blocks( # # Prepare BLOCKS_PER_TEST clean blocks once and reuse them for every simulation.
        blocks=BLOCKS_PER_TEST,
        data_seed=DATA_SEED,
        verbose=True,
    )
    # Note that "results" is a list, and "result" is a dictionary.
    # We use a list, because the experiment result is going to be written to a CSV file at the end.
    results = [] 

    for error_index, error_count in enumerate(ERROR_COUNTS):
        for trial_index in range(TRIALS_PER_POINT):
            noise_seed = (
                BASE_NOISE_SEED
                + (error_index * TRIALS_PER_POINT)
                + trial_index
            )

            for iterations in ITERATION_COUNTS:
                print(
                    f"Testing {error_count} errors, "
                    f"{iterations} iteration(s), "
                    f"trial {trial_index + 1}/{TRIALS_PER_POINT}."
                )

                result = run_decoder_test(
                    clean_blocks,
                    error_model="exact_random",
                    decoder_iterations=iterations,
                    noise_seed=noise_seed,
                    error_count=error_count,
                    verbose=False,
                )
                # This is one result entry in the list.
                result_row = {
                    "error_count": error_count,
                    "iterations": iterations,
                    "trial": trial_index + 1,
                    "noise_seed": noise_seed,
                }

                result_row.update(result)
                results.append(result_row)

    return results

# This will write the result of each simulation of an experiment into a csv file.
def write_results_csv(results):
    fieldnames = [
        "error_count",
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

    with open(csv_path, "w", newline="", encoding="utf-8") as csv_file:
        writer = csv.DictWriter(csv_file, fieldnames=fieldnames) # CSV library is lovely :)
        writer.writeheader()
        writer.writerows(results)
    print(f"Saved raw results to: {csv_path}")


# This function will plot the mean amount of bit errors after decoding as a function of initial bit errors.
# In the report this is often called post-FEC errors.
def plot_remaining_bit_errors(results):
    figure, axis = plt.subplots(figsize=(9, 5))

    for iterations in ITERATION_COUNTS:
        mean_remaining_bits = []

        for error_count in ERROR_COUNTS:
            matching_results = [
                result
                for result in results
                if (
                    result["error_count"] == error_count
                    and result["iterations"] == iterations
                )
            ]

            bit_values = [
                result["incorrect_bits"]
                for result in matching_results
                if result["incorrect_bits"] is not None
            ]

            if bit_values:
                mean_remaining_bits.append(statistics.mean(bit_values))
            else:
                mean_remaining_bits.append(float("nan"))

        axis.plot(
            ERROR_COUNTS,
            mean_remaining_bits,
            marker="o",
            label=f"{iterations} iteration(s)",
        )

    axis.set_title("Remaining Bit Errors After Product Decoding")
    axis.set_xlabel("Inserted errors per product block")
    axis.set_ylabel("Mean remaining incorrect bits")
    axis.grid(True)
    axis.legend()

    figure.tight_layout()
    figure.savefig(bit_error_plot_path, dpi=200)
    plt.close(figure)

    print(f"Saved bit-error plot to: {bit_error_plot_path}")


def main():
    results = run_experiment()
    write_results_csv(results)
    plot_remaining_bit_errors(results)


if __name__ == "__main__":
    main()