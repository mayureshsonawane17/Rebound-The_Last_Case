#!/usr/bin/env python3
"""
tools/slice_spritesheet.py
BounceFlux Re-runnable Sprite Sheet Slicer for Godot 4.x
Extracts all animations from art/source/spritesheet_overview.png,
removes near-white background to transparent RGBA with unmultiplied edges,
normalizes frames into uniform cells with consistent bottom-center pivots,
and exports numbered PNG sequences to assets/sprites/<group>/<animation>/.
Also generates Godot 4.x SpriteFrames .tres resources.
"""

import os
import sys
import json
import glob
from collections import deque
from PIL import Image
import numpy as np

SOURCE_PATH = "art/source/spritesheet_overview.png"
OUTPUT_BASE = "assets/sprites"

def remove_white_bg(sub_arr, bg_thresh=18, soft_range=32.0):
    """
    Remove near-white background using exterior flood-fill and edge un-multiplication.
    sub_arr: uint8 (H, W, 3) RGB.
    Returns: uint8 (H, W, 4) RGBA.
    """
    h, w, _ = sub_arr.shape
    dist = 255.0 - np.min(sub_arr, axis=2)
    near_white = dist < bg_thresh

    exterior = np.zeros((h, w), dtype=bool)
    queue = deque()
    for x in range(w):
        if near_white[0, x]: queue.append((0, x)); exterior[0, x] = True
        if near_white[h-1, x]: queue.append((h-1, x)); exterior[h-1, x] = True
    for y in range(h):
        if near_white[y, 0]: queue.append((y, 0)); exterior[y, 0] = True
        if near_white[y, w-1]: queue.append((y, w-1)); exterior[y, w-1] = True

    while queue:
        cy, cx = queue.popleft()
        for dy, dx in [(-1, 0), (1, 0), (0, -1), (0, 1)]:
            ny, nx = cy + dy, cx + dx
            if 0 <= ny < h and 0 <= nx < w:
                if not exterior[ny, nx] and near_white[ny, nx]:
                    exterior[ny, nx] = True
                    queue.append((ny, nx))

    fg = ~exterior
    alpha = np.zeros((h, w), dtype=np.float32)
    alpha[fg] = 1.0

    for y in range(h):
        for x in range(w):
            if exterior[y, x]:
                d = dist[y, x]
                if d > 3.0:
                    alpha[y, x] = min(1.0, (d - 3.0) / soft_range)

    rgba = np.zeros((h, w, 4), dtype=np.uint8)
    safe_a = np.maximum(alpha, 1e-4)
    for c in range(3):
        unmult = (sub_arr[:, :, c].astype(np.float32) - 255.0 * (1.0 - alpha)) / safe_a
        rgba[:, :, c] = np.clip(unmult, 0, 255).astype(np.uint8)
    rgba[:, :, 3] = (alpha * 255.0).astype(np.uint8)
    return rgba

def trim_rgba(rgba, pad=1, alpha_thresh=15):
    """Trim empty transparent borders."""
    mask = rgba[:, :, 3] > alpha_thresh
    if not np.any(mask):
        return rgba
    ymin, ymax = np.where(np.any(mask, axis=1))[0][[0, -1]]
    xmin, xmax = np.where(np.any(mask, axis=0))[0][[0, -1]]
    h, w, _ = rgba.shape
    ymin = max(0, ymin - pad)
    ymax = min(h, ymax + 1 + pad)
    xmin = max(0, xmin - pad)
    xmax = min(w, xmax + 1 + pad)
    return rgba[ymin:ymax, xmin:xmax]

