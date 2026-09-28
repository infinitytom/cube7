"""《立方-7》第三章以后的区域音乐（同样三层：base / melody / bright，同步无缝循环）。
复用 synth3.py 的采样器（FluidR3_GM，CC-BY 3.0）；缺的乐器采样会自动下载到 tools/sf/。
用法：python3 synth_chapters.py <输出目录> [ab|cc|rs|core|all]
  ab   晶簇深渊：钢片琴 + 竖琴 + 温暖的垫音，F 利底亚，空灵、有回声
  cc   云顶之城：弦乐 + 圆号 + 长笛，D 大调，开阔明亮的“首都”
  rs   锈海：大提琴 + 颤音弦乐 + 低音单簧管，C 小调，荒凉但有希望
  core 星核（终章）：合唱 + 管风琴 + 竖琴，E 大调，庄严温柔
"""
import os, sys
import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
out_dir = sys.argv[1] if len(sys.argv) > 1 else "out"
what = sys.argv[2] if len(sys.argv) > 2 else "all"
sys.argv = [sys.argv[0], out_dir]
import synth3 as S
from synth_boss import fetch

def arp(buf, inst, notes, t0, step, vel, pan, dur=0.8, rel=0.8):
    for k, m in enumerate(notes):
        S.place(buf, S.sample(inst, m, dur, vel, rel), t0 + k * step, pan)

def song(name, bpm, prog, melody, base_fn, melody_fn, bright_fn, wets=(0.3, 0.35, 0.45), gains=(0.5, 1.6, 1.0)):
    beat = 60 / bpm
    bar = beat * 4
    loop = bar * len(prog)
    n = int(loop * 3 * S.SR)
    base = np.zeros((n, 2)); melo = np.zeros((n, 2)); brt = np.zeros((n, 2))
    for rep in range(2):
        t0 = rep * loop
        for bi, (root, kind) in enumerate(prog):
            bt = t0 + bi * bar
            notes = S.chord_notes(root, kind)
            base_fn(base, bt, beat, bar, root, notes, bi)
            melody_fn(melo, bt, beat, bar, melody[bi % len(melody)], notes, bi)
            bright_fn(brt, bt, beat, bar, root, notes, bi)
    stems = {}
    for key, buf, wet, gain in ((name + "_base", base, wets[0], gains[0]), (name + "_melody", melo, wets[1], gains[1]), (name + "_bright", brt, wets[2], gains[2])):
        x = S.reverb(S.hp(buf, 30), wet) * gain
        stems[key] = S.loopify(x, loop)
    for k, v in S.master(stems).items():
        S.write_ogg(k, v)

