#!/usr/bin/env python3
"""
tools/slice_spritesheet.py
BounceFlux Re-runnable Sprite Sheet Slicer for Godot 4.x
Extracts all animations from art/source/spritesheet_overview.png:
- Glow/VFX sprites (ball, rewind, VFX, portal, evidence, power node, arc):
  uses Color to Alpha against white with un-premultiplied RGB.
- Solid sprites (guard, boss, crate, spikes, tiles, flag):
  uses border flood-fill with edge defringing.
- Strict frame isolation via valley bounds & connected components (no neighbor slivers).
- Normalizes into uniform cells with consistent bottom-center / center pivots.
- Generates Godot 4.x SpriteFrames .tres resources.
"""

import os
import sys
import json
from collections import deque
from PIL import Image
import numpy as np

SOURCE_PATH = "art/source/spritesheet_overview.png"
OUTPUT_BASE = "assets/sprites"

def color_to_alpha_white(rgb_arr, white_cutoff=246, min_alpha=0.035):
    """
    Color-to-alpha against white for glowing sprites.
    alpha = 1 - min(r,g,b)/255, then un-premultiply color:
    c = (c - 255*(1-alpha)) / alpha
    """
    rgb = rgb_arr.astype(np.float32)
    min_v = np.min(rgb, axis=2)
    alpha = np.where(min_v >= white_cutoff, 0.0, 1.0 - (min_v / 255.0))
    alpha = np.where(alpha < min_alpha, 0.0, alpha)
    
    safe_a = np.maximum(alpha, 1e-5)
    unmult = np.zeros_like(rgb)
    for c in range(3):
        unmult[:, :, c] = (rgb[:, :, c] - 255.0 * (1.0 - alpha)) / safe_a
    unmult = np.clip(unmult, 0, 255).astype(np.uint8)
    a_byte = np.clip(alpha * 255.0, 0, 255).astype(np.uint8)
    return np.dstack([unmult, a_byte])

def flood_fill_solid(rgb_arr, bg_thresh=225):
    """
    Flood-fill background from image borders for solid sprites, then defringe edge pixels.
    """
    h, w, _ = rgb_arr.shape
    min_v = np.min(rgb_arr, axis=2)
    is_bg_candidate = min_v > bg_thresh
    
    exterior = np.zeros((h, w), dtype=bool)
    queue = deque()
    for x in range(w):
        if is_bg_candidate[0, x]: queue.append((0, x)); exterior[0, x] = True
        if is_bg_candidate[h-1, x]: queue.append((h-1, x)); exterior[h-1, x] = True
    for y in range(h):
        if is_bg_candidate[y, 0]: queue.append((y, 0)); exterior[y, 0] = True
        if is_bg_candidate[y, w-1]: queue.append((y, w-1)); exterior[y, w-1] = True
        
    while queue:
        cy, cx = queue.popleft()
        for dy, dx in [(-1,0),(1,0),(0,-1),(0,1)]:
            ny, nx = cy + dy, cx + dx
            if 0 <= ny < h and 0 <= nx < w:
                if not exterior[ny, nx] and is_bg_candidate[ny, nx]:
                    exterior[ny, nx] = True
                    queue.append((ny, nx))
                    
    fg = ~exterior
    # Defringe edge pixels:
    touch_ext = np.zeros((h, w), dtype=bool)
    touch_ext[1:, :] |= exterior[:-1, :]
    touch_ext[:-1, :] |= exterior[1:, :]
    touch_ext[:, 1:] |= exterior[:, :-1]
    touch_ext[:, :-1] |= exterior[:, 1:]
    
    alpha = np.where(fg, 255, 0).astype(np.uint8)
    # If edge pixel is very light (residual white border), erase it
    edge_near_white = fg & touch_ext & (min_v > 180)
    alpha[edge_near_white] = 0
    
    # Soft defringe for intermediate edge pixels
    soft_edge = fg & touch_ext & (min_v > 120) & ~edge_near_white
    if np.any(soft_edge):
        edge_a = (1.0 - (min_v[soft_edge].astype(np.float32) - 120.0) / 135.0)
        alpha[soft_edge] = np.clip(edge_a * 255.0, 0, 255).astype(np.uint8)
        
    rgba = np.dstack([rgb_arr, alpha])
    return rgba

