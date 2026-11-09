#!/usr/bin/env python3
"""Mutate isolated help/UI resources and require the intended diagnostic."""
from pathlib import Path
import tempfile,subprocess,shutil,re,json
R=Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix='texshop-wording-audit-')as td:
 T=Path(td)
 for folder in ['Resources/Interfaces','Tests/Fixtures','Documentation/Releases','website','Manual Source','DocumentSources/CommentLinesRevised','ChangesDocument']:
  for p in (R/folder).rglob('*'):
   if p.is_file() and p.suffix in ['.strings','.htm','.html','.json','.md','.tex','.pdf']:
    dest=T/p.relative_to(R);dest.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(p,dest)
 check=(R/'Tests/check-settings-guidance.py').read_text().replace('ROOT = Path(__file__).resolve().parents[1]','ROOT = Path('+repr(str(T))+')')
 def guidance():return subprocess.run(['python3','-c',check],capture_output=True,text=True)
 def wording():return subprocess.run(['python3',str(R/'Tests/run-settings-ui-wording.py'),'--interfaces',str(T/'Resources/Interfaces')],capture_output=True,text=True)
 for run in [guidance,wording]:
  result=run();assert result.returncode==0,result.stderr
 cases=[]
 for filename in ['Documentation/Releases/5.60.md','website/release-notes.html','Resources/Interfaces/en.lproj/TeXShopHelp/pgs/whatisnew.htm','ChangesDocument/Changes.tex','Documentation/Releases/5.60-ja.md','website/release-notes-ja.html']:
  phrase='同じ行の色設定は1件の結果にまとめます。' if '-ja.' in filename else 'Color controls on the same row share one result.'
  cases.append(('release-search-'+filename,filename,phrase.encode(),b'REMOVED',guidance,'Release category and color-row guidance'))
 cases.append(('ko-category','Resources/Interfaces/ko.lproj/TeXShopHelp/pgs/basic_preferences.htm',''.join('&#'+str(ord(c))+';' for c in '범주').encode(),''.join('&#'+str(ord(c))+';' for c in '카테고리').encode(),guidance,'Korean category terminology'))

 for lang in ['en','ja','de','es','ko']:
  for name in ['basic_preferences','basic_spelling','configure_menushortcuts','configure_prefchanges','configure_hidden']:
   cases.append((f'outside-{lang}-{name}',f'Resources/Interfaces/{lang}.lproj/TeXShopHelp/pgs/{name}.htm',b'</body>',b'<p>fixture paragraph</p></body>',guidance,'body text outside content_border'))
 cases += [('ja-button','Resources/Interfaces/ja.lproj/TeXShopHelp/pgs/configure_menushortcuts.htm',b'</div>','<p>初期状態に戻す</p></div>'.encode('cp932'),guidance,'Japanese obsolete shortcut button'),('manual-find','Manual Source/Manual.tex',b'Switching between the Apple Find Panel and Apple Find Bar',b'After making a selection, TeXShop must be restarted. Switching between the Apple Find Panel and Apple Find Bar',guidance,'Find Panel restart guidance')]
 for suffix in ['.md','-ja.md']:
  file='Documentation/Releases/5.60'+suffix
  # The checker examines these current release sources directly.
  cases.append(('release-'+suffix,file,b'\n',b'\napproved compact layout\n',guidance,'approved compact layout'))
 for tag,body in [('ul',b'<ul><li>fixture item</li></ul>'),('div',b'<div>fixture division</div>'),('raw',b'fixture bare text'),('dl',b'<dl><dt>fixture term</dt><dd>fixture definition</dd></dl>')]:
  cases.append(('outside-'+tag,'Resources/Interfaces/en.lproj/TeXShopHelp/pgs/basic_preferences.htm',b'</body>',body+b'</body>',guidance,'body text outside content_border'))
 for term in ['Theme color groups are shown together in Appearance.','Settings » Themes']:
  cases.append(('obsolete-'+term,'Resources/Interfaces/en.lproj/TeXShopHelp/pgs/basic_preferences.htm',b'<div id="content_border">',('<div id="content_border"><p>'+term+'</p>').encode('ascii',errors='xmlcharrefreplace'),guidance,term))
 for chrome in ['menu_border','header_title']:
  cases.append(('chrome-paragraph-'+chrome,'Resources/Interfaces/en.lproj/TeXShopHelp/pgs/configure_hidden.htm',('<div id="'+chrome+'">').encode(),('<div id="'+chrome+'"><p>fixture body</p>').encode(),guidance,'body text outside content_border'))
 for text in ['解除','すべて元に戻す…']:
  cases.append(('ja-label-'+text,'Resources/Interfaces/ja.lproj/TeXShopHelp/pgs/configure_menushortcuts.htm',text.encode('cp932'),b'REMOVED',guidance,'Japanese shortcut button missing'))
 for name,file,old,new,run,message in cases:
  p=T/file;original=p.read_bytes();assert old in original,name;p.write_bytes(original.replace(old,new,1))
  result=run();p.write_bytes(original)
  assert result.returncode and message in result.stderr,(name,result.stdout,result.stderr)
  print('DETECTED',name,message,flush=True)
 for language in ['en','ko']:
  p=T/f'Resources/Interfaces/{language}.lproj/TeXShopHelp/pgs/basic_preferences1.htm';p.write_text('<html><body>obsolete</body></html>')
  result=guidance();p.unlink();assert result.returncode and 'Obsolete duplicate preferences help page' in result.stderr,result.stderr
  print('DETECTED obsolete duplicate help',language,flush=True)
 p=T/'Manual Source/Manual.tex';original=p.read_bytes();p.write_bytes(original+b'\nTransparency settings bring up a full Color Well\n');result=guidance();p.write_bytes(original)
 assert result.returncode and 'Opacity uses a slider in the manual' in result.stderr,result.stderr
 print('DETECTED old opacity manual',flush=True)
 search_wording=json.loads((R/'Tests/Fixtures/SettingsSearchWording.json').read_text())
 for lang in search_wording['counts']:
  p=T/f'Resources/Interfaces/{lang}.lproj/Localizable.strings';original=p.read_bytes();values=json.loads(subprocess.check_output(['plutil','-convert','json','-o','-',str(p)]));values['Settings results: %lu']='Categories: %lu'
  p.write_text('\n'.join(json.dumps(k,ensure_ascii=False)+' = '+json.dumps(v,ensure_ascii=False)+';' for k,v in values.items())+'\n')
  result=wording();p.write_bytes(original);assert result.returncode and 'Search counts refer to settings' in result.stderr,result.stderr
  print('DETECTED search count',lang,flush=True)
 for lang in search_wording['prefixes']:
  actual='Base' if lang=='en' else lang;p=T/f'Resources/Interfaces/{actual}.lproj/SettingsCategories.strings';original=p.read_bytes();values=json.loads(subprocess.check_output(['plutil','-convert','json','-o','-',str(p)]));values['catalog.typesetting.0.3.note']='(default: pdflatexmk)'
  p.write_text('\n'.join(json.dumps(k,ensure_ascii=False)+' = '+json.dumps(v,ensure_ascii=False)+';' for k,v in values.items())+'\n')
  result=wording();p.write_bytes(original);assert result.returncode and 'Engine defaults use consistent localized wording' in result.stderr,result.stderr
  print('DETECTED engine default',lang,flush=True)
 # Revert all distributed PDF copies together: identity alone cannot catch stale content.
 hidden=['DocumentSources/CommentLinesRevised/CommentLines.pdf','Resources/Interfaces/Base.lproj/CommentLines.pdf','Resources/Interfaces/en.lproj/CommentLines.pdf']
 originals={name:(T/name).read_bytes() for name in hidden}
 stale=subprocess.check_output(['git','show','fda72e9:DocumentSources/CommentLinesRevised/CommentLines.pdf'],cwd=R)
 for name in hidden:(T/name).write_bytes(stale)
 result=guidance()
 for name,data in originals.items():(T/name).write_bytes(data)
 assert result.returncode and "('Hidden PDF restart instructions', 'WatchServer')" in result.stderr,(result.stdout,result.stderr)
 print('DETECTED stale hidden PDF copies',flush=True)
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
