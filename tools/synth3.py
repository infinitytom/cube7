"""《方舟星球》配乐 v3：用真实乐器采样（FluidR3_GM，CC-BY 3.0）编排，
卷积混响 + 软限幅母带。输出无缝循环的 OGG 分轨。
用法：python3 synth3.py <输出目录> [title|gh|all]
"""
import os, sys, subprocess
import numpy as np
from scipy.signal import fftconvolve, butter, sosfilt

SR = 44100
SF = os.path.join(os.path.dirname(os.path.abspath(__file__)), "sf")
OUT = sys.argv[1] if len(sys.argv) > 1 else "out"
os.makedirs(OUT, exist_ok=True)
rng = np.random.default_rng(3)

# ------------------------------------------------------------------ 采样器

_cache = {}

def _load(inst, m):
    key = (inst, m)
    if key not in _cache:
        path = os.path.join(SF, inst, f"{m}.mp3")
        if not os.path.exists(path) or os.path.getsize(path) < 500:
            _cache[key] = None
        else:
            raw = subprocess.run(["ffmpeg", "-loglevel", "error", "-i", path, "-f", "f32le", "-ac", "1", "-ar", str(SR), "-"],
                                 capture_output=True).stdout
            x = np.frombuffer(raw, dtype=np.float32).astype(np.float64)
            # 去掉开头的静音
            nz = np.argmax(np.abs(x) > 1e-3) if np.any(np.abs(x) > 1e-3) else 0
            _cache[key] = x[max(nz - 20, 0):]
    return _cache[key]

def sample(inst, m, dur, vel=0.8, release=0.25):
    """取最接近的采样并变调；dur 秒后淡出（release）"""
    src = None
    for d in [0, 1, -1, 2, -2, 3, -3, 4, -4, 5, -5, 6, -6, 7, -7, 12, -12]:
        s = _load(inst, m + d)
        if s is not None:
            src, shift = s, -d
            break
    if src is None:
        return np.zeros(1)
    ratio = 2 ** (shift / 12)
    n_out = int((dur + release) * SR)
    need = int(n_out * ratio) + 2
    if need > len(src) and inst in SUSTAINED:
        src = _sustain(src, need)
    idx = np.arange(n_out) * ratio
    idx = idx[idx < len(src) - 1]
    y = np.interp(idx, np.arange(len(src)), src)
    env = np.ones(len(y))
    a = int(dur * SR)
    if a < len(y):
        r = len(y) - a
        env[a:] = np.linspace(1, 0, r) ** 2
    return y * env * vel

# 持续音乐器：采样只有 3 秒左右，需要时用稳定段交叉淡化循环来延长
SUSTAINED = {"string_ensemble_1", "pad_2_warm", "cello", "flute"}

def _sustain(src, need):
    a, b = int(0.9 * SR), int(min(2.3 * SR, len(src) * 0.75))
    if b - a < int(0.4 * SR):
        return src
    seg = src[a:b]
    xf = int(0.12 * SR)
    fade_in = np.linspace(0, 1, xf)
    out = src[:b].copy()
    while len(out) < need:
        tail = out[-xf:] * (1 - fade_in) + seg[:xf] * fade_in
        out = np.concatenate([out[:-xf], tail, seg[xf:]])
    return out

def place(buf, sig, t, pan=0.0, gain=1.0):
    i = int(t * SR)
    if i >= len(buf) or len(sig) == 0:
        return
    sig = sig[: len(buf) - i]
    l = np.cos((pan + 1) * np.pi / 4) * gain
    r = np.sin((pan + 1) * np.pi / 4) * gain
    buf[i:i + len(sig), 0] += sig * l
    buf[i:i + len(sig), 1] += sig * r

# ------------------------------------------------------------------ 效果

def lp(x, fc, order=2):
    sos = butter(order, fc / (SR / 2), btype="low", output="sos")
    return sosfilt(sos, x, axis=0)

def hp(x, fc, order=2):
    sos = butter(order, fc / (SR / 2), btype="high", output="sos")
    return sosfilt(sos, x, axis=0)

