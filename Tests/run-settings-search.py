#!/usr/bin/env python3
"""Search coverage through the complete production preference controller."""
from pathlib import Path
import subprocess,sys,tempfile
r=Path(__file__).resolve().parents[1]
arguments=sys.argv[1:];mutations='--mutations' in arguments
arguments=[a for a in arguments if a!='--mutations']
command=[sys.executable,str(r/'Tests/run-settings-classification.py'),'--search-coverage',*arguments]
subprocess.run(command,check=True)
if mutations:
 expected_failures={'boolean-label-weight':'Visible switch row names retain label weight','radio-choice-weight':'Radio matrix options have choice weight'}
 expected_failures.update({'legacy-label':'Result name is the visible row name','dock-obsolete-label':'Dock result uses the visible group name'})
 source=(r/'Sources/TSSettingsSearchCatalog.inc').read_text()
 cases=[('boolean-label-weight','@"catalog.general.0.0.title", TSSettingsSearchWeightLabel','@"catalog.general.0.0.title", TSSettingsSearchWeightChoice'),('radio-choice-weight','@"Xrb-Fe-9cg.title", TSSettingsSearchWeightChoice','@"Xrb-Fe-9cg.title", TSSettingsSearchWeightLabel')]
 cases.extend([('legacy-label','@"ahm-aK-Qi9.title", TSSettingsSearchWeightDescription','@"ahm-aK-Qi9.title", TSSettingsSearchWeightLabel'),('dock-obsolete-label','@"group.appearance.10.title", TSSettingsSearchWeightLabel','@"Dock Icon While Running", TSSettingsSearchWeightLabel')])
 with tempfile.TemporaryDirectory(prefix='texshop-search-roles-') as temp:
  for name,old,new in cases:
   assert source.count(old)==1
   text=source.replace(old,new)
   # Both radio options must retain their role, not merely one option.
   if name=='radio-choice-weight':text=text.replace('@"odm-Dy-TNW.title", TSSettingsSearchWeightChoice','@"odm-Dy-TNW.title", TSSettingsSearchWeightLabel')
   path=Path(temp)/'catalog.inc';path.write_text(text)
   # The old otf label is identical in Japanese; the old Dock label is
   # identical in English. Exercise each non-equivalent localized case.
   mutated_command=command.copy()
   if name in ('legacy-label','dock-obsolete-label'):
    if '--language' in mutated_command:
     pos=mutated_command.index('--language');del mutated_command[pos:pos+2]
    mutated_command+=['--language','Base' if name=='legacy-label' else 'ja']
   result=subprocess.run([*mutated_command,'--search-catalog',str(path)],capture_output=True,text=True)
   assert result.returncode and 'FAIL: '+expected_failures[name] in result.stderr,(name,result.stdout,result.stderr)
   print('DETECTED',name,[line for line in result.stderr.splitlines() if 'FAIL:' in line],flush=True)
 subprocess.run(command,check=True)
 print('NORMAL CONTROL search roles',flush=True)

if mutations:
 engine=(r/'Sources/TSSettingsSearch.m').read_text()
 cases=[('category-cascade','if (score && ownMatch)', 'if (score)', 'Category-only matches produce one named category doorway'),('category-doorway','if (categoryScore) [results addObject:', 'if (NO && categoryScore) [results addObject:', 'Category-only matches produce one named category doorway'),('theme-row-duplicates','(visualRows[entry.targetIdentifier] ?: entry.targetIdentifier)','entry.targetIdentifier','A visual theme row has one result retaining all color targets')]
 with tempfile.TemporaryDirectory(prefix='texshop-search-categories-') as td:
  for name,old,new,diagnostic in cases:
   assert engine.count(old)==1
   p=Path(td)/'search.m';p.write_text(engine.replace(old,new))
   result=subprocess.run([*command,'--search-source',str(p)],capture_output=True,text=True)
   assert result.returncode and 'FAIL: '+diagnostic in result.stderr,(name,result.stdout,result.stderr)
   print('DETECTED',name,diagnostic,flush=True)
 subprocess.run(command,check=True)
 print('NORMAL CONTROL category search',flush=True)
