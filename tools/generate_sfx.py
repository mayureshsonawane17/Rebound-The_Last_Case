#!/usr/bin/env python3
"""
tools/generate_sfx.py
BounceFlux Procedural SFX & Music Generator
Generates 16-bit 44.1 kHz mono WAVs into assets/audio/sfx/ and assets/audio/music/
Pure Python + numpy + wave. No external audio downloads or dependencies.
"""

import os
import wave
import numpy as np

SAMPLE_RATE = 44100
SFX_DIR = "assets/audio/sfx"
MUSIC_DIR = "assets/audio/music"

def save_wav(filename, samples):
    """Save float samples [-1.0, 1.0] as 16-bit mono 44.1kHz WAV."""
    os.makedirs(os.path.dirname(filename), exist_ok=True)
    samples = np.clip(samples, -1.0, 1.0)
    int_samples = (samples * 32767).astype(np.int16)
    with wave.open(filename, "wb") as wf:
        wf.setnchannels(1)
        wf.setsampwidth(2)
        wf.setframerate(SAMPLE_RATE)
        wf.writeframes(int_samples.tobytes())
    print(f"Generated: {filename} ({len(samples)/SAMPLE_RATE:.2f}s)")

# ── Synthesis Helpers ────────────────────────────────────────────────

def env_adsr(length, a=0.01, d=0.05, s=0.7, r=0.05):
    t = np.linspace(0, 1, length, endpoint=False)
    env = np.zeros(length, dtype=np.float32)
    a_len = int(a * length)
    d_len = int(d * length)
    r_len = int(r * length)
    s_len = max(0, length - a_len - d_len - r_len)
    
    idx = 0
    if a_len > 0:
        env[idx:idx+a_len] = np.linspace(0, 1.0, a_len)
        idx += a_len
    if d_len > 0:
        env[idx:idx+d_len] = np.linspace(1.0, s, d_len)
        idx += d_len
    if s_len > 0:
        env[idx:idx+s_len] = s
        idx += s_len
    if r_len > 0:
        env[idx:idx+r_len] = np.linspace(s, 0.0, r_len)
    return env

def exp_decay(length, decay=5.0):
    t = np.linspace(0, 1, length, endpoint=False)
    return np.exp(-decay * t)

def synth_sine(freqs, n_samples):
    t = np.linspace(0, n_samples / SAMPLE_RATE, n_samples, endpoint=False)
    if isinstance(freqs, (int, float)):
        phase = 2 * np.pi * freqs * t
    else:
        phase = 2 * np.pi * np.cumsum(freqs) / SAMPLE_RATE
    return np.sin(phase)

def synth_triangle(freqs, n_samples):
    s = synth_sine(freqs, n_samples)
    return 2.0 / np.pi * np.arcsin(np.clip(s, -0.999, 0.999))

def synth_square(freqs, n_samples, duty=0.5):
    s = synth_sine(freqs, n_samples)
    return np.where(s > (2 * duty - 1), 1.0, -1.0)

def synth_noise(n_samples):
    return np.random.uniform(-1.0, 1.0, n_samples)

# ── SFX Generators ───────────────────────────────────────────────────

def gen_jump():
    dur = 0.14
    n = int(dur * SAMPLE_RATE)
    freqs = np.linspace(160, 420, n)
    tone = 0.7 * synth_triangle(freqs, n) + 0.3 * synth_sine(freqs, n)
    env = exp_decay(n, decay=3.0)
    return tone * env

def gen_bounce():
    dur = 0.12
    n = int(dur * SAMPLE_RATE)
    freqs = np.linspace(140, 60, n)
    tone = 0.8 * synth_sine(freqs, n) + 0.2 * synth_triangle(freqs, n)
    env = exp_decay(n, decay=6.0)
    return tone * env

def gen_land():
    dur = 0.09
    n = int(dur * SAMPLE_RATE)
    freqs = np.linspace(95, 45, n)
    noise = synth_noise(n) * exp_decay(n, decay=8.0) * 0.35
    thud = synth_sine(freqs, n) * exp_decay(n, decay=5.0) * 0.65
    return noise + thud

def gen_evidence_collect():
    dur = 0.32
    n = int(dur * SAMPLE_RATE)
    n1 = int(n * 0.45)
    n2 = n - n1
    t1 = synth_sine(587.33, n1) * exp_decay(n1, decay=2.5) # D5
    t2 = synth_sine(880.00, n2) * exp_decay(n2, decay=2.0) # A5
    tone = np.concatenate([t1, t2])
    shimmer = synth_sine(1760.0, n) * exp_decay(n, decay=4.0) * 0.2
    return (tone * 0.8 + shimmer)

