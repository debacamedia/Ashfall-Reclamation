"""Applies Resource Pack 3.0 to the two level scenes as small text edits.

Run from the project root, after tools/integrate_resource_pack_v3.gd:

    python3 tools/apply_resource_pack_v3.py

The levels are never re-saved by Godot (that rewrites hundreds of unrelated
lines). Instead each level gains:
  - an instance of its levels/<level>/pack3_dressing.tscn (signs, graffiti,
    decals, ambient sound), as one ext_resource and one node line;
and Halden's Crossing some material paths repointed at Pack 3 materials, and
its flat concrete roofs given the tar-paper material.

Re-running is safe: every edit checks whether it's already been made.
"""
import re
from pathlib import Path

M3 = "res://assets/ashfall_pack_v3/materials/"
ENV3 = "res://assets/ashfall_pack_v3/environments/"


def swap_ext_path(text: str, old: str, new: str) -> str:
    """Points an ext_resource at a different file (dropping any uid, which
    would otherwise win over the path)."""
    pattern = re.compile(r'^(\[ext_resource [^\]]*?)( uid="[^"]*")?( path=")' + re.escape(old) + r'(")', re.M)
    if not pattern.search(text):
        assert new in text, f"neither {old} nor {new} found"
        return text
    return pattern.sub(lambda m: m.group(1) + m.group(3) + new + m.group(4), text, count=1)


def add_ext(text: str, line: str) -> str:
    if line in text:
        return text
    last = list(re.finditer(r"^\[ext_resource [^\n]*\]\n", text, re.M))[-1]
    return text[: last.end()] + line + "\n" + text[last.end():]


def add_dressing(text: str, level_dir: str) -> str:
    text = add_ext(text, f'[ext_resource type="PackedScene" path="res://levels/{level_dir}/pack3_dressing.tscn" id="pack3_dressing"]')
    node = '[node name="Pack3Dressing" parent="." instance=ExtResource("pack3_dressing")]'
    if node not in text:
        text = text.rstrip("\n") + "\n\n" + node + "\n"
    return text


def haldens() -> None:
    p = Path("levels/haldens_crossing/haldens_crossing.tscn")
    t = p.read_text()
    t = swap_ext_path(t, "res://assets/materials/brick.tres", M3 + "brick_weathered.tres")
    t = swap_ext_path(t, "res://assets/materials/asphalt.tres", M3 + "asphalt_cracked.tres")
    t = swap_ext_path(t, "res://assets/materials/tent_canvas.tres", M3 + "canvas_tent.tres")
    # Tried and left out (see docs/art/ashfall_pack_v3/INTEGRATION.md):
    # wood_charred (poles look like twisted rope), desert_sand ground (far too
    # bright), the panorama sky (washes the whole scene out)
    # Flat roofs (concrete) → tar paper. Only nodes named Roof; the same
    # concrete material stays everywhere else it's used.
    t = add_ext(t, f'[ext_resource type="Material" path="{M3}roofing_tarpaper.tres" id="pack3_roofing"]')
    concrete = re.search(r'path="res://assets/materials/concrete_stained\.tres" id="([^"]+)"', t).group(1)
    t, n = re.subn(r'(\[node name="Roof" type="MeshInstance3D" parent="Buildings/[^"]+"[^\]]*\]\n(?:[^\[\n][^\n]*\n)*?material_override = )ExtResource\("' + re.escape(concrete) + r'"\)',
                   r'\1ExtResource("pack3_roofing")', t)
    print(f"Halden's Crossing: {n} roofs → tar paper")
    t = add_dressing(t, "haldens_crossing")
    p.write_text(t)


def outpost() -> None:
    p = Path("levels/outpost_17/outpost_17.tscn")
    t = p.read_text()
    t = add_dressing(t, "outpost_17")
    p.write_text(t)


if __name__ == "__main__":
    haldens()
    outpost()
    print("applied")
