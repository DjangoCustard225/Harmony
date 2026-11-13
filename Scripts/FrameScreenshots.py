#!/usr/bin/env python3
"""Puts raw iPhone screenshots in a device frame for App Store and social images.

Usage: python3 Scripts/FrameScreenshots.py [raw_dir] [out_dir]

Reads every PNG in raw_dir (default screenshots/raw), draws a titanium iPhone frame with a
Dynamic Island around it on a tinted background with a caption, and writes 1320x2868 PNGs
(the App Store's 6.9-inch size) to out_dir (default screenshots/out). Needs only ffmpeg.
Edit CAPTIONS to change the text and colors; files without an entry get a neutral style.
"""
import pathlib
import subprocess
import sys

CANVAS_W, CANVAS_H = 1320, 2868
SCREEN_W = 1000
BEZEL = 22
SCREEN_RADIUS = 140
TOP_MARGIN = 520
FONT = "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"
SUBFONT = "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"

# file stem: (title, subtitle, background top RGB, glow RGB)
CAPTIONS = {
    "1-albums": ("Browse by album", "Artwork-first library of your own music", (22, 28, 40), (70, 90, 130)),
    "2-songs": ("Every song, offline", "Fast, clean and always available", (14, 34, 36), (40, 110, 110)),
    "3-now-playing": ("Now playing, in color", "Colors flow from the album artwork", (70, 10, 20), (190, 40, 55)),
    "4-lyrics": ("Lyrics in sync", "Follow along line by line", (30, 18, 96), (95, 70, 220)),
}
DEFAULT = ("Harmony", "Offline music player", (20, 20, 24), (80, 80, 100))


def sdf_alpha(half_w: float, half_h: float, radius: float) -> str:
    """geq expression: rounded-rectangle coverage 0...1 and inside distance, anti-aliased."""
    qx = f"(abs(X+0.5-{half_w})-({half_w}-{radius}))"
    qy = f"(abs(Y+0.5-{half_h})-({half_h}-{radius}))"
    return f"(hypot(max({qx},0),max({qy},0))+min(max({qx},{qy}),0)-{radius})"


def filter_graph(title: str, subtitle: str, top, glow) -> str:
    screen_h = round(SCREEN_W * 2556 / 1179)
    dev_w, dev_h = SCREEN_W + 2 * BEZEL, screen_h + 2 * BEZEL
    dev_x, dev_y = (CANVAS_W - dev_w) // 2, TOP_MARGIN
    outer = SCREEN_RADIUS + BEZEL
    island_w, island_h = 314, 92
    d_screen = sdf_alpha(SCREEN_W / 2, screen_h / 2, SCREEN_RADIUS)
    d_body = sdf_alpha(dev_w / 2, dev_h / 2, outer)
    d_island = sdf_alpha(island_w / 2, island_h / 2, island_h / 2)
    # Frame colors by depth from the outer edge: bright titanium rim, dark band, black bezel.
    depth = f"(-{d_body})"
    rim = f"if(lt({depth},3.5),150,if(lt({depth},9),44,6))"

    def channel(base_top: int, glow_c: int) -> str:
        fade = f"clip(1-hypot(X-{CANVAS_W / 2},Y-{TOP_MARGIN + screen_h * 0.45})/1500,0,1)"
        vertical = f"({base_top}*(1-Y/{CANVAS_H}*0.85))"
        return f"{vertical}+({glow_c}*0.42*{fade}*{fade})"

    bg = (
        f"color=c=black:s={CANVAS_W}x{CANVAS_H}:d=1,format=gbrp,"
        f"geq=r='{channel(top[0], glow[0])}':g='{channel(top[1], glow[1])}':b='{channel(top[2], glow[2])}',"
        f"format=rgba"
    )
    buttons = ",".join(
        f"drawbox=x={x}:y={dev_y + y}:w={w}:h={h}:color=0x77777c:t=fill"
        for x, y, w, h in [
            (dev_x - 7, 330, 9, 76),  # action button
            (dev_x - 7, 470, 9, 140),  # volume up
            (dev_x - 7, 640, 9, 140),  # volume down
            (dev_x + dev_w - 2, 600, 9, 220),  # side button
        ]
    )
    body = (
        f"color=c=black:s={dev_w}x{dev_h}:d=1,format=gbrap,"
        f"geq=r='{rim}':g='{rim}':b='{rim}+3':a='255*clip(0.5-{d_body},0,1)'"
    )
    screen = (
        f"scale={SCREEN_W}:{screen_h}:flags=lanczos,format=gbrap,"
        f"geq=r='r(X,Y)':g='g(X,Y)':b='b(X,Y)':a='255*clip(0.5-{d_screen},0,1)'"
    )
    island = (
        f"color=c=black:s={island_w}x{island_h}:d=1,format=gbrap,"
        f"geq=r='0':g='0':b='0':a='255*clip(0.5-{d_island},0,1)'"
    )
    text = (
        f"drawtext=fontfile={FONT}:text='{title}':fontsize=84:fontcolor=white:x=(w-text_w)/2:y=170,"
        f"drawtext=fontfile={SUBFONT}:text='{subtitle}':fontsize=44:fontcolor=0xC4C4CE:x=(w-text_w)/2:y=300"
    )
    return (
        f"{bg},{buttons}[canvas];"
        f"{body},split[b1][b2];"
        f"[b1]colorchannelmixer=rr=0:gg=0:bb=0:aa=0.6,gblur=sigma=38[shadow];"
        f"[0:v]{screen}[scr];"
        f"{island}[isl];"
        f"[canvas][shadow]overlay=x={dev_x}:y={dev_y + 36}:format=auto[c1];"
        f"[c1][b2]overlay=x={dev_x}:y={dev_y}:format=auto[c2];"
        f"[c2][scr]overlay=x={dev_x + BEZEL}:y={dev_y + BEZEL}:format=auto[c3];"
        f"[c3][isl]overlay=x={dev_x + (dev_w - island_w) // 2}:y={dev_y + BEZEL + 28}:format=auto,"
        f"{text},format=rgb24"
    )


def main() -> int:
    root = pathlib.Path(__file__).resolve().parent.parent
    raw = pathlib.Path(sys.argv[1]) if len(sys.argv) > 1 else root / "screenshots/raw"
    out = pathlib.Path(sys.argv[2]) if len(sys.argv) > 2 else root / "screenshots/out"
    out.mkdir(parents=True, exist_ok=True)
    files = sorted(raw.glob("*.png"))
    if not files:
        print(f"No PNG screenshots in {raw}")
        return 1
    for file in files:
        title, subtitle, top, glow = CAPTIONS.get(file.stem, DEFAULT)
        target = out / f"{file.stem}-framed.png"
        command = [
            "ffmpeg", "-y", "-loglevel", "error", "-i", str(file),
            "-filter_complex", filter_graph(title, subtitle, top, glow),
            "-frames:v", "1", str(target),
        ]  # fmt: skip
        result = subprocess.run(command, capture_output=True, text=True)
        if result.returncode != 0:
            print(f"{file.name}: failed\n{result.stderr}")
            return result.returncode
        print(f"{file.name} -> {target}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
