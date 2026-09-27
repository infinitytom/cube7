"""立方-7 音频 v2：更成熟的科幻氛围配乐 + 角色拟声 + 菜单音效。
依赖 synth.py 里的基础函数。"""
import sys, os
import numpy as np
sys.path.insert(0, os.path.dirname(__file__))
import synth as S
from synth import SR, mtof, place, reverb, write_ogg, lp_fast, hp_fast, bp_fast, env

rng = np.random.default_rng(11)

# ------------------------------------------------------------------ 乐器

def rhodes(f, dur, vel=1.0):
    """FM 电钢琴：带一点“叮”的敲击和缓慢衰减"""
    n = int((dur + 1.2) * SR)
    t = np.arange(n) / SR
    idx = 1.6 * np.exp(-t * 3.5) + 0.25
    mod = np.sin(2 * np.pi * f * 1.0 * t) * idx
    car = np.sin(2 * np.pi * f * t + mod)
    tine = 0.18 * np.sin(2 * np.pi * f * 14.0 * t) * np.exp(-t * 40)
    e = env(n, a=0.004, d=0.6, s=0.45, r=0.6, hold=dur)
    trem = 1.0 + 0.06 * np.sin(2 * np.pi * 4.5 * t)
    return (car + tine) * e * trem * vel * 0.5

def strings(freqs, dur, vel=1.0, bright=2400):
    n = int((dur + 1.4) * SR)
    t = np.arange(n) / SR
    s = np.zeros(n)
    for f in freqs:
        for det in (-0.09, 0.0, 0.08):
            ff = f * 2 ** (det / 12)
            vib = 1 + 0.0035 * np.sin(2 * np.pi * 5.2 * t + rng.uniform(0, 6))
            ph = 2 * np.pi * np.cumsum(ff * vib) / SR + rng.uniform(0, 6)
            for k in range(1, 9):
                s += np.sin(ph * k) / k * 0.09
    s = lp_fast(s, bright)
    e = env(n, a=0.9, d=0.5, s=0.85, r=1.2, hold=dur)
    return s * e * vel * 0.2

def sub(f, dur, vel=1.0):
    n = int((dur + 0.2) * SR)
    t = np.arange(n) / SR
    s = np.sin(2 * np.pi * f * t) + 0.2 * np.sin(2 * np.pi * f * 2 * t)
    e = env(n, a=0.02, d=0.2, s=0.8, r=0.15, hold=dur)
    return np.tanh(s * 1.3) * e * vel * 0.5

def arp_synth(f, dur, vel=1.0):
    """滤波锯齿拨弦：高次谐波衰减更快，模拟滤波器随包络闭合"""
    n = int((dur + 0.35) * SR)
    t = np.arange(n) / SR
    out = np.zeros(n)
    for k in range(1, 14):
        if f * k > 12000:
            break
        out += np.sin(2 * np.pi * f * k * t) / k * np.exp(-t * (6 + 5 * k))
    e = env(n, a=0.003, d=0.18, s=0.4, r=0.15, hold=dur)
    return out * e * vel * 0.35

def bell(f, dur, vel=1.0):
    n = int((dur + 2.0) * SR)
    t = np.arange(n) / SR
    s = np.sin(2 * np.pi * f * t + 1.2 * np.sin(2 * np.pi * f * 2.4 * t) * np.exp(-t * 3)) * np.exp(-t * 1.6)
    return s * vel * 0.35

def kick_deep(vel=1.0):
    n = int(0.5 * SR)
    t = np.arange(n) / SR
    f = 42 + 70 * np.exp(-t * 28)
    return np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t * 7) * vel * 0.95

def hat(vel=1.0, open_=False):
    n = int((0.35 if open_ else 0.06) * SR)
    t = np.arange(n) / SR
    x = hp_fast(rng.uniform(-1, 1, n), 7500)
    return x * np.exp(-t * (9 if open_ else 70)) * vel * 0.22

def rim(vel=1.0):
    n = int(0.12 * SR)
    t = np.arange(n) / SR
    x = bp_fast(rng.uniform(-1, 1, n), 1800, 5000) * np.exp(-t * 45) + np.sin(2 * np.pi * 520 * t) * np.exp(-t * 60) * 0.6
    return x * vel * 0.35

def snare_soft(vel=1.0):
    n = int(0.3 * SR)
    t = np.arange(n) / SR
    x = bp_fast(rng.uniform(-1, 1, n), 1200, 7000) * np.exp(-t * 16) + np.sin(2 * np.pi * 190 * t) * np.exp(-t * 30) * 0.5
    return x * vel * 0.4

def delay(x, secs, fb=0.35, mix=0.3, pingpong=True):
    d = int(secs * SR)
    out = np.copy(x)
    buf = np.zeros_like(x)
    for rep in range(1, 6):
        g = (fb ** rep) * mix
        sh = d * rep
        if sh >= len(x):
            break
        seg = x[:-sh]
        if pingpong and rep % 2 == 1:
            seg = seg[:, ::-1]
        out[sh:] += seg * g
    return out

