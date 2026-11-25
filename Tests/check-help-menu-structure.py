#!/usr/bin/env python3
"""The Help menu has the same structure in every language.

In 6.00 the Help menu starts with TeXShop Help (named as Apple names an application's help in each
language), the manual and First Steps, then the guides to TeXShop features (the quick start guide to
command completion first), the TeX documentation with George
Grätzer's Short Course, the notes of the release, and an Older Documents submenu with the documents written for
earlier versions by Herbert Schulz, Michael Sharpe and Richard Koch. Spell checking and the differences between
key bindings, macros and command completion are pages of TeXShop Help, not items of their own. Short Course Supplements --> Desktop, which copied the files of the 4th edition
next to the 5th edition of the Short Course, is gone with its files. Items that open a document only in
English say so in every language, in the same words for every item of a language. The menu is the
application's Help menu (systemMenu="help"), so macOS adds its search field. Reads the nibs and sources only.
With --mutation NAME the harness checks a mutated copy and must fail; --mutations runs them all."""
from pathlib import Path
import re
import subprocess
import sys

root = Path(__file__).resolve().parents[1]
TOP = ['showHelp', 'displayManual', 'displayGettingStartedTeXShop', '-', 'displayCommandCompletionQuickStart', 'displayCommentLines',
       'displayFileEncoding', 'displayHTMLHelp', '-', 'displayHelpForPackage', 'displayTeXLiveDocumentation', 'SHORT', '-', 'displayThisRelease',
       'displayChanges', '-', 'OLDER']
# TeXShop Help as Apple names an application's help in each language, and the Older Documents submenu.
HELP = {'Base': 'TeXShop Help', 'ja': 'TeXShopヘルプ', 'de': 'TeXShop-Hilfe', 'es': 'Ayuda de TeXShop', 'fr': 'Aide TeXShop',
        'it': 'Aiuto di TeXShop', 'ko': 'TeXShop 도움말', 'nl': 'TeXShop Help', 'pt': 'Ajuda do TeXShop', 'pt-PT': 'Ajuda do TeXShop',
        'ro': 'Ajutor TeXShop', 'zh_CN': 'TeXShop帮助'}
OLDER_TITLE = {'Base': 'Older Documents', 'ja': '過去の資料', 'de': 'Ältere Dokumente', 'es': 'Documentos antiguos',
               'fr': 'Documents plus anciens', 'it': 'Documenti meno recenti', 'ko': '지난 자료', 'nl': 'Oudere documenten',
               'pt': 'Documentos antigos', 'pt-PT': 'Documentos antigos', 'ro': 'Documente mai vechi', 'zh_CN': '早期文档'}
OLDER = ['displayTipsandTricks', 'displayRecentTeXFonts', 'displayNotesonApplescript', '-',
         'displayGettingStartedXeTeX', 'displayGettingStartedLatex']
# George Grätzer's Short Course: the course, all symbol tables, then each table of the math and the text symbols in
# the order of the book (Appendix B, Appendix C).
SHORT = ['displayShortCourse', 'displayTables', '-', 'displayHG', 'displayBinary', 'displayMoreBinary', 'displayNegatedBinary',
         'displayBinaryOperations', 'displayArrows', 'displayMiscSymbols', 'displayDelimiters', 'displayOperators',
         'displayLargeOperators', 'displayMathAccents', 'displayMathSpacing', '-', 'displayEuropean', 'displayTextAccents',
         'displayTextSizes', 'displayTextSymbols', 'displayTextSpacing']
MARK = {'de': ' (Englisch)', 'ja': '（英語）', 'ko': ' (영문)', 'es': ' (en inglés)', 'fr': ' (en anglais)',
        'it': ' (in inglese)', 'nl': ' (Engels)', 'pt': ' (em inglês)', 'pt-PT': ' (em inglês)',
        'ro': ' (în engleză)', 'zh_CN': '（英文）'}
