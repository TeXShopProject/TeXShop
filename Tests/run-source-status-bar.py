#!/usr/bin/env python3
"""The status bar under the source (Source > Show Status Bar).

1. Counting: TSStatusBarCounting.m against a Swift restatement of CotEditor's rules
   (characters = Swift's Character count, words = the localized word boundaries, lines and
   line numbers from the line endings, location and column in characters from 0), on fixed
   cases (combining marks, emoji ZWJ sequences, variation selectors, CR LF, Japanese, tabs)
   and on random texts with selections on character boundaries.
2. The bar in the windows of the compiled TSDocument nib of every language, never ordered
   on screen, each language in its own run with its Localizable.strings:
   - it lies flush with the bottom of the source window, of the source side of the window
     that shows both (on either side) and of a split source, and the source sits above it;
   - all six items and the file size fit the windows as the nibs make them;
   - the labels are the agreed translations, the parentheses appear only for a selection
     (and only for numbers above 0), the numbers follow the part being typed in;
   - an unsaved document shows no file size, a saved one shows it as Finder does;
   - Source > Show Status Bar (the production action and validation) hides and shows the
     bars of every document at once and keeps the choice in the defaults;
   - Edit > Statistics… is still there in the 12 menus and TSDocument answers it.
3. --perf: typing into a 5 MB document with and without the bar, and the longest pause of
   the main thread while the bar counts.

--images DIR draws the windows offscreen (no glass: the toolbar is drawn flat).
"""
import argparse, json, os, random, subprocess, sys, tempfile
from pathlib import Path
from source_tree import include_args, source_file
from production_fragments import method, verify_embedded

LANGUAGES = ['Base', 'de', 'es', 'fr', 'it', 'ja', 'ko', 'nl', 'pt', 'pt-PT', 'ro', 'zh_CN']
STRINGS = {  # Lines, Characters, Words, Location, Line, Column, item format, Show Status Bar
    'Base': ['Lines', 'Characters', 'Words', 'Location', 'Line', 'Column', '%1$@: %2$@', 'Show Status Bar'],
    'de': ['Zeilen', 'Zeichen', 'Wörter', 'Position', 'Zeile', 'Spalte', '%1$@: %2$@', 'Statusleiste einblenden'],
    'es': ['Líneas', 'Caracteres', 'Palabras', 'Posición', 'Línea', 'Columna', '%1$@: %2$@', 'Mostrar barra de estado'],
    'fr': ['Lignes', 'Caractères', 'Mots', 'Position', 'Ligne', 'Colonne', '%1$@\u00a0: %2$@', 'Afficher la barre d’état'],
    'it': ['Righe', 'Caratteri', 'Parole', 'Posizione', 'Riga', 'Colonna', '%1$@: %2$@', 'Mostra la barra di stato'],
    'ja': ['行', '文字', '単語', '位置', '行', '列', '%1$@: %2$@', 'ステータスバーを表示'],
    'ko': ['줄', '문자', '단어', '위치', '줄', '열', '%1$@: %2$@', '상태 막대 보기'],
    'nl': ['Regels', 'Tekens', 'Woorden', 'Locatie', 'Regel', 'Kolom', '%1$@: %2$@', 'Toon statusbalk'],
    'pt': ['Linhas', 'Caracteres', 'Palavras', 'Localização', 'Linha', 'Coluna', '%1$@: %2$@', 'Mostrar Barra de Estado'],
    'pt-PT': ['Linhas', 'Caracteres', 'Palavras', 'Posição', 'Linha', 'Coluna', '%1$@: %2$@', 'Mostrar barra de estado'],
    'ro': ['Linii', 'Caractere', 'Cuvinte', 'Poziție', 'Linie', 'Coloană', '%1$@: %2$@', 'Afișați bara de stare'],
    'zh_CN': ['行', '字符', '字', '位置', '行', '列', '%1$@：%2$@', '显示状态栏'],
}
LOCALES = {'Base': 'en_US', 'de': 'de_DE', 'es': 'es_ES', 'fr': 'fr_FR', 'it': 'it_IT', 'ja': 'ja_JP', 'ko': 'ko_KR',
           'nl': 'nl_NL', 'pt': 'pt_BR', 'pt-PT': 'pt_PT', 'ro': 'ro_RO', 'zh_CN': 'zh_CN'}

MUTATIONS = {
    # CR LF counts as two characters, as the text system's composed character sequences do.
    'crlf-two': ('TSStatusBarCounting.m', "            i += next == '\\n' ? 2 : 1;\n", '            i += 1;\n'),
    # The parentheses also appear with nothing selected.
    'parentheses-always': ('TSSourceStatusBar.m', '    if (selected != NSNotFound && selected > 0)\n', '    if (selected != NSNotFound)\n'),
    # Moving the source into the window that shows both leaves the bar behind.
    'not-placed-on-move': ('TSDocument.m', '                }\n            [self.sourceStatusBar placeBelowView: splitView];\n', '                }\n'),
    # The tool tip of a narrow bar stays empty.
    'no-tool-tip': ('TSSourceStatusBar.m', '        self.toolTip = tip;\n', '        ;\n'),
    # Show Status Bar changes the default but not the bars already open.
    'open-bars-unchanged': ('TSSourceStatusBar.m', '    if (source)\n        [self placeBelowView:source];\n', ''),
}

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--mutation', choices=sorted(MUTATIONS))
parser.add_argument('--images', type=Path, help='write offscreen pictures of the windows here')
parser.add_argument('--perf', action='store_true', help='measure typing into a 5 MB document')
args = parser.parse_args()
root = Path(__file__).resolve().parents[1]
names = ('TSStatusBarCounting.m', 'TSSourceStatusBar.m', 'TSDocumentWindowGlass.m', 'TSDocument.m', 'TSAppDelegate.m')
text = {name: source_file(root, name).read_text(encoding='utf-8', errors='surrogateescape') for name in names}
document = text['TSDocument.m']