# ------------------------------------------------------------------ 晶簇深渊
def render_ab():
    F = 41
    prog = [(F, "lyd"), (F, "lyd"), (43, "m7"), (43, "m7"), (46, "maj7"), (45, "m7"), (43, "m7"), (48, "sus"),
            (F, "lyd"), (50, "m7"), (46, "maj7"), (48, "sus"), (45, "m7"), (43, "m7"), (46, "maj7"), (48, "7")]
    mel = [
        [(0, 1.5, 81), (1.5, 0.5, 84), (2, 2, 83)],
        [(0, 1, 81), (1, 1, 77), (2, 2, 76)],
        [(0, 1.5, 79), (1.5, 0.5, 81), (2, 1, 82), (3, 1, 81)],
        [(0, 3, 77), (3, 1, 74)],
        [(0, 1.5, 76), (1.5, 0.5, 77), (2, 2, 81)],
        [(0, 1, 84), (1, 1, 81), (2, 2, 76)],
        [(0, 2, 79), (2, 1, 77), (3, 1, 74)],
        [(0, 4, 79)],
        [(0, 1, 84), (1, 1, 83), (2, 1, 81), (3, 1, 79)],
        [(0, 2, 81), (2, 2, 77)],
        [(0, 1.5, 81), (1.5, 0.5, 82), (2, 2, 86)],
        [(0, 3, 84), (3, 1, 81)],
        [(0, 1, 84), (1, 1, 81), (2, 1, 76), (3, 1, 81)],
        [(0, 2, 79), (2, 2, 74)],
        [(0, 1.5, 76), (1.5, 0.5, 79), (2, 2, 81)],
        [(0, 4, 79)],
    ]
    def base_fn(b, bt, beat, bar, root, notes, bi):
        r = root - 12
        S.place(b, S.sample("acoustic_bass", r, bar * 0.9, 0.5, 0.6), bt, 0.0)
        for m in S.voice(notes, 53, 67):
            S.place(b, S.sample("pad_2_warm", m, bar * 1.05, 0.16, 1.2), bt, S.rng.uniform(-0.4, 0.4))
        hp = S.voice(notes, 60, 79)
        arp(b, "orchestral_harp", hp + hp[::-1][1:3], bt, beat / 2, 0.22, -0.3, 0.9, 1.0)
    def mel_fn(m, bt, beat, bar, phrase, notes, bi):
        for (bb, d, mm) in phrase:
            S.place(m, S.sample("celesta", mm, d * beat, 0.42, 1.2), bt + bb * beat, 0.2)
            S.place(m, S.sample("vibraphone", mm - 12, d * beat, 0.16, 1.0), bt + bb * beat + beat * 0.02, -0.2)
    def br_fn(br, bt, beat, bar, root, notes, bi):
        for m in S.voice(notes, 57, 74):
            S.place(br, S.sample("string_ensemble_1", m, bar * 1.02, 0.14, 1.0), bt, S.rng.uniform(-0.5, 0.5))
        if bi % 2 == 1:
            hi = S.voice(notes, 84, 98)
            arp(br, "celesta", hi, bt + beat * 2, beat / 3, 0.2, 0.5, 0.5, 1.2)
    song("ab", 84, prog, mel, base_fn, mel_fn, br_fn, wets=(0.35, 0.42, 0.5))

# ------------------------------------------------------------------ 云顶之城
def render_cc():
    D = 38
    prog = [(D, "maj"), (43, "maj"), (45, "maj"), (D, "maj"), (47, "m7"), (43, "maj7"), (45, "sus"), (45, "7"),
            (D, "maj"), (42, "m7"), (43, "maj7"), (45, "maj"), (47, "m7"), (45, "7"), (43, "maj"), (45, "7")]
    mel = [
        [(0, 1, 74), (1, 1, 78), (2, 2, 81)],
        [(0, 1.5, 83), (1.5, 0.5, 81), (2, 2, 79)],
        [(0, 1, 76), (1, 1, 81), (2, 1, 85), (3, 1, 81)],
        [(0, 4, 78)],
        [(0, 1, 79), (1, 1, 78), (2, 1, 76), (3, 1, 74)],
        [(0, 2, 79), (2, 2, 83)],
        [(0, 1.5, 81), (1.5, 0.5, 79), (2, 2, 76)],
        [(0, 3, 76), (3, 1, 73)],
        [(0, 1, 74), (1, 1, 78), (2, 1, 81), (3, 1, 86)],
        [(0, 2, 85), (2, 2, 81)],
        [(0, 1.5, 83), (1.5, 0.5, 86), (2, 2, 88)],
        [(0, 2, 85), (2, 2, 81)],
        [(0, 1, 83), (1, 1, 81), (2, 1, 79), (3, 1, 78)],
        [(0, 2, 76), (2, 2, 79)],
        [(0, 1.5, 78), (1.5, 0.5, 79), (2, 2, 83)],
        [(0, 4, 81)],
    ]
    def base_fn(b, bt, beat, bar, root, notes, bi):
        r = root if root < 44 else root - 12
        for bb, off, v in [(0, 0, 0.55), (1.5, 7, 0.35), (2, 12, 0.4), (3, 7, 0.35)]:
            S.place(b, S.sample("contrabass", r + off, beat * 0.9, v, 0.2), bt + bb * beat, 0.0)
        for k in range(8):
            ns = S.voice(notes, 62, 76)
            S.place(b, S.sample("pizzicato_strings", ns[k % len(ns)], 0.3, 0.26, 0.3), bt + k * beat / 2, -0.3 if k % 2 else 0.3)
        for bb, v in [(0, 0.45), (2, 0.35)]:
            S.place(b, S.soft_kick(v), bt + bb * beat, 0.0)
    def mel_fn(m, bt, beat, bar, phrase, notes, bi):
        for (bb, d, mm) in phrase:
            S.place(m, S.sample("flute", mm, d * beat * 0.95, 0.4, 0.3), bt + bb * beat, 0.15)
            if bi >= 8:
                S.place(m, S.sample("french_horn", mm - 12, d * beat * 0.9, 0.3, 0.3), bt + bb * beat, -0.2)
    def br_fn(br, bt, beat, bar, root, notes, bi):
        for mm in S.voice(notes, 57, 76):
            S.place(br, S.sample("string_ensemble_1", mm, bar * 1.02, 0.17, 1.0), bt, S.rng.uniform(-0.5, 0.5))
        if bi % 4 == 3:
            hi = S.voice(notes, 72, 91)
            arp(br, "orchestral_harp", hi, bt + beat * 2, beat / 4, 0.25, 0.4, 0.6, 1.0)
    song("cc", 96, prog, mel, base_fn, mel_fn, br_fn, wets=(0.25, 0.32, 0.42))

