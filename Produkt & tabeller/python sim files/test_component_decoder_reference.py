from product_decoder_reference import (
    decode_component_codeword,
    decode_product_block,
    flip_vhdl_bit,
)


def add_vhdl_bit_errors(codeword, bit_indices):
    noisy_codeword = codeword

    for bit_index in bit_indices:
        noisy_codeword = flip_vhdl_bit(
            noisy_codeword,
            bit_index,
        )

    return noisy_codeword


def run_component_sanity_checks():
    clean_codeword = "0" * 256

    test_cases = [
        ((), "00"),
        ((0,), "01"),
        ((17,), "01"),
        ((0, 17), "10"),
        ((17, 203), "10"),
    ]

    for bit_indices, expected_status in test_cases:
        noisy_codeword = add_vhdl_bit_errors(
            clean_codeword,
            bit_indices,
        )

        decoded_codeword, errors_found = decode_component_codeword(
            noisy_codeword,
        )

        if decoded_codeword != clean_codeword:
            raise AssertionError(
                f"Failed to correct errors at VHDL bits {bit_indices}."
            )

        if errors_found != expected_status:
            raise AssertionError(
                f"Expected status {expected_status}, "
                f"got {errors_found} for {bit_indices}."
            )

    print("PASS: Component decoder reference sanity checks passed.")

def run_product_sanity_checks():
    clean_codeword = "0" * 256
    clean_product_block = [clean_codeword] * 256
    noisy_product_block = clean_product_block.copy()

    # Three errors in one input column cannot be corrected by the component decoder's first column pass.
    # but the product decoder should correct it.
    for vhdl_bit_index in (17, 99, 203):
        noisy_product_block[42] = flip_vhdl_bit(
            noisy_product_block[42],
            vhdl_bit_index,
        )

    decoded_product_block = decode_product_block(
        noisy_product_block,
        iterations=1,
    )

    if decoded_product_block != clean_product_block:
        raise AssertionError(
            "The product decoder reference failed to correct "
            "three errors in one column."
        )

    print("PASS: Product decoder reference sanity checks passed.")


if __name__ == "__main__":
    run_component_sanity_checks()
    run_product_sanity_checks()