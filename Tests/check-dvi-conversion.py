#!/usr/bin/env python3
"""Opening a .dvi/.ps/.eps file must not block the main thread or depend on the TeX command of Settings."""
import os, re, subprocess, sys, tempfile
from pathlib import Path

root = Path(__file__).resolve().parent.parent
src = (root / 'Sources/Typesetting/TSDocument-Jobs.m').read_text()

def strip_comments(text):
    text = re.sub(r'/\*.*?\*/', '', text, flags=re.S)
    return re.sub(r'(?m)(^|[^:"])//.*$', r'\1', text)

def method(pattern):
    m = re.search(pattern + r'.*?\n\}\n', src, re.S)
    if not m:
        raise SystemExit('method not found: ' + pattern)
    return strip_comments(m.group(0))

convert = method(r'- \(void\) convertDocument\n\{')
launch = method(r'- \(void\)launchConversionTask:')
fails = []
def check(ok, text):
    print(('PASS: ' if ok else 'FAIL: ') + text)
    if not ok:
        fails.append(text)

# Source checks, on the code without comments.
check('waitUntilExit' not in convert and 'waitUntilExit' not in launch,
      'neither convertDocument nor launchConversionTask waits for the tool')
check('LatexGSCommandKey' not in convert, 'convertDocument does not run the .tex command of Settings on a .dvi')
check('dvipdfmx' in convert and 'dvips' in convert, 'dvipdfmx and dvips are the .dvi converters')
check(re.search(r'^\s*\[\[self\.inputPipe fileHandleForWriting\] closeFile\];', launch, re.M) is not None,
      'standard input of the tool is closed at once')
check(re.search(r'task\.terminationHandler\s*=\s*\^', launch) is not None, 'completion is reported by a termination handler')
check('TSConversionTimeout' in launch and 'SIGTERM' in launch and 'SIGKILL' in launch,
      'a tool that does not end is stopped after a timeout')
check('stopJobTask' not in launch, 'the timeout does not wait on the main thread')

# Behavior of the commands convertDocument runs.
env = dict(os.environ, PATH='/usr/local/tetex/bin:' + os.environ['PATH'])
def run(cmd, cwd, timeout=90):
    return subprocess.run(cmd, cwd=cwd, env=env, stdin=subprocess.DEVNULL, capture_output=True, text=True, timeout=timeout)

with tempfile.TemporaryDirectory() as d:
    d = Path(d)
    (d / 'a.tex').write_text('\\documentclass{article}\\begin{document}a\\end{document}\n')
    run(['uplatex', '-interaction=batchmode', 'a.tex'], d)
    run(['dvipdfmx', '-o', str(d / 'a.pdf'), str(d / 'a.dvi')], d)
    check((d / 'a.pdf').exists(), 'dvipdfmx makes the PDF from the .dvi')

    # The .tex command of Settings given a .dvi stops at a TeX prompt; with the input closed it ends.
    tex2pdf = Path.home() / 'Library/TeXShop/bin/uplatex2pdf'
    if tex2pdf.exists():
        try:
            run([str(tex2pdf), 'a.dvi'], d, timeout=60)
            check(True, 'a TeX prompt with the input closed ends instead of waiting')
        except subprocess.TimeoutExpired:
            check(False, 'a TeX prompt with the input closed ends instead of waiting')
    else:
        print('SKIP: uplatex2pdf is not installed')

    # The dvips script, taken from the source: it leaves a .ps of the user alone, on success and on failure.
    m = re.search(r'TSDvipsConversionScript =\s*((?:\s*@"(?:[^"\\]|\\.)*"\s*)+);', src)
    script = ''.join(re.findall(r'@"((?:[^"\\]|\\.)*)"', m.group(1))).replace('\\"', '"').replace('\\\\', '\\')
    wrapper = root / 'Resources/Shellscripts/ps2pdftransparencywrap'
    work = d / 'w'
    work.mkdir()
    (work / 'a.dvi').write_bytes((d / 'a.dvi').read_bytes())
    (work / 'a.ps').write_text('%%USER-ORIGINAL\n')
    tools = subprocess.run(['which', 'dvips', 'gs'], env=env, capture_output=True, text=True).stdout.split()
    if len(tools) == 2 and wrapper.exists():
        gsdir = str(Path(tools[1]).parent)
        r = run(['/bin/sh', '-c', script, 'sh', 'a', str(work / 'a.dvi'), str(wrapper), gsdir, tools[0]], work)
        check(r.returncode == 0 and (work / 'a.pdf').exists(), 'dvips and Ghostscript make the PDF')
        check((work / 'a.ps').exists() and (work / 'a.ps').read_text() == '%%USER-ORIGINAL\n', 'a .ps of the user with the same name stays after a success')
        (work / 'a.pdf').unlink()
        r = run(['/bin/sh', '-c', script, 'sh', 'a', str(work / 'missing.dvi'), str(wrapper), gsdir, tools[0]], work)
        check(r.returncode != 0, 'a failed dvips ends with an error')
        check((work / 'a.ps').exists() and (work / 'a.ps').read_text() == '%%USER-ORIGINAL\n', 'a .ps of the user with the same name stays after a failure')
        left = [p for p in Path(tempfile.gettempdir()).glob('TeXShop-convert.*')]
        check(not left, 'the folder of the intermediate PostScript is removed')
    else:
        print('SKIP: dvips or Ghostscript is not installed')
sys.exit(1 if fails else 0)
