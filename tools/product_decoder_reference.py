from add_product_errors import CODEWORD_BITS, flip_bit, ROWS_PER_BLOCK, COLUMNS_PER_BLOCK


FIELD_SIZE = 256
FIELD_ORDER = FIELD_SIZE - 1
PRIMITIVE_REDUCTION = 0x1D


# Multiply one GF(256) element by alpha.
# This uses the same primitive polynomial, 0x11D, as the VHDL decoder.
def multiply_by_alpha(value):
    if not 0 <= value < FIELD_SIZE:
        raise ValueError("A GF(256) element must be between 0 and 255.")

    shifted_value = (value << 1) & 0xFF

    if value & 0x80:
        shifted_value ^= PRIMITIVE_REDUCTION

    return shifted_value


# Build alpha^i and log_alpha lookup tables once when this module is imported.
def build_field_tables():
    alpha_to = [0] * FIELD_ORDER
    log_alpha = [-1] * FIELD_SIZE

    value = 1

    for exponent in range(FIELD_ORDER):
        alpha_to[exponent] = value
        log_alpha[value] = exponent
        value = multiply_by_alpha(value)

    return alpha_to, log_alpha


ALPHA_TO_ELEMENT, ELEMENT_TO_LOG = build_field_tables()

# Calculate the two BCH syndromes and the overall parity of one received codeword.
def calculate_syndromes(codeword):
    if len(codeword) != CODEWORD_BITS:
        raise ValueError("A BCH codeword must contain exactly 256 bits.")
    if any(bit not in "01" for bit in codeword):
        raise ValueError("A BCH codeword may only contain '0' and '1'.")

    parity = 0
    syndrome_1 = 0
    syndrome_3 = 0

    for vhdl_bit_index in range(CODEWORD_BITS):
        string_index = CODEWORD_BITS - 1 - vhdl_bit_index # this is to make sure the order of reading is the same as the VHDL-vector convention.

        # if the bit is 1, we XOR it to the overall parity (if it is zero it has no effect)
        if codeword[string_index] == "1":
            parity ^= 1
            # Furthermore, if it is not the initial bit (the overall parity bit)
            # it should be XORed into the syndromes
            if vhdl_bit_index != 0:
                exponent = vhdl_bit_index - 1 # the convention is data_in(1)=alpha^0 (the first index is the overall parity)

                # XOR the element into both syndromes
                syndrome_1 ^= ALPHA_TO_ELEMENT[exponent]
                syndrome_3 ^= ALPHA_TO_ELEMENT[
                    (3 * exponent) % FIELD_ORDER # Exponents are reduced modulo 255, because alpha^255 = alpha^0 (cyclic code).
                ]

    return parity, syndrome_1, syndrome_3

NO_ERRORS = "no_errors"
ONE_ERROR = "one_error"
TWO_ERRORS = "two_errors"

# Calculate S1^3 using the logarithm representation of a GF(256) element.
def cube_field_element(element):
    if element == 0:
        return 0
    exponent = ELEMENT_TO_LOG[element]
    return ALPHA_TO_ELEMENT[(3 * exponent) % FIELD_ORDER]


# Classify the received BCH part in the same way as the VHDL decoder.
# This function cannot distinguish two actual errors from more complex error paterns
# instead it should be interpreted as:
# "what BCH-correction rule is the decoder pipeline using"
# and not:
# "how many actual channel errors do we with certainty know there are".
def classify_bch_pattern(syndrome_1, syndrome_3):
    if syndrome_1 == 0 and syndrome_3 == 0:
        return NO_ERRORS

    if cube_field_element(syndrome_1) == syndrome_3:
        return ONE_ERROR

    return TWO_ERRORS

ERRORS_FOUND_NONE = "00"
ERRORS_FOUND_ONE = "01"
ERRORS_FOUND_TWO = "10"
ERRORS_FOUND_INVALID = "11"


# Combine the BCH candidate pattern and parity into the same two-bit
# errors_found value produced by the VHDL component decoder.
# This status does not prove the actual number of channel errors.
def determine_errors_found(bch_pattern, parity):
    if parity not in (0, 1):
        raise ValueError("Parity must be either 0 or 1.")

    if bch_pattern == NO_ERRORS and parity == 0:
        return ERRORS_FOUND_NONE

    if (
        (bch_pattern == NO_ERRORS and parity == 1)
        or (bch_pattern == ONE_ERROR and parity == 1)
    ):
        return ERRORS_FOUND_ONE

    if (
        (bch_pattern == ONE_ERROR and parity == 0)
        or (bch_pattern == TWO_ERRORS and parity == 0)
    ):
        return ERRORS_FOUND_TWO

    return ERRORS_FOUND_INVALID

# Flip one bit using VHDL vector numbering rather than text-string numbering.
def flip_vhdl_bit(codeword, vhdl_bit_index):
    if not 0 <= vhdl_bit_index < CODEWORD_BITS: # is vhdl_bit_index less than 0 or higher than 255.
        raise ValueError("The VHDL bit index must be between 0 and 255.")

    string_index = CODEWORD_BITS - 1 - vhdl_bit_index
    return flip_bit(codeword, string_index)

