"""Draws the article's two diagrams.

usage: python docs/diagrams/make_diagrams.py
Writes docs/diagrams/leak-path.png (still) and docs/diagrams/rotation.gif
(animated). Needs Pillow and the Windows fonts Segoe UI, Consolas and Segoe
Fluent Icons. Timings and counts match labs/2-rotation/scenario.sh and its
recorded output.
"""

from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

OUT = Path(__file__).resolve().parent
FONTS = Path("C:/Windows/Fonts")
S = 2  # draw at 2x for smooth edges
FPS = 20

INK = (15, 23, 42)
MUTED = (100, 116, 139)
FAINT = (148, 163, 184)
PANEL = (248, 250, 252)
EDGE = (226, 232, 240)
WHITE = (255, 255, 255)
KEY, KEY_LIGHT = (79, 70, 229), (238, 242, 255)
LEAK, LEAK_LIGHT = (194, 65, 12), (255, 237, 213)
SAFE, SAFE_LIGHT = (15, 118, 110), (204, 251, 241)
OLD, OLD_LIGHT = (71, 85, 105), (241, 245, 249)
BLUE, BLUE_LIGHT = (37, 99, 235), (219, 234, 254)
GREEN, GREEN_LIGHT = (21, 128, 61), (220, 252, 231)


def font(name: str, size: float) -> ImageFont.FreeTypeFont:
    return ImageFont.truetype(str(FONTS / name), round(size * S))


REG = {n: font("segoeui.ttf", n) for n in (12, 13, 14)}
SEMI = {n: font("seguisb.ttf", n) for n in (12, 13, 14)}
BOLD = {n: font("segoeuib.ttf", n) for n in (11, 22)}
ITALIC = font("segoeuii.ttf", 12)
MONO = font("consola.ttf", 12)
ICON = font("SegoeIcons.ttf", 22)


def r(v: float) -> int:
    return round(v * S)


def canvas(w, h):
    im = Image.new("RGB", (r(w), r(h)), WHITE)
    return im, ImageDraw.Draw(im)


def text(d, xy, s, fnt, fill, anchor="lm"):
    d.text((r(xy[0]), r(xy[1])), s, font=fnt, fill=fill, anchor=anchor)


def width(d, s, fnt):
    return d.textlength(s, font=fnt) / S


def rect(d, box, fill, outline=None, w=1.0, radius=6):
    d.rounded_rectangle([r(v) for v in box], radius=r(radius), fill=fill,
                        outline=outline, width=r(w) if outline else 0)


def line(d, pts, fill, w=1.6):
    d.line([(r(x), r(y)) for x, y in pts], fill=fill, width=r(w), joint="curve")


def curve(d, a, b, fill):
    """An S-shaped connector from a to b, leaving and arriving horizontally."""
    (x0, y0), (x3, y3) = a, b
    xm = (x0 + x3) / 2
    pts = []
    for i in range(41):
        t = i / 40
        x = (1 - t) ** 3 * x0 + 3 * (1 - t) ** 2 * t * xm + 3 * (1 - t) * t ** 2 * xm + t ** 3 * x3
        y = (1 - t) ** 3 * y0 + 3 * (1 - t) ** 2 * t * y0 + 3 * (1 - t) * t ** 2 * y3 + t ** 3 * y3
        pts.append((x, y))
    line(d, pts, fill, 1.6)
    d.polygon([(r(x3), r(y3)), (r(x3 - 7), r(y3 - 4)), (r(x3 - 7), r(y3 + 4))], fill=fill)


def dashed(d, x, y0, y1, fill):
    y = y0
    while y < y1:
        line(d, [(x, y), (x, min(y + 4, y1))], fill, 1.2)
        y += 8


# --- Diagram 1: where the fake key ended up (still image) -------------------

LEAK_GROUPS = [
    ("GIT", [("Latest commit, after git rm --cached", "the file is no longer tracked", False),
             ("Git history", "every clone keeps the older commit", True)]),
    ("DOCKER", [("Build argument used in a RUN step", "docker history shows the value", True),
                ("Build argument copied into ENV", "docker inspect shows the value", True),
                ("COPY . . with no .dockerignore", "the file sits in a layer at /app/.env", True),
                ("COPY . . with .env in .dockerignore", "Docker skips the file", False),
                ("Secret mount", "readable during one build step, then gone", False)]),
    ("KUBERNETES", [("Secret file", "base64 -d turns the value back into the key", True)]),
]


