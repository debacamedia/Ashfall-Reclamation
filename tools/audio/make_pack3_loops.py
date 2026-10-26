"""Seamless loop versions of two Resource Pack 3 ambient sounds.

amb_fire_barrel ends on a different sample than it starts (a click every
loop) and amb_insects nearly so. This writes crossfaded copies to
assets/ashfall_pack_v3/derived/ (the pack's own files are left as shipped).
Run from the project root:

    python3 tools/audio/make_pack3_loops.py
"""
import struct
import wave
from pathlib import Path

SRC = Path("assets/ashfall_pack_v3/audio")
DST = Path("assets/ashfall_pack_v3/derived")
CROSSFADE = 0.8  # seconds blended across the loop point


def make_loop(name: str) -> None:
    with wave.open(str(SRC / f"{name}.wav")) as w:
        rate = w.getframerate()
        assert w.getnchannels() == 1 and w.getsampwidth() == 2
        data = w.readframes(w.getnframes())
    s = struct.unpack(f"<{len(data) // 2}h", data)
    n = len(s)
    f = int(rate * CROSSFADE)
    # The tail fades out over the head: the loop's last sample leads into its first
    out = list(s[f:n])
    for i in range(f):
        a = i / f
        out[n - 2 * f + i] = int(out[n - 2 * f + i] * (1.0 - a) + s[i] * a)
    out = out[: n - f]
    DST.mkdir(parents=True, exist_ok=True)
    with wave.open(str(DST / f"{name}_loop.wav"), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(rate)
        w.writeframes(struct.pack(f"<{len(out)}h", *[max(-32768, min(32767, v)) for v in out]))
    print(f"{name}_loop.wav: {len(out) / rate:.1f} s, ends {out[-1]} → starts {out[0]}")


if __name__ == "__main__":
    for name in ("amb_fire_barrel", "amb_insects"):
        make_loop(name)
