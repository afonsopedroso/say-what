"""Generates the Say What app icon (iOS, macOS, web) from code."""
import os, json
from PIL import Image, ImageDraw, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
S = 1024

def icon(size=S, rounded=False):
    img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    # vertical gradient background
    bg = Image.new("RGBA", (S, S))
    top, bot = (255, 92, 56), (214, 40, 22)
    d = ImageDraw.Draw(bg)
    for y in range(S):
        t = y / (S - 1)
        d.line([(0, y), (S, y)], fill=tuple(int(top[i] + (bot[i] - top[i]) * t) for i in range(3)) + (255,))
    if rounded:  # macOS style squircle-ish with margin
        mask = Image.new("L", (S, S), 0)
        ImageDraw.Draw(mask).rounded_rectangle([100, 100, S - 100, S - 100], radius=185, fill=255)
        shadow = Image.new("RGBA", (S, S), (0, 0, 0, 0))
        ImageDraw.Draw(shadow).rounded_rectangle([100, 118, S - 100, S - 82], radius=185, fill=(0, 0, 0, 90))
        img = Image.alpha_composite(img, shadow.filter(ImageFilter.GaussianBlur(14)))
        img.paste(bg, (0, 0), mask)
        scale, off = 0.8, 102
    else:
        img = bg
        scale, off = 1.0, 0
    d = ImageDraw.Draw(img)
    def P(x, y): return (off + x * scale, off + y * scale)
    # speech bubble
    bx0, by0, bx1, by1 = 180, 230, 844, 720
    d.rounded_rectangle([P(bx0, by0), P(bx1, by1)], radius=int(200 * scale), fill=(255, 255, 255, 255))
    d.polygon([P(300, 690), P(250, 860), P(450, 712)], fill=(255, 255, 255, 255))
    # waveform bars inside bubble
    bars = [0.32, 0.62, 1.0, 0.7, 0.42]
    cx, cy, w, gap, hmax = 512, 475, 62, 34, 330
    total = len(bars) * w + (len(bars) - 1) * gap
    x = cx - total / 2
    for b in bars:
        h = hmax * b
        d.rounded_rectangle([P(x, cy - h / 2), P(x + w, cy + h / 2)], radius=int(w / 2 * scale), fill=(234, 58, 32, 255))
        x += w + gap
    return img.resize((size, size), Image.LANCZOS)

# iOS: single 1024 icon
ios = os.path.join(ROOT, "iOS/App/Assets.xcassets/AppIcon.appiconset")
os.makedirs(ios, exist_ok=True)
icon().convert("RGB").save(os.path.join(ios, "icon-1024.png"))
json.dump({"images": [{"filename": "icon-1024.png", "idiom": "universal", "platform": "ios", "size": "1024x1024"}],
           "info": {"author": "xcode", "version": 1}}, open(os.path.join(ios, "Contents.json"), "w"), indent=2)
json.dump({"info": {"author": "xcode", "version": 1}}, open(os.path.join(ROOT, "iOS/App/Assets.xcassets/Contents.json"), "w"), indent=2)

# macOS: full size set
mac = os.path.join(ROOT, "macOS/Assets.xcassets/AppIcon.appiconset")
os.makedirs(mac, exist_ok=True)
images = []
for pt in [16, 32, 128, 256, 512]:
    for scale in [1, 2]:
        px = pt * scale
        name = f"mac-{pt}@{scale}x.png"
        icon(px, rounded=True).save(os.path.join(mac, name))
        images.append({"filename": name, "idiom": "mac", "scale": f"{scale}x", "size": f"{pt}x{pt}"})
json.dump({"images": images, "info": {"author": "xcode", "version": 1}}, open(os.path.join(mac, "Contents.json"), "w"), indent=2)
json.dump({"info": {"author": "xcode", "version": 1}}, open(os.path.join(ROOT, "macOS/Assets.xcassets/Contents.json"), "w"), indent=2)

# Web
web = os.path.join(ROOT, "web/icons")
os.makedirs(web, exist_ok=True)
for px in [180, 192, 512]:
    icon(px).convert("RGB").save(os.path.join(web, f"icon-{px}.png"))
icon(512, rounded=True).save(os.path.join(ROOT, "web/icons/icon-mac-512.png"))
print("icons ok")
