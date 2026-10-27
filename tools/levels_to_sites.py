"""Turns the Outpost 17 and Halden's Crossing level scenes into *sites*: the
places themselves (buildings, props, loot, spawners, signs, sounds), with the
level's own infrastructure taken out. The early zone (levels/early_zone/)
instances both sites and supplies that infrastructure once, for the whole
zone: lighting, terrain, the player, HUD, game mode, navigation, structures
and the wind.

Run once from the project root (Increment 15):

    python3 tools/levels_to_sites.py

It's a text edit, like the other level tools: the scenes are never re-saved
by Godot. Node blocks are removed (with their children and any signal
connections), then sub-resources and external resources nothing uses any
more are dropped. Re-running is safe: removed nodes are simply not found.
"""
import re
from pathlib import Path

# Node paths (from the scene root) removed from each level, children included
REMOVE = {
    "levels/outpost_17/outpost_17.tscn": [
        "Lighting", "Terrain", "Player", "HUD", "GameMode", "Navigation",
        "PlayerSpawn", "Arrivals", "Exits", "Ambience", "Structures",
        "Soundscape/DistantWind",  # non-positional: the zone plays it once
    ],
    "levels/haldens_crossing/haldens_crossing.tscn": [
        "Lighting", "Terrain", "Player", "HUD", "GameMode", "Navigation",
        "PlayerSpawn", "Arrivals", "Exits", "Ambience", "Structures",
    ],
}

# Properties set on site nodes: {file: {node path: {property: value}}}.
# Spawners sleep while nobody is within 230 m (EnemySpawner.active_radius),
# so raiders at a site you're far from cost nothing.
SET = {
    "levels/outpost_17/outpost_17.tscn": {"RaiderSpawner": {"active_radius": "230.0"}},
    "levels/haldens_crossing/haldens_crossing.tscn": {
        "RaiderSpawner": {"active_radius": "230.0"},
        "CampSpawner": {"active_radius": "230.0"},
    },
}

# Files only the old levels used
OBSOLETE = [
    "levels/outpost_17/outpost_17_navmesh.tres",
    "levels/outpost_17/outpost_17_environment.tres",
    "levels/haldens_crossing/haldens_crossing_navmesh.tres",
    "levels/haldens_crossing/haldens_crossing_environment.tres",
]

BLOCK = re.compile(r"^\[(\w+)([^\n]*)\]\n", re.M)


def split_blocks(text: str) -> list[dict]:
    """[{kind, head, body}] in file order; the body runs to the next block."""
    starts = list(BLOCK.finditer(text))
    blocks = []
    for i, m in enumerate(starts):
        end = starts[i + 1].start() if i + 1 < len(starts) else len(text)
        blocks.append({"kind": m.group(1), "head": m.group(0), "body": text[m.end():end]})
    return blocks


def attr(head: str, name: str) -> str | None:
    m = re.search(name + r'="([^"]*)"', head)
    return m.group(1) if m else None


def node_path(block: dict) -> str:
    name = attr(block["head"], "name")
    parent = attr(block["head"], "parent")
    if parent is None:
        return ""  # the root
    return name if parent == "." else parent + "/" + name


def convert(path: Path, remove: list[str]) -> tuple[int, int, int]:
    text = path.read_text()
    blocks = split_blocks(text)
    gone = 0
    kept = []
    for b in blocks:
        if b["kind"] == "node":
            p = node_path(b)
            if any(p == r or p.startswith(r + "/") for r in remove):
                gone += 1
                continue
        if b["kind"] == "connection":
            frm, to = attr(b["head"], "from"), attr(b["head"], "to")
            if any(x == r or (x or "").startswith(r + "/") for x in (frm, to) for r in remove):
                continue
        if b["kind"] == "editable":
            p = attr(b["head"], "path")
            if any(p == r or (p or "").startswith(r + "/") for r in remove):
                continue
        kept.append(b)

    # Drop sub-resources and external resources nothing refers to any more
    dropped_sub = dropped_ext = 0
    while True:
        used_text = "".join(b["head"] + b["body"] for b in kept if b["kind"] not in ("ext_resource",))
        changed = False
        out = []
        for b in kept:
            if b["kind"] == "sub_resource":
                rid = attr(b["head"], "id")
                others = used_text.replace(b["head"] + b["body"], "", 1)
                if f'SubResource("{rid}")' not in others:
                    dropped_sub += 1
                    changed = True
                    continue
            out.append(b)
        kept = out
        if not changed:
            break
    used_text = "".join(b["head"] + b["body"] for b in kept if b["kind"] != "ext_resource")
    out = []
    for b in kept:
        if b["kind"] == "ext_resource" and f'ExtResource("{attr(b["head"], "id")}")' not in used_text:
            dropped_ext += 1
            continue
        out.append(b)
    kept = out

    new = "".join(b["head"] + b["body"] for b in kept)
    # Keep exactly one blank line between blocks, like Godot writes them
    new = re.sub(r"\n{3,}", "\n\n", new).rstrip("\n") + "\n"
    if new != text:
        path.write_text(new)
    return gone, dropped_sub, dropped_ext


def set_properties(path: Path, props: dict) -> int:
    """Adds `name = value` lines under node headers (once)."""
    text = path.read_text()
    count = 0
    for node, values in props.items():
        name = node.split("/")[-1]
        parent = "." if "/" not in node else node.rsplit("/", 1)[0]
        m = re.search(r'^\[node name="' + re.escape(name) + r'"[^\]]*parent="' + re.escape(parent) + r'"[^\]]*\]\n', text, re.M)
        assert m, f"{node} not found in {path}"
        body_end = text.find("\n\n", m.end())
        body = text[m.end():body_end]
        # After the script line: properties are applied in order, and the
        # script's own properties don't exist until it's set
        s = re.search(r"^script = [^\n]*\n", body, re.M)
        at = m.end() + (s.end() if s else 0)
        for k, v in values.items():
            if re.search(r"^" + k + r" = ", body, re.M):
                continue
            text = text[:at] + f"{k} = {v}\n" + text[at:]
            count += 1
    path.write_text(text)
    return count


def main() -> None:
    for f, remove in REMOVE.items():
        gone, subs, exts = convert(Path(f), remove)
        print(f"{f}: {gone} nodes removed, {subs} sub-resources and {exts} external resources dropped")
    for f, props in SET.items():
        print(f"{f}: {set_properties(Path(f), props)} properties set")
    for f in OBSOLETE:
        p = Path(f)
        if p.exists():
            p.unlink()
            for extra in (Path(f + ".import"), Path(f + ".uid")):
                if extra.exists():
                    extra.unlink()
            print(f"deleted {f}")


if __name__ == "__main__":
    main()
