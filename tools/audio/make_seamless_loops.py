"""Seamless loop versions of the Resource Pack ambient sounds.

The pack's generator_idle, radio_static and distant_wind WAVs fade in and out
(about 0.1 s), so looping them directly dips every few seconds. This writes
crossfaded copies to assets/audio/loops/ (the pack's own files are left as
shipped). Run from the project root:

    python3 tools/audio/make_seamless_loops.py
"""
import math
import struct
import wave
from pathlib import Path

SRC = Path("assets/ashfall_pack_v1/audio")
DST = Path("assets/audio/loops")
TRIM = 0.15      # seconds cut from each end (the fades)
CROSSFADE = 0.6  # seconds blended across the loop point


def make_loop(name: str) -> None:
    with wave.open(str(SRC / f"{name}.wav")) as w:
        rate = w.getframerate()
        assert w.getnchannels() == 1 and w.getsampwidth() == 2
        data = w.readframes(w.getnframes())
    s = struct.unpack(f"<{len(data) // 2}h", data)
    t = s[int(rate * TRIM): len(s) - int(rate * TRIM)]
    n = len(t)
    f = int(rate * CROSSFADE)
    out = list(t[f:n - f])
    # Equal-power crossfade: the tail fades out while the head fades in, so
    # the end of the file flows straight into its start.
    for i in range(f):
        a = (i + 0.5) / f
        v = t[n - f + i] * math.cos(a * math.pi / 2) + t[i] * math.sin(a * math.pi / 2)
        out.append(max(-32768, min(32767, int(round(v)))))
    DST.mkdir(parents=True, exist_ok=True)
    with wave.open(str(DST / f"{name}_loop.wav"), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(rate)
        w.writeframes(struct.pack(f"<{len(out)}h", *out))
    print(f"{name}_loop.wav  {len(out) / rate:.2f} s")


if __name__ == "__main__":
    for n in ("generator_idle", "radio_static", "distant_wind"):
        make_loop(n)
