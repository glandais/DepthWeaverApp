"""Generate seamlessly tileable pattern images for the autostereogram generator."""

import math
import random

from PIL import Image, ImageDraw


SIZE = 128


def create_pattern(name, draw_func):
    img = Image.new("RGB", (SIZE, SIZE))
    draw = ImageDraw.Draw(img)
    draw_func(img, draw, SIZE)
    img.save(f"{name}.png")


def draw_wrapped_ellipse(draw, cx, cy, r, size, **kwargs):
    """Draw an ellipse that wraps around tile edges for seamless tiling."""
    for dy in (-size, 0, size):
        for dx in (-size, 0, size):
            draw.ellipse(
                [cx - r + dx, cy - r + dy, cx + r + dx, cy + r + dy],
                **kwargs,
            )


def dots(img, draw, size):
    random.seed(42)
    for _ in range(800):
        x, y = random.randint(0, size - 1), random.randint(0, size - 1)
        r = random.randint(1, 3)
        color = (random.randint(50, 255), random.randint(50, 255), random.randint(50, 255))
        draw_wrapped_ellipse(draw, x, y, r, size, fill=color)


def checkerboard(img, draw, size):
    cell = 16  # 128 / 16 = 8, divides evenly
    for y in range(0, size, cell):
        for x in range(0, size, cell):
            if ((x // cell) + (y // cell)) % 2 == 0:
                draw.rectangle([x, y, x + cell, y + cell], fill=(200, 80, 80))
            else:
                draw.rectangle([x, y, x + cell, y + cell], fill=(80, 80, 200))


def stripes_diagonal(img, draw, size):
    colors = [(230, 120, 50), (50, 150, 230), (230, 230, 50), (50, 200, 100)]
    stripe_w = 16  # 128 / 16 = 8, divides evenly for seamless tiling
    for y in range(size):
        for x in range(size):
            idx = ((x + y) // stripe_w) % len(colors)
            draw.point((x, y), fill=colors[idx])


def noise(img, draw, size):
    random.seed(123)
    for y in range(size):
        for x in range(size):
            c = (random.randint(0, 255), random.randint(0, 255), random.randint(0, 255))
            draw.point((x, y), fill=c)


def circles(img, draw, size):
    cell = 32  # 128 / 32 = 4, divides evenly
    r = 10
    palette = [
        (220, 60, 60), (60, 180, 60), (60, 100, 220), (230, 180, 40),
        (180, 60, 200), (60, 200, 200), (230, 120, 50), (120, 200, 80),
    ]
    random.seed(321)
    cols = size // cell
    for row_i in range(size // cell):
        # Pick `cols` distinct colors for this row (no repetition within a row)
        row_colors = random.sample(palette, cols)
        for col_i in range(cols):
            x, y = col_i * cell, row_i * cell
            cx, cy = x + cell // 2, y + cell // 2
            draw_wrapped_ellipse(draw, cx, cy, r, size, fill=row_colors[col_i])
            draw_wrapped_ellipse(draw, cx, cy, r - 3, size, fill=(30, 30, 30))


def triangles(img, draw, size):
    colors = [(255, 100, 100), (100, 255, 100), (100, 100, 255), (255, 255, 100), (255, 100, 255)]
    step = 16  # 128 / 16 = 8, divides evenly
    for y in range(0, size, step):
        for x in range(0, size, step):
            color = colors[((x // step) + (y // step)) % len(colors)]
            if ((x // step) + (y // step)) % 2 == 0:
                draw.polygon([(x, y + step), (x + step // 2, y), (x + step, y + step)], fill=color)
            else:
                draw.polygon([(x, y), (x + step // 2, y + step), (x + step, y)], fill=color)


def waves(img, draw, size):
    # Use frequencies that complete full cycles over `size` pixels
    # 2*pi*n / size where n is an integer
    fx1 = 2 * math.pi * 3 / size  # 3 cycles
    fy1 = 2 * math.pi * 1 / size
    fx2 = 2 * math.pi * 1 / size
    fy2 = 2 * math.pi * 3 / size
    fx3 = 2 * math.pi * 2 / size
    fy3 = 2 * math.pi * 2 / size
    for y in range(size):
        for x in range(size):
            r = int(127 + 127 * math.sin(x * fx1 + y * fy1))
            g = int(127 + 127 * math.sin(x * fx2 + y * fy2 + 2))
            b = int(127 + 127 * math.sin(x * fx3 - y * fy3 + 4))
            draw.point((x, y), fill=(r, g, b))


def mosaic(img, draw, size):
    random.seed(99)
    cell = 16  # 128 / 16 = 8, divides evenly
    for y in range(0, size, cell):
        for x in range(0, size, cell):
            color = (random.randint(30, 230), random.randint(30, 230), random.randint(30, 230))
            draw.rectangle([x, y, x + cell - 1, y + cell - 1], fill=color)


def stars(img, draw, size):
    random.seed(55)
    draw.rectangle([0, 0, size, size], fill=(15, 15, 40))
    for _ in range(200):
        x, y = random.randint(0, size - 1), random.randint(0, size - 1)
        brightness = random.randint(150, 255)
        r = random.randint(0, 2)
        draw_wrapped_ellipse(draw, x, y, r, size, fill=(brightness, brightness, brightness))


def hexagons(img, draw, size):
    hex_r = 10
    colors = [(200, 60, 60), (60, 200, 60), (60, 60, 200), (200, 200, 60)]
    # Use row/col spacing that divides evenly into size
    row_h = 16  # 128 / 16 = 8 rows
    col_w = 32  # 128 / 32 = 4 cols
    idx = 0
    for row_i in range(size // row_h):
        for col_i in range(size // col_w):
            cx = col_i * col_w + (hex_r if row_i % 2 else 0)
            cy = row_i * row_h
            points = []
            for i in range(6):
                angle = math.pi / 3 * i + math.pi / 6
                px = cx + hex_r * math.cos(angle)
                py = cy + hex_r * math.sin(angle)
                points.append((px, py))
            # Draw with wrapping for edge hexagons
            for dy in (-size, 0, size):
                for dx in (-size, 0, size):
                    shifted = [(p[0] + dx, p[1] + dy) for p in points]
                    draw.polygon(shifted, fill=colors[idx % len(colors)], outline=(30, 30, 30))
            idx += 1


if __name__ == "__main__":
    patterns = [
        ("pattern-dots", dots),
        ("pattern-checkerboard", checkerboard),
        ("pattern-stripes", stripes_diagonal),
        ("pattern-noise", noise),
        ("pattern-circles", circles),
        ("pattern-triangles", triangles),
        ("pattern-waves", waves),
        ("pattern-mosaic", mosaic),
        ("pattern-stars", stars),
        ("pattern-hexagons", hexagons),
    ]
    for name, func in patterns:
        create_pattern(name, func)
        print(f"Created {name}.png")