ENGLISH_ONLY = {'displayThisRelease', 'displayChanges', 'displayTeXLiveDocumentation', 'displayGettingStartedTeXShop',
                'displayManual', 'displayHTMLHelp', 'displayCommandCompletionQuickStart', 'displayFileEncoding', 'displayTipsandTricks',
                'displayCommentLines', 'displayRecentTeXFonts', 'displayNotesonApplescript', 'displayGettingStartedXeTeX',
                'displayGettingStartedLatex'}
# Documents a language has in its own words (TeX Live Documentation of pt-PT falls back to pt).
OWN = {'es': {'displayTeXLiveDocumentation'}, 'pt': {'displayTeXLiveDocumentation'}, 'pt-PT': {'displayTeXLiveDocumentation'},
       'fr': {'displayTeXLiveDocumentation', 'displayFileEncoding', 'displayTipsandTricks'}}
MUTATIONS = {
    # The supplements item comes back in Base.
    'supplements': ('Resources/Interfaces/Base.lproj/MainMenu.nib/designable.nib',
                    '<menuItem isSeparatorItem="YES" id="GrC-00-Sep"/>',
                    '<menuItem isSeparatorItem="YES" id="GrC-00-Sep"/>\n<menuItem title="Short Course Supplements" id="719" identifier="TSShortcut.supplementsToDesktop:.0"><connections><action selector="supplementsToDesktop:" target="705" id="778"/></connections></menuItem>'),
    # Japanese loses the English mark on Changes.
    'mark-missing': ('Resources/Interfaces/ja.lproj/MainMenu.nib/designable.nib', 'title="更新履歴（英語）"', 'title="更新履歴"'),
    # French marks its own Tips and Tricks as English.
    'mark-on-own': ('Resources/Interfaces/fr.lproj/MainMenu.nib/designable.nib', 'title="Trucs et astuces pour TeXShop"', 'title="Trucs et astuces pour TeXShop (en anglais)"'),
    # The English menu marks a document as English.
    'mark-in-english': ('Resources/Interfaces/Base.lproj/MainMenu.nib/designable.nib', 'title="TeXShop Manual"', 'title="TeXShop Manual (English)"'),
    # Japanese loses the English mark on the command completion quick start.
    'quickstart-mark-missing': ('Resources/Interfaces/ja.lproj/MainMenu.nib/designable.nib', 'title="コマンド補完クイックスタート（英語）"', 'title="コマンド補完クイックスタート"'),
    # The command completion quick start item is not connected to its action.
    'quickstart-action': ('Resources/Interfaces/de.lproj/MainMenu.nib/designable.nib', '<action selector="displayCommandCompletionQuickStart:"', '<action selector="displayCommandCompletionQuickStar:"'),
    # A symbol table leaves the Short Course.
    'table-missing': ('Resources/Interfaces/ja.lproj/MainMenu.nib/designable.nib', '<action selector="displayArrows:"', '<action selector="displayArrowz:"'),
    # The Short Course submenu loses its mark.
    'short-unmarked': ('Resources/Interfaces/de.lproj/MainMenu.nib/designable.nib', 'title="George Grätzers Kurzkurs (Englisch)" id="GrC-Mn-Itm"', 'title="George Grätzers Kurzkurs" id="GrC-Mn-Itm"'),
    # TeXShop Help keeps its former name.
    'help-panel-name': ('Resources/Interfaces/ja.lproj/MainMenu.nib/designable.nib', 'title="TeXShopヘルプ"', 'title="TeXShopヘルプパネル..."'),
    # Older Documents keeps its former Japanese name.
    'older-name': ('Resources/Interfaces/ja.lproj/MainMenu.nib/designable.nib', 'title="過去の資料" id="HlO-Dc-Mnu"', 'title="以前の資料" id="HlO-Dc-Mnu"'),
    # The release notes come first again.
    'release-first': ('Resources/Interfaces/Base.lproj/MainMenu.nib/designable.nib', '<action selector="showHelp:"', '<action selector="displayThisRelease:"'),
    # First Steps sends readers to the former Help Panel.
    'first-steps-panel': ('DocumentSources/First Steps Source/First Steps with TeXShop.tex', 'documentation in TeXShop Help under', 'documentation in the TeXShop Help Panel under'),
    # Spell Checking Help comes back as an item of its own.
    'spell-help-item': ('Sources/Editor/TSSpellSupport.m', '+ (void)installMenuItems\n{', '+ (void)installMenuItems\n{\n    // showSpellCheckingHelp:'),
    # The menu is not the application's Help menu.
    'not-help-menu': ('Resources/Interfaces/de.lproj/MainMenu.nib/designable.nib', 'systemMenu="help" ', ''),
}