def trim_rgba(rgba, pad=1, alpha_thresh=10):
    """Trim transparent borders."""
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

def slice_strip_isolated(sub_rgb, is_glow=True, min_dist=14, dark_core=False, cell_size=(64, 64), pivot="bottom_center", ground_offset=4):
    """
    Converts strip to RGBA (glow or solid), finds peaks and valley boundaries,
    and isolates each frame strictly within its valley bounds to prevent any neighbor bleed.
    """
    h, w, _ = sub_rgb.shape
    if is_glow:
        rgba = color_to_alpha_white(sub_rgb)
    else:
        rgba = flood_fill_solid(sub_rgb)
        
    alpha_norm = rgba[:, :, 3].astype(np.float32) / 255.0
    if dark_core:
        # Detect character silhouettes
        core = (sub_rgb[:, :, 0] < 90) & (sub_rgb[:, :, 2] > 70)
        signal = np.sum(core, axis=0).astype(np.float32)
    else:
        signal = np.sum(alpha_norm, axis=0)

    smoothed = np.convolve(signal, np.ones(3)/3.0, mode='same')
    peaks = []
    for x in range(1, len(smoothed)-1):
        if smoothed[x] >= 2.0 and smoothed[x] >= smoothed[x-1] and smoothed[x] >= smoothed[x+1]:
            if not peaks or x - peaks[-1] >= min_dist:
                peaks.append(x)

    if not peaks:
        trimmed = trim_rgba(rgba)
        if trimmed.shape[0] >= 2 and trimmed.shape[1] >= 2:
            return [place_in_cell(trimmed, cell_size=cell_size, pivot=pivot, ground_offset=ground_offset)]
        return []

    # Find the minimum-energy valley between consecutive peaks
    valleys = [0]
    for i in range(len(peaks) - 1):
        p1 = peaks[i]
        p2 = peaks[i+1]
        v = p1 + int(np.argmin(smoothed[p1:p2+1]))
        valleys.append(v)
    valleys.append(w)

    cells = []
    for i in range(len(peaks)):
        x0 = valleys[i]
        x1 = valleys[i+1]
        
        # Strictly zero out any pixels outside this frame's valley
        frame_rgba = np.zeros_like(rgba)
        frame_rgba[:, x0:x1] = rgba[:, x0:x1]
        
        trimmed = trim_rgba(frame_rgba, pad=1, alpha_thresh=12)
        if trimmed.shape[0] < 2 or trimmed.shape[1] < 2:
            continue
            
        cell_img = place_in_cell(trimmed, cell_size=cell_size, pivot=pivot, ground_offset=ground_offset)
        cells.append(cell_img)
        
    return cells

def slice_by_connectivity(sub_arr, min_w=8, thresh=25, is_glow=False):
    """Slice non-overlapping horizontal tiles/icons."""
    h, w, _ = sub_arr.shape
    if is_glow:
        rgba = color_to_alpha_white(sub_arr)
    else:
        rgba = flood_fill_solid(sub_arr)
        
    has_content = np.max(rgba[:, :, 3], axis=0) > thresh

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
        frame_rgba = np.zeros_like(rgba)
        frame_rgba[:, s:e] = rgba[:, s:e]
        trimmed = trim_rgba(frame_rgba, pad=0, alpha_thresh=thresh)
        if trimmed.shape[0] >= 2 and trimmed.shape[1] >= 2:
            crops.append(trimmed)
    return crops

