import pathlib

import matplotlib.pyplot as plt

from add_product_errors import (
    CODEWORD_BITS,
    add_ordered_errors,
    create_error_order,
)
from product_decoder_reference import decode_product_blocks
from run_product_test import prepare_clean_blocks


BLOCKS = 1
DATA_SEED = 42
NOISE_SEED = 1000

ITERATION_COUNTS = [1, 2, 3, 4, 5]

ERROR_COUNTS = list(range(0, 801))

script_folder = pathlib.Path(__file__).resolve().parent
output_folder = script_folder / "threshold_output"
plot_path = output_folder / "ordered_error_threshold_counts.png"

# Create one fixed ordered error profile for each product block.
def create_block_error_orders(block_count):
    return [
        create_error_order(NOISE_SEED + block_index)
        for block_index in range(block_count)
    ]


# Create noisy blocks by flipping the first error_count bits from each block's fixed error profile.
# It is important that the amount of errors is the only change, and not the ordering if this number changes.
# So 20 errors and 21 errors are only different in the next position in the order, while the initial 20 are identical.
def make_ordered_noisy_blocks(
    clean_blocks,
    error_orders,
    error_count,
):
    noisy_blocks = []
    total_inserted_errors = 0

    for clean_block, error_order in zip(
        clean_blocks,
        error_orders,
    ):
        noisy_block, inserted_errors = add_ordered_errors(
            clean_block,
            error_order,
            error_count,
        )

        noisy_blocks.append(noisy_block)
        total_inserted_errors += inserted_errors

    return noisy_blocks, total_inserted_errors

# Count the bit positions that still differ from the clean blocks.
# The function returns the amount of bits that differ, NOT amount of codewords.
def count_remaining_bit_errors(clean_blocks, decoded_blocks):
    remaining_bit_errors = 0

    for clean_block, decoded_block in zip(
        clean_blocks,
        decoded_blocks,
    ):
        for clean_codeword, decoded_codeword in zip(
            clean_block,
            decoded_block,
        ):
            remaining_bit_errors += sum(
                clean_bit != decoded_bit
                for clean_bit, decoded_bit in zip(
                    clean_codeword,
                    decoded_codeword,
                )
            )

    return remaining_bit_errors

# Run the adaptive ordered-error experiment with the Python reference decoder.
# This will try to decode blocks with different amount of iterations, and when it succeeds for a specific iteration count the first time
# it will break and up the amount of errors.
# Again it uses the error_orders so higher amounts of errors doesn't change the overall pattern of errors, so we have the same baseline to compare to.
def run_adaptive_experiment(clean_blocks, error_orders):
    results = []
    total_bits = len(clean_blocks) * CODEWORD_BITS * CODEWORD_BITS

    for error_count in ERROR_COUNTS:
        noisy_blocks, total_inserted_errors = make_ordered_noisy_blocks(
            clean_blocks,
            error_orders,
            error_count,
        )

        for iterations in ITERATION_COUNTS:
            decoded_blocks = decode_product_blocks(
                noisy_blocks,
                iterations,
            )

            remaining_bit_errors = count_remaining_bit_errors(
                clean_blocks,
                decoded_blocks,
            )

            # Store post-decode BER as well, so these results can later be reused for a classical BER plot if needed (first version did this).
            post_decode_ber = remaining_bit_errors / total_bits
            results.append(
                {
                    "error_count": error_count,
                    "pre_decode_ber": total_inserted_errors / total_bits,
                    "iterations": iterations,
                    "remaining_bit_errors": remaining_bit_errors,
                    "post_decode_ber": post_decode_ber,
                }
            )

            print(
                f"{error_count} inserted errors, "
                f"{iterations} iteration(s): "
                f"{remaining_bit_errors} remaining bit errors."
            )
            # The loop will break if a lower amount of iterations managed to correct all errors
            # Otherwise, we would just be wasting time, and we would have overlapping "iteration" lines in the resulting graph.
            if remaining_bit_errors == 0:
                break

    return results

