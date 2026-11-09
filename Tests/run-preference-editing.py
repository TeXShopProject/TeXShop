#!/usr/bin/env python3
"""Run the actual production editing class, including the cross-field restore regression."""
from pathlib import Path
import argparse,subprocess,tempfile
from source_tree import include_args
r=Path(__file__).resolve().parents[1]
p=argparse.ArgumentParser();p.add_argument('--mutations',action='store_true');a=p.parse_args()
expected_failures={'shared-restore': "step 4: restore GS's saved empty value, not the previous field's 20", 'focus-is-edit': 'step 2/3: untouched empty GS path does not block navigation', 'restore-keeps-dirty': 'step 5: restored invalid legacy value does not trap navigation', 'drop-write': 'step 1: tab width 20 saved'}
source=(r/'Sources/Settings/TSPreferenceInput.m').read_text()
mutations={
 'shared-restore':('NSString *original = [rule displayStringFromDefaults:defaults];','NSString *original = TSLastCommittedText;'),
 'focus-is-edit':('if (self.editedField != field) return YES;','/* incorrectly treats focus/display as an edit */'),
 'restore-keeps-dirty':('self.editedField = nil;\n}\n@end','/* incorrectly keeps the invalid field dirty */\n}\n@end'),
 'drop-write':('BOOL changed = [value storeInDefaults:defaults forKey:rule.key];','BOOL changed = NO;'),
}
for name in ['baseline']+(list(mutations) if a.mutations else []):
 with tempfile.TemporaryDirectory(prefix='texshop-preference-editing-') as td:
  t=Path(td);s=source
  if name!='baseline':
   old,new=mutations[name];assert s.count(old)==1,(name,s.count(old));s=s.replace(old,new)
   if name=='shared-restore':
    s=s.replace('@implementation TSPreferenceEditing','static NSString *TSLastCommittedText;\n@implementation TSPreferenceEditing')
    s=s.replace('field.stringValue = [rule displayStringForValue:value];','field.stringValue = [rule displayStringForValue:value];\n    TSLastCommittedText = field.stringValue;')
  (t/'TSPreferenceInput.m').write_text(s)
  subprocess.run(['xcrun','clang','-fobjc-arc','-Wall','-Wextra','-Werror','-Wno-unused-parameter','-Wnullability-completeness','-Wnullable-to-nonnull-conversion',*include_args(r),'-I',str(r/'Tests'),'-framework','Cocoa',str(r/'Tests/PreferenceEditing.m'),str(t/'TSPreferenceInput.m'),'-o',str(t/'probe')],check=True)
  run=subprocess.run([str(t/'probe')],capture_output=True,text=True)
  assert (run.returncode==0 if name=='baseline' else run.returncode==1 and 'FAIL: '+expected_failures[name] in run.stderr),(name,run.stdout,run.stderr)
  print(run.stdout.strip() if name=='baseline' else 'DETECTED: '+name+' '+run.stderr.strip(),flush=True)