def gen_checkpoint():
    dur = 0.45
    n = int(dur * SAMPLE_RATE)
    n_part = n // 3
    c1 = synth_triangle(440.0, n_part) * exp_decay(n_part, decay=1.5) # A4
    c2 = synth_triangle(554.37, n_part) * exp_decay(n_part, decay=1.5) # C#5
    c3 = synth_triangle(659.25, n - 2*n_part) * exp_decay(n - 2*n_part, decay=1.0) # E5
    return np.concatenate([c1, c2, c3]) * 0.85

def gen_hit():
    dur = 0.18
    n = int(dur * SAMPLE_RATE)
    freqs = np.linspace(220, 60, n)
    noise = synth_noise(n) * exp_decay(n, decay=6.0) * 0.6
    tone = synth_square(freqs, n) * exp_decay(n, decay=8.0) * 0.4
    return noise + tone

def gen_death():
    dur = 0.75
    n = int(dur * SAMPLE_RATE)
    freqs = np.linspace(180, 30, n)
    sweep = synth_triangle(freqs, n) * exp_decay(n, decay=2.0) * 0.7
    noise = synth_noise(n) * exp_decay(n, decay=3.5) * 0.35
    return sweep + noise

def gen_rewind_start():
    dur = 0.22
    n = int(dur * SAMPLE_RATE)
    freqs = np.linspace(150, 600, n)
    sweep = synth_sine(freqs, n) * exp_decay(n, decay=1.5)
    flutter = synth_noise(n) * exp_decay(n, decay=4.0) * 0.25
    return sweep * 0.75 + flutter

def gen_rewind_loop():
    dur = 0.6
    n = int(dur * SAMPLE_RATE)
    t = np.linspace(0, dur, n, endpoint=False)
    carrier = synth_sine(220.0 + 30.0 * np.sin(2 * np.pi * 6.0 * t), n)
    pulse_env = np.abs(np.sin(2 * np.pi * 5.0 * t)) ** 3
    return carrier * pulse_env * 0.65

def gen_rewind_end():
    dur = 0.15
    n = int(dur * SAMPLE_RATE)
    freqs = np.linspace(600, 200, n)
    tone = synth_triangle(freqs, n) * exp_decay(n, decay=5.0) * 0.8
    click = synth_noise(n) * exp_decay(n, decay=12.0) * 0.4
    return tone + click

def gen_power_node_hum():
    dur = 0.5
    n = int(dur * SAMPLE_RATE)
    hum = 0.7 * synth_sine(60.0, n) + 0.3 * synth_sine(120.0, n)
    return hum * 0.5

def gen_arc_zap():
    dur = 0.2
    n = int(dur * SAMPLE_RATE)
    noise = synth_noise(n) * exp_decay(n, decay=4.5) * 0.75
    buzz = synth_square(np.linspace(240, 80, n), n) * exp_decay(n, decay=6.0) * 0.35
    return noise + buzz

def gen_guard_alert():
    dur = 0.22
    n = int(dur * SAMPLE_RATE)
    freqs = np.linspace(440, 880, n)
    tone = synth_square(freqs, n, duty=0.3) * exp_decay(n, decay=2.5) * 0.6
    return tone

def gen_guard_shoot():
    dur = 0.2
    n = int(dur * SAMPLE_RATE)
    click = synth_noise(n) * exp_decay(n, decay=10.0) * 0.7
    snap = synth_triangle(np.linspace(500, 90, n), n) * exp_decay(n, decay=7.0) * 0.4
    return click + snap

def gen_guard_defeat():
    dur = 0.35
    n = int(dur * SAMPLE_RATE)
    thud = synth_sine(np.linspace(120, 40, n), n) * exp_decay(n, decay=3.5) * 0.7
    rustle = synth_noise(n) * exp_decay(n, decay=5.0) * 0.35
    return thud + rustle

def gen_portal():
    dur = 0.45
    n = int(dur * SAMPLE_RATE)
    t = np.linspace(0, dur, n, endpoint=False)
    mod = 250.0 + 120.0 * np.sin(2 * np.pi * 4.0 * t)
    s = synth_sine(mod, n) * exp_decay(n, decay=1.2) * 0.8
    return s

def gen_stage_clear():
    dur = 0.65
    n = int(dur * SAMPLE_RATE)
    n_seg = n // 3
    a1 = synth_sine(392.0, n_seg) * exp_decay(n_seg, decay=1.0)
    a2 = synth_sine(493.88, n_seg) * exp_decay(n_seg, decay=1.0)
    a3 = synth_sine(587.33, n - 2*n_seg) * exp_decay(n - 2*n_seg, decay=0.8)
    chord = np.concatenate([a1, a2, a3]) * 0.8
    return chord

def gen_ui_move():
    dur = 0.04
    n = int(dur * SAMPLE_RATE)
    return synth_triangle(600.0, n) * exp_decay(n, decay=8.0) * 0.45

def gen_ui_select():
    dur = 0.08
    n = int(dur * SAMPLE_RATE)
    t1 = synth_triangle(np.linspace(700, 1100, n), n) * exp_decay(n, decay=5.0) * 0.55
    return t1

