#!/usr/bin/env python3
"""Search actual localized command models from compiled menus without sending actions."""
from pathlib import Path
from shortcut_sources import production_source, companion_sources
import argparse,subprocess,tempfile
from source_tree import include_args
r=Path(__file__).resolve().parents[1]
p=argparse.ArgumentParser();p.add_argument('--app',type=Path);args=p.parse_args()
with tempfile.TemporaryDirectory(prefix='texshop-search-commands-') as td:
 t=Path(td);(t/'TSKeyboardShortcuts.m').write_text(production_source(r))
 subprocess.run(['xcrun','clang','-fobjc-arc','-O2','-Wno-nullability-completeness','-Wno-deprecated-declarations','-I',str(t),'-I',str(r/'Tests'),*include_args(r),'-framework','Cocoa','-framework','Carbon',str(r/'Tests/SettingsSearchCommands.m'),str(r/'Sources/Settings/TSSettingsSearch.m'),str(r/'Sources/Settings/TSSettingsCategory.m'),*companion_sources(r),'-o',str(t/'probe')],check=True)
 base=args.app/'Contents/Resources' if args.app else r/'Resources/Interfaces'
 paths=sorted(base.glob('*.lproj/MainMenu.nib'));assert len(paths)==12,len(paths)
 for folder in paths:
  path=sorted(folder.glob('keyedobjects*.nib'))[0] if folder.is_dir() else folder
  subprocess.run([str(t/'probe'),str(path)],check=True,timeout=180)
