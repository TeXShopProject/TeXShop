#!/usr/bin/env python3
"""Check all current help pages and the manual against the displayed Settings routes."""
from pathlib import Path
import html
import json
import re
import subprocess

ROOT = Path(__file__).resolve().parents[1]
LANGUAGES = ('en', 'ja', 'ko', 'de', 'es')
CATEGORIES = ('general', 'documents', 'editor', 'spelling', 'appearance',
              'preview', 'typesetting', 'console', 'keyboard', 'updates')
# Quoted names and HTML-wrapped names must be checked too. Source *menu* and
# theme *settings* remain valid; the removed sidebar categories do not.
QUOTE = r'["“”„«»\x27`]*'
ENGLISH = (rf'\b(?:Source|Engines?|Misc ?[12]?|Themes){QUOTE}\s+'
           rf'(?:configuration\s+)?(?:tab|category|pane|section)\b|'
           rf'\b(?:tab|category|pane)\s+{QUOTE}(?:Source|Engines?|Misc\d?|Themes)\b')
CATEGORY_RULES = {
    'en': ENGLISH,
    'ko': ENGLISH + r'|(문서|엔진설정|기타1|기타2)\s*(?:\(Engine\)\s*)?(탭|범주|카테고리|tab)',
    'ja': r'「(?:内部設定|詳細1|詳細2|書類|ソース|テーマ)」(?:タブ|カテゴリ|パネル|項目)|「(?:内部設定|詳細1|詳細2)」|内部設定\s*>',
    'de': rf'\b(?:Quelltext|Programme|Div\. ?[12]){QUOTE}[- ]?(?:Reiter|Kategorie|Tab|Bereich)\b|(?:Reiter|Kategorie)\s+{QUOTE}(?:Quelltext|Programme|Div\.)',
    'es': rf'\b(?:solapa|pestaña|categoría|sección|apartado)\s+{QUOTE}(?:Código|Motor|Misc\d?|Documento|Modos)\b',
}
REMOVED_MENU = (r'Edit Key Bindings File|Open Completion File|Edit Command Completion File|'
                r'Key Bindings menu|Vervollständigungsdatei öffnen|Autovervollständigung-Datei|'
                r'Abrir archivo de compleciones|Editar archivo de autocompleciones|'
                r'補完用語ファイルを開く|補完用語ファイルの編集|キーバインドファイルの編集')
OLD_UI = (r'Edit Rules|Check Spelling While Typing is independent|share one vertical scroll area|'
          r'LaTeXに対応したスペルチェック|従来のスペルチェック|同じ縦スクロール領域|'
          r'einen vertikalen Scrollbereich|un área de desplazamiento vertical|'
          r'two tabs inside Themes remain|テーマ内の2つのタブはそのまま')

def strings(path):
    return json.loads(subprocess.check_output(['plutil', '-convert', 'json', '-o', '-', str(path)]))

def read_help(path, language):
    raw = path.read_bytes()
    match = re.search(br'charset=([^"\s>]+)', raw, re.I)
    encoding = match[1].decode() if match else ('cp932' if language == 'ja' else 'latin-1')
    encoding = {'x-sjis': 'cp932', 'shift_jis': 'cp932'}.get(encoding.lower(), encoding)
    decoded = raw.decode(encoding)  # No replacement of invalid bytes.
    assert decoded.encode(encoding) == raw, path
    return html.unescape(decoded)

def plain(text):
    return re.sub(r'\s+', ' ', re.sub(r'<[^>]+>', ' ', text))

def check_obsolete(text, language, path):
    text = plain(text)
    for pattern in (CATEGORY_RULES[language], REMOVED_MENU, OLD_UI):
        match = re.search(pattern, text)
        assert match is None, (str(path), text[max(0, match.start()-60):match.end()+60])

page_count = 0
for language in LANGUAGES:
    folder = ROOT / f'Resources/Interfaces/{language}.lproj'
    categories = strings(ROOT / 'Resources/Interfaces' / ('Base.lproj' if language == 'en' else language+'.lproj') / 'SettingsCategories.strings')
    labels = strings(folder / 'Localizable.strings')
    pages = {}
    for path in sorted((folder / 'TeXShopHelp/pgs').glob('*.htm')):
        # Release history describes old versions deliberately; current instructions never do.
        if path.stem == 'whatisnew':
            continue
        text = read_help(path, language)
        check_obsolete(text, language, path)
        pages[path.stem] = text
        page_count += 1
    for name in ('basic_preferences', 'basic_spelling', 'configure_menushortcuts', 'configure_prefchanges'):
        text = pages[name]
        for key in CATEGORIES:
            assert categories[key] in text, (language, name, key)
        for key in ('Use LaTeX-aware spell checking (recommended)', 'Use legacy spell checking'):
            assert labels[key] in text, (language, name, key)
    for name, key in (('basic_autocompletion', 'Edit Key Bindings…'), ('basic_commandcompletion', 'Edit Command Completion…')):
        # Older de/es key-binding articles do not name an editor command; their
        # command-completion article does, and must use the current button label.
        if name == 'basic_commandcompletion' or language in ('en', 'ko', 'ja'):
            assert labels[key] in pages[name] and categories['keyboard'] in pages[name], (language, name, key)

manual = (ROOT / 'Manual Source/Manual.tex').read_text()
check_obsolete(manual, 'en', 'Manual.tex')
for file in ('Documentation/Releases/5.60.md', 'website/release-notes.html', 'Manual Source/Manual.tex'):
    text = (ROOT / file).read_text()
    assert 'NSUserKeyEquivalents' in text, file
    for obsolete in ('Settings → Spelling', 'with Edit Rules beneath', 'indented Edit Rules button',
                     'In Settings, Spelling,', 'Source category, there is a box',
                     'Input settings and shortcut results share one vertical scroll area'):
        assert obsolete not in text, (file, obsolete)
for file in ('Documentation/Releases/5.60-ja.md', 'website/release-notes-ja.html'):
    text = (ROOT / file).read_text()
    assert 'NSUserKeyEquivalents' in text and 'LaTeXの構造を考慮する（推奨）' in text and '従来方式を使う' in text
    assert '入力設定とショートカット一覧は同じ縦スクロール領域' not in text
contract = json.loads((ROOT / 'Tests/Fixtures/SettingsCategoryGroups.json').read_text())
assert not re.search(r'audit|監査|計画書|作業計画', contract['source'], re.I), 'Category fixture provenance must be independent of internal documents'
print(f'PASS: {page_count} current help pages in five languages, 20 category overviews, manual, editing routes and original encodings')
