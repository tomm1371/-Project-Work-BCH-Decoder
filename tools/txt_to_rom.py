# Usage
# python tools/txt_to_rom.py sim/TestFiles/*file to read from*.txt --out-dir quartus --name bch_decoder_codewords
"""Convert a text file of bitstrings into Quartus-friendly ROM assets.

The input is expected to contain one codeword per line using either:
- raw binary digits, or
- raw hexadecimal digits.

Blank lines and lines starting with # or -- are ignored.
The script writes both a Quartus .mif file and a VHDL package containing
the normalized codewords as a ROM constant array. The hardware now reads
the VHDL package directly, which is more reliable than inferred memory init.
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


def write_mif(output_path: Path, words: list[str], width: int) -> None:
    depth = len(words)
    lines = [
        f"WIDTH={width};",
        f"DEPTH={depth};",
        "ADDRESS_RADIX=DEC;",
        "DATA_RADIX=BIN;",
        "CONTENT BEGIN",
    ]
    for index, word in enumerate(words):
        lines.append(f"    {index} : {word};")
    lines.append("END;")
    output_path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def write_package(output_path: Path, words: list[str], width: int) -> None:
    depth = len(words)
    addr_width = ceil_log2(depth)
    rom_lines = []
    for index, word in enumerate(words):
        suffix = "," if index < depth - 1 else ""
        rom_lines.append(f"    {index} => \"{word}\"{suffix}")

    package_text = f"""LIBRARY ieee;
USE ieee.std_logic_1164.ALL;
USE ieee.numeric_std.ALL;

PACKAGE codeword_file_pkg IS
    CONSTANT CODEWORD_WIDTH : POSITIVE := {width};
    CONSTANT CODEWORD_COUNT : POSITIVE := {depth};
    CONSTANT CODEWORD_ADDR_WIDTH : POSITIVE := {addr_width};

    TYPE codeword_rom_t IS ARRAY (0 TO CODEWORD_COUNT - 1) OF STD_LOGIC_VECTOR(CODEWORD_WIDTH - 1 DOWNTO 0);

    CONSTANT CODEWORD_ROM : codeword_rom_t := (
{chr(10).join(rom_lines)}
    );
END PACKAGE codeword_file_pkg;

PACKAGE BODY codeword_file_pkg IS
END PACKAGE BODY codeword_file_pkg;
"""
    output_path.write_text(package_text, encoding="utf-8")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("input", type=Path, help="Source txt file")
    parser.add_argument(
        "--out-dir",
        type=Path,
        default=Path("quartus"),
        help="Directory for generated MIF/package files",
    )
    parser.add_argument(
        "--name",
        default="bch_decoder_codewords",
        help="Base filename for generated files",
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

    out_dir = args.out_dir if args.out_dir.is_absolute() else repo_root / args.out_dir
    out_dir.mkdir(parents=True, exist_ok=True)
    mif_path = out_dir / f"{args.name}.mif"
    pkg_path = repo_root / "src" / "top" / "codeword_file_pkg.vhd"

    write_mif(mif_path, normalized_words, width)
    write_package(pkg_path, words=normalized_words, width=width)

    print(f"Wrote {mif_path} ({len(normalized_words)} words x {width} bits)")
    print(f"Wrote {pkg_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
