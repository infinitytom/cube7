"""立方-7 音频合成：区域 1 主题曲（三层分轨，无缝循环）+ 全部音效。
纯 numpy 合成，输出 44.1kHz 立体声 OGG。"""
import numpy as np, subprocess, os, sys

SR = 44100
OUT = sys.argv[1] if len(sys.argv) > 1 else "out"
os.makedirs(OUT, exist_ok=True)
rng = np.random.default_rng(7)

def mtof(m): return 440.0 * 2 ** ((m - 69) / 12)
def t_arr(dur): return np.arange(int(dur * SR)) / SR

def env(n, a=0.005, d=0.1, s=0.6, r=0.1, hold=None):
    """ADSR；hold = 按住时长（秒），之后进入释放"""
    total = n / SR
    hold = total - r if hold is None else hold
    t = np.arange(n) / SR
    e = np.where(t < a, t / max(a, 1e-6), 1.0)
    dec = (t >= a) & (t < a + d)
    e = np.where(dec, 1 - (1 - s) * (t - a) / d, e)
    e = np.where(t >= a + d, s, e)
    rel = t >= hold
    e = np.where(rel, s * np.clip(1 - (t - hold) / max(r, 1e-6), 0, 1), e)
    return e

def lowpass(x, cutoff):
    # 单极点低通（逐样本，向量化近似：用 IIR）
    a = np.exp(-2 * np.pi * cutoff / SR)
    y = np.empty_like(x)
    acc = 0.0
    for i in range(len(x)):
        acc = (1 - a) * x[i] + a * acc
        y[i] = acc
    return y

def lp_fast(x, cutoff, passes=2):
    from scipy.signal import butter, sosfilt
    sos = butter(passes, cutoff / (SR / 2), btype="low", output="sos")
    return sosfilt(sos, x, axis=0)

def hp_fast(x, cutoff, order=2):
    from scipy.signal import butter, sosfilt
    sos = butter(order, cutoff / (SR / 2), btype="high", output="sos")
    return sosfilt(sos, x, axis=0)

def bp_fast(x, lo, hi, order=2):
    from scipy.signal import butter, sosfilt
    sos = butter(order, [lo / (SR / 2), hi / (SR / 2)], btype="band", output="sos")
    return sosfilt(sos, x, axis=0)

# ------------------------------------------------------------------ 乐器

def marimba(f, dur, vel=1.0):
    n = int((dur + 0.6) * SR)
    t = np.arange(n) / SR
    body = np.sin(2 * np.pi * f * t) * np.exp(-t * 7)
    over = 0.35 * np.sin(2 * np.pi * f * 4 * t) * np.exp(-t * 28)
    click = 0.15 * np.sin(2 * np.pi * f * 9.2 * t) * np.exp(-t * 90)
    return (body + over + click) * vel

def glock(f, dur, vel=1.0):
    n = int((dur + 1.4) * SR)
    t = np.arange(n) / SR
    # FM 钟琴
    mod = np.sin(2 * np.pi * f * 3.5 * t) * 2.2 * np.exp(-t * 6)
    s = np.sin(2 * np.pi * f * t + mod) * np.exp(-t * 2.8)
    s += 0.25 * np.sin(2 * np.pi * f * 2.76 * t) * np.exp(-t * 5)
    return s * vel * 0.8

def pluck(f, dur, vel=1.0, bright=0.5):
    # Karplus-Strong 拨弦（用 IIR 滤波器实现）
    from scipy.signal import lfilter
    n = int((dur + 0.4) * SR)
    p = max(2, int(SR / f))
    exc = np.zeros(n)
    exc[:p] = rng.uniform(-1, 1, p)
    d = 0.994 + 0.004 * bright
    a = np.zeros(p + 2); a[0] = 1.0; a[p] = -0.5 * d; a[p + 1] = -0.5 * d
    return lfilter([1.0], a, exc) * vel * 0.6

