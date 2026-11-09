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
           rf'(?:configuration\s+)?(?:tab|category|pane|flag)\b|'
           rf'\b(?:tab|category|pane)\s+{QUOTE}(?:Source|Engines?|Misc\d?|Themes)\b')
CATEGORY_RULES = {
    'en': ENGLISH + r'|(?i:\b(?:Source|Engines?|Misc ?[12]?|Themes)\s+(?:Preferences|Tab of Preferences)\b|\bThemes\s+panel\b)',
    'ko': ENGLISH + r'|(?i:\b(?:Source|Engines?|Themes)\s+(?:Preferences|Tab of Preferences)\b|\bThemes\s+panel\b)' + r'|(문서|엔진설정|기타1|기타2)\s*(?:\(Engine\)\s*)?(탭|범주|카테고리|tab)',
    'ja': r'「詳細」タブ|「(?:内部設定|詳細1|詳細2|書類|ソース|テーマ)」(?:タブ|カテゴリ|パネル|項目)|「(?:内部設定|詳細1|詳細2)」|内部設定\s*>',
    'de': rf'\bunter\s+{QUOTE}Programme\b|\bTitel\s+Programme\b|(?:Registerkarte)\s+{QUOTE}(?:Programme|Themes|Quelltext)\b|\b(?:Quelltext|Programme|Div\. ?[12]){QUOTE}[- ]?(?:Reiter|Kategorie|Tab|Bereich)\b|(?:Reiter|Kategorie)\s+{QUOTE}(?:Quelltext|Programme|Div\.)',
    'es': rf'\b(?:solapa|pestaña|categoría|sección|apartado)\s+{QUOTE}(?:Código|Motor|Misc\d?|Documento|Modos|Copiar)\b',
}
REMOVED_MENU = (r'Edit Key Bindings File|Open Completion File|Edit Command Completion File|'
                r'Key Bindings menu|Vervollständigungsdatei öffnen|Autovervollständigung-Datei|'
                r'Abrir archivo de compleciones|Editar archivo de autocompleciones|'
                r'補完用語ファイルを開く|補完用語ファイルの編集|キーバインドファイルの編集')
OLD_UI = (r'one at a time|一つずつ開け|하나씩 펼칠|jeweils eine Eingabegruppe|un grupo de entrada a la vez|'
          r'Edit Rules|Check Spelling While Typing is independent|share one vertical scroll area|'
          r'LaTeXに対応したスペルチェック|従来のスペルチェック|同じ縦スクロール領域|'
          r'einen vertikalen Scrollbereich|un área de desplazamiento vertical|'
          r'機能で探す|キーで探す|UTF パッケージ対応|Customizing Menu Shortcuts|'
          r'under Preferences\s*>\s*Source|two tabs inside Themes remain|テーマ内の2つのタブはそのまま|Typesetting tab')

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
    arrows = r'(?:Settings|Preferences|設定|설정|환경설정|Einstellungen|Ajustes|Preferencias)\s*[>→]\s*[「“"«]*(?:Source|Misc\s*[12]|Engines?|Themes|内部設定|詳細[12]|ソース|テーマ|기타[12]|엔진설정|Quelltext|Programme|Div\.\s*[12]|Código|Motor|Modos)\b'
    for pattern in (CATEGORY_RULES[language], REMOVED_MENU, OLD_UI, arrows):
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
        text = read_help(path, language)
        if path.stem == 'whatisnew':
            current = re.search(r'<h5>TeXShop Changes 5\.60</h5>(.*?)(?=<h5>|$)', text, re.S)
            if current is None: continue
            text = current[1]
        check_obsolete(text, language, path)
        pages[path.stem] = text
        page_count += 1
    if language in ('en', 'ko'):
        route = 'Settings > Typesetting > Lookup Commands and BibTeX > BibTeX Engine' if language == 'en' else 'Settings > 조판 > 검색 명령과 BibTeX > BibTeX 엔진'
        assert route in pages['advanced_bibtex'], (language, 'BibTeX Engine route')
    for name in ('basic_preferences', 'basic_spelling', 'configure_menushortcuts', 'configure_prefchanges'):
        text = pages[name]
        assert 'id="settings-search"' in text, (language, name, 'global search instructions')
        if language=='ja':
            for key in ('Search by Function','Search by Key'): assert labels[key] in text, (language,name,key)
        for key in CATEGORIES:
            assert categories[key] in text, (language, name, key)
        for key in ('Use LaTeX-aware spell checking (recommended)', 'Use legacy spell checking'):
            assert labels[key] in text, (language, name, key)
    for name, key in (('basic_autocompletion', 'Edit Key Bindings…'), ('basic_commandcompletion', 'Edit Command Completion…')):
        # Older de/es key-binding articles do not name an editor command; their
        # command-completion article does, and must use the current button label.
        if name == 'basic_commandcompletion' or language in ('en', 'ko', 'ja'):
            assert labels[key] in pages[name] and categories['keyboard'] in pages[name], (language, name, key)

ja_unicode=read_help(ROOT/'Resources/Interfaces/ja.lproj/TeXShopHelp/pgs/advanced_unicode.htm','ja')
assert strings(ROOT/'Resources/Interfaces/ja.lproj/SettingsMiscTwo.strings')['ahm-aK-Qi9.title'] in ja_unicode

manual = (ROOT / 'Manual Source/Manual.tex').read_text()
check_obsolete(manual, 'en', 'Manual.tex')
assert '\\section{Settings for the Source Window}' in manual
font_route = manual.split("To change the font in the Source Window,", 1)[1].split("Choose a font and size", 1)[0]
assert r"{\em Editor}" in font_route and r"{\em Appearance}" not in font_route, "Source font belongs to Editor"
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
assert 'catalog' in contract['source'].lower()
print(f'PASS: {page_count} current help pages in five languages, 20 category overviews, manual, editing routes and original encodings')

# Release changes must belong to the version's Settings section, not its footer.
from html.parser import HTMLParser
class ReleaseParser(HTMLParser):
    def __init__(self):
        super().__init__(); self.stack=[]; self.article=None; self.heading=''; self.in_heading=False; self.items=[]; self.item=None
    def handle_starttag(self,tag,attrs):
        self.stack.append(tag)
        if tag=='article': self.article=dict(attrs).get('id')
        if tag=='h3': self.heading='';self.in_heading=True
        if tag=='li': self.item=[self.article,self.heading,'ul' in self.stack,'']
    def handle_endtag(self,tag):
        if tag=='h3':self.in_heading=False
        if tag=='li' and self.item:self.items.append(self.item);self.item=None
        if tag=='article':self.article=None
        if tag in self.stack: self.stack=self.stack[:len(self.stack)-1-self.stack[::-1].index(tag)]
    def handle_data(self,data):
        if self.in_heading:self.heading+=data
        if self.item:self.item[3]+=data
for suffix,heading,phrase in [('', 'Settings and themes', 'Add Search Settings'),('-ja','設定とテーマ','「設定を検索」')]:
    md=(ROOT/('Documentation/Releases/5.60'+suffix+'.md')).read_text()
    section=md.split('## '+heading+'\n',1)[1].split('\n## ',1)[0]
    assert any(line.startswith('- ') and phrase in line for line in section.splitlines()), (suffix,'release Markdown section')
    parser=ReleaseParser();parser.feed((ROOT/('website/release-notes'+suffix+'.html')).read_text())
    assert any(a=='v5.60' and h==heading and ul and phrase in text for a,h,ul,text in parser.items), (suffix,'release article/list section')
print('PASS: release notes have one Settings item inside v5.60 and the matching Markdown section')