# Print the first observed decoding-failure threshold for each iteration count.
def print_error_thresholds(results):
    bits_per_block = CODEWORD_BITS * CODEWORD_BITS

    for iterations in ITERATION_COUNTS:
        iteration_results = [
            result
            for result in results
            if result["iterations"] == iterations
        ]

        first_failure = next(
            (
                result
                for result in iteration_results
                if result["remaining_bit_errors"] > 0
            ),
            None,
        )

        if first_failure is None:
            print(
                f"{iterations} iteration(s): "
                "no decoding failure within the tested range."
            )
            continue

        threshold_errors = first_failure["error_count"] - 1
        threshold_ber = threshold_errors / bits_per_block

        print(
            f"{iterations} iteration(s): "
            f"full correction through {threshold_errors} errors "
            f"(BER {threshold_ber:.6f}); "
            f"first failure at {first_failure['error_count']} errors."
        )




# Plot remaining bit errors against inserted errors.
def plot_ordered_error_threshold(results):
    output_folder.mkdir(exist_ok=True)

    figure, axis = plt.subplots(figsize=(10, 6))

    annotation_offsets = {
            1: (0, 18),
            2: (0, 18),
            3: (-30, 35),
            4: (-75, 60),
            5: (55, 85),
        }

    for iterations in ITERATION_COUNTS:
        iteration_results = [
            result
            for result in results
            if result["iterations"] == iterations
        ]

        if not iteration_results:
            continue

        x_values = [
            result["error_count"]
            for result in iteration_results
        ]
        y_values = [
            result["remaining_bit_errors"]
            for result in iteration_results
        ]

        line, = axis.plot(
            x_values,
            y_values,
            linewidth=2,
            label=f"{iterations} iteration(s)",
        )

        first_failure = next(
            (
                result
                for result in iteration_results
                if result["remaining_bit_errors"] > 0
            ),
            None,
        )
        # Add the first failure point for each iteration count.
        if first_failure is not None:
            failure_error_count = first_failure["error_count"]
            failure_remaining_errors = (
                first_failure["remaining_bit_errors"]
            )

            axis.scatter(
                failure_error_count,
                failure_remaining_errors,
                color=line.get_color(),
                edgecolors="white",
                linewidths=0.8,
                s=60,
                zorder=3,
            )

            axis.annotate(
                f"E={failure_error_count}",
                xy=(
                    failure_error_count,
                    failure_remaining_errors,
                ),
                xytext=annotation_offsets[iterations],
                textcoords="offset points",
                ha="center",
                va="bottom",
                color=line.get_color(),
                arrowprops={
                    "arrowstyle": "-",
                    "color": line.get_color(),
                },
                bbox={
                    "boxstyle": "round,pad=0.2",
                    "facecolor": "white",
                    "edgecolor": "none",
                    "alpha": 0.85,
                },
            )

    axis.set_title("Ordered-Error Product Decoder Threshold")
    axis.set_xlabel("Inserted errors per product block")
    axis.set_ylabel("Remaining bit errors after decoding")
    axis.set_xlim(left=0)
    axis.set_ylim(bottom=0)
    axis.grid(True, alpha=0.5)
    axis.legend()

    figure.tight_layout()
    figure.savefig(plot_path, dpi=200)
    plt.close(figure)

    print(f"Saved threshold plot to: {plot_path}")

def main():
    # Make input data 
    print("Preparing one clean product block.")
    clean_blocks = prepare_clean_blocks(
        blocks=BLOCKS,
        data_seed=DATA_SEED,
    )
    # Create the error orders for each block.
    error_orders = create_block_error_orders(
        len(clean_blocks),
    )
    # Run the experiment and get data
    results = run_adaptive_experiment(
        clean_blocks,
        error_orders,
    )
    # Print the threshold values for this seed.
    # This only makes sense if the step size is 1.
    print_error_thresholds(results)

    # Plot the data.
    plot_ordered_error_threshold(results)


if __name__ == "__main__":
    main()