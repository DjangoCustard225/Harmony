#!/usr/bin/env python3
"""Render Harmony's vector icon as an opaque PNG for builds without Icon Composer."""

import json
import shutil
import subprocess
import xml.etree.ElementTree as ET
from pathlib import Path

root = Path(__file__).resolve().parent.parent
icon = root / "HarmonyIcon.icon"
config = json.loads((icon / "icon.json").read_text())
ET.register_namespace("", "http://www.w3.org/2000/svg")
ns = "{http://www.w3.org/2000/svg}"
svg = ET.Element(ns + "svg", width="1024", height="1024", viewBox="0 0 1024 1024")
ET.SubElement(svg, ns + "title").text = "Harmony — musical note"
defs = ET.SubElement(svg, ns + "defs")
gradient = ET.SubElement(defs, ns + "linearGradient", id="background", x1="0", y1="0", x2="1", y2="1")
default_fill = config.get("fill")
if default_fill is None:
    for entry in config.get("fill-specializations", []):
        if "appearance" not in entry or entry["appearance"] == "light":
            default_fill = entry["value"]
            break
colors = default_fill["linear-gradient"]
for index, color in enumerate(colors):
    components = [float(value) for value in color.removeprefix("srgb:").split(",")]
    rgb = "#" + "".join(f"{round(value * 255):02x}" for value in components[:3])
    ET.SubElement(gradient, ns + "stop", offset=str(index / (len(colors) - 1)), **{"stop-color": rgb})
ET.SubElement(svg, ns + "rect", width="1024", height="1024", fill="url(#background)")
for group in config["groups"]:
    for layer in group["layers"]:
        source = ET.parse(icon / "Assets" / layer["image-name"]).getroot()
        for element in source:
            if element.tag != ns + "title":
                svg.append(element)
source_path = root / "AppIcon.svg"
ET.indent(svg, space="  ")
ET.ElementTree(svg).write(source_path, encoding="unicode")
with source_path.open("a") as output:
    output.write("\n")
subprocess.run([
    "ffmpeg", "-hide_banner", "-loglevel", "error", "-y", "-i", str(source_path),
    "-frames:v", "1", "-pix_fmt", "rgb24", str(root / "AppIcon.png")
], check=True)
shutil.copyfile(root / "AppIcon.png", root / "Harmony/Assets.xcassets/AppIcon.appiconset/AppIcon.png")
print("Rendered opaque 1024 × 1024 Harmony icon from the native vector layers.")

# Use the same silhouette for the small in-app brand mark.
mark = root / "Harmony/Assets.xcassets/HarmonyMark.imageset"
mark.mkdir(parents=True, exist_ok=True)
(mark / "Contents.json").write_text(json.dumps({
    "images": [{"filename": "HarmonyMark.png", "idiom": "universal"}],
    "info": {"author": "xcode", "version": 1},
    "properties": {"template-rendering-intent": "template"}
}, indent=2) + "\n")
subprocess.run([
    "ffmpeg", "-hide_banner", "-loglevel", "error", "-y",
    "-i", str(icon / "Assets/MusicNote.svg"), "-vf", "scale=256:256",
    "-frames:v", "1", "-pix_fmt", "rgba", str(mark / "HarmonyMark.png")
], check=True)