def span(source, start, end):
    i = source.index(start)
    j = source.index(end, i) + len(end)
    return source[i:j]


fragments = {
    'install': span(document, '    // The status bar under the source.\n', '    [self.sourceStatusBar fileDidChangeAtURL:[self fileURL]];\n'),
    'move': span(document, '            [splitView removeFromSuperview];\n            if (interchange) {\n', '            [self.sourceStatusBar placeBelowView: splitView];\n'),
    'separate': span(document, '            useFullSplitWindow = NO;\n            [splitView removeFromSuperview];\n', '            [self.sourceStatusBar placeBelowView: splitView];\n'),
    'split': method(document, '- (void) splitWindow: sender'),
    'settext': method(document, '- (void) setTextView: (id)aView'),
    'filedate': method(document, '- (void)setFileModificationDate:(NSDate *)date'),
    'toggle': method(text['TSAppDelegate.m'], '- (IBAction)toggleStatusBar:(id)sender'),
    'validate': method(text['TSAppDelegate.m'], '- (BOOL)validateMenuItem:(NSMenuItem *)anItem'),
}
originals = dict(fragments)
if args.mutation:
    name, old, new = MUTATIONS[args.mutation]
    if name == 'TSDocument.m':
        assert fragments['move'].count(old) == 1, args.mutation
        fragments['move'] = fragments['move'].replace(old, new)
    else:
        assert text[name].count(old) == 1, args.mutation
        text[name] = text[name].replace(old, new)

failures = []
def fail(message):
    failures.append(message)
    print('FAIL:', message)

# Edit > Statistics… stays: the menu item in every language, and its methods as on master.
for lang in LANGUAGES:
    nib = (root / f'Resources/Interfaces/{lang}.lproj/MainMenu.nib/designable.nib').read_text(encoding='utf-8')
    if nib.count('selector="showStatistics:"') != 1:
        fail(f'{lang}: Edit > Statistics… is in the menu')
    i = nib.index('selector="toggleStatusBar:"'); item = nib[nib.rfind('<menuItem ', 0, i):i]
    if f'title="{STRINGS[lang][7]}"' not in item or 'identifier="TSShortcut.toggleStatusBar:.0"' not in item:
        fail(f'{lang}: Show Status Bar has its title and identifier')
    numbers = nib.index('selector="showHideLineNumbers:"')
    if not numbers < i < nib.index('<menuItem ', nib.index('</menuItem>', numbers)) + 400:
        fail(f'{lang}: Show Status Bar follows Show Line Numbers')
# Its command opens Text Statistics now (Tests/run-text-statistics.py).
if document.count('- (void)showStatistics: sender') != 1:
    fail('TSDocument answers Edit > Statistics…')

