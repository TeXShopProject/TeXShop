#!/usr/bin/env python3
"""Verify search ordering, explicit result names and text normalization."""
from pathlib import Path
import subprocess,tempfile,sys,shutil
r=Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix='texshop-search-core-') as td:
 t=Path(td);p=t/'probe'
 def run(stage=None):
  unit=(stage or r/'Sources')/'TSSettingsSearch.m'
  subprocess.run(['xcrun','clang','-fobjc-arc','-Werror','-Wnullability-completeness','-Wnullable-to-nonnull-conversion','-mmacosx-version-min=14.6','-I',str(stage or r/'Sources'),'-I',str(r/'Sources'),'-framework','Cocoa',str(r/'Tests/SettingsSearchCore.m'),str(unit),str(r/'Sources/TSSettingsCategory.m'),'-o',str(p)],check=True)
  return subprocess.run([str(p)],capture_output=True,text=True,timeout=30)
 result=run();print(result.stdout);assert result.returncode==0,result.stderr
 if '--mutations' in sys.argv:
  cases=[('matched-label','TSSettingsSearch.m','if (preferred != nil) {','if (NO) {'),('note-as-title','TSSettingsSearch.m','return @"";','return self.entries.firstObject.text ?: @"";'),('canonical-substring','TSSettingsSearchText.h','options:NSLiteralSearch','options:0'),('compatibility-token-boundary','TSSettingsSearchText.h','[query componentsSeparatedByCharactersInSet:','[query.precomposedStringWithCompatibilityMapping componentsSeparatedByCharactersInSet:')]
  for name,file,old,new in cases:
   stage=t/name;stage.mkdir()
   for f in ['TSSettingsSearch.m','TSSettingsSearch.h','TSSettingsSearchText.h']:shutil.copy2(r/'Sources'/f,stage/f)
   path=stage/file;source=path.read_text();assert old in source;path.write_text(source.replace(old,new,1))
   result=run(stage);expected={'matched-label':'title isEqual:text','note-as-title':'title].length==0','canonical-substring':'such as','compatibility-token-boundary':'count==1'}[name]
   assert result.returncode and expected in result.stderr,(name,result.stdout,result.stderr)
   print('DETECTED',name,result.stderr.strip())
  result=run();assert result.returncode==0,result.stderr;print('NORMAL CONTROL search core')
