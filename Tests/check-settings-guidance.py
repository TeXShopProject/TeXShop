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
# Themes is the current category; Appearance, its earlier 5.60 name, and the
# old Themes tab are obsolete.
QUOTE = r'["“”„«»\x27`]*'
ENGLISH = (rf'\b(?:Source|Engines?|Misc\.? ?[12]?|Appearance){QUOTE}\s+'
           rf'(?:configuration\s+)?(?:tab|category|pane|flag)\b|'
           rf'\b(?:tab|category|pane)\s+{QUOTE}(?:Source|Engines?|Misc\d?|Appearance)\b|'
           rf'\bThemes{QUOTE}\s+tab\b|\btab\s+{QUOTE}Themes\b')
CATEGORY_RULES = {
    'en': ENGLISH + r'|(?i:\b(?:Source|Engines?|Misc\.? ?[12]?|Themes)\s+(?:Preferences|Tab of Preferences)\b|\bThemes\s+panel\b)',
    'ko': ENGLISH + r'|(?i:\b(?:Source|Engines?|Themes)\s+(?:Preferences|Tab of Preferences)\b|\bThemes\s+panel\b)' + r'|(문서|엔진설정|기타1|기타2)\s*(?:\(Engine\)\s*)?(탭|범주|카테고리|tab)|모양\s*(?:category|범주|카테고리)|맞춤법 검사, 모양,|모양에서',
    'ja': r'「詳細」タブ|「テーマ」タブ|「(?:内部設定|詳細1|詳細2|書類|ソース|外観)」(?:タブ|カテゴリ|パネル|項目)|「(?:内部設定|詳細1|詳細2)」|内部設定\s*>',
    'de': rf'\bunter\s+{QUOTE}Programme\b|\bTitel\s+Programme\b|(?:Registerkarte)\s+{QUOTE}(?:Programme|Themes|Quelltext)\b|\b(?:Quelltext|Programme|Div\. ?[12]){QUOTE}[- ]?(?:Reiter|Kategorie|Tab|Bereich)\b|(?:Reiter|Kategorie)\s+{QUOTE}(?:Quelltext|Programme|Div\.|Erscheinungsbild)',
    'es': rf'\b(?:solapa|pestaña|categoría|sección|apartado)\s+{QUOTE}(?:Código|Motor|Misc\d?|Documento|Modos|Copiar|Apariencia)\b',
}
REMOVED_MENU = (r'Edit Key Bindings File|Open Completion File|Edit Command Completion File|'
                r'Key Bindings menu|Vervollständigungsdatei öffnen|Autovervollständigung-Datei|'
                r'Abrir archivo de compleciones|Editar archivo de autocompleciones|'
                r'補完用語ファイルを開く|補完用語ファイルの編集|キーバインドファイルの編集')