def place_in_cell(sprite_rgba, cell_size=(64, 64), pivot="bottom_center", ground_offset=4):
    """
    Places trimmed sprite_rgba inside a cell_size canvas.
    pivot:
      'bottom_center': grounded horizontally at center, bottom at cell_h - ground_offset
      'center': centered horizontally and vertically
    """
    cw, ch = cell_size
    sh, sw, _ = sprite_rgba.shape
    
    if sw > cw or sh > ch:
        scale = min(float(cw) / sw, float(ch) / sh)
        new_w = max(1, int(sw * scale))
        new_h = max(1, int(sh * scale))
        pil_im = Image.fromarray(sprite_rgba).resize((new_w, new_h), Image.NEAREST)
        sprite_rgba = np.array(pil_im)
        sh, sw, _ = sprite_rgba.shape

    cell = np.zeros((ch, cw, 4), dtype=np.uint8)
    
    if pivot == "bottom_center":
        ox = (cw - sw) // 2
        oy = max(0, ch - ground_offset - sh)
    elif pivot == "center":
        ox = (cw - sw) // 2
        oy = (ch - sh) // 2
    else:
        ox, oy = 0, 0

    cell[oy:oy+sh, ox:ox+sw] = sprite_rgba
    return Image.fromarray(cell)

def slice_by_peaks(sub_arr, min_dist=14, thresh=30, dark_core=False, pad_x=2):
    """
    Slice horizontal strip by finding column peaks of content.
    """
    h, w, _ = sub_arr.shape
    if dark_core:
        core = (sub_arr[:, :, 0] < 90) & (sub_arr[:, :, 2] > 70)
        signal = np.sum(core, axis=0)
    else:
        dist = 255.0 - np.min(sub_arr, axis=2)
        signal = np.sum(dist > thresh, axis=0)

    smoothed = np.convolve(signal, np.ones(3)/3.0, mode='same')
    peaks = []
    for x in range(1, len(smoothed)-1):
        if smoothed[x] >= 3 and smoothed[x] >= smoothed[x-1] and smoothed[x] >= smoothed[x+1]:
            if not peaks or x - peaks[-1] >= min_dist:
                peaks.append(x)

    crops = []
    if not peaks:
        crops.append(sub_arr)
        return crops

    # Boundaries are midpoints between peaks
    bounds = [0]
    for i in range(len(peaks) - 1):
        mid = (peaks[i] + peaks[i+1]) // 2
        bounds.append(mid)
    bounds.append(w)

    for i in range(len(peaks)):
        x0 = max(0, bounds[i])
        x1 = min(w, bounds[i+1])
        slice_crop = sub_arr[:, x0:x1]
        dist_slice = 255.0 - np.min(slice_crop, axis=2)
        nz = np.where(np.max(dist_slice, axis=0) > 15)[0]
        if len(nz) > 0:
            cx0 = max(0, x0 + nz[0] - pad_x)
            cx1 = min(w, x0 + nz[-1] + 1 + pad_x)
            crops.append(sub_arr[:, cx0:cx1])
        else:
            crops.append(slice_crop)
    return crops

def slice_by_connectivity(sub_arr, min_w=6, thresh=25, pad_x=2):
    """
    Slice horizontal strip by finding non-empty column intervals.
    """
    h, w, _ = sub_arr.shape
    dist = 255.0 - np.min(sub_arr, axis=2)
    has_content = np.max(dist, axis=0) > thresh

    intervals = []
    in_i = False
    s = 0
    for x, v in enumerate(has_content):
        if v and not in_i:
            in_i = True
            s = x
        elif not v and in_i:
            in_i = False
            if x - s >= min_w:
                intervals.append((s, x))
    if in_i and w - s >= min_w:
        intervals.append((s, w))

    crops = []
    for s, e in intervals:
        pad_s = max(0, s - pad_x)
        pad_e = min(w, e + pad_x)
        crops.append(sub_arr[:, pad_s:pad_e])
    return crops

def export_animation(crops, out_dir, cell_size, pivot="bottom_center", ground_offset=4):
    os.makedirs(out_dir, exist_ok=True)
    frames = []
    for idx, crop in enumerate(crops):
        rgba = remove_white_bg(crop)
        trimmed = trim_rgba(rgba)
        if trimmed.shape[0] < 2 or trimmed.shape[1] < 2:
            continue
        cell_img = place_in_cell(trimmed, cell_size=cell_size, pivot=pivot, ground_offset=ground_offset)
        out_file = os.path.join(out_dir, f"{len(frames):02d}.png")
        cell_img.save(out_file)
        frames.append(out_file)
    return frames

