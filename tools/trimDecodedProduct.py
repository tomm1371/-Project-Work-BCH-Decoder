import pathlib

file_r = pathlib.Path("sim", "TestFiles", "decoderProductOutput.txt")
file_w = pathlib.Path("sim", "TestFiles", "trimmedDecodedOutput.txt")

BLOCK_SIZE = 256  # total rows per product block (including parity rows)
DATA_ROWS  = 239  # rows to keep per block (drop last 17)
DATA_BITS  = 239  # bits to keep per row (drop last 17 bits)

TRANSPOSE  = True  # set to False to skip transposition

print("Found files")

with open(file_r, "r") as reader, open(file_w, "w") as writer:
    row_in_block = 0
    block: list[str] = []

    def flush_block(block: list[str]) -> None:
        """Write a completed 239x239 block, transposed if enabled."""
        if not block:
            return
        if TRANSPOSE:
            # block[r][c] -> transposed[c][r]
            # each row is a string of '0'/'1', so index directly
            for col in range(DATA_BITS):
                transposed_row = "".join(block[row][col] for row in range(len(block)))
                writer.write(transposed_row + "\n")
        else:
            for row in block:
                writer.write(row + "\n")

    for line in reader:
        line = line.strip()
        if not line:
            continue

        if row_in_block < DATA_ROWS:
            block.append(line[:DATA_BITS])  # accumulate data rows

        row_in_block += 1
        if row_in_block == BLOCK_SIZE:
            flush_block(block)
            block = []
            row_in_block = 0

    # flush any incomplete final block
    if block:
        flush_block(block)

print("Done trimming decoded output")