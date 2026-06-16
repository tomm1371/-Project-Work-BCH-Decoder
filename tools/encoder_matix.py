def lfsr_remainder(data_bits, genpoly=0b0110111101100011, n_parity=16):
    """
    data_bits fed MSB first (index 0 = MSB of message),
    followed by 16 zeros already appended.
    Total 255 bits processed.
    """
    shift_reg = 0
    mask = (1 << n_parity) - 1

    for bit in data_bits:  # already 255 bits, MSB first, zeros appended
        msb = (shift_reg >> (n_parity - 1)) & 1
        shift_reg = ((shift_reg << 1) | bit) & mask
        if msb:
            shift_reg ^= genpoly

    return shift_reg


def build_parity_matrix(n_data=239, n_parity=16):
    matrix = [[0] * n_data for _ in range(n_parity)]

    for col in range(n_data):
        # Unit vector MSB first — col 0 = message bit 238 (MSB)
        data_bits = [1 if i == col else 0 for i in range(n_data)]
        # Append 16 zeros as the encoder does
        padded = data_bits + [0] * n_parity  # 255 bits total

        remainder = lfsr_remainder(padded)

        for row in range(n_parity):
            matrix[row][col] = (remainder >> (n_parity - 1 - row)) & 1

    return matrix


def verify_encoder(data_hex, expected_hex, n_data=239, n_parity=16):
    # Convert hex to 239 bits MSB first
    data_int = int(data_hex, 16)
    data_bits = [(data_int >> (n_data - 1 - i)) & 1 for i in range(n_data)]

    # Append 16 zeros as encoder does
    padded = data_bits + [0] * n_parity

    remainder = lfsr_remainder(padded)

    # Even parity over message bits
    msg_parity = 0
    for b in data_bits:
        msg_parity ^= b

    # Even parity over remainder
    rem_parity = 0
    for i in range(n_parity):
        rem_parity ^= (remainder >> i) & 1

    even_parity = msg_parity ^ rem_parity

    # Assemble: message(255 downto 17) | remainder(16 downto 1) | even(0)
    codeword = (data_int << (n_parity + 1)) | (remainder << 1) | even_parity

    result_hex = format(codeword, '064X')
    print(f"Got:      {result_hex}")
    print(f"Expected: {expected_hex.upper()}")
    print(f"Match:    {result_hex == expected_hex.upper()}")

def print_vhdl_matrix(matrix, n_data=239, n_parity=16):
    print("TYPE parity_matrix_t IS ARRAY (0 TO 16) OF STD_LOGIC_VECTOR(0 TO 238);")
    print("CONSTANT parity_matrix : parity_matrix_t := (")
    for row in range(n_parity):
        bits = "".join(str(b) for b in matrix[row])
        print(f'    {row} => "{bits}",')
    # Row 16: even parity over all data bits = all ones
    print(f'    16 => "{"1" * n_data}"')
    print(");")


# Run verification first
print("=== Verifying against test vector ===")
verify_encoder(
    "2D84D096510E5BB388C39EDC07FA7D79AAABAF3565675DD93604031D00C8",
    "5B09A12CA21CB76711873DB80FF4FAF355575E6ACACEBBB26C08063A0190BB29"
)

# Build and print the correct matrix
print("\n=== Correct parity matrix ===")
matrix = build_parity_matrix()
print_vhdl_matrix(matrix)