def make_ir(secs=2.6, bright=6000):
    """合成的房间冲激响应：指数衰减的立体声噪声 + 早期反射，高频衰减更快"""
    n = int(secs * SR)
    t = np.arange(n) / SR
    ir = np.zeros((n, 2))
    for ch in range(2):
        noise = rng.standard_normal(n)
        lo = lp(noise, 2500) * np.exp(-t * 2.2)
        hi = hp(noise, 2500) * np.exp(-t * 5.0) * 0.5
        ir[:, ch] = lo + hi
        for k in range(8):
            d = int(rng.uniform(0.008, 0.06) * SR)
            ir[d, ch] += rng.uniform(0.3, 0.7) * (1 if rng.random() > 0.5 else -1)
    ir[:int(0.004 * SR)] = 0
    ir /= np.sqrt((ir ** 2).sum(axis=0, keepdims=True))
    return lp(ir, bright)

IR = None

def reverb(x, wet=0.25, pre=0.02):
    global IR
    if IR is None:
        IR = make_ir()
    d = int(pre * SR)
    y = np.zeros((len(x) + len(IR) + d, 2))
    for ch in range(2):
        y[d:d + len(x) + len(IR) - 1, ch] = fftconvolve(x[:, ch], IR[:, ch])
    y = y[:len(x)]
    return x * (1 - wet * 0.35) + y * wet * 0.9

def master(stems, target_rms=0.1, peak=0.8):
    total = sum(stems.values())
    rms = np.sqrt((total ** 2).mean()) + 1e-9
    # 按响度对齐，再用软限幅兜住峰值（留出 OGG 编码的余量）
    g = min(target_rms / rms, peak / (np.max(np.abs(total)) + 1e-9) * 1.5)
    out = {}
    for k, v in stems.items():
        y = v * g
        out[k] = np.tanh(y * 1.2) / np.tanh(1.2) * 0.9
    return out

def write_ogg(name, x, q=6):
    from scipy.io import wavfile
    wav = os.path.join(OUT, name + ".wav")
    ogg = os.path.join(OUT, name + ".ogg")
    wavfile.write(wav, SR, (np.clip(x, -1, 1) * 32767).astype(np.int16))
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", wav, "-c:a", "libvorbis", "-q:a", str(q), ogg], check=True)
    os.remove(wav)
    print("wrote", ogg, f"{os.path.getsize(ogg) // 1024} KB")

def loopify(buf, loop_len):
    """把第二遍的尾巴（混响）叠回开头，得到无缝循环的一段"""
    a = int(loop_len * SR)
    body = buf[a:2 * a].copy()
    tail = buf[2 * a:3 * a]
    body[:len(tail)] += tail[:len(body)]
    return body

# ------------------------------------------------------------------ 和弦工具

def chord_notes(root, kind):
    iv = {"maj7": [0, 4, 7, 11], "m7": [0, 3, 7, 10], "7": [0, 4, 7, 10], "sus": [0, 5, 7, 10],
          "maj9": [0, 4, 7, 11, 14], "add9": [0, 4, 7, 14], "maj": [0, 4, 7], "m": [0, 3, 7], "lyd": [0, 4, 6, 11]}[kind]
    return [root + i for i in iv]

def voice(notes, low, high):
    """把和弦音放进 [low, high] 区间，紧凑排列"""
    out = []
    for n in notes:
        while n < low:
            n += 12
        while n > high:
            n -= 12
        out.append(n)
    return sorted(set(out))

# ------------------------------------------------------------------ 标题曲：《方舟》
# D 大调，72 BPM，16 小节循环。竖琴分解和弦 + 弦乐铺底 + 钢片琴主旋律 + 长笛，温柔、辽阔、有一点点孤独。