def warm_pad(freqs, dur):
    n = int((dur + 0.8) * SR)
    t = np.arange(n) / SR
    s = np.zeros(n)
    for f in freqs:
        for det in (-0.12, 0.0, 0.11):
            ff = f * 2 ** (det / 12)
            ph = rng.uniform(0, 2 * np.pi)
            # 柔和锯齿（前 6 个谐波）
            for k in range(1, 7):
                s += np.sin(2 * np.pi * ff * k * t + ph * k) / k * 0.12
    s = lp_fast(s, 1800)
    e = env(n, a=0.35, d=0.4, s=0.8, r=0.7, hold=dur)
    return s * e * 0.22

def bass(f, dur, vel=1.0):
    n = int((dur + 0.15) * SR)
    t = np.arange(n) / SR
    s = np.sin(2 * np.pi * f * t) + 0.3 * np.sin(2 * np.pi * f * 2 * t) + 0.12 * np.sin(2 * np.pi * f * 3 * t)
    e = env(n, a=0.008, d=0.12, s=0.7, r=0.08, hold=dur)
    return np.tanh(s * 1.2) * e * vel * 0.55

def kick(vel=1.0):
    n = int(0.35 * SR)
    t = np.arange(n) / SR
    f = 50 + 90 * np.exp(-t * 35)
    ph = 2 * np.pi * np.cumsum(f) / SR
    return np.sin(ph) * np.exp(-t * 11) * vel * 0.9

def snare_rim(vel=1.0):
    n = int(0.2 * SR)
    t = np.arange(n) / SR
    noise = bp_fast(rng.uniform(-1, 1, n), 1500, 6000)
    tone = np.sin(2 * np.pi * 330 * t) * np.exp(-t * 40)
    return (noise * np.exp(-t * 28) * 1.6 + tone * 0.5) * vel * 0.45

def shaker(vel=1.0):
    n = int(0.08 * SR)
    t = np.arange(n) / SR
    noise = hp_fast(rng.uniform(-1, 1, n), 6000)
    return noise * np.exp(-t * 60) * vel * 0.25

def clap(vel=1.0):
    n = int(0.25 * SR)
    t = np.arange(n) / SR
    noise = bp_fast(rng.uniform(-1, 1, n), 900, 4000)
    e = np.zeros(n)
    for off in (0.0, 0.011, 0.022):
        e += np.where(t >= off, np.exp(-(t - off) * 50), 0)
    return noise * e * vel * 0.35

# ------------------------------------------------------------------ 混音工具

def place(buf, sig, start_s, pan=0.0, gain=1.0):
    i = int(start_s * SR)
    if i >= len(buf):
        return
    sig = sig[: len(buf) - i]
    l = np.cos((pan + 1) * np.pi / 4) * gain
    r = np.sin((pan + 1) * np.pi / 4) * gain
    buf[i : i + len(sig), 0] += sig * l
    buf[i : i + len(sig), 1] += sig * r

def reverb(x, mix=0.22, room=0.82):
    # Schroeder：4 梳状 + 2 全通，左右声道延迟略不同
    out = np.zeros_like(x)
    for ch, spread in ((0, 0), (1, 23)):
        s = x[:, ch]
        acc = np.zeros_like(s)
        for d in (1557, 1617, 1491, 1422):
            d = d + spread
            y = np.copy(s)
            for i in range(d, len(s), d):
                y[i : i + d] += y[i - d : i - d + min(d, len(s) - i)] * room
            acc += y
        acc /= 4
        from scipy.signal import lfilter
        for d, g in ((225, 0.5), (556, 0.5)):
            d += spread
            b = np.zeros(d + 1); b[0] = -g; b[d] = 1.0
            a = np.zeros(d + 1); a[0] = 1.0; a[d] = -g
            acc = lfilter(b, a, acc)
        out[:, ch] = acc
    return x * (1 - mix) + lp_fast(out, 6000) * mix

def master(x, gain=0.9):
    x = x / (np.max(np.abs(x)) + 1e-9) * gain
    return np.tanh(x * 1.1) / np.tanh(1.1)

