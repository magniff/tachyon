#!/usr/bin/env python3
# Writes the hidden test inputs of 13-port-c (fixed seeds). The decompress
# inputs are made by compressing with the reference program, so it takes
# the path of reference.c compiled (`cc -O2 -o ref reference.c`):
#
#     python3 gen.py ./ref
#
# The expected outputs come from the reference solution (and match the C
# program byte for byte).
import os
import random
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
REF = sys.argv[1]


def write(name, data):
    with open(os.path.join(HERE, name + ".in"), "wb") as f:
        f.write(data)


def compressed_hex(data):
    out = subprocess.run([REF], input=b"compress\n" + data,
                         capture_output=True, check=True).stdout
    return out.split(b"\n", 1)[1]


def stream(data):
    return bytes.fromhex(compressed_hex(data).decode())


def first_match(s):
    """The position of the first match token's first byte in stream s."""
    p = 11
    while True:
        flags = s[p]
        p += 1
        for bit in range(8):
            if flags >> bit & 1:
                return p
            p += 1


def text(rng, nbytes, vocab):
    words = []
    total = 0
    while total < nbytes:
        w = rng.choice(vocab)
        if rng.random() < 0.08:
            w += rng.choice([".", ",", ";", "!", "?"])
        words.append(w)
        total += len(w) + 1
        if rng.random() < 0.07:
            words.append("\n")
    return " ".join(words).encode()


VOCAB_SMALL = ("the of and to in a is that for it as was with be by on not he "
               "this are or his from at which but have an they you were her "
               "she there been one all we their has would when if so no will "
               "my more out up said what its about into than them can only "
               "other new some time could these two may then do first any "
               "like now my such our over man me even most made after also "
               "did many before must through back years where much your way "
               "well down should because each just those people how too "
               "little state good very make world still own see men work "
               "long get here between both life being under never day same "
               "another know while last might us great old year off come "
               "since against go came right used take three").split()


def main():
    rng = random.Random(1313)

    # 01: the example
    write("01", b"compress\nabracadabra abracadabra abracadabra\n")

    # 02: a mode line ending in \r, no newline: empty data
    write("02", b"compress\r")

    # 03: long runs: overlapping matches, the 18-byte limit, lazy choices
    data = (b"a" * 5000 + b"ab" * 1500 + b"abc" * 700 + b"xyzzy" + b"a" * 37
            + b"\n" + b"0123456789" * 50 + b"0123456788" + b"0123456789" * 3)
    write("03", b"compress\n" + data)

    # 04: binary bytes, every value, with repeats near and far
    chunk = bytes(rng.randrange(256) for _ in range(700))
    data = bytearray()
    for i in range(40):
        r = rng.random()
        if r < 0.4:
            data += chunk[rng.randrange(600):][:rng.randrange(3, 60)]
        elif r < 0.7:
            data += bytes(rng.randrange(256) for _ in range(rng.randrange(1, 30)))
        else:
            data += bytes(range(256))[rng.randrange(200):][:rng.randrange(2, 50)]
    data += b"\r\n\x00\x00\x00\xff\xff\xff\xff\x80\x80"
    write("04", b"compress\n" + bytes(data))

    # 05: more than the window: repeats at distances 4095, 4096 and 4097
    block = text(rng, 4090, VOCAB_SMALL)
    tail = b"<<marker-one>>"
    data = block[:4081] + tail + block[:4082] + tail + block[:4083] + tail
    data += block[:4083] + tail + text(rng, 50000, VOCAB_SMALL)
    data += block[:2000]
    write("05", b"compress\n" + data)

    # 06: large text, about 400 KB (speed)
    vocab = VOCAB_SMALL + ["".join(rng.choice("abcdefghijklmnopqrstuvwxyz")
                                   for _ in range(rng.randrange(3, 12)))
                           for _ in range(3000)]
    data = text(rng, 400000, vocab)
    write("06", b"compress\n" + data)

    # 07: a round trip: CRLF data with some binary bytes, the hex in
    # uppercase, odd line breaks
    data = (b"line one\r\nline two\r\nline one\r\nline two\r\n\tindented\r\n" * 3
            + b"bytes \x00\x80\xff\xfe\x80\xff\xfe\x80\xff\xfe end\r\n"
            + b"line one\r\nline two\r\n\tindented\r\n" * 2)
    hx = compressed_hex(data).decode().replace("\n", "").upper()
    parts = []
    i = 0
    while i < len(hx):
        k = rng.randrange(1, 23)
        parts.append(hx[i:i + k])
        i += k
    write("07", ("decompress\r\n" + " \t".join(parts[:10]) + "\n\n"
                 + "\r\n".join(parts[10:]) + "\n").encode())

    # 08: decompress a large stream (about 600 KB of hex)
    data = text(random.Random(88), 300000, vocab)
    write("08", b"decompress\n" + compressed_hex(data))

    base = (b"It was the best of times, it was the worst of times, it was "
            b"the age of wisdom, it was the age of foolishness.\n") * 3
    s = bytearray(stream(base))

    # 09: a distance before the start of the data (the first match's
    # distance made larger than the output so far)
    t = bytearray(s)
    t[first_match(t)] = 0xF0
    write("09", b"decompress\n" + t.hex().encode() + b"\n")

    # 10: the stream cut in the middle of a match
    write("10", b"decompress\n" + s[:len(s) - 1].hex().encode())

    # 11: one data byte changed: the CRC does not match
    t = bytearray(s)
    t[13] ^= 0x20
    write("11", b"decompress\n" + t.hex().encode() + b"\n")

    # 12: bytes after the end
    write("12", b"decompress\n" + (bytes(s) + b"\x00\x01\x02").hex().encode())

    # 13: a match running past the stored length (the length made smaller)
    t = bytearray(s)
    t[3] = (len(base) - 2) & 0xFF
    t[4] = (len(base) - 2) >> 8
    write("13", b"decompress\n" + t.hex().encode())

    # 14: a character that is not hex
    write("14", b"decompress\n4c5a01 0000\n00 00g0\n")

    # 15: an unknown mode (the mode is case-sensitive)
    write("15", b"Compress\nabc\n")


main()