def render_title():
    bpm = 72
    beat = 60 / bpm
    bar = beat * 4
    D = 50
    prog = [(D, "maj9"), (47, "m7"), (43, "lyd"), (45, "sus"),
            (D, "maj7"), (40, "m7"), (43, "maj7"), (45, "sus"),
            (47, "m7"), (42, "m7"), (43, "maj7"), (45, "7"),
            (40, "m7"), (45, "sus"), (D, "maj9"), (D, "add9")]
    # 主旋律（从第 5 小节进来）：(拍, 时值, 音高)
    mel = {
        4: [(0, 2, 81), (2, 1, 78), (3, 1, 76)],
        5: [(0, 3, 74), (3, 1, 78)],
        6: [(0, 2, 79), (2, 1, 83), (3, 1, 81)],
        7: [(0, 4, 76)],
        8: [(0, 1, 78), (1, 1, 81), (2, 1, 86), (3, 1, 85)],
        9: [(0, 3, 83), (3, 1, 81)],
        10: [(0, 1, 79), (1, 1, 76), (2, 1, 78), (3, 1, 79)],
        11: [(0, 4, 81)],
        12: [(0, 1, 83), (1, 1, 81), (2, 1, 79), (3, 1, 78)],
        13: [(0, 2, 76), (2, 2, 81)],
        14: [(0, 1, 78), (1, 1, 76), (2, 1, 74), (3, 1, 76)],
        15: [(0, 4, 74)],
    }
    loop = bar * len(prog)
    n = int((loop * 3) * SR)
    pad = np.zeros((n, 2)); harp = np.zeros((n, 2)); lead = np.zeros((n, 2)); low = np.zeros((n, 2))
    for rep in range(2):
        t0 = rep * loop
        for bi, (root, kind) in enumerate(prog):
            bt = t0 + bi * bar
            notes = chord_notes(root, kind)
            # 弦乐 + 暖垫：中音区紧凑排列，整小节长音
            for m in voice(notes, 57, 72):
                # 提前 0.25 秒起音、拖长尾音，和下一小节交叉淡化，避免每小节开头出现空洞
                place(pad, sample("string_ensemble_1", m, bar * 1.05, 0.30, 1.4), bt - 0.25 if bt > 0.3 else bt, rng.uniform(-0.4, 0.4))
                place(pad, sample("pad_2_warm", m, bar * 1.05, 0.14, 1.4), bt - 0.25 if bt > 0.3 else bt, 0.0)
            # 大提琴根音
            place(low, sample("cello", root if root >= 43 else root + 12, bar * 1.0, 0.42, 1.0), bt, -0.1)
            # 竖琴：八分音符上行分解，每两小节在高处点一下
            arp = voice(notes, 62, 86)
            seq = (arp + arp[::-1][1:-1]) * 3
            for k in range(8):
                m = seq[k % len(seq)]
                place(harp, sample("orchestral_harp", m, beat * 1.5, 0.34 if k % 4 == 0 else 0.24, 0.9), bt + k * beat / 2, 0.35 if k % 2 else -0.35)
            # 旋律：钢片琴，第 9 小节起长笛低八度重复
            for (b, d, m) in mel.get(bi, []):
                place(lead, sample("celesta", m, d * beat, 0.55, 0.6), bt + b * beat, -0.1)
                if bi >= 8:
                    place(lead, sample("flute", m - 12, d * beat * 0.95, 0.34, 0.3), bt + b * beat + 0.01, 0.15)
    mix = pad * 0.55 + harp * 0.9 + lead * 1.3 + low * 0.6
    mix = hp(mix, 35)
    mix = reverb(mix, 0.42)
    body = loopify(mix, loop)
    st = master({"title_base": body})
    write_ogg("title_base", st["title_base"])

# ------------------------------------------------------------------ 第一章：《翠绿温室群岛》
# G 大调，100 BPM，32 小节循环，三层分轨（游戏里按状态淡入淡出）：
#   base   = 贝斯 + 电钢琴切分和弦 + 轻柔的鼓（木鱼 + 柔和底鼓 + 沙锤）
#   melody = 颤音琴主旋律 + 拨弦对位
#   bright = 弦乐 + 竖琴 + 长笛副旋律（找到新东西时的“亮起来”）

