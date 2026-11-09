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
   result=subprocess.run([*command,'--search-catalog',str(path)],capture_output=True,text=True)
   assert result.returncode and 'FAIL: '+expected_failures[name] in result.stderr,(name,result.stdout,result.stderr)
   print('DETECTED',name,[line for line in result.stderr.splitlines() if 'FAIL:' in line],flush=True)
 subprocess.run(command,check=True)
 print('NORMAL CONTROL search roles',flush=True)
