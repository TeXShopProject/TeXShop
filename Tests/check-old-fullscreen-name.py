#!/usr/bin/env python3
"""Check that Window > Fullscreen (Old Method) says it is the old method in every language.

TeXShop's own full screen (TSDocument -fullscreen:) is not the full screen of macOS (View > Enter Full Screen).
Its menu item names it as the old method in the MainMenu nib of every language, in the editable nib and in each
compiled variant, with Apple's term for full screen in that language.
--mutation old-name puts back the earlier Japanese name. The check must then fail.
"""
import argparse
import plistlib
import re
from pathlib import Path

NAMES = {
    'Base': 'Fullscreen (Old Method)',
    'de': 'Vollbild (alte Methode)',
    'es': 'Pantalla completa (método antiguo)',
    'fr': 'Plein écran (ancienne méthode)',
    'it': 'A tutto schermo (vecchio metodo)',
    'ja': 'フルスクリーン（旧方式）',
    'ko': '전체 화면 (옛날방식)',
    'nl': 'Schermvullend (oude methode)',
    'pt': 'Tela Cheia (método antigo)',
    'pt-PT': 'Ecrã completo (método antigo)',
    'ro': 'Pe tot ecranul (metoda veche)',
    'zh_CN': '全屏幕（旧方法）',
}
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--mutation', choices=['old-name'])
args = parser.parse_args()
root = Path(__file__).resolve().parents[1]
found = {}
try:
    for nib in sorted((root / 'Resources/Interfaces').glob('*.lproj/MainMenu.nib')):
        language = nib.parent.name.removesuffix('.lproj')
        text = (nib / 'designable.nib').read_text(encoding='utf-8')
        titles = re.findall(r'<menuItem title="([^"]*)" [^>]*identifier="TSShortcut\.fullscreen:\.0"', text)
        assert len(titles) == 1, f'{language}: the Fullscreen (Old Method) item is not found once'
        title = titles[0].replace('&amp;', '&')
        if args.mutation == 'old-name' and language == 'ja':
            title = 'フルスクリーン表示'
        assert title == NAMES.get(language), f'{language}: the item is named {title!r}, not {NAMES.get(language)!r}'
        for compiled in sorted(nib.glob('keyedobjects*.nib')):
            data = compiled.read_bytes()
            assert title.encode('utf-8') in data or title.encode('utf-16-le') in data or title.encode('utf-16-be') in data, \
                f'{compiled.relative_to(root)}: the compiled nib does not have the name; run Tests/compile-interface.py MainMenu'
        found[language] = title
    assert set(found) == set(NAMES), f'languages differ: {sorted(set(found) ^ set(NAMES))}'
except AssertionError as error:
    if args.mutation:
        print(f'PASS: detected mutation {args.mutation}: {error}')
        raise SystemExit(0)
    raise
if args.mutation:
    raise SystemExit(f'mutation {args.mutation} was not detected')
print(f'PASS: Fullscreen (Old Method) is named as the old method in all {len(found)} MainMenu nibs, editable and compiled')
