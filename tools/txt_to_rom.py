# Usage
# python tools/txt_to_rom.py sim/TestFiles/<file>.txt --target encoder
# python tools/txt_to_rom.py sim/TestFiles/<file>.txt --target decoder
"""Convert a text file of bitstrings into a VHDL codeword package.

The input is expected to contain one codeword per line using either:
- raw binary digits, or
- raw hexadecimal digits.

Blank lines and lines starting with # or -- are ignored.
The script writes a VHDL package containing the codewords as a ROM constant
array. Use --target encoder or --target decoder to control the output package
and type names, and the output file destination.
"""

from __future__ import annotations

import argparse
import math
import re
from pathlib import Path


BIN_RE = re.compile(r"^[01]+$")
HEX_RE = re.compile(r"^[0-9A-Fa-f]+$")


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


def normalize_words(words: list[str], width: int | None, data_kind: str) -> tuple[list[str], int]:
    if width is None:
        if data_kind == "hex":
            width = max(len(word) for word in words) * 4
        else:
            width = max(len(word) for word in words)

    normalized: list[str] = []
    for word in words:
        if data_kind == "hex":
            bits = bin(int(word, 16))[2:].zfill(len(word) * 4)
        else:
            bits = word
        if len(bits) > width:
            raise ValueError(f"Word {word!r} is wider than requested width {width}")
        normalized.append(bits.zfill(width))

    return normalized, width


def write_package(output_path: Path, words: list[str], width: int, target: str) -> None:
    depth = len(words)
    addr_width = ceil_log2(depth)

    # Derive naming from target
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
        default="decoder",
        help="Target use: 'encoder' or 'decoder'. Controls package name and output path.",
    )
    parser.add_argument(
        "--width",
        type=int,
        default=None,
        help="Force output word width in bits",
    )
    args = parser.parse_args()

    repo_root = Path(__file__).resolve().parents[1]

    words, data_kind = parse_codewords(args.input)
    normalized_words, width = normalize_words(words, args.width, data_kind)

    pkg_filename = f"codeword_{args.target}_pkg.vhd"
    pkg_path = repo_root / "src" / "data" / pkg_filename

    write_package(pkg_path, words=normalized_words, width=width, target=args.target)

    print(f"Wrote {pkg_path}  ({len(normalized_words)} words x {width} bits, target={args.target})")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())