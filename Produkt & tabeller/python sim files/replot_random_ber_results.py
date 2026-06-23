import csv
import pathlib
import statistics

import matplotlib.pyplot as plt


# This script simply replots the results from the 2 performacne experiments of the VHDL and Python reference models respectively.
# Because the VHDL experiment took about 5 hours to complete, and the Python reference model took over 1 hour to finish,
# redoing the experiments was not an option, when all we wanted to do was change the way the results were plotted.
# Therefore this script simply reads the 2 result CSV files and replots them.

# The resultin graph will have each iteration count "line" be "born" at the first pre-FEC BER that it can no longer fully correct all errors.
# A point is set along a mutual floor value here for all iteration counts, and then the actual data points will start at different heights from their respective points.
# It makes the 2 graphs look a lot more like the verification graph, and overall look more slick.

script_folder = pathlib.Path(__file__).resolve().parent
output_folder = script_folder / "statistics_output"
PRODUCT_BLOCK_BITS = 256 * 256

PLOTS = [
    {
        "csv_name": "python_reference_random_ber_results.csv",
        "plot_name": "python_reference_random_ber_no_floor.png",
        "title": "Python Reference Product Decoder Random-Error Performance",
    },
    {
        "csv_name": "vhdl_random_ber_results.csv",
        "plot_name": "vhdl_random_ber_no_floor.png",
        "title": "VHDL Product Decoder Random-Error Performance",
    },
]

# Read every line of the CSV file and create a dictionary containing the 3 values that the plot needs.
def read_results(csv_path):
    results = []

    with csv_path.open(newline="", encoding="utf-8") as csv_file:
        for row in csv.DictReader(csv_file):
            results.append(
                {
                    "configured_pre_decode_ber": float(
                        row["configured_pre_decode_ber"]
                    ),
                    "post_decode_ber": float(row["post_decode_ber"]),
                    "iterations": int(row["iterations"]),
                    "blocks": int(row["blocks"]),
                }
            )

    return results

# Plot one mean post-decoding BER curve per iteration and mark each iteration's first non-zero BER as a separate threshold point.
def plot_results(results, plot_path, title):
    error_probabilities = sorted(
        {result["configured_pre_decode_ber"] for result in results}
    )
    iteration_counts = sorted({result["iterations"] for result in results})

    figure, axis = plt.subplots(figsize=(9, 5))

    for iterations in iteration_counts:
        plot_probabilities = []
        plot_post_decode_ber = []
        threshold_probability = None
        threshold_floor = None

        for error_probability in error_probabilities:
            matching_results = [
                result
                for result in results
                if (
                    result["configured_pre_decode_ber"] == error_probability
                    and result["iterations"] == iterations
                )
            ]
            mean_ber = statistics.mean(
                result["post_decode_ber"]
                for result in matching_results
            )

            if mean_ber == 0:
                continue

            if threshold_probability is None:
                total_bits = sum(
                    result["blocks"] * PRODUCT_BLOCK_BITS
                    for result in matching_results
                )
                threshold_probability = error_probability
                threshold_floor = 0.5 / total_bits

            plot_probabilities.append(error_probability)
            plot_post_decode_ber.append(mean_ber)

        line, = axis.plot(
            plot_probabilities,
            plot_post_decode_ber,
            label=f"{iterations} iteration(s)",
        )

        # Mark the first non-zero BER at a common visual floor WITHOUT connecting the marker to the measured BER curve.
        # The first version connected these, and made for some horribly misleading graphs.
        axis.scatter(
            threshold_probability,
            threshold_floor,
            color=line.get_color(),
            s=24,
            zorder=3,
        )

    axis.set_title(title)
    axis.set_xlabel("Configured pre-decoding BER (p)")
    axis.set_ylabel("Mean post-decoding BER")
    axis.set_yscale("log")
    axis.grid(True, which="both", alpha=0.5)
    axis.legend()

    figure.tight_layout()
    figure.savefig(plot_path, dpi=200)
    plt.close(figure)

    print(f"Saved plot to: {plot_path}")


def main():
    for plot_config in PLOTS:
        csv_path = output_folder / plot_config["csv_name"]
        plot_path = output_folder / plot_config["plot_name"]
        results = read_results(csv_path)
        plot_results(results, plot_path, plot_config["title"])


if __name__ == "__main__":
    main()