def write_ogg(name, x, q=6):
    wav = os.path.join(OUT, name + ".wav")
    ogg = os.path.join(OUT, name + ".ogg")
    from scipy.io import wavfile
    wavfile.write(wav, SR, (np.clip(x, -1, 1) * 32767).astype(np.int16))
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", wav, "-c:a", "libvorbis", "-q:a", str(q), ogg], check=True)
    os.remove(wav)
    print("wrote", ogg, f"{os.path.getsize(ogg)//1024} KB")

# ------------------------------------------------------------------ 作曲：区域 1「翠绿温室」

BPM = 120
BEAT = 60 / BPM
BAR = BEAT * 4
BARS = 32
LOOP = BARS * BAR

N = {"C": 0, "C#": 1, "D": 2, "Eb": 3, "E": 4, "F": 5, "F#": 6, "G": 7, "Ab": 8, "A": 9, "Bb": 10, "B": 11}
CHORDS = {
    "F": ["F", "A", "C"], "Dm": ["D", "F", "A"], "Bb": ["Bb", "D", "F"], "C": ["C", "E", "G"],
    "C7": ["C", "E", "G", "Bb"], "Am": ["A", "C", "E"], "Gm7": ["G", "Bb", "D", "F"],
    "A7": ["A", "C#", "E", "G"], "Gm": ["G", "Bb", "D"],
}
PROG = (["F", "Dm", "Bb", "C", "F", "Am", "Bb", "C7"] +
        ["F", "Dm", "Gm7", "C", "F", "A7", "Dm", "C"] +
        ["Bb", "C", "Am", "Dm", "Gm", "C", "F", "C7"] +
        ["F", "Dm", "Bb", "C", "F", "Am", "Bb", "F"])

A = [
    [(0, 1, 72), (1, 1, 69), (2, 1, 72), (3, 1, 77)],
    [(0, 3, 76), (3, 1, 74)],
    [(0, 1, 74), (1, 1, 70), (2, 1, 74), (3, 1, 77)],
    [(0, 2, 76), (2, 2, 72)],
    [(0, 1, 69), (1, .5, 69), (1.5, .5, 72), (2, 1, 77), (3, 1, 76)],
    [(0, 1, 76), (1, 1, 74), (2, 2, 72)],
    [(0, 1.5, 74), (1.5, .5, 72), (2, 1, 70), (3, 1, 74)],
    [(0, 3, 72)],
]
A2 = [
    A[0],
    [(0, 3, 81), (3, 1, 79)],
    [(0, 1, 77), (1, 1, 74), (2, 1, 70), (3, 1, 74)],
    [(0, 2, 72), (2, 2, 76)],
    [(0, 1.5, 77), (1.5, .5, 76), (2, 1, 77), (3, 1, 81)],
    [(0, 1, 79), (1, 1, 77), (2, 2, 76)],
    [(0, 1, 74), (1, 1, 77), (2, 1, 81), (3, 1, 77)],
    [(0, 2, 79), (2, 2, 76)],
]
B = [
    [(0, 3, 74), (3, 1, 77)],
    [(0, 3, 76), (3, 1, 79)],
    [(0, 2, 81), (2, 1, 79), (3, 1, 76)],
    [(0, 4, 77)],
    [(0, 1, 74), (1, 1, 79), (2, 1, 82), (3, 1, 81)],
    [(0, 2, 79), (2, 2, 76)],
    [(0, 1, 77), (1, 1, 81), (2, 1, 84), (3, 1, 81)],
    [(0, 3, 79)],
]
A3 = A[:7] + [[(0, 4, 77)]]
MELODY = A + A2 + B + A3

def chord_pcs(name): return [N[n] for n in CHORDS[name]]

def near(pc, center):
    """把音级放到离 center 最近的八度"""
    base = center - (center % 12) + pc
    if base - center > 6: base -= 12
    if center - base > 6: base += 12
    return base

