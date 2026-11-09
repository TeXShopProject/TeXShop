#!/usr/bin/env python3
from pathlib import Path
import subprocess,tempfile,sys
from shortcut_sources import NAMES, companion_sources
r=Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix='texshop-shortcut-launch-') as directory:
 d=Path(directory);source=r/'Sources/TSKeyboardShortcuts.m'
 command=['xcrun','clang','-fobjc-arc','-Wno-deprecated-declarations','-mmacosx-version-min=14.6','-I',str(r/'Sources'),'-I',str(r/'Tests'),'-framework','Cocoa','-framework','Carbon',str(r/'Tests/ShortcutLaunch.m'),*[str(r/'Sources'/n) for n in NAMES],*companion_sources(r),'-o',str(d/'probe')]
 def run(path):
  subprocess.run([str(path) if x==str(source) else x for x in command],check=True)
  return subprocess.run([str(d/'probe')],capture_output=True,text=True,timeout=10)
 result=run(source);assert result.returncode==0,result.stderr;print(result.stdout,flush=True)
 if '--mutations' in sys.argv:
  text=source.read_text()
  for name,old,new in [('skip-install','        [self startObservingMenu];',';'),('synchronous-start','dispatch_async(dispatch_get_main_queue(), ^{\n        configuration(self);\n        [self startObservingMenu];\n    });','configuration(self);[self startObservingMenu];')]:
   assert text.count(old)==1;path=d/'TSKeyboardShortcuts.m';path.write_text(text.replace(old,new));result=run(path);expected={'skip-install':'Launch installs saved shortcut on the final Find menu without opening settings','synchronous-start':'Installation waits until all launch observers finish'}[name];assert result.returncode and 'FAIL: '+expected in result.stderr,(name,result.stderr);print('DETECTED',name,result.stderr.strip(),flush=True)
  result=run(source);assert result.returncode==0,result.stderr;print('NORMAL CONTROL',result.stdout,flush=True)