def make_leak_png():
    rows_x0, rows_x1, row_h, row_gap, header_h, top = 330, 960, 46, 8, 28, 108
    n_rows = sum(len(rows) for _, rows in LEAK_GROUPS)
    height = top + n_rows * (row_h + row_gap) + len(LEAK_GROUPS) * header_h + 24
    im, d = canvas(1000, height)
    text(d, (40, 40), "Where the fake key ended up", BOLD[22], INK)
    text(d, (40, 70), "I put a fake API key in a .env file, then took the usual deploy steps. "
                      "5 of the 8 places I checked kept a readable copy.", REG[14], MUTED)

    y, rows = top, []
    for name, group in LEAK_GROUPS:
        text(d, (rows_x0, y + 14), name, BOLD[11], MUTED)
        y += header_h
        for label, detail, leaked in group:
            rows.append((y, label, detail, leaked))
            y += row_h + row_gap
    mid = (rows[0][0] + rows[-1][0] + row_h) / 2
    card = (40, mid - 46, 240, mid + 46)

    for y, label, detail, leaked in rows:
        color, light = (LEAK, LEAK_LIGHT) if leaked else (SAFE, SAFE_LIGHT)
        curve(d, (card[2], mid), (rows_x0 - 2, y + row_h / 2), color)
        rect(d, (rows_x0, y, rows_x1, y + row_h), WHITE, EDGE, 1)
        d.rectangle([r(rows_x0), r(y + 6), r(rows_x0 + 3), r(y + row_h - 6)], fill=color)
        text(d, (rows_x0 + 16, y + 15), label, SEMI[14], INK)
        text(d, (rows_x0 + 16, y + 33), detail, REG[12], MUTED)
        badge = "Readable copy" if leaked else "No copy"
        bw = width(d, badge, SEMI[12]) + 22
        rect(d, (rows_x1 - 14 - bw, y + 12, rows_x1 - 14, y + row_h - 12), light, None, radius=11)
        text(d, (rows_x1 - 14 - bw / 2, y + row_h / 2), badge, SEMI[12], color, anchor="mm")

    rect(d, card, KEY_LIGHT, KEY, 1.5, 10)
    text(d, (140, mid - 22), chr(0xE192), ICON, KEY, anchor="mm")
    text(d, (140, mid + 6), ".env file", SEMI[14], INK, anchor="mm")
    text(d, (140, mid + 27), "API_KEY=canary-5f0c…", MONO, KEY, anchor="mm")

    im.save(OUT / "leak-path.png", optimize=True)
    print(f"leak-path.png: {(OUT / 'leak-path.png').stat().st_size // 1024} KB")


# --- Diagram 2: changing a password while the app runs (animated) -----------

T0, T1, RUN = 270, 950, 11.0
N = 95  # new connections per run, as in labs/2-rotation/output.txt


def X(s):
    return T0 + (T1 - T0) * s / RUN


CONNECTIONS = [(k + 0.5) * RUN / N for k in range(N)]
OLD_PW, NEW_PW = (OLD, OLD_LIGHT), (KEY, KEY_LIGHT)

PANELS = [
    {"name": "Change the password in place", "fails": (3.0, 8.0),
     "tick": lambda c: LEAK if 3.0 <= c < 8.0 else FAINT,
     "events": [(3, "password changed"), (8, "app redeployed")],
     "rows": [("Database accepts", [(0, 3, "app, old password", *OLD_PW), (3, 11, "app, new password", *NEW_PW)]),
              ("App logs in with", [(0, 3, "app, old password", *OLD_PW),
                                    (3, 8, "old password: refused", LEAK, LEAK_LIGHT),
                                    (8, 11, "app, new password", *NEW_PW)]),
              ("New connections", "ticks"),
              ("Open connection", [(0, 11, "opened at 0 s with the old password, still answering", *OLD_PW)])]},
    {"name": "Use two logins", "fails": None,
     "tick": lambda c: BLUE if c < 5.0 else GREEN,  # the login each new connection used
     "events": [(3, "add app_green"), (5, "switch app"), (7, "NOLOGIN"), (9, "close old connections")],
     "rows": [("Database accepts", [(0, 7, "app_blue", BLUE, BLUE_LIGHT),
                                    (7, 11, "app_blue refused (NOLOGIN)", OLD, OLD_LIGHT)]),
              ("", [(3, 11, "app_green", GREEN, GREEN_LIGHT)]),
              ("App logs in as", [(0, 5, "app_blue", BLUE, BLUE_LIGHT), (5, 11, "app_green", GREEN, GREEN_LIGHT)]),
              ("New connections", "ticks"),
              ("Open connection", [(0, 9, "app_blue, opened at 0 s, still answering", BLUE, BLUE_LIGHT)])]},
]


ROWS_AT = 86  # first row's centre, below the panel title and the event labels


def panel_box(i):
    top = 98
    for p in PANELS[:i]:
        top += ROWS_AT - 4 + len(p["rows"]) * 30 + 22 + 18
    return top, top + ROWS_AT - 4 + len(PANELS[i]["rows"]) * 30 + 22