def render_stems():
    total = LOOP * 2 + 2.0      # 渲染两遍，取第二遍 → 混响尾巴自然接回开头，循环无缝
    base = np.zeros((int(total * SR), 2))
    mel = np.zeros_like(base)
    bright = np.zeros_like(base)
    for rep in range(2):
        t0 = rep * LOOP
        for bi, ch in enumerate(PROG):
            bt = t0 + bi * BAR
            pcs = chord_pcs(ch)
            root = pcs[0]
            # ---- 底层：铺底 + 贝斯 + 轻打击乐
            pad_notes = sorted(near(pc, 62) for pc in pcs[:3])
            place(base, warm_pad([mtof(m) for m in pad_notes], BAR * 0.98), bt, 0.0, 1.0)
            r2 = near(root, 41)
            for off, dur, m in ((0, .7, r2), (1.5, .45, r2 + 7), (2, .7, r2), (3.5, .45, r2 + 12)):
                place(base, bass(mtof(m), dur * BEAT), bt + off * BEAT, 0.0, 1.0)
            for b in range(4):
                if b in (0, 2):
                    place(base, kick(0.8), bt + b * BEAT, 0.0, 0.9)
                if b in (1, 3):
                    place(base, snare_rim(0.7), bt + b * BEAT, 0.1, 0.8)
                for e in range(2):
                    place(base, shaker(0.9 if e == 1 else 0.6), bt + (b + e * 0.5) * BEAT, 0.35, 1.0)
            # ---- 旋律层：马林巴主旋律 + 拨弦琶音
            for off, dur, m in MELODY[bi]:
                place(mel, marimba(mtof(m), dur * BEAT, 0.9), bt + off * BEAT, -0.12, 0.9)
                place(mel, marimba(mtof(m + 12), dur * BEAT, 0.22), bt + off * BEAT + 0.012, 0.25, 0.9)
            arp = sorted(near(pc, 67) for pc in pcs) + [near(pcs[0], 67) + 12]
            for k in range(8):
                m = arp[[0, 1, 2, 3, 2, 1, 2, 3][k] % len(arp)]
                place(mel, pluck(mtof(m), 0.25, 0.35), bt + k * 0.5 * BEAT, 0.4 if k % 2 else -0.4, 0.7)
            # ---- 明亮层：钟琴副旋律 + 拍手 + 更满的鼓
            top = near(pcs[-1] if len(pcs) < 4 else pcs[2], 84)
            place(bright, glock(mtof(top), BEAT * 1.5, 0.6), bt, 0.3, 0.8)
            if bi % 2 == 1:
                place(bright, glock(mtof(near(pcs[1], 86)), BEAT, 0.45), bt + 2.5 * BEAT, -0.3, 0.8)
            for b in (1, 3):
                place(bright, clap(0.9), bt + b * BEAT, 0.0, 0.9)
            place(bright, kick(0.5), bt + 3.5 * BEAT, 0.0, 0.7)
    stems = {}
    for name, buf, rev in (("gh_base", base, 0.18), ("gh_melody", mel, 0.26), ("gh_bright", bright, 0.3)):
        x = reverb(buf, rev)
        a = int(LOOP * SR)
        stems[name] = x[a : 2 * a]
    # 统一响度：按三轨叠加后的峰值归一，保持相对音量
    peak = np.max(np.abs(stems["gh_base"] + stems["gh_melody"] + stems["gh_bright"]))
    for name, x in stems.items():
        y = x / peak * 0.92
        write_ogg(name, y)

# ------------------------------------------------------------------ 音效

def sfx_out(name, x, rev=0.0):
    if x.ndim == 1:
        x = np.stack([x, x], axis=1)
    if rev > 0:
        x = reverb(np.concatenate([x, np.zeros((int(0.5 * SR), 2))]), rev)
    write_ogg(name, master(x, 0.85), q=5)

def noise(n): return rng.uniform(-1, 1, n)