def generate_sprite_frames_tres(group_name, anim_dict, tres_path):
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
        loop_str = "true" if anim_name in ["idle", "run", "walk", "bounce", "effect", "aura", "portal", "attack"] else "false"
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

    img = Image.open(SOURCE_PATH).convert("RGB")
    arr = np.array(img)
    print(f"Loaded {SOURCE_PATH} (size: {img.size})")

    report = {}

    # ─────────────────────────────────────────────────────────────
    # 1. BALL ANIMATIONS (Glow = True, Cell: 64x64, pivot: center)
    # ─────────────────────────────────────────────────────────────
    ball_specs = [
        ("idle", 16, (26, 65, 10, 520), {"min_dist": 22, "dark_core": True}),
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
        cells = slice_strip_isolated(sub, is_glow=True, min_dist=opts["min_dist"], dark_core=opts["dark_core"],
                                     cell_size=(64, 64), pivot="center")
        out_dir = os.path.join(OUTPUT_BASE, "ball", name)
        os.makedirs(out_dir, exist_ok=True)
        paths = []
        for idx, cell in enumerate(cells):
            p = os.path.join(out_dir, f"{idx:02d}.png")
            cell.save(p)
            paths.append(f"res://{p}")
        ball_frames_map[name] = paths
        report[f"ball/{name}"] = {"labeled": labeled_count, "extracted": len(cells)}

    # ─────────────────────────────────────────────────────────────
    # 2. REWIND ANIMATIONS (Glow = True, Cell: 64x64, pivot: center)
    # ─────────────────────────────────────────────────────────────
    rewind_specs = [
        ("effect", 24, (26, 65, 535, 1020), {"min_dist": 16}),
        ("aura", 16, (80, 120, 535, 1020), {"min_dist": 18}),
        ("restore", 12, (136, 175, 535, 1020), {"min_dist": 24}),
    ]

    rewind_frames_map = {}
    for name, labeled_count, box, opts in rewind_specs:
        y0, y1, x0, x1 = box
        sub = arr[y0:y1, x0:x1]
        cells = slice_strip_isolated(sub, is_glow=True, min_dist=opts["min_dist"], dark_core=False,
                                     cell_size=(64, 64), pivot="center")
        out_dir = os.path.join(OUTPUT_BASE, "rewind", name)
        os.makedirs(out_dir, exist_ok=True)
        paths = []
        for idx, cell in enumerate(cells):
            p = os.path.join(out_dir, f"{idx:02d}.png")
            cell.save(p)
            paths.append(f"res://{p}")
        rewind_frames_map[name] = paths
        report[f"rewind/{name}"] = {"labeled": labeled_count, "extracted": len(cells)}

    # ─────────────────────────────────────────────────────────────
    # 3. GUARD ANIMATIONS (Solid = True, Cell: 96x96, pivot: bottom_center, ground_offset=6)
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
        cells = slice_strip_isolated(sub, is_glow=False, min_dist=opts["min_dist"], dark_core=True,
                                     cell_size=(96, 96), pivot="bottom_center", ground_offset=6)
        out_dir = os.path.join(OUTPUT_BASE, "guard", name)
        os.makedirs(out_dir, exist_ok=True)
        paths = []
        for idx, cell in enumerate(cells):
            p = os.path.join(out_dir, f"{idx:02d}.png")
            cell.save(p)
            paths.append(f"res://{p}")
        guard_frames_map[name] = paths
        report[f"guard/{name}"] = {"labeled": labeled_count, "extracted": len(cells)}

    # Guard portrait
    p_crop = arr[195:300, 530:590]
    p_rgba = trim_rgba(flood_fill_solid(p_crop))
    p_cell = place_in_cell(p_rgba, cell_size=(96, 96), pivot="bottom_center", ground_offset=6)
    p_dir = os.path.join(OUTPUT_BASE, "guard", "portrait")
    os.makedirs(p_dir, exist_ok=True)
    p_cell.save(os.path.join(p_dir, "00.png"))
    guard_frames_map["portrait"] = [f"res://{p_dir}/00.png"]

    # ─────────────────────────────────────────────────────────────
    # 4. BOSS ANIMATIONS (Solid = True, Cell: 128x128, pivot: bottom_center, ground_offset=8)
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
        cells = slice_strip_isolated(sub, is_glow=False, min_dist=opts["min_dist"], dark_core=True,
                                     cell_size=(128, 128), pivot="bottom_center", ground_offset=8)
        out_dir = os.path.join(OUTPUT_BASE, "boss", name)
        os.makedirs(out_dir, exist_ok=True)
        paths = []
        for idx, cell in enumerate(cells):
            p = os.path.join(out_dir, f"{idx:02d}.png")
            cell.save(p)
            paths.append(f"res://{p}")
        boss_frames_map[name] = paths
        report[f"boss/{name}"] = {"labeled": labeled_count, "extracted": len(cells)}

    # Boss portrait
    bp_crop = arr[330:450, 520:585]
    bp_rgba = trim_rgba(flood_fill_solid(bp_crop))
    bp_cell = place_in_cell(bp_rgba, cell_size=(128, 128), pivot="bottom_center", ground_offset=8)
    bp_dir = os.path.join(OUTPUT_BASE, "boss", "portrait")
    os.makedirs(bp_dir, exist_ok=True)
    bp_cell.save(os.path.join(bp_dir, "00.png"))
    boss_frames_map["portrait"] = [f"res://{bp_dir}/00.png"]

    # ─────────────────────────────────────────────────────────────
    # 5. VFX ANIMATIONS (Glow = True, Cell: 96x96, pivot: center)
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
        cs = (128, 64) if name in ["dash_trail", "stage_transition"] else (96, 96)
        cells = slice_strip_isolated(sub, is_glow=True, min_dist=opts["min_dist"], dark_core=False,
                                     cell_size=cs, pivot="center")
        out_dir = os.path.join(OUTPUT_BASE, "vfx", name)
        os.makedirs(out_dir, exist_ok=True)
        paths = []
        for idx, cell in enumerate(cells):
            p = os.path.join(out_dir, f"{idx:02d}.png")
            cell.save(p)
            paths.append(f"res://{p}")
        vfx_frames_map[name] = paths
        report[f"vfx/{name}"] = {"labeled": labeled_count, "extracted": len(cells)}

    # ─────────────────────────────────────────────────────────────
    # 6. PROPS & HAZARDS
    # ─────────────────────────────────────────────────────────────
    # Evidence (Glow = True, y: 570..605, x: 10..160)
    ev_sub = arr[570:605, 10:160]
    ev_cells = slice_strip_isolated(ev_sub, is_glow=True, min_dist=18, cell_size=(64, 64), pivot="center")
    ev_dir = os.path.join(OUTPUT_BASE, "props", "evidence")
    os.makedirs(ev_dir, exist_ok=True)
    for idx, c in enumerate(ev_cells):
        c.save(os.path.join(ev_dir, f"{idx:02d}.png"))
    report["props/evidence"] = {"labeled": 8, "extracted": len(ev_cells)}

    # Checkpoint Flag (Solid = True, y: 565..605, x: 165..275)
    flag_sub = arr[565:605, 165:275]
    flag_cells = slice_strip_isolated(flag_sub, is_glow=False, min_dist=18, cell_size=(64, 64), pivot="bottom_center", ground_offset=4)
    flag_dir = os.path.join(OUTPUT_BASE, "props", "checkpoint")
    os.makedirs(flag_dir, exist_ok=True)
    for idx, c in enumerate(flag_cells):
        c.save(os.path.join(flag_dir, f"{idx:02d}.png"))
    report["props/checkpoint"] = {"labeled": 8, "extracted": len(flag_cells)}

    # Crate (Solid = True, y: 560..605, x: 280..430)
    crate_sub = arr[560:605, 280:430]
    crate_cells = slice_strip_isolated(crate_sub, is_glow=False, min_dist=30, cell_size=(64, 64), pivot="bottom_center", ground_offset=4)
    crate_dir = os.path.join(OUTPUT_BASE, "props", "crate")
    os.makedirs(crate_dir, exist_ok=True)
    for idx, c in enumerate(crate_cells):
        c.save(os.path.join(crate_dir, f"{idx:02d}.png"))
    report["props/crate"] = {"labeled": 3, "extracted": len(crate_cells)}

    # Spikes (Solid = True, y: 565..605, x: 440..540)
    spikes_sub = arr[565:605, 440:540]
    spikes_cells = slice_strip_isolated(spikes_sub, is_glow=False, min_dist=22, cell_size=(64, 48), pivot="bottom_center", ground_offset=4)
    spikes_dir = os.path.join(OUTPUT_BASE, "hazards", "spikes")
    os.makedirs(spikes_dir, exist_ok=True)
    for idx, c in enumerate(spikes_cells):
        c.save(os.path.join(spikes_dir, f"{idx:02d}.png"))
    report["hazards/spikes"] = {"labeled": 4, "extracted": len(spikes_cells)}

    # Electric Arc (Glow = True, y: 575..595, x: 550..675)
    # Extract the full continuous lightning beam
    arc_full_crop = arr[578:594, 555:675]
    arc_full_rgba = trim_rgba(color_to_alpha_white(arc_full_crop))
    arc_dir = os.path.join(OUTPUT_BASE, "hazards", "electric_arc")
    os.makedirs(arc_dir, exist_ok=True)
    Image.fromarray(arc_full_rgba).save(os.path.join(arc_dir, "beam.png"))
    
    # Also extract individual pulses for animated sprite
    arc_sub = arr[576:595, 550:675]
    arc_cells = slice_strip_isolated(arc_sub, is_glow=True, min_dist=18, cell_size=(128, 48), pivot="center")
    for idx, c in enumerate(arc_cells):
        c.save(os.path.join(arc_dir, f"{idx:02d}.png"))
    report["hazards/electric_arc"] = {"labeled": 16, "extracted": len(arc_cells)}

    # Power Node (Glow = True, y: 565..605, x: 675..760)
    node_sub = arr[565:605, 675:760]
    node_cells = slice_strip_isolated(node_sub, is_glow=True, min_dist=20, cell_size=(64, 64), pivot="bottom_center", ground_offset=4)
    node_dir = os.path.join(OUTPUT_BASE, "hazards", "power_node")
    os.makedirs(node_dir, exist_ok=True)
    for idx, c in enumerate(node_cells):
        c.save(os.path.join(node_dir, f"{idx:02d}.png"))
    report["hazards/power_node"] = {"labeled": 8, "extracted": len(node_cells)}

    # ─────────────────────────────────────────────────────────────
    # 7. PLATFORM TILES (y: 630..675, x: 5..470)
    # ─────────────────────────────────────────────────────────────
    tiles_sub = arr[630:675, 5:470]
    tile_crops = slice_by_connectivity(tiles_sub, min_w=10, thresh=25, is_glow=False)
    tiles_dir = os.path.join(OUTPUT_BASE, "tiles")
    os.makedirs(tiles_dir, exist_ok=True)
    tile_names = ["ground", "hazard", "inset", "block", "slope", "pillar", "scaffold_wide", "scaffold_mid", "crate_tile", "ladder"]
    for idx, crop in enumerate(tile_crops):
        t_img = Image.fromarray(crop)
        name = tile_names[idx] if idx < len(tile_names) else f"tile_{idx:02d}"
        t_img.save(os.path.join(tiles_dir, f"{name}.png"))
    report["tiles"] = {"labeled": 10, "extracted": len(tile_crops)}

    # ─────────────────────────────────────────────────────────────
    # 8. UI ELEMENTS (y: 632..665, x: 480..760)
    # ─────────────────────────────────────────────────────────────
    ui_sub = arr[632:665, 480:760]
    ui_crops = slice_by_connectivity(ui_sub, min_w=8, thresh=25, is_glow=False)
    ui_dir = os.path.join(OUTPUT_BASE, "ui")
    os.makedirs(ui_dir, exist_ok=True)
    ui_names = ["heart", "coin", "gem", "gear", "pause", "play", "check", "cross", "document"]
    for idx, crop in enumerate(ui_crops):
        u_cell = place_in_cell(crop, cell_size=(32, 32), pivot="center")
        name = ui_names[idx] if idx < len(ui_names) else f"icon_{idx:02d}"
        u_cell.save(os.path.join(ui_dir, f"{name}.png"))
    report["ui"] = {"labeled": 9, "extracted": len(ui_crops)}

    # ─────────────────────────────────────────────────────────────
    # 9. STORY PANELS (y: 560..665, x: 780..1020)
    # ─────────────────────────────────────────────────────────────
    story_dir = os.path.join(OUTPUT_BASE, "story")
    os.makedirs(story_dir, exist_ok=True)
    p_intervals = [(784, 848), (854, 928), (934, 1016)]
    for idx, (px0, px1) in enumerate(p_intervals):
        crop = arr[560:665, px0:px1]
        s_rgba = trim_rgba(flood_fill_solid(crop))
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
