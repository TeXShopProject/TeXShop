#!/usr/bin/env python3
"""Mutate isolated help/UI resources and require the intended diagnostic."""
from pathlib import Path
import tempfile,subprocess,shutil,re,json
R=Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix='texshop-wording-audit-')as td:
 T=Path(td)
 for folder in ['Resources/Interfaces','Tests/Fixtures','Documentation/Releases','website','Manual Source','DocumentSources/CommentLinesRevised']:
  for p in (R/folder).rglob('*'):
   if p.is_file() and p.suffix in ['.strings','.htm','.html','.json','.md','.tex']:
    dest=T/p.relative_to(R);dest.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(p,dest)
 check=(R/'Tests/check-settings-guidance.py').read_text().replace('ROOT = Path(__file__).resolve().parents[1]','ROOT = Path('+repr(str(T))+')')
 def guidance():return subprocess.run(['python3','-c',check],capture_output=True,text=True)
 def wording():return subprocess.run(['python3',str(R/'Tests/run-settings-ui-wording.py'),'--interfaces',str(T/'Resources/Interfaces')],capture_output=True,text=True)
 for run in [guidance,wording]:
  result=run();assert result.returncode==0,result.stderr
 cases=[]
 for lang in ['en','ja','de','es','ko']:
  for name in ['basic_preferences','basic_spelling','configure_menushortcuts','configure_prefchanges','configure_hidden']:
   cases.append((f'outside-{lang}-{name}',f'Resources/Interfaces/{lang}.lproj/TeXShopHelp/pgs/{name}.htm',b'</body>',b'<p>fixture paragraph</p></body>',guidance,'body text outside content_border'))
 cases += [('ja-button','Resources/Interfaces/ja.lproj/TeXShopHelp/pgs/configure_menushortcuts.htm',b'</div>','<p>初期状態に戻す</p></div>'.encode('cp932'),guidance,'AssertionError'),('manual-find','Manual Source/Manual.tex',b'Switching between the Apple Find Panel and Apple Find Bar',b'After making a selection, TeXShop must be restarted. Switching between the Apple Find Panel and Apple Find Bar',guidance,'Find Panel restart guidance')]
 for suffix in ['.md','-ja.md']:
  file='Documentation/Releases/5.60'+suffix
  # The checker examines these current release sources directly.
  cases.append(('release-'+suffix,file,b'\n',b'\napproved compact layout\n',guidance,'approved compact layout'))
 for name,file,old,new,run,message in cases:
  p=T/file;original=p.read_bytes();assert old in original,name;p.write_bytes(original.replace(old,new,1))
  result=run();p.write_bytes(original)
  assert result.returncode and message in result.stderr,(name,result.stdout,result.stderr)
  print('DETECTED',name,message,flush=True)
 for lang in ['Base','ja']:
  p=T/f'Resources/Interfaces/{lang}.lproj/SettingsDock.strings';original=p.read_bytes()
  p.write_bytes(original+b'\n"obsolete guidance" = "Returns to the standard icon after quitting.";\n')
  result=wording();p.write_bytes(original);assert result.returncode and 'Dock key set excludes obsolete instructions' in result.stderr,result.stderr
  print('DETECTED Dock key set',lang,flush=True)
 for lang in ['Base','ja']:
  p=T/f'Resources/Interfaces/{lang}.lproj/SettingsCategories.strings';original=p.read_bytes()
  values=json.loads(subprocess.check_output(['plutil','-convert','json','-o','-',str(p)]));values['catalog.documents.1.3.note']='Wrong conversion explanation'
  p.write_text('\n'.join(json.dumps(k,ensure_ascii=False)+' = '+json.dumps(v,ensure_ascii=False)+';' for k,v in values.items())+'\n')
  result=wording();p.write_bytes(original);assert result.returncode and 'approved conversion explanation' in result.stderr,result.stderr
  print('DETECTED exact conversion note',lang,flush=True)
 for run in [guidance,wording]:
  result=run();assert result.returncode==0,result.stderr
 print('NORMAL CONTROL help and UI wording')
