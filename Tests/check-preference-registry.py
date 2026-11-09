#!/usr/bin/env python3
"""Fail when a new defaults key lacks an explicit profile policy."""
from pathlib import Path
import re,plistlib,json,sys
root=Path(__file__).resolve().parents[1]
model=(root/'Sources/TSPreferenceProfile.m').read_text()
known=set(re.findall(r'@"([^"\n]+)"',model.split('BOOL TSPreferenceProfilePreservesKey')[0]))
constants={}
uses={}
def add(key,source):uses.setdefault(key,[]).append(source)
for p in sorted((root/'Sources').glob('*.[mh]')):
 s=p.read_text(errors='replace')
 s=re.sub(r'/\*.*?\*/','',s,flags=re.S);s=re.sub(r'//[^\n]*','',s)
 for sym,key in re.findall(r'(?:NSString\s*\*\s*(?:const\s*)?|TSPreferenceKey\s+(?:const\s*)?)(\w+)\s*=\s*@"([^"\n]+)"',s):
  constants[sym]=key
  if sym.endswith('Key'):add(key,str(p.relative_to(root))+':'+sym)
# Resolve shared constants used by the profile registry after discovery.
known.update(constants[sym] for sym in re.findall(r'\b[A-Za-z_]\w*\b',model.split('BOOL TSPreferenceProfilePreservesKey')[0]) if sym in constants)
for p in sorted((root/'Sources').glob('*.[mh]')):
 s=p.read_text(errors='replace');s=re.sub(r'/\*.*?\*/','',s,flags=re.S);s=re.sub(r'//[^\n]*','',s)
 # Message receivers with a defaults contract; include multiline expressions.
 for m in re.finditer(r'\[(?:SUD|defaults|self\.defaults|NSUserDefaults\.standardUserDefaults|userDefaults)\s+[^;]*?(?:ForKey|forKey):\s*(@"[^"\n]+"|\w+)',s):
  token=m[1];key=token[2:-1] if token.startswith('@"') else constants.get(token)
  if key:add(key,str(p.relative_to(root))+':'+str(s.count('\n',0,m.start())+1))
for p in (root/'Resources/Shellscripts').glob('*Defaults*.plist'):
 for key in plistlib.loads(p.read_bytes()):add(key,str(p.relative_to(root)))
# Values assembled by the invisible-character compatibility adapter.
for prefix in ['Space','FullwidthSpace','NewLine','Tab']:add(prefix+'CharacterKindExtended','Sources/TSInvisibleCharacters.h:dynamic suffix')
# Runtime-only strings and non-defaults file dictionary keys declared with Key suffix.
nondefaults={'/tmp/TeXShop_Output'}
missing=set(uses)-known-nondefaults
if missing:
 print(json.dumps({k:uses[k] for k in sorted(missing)},ensure_ascii=False,indent=2));raise SystemExit(1)
if len(sys.argv)>1:Path(sys.argv[1]).write_text(json.dumps(uses,ensure_ascii=False,indent=2))
print(f'PASS: {len(uses)} discovered defaults keys classified; dynamic suffixes included; unknown external keys preserved')
