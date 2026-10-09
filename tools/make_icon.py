"""يولّد أيقونة التطبيق (assets/icon.png و assets/icon_fg.png)"""
from PIL import Image, ImageDraw, ImageFont
import os

S = 1024
os.makedirs("assets", exist_ok=True)


def gradient(size):
    img = Image.new("RGB", (size, size))
    px = img.load()
    c1, c2 = (201, 100, 66), (217, 119, 87)
    for y in range(size):
        for x in range(size):
            t = (x + y) / (2 * size)
            px[x, y] = tuple(int(c1[i] + (c2[i] - c1[i]) * t) for i in range(3))
    return img


def font(sz):
    for p in [
        "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",
        "/usr/share/fonts/truetype/liberation/LiberationSans-Bold.ttf",
    ]:
        if os.path.exists(p):
            return ImageFont.truetype(p, sz)
    return ImageFont.load_default()


def draw_w(img, scale):
    d = ImageDraw.Draw(img)
    f = font(int(S * scale))
    bb = d.textbbox((0, 0), "W", font=f)
    d.text(
        ((S - (bb[2] - bb[0])) / 2 - bb[0], (S - (bb[3] - bb[1])) / 2 - bb[1]),
        "W",
        font=f,
        fill="white",
    )


bg = gradient(S).convert("RGBA")
draw_w(bg, 0.62)
mask = Image.new("L", (S, S), 0)
ImageDraw.Draw(mask).rounded_rectangle((0, 0, S, S), radius=int(S * 0.23), fill=255)
bg.putalpha(mask)
bg.save("assets/icon.png")

fg = Image.new("RGBA", (S, S), (0, 0, 0, 0))
draw_w(fg, 0.42)
fg.save("assets/icon_fg.png")
print("icons generated")