def gen_ui_back():
    dur = 0.07
    n = int(dur * SAMPLE_RATE)
    t1 = synth_triangle(np.linspace(800, 450, n), n) * exp_decay(n, decay=6.0) * 0.5
    return t1

# ── Loopable Neo-Noir Theme ──────────────────────────────────────────

def gen_music_track(duration=32.0):
    """
    Loopable 32-second neo-noir track:
    - Low drone in A minor (A1: 55Hz, E2: 82.4Hz)
    - Slow minor arpeggio (A minor -> F major -> D minor -> E7)
    - Filtered sub-bass pulse
    """
    num_samples = int(duration * SAMPLE_RATE)
    t = np.linspace(0, duration, num_samples, endpoint=False)
    music = np.zeros(num_samples, dtype=np.float32)

    # 1. Low ambient dark drone
    drone = 0.5 * np.sin(2 * np.pi * 55.0 * t) + 0.3 * np.sin(2 * np.pi * 82.4 * t) + 0.15 * np.sin(2 * np.pi * 110.0 * t)
    # Slow tape flutter
    drone *= (0.85 + 0.15 * np.sin(2 * np.pi * 0.25 * t))
    music += drone * 0.35

    # 2. Chord progression: 4 bars x 8 seconds = 32s
    # Chords (frequencies):
    # Am:  A2(110), C3(130.8), E3(164.8)
    # F:   F2(87.3), A2(110), C3(130.8)
    # Dm:  D2(73.4), F2(87.3), A2(110)
    # E7:  E2(82.4), G#2(103.8), B2(123.5), D3(146.8)
    chords = [
        [110.0, 130.81, 164.81, 220.0],     # Am
        [87.31, 110.0, 130.81, 174.61],     # F
        [73.42, 87.31, 110.0, 146.83],      # Dm
        [82.41, 103.83, 123.47, 164.81],    # E7
    ]

    bar_len = num_samples // len(chords)
    note_dur = 0.5 # 8th notes in 8s bar = 16 notes
    note_samples = int(note_dur * SAMPLE_RATE)

    for bar_idx, chord_freqs in enumerate(chords):
        bar_start = bar_idx * bar_len
        bar_end = bar_start + bar_len
        num_notes = bar_len // note_samples
        for n_i in range(num_notes):
            n_start = bar_start + n_i * note_samples
            n_end = min(bar_end, n_start + note_samples)
            f = chord_freqs[n_i % len(chord_freqs)]
            # Arpeggiated electric piano tone (triangle + soft overtone)
            seg_len = n_end - n_start
            seg_t = np.linspace(0, seg_len / SAMPLE_RATE, seg_len, endpoint=False)
            tone = 0.7 * np.sin(2 * np.pi * f * seg_t) + 0.3 * np.sin(2 * np.pi * f * 2 * seg_t)
            env = np.exp(-3.5 * seg_t)
            music[n_start:n_end] += tone * env * 0.3

    # Smooth crossfade 0.5s at edges for seamless loop
    xfade_samples = int(0.5 * SAMPLE_RATE)
    xfade_in = np.linspace(0, 1, xfade_samples)
    xfade_out = np.linspace(1, 0, xfade_samples)
    music[:xfade_samples] = music[:xfade_samples] * xfade_in + music[-xfade_samples:] * xfade_out

    return music * 0.8

def main():
    print("Generating BounceFlux SFX...")
    sfx_map = {
        "jump.wav": gen_jump(),
        "bounce.wav": gen_bounce(),
        "land.wav": gen_land(),
        "evidence_collect.wav": gen_evidence_collect(),
        "checkpoint.wav": gen_checkpoint(),
        "hit.wav": gen_hit(),
        "death.wav": gen_death(),
        "rewind_start.wav": gen_rewind_start(),
        "rewind_loop.wav": gen_rewind_loop(),
        "rewind_end.wav": gen_rewind_end(),
        "power_node_hum.wav": gen_power_node_hum(),
        "arc_zap.wav": gen_arc_zap(),
        "guard_alert.wav": gen_guard_alert(),
        "guard_shoot.wav": gen_guard_shoot(),
        "guard_defeat.wav": gen_guard_defeat(),
        "portal.wav": gen_portal(),
        "stage_clear.wav": gen_stage_clear(),
        "ui_move.wav": gen_ui_move(),
        "ui_select.wav": gen_ui_select(),
        "ui_back.wav": gen_ui_back(),
    }

    for fname, data in sfx_map.items():
        save_wav(os.path.join(SFX_DIR, fname), data)

    print("\nGenerating BounceFlux Loopable Neo-Noir Music Track...")
    music_track = gen_music_track(32.0)
    save_wav(os.path.join(MUSIC_DIR, "noir_theme.wav"), music_track)
    print("\nAll audio generated successfully!")

if __name__ == "__main__":
    main()