# Correct codewords that the BCH logic classifies as zero or one BCH error.
def correct_zero_or_one_bch_error(
    codeword,
    bch_pattern,
    parity,
    syndrome_1,
):
    if bch_pattern == NO_ERRORS:
        if parity == 1:
            return flip_vhdl_bit(codeword, 0) # this means that the parity bit is errorneous, and nothing else is.

        return codeword

    if bch_pattern != ONE_ERROR:
        raise ValueError(
            "This function only handles no_errors and one_error patterns."
        )

    bch_bit_index = ELEMENT_TO_LOG[syndrome_1] + 1 # add 1, since index 0 is overall parity, which is handled above.
    corrected_codeword = flip_vhdl_bit(codeword, bch_bit_index)

    if parity == 0:
        corrected_codeword = flip_vhdl_bit(corrected_codeword, 0) # This means that there is 1 error in the BCH part, AND the parity bit is wrong.

    return corrected_codeword

# Multiply two ordinary GF(256) elements using logarithm tables.
def multiply_field_elements(first_element, second_element):
    if not 0 <= first_element < FIELD_SIZE:
        raise ValueError("The first GF(256) element must be between 0 and 255.")
    if not 0 <= second_element < FIELD_SIZE:
        raise ValueError("The second GF(256) element must be between 0 and 255.")

    if first_element == 0 or second_element == 0:
        return 0

    # Multiplication in the log domain consists of adding exponents, modulo 255.
    # It is used for the 2-error case.
    product_exponent = (
        ELEMENT_TO_LOG[first_element]
        + ELEMENT_TO_LOG[second_element]
    ) % FIELD_ORDER

    return ALPHA_TO_ELEMENT[product_exponent] # Returns 8-bit rep of the resulting field element

# Divide two GF(256) elements using logarithm tables.
def divide_field_elements(numerator, denominator):
    if not 0 <= numerator < FIELD_SIZE:
        raise ValueError("The numerator must be between 0 and 255.")
    if not 0 <= denominator < FIELD_SIZE:
        raise ValueError("The denominator must be between 0 and 255.")
    if denominator == 0:
        raise ZeroDivisionError("Division by zero is undefined in GF(256).")

    if numerator == 0:
        return 0
    # Division in the log domain consists of subtracting exponents, modulo 255.
    # It is also used for the 2-error case.
    quotient_exponent = (
        ELEMENT_TO_LOG[numerator]
        - ELEMENT_TO_LOG[denominator]
    ) % FIELD_ORDER

    return ALPHA_TO_ELEMENT[quotient_exponent] # Returns 8-bit rep of the resulting field element


# Build a lookup table for the roots of z^2 + z + A = 0.
# Each entry maps log(A) to the logarithms of the two roots.
def build_root_log_table():
    root_logs_by_log_a = [None] * FIELD_SIZE

    # Match the unused VHDL LUT entry at address 255.
    root_logs_by_log_a[255] = (0, 0)

    for root_log in range(FIELD_ORDER):
        root = ALPHA_TO_ELEMENT[root_log]
        root_square = ALPHA_TO_ELEMENT[(2 * root_log) % FIELD_ORDER]

        # We simply try every field element until the equation is true (we've found a root)
        normalized_a = root_square ^ root
        if normalized_a == 0: 
            continue

        log_a = ELEMENT_TO_LOG[normalized_a]
        # Remember that if z is a root, then z+1 is the other root in our field.
        companion_root = root ^ 1
        companion_root_log = ELEMENT_TO_LOG[companion_root]

        # Since there are 2 roots, we will find z+1 after z
        # so we should not overwrite the initial value/pair of z and z+1, as that would create the same pair in the opposite order.
        if root_logs_by_log_a[log_a] is None:
            root_logs_by_log_a[log_a] = (
                root_log,
                companion_root_log,
            )

    return root_logs_by_log_a

ROOT_LOGS_BY_LOG_A = build_root_log_table()

 # Match the VHDL logarithm LUT, including its default value for element zero.
def vhdl_element_to_log(element):
    if element == 0:
        return 0
    return ELEMENT_TO_LOG[element]


# Find the two candidate BCH error locations as alpha exponents.
# We reuse the convention from the Decoder:
#   X = alpha^i
#   Y = alpha^j
#   S1 = X+Y
#   S3 = X^3+Y^3
#   S1^3+S3 = X*Y*S1 => X*Y = (S1^3+S3) / S1
#   z1 = X/S1
#   z2 = Y/S1
def find_two_error_location_logs(syndrome_1, syndrome_3):
    log_syndrome_1 = vhdl_element_to_log(syndrome_1)

    # Find S1^3+S3
    difference = cube_field_element(syndrome_1) ^ syndrome_3
    log_difference = vhdl_element_to_log(difference)
    # Find log(X*Y)
    log_xy = (
        log_difference
        - log_syndrome_1
    ) % FIELD_ORDER
    # Find log(S1^2) = 2 *log(S1)
    log_syndrome_1_squared = (
        2 * log_syndrome_1
    ) % FIELD_ORDER
    # Find log(A) = log(XY) - log(S1^2)
    log_a = (
        log_xy
        - log_syndrome_1_squared
    ) % FIELD_ORDER

    # Get the positions from the log value of A.
    root_logs = ROOT_LOGS_BY_LOG_A[log_a]

    if root_logs is None:
        return None

    first_root_log, second_root_log = root_logs

    # X = z1*S1
    first_location_log = (
        first_root_log
        + log_syndrome_1
    ) % FIELD_ORDER
    # Y = z2*S1
    second_location_log = (
        second_root_log
        + log_syndrome_1
    ) % FIELD_ORDER

