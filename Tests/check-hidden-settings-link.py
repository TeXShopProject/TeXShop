#!/usr/bin/env python3
"""The General link to the hidden settings document names it as the Help menu does.

Settings > General > Advanced has a description that quotes the Help menu item of the
document (CommentLines.pdf) and a link that opens it. In every language the link reads as
reviewed, ends with the ellipsis character, and the description quotes the Help menu item,
so that the description, the link and the Help menu name the same document. With --app the
built bundle carries the same strings.
"""
from pathlib import Path
import argparse, json, re, subprocess

ROOT = Path(__file__).resolve().parents[1]
INTERFACES = ROOT / 'Resources/Interfaces'
DESCRIPTION, LINK = 'catalog.general.5.0.title', 'catalog.general.5.1.title'
EXPECTED = {
    'Base': 'Open the Comment Lines and Hidden Settings Manual…',
    'ja': 'マジックコメントと隠し設定のマニュアルを開く…',
    'de': 'Handbuch zu Kommentarzeilen und versteckten Einstellungen öffnen…',
    'es': 'Abrir el manual de líneas mágicas y ajustes ocultos…',
    'fr': 'Ouvrir le manuel des commentaires spéciaux et réglages cachés…',
    'it': 'Apri il manuale delle linee di commento e impostazioni nascoste…',
    'ko': '매직 코멘트와 숨겨진 설정 설명서 열기…',
    'nl': 'Handleiding voor commentaarregels en verborgen instellingen openen…',
    'pt': 'Abrir o manual de linhas especiais e ajustes ocultos…',
    'pt-PT': 'Abrir o manual de linhas de comentário e definições ocultas…',
    'ro': 'Deschide manualul pentru linii de comentarii și configurări ascunse…',
    'zh_CN': '打开魔术行与隐藏设置手册…',
}
# A Help menu item may say the document is in English; the description quotes the name only.
LANGUAGE_NOTE = re.compile(r'\s*[(（][^()（）]*[)）]$')


def strings(path):
    return json.loads(subprocess.check_output(['plutil', '-convert', 'json', '-o', '-', str(path)]))


def help_menu_name(lang):
    text = (INTERFACES / f'{lang}.lproj/MainMenu.nib/designable.nib').read_text(encoding='utf-8')
    action = text.index('selector="displayCommentLines:"')
    item = text[text.rindex('<menuItem ', 0, action):action]
    title = re.search(r'title="([^"]*)"', item) or re.search(r'<string key="title">([^<]*)</string>', item)
    assert title, (lang, 'Help menu item has a title')
    return LANGUAGE_NOTE.sub('', title.group(1).strip())


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--app', type=Path)
    args = parser.parse_args()
    catalog = (ROOT / 'Sources/Settings/TSSettingsSearchCatalog.inc').read_text()
    for key in (DESCRIPTION, LINK):
        assert f'@"row.catalog.general.5.1", @"SettingsCategories", @"{key}"' in catalog, (key, 'searchable')
    for lang, link in EXPECTED.items():
        table = strings(INTERFACES / f'{lang}.lproj/SettingsCategories.strings')
        assert table[LINK] == link, (lang, table[LINK])
        assert link.endswith('…') and not link.endswith('...'), (lang, 'ellipsis character')
        name = help_menu_name(lang)
        assert name in table[DESCRIPTION], (lang, 'description quotes the Help menu item', name, table[DESCRIPTION])
        if args.app:
            built = strings(args.app / f'Contents/Resources/{lang}.lproj/SettingsCategories.strings')
            assert (built[LINK], built[DESCRIPTION]) == (table[LINK], table[DESCRIPTION]), (lang, 'built bundle')
    # The PDF the link opens is the hidden settings document, not the TeXShop Manual.
    help_documents = (ROOT / 'Sources/App/HelpDocuments.m').read_text()
    body = help_documents[help_documents.index('- (IBAction)displayCommentLines:'):]
    body = body[:body.index('\n}')]
    assert 'pathForResource:@"CommentLines" ofType:@"pdf"' in body, 'link opens CommentLines.pdf'
    print(f'PASS: the hidden settings link in {len(EXPECTED)} languages ends with … and its description quotes the Help menu item'
          + (' (built bundle too)' if args.app else ''))


if __name__ == '__main__':
    main()
