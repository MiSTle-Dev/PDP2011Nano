#
# Convert a Verilog $readmemh style hex file (like keymap.hex) into a Gowin
# memory initialization (.mi) file, usable with the Gowin IP/BSRAM
# initialization flow.
#
# Input: // and /* */ comments, @<hex address> markers and whitespace separated
# hex byte values. Addresses not present in the input are filled with zeros.
#
# Usage:
#   python keymap_to_gowin_mi.py keymap.hex -o keymap.mi
#   python keymap_to_gowin_mi.py keymap.hex > keymap.mi
#

import argparse
import re
import sys

DEFAULT_DEPTH = 2048  # keymap_rom.v: reg [7:0] mem [2047:0]
DEFAULT_WIDTH = 8


def parse_readmemh(text, depth, width):
    text = re.sub(r"/\*.*?\*/", " ", text, flags=re.DOTALL)
    text = re.sub(r"//[^\n]*", " ", text)

    max_value = (1 << width) - 1
    values = {}
    addr = 0

    for token in text.split():
        if token.startswith("@"):
            addr = int(token[1:], 16)
            continue
        value = int(token, 16)
        if value > max_value:
            raise ValueError(f"value {token} at address {addr:#x} does not fit in {width} bits")
        if not 0 <= addr < depth:
            raise ValueError(f"address {addr:#x} is outside depth {depth}")
        values[addr] = value
        addr += 1

    return [values.get(a, 0) for a in range(depth)]


def format_mi(data, depth, width):
    hex_digits = (width + 3) // 4
    lines = [
        "#File_format=Hex",
        f"#Address_depth={depth}",
        f"#Data_width={width}",
    ]
    lines += [f"{v:0{hex_digits}X}" for v in data]
    return "\n".join(lines) + "\n"


def main():
    parser = argparse.ArgumentParser(description="Convert a readmemh hex file to a Gowin .mi file")
    parser.add_argument("input", help="readmemh style hex file")
    parser.add_argument("-o", "--output", help="output .mi file (default: stdout)")
    parser.add_argument("--depth", type=int, default=DEFAULT_DEPTH,
                        help=f"memory depth in words (default: {DEFAULT_DEPTH})")
    parser.add_argument("--width", type=int, default=DEFAULT_WIDTH,
                        help=f"data width in bits (default: {DEFAULT_WIDTH})")
    args = parser.parse_args()

    with open(args.input) as f:
        data = parse_readmemh(f.read(), args.depth, args.width)

    mi = format_mi(data, args.depth, args.width)

    if args.output:
        with open(args.output, "w") as f:
            f.write(mi)
    else:
        sys.stdout.write(mi)


if __name__ == "__main__":
    main()
