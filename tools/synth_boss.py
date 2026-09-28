"""《立方-7》Boss 战配乐：「熔炉守卫」。
复用 synth3.py 的采样器和混音（FluidR3_GM 采样，CC-BY 3.0）。
第一次运行会从 gleitz/midi-js-soundfonts 下载需要的乐器采样到 tools/sf/。
用法：python3 synth_boss.py <输出目录>
分三层（和区域音乐一样同步循环）：
  base   = 定音鼓 + 太鼓的机械节奏 + 低音提琴的顽固低音（像锻锤一下一下砸）
  melody = 圆号 / 长号的主题（厚重、有点滑稽的“老总管”）
  bright = 震音弦乐 + 合唱（最后一阶段全开）
"""
import os, sys, urllib.request
import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.argv = [sys.argv[0], sys.argv[1] if len(sys.argv) > 1 else "out"]
import synth3 as S

NAMES = ["C", "Db", "D", "Eb", "E", "F", "Gb", "G", "Ab", "A", "Bb", "B"]

def fetch(inst, lo, hi):
    d = os.path.join(S.SF, inst)
    os.makedirs(d, exist_ok=True)
    for m in range(lo, hi + 1):
        path = os.path.join(d, f"{m}.mp3")
        if os.path.exists(path) and os.path.getsize(path) > 500:
            continue
        note = f"{NAMES[m % 12]}{m // 12 - 1}"
        url = f"https://raw.githubusercontent.com/gleitz/midi-js-soundfonts/gh-pages/FluidR3_GM/{inst}-mp3/{note}.mp3"
        try:
            urllib.request.urlretrieve(url, path)
        except Exception as e:
            print("skip", inst, note, e)

def render_boss():
    bpm = 132
    beat = 60 / bpm
    bar = beat * 4
    # D 小调，带一点弗里几亚的降二级（Eb）——紧张但不阴森
    D = 38
    prog = [(D, "m"), (D, "m"), (39, "maj"), (D, "m"),
            (46, "maj"), (45, "7"), (D, "m"), (45, "7"),
            (D, "m"), (41, "maj"), (43, "m"), (45, "7"),
            (46, "maj"), (43, "m"), (45, "sus"), (45, "7")]
    horn = [
        [(0, 1.5, 62), (1.5, 0.5, 65), (2, 1, 69), (3, 1, 67)],
        [(0, 2, 65), (2, 1, 64), (3, 1, 62)],
        [(0, 1.5, 63), (1.5, 0.5, 67), (2, 2, 70)],
        [(0, 3, 69), (3, 1, 65)],
        [(0, 1, 70), (1, 1, 69), (2, 1, 65), (3, 1, 62)],
        [(0, 1.5, 64), (1.5, 0.5, 67), (2, 2, 73)],
        [(0, 1, 74), (1, 1, 72), (2, 1, 69), (3, 1, 65)],
        [(0, 4, 69)],
        [(0, 0.5, 62), (0.5, 0.5, 65), (1, 1, 69), (2, 1, 74), (3, 1, 72)],
        [(0, 2, 72), (2, 1, 69), (3, 1, 65)],
        [(0, 1.5, 70), (1.5, 0.5, 69), (2, 2, 67)],
        [(0, 1, 69), (1, 1, 73), (2, 2, 76)],
        [(0, 1.5, 77), (1.5, 0.5, 74), (2, 2, 70)],
        [(0, 1.5, 70), (1.5, 0.5, 69), (2, 2, 67)],
        [(0, 2, 69), (2, 2, 74)],
        [(0, 3, 73), (3, 1, 69)],
    ]
    loop = bar * len(prog)
    n = int(loop * 3 * S.SR)
    base = np.zeros((n, 2)); melo = np.zeros((n, 2)); brt = np.zeros((n, 2))
    for rep in range(2):
        t0 = rep * loop
        for bi, (root, kind) in enumerate(prog):
            bt = t0 + bi * bar
            notes = S.chord_notes(root, kind)
            r = root if root < 44 else root - 12
            # --- base：锻锤节奏（底鼓 1、1.75、3，定音鼓强调 2、4），低音提琴八分音符顽固低音
            for b, v in [(0, 0.9), (0.75, 0.5), (2, 0.8), (2.75, 0.4), (3.5, 0.45)]:
                S.place(base, S.soft_kick(v), bt + b * beat, 0.0)
            for b in [1, 3]:
                S.place(base, S.sample("timpani", r + 12, beat * 0.6, 0.55, 0.3), bt + b * beat, -0.1)
            if bi % 4 == 3:
                for k in range(4):
                    S.place(base, S.sample("timpani", r + 12, beat * 0.2, 0.3 + k * 0.08, 0.2), bt + (3 + k * 0.25) * beat, 0.1)
            for k in range(8):
                m = r + (0 if k % 2 == 0 else (12 if k % 4 == 1 else 7))
                S.place(base, S.sample("contrabass", m, beat * 0.42, 0.5 if k % 2 == 0 else 0.36, 0.06), bt + k * beat / 2, 0.0)
            for k in range(8):
                S.place(base, S.tick(1.0 if k % 2 == 0 else 0.6, 1.3), bt + k * beat / 2, 0.4 if k % 2 else -0.4)
            # --- melody：圆号主题 + 长号低八度加厚
            for (b, d, m) in horn[bi]:
                S.place(melo, S.sample("french_horn", m, d * beat * 0.95, 0.5, 0.2), bt + b * beat, -0.15)
                S.place(melo, S.sample("trombone", m - 12, d * beat * 0.9, 0.32, 0.15), bt + b * beat, 0.2)
            # --- bright：震音弦乐（和弦）+ 合唱长音
            for m in S.voice(notes, 57, 74):
                S.place(brt, S.sample("tremolo_strings", m, bar * 1.0, 0.2, 0.6), bt, S.rng.uniform(-0.5, 0.5))
            if bi % 2 == 0:
                for m in S.voice(notes, 60, 72)[:2]:
                    S.place(brt, S.sample("choir_aahs", m, bar * 2.0, 0.18, 1.0), bt, S.rng.uniform(-0.3, 0.3))
    stems = {}
    for name, buf, wet, gain in (("boss_base", base, 0.14, 0.55), ("boss_melody", melo, 0.24, 1.6), ("boss_bright", brt, 0.34, 1.0)):
        x = S.reverb(S.hp(buf, 30), wet) * gain
        stems[name] = S.loopify(x, loop)
    for k, v in S.master(stems, target_rms=0.12).items():
        S.write_ogg(k, v)

if __name__ == "__main__":
    S.OUT = sys.argv[1]
    os.makedirs(S.OUT, exist_ok=True)
    fetch("timpani", 38, 62)
    fetch("contrabass", 26, 55)
    fetch("french_horn", 55, 80)
    fetch("trombone", 40, 68)
    fetch("tremolo_strings", 50, 78)
    fetch("choir_aahs", 55, 76)
    fetch("woodblock", 70, 90)
    render_boss()
