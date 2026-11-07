#!/usr/bin/env python3
"""Verify the settings shell without ordering windows or writing user defaults."""
from pathlib import Path
import argparse,subprocess,tempfile
parser=argparse.ArgumentParser()
parser.add_argument("output",nargs="?")
parser.add_argument("--app",type=Path)
args=parser.parse_args()
r=Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix='texshop-sidebar-') as td:
 p=Path(td);resources=args.app/'Contents/Resources' if args.app else None
 nib=resources/'SettingsWindow.nib' if resources else p/'SettingsWindow.nib'
 if resources is None:subprocess.run(['xcrun','ibtool','--compile',str(nib),str(r/'Resources/SettingsWindow.xib')],check=True)
 subprocess.run(['xcrun','clang','-fobjc-arc','-Wall','-Wextra','-Wno-unused-parameter','-I',str(r/'Tests'),'-I',str(r/'Sources'),'-framework','Cocoa',str(r/'Tests/SettingsSidebar.m'),str(r/'Sources/TSSettingsWindowController.m'),str(r/'Sources/TSSettingsNavigationHistory.m'),'-o',str(p/'test')],check=True)
 out=Path(args.output) if args.output else p/'images';out.mkdir(parents=True,exist_ok=True)
 paths=sorted((resources or r/'Resources/Interfaces').glob('*.lproj/Preferences.nib/keyedobjects.nib'))
 assert len(paths)==12
 subprocess.run([str(p/'test'),str(nib),str(out),*map(str,paths)],check=True)
