#!/usr/bin/env python3
"""Check current settings routes and displayed labels while preserving help encodings."""
from pathlib import Path
import re,html,json,subprocess
r=Path(__file__).resolve().parents[1]
def read_help(lang,name):
 p=r/f'Resources/Interfaces/{lang}.lproj/TeXShopHelp/pgs/{name}.htm';raw=p.read_bytes();m=re.search(br'charset=([^"\s>]+)',raw,re.I);enc=m[1].decode() if m else 'utf-8';enc={'x-sjis':'cp932','shift_jis':'cp932'}.get(enc.lower(),enc)
 if lang=='ja':assert enc=='cp932'
 return html.unescape(raw.decode(enc))
for lang in ['en','ja','ko','de','es']:
 folder=r/'Resources/Interfaces'/('Base.lproj' if lang=='en' else lang+'.lproj');category=json.loads(subprocess.check_output(['plutil','-convert','json','-o','-',str(folder/'SettingsCategories.strings')]))
 labels=json.loads(subprocess.check_output(['plutil','-convert','json','-o','-',str(r/'Resources/Interfaces'/(lang+'.lproj')/'Localizable.strings')]))
 for page in ['basic_preferences','basic_spelling']:
  text=read_help(lang,page)
  for key in ['general','documents','editor','spelling','appearance','preview','typesetting','console','keyboard','updates']:assert category[key] in text,(lang,page,key)
  for key in ['Use LaTeX-aware spell checking (recommended)','Use legacy spell checking']:assert labels[key] in text,(lang,page,key)
for lang in ['en','ko','ja']:
 a=read_help(lang,'basic_autocompletion');c=read_help(lang,'basic_commandcompletion')
 labels=json.loads(subprocess.check_output(['plutil','-convert','json','-o','-',str(r/'Resources/Interfaces'/(lang+'.lproj')/'Localizable.strings')]))
 assert labels['Edit Key Bindings…'] in a and labels['Edit Command Completion…'] in c,lang
 for text in [a,c]:
  for obsolete in ['"Edit Key Bindings File..." item','Select "Open Completion File"','「キーバインドファイルの編集」メニュー','「補完用語ファイルを開く...」']:assert obsolete not in text,(lang,obsolete)
for page in ['basic_autocompletion','configure_autocompletion']:assert 'solapa Documento' not in read_help('es',page)
for file in ['Documentation/Releases/5.60.md','website/release-notes.html','Manual Source/Manual.tex']:
 s=(r/file).read_text();assert 'NSUserKeyEquivalents' in s,file
 for obsolete in ['Settings → Spelling','with Edit Rules beneath','indented Edit Rules button','In Settings, Spelling,','Source category, there is a box','Input settings and shortcut results share one vertical scroll area']:assert obsolete not in s,(file,obsolete)
for file in ['Documentation/Releases/5.60-ja.md','website/release-notes-ja.html']:
 s=(r/file).read_text();assert 'NSUserKeyEquivalents' in s and 'LaTeXの構造を考慮する（推奨）' in s and '従来方式を使う' in s
 assert '入力設定とショートカット一覧は同じ縦スクロール領域' not in s
print('PASS: current UI names, editing routes, title-based shortcut migration and original help encodings')