def make_sfx():
    # 破坏：软（土/草/砂）
    n = int(0.35 * SR); t = np.arange(n) / SR
    x = lp_fast(noise(n), 1400) * np.exp(-t * 14) * 1.6 + np.sin(2 * np.pi * 110 * t) * np.exp(-t * 30) * 0.6
    sfx_out("break_soft", x)
    # 破坏：硬（岩石/矿）
    n = int(0.45 * SR); t = np.arange(n) / SR
    x = bp_fast(noise(n), 300, 3500) * np.exp(-t * 12) * 1.4
    for k in range(5):
        st = rng.uniform(0.0, 0.12)
        x += np.where(t > st, bp_fast(noise(n), 2000, 7000) * np.exp(-(t - st) * 60), 0) * 0.5
    x += np.sin(2 * np.pi * 70 * t) * np.exp(-t * 20) * 0.8
    sfx_out("break_hard", x)
    # 破坏：玻璃
    n = int(0.9 * SR); t = np.arange(n) / SR
    x = hp_fast(noise(n), 3000) * np.exp(-t * 9) * 0.8
    for k in range(9):
        f = rng.uniform(2500, 7000); st = rng.uniform(0.0, 0.25)
        x += np.where(t > st, np.sin(2 * np.pi * f * (t - st)) * np.exp(-(t - st) * rng.uniform(12, 25)), 0) * 0.3
    sfx_out("break_glass", x, 0.2)
    # 木箱
    n = int(0.3 * SR); t = np.arange(n) / SR
    x = bp_fast(noise(n), 200, 2200) * np.exp(-t * 18) * 1.4 + np.sin(2 * np.pi * 180 * t) * np.exp(-t * 25) * 0.7
    sfx_out("break_wood", x)
    # 金币：两音叮
    x = np.zeros(int(0.5 * SR))
    for st, m in ((0.0, 88), (0.07, 93)):
        g = glock(mtof(m), 0.2, 0.6)[: len(x) - int(st * SR)]
        x[int(st * SR) : int(st * SR) + len(g)] += g
    sfx_out("coin", x)
    # 能源：上行短扫频
    n = int(0.35 * SR); t = np.arange(n) / SR
    f = 600 + 1800 * t / t[-1]
    x = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t * 7) * 0.7
    sfx_out("energy", x, 0.2)
    # 变形：下-上滑音 + 闪光
    n = int(0.45 * SR); t = np.arange(n) / SR
    f = 300 * 2 ** (np.sin(np.pi * t / t[-1]) * 1.5)
    x = np.sin(2 * np.pi * np.cumsum(f) / SR) * env(n, 0.01, 0.1, 0.7, 0.2) * 0.6
    x += glock(mtof(96), 0.1, 0.3)[:n]
    sfx_out("morph", x, 0.25)
    # 解锁：大调琶音号角
    x = np.zeros(int(2.2 * SR))
    for i, m in enumerate([65, 69, 72, 77, 81, 84]):
        g = marimba(mtof(m), 0.3, 0.8)
        st = int(i * 0.09 * SR)
        x[st : st + len(g)] += g[: len(x) - st]
    ch = warm_pad([mtof(65), mtof(69), mtof(72), mtof(77)], 1.2)
    x[int(0.5 * SR) : int(0.5 * SR) + len(ch)] += ch[: len(x) - int(0.5 * SR)] * 2.5
    sfx_out("unlock", x, 0.3)
    # 检查点：柔和叮咚
    x = np.zeros(int(1.0 * SR))
    for st, m in ((0.0, 79), (0.12, 84)):
        g = glock(mtof(m), 0.3, 0.5)
        x[int(st * SR) : int(st * SR) + len(g)] += g[: len(x) - int(st * SR)]
    sfx_out("checkpoint", x, 0.3)
    # 谜题解开：经典四音上行
    x = np.zeros(int(1.6 * SR))
    for i, m in enumerate([72, 76, 79, 84]):
        g = marimba(mtof(m), 0.25, 0.9)
        st = int(i * 0.11 * SR)
        x[st : st + len(g)] += g[: len(x) - st]
    sfx_out("success", x, 0.3)
    # 冲刺：呼啸
    n = int(0.4 * SR); t = np.arange(n) / SR
    x = bp_fast(noise(n), 400, 3000) * np.sin(np.pi * t / t[-1]) ** 2 * 1.2
    sfx_out("dash", x)
    # 钻头：短促的研磨声（循环播放）
    n = int(0.25 * SR); t = np.arange(n) / SR
    x = (np.sign(np.sin(2 * np.pi * 95 * t)) * 0.3 + bp_fast(noise(n), 500, 2500) * 0.8) * (0.8 + 0.2 * np.sin(2 * np.pi * 30 * t))
    x *= env(n, 0.01, 0.05, 0.9, 0.05)
    sfx_out("drill", x)
    # 弹跳垫
    n = int(0.5 * SR); t = np.arange(n) / SR
    f = 180 * (1 + 3 * (1 - np.exp(-t * 12)))
    x = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t * 6) * 0.8
    sfx_out("boing", x)
    # 抓取 / 投掷
    n = int(0.2 * SR); t = np.arange(n) / SR
    sfx_out("grab", np.sin(2 * np.pi * np.cumsum(500 + 700 * t / t[-1]) / SR) * np.exp(-t * 18) * 0.6)
    sfx_out("throw", bp_fast(noise(n), 800, 4000) * np.sin(np.pi * t / t[-1]) * 0.9)
    # 记忆碎片：闪亮的上行钟琴
    x = np.zeros(int(1.8 * SR))
    for i, m in enumerate([84, 88, 91, 96, 100]):
        g = glock(mtof(m), 0.2, 0.45)
        st = int(i * 0.06 * SR)
        x[st : st + len(g)] += g[: len(x) - st]
    sfx_out("fragment", x, 0.35)
    # 掉落重生：下行 + 噗
    n = int(0.6 * SR); t = np.arange(n) / SR
    x = np.sin(2 * np.pi * np.cumsum(700 * np.exp(-t * 4)) / SR) * np.exp(-t * 5) * 0.6
    sfx_out("respawn", x, 0.2)
    # 滚动：低沉的持续隆隆声（循环，按速度调音量/音高）
    n = int(1.0 * SR); t = np.arange(n) / SR
    x = lp_fast(noise(n), 260) * 3.0
    x = x * np.hanning(n) ** 0.05  # 首尾几乎不变，便于循环
    sfx_out("roll", x)
    # 撞击（撞墙、落地）
    n = int(0.25 * SR); t = np.arange(n) / SR
    sfx_out("thud", np.sin(2 * np.pi * np.cumsum(120 * np.exp(-t * 8) + 40) / SR) * np.exp(-t * 18) + lp_fast(noise(n), 800) * np.exp(-t * 30) * 0.6)
    # 光桥展开：连续上行音阶
    x = np.zeros(int(2.5 * SR))
    for i, m in enumerate([65, 67, 69, 72, 74, 77, 79, 81, 84, 86, 89]):
        g = glock(mtof(m), 0.15, 0.4)
        st = int(i * 0.14 * SR)
        x[st : st + len(g)] += g[: len(x) - st]
    sfx_out("bridge", x, 0.35)
    # 过关：小号角式终止乐句
    x = np.zeros(int(3.0 * SR))
    for st, dur, m in ((0, .15, 72), (.15, .15, 72), (.3, .15, 72), (.45, .6, 77), (1.1, .25, 76), (1.35, .25, 79), (1.6, 1.0, 84)):
        g = marimba(mtof(m), dur, 0.9)
        s = int(st * SR)
        x[s : s + len(g)] += g[: len(x) - s]
    ch = warm_pad([mtof(65), mtof(69), mtof(72), mtof(77)], 1.6)
    s = int(1.6 * SR)
    x[s : s + len(ch)] += ch[: len(x) - s] * 2.0
    sfx_out("level_clear", x, 0.3)

if __name__ == "__main__":
    what = sys.argv[2] if len(sys.argv) > 2 else "all"
    if what in ("all", "sfx"):
        make_sfx()
    if what in ("all", "music"):
        render_stems()