def clipped_label(im, xy, right, s, color, background):
    """Draws a bar's label, cut off at the bar's right edge while the bar is still growing."""
    visible = right - xy[0]
    if visible <= 0:
        return
    label = Image.new("RGB", (r(width(ImageDraw.Draw(im), s, REG[12]) + 2), r(18)), background)
    ImageDraw.Draw(label).text((0, r(9)), s, font=REG[12], fill=color, anchor="lm")
    im.paste(label.crop((0, 0, min(label.width, r(visible)), label.height)), (r(xy[0]), r(xy[1] - 9)))


def rotation_frame(now):
    im, d = canvas(1000, panel_box(len(PANELS) - 1)[1] + 112)
    text(d, (40, 38), "Changing a database password while the app runs", BOLD[22], INK)
    text(d, (40, 68), "A new connection fails when the app logs in with something the database no longer accepts.",
         REG[14], MUTED)
    shown = [c for c in CONNECTIONS if c <= now]

    for i, panel in enumerate(PANELS):
        top, bottom = panel_box(i)
        rect(d, (40, top, 960, bottom), PANEL, EDGE, 1, 8)
        text(d, (56, top + 20), panel["name"], SEMI[14], INK)
        lo, hi = panel["fails"] or (0.0, -1.0)
        failed = sum(lo <= c < hi for c in shown)
        text(d, (944, top + 20), f"New connections failed: {failed} of {len(shown)}",
             SEMI[13], LEAK if failed else MUTED, anchor="rm")

        for at, label in panel["events"]:
            if now >= at:
                text(d, (X(at), top + 42), f"{at} s", SEMI[12], INK, anchor="mm")
                dashed(d, X(at), top + 51, bottom - 8, FAINT)
                text(d, (X(at) + 5, top + 62), label, REG[12], MUTED)

        for j, (label, row) in enumerate(panel["rows"]):
            y = top + ROWS_AT + j * 30
            if label:
                text(d, (T0 - 14, y), label, REG[13], INK, anchor="rm")
            if row == "ticks":
                for c in shown:
                    line(d, [(X(c), y - 9), (X(c), y + 9)], panel["tick"](c), 2.2)
                continue
            for start, end, seg_label, color, light in row:
                if X(min(end, now)) - X(start) < 3:
                    continue
                x0, x1 = X(start), X(min(end, now))
                rect(d, (x0 + 1, y - 10, x1 - 1, y + 10), light, color, 1.2, 4)
                clipped_label(im, (x0 + 8, y), x1 - 6, seg_label, color, light)
            if label == "Open connection" and panel["fails"] is None and now >= 9:
                text(d, (X(9) + 6, y), "closed at 9 s", ITALIC, MUTED)

    _, last_bottom = panel_box(len(PANELS) - 1)
    axis_y = last_bottom + 14
    line(d, [(T0, axis_y), (T1, axis_y)], FAINT, 1.2)
    for s in range(12):
        line(d, [(X(s), axis_y), (X(s), axis_y + 5)], FAINT, 1.2)
        text(d, (X(s), axis_y + 16), f"{s} s", REG[12], MUTED, anchor="mm")
    px = X(now)
    for i in range(len(PANELS)):  # skip each panel's header, where the counter sits
        top, _ = panel_box(i)
        end = panel_box(i + 1)[0] if i + 1 < len(PANELS) else axis_y
        line(d, [(px, top + 52), (px, end)], INK, 1.4)
    rect(d, (px - 32, axis_y + 28, px + 32, axis_y + 48), INK, None, radius=4)
    text(d, (px, axis_y + 38), f"t = {now:.1f} s", SEMI[12], WHITE, anchor="mm")

    legend_y = axis_y + 78
    legend = ((FAINT, "connection worked"), (LEAK, "connection failed"),
              (BLUE, "worked, as app_blue"), (GREEN, "worked, as app_green"))
    x = 40
    for color, label in legend:
        line(d, [(x + 4, legend_y - 8), (x + 4, legend_y + 8)], color, 2.2)
        text(d, (x + 14, legend_y), label, REG[13], MUTED)
        x += 14 + width(d, label, REG[13]) + 32
    return im


def make_rotation_gif():
    sweep = 8.0  # seconds of GIF time for the 11-second run
    frames = [rotation_frame(min(RUN, f / FPS * RUN / sweep)) for f in range(int(sweep * FPS) + 1)]
    small = [f.resize((f.width // S, f.height // S), Image.Resampling.LANCZOS) for f in frames]
    palette = small[-1].quantize(colors=200, method=Image.Quantize.MEDIANCUT)
    pal = [f.quantize(palette=palette, dither=Image.Dither.NONE) for f in small]
    durations = [1000 // FPS] * len(pal)
    durations[-1] = 5000  # hold the last frame
    path = OUT / "rotation.gif"
    pal[0].save(path, save_all=True, append_images=pal[1:], duration=durations, loop=0, optimize=True)
    print(f"rotation.gif: {len(pal)} frames, {path.stat().st_size // 1024} KB")


if __name__ == "__main__":
    make_leak_png()
    make_rotation_gif()
