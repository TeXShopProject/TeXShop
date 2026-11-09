#!/usr/bin/env python3
"""Check fixed menu and macro assignments against inverse layout events, never AppKit dispatch."""
from pathlib import Path
import argparse,subprocess,tempfile
from shortcut_sources import production_source, companion_sources
from source_tree import include_args
root=Path(__file__).resolve().parents[1]
parser=argparse.ArgumentParser();parser.add_argument('--app',type=Path);args=parser.parse_args()
with tempfile.TemporaryDirectory(prefix='texshop-assignment-layouts-') as folder:
 temp=Path(folder);(temp/'TSKeyboardShortcuts.m').write_text(production_source(root))
 subprocess.run(['xcrun','clang','-fobjc-arc','-O2','-Wno-deprecated-declarations','-I',folder,*include_args(root),'-framework','Cocoa','-framework','Carbon',str(root/'Tests/ShortcutAssignmentLayouts.m'),*companion_sources(root),'-o',str(temp/'probe')],check=True)
 base=args.app/'Contents/Resources' if args.app else root/'Resources/Interfaces'
 menus=[]
 for lang in ['Base','ja','de']:
  path=base/(lang+'.lproj')/'MainMenu.nib'
  menus.append(sorted(path.glob('keyedobjects*.nib'))[0] if path.is_dir() else path)
 macros=sorted((root/'Resources/TeXShop/Macros').glob('*.plist'))
 subprocess.run([str(temp/'probe'),*map(str,menus),*map(str,macros)],check=True)