failures = []


def check(ok, message):
    if not ok:
        failures.append(message)


def help_menu(text):
    """{'TOP', 'OLDER', 'SHORT'}: items as selectors or '-' ('OLDER'/'SHORT' for the submenus), {selector: title},
    {'OLDER'/'SHORT': submenu title}, and the attributes of the Help menu."""
    a = text.index('systemMenu="help"')
    start = text.rfind('<menu key="submenu"', 0, a)
    head = text[start:text.index('>', start)]
    end = text.index('</menu>\n                </menuItem>\n            </items>', a)
    body = text[start:end]
    lists, titles, submenus, stack, last = {'TOP': [], 'OLDER': [], 'SHORT': []}, {}, {}, [], None
    for m in re.finditer(r'<menuItem (isSeparatorItem="YES")?[^>]*?(?:title="([^"]*)")?[^>]*>|<menu key="submenu"|</menu>|<action selector="(\w+):"', body):
        whole = m.group(0)
        current = stack[-1] if stack else 'TOP'
        if whole.startswith('<menu key="submenu"'):
            if m.start() > 0:
                stack.append(pending)
        elif whole == '</menu>':
            stack.pop()
        elif m.group(1):
            lists[current].append('-')
        elif whole.startswith('<menuItem'):
            last = m.group(2)
            pending = 'OLDER' if 'HlO-Dc-Mnu' in whole else 'SHORT' if 'GrC-Mn-Itm' in whole else None
            if pending:
                lists[current].append(pending)
                submenus[pending] = last
        elif m.group(3):
            lists[current].append(m.group(3))
            titles[m.group(3)] = (last, current)
    return lists, titles, submenus, head