# returns the locations at indexes - 1, meaning that (17,203) indicates errors at BCH-bit 18 and 204, since the overall parity bit is not handled by the code.
    return first_location_log, second_location_log 

# Correct a codeword using the VHDL two-BCH-error correction rule.
def correct_two_bch_error_pattern(
    codeword,
    parity,
    syndrome_1,
    syndrome_3,
):
    if parity == 1: # VHDL only applies the two-BCH-error correction rule for even parity.
        return codeword

    location_logs = find_two_error_location_logs(
        syndrome_1,
        syndrome_3,
    )

    if location_logs is None:
        return codeword

    first_location_log, second_location_log = location_logs

    corrected_codeword = flip_vhdl_bit(
        codeword,
        first_location_log + 1,
    )
    corrected_codeword = flip_vhdl_bit(
        corrected_codeword,
        second_location_log + 1,
    )
    # A returned log i maps to bch bit i+1
    # VHDL bit 0 is the separate overall parity bit.
    return corrected_codeword

# Final "component" decoder function. This takes a codeword in, and corrects it if it has errors.
# Return both the corrected codeword and the VHDL errors_found status.
def decode_component_codeword(codeword):
    parity, syndrome_1, syndrome_3 = calculate_syndromes(codeword)

    bch_pattern = classify_bch_pattern(
        syndrome_1,
        syndrome_3,
    )

    errors_found = determine_errors_found(
        bch_pattern,
        parity,
    )

    if bch_pattern in (NO_ERRORS, ONE_ERROR):
        corrected_codeword = correct_zero_or_one_bch_error(
            codeword,
            bch_pattern,
            parity,
            syndrome_1,
        )
    else:
        corrected_codeword = correct_two_bch_error_pattern(
            codeword,
            parity,
            syndrome_1,
            syndrome_3,
        )

    return corrected_codeword, errors_found

# Transpose a 256x256 product-code block.
# The Python reference runs sequentially, so the returned matrix can simply
# replace the previous one. The VHDL implementation needs separate buffers
# because several pipeline stages may process different blocks at the same time.
# Garbage collector is lovely ;)
def transpose_product_block(product_block):
    if len(product_block) != COLUMNS_PER_BLOCK:
        raise ValueError("A product block must contain exactly 256 codewords.")

    for codeword in product_block:
        if len(codeword) != CODEWORD_BITS:
            raise ValueError(
                "Every product-codeword must contain exactly 256 bits."
            )

    return [
        "".join(
            product_block[column_index][row_index]
            for column_index in range(COLUMNS_PER_BLOCK)
        )
        for row_index in range(ROWS_PER_BLOCK)
    ]

# Decode one 256x256 product-code block sequentially.
# The input and returned block both use the external column-stream convention.
# Internally, each iteration ends with decoded rows.
# The final transpose matches the VHDL output stage, which streams columns.
def decode_product_block(product_block, iterations):
    if not isinstance(iterations, int) or iterations < 1:
        raise ValueError("Iterations must be a positive integer.")

    column_codewords = product_block
    # Here it will transpose on every pass (2 passes pr. iteration)
    for iteration_index in range(iterations):
        decoded_columns = []

        for column_codeword in column_codewords:
            decoded_codeword, _ = decode_component_codeword(
                column_codeword,
            )
            decoded_columns.append(decoded_codeword)

        row_codewords = transpose_product_block(decoded_columns)

        decoded_rows = []

        for row_codeword in row_codewords:
            decoded_codeword, _ = decode_component_codeword(
                row_codeword,
            )
            decoded_rows.append(decoded_codeword)

        if iteration_index < iterations - 1: # There are still iterations left.
            column_codewords = transpose_product_block(decoded_rows)

   # The final pass will be a row-pass, but we must output columns to match the VHDL process
   # where the final output is always columns, as this output is (most of the time) the input to the next stage.
    return transpose_product_block(decoded_rows)


# Decode several product blocks with one selected number of iterations.
# Mainly just a wrapper so we can use it for simulations with multiple blocks.
def decode_product_blocks(product_blocks, iterations):
    decoded_blocks = []

    for product_block in product_blocks:
        decoded_block = decode_product_block(
            product_block,
            iterations=iterations,
        )
        decoded_blocks.append(decoded_block)

    return decoded_blocks
