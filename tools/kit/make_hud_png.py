#!/usr/bin/env python3
"""Genera los PNG de ejemplo del HUD (volante, pedal, palanca, botones) en assets/hud/.
Son plantillas: reemplazalos por tu arte conservando NOMBRE y PROPORCIÓN (ver docs/05).
Uso: python3 tools/make_hud_png.py [carpeta_salida]"""
import sys, os, math
from PIL import Image, ImageDraw, ImageFilter

OUT = sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(__file__), "..", "proyecto_godot", "demo", "hud")
os.makedirs(OUT, exist_ok=True)
S = 2  # supermuestreo para bordes suaves

def canvas(w, h):
    return Image.new("RGBA", (w * S, h * S), (0, 0, 0, 0))

def save(img, name):
    w, h = img.size
    img.resize((w // S, h // S), Image.LANCZOS).save(os.path.join(OUT, name + ".png"))

def rr(d, box, r, fill=None, outline=None, width=1):
    d.rounded_rectangle([v * S for v in box], r * S, fill=fill, outline=outline, width=width * S)

def circle(d, c, r, fill=None, outline=None, width=1):
    d.ellipse([(c[0] - r) * S, (c[1] - r) * S, (c[0] + r) * S, (c[1] + r) * S], fill=fill, outline=outline, width=width * S)

# ---- volante 512x512, marca naranja ARRIBA (se gira por código alrededor del centro) ----
im = canvas(512, 512); d = ImageDraw.Draw(im)
circle(d, (256, 256), 240, fill=(26, 29, 34, 255))
circle(d, (256, 256), 210, outline=(58, 64, 74, 255), width=50)
d.rectangle([(256 - 15) * S, 40 * S, (256 + 15) * S, 240 * S], fill=(58, 64, 74, 255))
d.rectangle([40 * S, (256 - 15) * S, 472 * S, (256 + 15) * S], fill=(58, 64, 74, 255))
circle(d, (256, 256), 68, fill=(20, 24, 30, 255), outline=(90, 100, 114, 255), width=6)
circle(d, (256, 256), 18, fill=(255, 106, 8, 255))
d.rectangle([(256 - 15) * S, 8 * S, (256 + 15) * S, 52 * S], fill=(255, 106, 8, 255))
save(im, "wheel")

# ---- pedal único 140x640: arriba GAS, abajo FRENO, línea del medio ----
im = canvas(140, 640); d = ImageDraw.Draw(im)
rr(d, (2, 2, 138, 638), 60, fill=(13, 16, 21, 235), outline=(74, 79, 87, 255), width=4)
rr(d, (20, 24, 120, 300), 40, outline=(90, 200, 100, 120), width=3)
rr(d, (20, 340, 120, 616), 40, outline=(220, 90, 90, 120), width=3)
d.line([(14 * S, 320 * S), (126 * S, 320 * S)], fill=(255, 255, 255, 170), width=4 * S)
save(im, "pedal_bg")
im = canvas(96, 96); d = ImageDraw.Draw(im)
circle(d, (48, 48), 44, fill=(10, 13, 18, 255), outline=(109, 185, 255, 255), width=5)
circle(d, (48, 48), 12, fill=(109, 185, 255, 255))
save(im, "pedal_knob")
save(im, "slider_knob")

# ---- barra de dirección 800x128 ----
im = canvas(800, 128); d = ImageDraw.Draw(im)
rr(d, (2, 2, 798, 126), 62, fill=(16, 19, 24, 235), outline=(74, 79, 87, 255), width=4)
d.line([(400 * S, 14 * S), (400 * S, 114 * S)], fill=(255, 255, 255, 130), width=3 * S)
save(im, "slider_bg")

# ---- marchas ----
def key(name, arrow, on):
    im = canvas(128, 128); d = ImageDraw.Draw(im)
    fill = (59, 160, 255, 160) if on else (20, 26, 33, 190)
    rr(d, (4, 4, 124, 124), 26, fill=fill, outline=(143, 209, 255, 255) if on else (255, 255, 255, 70), width=3)
    cx, cy = 64, 64
    pts = [(cx, cy - 26), (cx - 28, cy + 16), (cx + 28, cy + 16)] if arrow == "up" else [(cx, cy + 26), (cx - 28, cy - 16), (cx + 28, cy - 16)]
    d.polygon([(x * S, y * S) for x, y in pts], fill=(232, 241, 255, 255))
    save(im, name)
key("gear_up", "up", False); key("gear_up_on", "up", True)
key("gear_dn", "dn", False); key("gear_dn_on", "dn", True)
im = canvas(128, 128); d = ImageDraw.Draw(im)
rr(d, (4, 4, 124, 124), 26, fill=(10, 14, 20, 140), outline=(255, 255, 255, 40), width=2)
save(im, "gear_mid")

# ---- botones redondos 128x128 ----
def round_btn(name, ring, glow=False, glyph=None):
    im = canvas(128, 128); d = ImageDraw.Draw(im)
    if glow:
        circle(d, (64, 64), 62, fill=ring[:3] + (70,))
    circle(d, (64, 64), 54, fill=(ring[0] // 4, ring[1] // 4, ring[2] // 4, 235), outline=ring, width=5)
    if glyph == "H":
        d.rectangle([40 * S, 38 * S, 48 * S, 90 * S], fill=ring); d.rectangle([80 * S, 38 * S, 88 * S, 90 * S], fill=ring); d.rectangle([40 * S, 60 * S, 88 * S, 68 * S], fill=ring)
    elif glyph == "II":
        d.rectangle([44 * S, 38 * S, 56 * S, 90 * S], fill=ring); d.rectangle([72 * S, 38 * S, 84 * S, 90 * S], fill=ring)
    elif glyph == "CAM":
        d.rounded_rectangle([34 * S, 46 * S, 94 * S, 84 * S], 6 * S, outline=ring, width=4 * S); circle(d, (64, 66), 11, outline=ring, width=4)
    save(im, name)
round_btn("handbrake", (255, 100, 90), False, "H"); round_btn("handbrake_on", (255, 100, 90), True, "H")
round_btn("btn_pause", (200, 210, 235), False, "II"); round_btn("btn_cam", (255, 210, 140), False, "CAM")
print("PNG escritos en", os.path.abspath(OUT))