def run(overrides):
    for nib in sorted((root / 'Resources/Interfaces').glob('*.lproj/MainMenu.nib/designable.nib')):
        name = nib.relative_to(root).as_posix()
        lang = nib.parts[-3][:-6]
        text = overrides.get(name) or nib.read_text(encoding='utf-8')
        lists, titles, submenus, head = help_menu(text)
        top, older, short = lists['TOP'], lists['OLDER'], lists['SHORT']
        check(top == TOP, f'{lang}: Help menu items {top}')
        check(older == OLDER, f'{lang}: Older Documents items {older}')
        check(short == SHORT, f'{lang}: Short Course items {short}')
        # The Short Course submenu is marked as English in its own title; its items are not.
        mark = MARK.get(lang)
        check((submenus.get('SHORT') or '').endswith(mark) if mark else not any(submenus.get('SHORT', '').endswith(m) for m in set(MARK.values()) | {' (English)'}),
              f"{lang}: the Short Course submenu {'is' if mark else 'is not'} marked: {submenus.get('SHORT')!r}")
        check('systemMenu="help"' in head, f'{lang}: the Help menu is the application Help menu')
        check(titles.get('showHelp', ('',))[0] == HELP[lang], f"{lang}: TeXShop Help is named {titles.get('showHelp', ('',))[0]!r}")
        check(submenus.get('OLDER') == OLDER_TITLE[lang], f"{lang}: Older Documents is named {submenus.get('OLDER')!r}")
        check('supplementsToDesktop' not in text, f'{lang}: Short Course Supplements is gone')
        for selector, (title, place) in titles.items():
            if place == 'SHORT':
                check(not any(title.endswith(m) for m in set(MARK.values()) | {' (English)'}), f'{lang}: {selector} in the Short Course is not marked: {title!r}')
                check(title and '\n' not in title, f'{lang}: {selector} has a title')
                continue
            check('\n' not in title and title == title.strip(), f'{lang}: {selector} title {title!r} has stray space')
            if lang == 'Base':
                # The English menu opens documents in its own language: no item carries a mark.
                check(not any(title.endswith(m) for m in set(MARK.values()) | {' (English)'}), f'Base: {selector} has a language mark: {title!r}')
                continue
            marked = title.endswith(MARK[lang])
            wanted = selector in ENGLISH_ONLY and selector not in OWN.get(lang, set())
            check(marked == wanted, f'{lang}: {selector} {"needs" if wanted else "must not have"} the English mark: {title!r}')
            others = [m for l, m in MARK.items() if m != MARK[lang] and title.endswith(m)]
            check(not others, f'{lang}: {selector} has the mark of another language: {title!r}')
    sources = (root / 'Sources/App/HelpDocuments.m').read_text() + (root / 'Sources/App/HelpDocuments.h').read_text()
    spell = overrides.get('Sources/Editor/TSSpellSupport.m') or (root / 'Sources/Editor/TSSpellSupport.m').read_text()
    check('showSpellCheckingHelp' not in spell and 'SpellCheckingHelp' not in spell, 'spell checking has no Help menu item or window of its own')
    check(not list((root / 'Resources/TeXShop/SpellCheck').glob('SpellCheckingHelp*.html')), 'the separate spell checking help pages are removed')
    check('displayTeXShopConfusion' not in sources, 'HelpDocuments has no displayTeXShopConfusion:')
    check(not list((root / 'Resources/Interfaces').glob('*.lproj/TeXShop Feature Confusion.pdf')), 'TeXShop Feature Confusion is removed')
    check('Feature Confusion' not in (root / 'TeXShop.xcodeproj/project.pbxproj').read_text(), 'the project no longer copies TeXShop Feature Confusion')
    # Current documents opened from the Help menu name TeXShop Help by its menu name, not the former Help Panel.
    for doc in ('DocumentSources/First Steps Source/First Steps with TeXShop.tex', 'DocumentSources/CommentLinesRevised/CommentLines.tex',
                'DocumentSources/Manual Source/Manual.tex'):
        text = overrides.get(doc) or (root / doc).read_text(errors='replace')
        check('Help Panel' not in text, f'{doc} names TeXShop Help, not the Help Panel')
    check('supplementsToDesktop' not in sources, 'HelpDocuments has no supplementsToDesktop:')
    check(not (root / 'Resources/Course Supplements').exists(), 'the 4th edition supplements are removed')
    check('Course Supplements' not in (root / 'TeXShop.xcodeproj/project.pbxproj').read_text(), 'the project no longer copies the supplements')


def main():
    args = sys.argv[1:]
    if args == ['--mutations']:
        bad = []
        for name in MUTATIONS:
            r = subprocess.run([sys.executable, __file__, '--mutation', name], capture_output=True, text=True)
            print(('PASS: detected' if r.returncode else 'FAIL: missed') + f' mutation {name}: ' + (r.stdout.strip().splitlines() or [''])[0])
            if not r.returncode:
                bad.append(name)
        sys.exit(1 if bad else 0)
    overrides = {}
    if args[:1] == ['--mutation']:
        path, old, new = MUTATIONS[args[1]]
        text = (root / path).read_text(encoding='utf-8')
        if old not in text:
            sys.exit(f'mutation {args[1]}: text not found')
        overrides[path] = text.replace(old, new, 1)
    run(overrides)
    if failures:
        for f in failures:
            print('FAIL:', f)
        sys.exit(1)
    print('PASS: 12 Help menus: TeXShop Help first, then the TeXShop documents, the TeX documentation, the release notes and Older Documents; English marks; no separate spell checking or feature confusion items; Help menu of the application')


if __name__ == '__main__':
    main()
