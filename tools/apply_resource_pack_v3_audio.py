"""Points the game's sounds at Resource Pack 3 (as text edits of resource
paths in scenes and item resources; no scene is re-saved by Godot).

Run from the project root, after tools/integrate_resource_pack_v3.gd (which
makes the sets):

    python3 tools/apply_resource_pack_v3_audio.py

Left as they are (the pack's versions measured badly; see
docs/art/ashfall_pack_v3/INTEGRATION.md): gunshots, raider voices, the
player's hurt grunts, the heartbeat, the death sting, wind, the marksman
reload, target pings. Re-running is safe.
"""
import re
from pathlib import Path

A = "res://assets/audio/"
P3 = "res://assets/ashfall_pack_v3/"

# Per file first (they win over the general mapping below)
PER_FILE = {
    "scenes/world/containers/footlocker.tscn": {
        A + "locker_open.wav": P3 + "audio/locker_open.wav",
        A + "sets/ladder_step.tres": P3 + "audio/locker_close.wav",  # was borrowed as the lid's clang
    },
    "scenes/world/containers/weapons_locker.tscn": {
        A + "locker_open.wav": P3 + "audio/locker_open.wav",
        A + "sets/ladder_step.tres": P3 + "audio/locker_close.wav",
    },
    "scenes/world/containers/supply_crate.tscn": {
        A + "crate_open.wav": P3 + "audio/crate_open.wav",
        A + "crate_close.wav": P3 + "audio/crate_close.wav",
    },
    "resources/items/medkit.tres": {A + "heal.wav": P3 + "audio/heal_medkit.wav"},
    "resources/items/bandage.tres": {A + "heal.wav": P3 + "audio/heal_bandage.wav"},
    "scenes/weapons/pipe_pistol.tscn": {A + "pistol_reload.wav": P3 + "audio/pipe_pistol_reload.wav"},
    "scenes/world/props/burning_barrel.tscn": {A + "fire_loop.wav": P3 + "derived/amb_fire_barrel_loop.wav"},
    # The machete's blade biting, rather than the generic flesh impact
    "scenes/weapons/machete.tscn": {
        A + "sets/impact_flesh.tres": P3 + "sets/machete_hit.tres",
        P3 + "sets/impact_flesh.tres": P3 + "sets/machete_hit.tres",
    },
}

GENERAL = {
    A + "pickup_soft.wav": P3 + "sets/pickup_soft.tres",
    A + "pickup_metal.wav": P3 + "sets/pickup_metal.tres",
    A + "pickup_ammo.wav": P3 + "sets/pickup_ammo.tres",
    A + "pickup_weapon.wav": P3 + "sets/pickup_weapon.tres",
    A + "rifle_dry_fire.wav": P3 + "sets/dry_fire.tres",
    A + "rummage.wav": P3 + "sets/rummage.tres",
    A + "melee_swing.wav": P3 + "sets/machete_swing.tres",
    A + "weapon_draw.wav": P3 + "sets/weapon_draw.tres",
    A + "aim_in.wav": P3 + "sets/aim_in.tres",
    A + "land.wav": P3 + "sets/land.tres",
    A + "sets/ladder_step.tres": P3 + "sets/ladder_step.tres",
    A + "shell_insert.wav": P3 + "sets/shell_insert.tres",
    A + "shotgun_pump.wav": P3 + "audio/shotgun_pump.wav",
    A + "bolt_cycle.wav": P3 + "audio/marksman_bolt_cycle.wav",
    A + "rifle_reload.wav": P3 + "audio/rifle_reload.wav",
    A + "pistol_reload.wav": P3 + "audio/pistol_reload.wav",
    A + "sets/impact_flesh.tres": P3 + "sets/impact_flesh.tres",
    A + "sets/impact_dirt.tres": P3 + "sets/impact_dirt.tres",
    A + "sets/footstep_gravel.tres": P3 + "sets/footstep_gravel.tres",
}

EXT = re.compile(r'^(\[ext_resource [^\]]*?)( uid="[^"]*")?( path=")([^"]+)(")', re.M)


def apply(path: Path, mapping: dict) -> int:
    text = path.read_text()
    count = 0

    def sub(m: re.Match) -> str:
        nonlocal count
        new = mapping.get(m.group(4))
        if new is None:
            return m.group(0)
        count += 1
        return m.group(1) + m.group(3) + new + m.group(5)  # uid dropped: the path decides

    text = EXT.sub(sub, text)
    if count:
        path.write_text(text)
    return count


def main() -> None:
    total = 0
    for f, mapping in PER_FILE.items():
        total += apply(Path(f), mapping)
    for root in ("scenes", "resources", "levels"):
        for f in Path(root).rglob("*.t*"):
            if f.suffix in (".tscn", ".tres") and "ashfall_pack" not in str(f):
                total += apply(f, GENERAL)
    # The HUD's own sounds are constants in its script
    hud = Path("scripts/ui/hud.gd")
    t = hud.read_text()
    for old, new in ((A + "ui_hit.wav", P3 + "audio/ui_hitmarker.wav"),
                     (A + "ui_kill.wav", P3 + "audio/ui_kill_confirm.wav"),
                     (A + "ui_denied.wav", P3 + "audio/ui_denied.wav")):
        if old in t:
            t = t.replace(old, new)
            total += 1
    hud.write_text(t)
    print(f"{total} sound references now use Pack 3")


if __name__ == "__main__":
    main()
