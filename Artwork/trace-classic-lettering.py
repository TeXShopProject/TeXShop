#!/usr/bin/env python3
"""Recover the classic round icon's lettering as reusable vector outlines.

Requires Pillow, NumPy, SciPy, fontTools, and the potrace executable.
The 1024-pixel source is preserved in Resources/DockIcons/round.png.
"""
from pathlib import Path
import json
import subprocess
import tempfile
import xml.etree.ElementTree as ET

import numpy as np
from PIL import Image
from scipy.ndimage import binary_closing, label
from fontTools.svgLib.path import parse_path
from fontTools.pens.recordingPen import RecordingPen
from fontTools.pens.transformPen import TransformPen

root = Path(__file__).resolve().parents[1]
image = np.array(Image.open(root / 'Resources/DockIcons/round.png').convert('RGBA'))
rgb = image[:, :, :3].astype(int)
y, x = np.indices(image.shape[:2])
mask = ((rgb.min(2) > 185) & ((rgb.max(2) - rgb.min(2)) < 14)
        & (x > 140) & (x < 880) & (y > 300) & (y < 730)
        & (image[:, :, 3] > 200))
components, count = label(mask)
sizes = np.bincount(components.ravel())
# Remove the rim fragments; close tiny gaps caused by the original bevel.
mask = np.isin(components, [i for i in range(1, count + 1) if sizes[i] > 1000])
mask = binary_closing(mask, structure=np.ones((3, 3)))
with tempfile.TemporaryDirectory() as directory:
    pbm, svg = Path(directory) / 'lettering.pbm', Path(directory) / 'lettering.svg'
    Image.fromarray(np.where(mask, 0, 255).astype('uint8')).convert('1').save(pbm)
    subprocess.run(['potrace', str(pbm), '-s', '-o', str(svg),
                    '--alphamax', '1', '--opttolerance', '0.2'], check=True)
    pen = RecordingPen()
    transformed = TransformPen(pen, (.1, 0, 0, .1, 0, 0))
    for path in ET.parse(svg).getroot().iter('{http://www.w3.org/2000/svg}path'):
        parse_path(path.get('d'), transformed)
    (root / 'Artwork/Classic-TeX-outline.json').write_text(json.dumps(pen.value, indent=2) + '\n')
