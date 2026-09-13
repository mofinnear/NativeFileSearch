#!/usr/bin/env python3
"""Build a small modern ICNS container from PNG representations."""

from pathlib import Path
import struct
import sys


def main() -> int:
    if len(sys.argv) != 3:
        print("usage: build-icns.py ICONSET OUTPUT", file=sys.stderr)
        return 2

    iconset = Path(sys.argv[1])
    output = Path(sys.argv[2])
    representations = [
        (b"ic07", "icon_128x128.png"),
        (b"ic08", "icon_256x256.png"),
        (b"ic09", "icon_512x512.png"),
        (b"ic10", "icon_512x512@2x.png"),
    ]

    chunks = []
    for type_code, filename in representations:
        data = (iconset / filename).read_bytes()
        chunks.append(type_code + struct.pack(">I", len(data) + 8) + data)

    payload = b"".join(chunks)
    output.write_bytes(b"icns" + struct.pack(">I", len(payload) + 8) + payload)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
