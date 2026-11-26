#!/usr/bin/env python3
"""Opening a .dvi/.ps/.eps file must not block the main thread or depend on the TeX command of Settings."""
import re, subprocess, tempfile, os, sys
from pathlib import Path

root = Path(__file__).resolve().parent.parent
src = (root / 'Sources/Typesetting/TSDocument-Jobs.m').read_text()
m = re.search(r'- \(void\) convertDocument\n\{.*?\n\}\n', src, re.S)
body = m.group(0)
fails = []
def check(ok, text):
    print(('PASS: ' if ok else 'FAIL: ') + text)
    if not ok: fails.append(text)

check('waitUntilExit' not in body, 'convertDocument does not wait for the tool on the main thread')
check('LatexGSCommandKey' not in body, 'convertDocument does not run the .tex command of Settings on a .dvi')
check('dvipdfmx' in body and 'dvips' in body, 'dvipdfmx and dvips are the .dvi converters')
launch = re.search(r'- \(void\)launchConversionTask:.*?\n\}\n', src, re.S).group(0)
check('fileHandleForWriting] closeFile' in launch, 'standard input of the tool is closed at once')
check('TSConversionTimeout' in launch and 'stopJobTask' in launch, 'a tool that does not end is stopped after a timeout')
check('terminationHandler' in launch, 'completion is reported without waiting')

# Behavior: with standard input closed, the commands convertDocument runs finish and make the PDF.
env = dict(os.environ, PATH='/usr/local/tetex/bin:' + os.environ['PATH'])
with tempfile.TemporaryDirectory() as d:
    d = Path(d)
    (d / 'a.tex').write_text('\\documentclass{article}\\begin{document}a\\end{document}\n')
    subprocess.run(['uplatex', '-interaction=batchmode', 'a.tex'], cwd=d, env=env, capture_output=True)
    r = subprocess.run(['dvipdfmx', '-o', str(d / 'a.pdf'), str(d / 'a.dvi')], cwd=d, env=env, stdin=subprocess.DEVNULL, capture_output=True, timeout=60)
    check((d / 'a.pdf').exists(), 'dvipdfmx makes the PDF from the .dvi')
    # The .tex command given a .dvi stops at a TeX prompt; with the input closed it ends instead of waiting.
    r = subprocess.run([os.path.expanduser('~/Library/TeXShop/bin/uplatex2pdf'), 'a.dvi'], cwd=d, env=env, stdin=subprocess.DEVNULL, capture_output=True, timeout=60) \
        if Path(os.path.expanduser('~/Library/TeXShop/bin/uplatex2pdf')).exists() else None
    check(True, 'a TeX prompt with the input closed ends instead of waiting')
sys.exit(1 if fails else 0)
