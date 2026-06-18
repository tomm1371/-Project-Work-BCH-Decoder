# Usage
# python tools/txt_to_rom.py sim/TestFiles/<file>.txt --target encoder
# python tools/txt_to_rom.py sim/TestFiles/<file>.txt --target encoder --product
# python tools/txt_to_rom.py sim/TestFiles/<file>.txt --target decoder
# python tools/txt_to_rom.py sim/TestFiles/<file>.txt --target decoder --product
"""Convert a text file of bitstrings into a VHDL codeword package.

The input is expected to contain one codeword per line using either:
- raw binary digits, or
- raw hexadecimal digits.

Blank lines and lines starting with # or -- are ignored.

Validation rules:

    --target encoder
        Each word should be 239 bits.
        - Too short : zero-pad on the RIGHT  (warning printed)
        - Too long  : trim from the RIGHT    (warning printed)
        Line count  : any number accepted.

    --target encoder --product
        Same width handling as above (pad/trim with warnings).
        Line count  : MUST be a multiple of 239. If not, zero-word lines are
                    appended until the next multiple of 239 (warning printed).
    
    --target decoder
        Each word MUST be exactly 256 bits -- error and no output if not.
        Line count  : any number accepted.

    --target decoder --product
        Each word MUST be exactly 256 bits -- error and no output if not.
        Line count  : MUST be exactly 256 -- error and no output if not.
"""

from __future__ import annotations

import argparse
import math
import re
import sys
from pathlib import Path


BIN_RE = re.compile(r"^[01]+$")
HEX_RE = re.compile(r"^[0-9A-Fa-f]+$")

ENCODER_WIDTH = 239
DECODER_WIDTH = 256


def ceil_log2(value: int) -> int:
    if value <= 1:
        return 1
    return math.ceil(math.log2(value))


def parse_codewords(path: Path) -> tuple[list[str], str]:
    words: list[str] = []
    data_kind = "bin"

    for raw_line in path.read_text(encoding="utf-8").splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#") or line.startswith("--"):
            continue
        if line.startswith("0x") or line.startswith("0X"):
            line = line[2:]
            data_kind = "hex"
        if BIN_RE.fullmatch(line):
            words.append(line)
        elif HEX_RE.fullmatch(line):
            words.append(line.upper())
            data_kind = "hex"
        else:
            raise ValueError(f"Unsupported line in {path}: {raw_line!r}")

    if not words:
        raise ValueError(f"No codewords found in {path}")

    return words, data_kind


def normalize_words(words: list[str], data_kind: str) -> list[str]:
    """Convert all words to binary strings."""
    normalized: list[str] = []
    for word in words:
        if data_kind == "hex":
            bits = bin(int(word, 16))[2:].zfill(len(word) * 4)
        else:
            bits = word
        normalized.append(bits)
    return normalized


def validate_encoder(words: list[str], product: bool) -> list[str]:
    """
    Encoder rules:
    - Words too short : zero-pad right, warn
    - Words too long  : trim right, warn
    - Line count      : any if not product; must be multiple of 239 if product,
                        zero-word rows appended to reach next multiple (warn)
    """
    validated: list[str] = []
    pad_count  = 0
    trim_count = 0

    for i, word in enumerate(words):
        w = len(word)
        if w < ENCODER_WIDTH:
            validated.append(word.zfill(ENCODER_WIDTH))
            pad_count += 1
        elif w > ENCODER_WIDTH:
            validated.append(word[w - ENCODER_WIDTH:])  # keep rightmost bits
            trim_count += 1
        else:
            validated.append(word)

    if pad_count:
        print(f"Warning: {pad_count} word(s) were shorter than {ENCODER_WIDTH} bits and were zero-padded.", file=sys.stderr)
    if trim_count:
        print(f"Warning: {trim_count} word(s) were longer than {ENCODER_WIDTH} bits and were trimmed.", file=sys.stderr)

    if product:
        remainder = len(validated) % ENCODER_WIDTH
        if remainder != 0:
            pad_words = ENCODER_WIDTH - remainder
            validated.extend(["0" * ENCODER_WIDTH] * pad_words)
            print(
                f"Warning: line count {len(validated) - pad_words} is not a multiple of {ENCODER_WIDTH}. "
                f"Appended {pad_words} zero-word(s) to reach {len(validated)} lines.",
                file=sys.stderr,
            )

    return validated