# ------------------------------------------------------------------ 和声

CH = {
    "Dmaj9": [50, 57, 61, 64, 66], "Bm9": [47, 54, 57, 61, 62], "Gmaj9": [43, 50, 54, 57, 59],
    "Asus": [45, 52, 55, 59, 62], "F#m7": [42, 49, 52, 57, 61], "Em9": [40, 47, 50, 54, 55],
    "Cmaj7": [48, 55, 59, 64, 67],
}
PROG = (["Dmaj9", "Bm9", "Gmaj9", "Asus", "Dmaj9", "F#m7", "Gmaj9", "Cmaj7"] +
        ["Dmaj9", "Bm9", "Em9", "Asus", "Gmaj9", "F#m7", "Em9", "Asus"] +
        ["Gmaj9", "Asus", "F#m7", "Bm9", "Gmaj9", "Cmaj7", "Em9", "Asus"] +
        ["Dmaj9", "Bm9", "Gmaj9", "Asus", "Dmaj9", "F#m7", "Gmaj9", "Dmaj9"])
A = [
    [(0, 1.5, 76), (1.5, .5, 78), (2, 2, 81)],
    [(0, 1, 83), (1, 1, 81), (2, 2, 78)],
    [(0, 1.5, 85), (1.5, .5, 83), (2, 2, 81)],
    [(0, 3, 76)],
    [(0, 1.5, 76), (1.5, .5, 78), (2, 1, 81), (3, 1, 85)],
    [(0, 2, 81), (2, 1, 76), (3, 1, 78)],
    [(0, 1.5, 79), (1.5, .5, 78), (2, 2, 74)],
    [(0, 4, 76)],
]
A2 = [
    A[0],
    [(0, 1, 83), (1, 1, 85), (2, 2, 86)],
    [(0, 1.5, 83), (1.5, .5, 81), (2, 2, 78)],
    [(0, 3, 76), (3, 1, 79)],
    [(0, 2, 78), (2, 1, 81), (3, 1, 83)],
    [(0, 2, 85), (2, 2, 81)],
    [(0, 1.5, 79), (1.5, .5, 78), (2, 2, 76)],
    [(0, 4, 76)],
]
B = [
    [(0, 2, 86), (2, 2, 85)],
    [(0, 2, 83), (2, 2, 88)],
    [(0, 3, 85), (3, 1, 81)],
    [(0, 4, 83)],
    [(0, 1, 81), (1, 1, 83), (2, 2, 86)],
    [(0, 2, 88), (2, 2, 83)],
    [(0, 2, 81), (2, 2, 79)],
    [(0, 4, 76)],
]
MEL = A + A2 + B + (A[:7] + [[(0, 4, 81)]])

def render_area(prefix="gh", bpm=96):
    beat = 60 / bpm
    bar = beat * 4
    loop = bar * len(PROG)
    total = loop * 2 + 3
    base = np.zeros((int(total * SR), 2)); mel = np.zeros_like(base); bright = np.zeros_like(base)
    for rep in range(2):
        t0 = rep * loop
        for bi, ch in enumerate(PROG):
            bt = t0 + bi * bar
            notes = CH[ch]
            # 底层：弦乐铺底 + 低音 + 克制的鼓
            place(base, strings([mtof(m) for m in notes[1:]], bar * 0.99, 0.9), bt, 0.0)
            r = notes[0]
            for off, dur, m in ((0, 1.4, r), (1.5, 0.45, r), (2.5, 1.4, r + 7 if bi % 2 else r + 12)):
                place(base, sub(mtof(m - 12 if m > 52 else m), dur * beat), bt + off * beat, 0.0, 0.9)
            place(base, kick_deep(0.9), bt, 0.0)
            place(base, kick_deep(0.6), bt + 2.5 * beat, 0.0)
            place(base, rim(0.6), bt + 2 * beat, 0.15)
            for e in range(8):
                place(base, hat(0.55 if e % 2 else 0.3), bt + e * 0.5 * beat, 0.3)
            # 旋律层：电钢琴主旋律 + 滤波琶音
            for off, dur, m in MEL[bi]:
                place(mel, rhodes(mtof(m), dur * beat, 0.8), bt + off * beat, -0.15)
                place(mel, rhodes(mtof(m - 12), dur * beat, 0.25), bt + off * beat + 0.01, 0.2)
            ups = sorted(notes[2:]) + [notes[2] + 12]
            for k in range(16):
                m = ups[[0, 1, 2, 3, 2, 1, 3, 2][k % 8] % len(ups)] + 12
                place(mel, arp_synth(mtof(m), 0.2, 0.5 if k % 4 == 0 else 0.32), bt + k * 0.25 * beat, 0.35 if k % 2 else -0.35)
            # 明亮层：高音弦乐对位 + 钟声 + 更完整的鼓
            top = max(notes) + 12
            place(bright, strings([mtof(top), mtof(top + 7)], bar * 0.98, 0.8, 4200), bt, 0.25)
            if bi % 4 == 0:
                place(bright, bell(mtof(top + 12), bar, 0.6), bt, -0.3)
            place(bright, snare_soft(0.8), bt + 1 * beat, 0.0)
            place(bright, snare_soft(0.8), bt + 3 * beat, 0.0)
            place(bright, hat(0.5, True), bt + 3.5 * beat, -0.25)
    stems = {}
    for name, buf, rv in ((f"{prefix}_base", base, 0.2), (f"{prefix}_melody", delay(mel, beat * 0.75, 0.3, 0.28), 0.28), (f"{prefix}_bright", bright, 0.32)):
        x = reverb(buf, rv)
        a = int(loop * SR)
        stems[name] = x[a:2 * a]
    peak = np.max(np.abs(sum(stems.values())))
    for name, x in stems.items():
        write_ogg(name, x / peak * 0.9)