def generate_sprite_frames_tres(group_name, anim_dict, tres_path):
    """
    anim_dict: { anim_name: [list of relative image paths res://...] }
    """
    ext_resources = []
    res_id_map = {}
    
    all_paths = []
    for anim_name, paths in anim_dict.items():
        all_paths.extend(paths)
        
    for idx, p in enumerate(all_paths):
        res_id = f"Ext_{idx+1}"
        res_id_map[p] = res_id
        ext_resources.append(f'[ext_resource type="Texture2D" path="{p}" id="{res_id}"]')
        
    anim_blocks = []
    for anim_name, paths in anim_dict.items():
        frame_entries = []
        for p in paths:
            rid = res_id_map[p]
            frame_entries.append(f'{{\n"duration": 1.0,\n"texture": ExtResource("{rid}")\n}}')
        frames_joined = ",\n".join(frame_entries)
        loop_str = "true" if anim_name in ["idle", "run", "walk", "bounce", "effect", "aura"] else "false"
        speed = 10.0 if anim_name in ["idle", "run", "walk"] else 12.0
        anim_blocks.append(f"""{{
"frames": [
{frames_joined}
],
"loop": {loop_str},
"name": &"{anim_name}",
"speed": {speed}
}}""")

    anims_joined = ",\n".join(anim_blocks)
    load_steps = len(ext_resources) + 1
    content = f"""[gd_resource type="SpriteFrames" load_steps={load_steps} format=3]

""" + "\n".join(ext_resources) + f"""

[resource]
animations = [
{anims_joined}
]
"""
    with open(tres_path, "w") as f:
        f.write(content)
    print(f"Generated {tres_path}")