# ------------------------------------------------------------------ 锈海
def render_rs():
    Cc = 36
    prog = [(Cc, "m"), (Cc, "m"), (44, "maj"), (43, "7"), (Cc, "m"), (41, "m"), (43, "sus"), (43, "7"),
            (44, "maj7"), (46, "maj"), (Cc, "m"), (41, "m7"), (44, "maj"), (46, "maj"), (43, "sus"), (43, "7")]
    mel = [
        [(0, 2, 72), (2, 1, 75), (3, 1, 74)],
        [(0, 3, 72), (3, 1, 67)],
        [(0, 1.5, 68), (1.5, 0.5, 72), (2, 2, 75)],
        [(0, 2, 74), (2, 2, 71)],
        [(0, 2, 72), (2, 1, 75), (3, 1, 79)],
        [(0, 3, 77), (3, 1, 75)],
        [(0, 1.5, 74), (1.5, 0.5, 72), (2, 2, 71)],
        [(0, 4, 67)],
        [(0, 1, 75), (1, 1, 79), (2, 2, 80)],
        [(0, 2, 79), (2, 2, 77)],
        [(0, 1.5, 75), (1.5, 0.5, 74), (2, 2, 72)],
        [(0, 3, 72), (3, 1, 68)],
        [(0, 1, 72), (1, 1, 75), (2, 2, 80)],
        [(0, 2, 82), (2, 2, 79)],
        [(0, 2, 77), (2, 2, 74)],
        [(0, 4, 74)],
    ]
    def base_fn(b, bt, beat, bar, root, notes, bi):
        r = root - 12 if root > 40 else root
        S.place(b, S.sample("cello", r + 12, bar * 0.95, 0.35, 0.6), bt, -0.1)
        S.place(b, S.sample("contrabass", r, bar * 0.95, 0.35, 0.6), bt, 0.1)
        for mm in S.voice(notes, 55, 70):
            S.place(b, S.sample("tremolo_strings", mm, bar * 1.02, 0.12, 1.0), bt, S.rng.uniform(-0.5, 0.5))
        S.place(b, S.sample("timpani", r + 12, beat, 0.25, 0.8), bt, 0.0)
    def mel_fn(m, bt, beat, bar, phrase, notes, bi):
        for (bb, d, mm) in phrase:
            S.place(m, S.sample("clarinet", mm - 12, d * beat * 0.95, 0.45, 0.3), bt + bb * beat, 0.1)
    def br_fn(br, bt, beat, bar, root, notes, bi):
        for mm in S.voice(notes, 60, 79):
            S.place(br, S.sample("choir_aahs", mm, bar * 1.02, 0.14, 1.2), bt, S.rng.uniform(-0.4, 0.4))
        if bi % 2 == 0:
            hi = S.voice(notes, 72, 88)
            arp(br, "orchestral_harp", hi, bt + beat, beat / 2, 0.2, -0.4, 0.8, 1.0)
    song("rs", 72, prog, mel, base_fn, mel_fn, br_fn, wets=(0.35, 0.35, 0.5))