def soft_kick(vel=1.0):
    n = int(0.35 * SR)
    t = np.arange(n) / SR
    f = 48 + 60 * np.exp(-t * 30)
    return np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t * 9) * vel

def shaker(vel=1.0):
    n = int(0.09 * SR)
    t = np.arange(n) / SR
    x = hp(rng.standard_normal(n), 5500, 2)
    x = lp(x, 11000)
    return lp(x, 8000) * np.exp(-t * 55) * (1 - np.exp(-t * 400)) * vel * 0.05

def render_greenhouse():
    bpm = 100
    beat = 60 / bpm
    bar = beat * 4
    G = 43
    A = [(G, "maj7"), (40, "m7"), (48, "maj7"), (50, "sus"),
         (G, "add9"), (45, "m7"), (48, "maj7"), (50, "7"),
         (40, "m7"), (47, "m7"), (48, "maj7"), (43, "maj"),
         (45, "m7"), (50, "sus"), (48, "maj7"), (50, "7")]
    B = [(48, "maj7"), (50, "maj"), (47, "m7"), (40, "m7"),
         (45, "m7"), (50, "sus"), (G, "maj7"), (G, "add9"),
         (48, "lyd"), (50, "maj"), (47, "m7"), (40, "m7"),
         (45, "m7"), (50, "7"), (G, "maj9"), (50, "sus")]
    prog = A + B
    # 颤音琴主旋律（A 段 16 小节；B 段换成更舒展的一句）
    ma = [
        [(0, 0.5, 74), (0.5, 0.5, 79), (1, 1, 81), (2, 1.5, 83), (3.5, 0.5, 81)],
        [(0, 1, 79), (1, 1, 76), (2, 2, 74)],
        [(0, 0.5, 76), (0.5, 0.5, 79), (1, 1, 83), (2, 1, 84), (3, 1, 83)],
        [(0, 3, 81)],
        [(0, 0.5, 74), (0.5, 0.5, 79), (1, 1, 81), (2, 1.5, 83), (3.5, 0.5, 86)],
        [(0, 1, 84), (1, 1, 83), (2, 2, 81)],
        [(0, 1, 79), (1, 0.5, 81), (1.5, 0.5, 79), (2, 1, 76), (3, 1, 79)],
        [(0, 3, 78)],
        [(0, 1.5, 79), (1.5, 0.5, 78), (2, 2, 76)],
        [(0, 1, 74), (1, 1, 78), (2, 2, 81)],
        [(0, 1.5, 83), (1.5, 0.5, 81), (2, 1, 79), (3, 1, 76)],
        [(0, 3, 79)],
        [(0, 0.5, 76), (0.5, 0.5, 79), (1, 1, 84), (2, 1, 83), (3, 1, 81)],
        [(0, 2, 78), (2, 1, 81), (3, 1, 86)],
        [(0, 1.5, 84), (1.5, 0.5, 83), (2, 1, 79), (3, 1, 76)],
        [(0, 4, 78)],
    ]
    mb = [
        [(0, 2, 84), (2, 1, 83), (3, 1, 79)],
        [(0, 3, 81), (3, 1, 78)],
        [(0, 2, 83), (2, 1, 81), (3, 1, 79)],
        [(0, 4, 79)],
        [(0, 1, 76), (1, 1, 79), (2, 1, 84), (3, 1, 83)],
        [(0, 2, 81), (2, 2, 78)],
        [(0, 1, 79), (1, 1, 83), (2, 1, 86), (3, 1, 91)],
        [(0, 4, 88)],
        [(0, 2, 88), (2, 1, 86), (3, 1, 84)],
        [(0, 3, 86), (3, 1, 81)],
        [(0, 2, 83), (2, 1, 81), (3, 1, 79)],
        [(0, 4, 79)],
        [(0, 1, 81), (1, 1, 84), (2, 1, 83), (3, 1, 81)],
        [(0, 2, 78), (2, 2, 81)],
        [(0, 1, 83), (1, 1, 81), (2, 1, 78), (3, 1, 74)],
        [(0, 4, 79)],
    ]
    mel = ma + mb
    loop = bar * len(prog)
    n = int(loop * 3 * SR)
    base = np.zeros((n, 2)); melo = np.zeros((n, 2)); brt = np.zeros((n, 2))
    for rep in range(2):
        t0 = rep * loop
        for bi, (root, kind) in enumerate(prog):
            bt = t0 + bi * bar
            notes = chord_notes(root, kind)
            r = root if root < 48 else root - 12
            # --- base：贝斯（1 拍根音、3 拍五度、4.5 拍经过音）
            place(base, sample("acoustic_bass", r, beat * 1.4, 0.62, 0.15), bt, 0.0)
            place(base, sample("acoustic_bass", r + 7, beat * 0.9, 0.5, 0.15), bt + 2 * beat, 0.0)
            nxt = prog[(bi + 1) % len(prog)][0]
            nxt = nxt if nxt < 48 else nxt - 12
            place(base, sample("acoustic_bass", nxt - 1 if nxt > r else nxt + 2, beat * 0.4, 0.4, 0.1), bt + 3.5 * beat, 0.0)
            # 电钢琴：切分和弦（1、2.5、4 拍）
            ep = voice(notes, 55, 71)
            for (b, d, v) in [(0, 1.2, 0.32), (1.5, 0.8, 0.26), (3, 0.9, 0.24)]:
                for m in ep:
                    place(base, sample("electric_piano_1", m, d * beat, v, 0.3), bt + b * beat, -0.25)
            # 轻鼓：底鼓 1、2.5、3 拍；木鱼 2、4 拍；沙锤八分
            for b, v in [(0, 0.55), (1.5, 0.3), (2, 0.45)]:
                place(base, soft_kick(v), bt + b * beat, 0.0)
            for b in [1, 3]:
                place(base, sample("woodblock", 67, 0.2, 0.22, 0.05), bt + b * beat, 0.2)
            for k in range(8):
                place(base, shaker(0.8 if k % 2 else 0.45), bt + k * beat / 2, 0.4)
            # --- melody：颤音琴 + 拨弦对位（反拍的和弦音）
            for (b, d, m) in mel[bi]:
                place(melo, sample("vibraphone", m, d * beat, 0.5, 0.7), bt + b * beat, 0.1)
            pz = voice(notes, 67, 79)
            for k, b in enumerate([0.5, 1.5, 2.5, 3.5]):
                place(melo, sample("pizzicato_strings", pz[k % len(pz)], 0.3, 0.3, 0.2), bt + b * beat, -0.45)
            # --- bright：弦乐长音 + 竖琴四小节一次上行刮奏 + B 段长笛
            for m in voice(notes, 62, 79):
                place(brt, sample("string_ensemble_1", m, bar * 1.05, 0.22, 1.2), bt - 0.2 if bt > 0.3 else bt, rng.uniform(-0.5, 0.5))
            if bi % 4 == 0:
                arp = voice(notes, 67, 96)
                for k, m in enumerate(arp + [a + 12 for a in arp][:3]):
                    place(brt, sample("orchestral_harp", m, 1.0, 0.28, 0.8), bt + k * 0.06, 0.4)
            if bi >= 16:
                for (b, d, m) in ma[bi - 16]:
                    place(brt, sample("flute", m - 5 if m > 76 else m + 7, d * beat, 0.24, 0.2), bt + b * beat + beat * 0.5, -0.3)
    stems = {}
    for name, buf, wet, gain in (("gh_base", base, 0.18, 0.4), ("gh_melody", melo, 0.3, 2.1), ("gh_bright", brt, 0.4, 1.1)):
        x = reverb(hp(buf, 30), wet) * gain
        stems[name] = loopify(x, loop)
    for k, v in master(stems).items():
        write_ogg(k, v)

if __name__ == "__main__":
    what = sys.argv[2] if len(sys.argv) > 2 else "all"
    if what in ("all", "title"):
        render_title()
    if what in ("all", "gh"):
        render_greenhouse()