def run_slicer():
    if not os.path.exists(SOURCE_PATH):
        print(f"Error: {SOURCE_PATH} not found!")
        sys.exit(1)

    img = Image.open(SOURCE_PATH)
    arr = np.array(img)
    print(f"Loaded {SOURCE_PATH} (size: {img.size})")

    report = {}

    # ─────────────────────────────────────────────────────────────
    # 1. BALL ANIMATIONS (Cell: 64x64, pivot: bottom_center, ground_offset=8)
    # ─────────────────────────────────────────────────────────────
    ball_specs = [
        ("idle", 16, (22, 65, 10, 520), {"min_dist": 22, "dark_core": True}),
        ("run", 24, (78, 120, 10, 520), {"min_dist": 16, "dark_core": True}),
        ("jump", 16, (132, 172, 10, 520), {"min_dist": 20, "dark_core": True}),
        ("fall", 12, (185, 228, 10, 520), {"min_dist": 24, "dark_core": True}),
        ("land", 16, (238, 275, 10, 520), {"min_dist": 22, "dark_core": True}),
        ("bounce", 20, (285, 323, 10, 520), {"min_dist": 20, "dark_core": True}),
        ("wall_jump", 12, (332, 372, 10, 520), {"min_dist": 24, "dark_core": True}),
        ("hit", 12, (382, 419, 10, 520), {"min_dist": 25, "dark_core": True}),
        ("death", 16, (428, 465, 10, 520), {"min_dist": 24, "dark_core": False}),
    ]

    ball_frames_map = {}
    for name, labeled_count, box, opts in ball_specs:
        y0, y1, x0, x1 = box
        sub = arr[y0:y1, x0:x1]
        crops = slice_by_peaks(sub, min_dist=opts["min_dist"], dark_core=opts["dark_core"])
        out_dir = os.path.join(OUTPUT_BASE, "ball", name)
        frames = export_animation(crops, out_dir, cell_size=(64, 64), pivot="bottom_center", ground_offset=8)
        ball_frames_map[name] = [f"res://{f}" for f in frames]
        report[f"ball/{name}"] = {"labeled": labeled_count, "extracted": len(frames)}

    # ─────────────────────────────────────────────────────────────
    # 2. REWIND ANIMATIONS (Cell: 64x64, pivot: center)
    # ─────────────────────────────────────────────────────────────
    rewind_specs = [
        ("effect", 24, (22, 65, 535, 1020), {"min_dist": 16}),
        ("aura", 16, (80, 120, 535, 1020), {"min_dist": 18}),
        ("restore", 12, (136, 175, 535, 1020), {"min_dist": 24}),
    ]

    rewind_frames_map = {}
    for name, labeled_count, box, opts in rewind_specs:
        y0, y1, x0, x1 = box
        sub = arr[y0:y1, x0:x1]
        crops = slice_by_peaks(sub, min_dist=opts["min_dist"], dark_core=False)
        out_dir = os.path.join(OUTPUT_BASE, "rewind", name)
        frames = export_animation(crops, out_dir, cell_size=(64, 64), pivot="center")
        rewind_frames_map[name] = [f"res://{f}" for f in frames]
        report[f"rewind/{name}"] = {"labeled": labeled_count, "extracted": len(frames)}

    # ─────────────────────────────────────────────────────────────
    # 3. GUARD ANIMATIONS (Cell: 96x96, pivot: bottom_center, ground_offset=10)
    # ─────────────────────────────────────────────────────────────
    guard_specs = [
        ("idle", 8, (215, 260, 595, 645), {"min_dist": 12}),
        ("walk", 16, (215, 260, 650, 840), {"min_dist": 12}),
        ("alert", 8, (215, 260, 845, 930), {"min_dist": 14}),
        ("aim", 8, (265, 315, 595, 680), {"min_dist": 14}),
        ("shoot", 10, (265, 315, 685, 795), {"min_dist": 14}),
        ("hit", 8, (265, 315, 795, 855), {"min_dist": 14}),
        ("defeat", 12, (265, 315, 855, 1005), {"min_dist": 16}),
    ]

    guard_frames_map = {}
    for name, labeled_count, box, opts in guard_specs:
        y0, y1, x0, x1 = box
        sub = arr[y0:y1, x0:x1]
        crops = slice_by_peaks(sub, min_dist=opts["min_dist"], dark_core=True)
        out_dir = os.path.join(OUTPUT_BASE, "guard", name)
        frames = export_animation(crops, out_dir, cell_size=(96, 96), pivot="bottom_center", ground_offset=10)
        guard_frames_map[name] = [f"res://{f}" for f in frames]
        report[f"guard/{name}"] = {"labeled": labeled_count, "extracted": len(frames)}

    # Guard portrait
    p_crop = arr[195:300, 530:590]
    p_rgba = trim_rgba(remove_white_bg(p_crop))
    p_cell = place_in_cell(p_rgba, cell_size=(96, 96), pivot="bottom_center", ground_offset=10)
    p_dir = os.path.join(OUTPUT_BASE, "guard", "portrait")
    os.makedirs(p_dir, exist_ok=True)
    p_cell.save(os.path.join(p_dir, "00.png"))
    guard_frames_map["portrait"] = [f"res://{p_dir}/00.png"]

    # ─────────────────────────────────────────────────────────────
    # 4. BOSS ANIMATIONS (Cell: 128x128, pivot: bottom_center, ground_offset=12)
    # ─────────────────────────────────────────────────────────────
    boss_specs = [
        ("idle", 8, (345, 400, 585, 680), {"min_dist": 12}),
        ("attack", 16, (345, 400, 685, 845), {"min_dist": 14}),
        ("hit", 10, (345, 400, 845, 950), {"min_dist": 14}),
        ("defeat", 12, (405, 460, 730, 1010), {"min_dist": 16}),
    ]

    boss_frames_map = {}
    for name, labeled_count, box, opts in boss_specs:
        y0, y1, x0, x1 = box
        sub = arr[y0:y1, x0:x1]
        crops = slice_by_peaks(sub, min_dist=opts["min_dist"], dark_core=True)
        out_dir = os.path.join(OUTPUT_BASE, "boss", name)
        frames = export_animation(crops, out_dir, cell_size=(128, 128), pivot="bottom_center", ground_offset=12)
        boss_frames_map[name] = [f"res://{f}" for f in frames]
        report[f"boss/{name}"] = {"labeled": labeled_count, "extracted": len(frames)}

    # Boss portrait
    bp_crop = arr[330:450, 520:585]
    bp_rgba = trim_rgba(remove_white_bg(bp_crop))
    bp_cell = place_in_cell(bp_rgba, cell_size=(128, 128), pivot="bottom_center", ground_offset=12)
    bp_dir = os.path.join(OUTPUT_BASE, "boss", "portrait")
    os.makedirs(bp_dir, exist_ok=True)
    bp_cell.save(os.path.join(bp_dir, "00.png"))
    boss_frames_map["portrait"] = [f"res://{bp_dir}/00.png"]

    # ─────────────────────────────────────────────────────────────
    # 5. VFX ANIMATIONS (Cell: 96x96, pivot: center)
    # ─────────────────────────────────────────────────────────────
    vfx_specs = [
        ("bounce_impact", 12, (490, 535, 5, 160), {"min_dist": 16}),
        ("dash_trail", 16, (490, 535, 165, 265), {"min_dist": 16}),
        ("ground_dash", 16, (490, 535, 270, 375), {"min_dist": 18}),
        ("spark", 8, (490, 535, 380, 445), {"min_dist": 14}),
        ("explosion", 16, (490, 535, 455, 575), {"min_dist": 22}),
        ("collect_spark", 12, (490, 535, 580, 680), {"min_dist": 16}),
        ("portal", 12, (490, 535, 690, 830), {"min_dist": 18}),
        ("stage_transition", 16, (490, 535, 840, 1020), {"min_dist": 16}),
    ]

    vfx_frames_map = {}
    for name, labeled_count, box, opts in vfx_specs:
        y0, y1, x0, x1 = box
        sub = arr[y0:y1, x0:x1]
        crops = slice_by_peaks(sub, min_dist=opts["min_dist"], dark_core=False)
        out_dir = os.path.join(OUTPUT_BASE, "vfx", name)
        cs = (128, 64) if name in ["dash_trail", "stage_transition"] else (96, 96)
        frames = export_animation(crops, out_dir, cell_size=cs, pivot="center")
        vfx_frames_map[name] = [f"res://{f}" for f in frames]
        report[f"vfx/{name}"] = {"labeled": labeled_count, "extracted": len(frames)}

    # ─────────────────────────────────────────────────────────────
    # 6. PROPS & HAZARDS
    # ─────────────────────────────────────────────────────────────
    props_specs = [
        ("props", "evidence", 8, (560, 605, 10, 160), {"min_dist": 18}),
        ("props", "checkpoint", 8, (560, 605, 165, 275), {"min_dist": 18}),
        ("props", "crate", 3, (560, 605, 280, 430), {"min_dist": 30}),
        ("hazards", "spikes", 4, (560, 605, 440, 540), {"min_dist": 22}),
        ("hazards", "electric_arc", 16, (560, 605, 545, 660), {"min_dist": 20}),
        ("hazards", "power_node", 8, (560, 605, 665, 760), {"min_dist": 20}),
    ]

    for group, name, labeled_count, box, opts in props_specs:
        y0, y1, x0, x1 = box
        sub = arr[y0:y1, x0:x1]
        crops = slice_by_peaks(sub, min_dist=opts["min_dist"], dark_core=False)
        out_dir = os.path.join(OUTPUT_BASE, group, name)
        cs = (128, 48) if name == "electric_arc" else (64, 64)
        frames = export_animation(crops, out_dir, cell_size=cs, pivot="bottom_center", ground_offset=4)
        report[f"{group}/{name}"] = {"labeled": labeled_count, "extracted": len(frames)}

    # ─────────────────────────────────────────────────────────────
    # 7. PLATFORM TILES (y: 630..675, x: 5..470)
    # ─────────────────────────────────────────────────────────────
    tiles_sub = arr[630:675, 5:470]
    tile_crops = slice_by_connectivity(tiles_sub, min_w=10, thresh=25)
    tiles_dir = os.path.join(OUTPUT_BASE, "tiles")
    os.makedirs(tiles_dir, exist_ok=True)
    tile_names = ["ground", "hazard", "inset", "block", "slope", "pillar", "scaffold_wide", "scaffold_mid", "crate_tile", "ladder"]
    for idx, crop in enumerate(tile_crops):
        t_rgba = trim_rgba(remove_white_bg(crop))
        t_img = Image.fromarray(t_rgba)
        name = tile_names[idx] if idx < len(tile_names) else f"tile_{idx:02d}"
        t_img.save(os.path.join(tiles_dir, f"{name}.png"))
    report["tiles"] = {"labeled": 10, "extracted": len(tile_crops)}

    # ─────────────────────────────────────────────────────────────
    # 8. UI ELEMENTS (y: 632..665, x: 480..760)
    # ─────────────────────────────────────────────────────────────
    ui_sub = arr[632:665, 480:760]
    ui_crops = slice_by_connectivity(ui_sub, min_w=8, thresh=25)
    ui_dir = os.path.join(OUTPUT_BASE, "ui")
    os.makedirs(ui_dir, exist_ok=True)
    ui_names = ["heart", "coin", "gem", "gear", "pause", "play", "check", "cross", "document"]
    for idx, crop in enumerate(ui_crops):
        u_rgba = trim_rgba(remove_white_bg(crop))
        u_cell = place_in_cell(u_rgba, cell_size=(32, 32), pivot="center")
        name = ui_names[idx] if idx < len(ui_names) else f"icon_{idx:02d}"
        u_cell.save(os.path.join(ui_dir, f"{name}.png"))
    report["ui"] = {"labeled": 9, "extracted": len(ui_crops)}

    # ─────────────────────────────────────────────────────────────
    # 9. STORY PANELS (y: 560..665, x: 780..1020)
    # ─────────────────────────────────────────────────────────────
    story_dir = os.path.join(OUTPUT_BASE, "story")
    os.makedirs(story_dir, exist_ok=True)
    # The 3 panels are at x intervals: (784, 848), (854, 928), (934, 1016)
    p_intervals = [(784, 848), (854, 928), (934, 1016)]
    for idx, (px0, px1) in enumerate(p_intervals):
        crop = arr[560:665, px0:px1]
        s_rgba = trim_rgba(remove_white_bg(crop))
        s_img = Image.fromarray(s_rgba)
        s_img.save(os.path.join(story_dir, f"panel_{idx+1}.png"))
    report["story"] = {"labeled": 3, "extracted": len(p_intervals)}

    # ─────────────────────────────────────────────────────────────
    # GENERATE GODOT SPRITEFRAMES RESOURCES (.tres)
    # ─────────────────────────────────────────────────────────────
    os.makedirs("assets/sprites/ball", exist_ok=True)
    generate_sprite_frames_tres("ball", ball_frames_map, "assets/sprites/ball/ball_frames.tres")

    os.makedirs("assets/sprites/guard", exist_ok=True)
    generate_sprite_frames_tres("guard", guard_frames_map, "assets/sprites/guard/guard_frames.tres")

    os.makedirs("assets/sprites/boss", exist_ok=True)
    generate_sprite_frames_tres("boss", boss_frames_map, "assets/sprites/boss/boss_frames.tres")

    os.makedirs("assets/sprites/rewind", exist_ok=True)
    generate_sprite_frames_tres("rewind", rewind_frames_map, "assets/sprites/rewind/rewind_frames.tres")

    os.makedirs("assets/sprites/vfx", exist_ok=True)
    generate_sprite_frames_tres("vfx", vfx_frames_map, "assets/sprites/vfx/vfx_frames.tres")

    # Save summary report
    with open("assets/sprites/slicing_report.json", "w") as f:
        json.dump(report, f, indent=2)

    print("\n--- SLICING SUMMARY REPORT ---")
    for k, v in report.items():
        diff = v["extracted"] - v["labeled"]
        status = "MATCH" if diff == 0 else f"MISMATCH ({diff:+d})"
        print(f"  {k:24s} -> Labeled: {v['labeled']:2d} | Extracted: {v['extracted']:2d} | {status}")
    print("\nSlicing completed successfully!")

if __name__ == "__main__":
    run_slicer()