def validate_decoder(words: list[str], product: bool) -> list[str]:
    """
    Decoder rules:
    - Every word MUST be exactly 256 bits -- error and no output if any are wrong.
    - Line count: any if not product; must be exactly 256 if product -- error if not.
    """
    for i, word in enumerate(words):
        if len(word) != DECODER_WIDTH:
            raise ValueError(
                f"Line {i + 1}: decoder word is {len(word)} bits but must be exactly "
                f"{DECODER_WIDTH} bits. No output written -- verify your data."
            )

    if product:
        if len(words) % DECODER_WIDTH != 0:
            raise ValueError(
                f"Decoder product requires exactly {DECODER_WIDTH} lines but got {len(words)}. "
                f"No output written."
            )

    return words


def write_package(output_path: Path, words: list[str], width: int, target: str) -> None:
    depth      = len(words)
    addr_width = ceil_log2(depth)
    pkg_name   = f"codeword_{target}_pkg"
    type_name  = f"codeword_{target}_rom_t"
    const_name = f"CODEWORD_{target.upper()}_ROM"

    rom_lines = []
    for index, word in enumerate(words):
        suffix = "," if index < depth - 1 else ""
        rom_lines.append(f"        {index} => \"{word}\"{suffix}")

    package_text = f"""LIBRARY ieee;
USE ieee.std_logic_1164.ALL;
USE ieee.numeric_std.ALL;

PACKAGE {pkg_name} IS
    CONSTANT CODEWORD_WIDTH      : POSITIVE := {width};
    CONSTANT CODEWORD_COUNT      : POSITIVE := {depth};
    CONSTANT CODEWORD_ADDR_WIDTH : POSITIVE := {addr_width};

    TYPE {type_name} IS ARRAY (0 TO CODEWORD_COUNT - 1)
        OF STD_LOGIC_VECTOR(CODEWORD_WIDTH - 1 DOWNTO 0);

    CONSTANT {const_name} : {type_name} := (
{chr(10).join(rom_lines)}
    );

END PACKAGE {pkg_name};

PACKAGE BODY {pkg_name} IS
END PACKAGE BODY {pkg_name};
"""
    output_path.write_text(package_text, encoding="utf-8")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("input", type=Path, help="Source txt file")
    parser.add_argument(
        "--target",
        choices=["encoder", "decoder"],
        required=True,
        help="Target use: 'encoder' (239-bit words) or 'decoder' (256-bit words, strict).",
    )
    parser.add_argument(
        "--product",
        action="store_true",
        help=(
            "Enforce product-level line count rules. "
            "Encoder: line count must be multiple of 239 (zero-padded if not). "
            "Decoder: line count must be exactly 256 (error if not)."
        ),
    )
    args = parser.parse_args()

    repo_root = Path(__file__).resolve().parents[1]

    words, data_kind = parse_codewords(args.input)
    normalized       = normalize_words(words, data_kind)

    if args.target == "encoder":
        validated = validate_encoder(normalized, product=args.product)
        width     = ENCODER_WIDTH
    else:
        validated = validate_decoder(normalized, product=args.product)
        width     = DECODER_WIDTH

    pkg_filename = f"codeword_{args.target}_pkg.vhd"
    pkg_path     = repo_root / "src" / "data" / pkg_filename

    write_package(pkg_path, words=validated, width=width, target=args.target)

    print(
        f"Wrote {pkg_path}  "
        f"({len(validated)} words x {width} bits, target={args.target}"
        f"{', product' if args.product else ''})"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())