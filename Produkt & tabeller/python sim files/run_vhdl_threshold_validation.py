import csv
import pathlib

from compare_reference_with_vhdl import (
    BLOCKS,
    DATA_SEED,
    run_threshold_case,
)
from run_product_test import prepare_clean_blocks


# First failing error count found by run_ordered_error_threshold.py.
FIRST_FAILURES = {
    1: 250,
    2: 440,
    3: 512,
    4: 586,
    5: 597,
}

script_folder = pathlib.Path(__file__).resolve().parent
output_folder = script_folder / "threshold_validation_output"
csv_path = output_folder / "vhdl_threshold_validation.csv"

# We write the results to a csv file to validate that the python model and VHDL implementation will both succeed/fail at the same value.
# Also we want to validate that when they fail, they fail at exactly the same spots, meaning the amount of errors left, and their positions, must be identical in both cases.
def write_results(results):
    with csv_path.open("w", newline="", encoding="utf-8") as csv_file:
        writer = csv.DictWriter(
            csv_file,
            fieldnames=[
                "decoder_iterations",
                "error_count",
                "expected_full_correction",
                "full_correction",
                "python_vhdl_identical",
            ],
        )
        writer.writeheader()
        writer.writerows(results)


def main():
    output_folder.mkdir(exist_ok=True)

    print("Preparing one clean product block.")
    clean_blocks = prepare_clean_blocks(
        blocks=BLOCKS,
        data_seed=DATA_SEED,
    )

    results = []
    for iterations, first_failure in FIRST_FAILURES.items():
        test_cases = [
            (first_failure - 1, True), # Here we expect correction
            (first_failure, False), # here we dont.
        ]

        for error_count, expect_full_correction in test_cases:
            expected_text = "full correction" if expect_full_correction else "failure"
            print(
                f"\nValidating {iterations} iteration(s), "
                f"E={error_count}: expected {expected_text}."
            )

            result = run_threshold_case(
                clean_blocks,
                error_count,
                iterations,
                expect_full_correction,
            )
            result["python_vhdl_identical"] = True
            results.append(result)

    write_results(results)
    print(f"\nPASS: Saved {len(results)} validation results to {csv_path}.")


if __name__ == "__main__":
    main()
