#!/usr/bin/env python3
"""Verify search ordering and text normalization using deterministic resource text."""
from pathlib import Path
import subprocess,tempfile
r=Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix='texshop-search-core-') as td:
 p=Path(td)/'probe'
 subprocess.run(['xcrun','clang','-fobjc-arc','-Werror','-Wnullability-completeness','-Wnullable-to-nonnull-conversion','-mmacosx-version-min=14.6','-I',str(r/'Sources'),'-framework','Cocoa',str(r/'Tests/SettingsSearchCore.m'),str(r/'Sources/TSSettingsSearch.m'),str(r/'Sources/TSSettingsCategory.m'),'-o',str(p)],check=True)
 subprocess.run([str(p)],check=True,timeout=30)
