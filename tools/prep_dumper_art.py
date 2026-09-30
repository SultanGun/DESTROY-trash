"""Normalize the dumper sprite set.

Canonical geometry is derived from mc/idle (the only internally consistent set:
all four frames share feet y=1251), so the normalized set matches the standing
pose the player already renders with.  Canvas stays 1280x1280 so the existing
AnimatedSprite2D `scale = 0.1` and the CharacterBody2D FOOT_Y convention keep
working unchanged (origin -> feet = 1251-640 = 611px = 61.1 world px, same as
today's mc/idle).

Every frame is resampled to a common content height with LANCZOS and pasted at
integer offsets - no per-direction drift, no vertical bob, no lateral wobble.
"""
import os, re
from PIL import Image

PROJ = r"C:\Users\HP\Documents\destroy-trash"
MC = os.path.join(PROJ, "assets", "sprites", "mc")
DST_ROOT = os.path.join(PROJ, "assets", "sprites", "dumper")
NEW = {"right": r"C:\Users\HP\Downloads\kanan sprite",
       "left":  r"C:\Users\HP\Downloads\kiri sprite\KIRI"}

CANVAS = 1280
CENTER_X = 640
CROP_ALPHA = 4

# direction -> [(source filename, output filename)]
PLAN = {
    "right": [("1 (1).png", "1.png"), ("2.png", "2.png"),
              ("3 (1).png", "3.png"), ("4.png", "4.png")],
    "left":  [("1.png", "1.png"), ("2.png", "2.png"),
              ("3.png", "3.png"), ("5.png", "4.png")],
    "front": [(f"{i}.png", f"{i}.png") for i in range(1, 5)],
    "back":  [(f"{i}.png", f"{i}.png") for i in range(1, 6)],
    "idle":  [(f"{i}.png", f"{i}.png") for i in range(1, 5)],
}


def bbox_of(im):
    a = im.getchannel("A").point(lambda v: 255 if v >= CROP_ALPHA else 0)
    return a.getbbox()


def trimmed(path):
    im = Image.open(path).convert("RGBA")
    bb = bbox_of(im)
    if bb is None:
        raise SystemExit(f"blank frame: {path}")
    return im.crop(bb), bb


# ---- canonical geometry from mc/idle frame 1 -------------------------------
_, ref_bb = trimmed(os.path.join(MC, "idle", "1.png"))
CANON_H = ref_bb[3] - ref_bb[1]     # 1163
FEET_Y = ref_bb[3]                  # 1251
print(f"canonical: height={CANON_H}  feet_y={FEET_Y}  "
      f"origin->feet={(FEET_Y - CENTER_X) / 10:.1f} world px @scale 0.1")

report = []
for direction, files in PLAN.items():
    src_dir = NEW.get(direction) or os.path.join(MC, direction)
    out_dir = os.path.join(DST_ROOT, direction)
    os.makedirs(out_dir, exist_ok=True)
    print(f"\n===== {direction}  src={src_dir}")
    for src_name, out_name in files:
        cropped, bb = trimmed(os.path.join(src_dir, src_name))
        w, h = cropped.size
        k = CANON_H / h
        nw, nh = max(1, round(w * k)), CANON_H
        res = cropped.resize((nw, nh), Image.LANCZOS)
        # LANCZOS ringing can drop the faintest foot pixels below the alpha
        # threshold, so converge on the measured result instead of trusting the
        # paste rect: paste, measure, correct, repeat.  2-3 passes is typical.
        dx = round(CENTER_X - nw / 2.0)
        dy = FEET_Y - nh
        vb = None
        for attempt in range(5):
            canvas = Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 0))
            canvas.paste(res, (dx, dy), res)
            vb = bbox_of(canvas)
            if vb is None:
                raise SystemExit(f"blank output: {direction}/{src_name}")
            err_feet = FEET_Y - vb[3]
            err_cx = CENTER_X - (vb[0] + vb[2]) / 2.0
            if err_feet == 0 and err_cx == 0:
                break
            dx += round(err_cx)
            dy += err_feet
        out_path = os.path.join(out_dir, out_name)
        if dx < 0 or dx + nw > CANVAS or dy < 0 or dy + nh > CANVAS:
            raise SystemExit(f"would clip: {direction}/{src_name} "
                             f"nw={nw} dx={dx} nh={nh} dy={dy}")
        canvas.save(out_path)
        vb = bbox_of(Image.open(out_path).convert("RGBA"))
        cx = (vb[0] + vb[2]) / 2.0
        # Invariants that actually govern animation stability:
        #  - feet land on the canonical line (no vertical bob between frames)
        #  - horizontal centre is within 1px (no lateral wobble; odd widths
        #    cannot centre exactly on an even canvas)
        #  - nothing clipped by the canvas
        # The silhouette *top* legitimately varies by a few px because the
        # extreme head row is sub-threshold antialiasing after LANCZOS; that
        # is reported, not asserted.
        inside = 0 <= vb[0] and vb[2] <= CANVAS and 0 <= vb[1] and vb[3] <= CANVAS
        ok = (vb[3] == FEET_Y) and abs(cx - CENTER_X) <= 1 and inside
        report.append((direction, out_name, vb, ok))
        print(f"  {src_name:<12} {w}x{h} k={k:.4f} -> {nw}x{nh} "
              f"feet={vb[3]} cx={cx:.1f} top={vb[1]} vis_h={vb[3]-vb[1]} "
              f"{'OK' if ok else 'FAIL'}")

print("\n########## verification ##########")
bad = [r for r in report if not r[3]]
for direction, out_name, vb, ok in report:
    print(f"  {direction:<6} {out_name:<8} bbox={vb} {'OK' if ok else 'FAIL'}")
feet = sorted({r[2][3] for r in report})
cxs = sorted({round((r[2][0] + r[2][2]) / 2.0, 1) for r in report})
tops = sorted({r[2][1] for r in report})
print(f"\nfeet lines      : {feet}   (must be [{FEET_Y}])")
print(f"centres x       : {cxs}   (must all be within 1 of {CENTER_X})")
print(f"silhouette tops : {tops}   (informational, antialias spread)")
print(f"frames={len(report)}  aligned={len(report) - len(bad)}  FAIL={len(bad)}")
if bad:
    raise SystemExit("alignment failures present")
print("\n########## final set ##########")
for d in sorted(os.listdir(DST_ROOT)):
    p = os.path.join(DST_ROOT, d)
    if os.path.isdir(p):
        n = sorted(f for f in os.listdir(p) if f.endswith(".png"))
        print(f"  {d:<6} {len(n)}: {n}")
