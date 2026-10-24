"""Draws the Helper app icon (Pip on a night-blue background) with no extra libraries.

Usage: python tools/make_icon.py Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png
"""
import math
import struct
import sys
import zlib

SIZE = 1024
SS = 2  # supersampling for smooth edges


def mix(a, b, t):
    return tuple(a[i] + (b[i] - a[i]) * t for i in range(3))


def over(dst, src, alpha):
    return tuple(dst[i] * (1 - alpha) + src[i] * alpha for i in range(3))


BG_TOP, BG_BOTTOM = (10, 16, 41), (27, 37, 86)
BODY_TOP, BODY_BOTTOM = (84, 230, 204), (64, 115, 247)
GLOW = (158, 242, 255)
DARK = (20, 20, 26)
CHEEK = (255, 140, 166)


def in_ellipse(x, y, cx, cy, rx, ry):
    return ((x - cx) / rx) ** 2 + ((y - cy) / ry) ** 2 <= 1


def smile_dist(x, y, cx, cy, w, h):
    """Distance to a smile curve: y = cy + h*(1 - (2u-1)^2) for u in [0,1]."""
    if abs(x - cx) > w / 2:
        return 1e9
    u = (x - (cx - w / 2)) / w
    curve = cy + h * (1 - (2 * u - 1) ** 2)
    return abs(y - curve)


def color_at(x, y):
    c = mix(BG_TOP, BG_BOTTOM, y / SIZE)
    # soft glow behind Pip
    d = math.hypot(x - 512, y - 560)
    c = over(c, (60, 140, 220), max(0.0, 1 - d / 520) * 0.35)

    # antenna stem + ball
    if abs(x - 512) < 13 and 215 < y < 330:
        c = BODY_TOP
    if in_ellipse(x, y, 512, 200, 46, 46):
        c = GLOW
    elif math.hypot(x - 512, y - 200) < 80:
        c = over(c, GLOW, (1 - (math.hypot(x - 512, y - 200) - 46) / 34) * 0.4)

    # body
    cx, cy, r = 512, 580, 300
    if in_ellipse(x, y, cx, cy, r, r):
        c = mix(BODY_TOP, BODY_BOTTOM, (y - (cy - r)) / (2 * r))
        if in_ellipse(x, y, 400, 430, 95, 48):
            c = over(c, (255, 255, 255), 0.35)
        # eyes
        for ex in (450, 574):
            if in_ellipse(x, y, ex, 560, 58, 70):
                c = (255, 255, 255)
                if in_ellipse(x, y, ex, 575, 34, 34):
                    c = DARK
                    if in_ellipse(x, y, ex + 12, 560, 11, 11):
                        c = (255, 255, 255)
        # cheeks
        for kx in (372, 652):
            if in_ellipse(x, y, kx, 650, 38, 21):
                c = over(c, CHEEK, 0.6)
        # smile
        if smile_dist(x, y, 512, 675, 110, 30) < 9:
            c = DARK
    return c


def main(path):
    rows = []
    for py in range(SIZE):
        row = bytearray([0])
        for px in range(SIZE):
            acc = [0.0, 0.0, 0.0]
            for sy in range(SS):
                for sx in range(SS):
                    col = color_at(px + (sx + 0.5) / SS, py + (sy + 0.5) / SS)
                    for i in range(3):
                        acc[i] += col[i]
            row += bytes(int(min(255, max(0, v / (SS * SS)))) for v in acc)
        rows.append(bytes(row))
    raw = b"".join(rows)

    def chunk(kind, data):
        return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data) & 0xFFFFFFFF)

    png = b"\x89PNG\r\n\x1a\n"
    png += chunk(b"IHDR", struct.pack(">IIBBBBB", SIZE, SIZE, 8, 2, 0, 0, 0))
    png += chunk(b"IDAT", zlib.compress(raw, 9))
    png += chunk(b"IEND", b"")
    with open(path, "wb") as f:
        f.write(png)


if __name__ == "__main__":
    main(sys.argv[1])
