#!/usr/bin/env python3
"""Record the outer shape that macOS gives app icons, and the frame shapes inside it.

macOS 26 and later cut an Icon Composer icon to its own rounded shape. Its corners are
not circular arcs, so a frame drawn with circular corners looks narrower at the corners.
This script exports Artwork/TeXShop.icon with Icon Composer's ictool, reads the outer
shape from the transparency of the export, and writes Artwork/Icon-mask-outline.json:
the shape itself and the same shape moved inward by the white rim (48 units) and by the
rim highlight (3 units), in the 1024-unit artwork canvas. Run it from the repository root
when a new macOS design generation changes the icon shape; generate-icon.swift reads
the result. Requires Xcode 26 or later, Pillow, NumPy and SciPy.
"""
from pathlib import Path
import json
import subprocess
import sys
import tempfile

import numpy as np
from PIL import Image
from scipy.interpolate import UnivariateSpline

root = Path(__file__).resolve().parents[1]
ictool = '/Applications/Xcode.app/Contents/Applications/Icon Composer.app/Contents/Executables/ictool'
generation = sys.argv[1] if len(sys.argv) > 1 else '26'
pixels = 4096
scale = pixels / 1024
insets = {'mask': 0, 'field': 48, 'highlight': 3}

with tempfile.TemporaryDirectory() as folder:
    export = Path(folder) / 'icon.png'
    subprocess.run([ictool, str(root / 'Artwork/TeXShop.icon'), '--export-image', '--output-file', str(export),
                    '--platform', 'macOS', '--rendition', 'Default', '--width', '1024', '--height', '1024',
                    '--scale', str(int(scale)), '--design-generation', generation], check=True, capture_output=True)
    alpha = np.array(Image.open(export).convert('RGBA'))[:, :, 3].astype(float) / 255
assert alpha.shape == (pixels, pixels)

# The edge of the shape where it is half transparent, in every row of each corner, folded into
# the top-left corner. The frame covers the whole canvas, so transparency comes from the shape.
points = []
for corner in (alpha, alpha[:, ::-1], alpha[::-1, :], alpha[::-1, ::-1]):
    for image, swap in ((corner, False), (corner.T, True)):
        for row in range(pixels // 2):
            values = image[row, :pixels // 2]
            inside = np.nonzero(values >= 0.5)[0]
            if len(inside) == 0 or inside[0] == 0:
                continue
            i = inside[0]
            x = (i - 0.5 + (0.5 - values[i - 1]) / (values[i] - values[i - 1])) / scale
            y = (row + 0.5) / scale
            points.append((y, x) if swap else (x, y))
points = np.array(points)

# The shape is symmetric about the diagonal. Describe the half below it as x = f(y), from the
# corner's diagonal point to where the edge becomes straight.
lower = np.vstack([points[points[:, 1] >= points[:, 0]], points[points[:, 0] > points[:, 1]][:, ::-1]])
order = np.argsort(lower[:, 1])
y_data, x_data = lower[order, 1], lower[order, 0]
diagonal = float(np.median(points[np.abs(points[:, 0] - points[:, 1]) < 0.5][:, 0]))
keep = y_data >= diagonal - 2
spline = UnivariateSpline(y_data[keep], x_data[keep], k=5, s=keep.sum() * 0.02 ** 2)
residual = np.abs(spline(y_data[keep]) - x_data[keep])
straight = float(y_data[keep][spline(y_data[keep]) > 0.01].max())
print(f'diagonal point {diagonal:.2f}; the edge is straight from {straight:.1f}; '
      f'fit error mean {residual.mean():.3f}, max {residual.max():.3f} units')

def corner(inset, samples=40):
    """Points of the top-left corner moved inward by inset, from the top edge round to the left edge."""
    ys = np.linspace(diagonal, straight, samples)
    xs, slope = spline(ys), spline.derivative()(ys)
    norm = np.sqrt(1 + slope ** 2)
    left = np.column_stack([xs + inset / norm, ys - inset * slope / norm])   # x = f(y), below the diagonal
    left = left[left[:, 0] >= inset - 1e-9]
    left[-1, 0] = inset
    top = left[::-1, ::-1]                                                  # mirrored above the diagonal
    return np.vstack([top[:-1], left])[::-1]

def outline(inset):
    """A closed path: four corners joined by straight edges, as Catmull-Rom curves through the points."""
    c = corner(inset)                       # from the left edge (x = inset) round to the top edge (y = inset)
    quarter = [c, np.column_stack([1024 - c[::-1, 0], c[::-1, 1]]),
               np.column_stack([1024 - c[:, 0], 1024 - c[:, 1]]), np.column_stack([c[::-1, 0], 1024 - c[::-1, 1]])]
    ops = []
    for i, q in enumerate(quarter):
        q = q.tolist()
        ops.append(['moveTo' if i == 0 else 'lineTo', [q[0]]])
        for j in range(len(q) - 1):
            p0, p1, p2 = q[max(j - 1, 0)], q[j], q[j + 1]
            p3 = q[min(j + 2, len(q) - 1)]
            c1 = [p1[k] + (p2[k] - p0[k]) / 6 for k in (0, 1)]
            c2 = [p2[k] - (p3[k] - p1[k]) / 6 for k in (0, 1)]
            ops.append(['curveTo', [c1, c2, p2]])
    ops.append(['closePath', []])
    return [[op, [[round(v, 3) for v in p] for p in pts]] for op, pts in ops]

result = {'design-generation': int(generation), 'canvas': 1024,
          'outlines': {name: outline(inset) for name, inset in insets.items()}}
(root / 'Artwork/Icon-mask-outline.json').write_text(json.dumps(result, separators=(',', ':')) + '\n')
print('Wrote Artwork/Icon-mask-outline.json')
