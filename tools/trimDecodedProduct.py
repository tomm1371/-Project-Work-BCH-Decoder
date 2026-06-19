import pathlib

file_r = pathlib.Path("sim", "TestFiles", "encodedOutput.txt")
file_w = pathlib.Path("sim", "TestFiles", "trimmedDecodedOutput.txt")

BLOCK_SIZE  = 256   # total rows per product block (including parity rows)
DATA_ROWS   = 239   # rows to keep per block (drop last 17)
DATA_BITS   = 239   # bits to keep per row (drop last 17 bits)

print("Found files")

with open(file_r, "r") as reader, open(file_w, "w") as writer:
    row_in_block = 0  # tracks position within the current 256-row block

    for line in reader:
        line = line.strip()
        if not line:
            continue

        if row_in_block < DATA_ROWS:
            writer.write(line[:DATA_BITS] + "\n")  # keep first 239 bits of data rows

        row_in_block += 1
        if row_in_block == BLOCK_SIZE:
            row_in_block = 0  # reset for next block

print("Done")