with tempfile.TemporaryDirectory(prefix='texshop-status-bar-') as tmp:
    tmp = Path(tmp)
    for name in ('TSStatusBarCounting.m', 'TSSourceStatusBar.m', 'TSDocumentWindowGlass.m'):
        (tmp / name).write_text(text[name], encoding='utf-8', errors='surrogateescape')

    # 1. Counting against the Swift restatement of CotEditor's rules.
    (tmp / 'oracle.swift').write_text(r'''
import Foundation
func words(_ s: Substring) -> Int { var n = 0; s.enumerateSubstrings(in: s.startIndex..<s.endIndex, options: [.byWords, .localized, .substringNotRequired]) { _, _, _, _ in n += 1 }; return n }
func lines(_ s: String) -> Int { if s.isEmpty { return 0 }; var n = 0; (s as NSString).enumerateSubstrings(in: NSRange(location: 0, length: (s as NSString).length), options: [.byLines, .substringNotRequired]) { _, _, _, _ in n += 1 }; return n }
func isEnd(_ c: unichar) -> Bool { c == 10 || c == 13 || c == 0x85 || c == 0x2028 || c == 0x2029 }
func lineNumber(_ s: String, _ loc: Int) -> Int {
    let ns = s as NSString; if s.isEmpty || loc == 0 { return 1 }
    var n = 0; ns.enumerateSubstrings(in: NSRange(location: 0, length: loc), options: [.byLines, .substringNotRequired]) { _, _, _, _ in n += 1 }
    let insideCRLF = loc < ns.length && ns.character(at: loc - 1) == 13 && ns.character(at: loc) == 10
    if isEnd(ns.character(at: loc - 1)) && !insideCRLF { n += 1 }
    return n
}
func selectedLines(_ s: String, _ r: NSRange) -> Int { r.length == 0 ? 0 : lineNumber(s, r.location + r.length - 1) - lineNumber(s, r.location) + 1 }
let input = try! JSONSerialization.jsonObject(with: FileHandle.standardInput.readDataToEndOfFile()) as! [String: Any]
var out: [Any] = []
if let strings = input["bounds"] as? [String] {
    for s in strings { var b = [0]; var i = s.startIndex; while i < s.endIndex { i = s.index(after: i); b.append(s.utf16.distance(from: s.utf16.startIndex, to: i)) }; out.append(b) }
} else {
    for c in input["cases"] as! [[String: Any]] {
        let s = c["s"] as! String, loc = c["loc"] as! Int, len = c["len"] as! Int
        let r = Range(NSRange(location: loc, length: len), in: s)!
        let ls = (s as NSString).lineRange(for: NSRange(location: loc, length: 0)).location
        let start = Range(NSRange(location: ls, length: 0), in: s)!.lowerBound
        out.append([lines(s), s.count, words(s[...]), selectedLines(s, NSRange(location: loc, length: len)), s[r].count, words(s[r]),
                    s.distance(from: s.startIndex, to: r.lowerBound), lineNumber(s, loc), s.distance(from: start, to: r.lowerBound)])
    }
}
print(String(data: try! JSONSerialization.data(withJSONObject: out), encoding: .utf8)!)
''')
    (tmp / 'mine.m').write_text(r'''
#import <Foundation/Foundation.h>
#import "TSStatusBarCounting.h"
int main(void) { @autoreleasepool {
    NSDictionary *input = [NSJSONSerialization JSONObjectWithData:[NSFileHandle.fileHandleWithStandardInput readDataToEndOfFile] options:0 error:nil];
    NSMutableArray *out = [NSMutableArray array];
    for (NSDictionary *c in input[@"cases"]) {
        TSStatusBarCounts k = TSStatusBarCountsUnknown();
        TSStatusBarCount(c[@"s"], @[[NSValue valueWithRange:NSMakeRange([c[@"loc"] unsignedIntegerValue], [c[@"len"] unsignedIntegerValue])]], YES, YES, &k, nil);
        [out addObject:@[@(k.lines), @(k.characters), @(k.words), @(k.selectedLines), @(k.selectedCharacters), @(k.selectedWords), @(k.location), @(k.line), @(k.column)]];
    }
    printf("%s\n", [[NSString alloc] initWithData:[NSJSONSerialization dataWithJSONObject:out options:0 error:nil] encoding:NSUTF8StringEncoding].UTF8String);
} return 0; }
''')
    subprocess.run(['xcrun', 'swiftc', '-O', str(tmp / 'oracle.swift'), '-o', str(tmp / 'oracle')], check=True, stderr=subprocess.DEVNULL)
    subprocess.run(['xcrun', 'clang', '-fobjc-arc', '-framework', 'Foundation', '-I', str(tmp), *include_args(root),
                    str(tmp / 'mine.m'), str(tmp / 'TSStatusBarCounting.m'), '-o', str(tmp / 'mine')], check=True)
    run = lambda exe, data: json.loads(subprocess.run([str(tmp / exe), '-AppleLanguages', '(ja)'], input=json.dumps(data).encode(),
                                                      capture_output=True, check=True).stdout)
    names9 = ['lines', 'characters', 'words', 'selected lines', 'selected characters', 'selected words', 'location', 'line', 'column']
    # Fixed cases: [text, selection start, length (UTF-16), expected numbers or None for the oracle's]
    fixed = [
        ('あああAあ', 5, 0, [1, 5, None, 0, 0, 0, 5, 1, 5]),            # the agreed picture: cursor at the end
        ('a\r\nb', 1, 3, [2, 3, 2, 2, 2, 1, 1, 1, 1]),                 # CotEditor's own CR LF case
        ('dog is 🐕.\ncow is 🐄.\nBoth are 👍🏼.', 11, 10, [3, 31, 6, 1, 9, 2, 10, 2, 0]),  # CotEditor's own case
        ('e\u0301te\u0301', 0, 5, [1, 3, None, 1, 3, None, 0, 1, 0]),   # combining acute accents
        ('👨\u200d👩\u200d👧\u200d👦 ok', 11, 0, [1, 4, None, 0, 0, 0, 1, 1, 1]),  # one ZWJ family, then " ok"
        ('葛\U000E0100城', 3, 1, [1, 2, None, 1, 1, None, 1, 1, 1]),     # an ideographic variation selector
        ('\t\tx', 3, 0, [1, 3, 1, 0, 0, 0, 3, 1, 3]),                  # a tab is one column
        ('日本語の文章です。\n二行目', 10, 3, [2, 13, None, 1, 3, None, 10, 2, 0]),
        ('a\r\n', 3, 0, [1, 2, 1, 0, 0, 0, 2, 2, 0]),                   # an empty last line is not counted
        ('', 0, 0, [0, 0, 0, 0, 0, 0, 0, 1, 0]),
    ]
    cases = [{'s': s, 'loc': a, 'len': n} for s, a, n, _ in fixed]
    random.seed(20261115)
    atoms = ['a', 'Z', ' ', '\t', '\n', '\r', '\r\n', '\u2028', '\u2029', '\x85', '\x0c', 'é', 'e\u0301', '\u0301', 'あ', 'か\u3099',
             '漢', '葛\U000E0100', '👍🏼', '👨\u200d👩\u200d👧', '🇯🇵', '🇺', '\u200d', '©\ufe0f', '한', '\u1100\u1161', '각\u11a8', 'ก้',
             'क्षि', '\\section{x}', '.', "'", '3.14', 'Ａ', 'ｶﾞ', 'ー', '。', '\u302a', '\u0600a']
    texts = [''.join(random.choice(atoms) for _ in range(random.randint(0, 30))) for _ in range(3000)]
    for s, bounds in zip(texts, run('oracle', {'bounds': texts})):
        a = random.choice(bounds); b = random.choice([x for x in bounds if x >= a])
        cases.append({'s': s, 'loc': a, 'len': b - a})
    expected, got = run('oracle', {'cases': cases}), run('mine', {'cases': cases})
    for i, (c, e, g) in enumerate(zip(cases, expected, got)):
        if i < len(fixed):
            want = [e[k] if v is None else v for k, v in enumerate(fixed[i][3])]
            if want != e:
                fail(f'the restatement of CotEditor agrees with the fixed case {c["s"]!r}: {want} {e}')
            e = want
        if e != g:
            fail(f'counts of {c["s"]!r} at {c["loc"]},{c["len"]}: ' + ', '.join(f'{n} {x}≠{y}' for n, x, y in zip(names9, e, g) if x != y))
            if len(failures) > 20:
                break
    print(f'counting: {len(cases)} texts ({len(fixed)} fixed) agree with the restatement of CotEditor' if not failures else 'counting: mismatches')

    # 2. The bar in the windows.
    program = r'''
#import <Cocoa/Cocoa.h>
#import <PDFKit/PDFKit.h>
#import <objc/runtime.h>
#import "TestAppKitIsolation.h"
#import "TSDocumentWindowGlass.h"
#import "TSSourceStatusBar.h"
static int failures, checks;
static void Check(BOOL ok, NSString *name) { checks++; if (!ok) { printf("FAIL: %s\n", name.UTF8String); failures++; } }
static void TSSplitToggleItemsFollowSplit(void) {}
@interface TSTextEditorWindow : NSWindow @end @implementation TSTextEditorWindow @end
@interface TSFullSplitWindow : NSWindow @end @implementation TSFullSplitWindow @end

@interface TSDocument : NSObject
{
@public
    NSSplitView *splitView;
    NSScrollView *scrollView, *scrollView2;
    NSTextView *textView, *textView1, *textView2;
    NSView *leftView, *rightView;
    NSWindow *textWindow, *fullSplitWindow;
    NSDrawer *myDrawer;
    BOOL windowIsSplit, useFullSplitWindow;
    NSTextStorage *_textStorage;
}
@property (strong) NSWindow *pdfKitWindow;
@property (strong) PDFView *myPDFKitView, *myPDFKitView2;
@property (strong) TSSourceStatusBar *sourceStatusBar;
@property (strong) NSURL *fileURL;
@end
@interface NSObject (TSFileDate)
- (void)setFileModificationDate:(NSDate *)date;
@end
@implementation NSObject (TSFileDate)
- (void)setFileModificationDate:(NSDate *)date {}
@end
@implementation TSDocument
- (void)setValue:(id)value forUndefinedKey:(NSString *)key {}
- (void)removeCurrentLineColor:(id)view {}
- (id)textView { return textView; }
- (void)installStatusBar {
INSTALL}
- (void)moveSourceToSides:(BOOL)interchange {
MOVE}
- (void)separateWindows {
    if (useFullSplitWindow) {
SEPARATE    }
}
SPLITMETHOD
SETTEXTMETHOD
FILEDATEMETHOD
@end

@interface TSAppDelegateProbe : NSObject
- (IBAction)displayLatexPanel:(id)sender;
- (IBAction)displayMatrixPanel:(id)sender;
@end
@implementation TSAppDelegateProbe
- (IBAction)displayLatexPanel:(id)sender {}
- (IBAction)displayMatrixPanel:(id)sender {}
TOGGLEMETHOD
VALIDATEMETHOD
@end

static void Register(NSString *name, Class base) {
    if (NSClassFromString(name)) return;
    objc_registerClassPair(objc_allocateClassPair(base, name.UTF8String, 0));
}
@interface GlassToolbar : NSObject <NSToolbarDelegate> @end
@implementation GlassToolbar
- (NSArray *)items { return @[@"a", @"b", @"c"]; }
- (NSArray *)toolbarDefaultItemIdentifiers:(NSToolbar *)toolbar { return self.items; }
- (NSArray *)toolbarAllowedItemIdentifiers:(NSToolbar *)toolbar { return self.items; }
- (NSToolbarItem *)toolbar:(NSToolbar *)toolbar itemForItemIdentifier:(NSString *)identifier willBeInsertedIntoToolbar:(BOOL)flag {
    NSToolbarItem *item = [[NSToolbarItem alloc] initWithItemIdentifier:identifier];
    item.label = identifier; item.image = [NSImage imageWithSystemSymbolName:@"doc" accessibilityDescription:nil];
    return item;
}
@end
static GlassToolbar *toolbarDelegate;
static NSData *nibData;

static void Settle(NSWindow *window) {
    for (int i = 0; i < 3; i++) { [window layoutIfNeeded]; [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.01]]; }
}
static void WaitForCount(TSSourceStatusBar *bar) {
    NSDate *limit = [NSDate dateWithTimeIntervalSinceNow:20];
    while (bar.counting && limit.timeIntervalSinceNow > 0) [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.005]];
}
static TSDocument *Open(NSString *string) {
    TSDocument *doc = [TSDocument new];
    NSArray *objects;
    if (![[[NSNib alloc] initWithNibData:nibData bundle:nil] instantiateWithOwner:doc topLevelObjects:&objects]) return nil;
    for (NSWindow *w in objects) if ([w isKindOfClass:NSWindow.class]) w.releasedWhenClosed = NO;
    doc->textView = doc->textView1;
    [doc->scrollView2 removeFromSuperview];
    [doc.myPDFKitView2 removeFromSuperview];
    doc->_textStorage = doc->textView1.textStorage;
    [doc->textView2.layoutManager replaceTextStorage:doc->_textStorage];
    [doc->_textStorage setAttributedString:[[NSAttributedString alloc] initWithString:string attributes:@{NSFontAttributeName: [NSFont userFixedPitchFontOfSize:13], NSForegroundColorAttributeName: NSColor.textColor}]];
    doc->textView2.font = doc->textView1.font;
    for (NSWindow *w in @[doc->textWindow, doc.pdfKitWindow, doc->fullSplitWindow]) {
        w.toolbarStyle = NSWindowToolbarStyleExpanded;
        NSToolbar *toolbar = [[NSToolbar alloc] initWithIdentifier:[@"bar-" stringByAppendingString:NSStringFromClass(w.class)]];
        toolbar.delegate = toolbarDelegate; w.toolbar = toolbar;
        TSDocumentWindowPrepare(w);
    }
    [doc installStatusBar];
    WaitForCount(doc.sourceStatusBar);
    return doc;
}
static NSRect InWindow(NSView *v) { return [v convertRect:v.bounds toView:nil]; }
// The bar lies at the bottom of the window side that holds the source, the source right above it.
static void CheckPlaced(TSDocument *doc, NSString *where) {
    TSSourceStatusBar *bar = doc.sourceStatusBar;
    NSView *parent = doc->splitView.superview;
    NSRect b = InWindow(bar), s = InWindow(doc->splitView), p = InWindow(parent);
    Check(bar.superview == parent && bar.window != nil, [NSString stringWithFormat:@"%@: the bar is beside the source", where]);
    Check(fabs(NSMinY(b)) < 0.5 && fabs(NSHeight(b) - TSSourceStatusBar.barHeight) < 0.5 && fabs(NSWidth(b) - NSWidth(p)) < 0.5 && fabs(NSMinX(b) - NSMinX(p)) < 0.5,
          [NSString stringWithFormat:@"%@: the bar lies flush with the bottom of the window, as wide as the source (%@ in %@)", where, NSStringFromRect(b), NSStringFromRect(p)]);
    Check(fabs(NSMinY(s) - NSMaxY(b)) < 0.5 && fabs(NSMaxY(s) - NSMaxY(p)) < 0.5,
          [NSString stringWithFormat:@"%@: the source fills the rest above the bar (%@)", where, NSStringFromRect(s)]);
}
// Without a selection all six items and the file size fit; with one, the items that do not fit are left out whole,
// from the end, never cut.
static void CheckFits(TSSourceStatusBar *bar, NSString *where, BOOL all) {
    NSArray *shown = bar.visibleItems, *every = bar.allItems;
    BOOL prefix = shown.count >= 1 && [every subarrayWithRange:NSMakeRange(0, shown.count)].count == shown.count
        && [[every subarrayWithRange:NSMakeRange(0, shown.count)] isEqual:shown];
    Check(prefix && (!all || (shown.count == 6 && (bar.fileSize == nil || bar.visibleFileSize != nil) && bar.statisticsButton != nil)),
          [NSString stringWithFormat:@"%@: %@ (%@ of %@, %.0f wide)", where, all ? @"all six items and the file size fit" : @"whole items from the left",
           [shown componentsJoinedByString:@" | "], [every componentsJoinedByString:@" | "], NSWidth(bar.bounds)]);
    if (!all && shown.count < 6) printf("NOTE: %s: %lu of 6 items fit\n", where.UTF8String, (unsigned long)shown.count);
    NSString *tip = [every componentsJoinedByString:@"\n"];
    Check(shown.count < every.count ? [bar.toolTip isEqual:tip] : bar.toolTip == nil,
          [NSString stringWithFormat:@"%@: the tool tip lists every item only when some are left out (%@)", where, bar.toolTip]);
}
static NSString *Item(NSArray *labels, NSString *format, NSUInteger i, NSString *value) {
    return [[format stringByReplacingOccurrencesOfString:@"%1$@" withString:labels[i]] stringByReplacingOccurrencesOfString:@"%2$@" withString:value];
}
static void Select(TSDocument *doc, NSTextView *view, NSRange range) {
    view.selectedRange = range;
    [doc setTextView:view];
    WaitForCount(doc.sourceStatusBar);
}
static NSBitmapImageRep *Draw(NSWindow *window) {
    NSView *frame = window.contentView.superview;
    [window layoutIfNeeded]; [frame layoutSubtreeIfNeeded];
    NSBitmapImageRep *rep = [frame bitmapImageRepForCachingDisplayInRect:frame.bounds];
    [frame cacheDisplayInRect:frame.bounds toBitmapImageRep:rep];
    return rep;
}
static NSString *images;
static void Save(NSWindow *window, NSString *name) {
    if (!images) return;
    for (NSString *look in @[@"light", @"dark"]) {
        window.appearance = [NSAppearance appearanceNamed:[look isEqual:@"dark"] ? NSAppearanceNameDarkAqua : NSAppearanceNameAqua];
        [[Draw(window) representationUsingType:NSBitmapImageFileTypePNG properties:@{}]
            writeToFile:[images stringByAppendingPathComponent:[NSString stringWithFormat:@"%@-%@.png", name, look]] atomically:YES];
    }
}
static NSString *Sample(void) {
    NSMutableString *s = [NSMutableString stringWithString:@"\\documentclass{article}\n\\begin{document}\n"];
    for (int i = 1; i <= 60; i++) [s appendFormat:@"Line %d: Hello, world! こんにちは。 é 👍🏼\n", i];
    [s appendString:@"\\end{document}\n"];
    return s;
}

static void Perf(void) {
    NSMutableString *big = [NSMutableString string];
    NSString *unit = @"\\section{Intro} The quick brown fox, 日本語の文章です。数式 $\\alpha$ と、かな漢字。\n";
    while ([big lengthOfBytesUsingEncoding:NSUTF8StringEncoding] < 5 * 1000 * 1000) [big appendString:unit];
    NSString *string = big;
    for (NSNumber *withBar in @[@NO, @YES]) {
        TSDocument *doc = Open(string);
        doc->textView1.layoutManager.allowsNonContiguousLayout = YES;
        if (!withBar.boolValue) { [doc.sourceStatusBar stop]; [doc.sourceStatusBar removeFromSuperview]; }
        doc->textView1.selectedRange = NSMakeRange(doc->_textStorage.length / 2, 0);
        Settle(doc->textWindow);
        // Typing: 200 keystrokes, 60 ms apart (a fast typist), with the run loop turning between them.
        __block CFAbsoluteTime longest = 0, total = 0, lastBeat = CFAbsoluteTimeGetCurrent(), longestPause = 0;
        NSTimer *beat = [NSTimer timerWithTimeInterval:0.002 repeats:YES block:^(NSTimer *t) {
            CFAbsoluteTime now = CFAbsoluteTimeGetCurrent(); longestPause = MAX(longestPause, now - lastBeat); lastBeat = now; }];
        [NSRunLoop.currentRunLoop addTimer:beat forMode:NSRunLoopCommonModes];
        for (int i = 0; i < 200; i++) {
            CFAbsoluteTime a = CFAbsoluteTimeGetCurrent();
            [doc->textView1 insertText:(i % 7 == 6 ? @"あ" : @"a") replacementRange:doc->textView1.selectedRange];
            CFAbsoluteTime t = CFAbsoluteTimeGetCurrent() - a; total += t; longest = MAX(longest, t);
            lastBeat = CFAbsoluteTimeGetCurrent();
            [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.06]];
        }
        CFAbsoluteTime stop = CFAbsoluteTimeGetCurrent();
        WaitForCount(doc.sourceStatusBar);
        CFAbsoluteTime settled = CFAbsoluteTimeGetCurrent() - stop;
        [beat invalidate];
        printf("PERF %s bar: %lu UTF-16 units, keystroke mean %.2f ms, longest %.2f ms; longest main-thread pause %.1f ms%s\n",
               withBar.boolValue ? "with" : "without", (unsigned long)doc->_textStorage.length, total / 200 * 1000, longest * 1000, longestPause * 1000,
               withBar.boolValue ? [[NSString stringWithFormat:@"; numbers %.0f ms after the last keystroke", settled * 1000] UTF8String] : "");
        if (withBar.boolValue) {
            TSStatusBarCounts c = doc.sourceStatusBar.counts;
            Check(c.characters != NSNotFound && c.words != NSNotFound && c.lines != NSNotFound, @"the 5 MB document is counted after typing stops");
            Check(longestPause < 0.1, [NSString stringWithFormat:@"the main thread never waits for the count (longest pause %.1f ms)", longestPause * 1000]);
        }
    }
}

int main(int argc, char **argv) { @autoreleasepool {
    TSInstallAppKitIsolation();
    [NSApplication sharedApplication];
    toolbarDelegate = [GlassToolbar new];
    for (NSString *name in @[@"TSConsoleWindow", @"TSFullscreenWindow", @"TSHTMLWindow", @"TSLogWindow", @"TSPreviewWindow"]) Register(name, NSWindow.class);
    Register(@"MyPDFView", NSView.class); Register(@"MyPDFKitView", PDFView.class); Register(@"ScrapPDFKitView", PDFView.class);
    Register(@"TSTextView", NSTextView.class); Register(@"ScrapTextView", NSTextView.class); Register(@"TSAdvancedFindTextView", NSTextView.class);
    nibData = [NSData dataWithContentsOfFile:@(argv[1])];
    NSString *lang = @(argv[2]);
    NSDictionary *spec = [NSJSONSerialization JSONObjectWithData:[@(argv[3]) dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil];
    NSArray *labels = spec[@"labels"]; NSString *format = spec[@"format"];
    images = getenv("IMAGES") ? @(getenv("IMAGES")) : nil;
    BOOL pictures = images && ([lang isEqual:@"Base"] || [lang isEqual:@"ja"]);
    NSString *tag = [NSString stringWithFormat:@" (%@)", lang];
    if (getenv("PERF")) { Perf(); if (failures) return 1; printf("PASS: %d checks\n", checks); return 0; }

    // Shown by default, before anything is stored.
    Check(TSSourceStatusBar.shown && [NSUserDefaults.standardUserDefaults objectForKey:@"ShowStatusBar"] == nil, @"the bars are shown by default");

    // The agreed picture: "あああAあ" with the insertion point at the end.
    TSDocument *doc = Open(spec[@"text"]);
    TSSourceStatusBar *bar = doc.sourceStatusBar;
    Check(bar != nil, [@"the document makes its status bar" stringByAppendingString:tag]);
    CheckPlaced(doc, [@"the source window" stringByAppendingString:tag]);
    Select(doc, doc->textView1, NSMakeRange(5, 0));
    NSArray *w = spec[@"words"];
    NSArray *expect = @[Item(labels, format, 0, @"1"), Item(labels, format, 1, @"5"), Item(labels, format, 2, [w[0] stringValue]),
                        Item(labels, format, 3, @"5"), Item(labels, format, 4, @"1"), Item(labels, format, 5, @"5")];
    Check([bar.allItems isEqual:expect], [NSString stringWithFormat:@"no selection: no parentheses (%@)%@", [bar.allItems componentsJoinedByString:@" | "], tag]);
    Check(bar.fileSize == nil && bar.visibleFileSize == nil, [@"an unsaved document shows no file size" stringByAppendingString:tag]);
    Select(doc, doc->textView1, NSMakeRange(0, 3));
    expect = @[Item(labels, format, 0, @"1 (1)"), Item(labels, format, 1, @"5 (3)"),
               Item(labels, format, 2, [w[1] integerValue] ? [NSString stringWithFormat:@"%@ (%@)", w[0], w[1]] : [w[0] stringValue]),
               Item(labels, format, 3, @"0"), Item(labels, format, 4, @"1"), Item(labels, format, 5, @"0")];
    Check([bar.allItems isEqual:expect], [NSString stringWithFormat:@"a selection: the numbers in it in parentheses (%@)%@", [bar.allItems componentsJoinedByString:@" | "], tag]);

    // A saved document: the size of its file, as Finder writes it.
    NSString *file = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"status-bar-%d.tex", getpid()]];
    [[@"" stringByPaddingToLength:792 withString:@"x" startingAtIndex:0] writeToFile:file atomically:YES encoding:NSUTF8StringEncoding error:nil];
    doc.fileURL = [NSURL fileURLWithPath:file];
    [doc setFileModificationDate:[NSDate date]];
    NSString *size = [NSByteCountFormatter stringFromByteCount:792 countStyle:NSByteCountFormatterCountStyleFile];
    Check([bar.fileSize isEqual:@792] && [bar.visibleFileSize isEqual:size] && [size containsString:@"792"]
          && ([spec[@"bytes"] length] == 0 || [size isEqual:spec[@"bytes"]]),
          [NSString stringWithFormat:@"a saved document shows the size of its file (%@, %@)%@", bar.visibleFileSize, spec[@"bytes"], tag]);
    [@"x" writeToFile:file atomically:YES encoding:NSUTF8StringEncoding error:nil];
    [doc setFileModificationDate:[NSDate date]];
    Check([bar.fileSize isEqual:@1], [@"saving again reads the size again" stringByAppendingString:tag]);
    [NSFileManager.defaultManager removeItemAtPath:file error:nil];

    // A longer text: every item and the file size fit the source window as the nib makes it.
    TSDocument *wide = Open(Sample());
    wide.fileURL = [NSURL fileURLWithPath:@(argv[1])];
    [wide setFileModificationDate:[NSDate date]];
    Select(wide, wide->textView1, NSMakeRange(40, 300));
    CheckFits(wide.sourceStatusBar, [@"the source window with a selection" stringByAppendingString:tag], NO);
    TSStatusBarCounts c = wide.sourceStatusBar.counts;
    Check(c.lines == 63 && c.selectedCharacters > 0 && c.line == 2, [NSString stringWithFormat:@"the numbers of the longer text (%lu lines, line %lu)%@", c.lines, c.line, tag]);
    if (pictures) Save(wide->textWindow, [NSString stringWithFormat:@"%@-01-source-selection", lang]);
    Select(wide, wide->textView1, NSMakeRange(40, 0));
    CheckFits(wide.sourceStatusBar, [@"the source window without a selection" stringByAppendingString:tag], NO);
    // The width from which every item, the Text Statistics button and the file size fit.
    NSRect nibFrame = wide->textWindow.frame;
    CGFloat least = 0;
    for (CGFloat width = 1000; width >= 300; width -= 10) {
        [wide->textWindow setFrame:NSMakeRect(NSMinX(nibFrame), NSMinY(nibFrame), width, NSHeight(nibFrame)) display:NO];
        if (wide.sourceStatusBar.visibleItems.count == 6 && wide.sourceStatusBar.statisticsButton && wide.sourceStatusBar.visibleFileSize) least = width; else break;
    }
    printf("WIDTH: %s: every item, the button and the file size fit from %.0f points of window width (the nib's window is %.0f)\n",
           lang.UTF8String, least, NSWidth(nibFrame));
    Check(least > 0 && least <= 780, [NSString stringWithFormat:@"every item fits a source window of 780 points (from %.0f)%@", least, tag]);
    [wide->textWindow setFrame:NSMakeRect(NSMinX(nibFrame), NSMinY(nibFrame), 780, NSHeight(nibFrame)) display:NO];
    CheckFits(wide.sourceStatusBar, [@"a source window of 780 points" stringByAppendingString:tag], YES);
    [wide->textWindow setFrame:nibFrame display:NO];
    if (images) Save(wide->textWindow, [NSString stringWithFormat:@"%@-02-source", lang]);

    // A narrow window: the items that do not fit are left out whole, from the end; the tool tip lists them all.
    NSRect wideFrame = wide->textWindow.frame;
    [wide->textWindow setFrame:NSMakeRect(NSMinX(wideFrame), NSMinY(wideFrame), 330, NSHeight(wideFrame)) display:NO];
    Settle(wide->textWindow);
    Check(wide.sourceStatusBar.visibleItems.count < 6, [@"a narrow window leaves items out" stringByAppendingString:tag]);
    CheckFits(wide.sourceStatusBar, [@"a narrow source window" stringByAppendingString:tag], NO);
    [wide->textWindow setFrame:wideFrame display:NO];
    Settle(wide->textWindow);
    CheckFits(wide.sourceStatusBar, [@"the source window at its width again" stringByAppendingString:tag], NO);

    // A split source: the bar under both parts, the numbers following the part typed in.
    [wide splitWindow:nil]; Settle(wide->textWindow);
    CheckPlaced(wide, [@"a split source" stringByAppendingString:tag]);
    Check(NSMinY(InWindow(wide->scrollView2)) >= NSMaxY(InWindow(wide.sourceStatusBar)) - 0.5, [@"the lower part ends above the bar" stringByAppendingString:tag]);
    Select(wide, wide->textView2, NSMakeRange(wide->_textStorage.length - 5, 0));
    Check(wide.sourceStatusBar.counts.line == 63, [NSString stringWithFormat:@"the numbers follow the lower part (line %lu)%@", wide.sourceStatusBar.counts.line, tag]);
    Select(wide, wide->textView1, NSMakeRange(0, 0));
    Check(wide.sourceStatusBar.counts.line == 1, [@"and the upper part again" stringByAppendingString:tag]);
    if (pictures) Save(wide->textWindow, [NSString stringWithFormat:@"%@-03-source-split", lang]);
    [wide splitWindow:nil];

    // The window that shows both: the bar under the source side, on either side.
    for (NSNumber *interchange in @[@NO, @YES]) {
        TSDocument *both = Open(Sample());
        both.fileURL = [NSURL fileURLWithPath:@(argv[1])];
        [both setFileModificationDate:[NSDate date]];
        [both moveSourceToSides:interchange.boolValue];
        NSView *pdf = both.myPDFKitView.superview; [pdf removeFromSuperview];
        NSView *other = interchange.boolValue ? both->leftView : both->rightView; [other addSubview:pdf]; pdf.frame = other.bounds;
        [both->fullSplitWindow setFrame:NSMakeRect(40, 40, 1600, 700) display:NO];
        both->useFullSplitWindow = YES;
        Settle(both->fullSplitWindow);
        NSString *where = [NSString stringWithFormat:@"the window that shows both, source on the %@%@", interchange.boolValue ? @"right" : @"left", tag];
        CheckPlaced(both, where);
        Select(both, both->textView1, NSMakeRange(40, 0));
        CheckFits(both.sourceStatusBar, where, YES);
        if (pictures && !interchange.boolValue) {
            Select(both, both->textView1, NSMakeRange(40, 120));
            Save(both->fullSplitWindow, [NSString stringWithFormat:@"%@-04-one-window", lang]);
            [both splitWindow:nil]; Settle(both->fullSplitWindow);
            CheckPlaced(both, [@"a split source in the window that shows both" stringByAppendingString:tag]);
            Save(both->fullSplitWindow, [NSString stringWithFormat:@"%@-05-one-window-split", lang]);
            [both splitWindow:nil];
        }
        [both separateWindows];
        Settle(both->textWindow);
        CheckPlaced(both, [@"back in the source window" stringByAppendingString:tag]);
    }

    // Source > Show Status Bar: every open document at once, kept in the defaults, the item checked while shown.
    TSAppDelegateProbe *app = [TSAppDelegateProbe new];
    NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:@"Show Status Bar" action:@selector(toggleStatusBar:) keyEquivalent:@""];
    Check([app validateMenuItem:item] && item.state == NSControlStateValueOn, [@"the item is checked while the bars are shown" stringByAppendingString:tag]);
    [app toggleStatusBar:item];
    Check(![NSUserDefaults.standardUserDefaults boolForKey:@"ShowStatusBar"] && [NSUserDefaults.standardUserDefaults objectForKey:@"ShowStatusBar"] != nil,
          [@"hiding is kept in the defaults" stringByAppendingString:tag]);
    for (TSDocument *d in @[doc, wide]) {
        NSView *parent = d->splitView.superview;
        Check(d.sourceStatusBar.superview == nil && NSEqualRects(d->splitView.frame, parent.bounds), [@"hiding takes every open bar away, the source fills the window" stringByAppendingString:tag]);
    }
    Check([app validateMenuItem:item] && item.state == NSControlStateValueOff, [@"the item is unchecked while the bars are hidden" stringByAppendingString:tag]);
    TSDocument *later = Open(@"later");
    Check(later.sourceStatusBar.superview == nil, [@"a document opened while hidden has no bar" stringByAppendingString:tag]);
    [doc->_textStorage replaceCharactersInRange:NSMakeRange(0, 0) withString:@"x"];
    Check(!doc.sourceStatusBar.counting, [@"a hidden bar does not count" stringByAppendingString:tag]);
    [app toggleStatusBar:item];
    Check([NSUserDefaults.standardUserDefaults boolForKey:@"ShowStatusBar"] && item.state == NSControlStateValueOff && [app validateMenuItem:item] && item.state == NSControlStateValueOn,
          [@"showing again is kept, and the item is checked again" stringByAppendingString:tag]);
    for (TSDocument *d in @[doc, wide, later]) CheckPlaced(d, [@"showing again puts every bar back" stringByAppendingString:tag]);
    WaitForCount(doc.sourceStatusBar);
    Check(doc.sourceStatusBar.counts.characters == 6, [@"a bar shown again counts what was typed while hidden" stringByAppendingString:tag]);

    if (failures) return 1;
    printf("PASS: %d checks%s\n", checks, tag.UTF8String);
} return 0; }
'''
    program = (program.replace('INSTALL', fragments['install']).replace('MOVE', fragments['move']).replace('SEPARATE', fragments['separate'])
               .replace('SPLITMETHOD', fragments['split']).replace('SETTEXTMETHOD', fragments['settext'])
               .replace('FILEDATEMETHOD', fragments['filedate'].replace('[super setFileModificationDate:date];', ''))
               .replace('TOGGLEMETHOD', fragments['toggle']).replace('VALIDATEMETHOD', fragments['validate']))
    if not args.mutation:
        checked = [(k, document if k not in ('toggle', 'validate') else text['TSAppDelegate.m'], v) for k, v in originals.items() if k != 'filedate']
        verify_embedded(program, checked)
    (tmp / 'probe.m').write_text(program, encoding='utf-8', errors='surrogateescape')
    subprocess.run(['xcrun', 'clang', '-fobjc-arc', '-w', '-framework', 'Cocoa', '-framework', 'Quartz', '-I', str(tmp), *include_args(root),
                    '-I', str(root / 'Tests'), str(tmp / 'probe.m'), str(tmp / 'TSSourceStatusBar.m'), str(tmp / 'TSStatusBarCounting.m'),
                    str(tmp / 'TSDocumentWindowGlass.m'), '-o', str(tmp / 'probe')], check=True)
    for lang in LANGUAGES:
        folder = 'en' if lang == 'Base' else lang
        (tmp / f'{folder}.lproj').mkdir(exist_ok=True)
        (tmp / f'{folder}.lproj/Localizable.strings').write_bytes((root / f'Resources/Interfaces/{folder}.lproj/Localizable.strings').read_bytes())
    env = dict(os.environ)
    if args.images:
        args.images.mkdir(parents=True, exist_ok=True)
        env['IMAGES'] = str(args.images.resolve())
    words = run('oracle', {'cases': [{'s': 'あああAあ', 'loc': 0, 'len': 3}]})[0]
    bytes_text = {'Base': '792 bytes', 'ja': '792 バイト'}
    langs = ['Base'] if args.perf else LANGUAGES
    for lang in langs:
        folder = 'en' if lang == 'Base' else lang
        nib = next((root / f'Resources/Interfaces/{lang}.lproj/TSDocument.nib').glob('keyedobjects*.nib'))
        spec = {'labels': STRINGS[lang][:6], 'format': STRINGS[lang][6], 'text': 'あああAあ', 'words': [words[2], words[5]]}
        # The size as Foundation writes it in that language: Base and Japanese are checked against the agreed text.
        spec['bytes'] = bytes_text.get(lang, '')
        command = [str(tmp / 'probe'), str(nib), lang, json.dumps(spec, ensure_ascii=False), '-AppleLanguages', f'({folder})', '-AppleLocale', LOCALES[lang]]
        e = dict(env)
        if args.perf:
            e['PERF'] = '1'
        result = subprocess.run(command, capture_output=True, text=True, timeout=900, env=e)
        print(result.stdout.strip())
        if result.returncode:
            fail(f'the bar in the {lang} windows')
            print(result.stderr[-2000:])

if args.mutation:
    if not failures:
        sys.exit(f'FAIL: mutation {args.mutation} was not detected')
    print(f'PASS: detected mutation {args.mutation}')
elif failures:
    sys.exit(f'FAIL: {len(failures)}')
else:
    print('PASS: the status bar under the source')