def render_title(bpm=72):
    beat = 60 / bpm
    bar = beat * 4
    prog = PROG[:16]
    loop = bar * len(prog)
    total = loop * 2 + 4
    buf = np.zeros((int(total * SR), 2))
    for rep in range(2):
        t0 = rep * loop
        for bi, ch in enumerate(prog):
            bt = t0 + bi * bar
            notes = CH[ch]
            place(buf, strings([mtof(m) for m in notes], bar * 0.99, 1.0, 1800), bt, 0.0)
            place(buf, sub(mtof(notes[0] - 12), bar * 0.9, 0.7), bt, 0.0)
            for off, dur, m in MEL[bi]:
                if off in (0, 2):
                    place(buf, rhodes(mtof(m), dur * beat, 0.55), bt + off * beat, -0.2)
            if bi % 2 == 0:
                place(buf, bell(mtof(max(notes) + 12), bar, 0.45), bt + beat * 2, 0.3)
    x = reverb(delay(buf, beat * 0.75, 0.35, 0.3), 0.4)
    a = int(loop * SR)
    y = x[a:2 * a]
    write_ogg("title_base", y / np.max(np.abs(y)) * 0.85)

# ------------------------------------------------------------------ 角色拟声 & 菜单

def voice_nova():
    """一个“音节”：带共振峰的柔和合成人声，由游戏随机变调"""
    n = int(0.085 * SR)
    t = np.arange(n) / SR
    f0 = 330
    src = np.zeros(n)
    for k in range(1, 20):
        src += np.sin(2 * np.pi * f0 * k * t) / k
    x = bp_fast(src, 500, 900) * 1.0 + bp_fast(src, 1600, 2600) * 0.6 + bp_fast(src, 2800, 3400) * 0.25
    x *= env(n, 0.006, 0.02, 0.8, 0.03)
    return x

def chirp(pts, dur, vel=1.0, wobble=0.0):
    """PIX 的哔啵：按音高轨迹滑动的纯音 + 一点方波味"""
    n = int(dur * SR)
    t = np.arange(n) / SR
    f = np.interp(t, np.linspace(0, dur, len(pts)), pts)
    if wobble:
        f *= 1 + wobble * np.sin(2 * np.pi * 22 * t)
    ph = 2 * np.pi * np.cumsum(f) / SR
    x = np.sin(ph) * 0.8 + np.sign(np.sin(ph)) * 0.12
    return x * env(n, 0.005, 0.03, 0.8, 0.04) * vel

def ui_tick(f=2200, dur=0.03):
    n = int(dur * SR)
    t = np.arange(n) / SR
    return np.sin(2 * np.pi * f * t) * np.exp(-t * 120)

def make_voices():
    S.sfx_out("voice_nova", voice_nova())
    S.sfx_out("pix_happy", np.concatenate([chirp([900, 1500], 0.07), np.zeros(int(0.03 * SR)), chirp([1300, 2100], 0.09)]), 0.15)
    S.sfx_out("pix_curious", chirp([1000, 1500, 1100, 1700], 0.26), 0.15)
    S.sfx_out("pix_hurt", chirp([1400, 600], 0.22, wobble=0.08), 0.1)
    S.sfx_out("pix_morph", chirp([700, 1200, 900, 1600], 0.2), 0.1)
    S.sfx_out("ui_move", ui_tick(2400, 0.035))
    S.sfx_out("ui_confirm", np.concatenate([ui_tick(1600, 0.05), ui_tick(2400, 0.07)]))
    S.sfx_out("ui_back", np.concatenate([ui_tick(2000, 0.05), ui_tick(1300, 0.07)]))

if __name__ == "__main__":
    S.OUT = sys.argv[1]
    os.makedirs(S.OUT, exist_ok=True)
    what = sys.argv[2] if len(sys.argv) > 2 else "all"
    if what in ("all", "voices"):
        make_voices()
    if what in ("all", "title"):
        render_title()
    if what in ("all", "area"):
        render_area()