OLD_UI = (r'An obsolete remembered category opens General.|without a separate background process|高さコンパクトな|標準のアプリアイコンに戻り。|Theme color groups are shown together in Appearance.|設定ウインドウの左下にある|Auswahlmenüs unten in den Einstellungen|En la parte de abajo de la ventana de Ajustes|Both theme color groups appear in one pane|Keyboard results use one vertical scroll area|approved compact layout|30-point sidebar|承認済みのコンパクト|both color groups|テーマの2つの色グループ|A pulldown menu at the bottom of the Settings window|one at a time|一つずつ開け|하나씩 펼칠|jeweils eine Eingabegruppe|un grupo de entrada a la vez|'
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
    arrows = r'(?<!System )(?:Settings|Preferences|設定|설정|환경설정|Einstellungen|Ajustes|Preferencias)\s*[>→›▸»]\s*[「“"«]*(?:Source|Misc\.?\s*[12]|Engines?|Appearance|内部設定|詳細[12]|ソース|外観|모양|기타[12]|엔진설정|Quelltext|Programme|Div\.\s*[12]|Código|Motor|Modos)\b'
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
    overview=pages['basic_preferences']
    assert 'id="settings-search"' in overview,(language,'central search instructions')
    for key in CATEGORIES: assert categories[key] in overview,(language,'overview',key)
    for name in ('basic_spelling','configure_menushortcuts','configure_prefchanges'):
        assert 'id="settings-search"' not in pages[name],(language,name,'duplicate search section')
        assert 'basic_preferences.htm#settings-search' in pages[name],(language,name,'central overview link')
    # The two method rows use their visible Settings names.
    for key in ('catalog.spelling.1.0.title','catalog.spelling.1.2.title'):
        assert categories[key] in overview,(language,'spelling overview',key)
    assert labels['Use legacy spell checking'] not in overview,(language,'spelling overview uses a label the window does not show')
    if language=='ja':
        for key in ('Search by Function','Search by Key','Remove Shortcut','Restore Default','Restore All…'):
            assert key in labels and '「'+labels[key]+'」' in pages['configure_menushortcuts'],('Japanese shortcut button missing',key)
        assert '割り当てを解除' not in pages['configure_menushortcuts'] and '初期状態に戻す' not in pages['configure_menushortcuts'], 'Japanese obsolete shortcut button'
    # Check the DOM location, not just whether the added paragraph exists.
    from html.parser import HTMLParser
    class ContentParser(HTMLParser):
        def __init__(self):super().__init__();self.stack=[];self.outside=[]
        def handle_starttag(self,tag,attrs):
            if tag not in ('br','hr','img','meta','link','input'):self.stack.append((tag,dict(attrs).get('id')))
        def handle_endtag(self,tag):
            for i in range(len(self.stack)-1,-1,-1):
                if self.stack[i][0]==tag:self.stack=self.stack[:i];break
        def handle_data(self,text):
            if not text.strip() or not any(t=='body' for t,i in self.stack):return
            if any(i=='content_border' or t in ('script','style') for t,i in self.stack):return
            chrome=any(i in {'header_background','header_logo','header_chapter','header_title','menu_border'} for t,i in self.stack)
            # Chrome contains navigation links or headings, never body paragraphs.
            heading_or_link=any(t in ('a','h1','h2','h3','h4') for t,i in self.stack) or self.stack[-1][1] in {'header_chapter','header_title'}
            if not (chrome and heading_or_link and not any(t in ('p','dd','dt') for t,i in self.stack)):self.outside.append(text.strip()[:80])
    for name in ('basic_preferences','basic_spelling','configure_menushortcuts','configure_prefchanges','configure_hidden'):
        parser=ContentParser();parser.feed(pages[name]);assert not parser.outside,(language,name,'body text outside content_border',parser.outside)
    # Older de/es key-binding articles do not describe the list; the others name its
    # columns as Settings shows them. Every command-completion article uses the
    # current button label.
    if language in ('en', 'ko', 'ja'):
        assert all(labels[key] in pages['basic_autocompletion'] for key in ('Input Character', 'Output String', 'Insert')) and categories['keyboard'] in pages['basic_autocompletion'], (language, 'basic_autocompletion')
    assert labels['Edit Command Completion…'] in pages['basic_commandcompletion'] and categories['keyboard'] in pages['basic_commandcompletion'], (language, 'basic_commandcompletion')

ja_unicode=read_help(ROOT/'Resources/Interfaces/ja.lproj/TeXShopHelp/pgs/advanced_unicode.htm','ja')
assert strings(ROOT/'Resources/Interfaces/ja.lproj/SettingsMiscTwo.strings')['ahm-aK-Qi9.title'] in ja_unicode

for suffix,language in [('', 'en'),('-ja','ja')]:
    check_obsolete((ROOT/('Documentation/Releases/5.60'+suffix+'.md')).read_text(),language,'current release Markdown')
    web=(ROOT/('website/release-notes'+suffix+'.html')).read_text()
    current=re.search(r'<article[^>]*id="v5.60"[^>]*>(.*?)</article>',web,re.S)
    assert current is not None
    check_obsolete(current[1],language,'current website release')
manual = (ROOT / 'DocumentSources/Manual Source/Manual.tex').read_text()
check_obsolete(manual, 'en', 'Manual.tex')
assert '\\section{Settings for the Source Window}' in manual
assert 'After making a selection, TeXShop must be restarted' not in manual, 'Find Panel restart guidance must distinguish OgreKit'
font_route = manual.split("To change the font in the Source Window,", 1)[1].split("Choose a font and size", 1)[0]
assert r"{\em Editor}" in font_route and r"{\em Appearance}" not in font_route, "Source font belongs to Editor"
for file in ('Documentation/Releases/5.60.md', 'website/release-notes.html', 'DocumentSources/Manual Source/Manual.tex'):
    text = (ROOT / file).read_text()
    assert 'NSUserKeyEquivalents' in text, file
    for obsolete in ('Settings → Spelling', 'with Edit Rules beneath', 'indented Edit Rules button',
                     'In Settings, Spelling,', 'Source category, there is a box',
                     'Input settings and shortcut results share one vertical scroll area'):
        assert obsolete not in text, (file, obsolete)
for file in ('Documentation/Releases/5.60-ja.md', 'website/release-notes-ja.html'):
    text = (ROOT / file).read_text()
    assert 'NSUserKeyEquivalents' in text and 'LaTeXの構造を考慮する（推奨）' in text and '従来の方式' in text and '従来方式を使う' not in text
    assert '入力設定とショートカット一覧は同じ縦スクロール領域' not in text
contract = json.loads((ROOT / 'Tests/Fixtures/SettingsCategoryGroups.json').read_text())
assert 'catalog' in contract['source'].lower()
print(f'PASS: {page_count} current help pages in five languages, five central category overviews and 25 DOM layouts, manual, editing routes and original encodings')

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

comment=(ROOT/'DocumentSources/CommentLinesRevised/CommentLines.tex').read_text()
for key in ('ApplePersistence','WatchServer','ExtraCommandsNotToCheckParameters','ExtraCommandsToCheckParameters'):
    section=comment.split('defaults write TeXShop '+key,1)[1].split('\\item',1)[0]
    assert 'Restart TeXShop' in section,(key,'hidden-setting restart documentation')
print('PASS: four startup-only hidden settings are documented in CommentLines')

# The hidden-settings PDF is part of the shipped documentation contract.
import hashlib
hidden=ROOT/'DocumentSources/CommentLinesRevised/CommentLines.pdf'
from pypdf import PdfReader
pdf_text=' '.join(' '.join(page.extract_text() for page in PdfReader(hidden).pages).split())
for key in ('WatchServer','ApplePersistence','ExtraCommandsToCheckParameters','ExtraCommandsNotToCheckParameters'):
    assert 'defaults write TeXShop '+key in pdf_text,('Hidden PDF current content',key)
    section=pdf_text.split('defaults write TeXShop '+key,1)[1].split('defaults write TeXShop ',1)[0]
    assert 'Restart TeXShop after changing this setting.' in section,('Hidden PDF restart instructions',key)
assert pdf_text.count('Restart TeXShop after changing this setting.')>=4,'Hidden PDF restart instructions'
for target in ('Base','en'):
    product=ROOT/f'Resources/Interfaces/{target}.lproj/CommentLines.pdf'
    assert hidden.read_bytes()==product.read_bytes(),('Hidden PDF distribution identity',target)
print('PASS: hidden PDF current text and distribution identity')

# The current public English copies carry identical Settings layout wording.
phrase='Settings has a compact sidebar with ten categories: General, Documents and Saving, Editor, Keyboard, Spell Checking, Themes, Preview, Typesetting, Console, and Updates. Each category shows overview cards and named groups with switches, right-aligned controls, wrapping labels and indented dependent options. The Dock icon is in General, engine profiles are in Typesetting, and Themes contains only what themes store.'
for filename in ('Documentation/Releases/5.60.md','website/release-notes.html','Resources/Interfaces/en.lproj/TeXShopHelp/pgs/whatisnew.htm'):
    assert phrase in (ROOT/filename).read_text(),('Current release layout copies agree',filename)

# Obsolete unlinked pages still enter help indexes, so they must not ship.
for language in ('en','ko'):
    assert not (ROOT/f'Resources/Interfaces/{language}.lproj/TeXShopHelp/pgs/basic_preferences1.htm').exists(),'Obsolete duplicate preferences help page'
assert 'Transparency settings bring up a full Color Well' not in manual,'Opacity uses a slider in the manual'

warning='A note with a yellow warning symbol explains changes to the spell-checking method, new-PDF zoom or default encoding when relevant. Auto Save requires a restart. The standard Find Panel, the Find Bar and the Advanced Find panel switch immediately; switching to or from OgreKit requires a restart.'
for filename in ('Documentation/Releases/5.60.md','website/release-notes.html','Resources/Interfaces/en.lproj/TeXShopHelp/pgs/whatisnew.htm'):
    text=(ROOT/filename).read_text()
    assert warning in text,('Current release warning copies agree',filename)
    for retired in ('All three groups remain open','Changing the method keeps the inactive options and their values','with all three groups open','without discarding unsaved edits'):
        assert retired not in text,('Retired redundant release explanation',filename,retired)

# Release copies describe Search Settings briefly; details belong to the help and manual.
search_copy='Selecting a result shows and highlights the setting.'
for filename in ('Documentation/Releases/5.60.md','website/release-notes.html','Resources/Interfaces/en.lproj/TeXShopHelp/pgs/whatisnew.htm','DocumentSources/ChangesDocument/Changes.tex'):
    assert search_copy in (ROOT/filename).read_text(),('Release category and color-row guidance',filename)
ja_copy='選んだ項目へ移動して強調します。'
for filename in ('Documentation/Releases/5.60-ja.md','website/release-notes-ja.html'):
    assert ja_copy in (ROOT/filename).read_text(),('Release category and color-row guidance',filename)
ko=html.unescape((ROOT/'Resources/Interfaces/ko.lproj/TeXShopHelp/pgs/basic_preferences.htm').read_text())
assert '카테고리' not in ko and '범주' in ko,'Korean category terminology is consistent'
print('PASS: six release copies and Korean category terminology')

for filename in ['Documentation/Releases/5.60.md','website/release-notes.html','Resources/Interfaces/en.lproj/TeXShopHelp/pgs/whatisnew.htm','DocumentSources/ChangesDocument/Changes.tex']:
    text=(ROOT/filename).read_text()
    assert 'slider, a numeric field or the arrow buttons beside the field' in text,('Opacity numeric field and arrow buttons in release notes',filename)
assert 'slider and a numeric field' in manual,'Opacity numeric field in manual'
for lang,term in {'en':'numeric field','ja':'数値欄','de':'Zahlenfeld','es':'campo numérico','ko':'숫자 입력 필드'}.items():
    page=ROOT/f'Resources/Interfaces/{lang}.lproj/TeXShopHelp/pgs/basic_preferences.htm'
    assert term in read_help(page,lang),('Opacity numeric field in help',lang)
assert 'arrow buttons beside the field to raise or lower it by one percent' in manual,'Opacity arrow buttons in manual'
for lang,term in {'en':'arrow buttons','ja':'矢印ボタン','de':'Pfeiltasten','es':'botones de flecha','ko':'화살표 버튼'}.items():
    page=ROOT/f'Resources/Interfaces/{lang}.lproj/TeXShopHelp/pgs/basic_preferences.htm'
    assert term in read_help(page,lang),('Opacity arrow buttons in help',lang)

for filename in ["Documentation/Releases/5.60-ja.md","website/release-notes-ja.html"]:
    assert "数値欄、その横の矢印ボタン" in (ROOT/filename).read_text(),("Opacity numeric field in release notes",filename)

# Seventh audit: invalid typed text stays intact until commit, as pasted text does.
assert 'Invalid input, including decimals, restores the previous value at the end of editing. Typed and pasted input follow the same rule.' in manual, 'Opacity commit guidance in manual'
for lang,terms in {
    'en':['Invalid text, including decimal values','typed and pasted input follow the same rule'],
    'ja':['小数などの無効な入力は、確定時に元の値へ戻します','打鍵と貼り付けで同じ規則'],
    'de':['Ungültige Eingaben einschließlich Dezimalzahlen','getippten und eingefügten Text gilt dieselbe Regel'],
    'es':['las entradas no válidas, incluidos los decimales','El texto escrito y el pegado siguen la misma regla'],
    'ko':['소수 등 잘못된 입력은 편집을 마칠 때 이전 값으로 돌아갑니다','직접 입력한 텍스트와 붙여넣은 텍스트에 같은 규칙이 적용됩니다'],
}.items():
    text=read_help(ROOT/f'Resources/Interfaces/{lang}.lproj/TeXShopHelp/pgs/basic_preferences.htm',lang)
    for term in terms: assert term in text,('Opacity commit guidance',lang,term)
print('PASS: typed/pasted opacity validation guidance in five helps, manual and six release copies')


def check_internal_link_release(text):
    for phrase in ("Size internal-link previews to the text column of the target page", "never below half size", ">Uwe Schmock</a>", 'issues/12">#12</a>'):
        assert phrase in text, ("Internal-link preview release guidance", phrase)

check_internal_link_release((ROOT/"Resources/Interfaces/en.lproj/TeXShopHelp/pgs/whatisnew.htm").read_text())
print("PASS: English help retains the merged internal-link preview release entry")