# ------------------------------------------------------------------ 星核（终章）
def render_core():
    E = 40
    prog = [(E, "maj"), (47, "maj"), (49, "m7"), (45, "maj7"), (E, "maj"), (42, "m7"), (45, "maj7"), (47, "sus"),
            (E, "maj"), (44, "m7"), (45, "maj7"), (47, "maj"), (49, "m7"), (45, "maj7"), (47, "sus"), (47, "7")]
    mel = [
        [(0, 2, 76), (2, 1, 80), (3, 1, 83)],
        [(0, 3, 82), (3, 1, 78)],
        [(0, 1.5, 80), (1.5, 0.5, 78), (2, 2, 76)],
        [(0, 4, 76)],
        [(0, 1, 76), (1, 1, 80), (2, 1, 83), (3, 1, 88)],
        [(0, 3, 85), (3, 1, 81)],
        [(0, 2, 83), (2, 2, 80)],
        [(0, 4, 78)],
        [(0, 1.5, 80), (1.5, 0.5, 83), (2, 2, 88)],
        [(0, 2, 87), (2, 2, 83)],
        [(0, 1.5, 85), (1.5, 0.5, 83), (2, 2, 81)],
        [(0, 3, 83), (3, 1, 78)],
        [(0, 1, 80), (1, 1, 83), (2, 2, 88)],
        [(0, 2, 88), (2, 2, 85)],
        [(0, 2, 83), (2, 2, 81)],
        [(0, 4, 80)],
    ]
    def base_fn(b, bt, beat, bar, root, notes, bi):
        for mm in S.voice(notes, 48, 64):
            S.place(b, S.sample("church_organ", mm, bar * 1.0, 0.14, 0.8), bt, S.rng.uniform(-0.3, 0.3))
        S.place(b, S.sample("contrabass", root - 12 if root > 44 else root, bar * 0.9, 0.35, 0.8), bt, 0.0)
        hp = S.voice(notes, 64, 83)
        arp(b, "orchestral_harp", hp + hp[::-1][1:], bt, beat / 2, 0.2, 0.3, 0.9, 1.0)
    def mel_fn(m, bt, beat, bar, phrase, notes, bi):
        for (bb, d, mm) in phrase:
            S.place(m, S.sample("choir_aahs", mm - 12, d * beat, 0.34, 0.8), bt + bb * beat, -0.1)
            S.place(m, S.sample("flute", mm, d * beat * 0.9, 0.24, 0.4), bt + bb * beat, 0.2)
    def br_fn(br, bt, beat, bar, root, notes, bi):
        for mm in S.voice(notes, 57, 76):
            S.place(br, S.sample("string_ensemble_1", mm, bar * 1.02, 0.18, 1.0), bt, S.rng.uniform(-0.5, 0.5))
        if bi % 2 == 1:
            arp(br, "celesta", S.voice(notes, 84, 98), bt + beat * 2, beat / 3, 0.2, -0.4, 0.5, 1.2)
    song("core", 76, prog, mel, base_fn, mel_fn, br_fn, wets=(0.4, 0.42, 0.5))

if __name__ == "__main__":
    S.OUT = out_dir
    os.makedirs(S.OUT, exist_ok=True)
    need = {
        "ab": [("celesta", 70, 100), ("vibraphone", 60, 90), ("orchestral_harp", 55, 100), ("pad_2_warm", 50, 72), ("acoustic_bass", 26, 50), ("string_ensemble_1", 55, 78)],
        "cc": [("flute", 70, 92), ("french_horn", 55, 80), ("contrabass", 24, 55), ("pizzicato_strings", 60, 80), ("string_ensemble_1", 55, 78), ("orchestral_harp", 70, 95)],
        "rs": [("cello", 36, 60), ("contrabass", 24, 50), ("tremolo_strings", 52, 80), ("timpani", 36, 55), ("clarinet", 52, 72), ("choir_aahs", 58, 80), ("orchestral_harp", 70, 90)],
        "core": [("church_organ", 46, 66), ("contrabass", 26, 50), ("orchestral_harp", 62, 86), ("choir_aahs", 60, 80), ("flute", 74, 92), ("string_ensemble_1", 55, 78), ("celesta", 82, 100)],
    }
    todo = ["ab", "cc", "rs", "core"] if what == "all" else [what]
    for name in todo:
        for inst, lo, hi in need[name]:
            fetch(inst, lo, hi)
        {"ab": render_ab, "cc": render_cc, "rs": render_rs, "core": render_core}[name]()
