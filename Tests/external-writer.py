#!/usr/bin/env python3
"""Rewrite a .tex file in 20480-byte chunks, like an external tool that saves in several steps.
Usage: external-writer.py FILE [chunks=5] [delay_ms=5] [rounds=20]
Open FILE in TeXShop first, then run this. After each round, the editor must show as many characters as `wc -c FILE`.
See Documentation/File-watch-reload.md."""
import os, sys, time

path = sys.argv[1]
chunks = int(sys.argv[2]) if len(sys.argv) > 2 else 5
delay = float(sys.argv[3]) / 1000 if len(sys.argv) > 3 else 0.005
rounds = int(sys.argv[4]) if len(sys.argv) > 4 else 20

line = b"% filler line for TeXShop reload test 0123456789\n"
block = (line * (20480 // len(line) + 1))[:20480]

for r in range(rounds):
    with open(path, "wb", buffering=0) as f:      # O_TRUNC, then unbuffered 20 KB writes
        f.write(b"\\documentclass{article}\\begin{document}\n")
        for _ in range(chunks):
            f.write(block)
            time.sleep(delay)
        f.write(b"\\end{document}\n")
    time.sleep(0.5)
    print(f"round {r}: on disk {os.path.getsize(path)} bytes", flush=True)
