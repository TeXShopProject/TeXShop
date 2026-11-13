#!/usr/bin/env python3
"""Check the tool tips of the five mouse tools in the preview toolbars with production toolbar code.

The Mouse Mode item of the Preview window and of the single window shows one tool tip
per tool (Scroll, Select Text, Magnify, Magnify (Large), Select PDF), translated in
every language, and the item itself has no tool tip over them. Tags and the command
are unchanged. Nothing is shown on screen and no user settings are read.
"""
import argparse, os, plistlib, shutil, subprocess, sys, tempfile
from pathlib import Path
from production_fragments import method as production_method, verify_embedded
from source_tree import include_args

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--mutation', choices=['no-segment-tips', 'keep-item-tip', 'same-key', 'untranslated'])
args = parser.parse_args()
root = Path(__file__).resolve().parents[1]
toolbar = (root/'Sources/Windows/TSToolbarController.m').read_text()

fragments = []
def method(signature):
    fragment = production_method(toolbar, signature)
    fragments.append(('complete method:'+signature, toolbar, fragment))
    return fragment
def span(first, last):
    start = toolbar.index(first); end = toolbar.index(last, start) + len(last)
    fragment = toolbar[start:end]
    fragments.append(('statements:'+first, toolbar, fragment))
    return fragment

constants = span('static NSString* \tkSourceToolbarIdentifier', 'kHtmlSearchTID              = @"HtmlSearch";')
signatures = ['- (NSToolbarItem*) makeToolbarItemWithItemIdentifier:(NSString*)itemIdent key:(NSString*)itemKey\n{',
              '- (NSToolbarItem*) makeToolbarItemWithItemIdentifier:(NSString*)itemIdent key:(NSString*)itemKey customView:(id)customView',
              '- (NSToolbarItem*) makeMouseModeItemWithItemIdentifier:']
methods = '\n'.join(method(s) for s in signatures)

# Both preview toolbars build their Mouse Mode item with the helper compiled below.
item_for = production_method(toolbar, '- (NSToolbarItem *) toolbar: (NSToolbar *)toolbar itemForItemIdentifier:')
for ident, outlet in (('kMouseModeKKTID', 'mouseModeMatrixKK'), ('skMouseModeTID', 'mouseModeMatrixFull')):
    call = f'myToolbarItem = [self makeMouseModeItemWithItemIdentifier: {ident} key:{ident}\n                                                           customView: {outlet}];'
    assert item_for.count(call) == 1, 'itemForItemIdentifier builds the Mouse Mode item with the helper: '+ident
assert item_for.count('makeMouseModeItemWithItemIdentifier') == 2

if args.mutation == 'no-segment-tips':
    old = '                [mySegmentedControl setToolTip: NSLocalizedStringFromTable(toolTipKeys[segment], @"ToolbarItems", nil)\n                                    forSegment: segment];'
    assert methods.count(old) == 1
    methods = methods.replace(old, '                ;')
elif args.mutation == 'keep-item-tip':
    old = '            theToolbarItem.toolTip = nil;'
    assert methods.count(old) == 1
    methods = methods.replace(old, '')
elif args.mutation == 'same-key':
    old = 'NSLocalizedStringFromTable(toolTipKeys[segment], @"ToolbarItems", nil)'
    assert methods.count(old) == 1
    methods = methods.replace(old, 'NSLocalizedStringFromTable(toolTipKeys[0], @"ToolbarItems", nil)')

program = r'''
#import <Cocoa/Cocoa.h>
#import "TestAppKitIsolation.h"
#import "TSPreviewLayout.h"
#import "TSPreviewAppearance.h"
#define MITSU_PDF 1
static BOOL atLeastMonterey = YES;
CONSTANTS
@interface TSDocument : NSObject <NSToolbarDelegate>
@property NSInteger mode;
@end
@implementation TSDocument
- (void)changeMouseMode:(id)sender { self.mode = [sender selectedTag]; }
METHODS
@end
static void Check(BOOL ok, NSString *message) { if (!ok) { NSLog(@"FAIL: %@", message); exit(1); } }
static NSString *Localized(NSString *key) { return [NSBundle.mainBundle localizedStringForKey:key value:@"MISSING" table:@"ToolbarItems"]; }
int main(int argc, char **argv) { @autoreleasepool {
 TSInstallAppKitIsolation(); [NSApplication sharedApplication];
 NSString *language = @(argv[1]);
 Check([NSBundle.mainBundle.preferredLocalizations.firstObject isEqual:language], @"Requested localization");
 Check([NSBundle.mainBundle.bundleIdentifier hasPrefix:@"org.texshop.MouseModeTipTest."], @"Isolated test bundle");
 NSArray *keys = @[@"tiToolTipMouseModeScroll", @"tiToolTipMouseModeSelectText", @"tiToolTipMouseModeMagnify",
                   @"tiToolTipMouseModeMagnifyLarge", @"tiToolTipMouseModeSelectPDF"];
 NSArray *expected = EXPECTED_TEXT[language], *english = EXPECTED_TEXT[@"en"];
 Check(expected.count == 5 && english.count == 5, @"Expected text listed");
 TSDocument *d = [TSDocument new];
 for (NSString *ident in @[kMouseModeKKTID, skMouseModeTID]) {
  NSToolbarItem *item = [d makeMouseModeItemWithItemIdentifier:ident key:ident customView:nil];
  NSString *where = [NSString stringWithFormat:@"%@ %@", language, ident];
  Check([item.view isKindOfClass:NSSegmentedControl.class], [@"Segmented control: " stringByAppendingString:where]);
  NSSegmentedControl *control = (NSSegmentedControl *)item.view;
  Check(control.segmentCount == 5, [@"Five tools: " stringByAppendingString:where]);
  Check(item.toolTip.length == 0 && control.toolTip.length == 0, [NSString stringWithFormat:@"No tool tip over the tools: %@ (%@ / %@)", where, item.toolTip, control.toolTip]);
  Check([item.label isEqual:Localized([@"tiLabel" stringByAppendingString:ident])] && [item.paletteLabel isEqual:Localized([@"tiPaletteLabel" stringByAppendingString:ident])], [@"Label and palette label: " stringByAppendingString:where]);
  NSMutableSet *seen = [NSMutableSet set];
  for (NSInteger segment = 0; segment < 5; segment++) {
   NSString *tip = [control toolTipForSegment:segment];
   NSString *at = [NSString stringWithFormat:@"%@ segment %ld: %@", where, (long)segment, tip];
   Check(tip.length > 0 && ![tip isEqual:@"MISSING"] && ![tip hasPrefix:@"tiToolTip"], [@"Tool tip present: " stringByAppendingString:at]);
   Check([tip isEqual:Localized(keys[segment])], [@"Tool tip from its own key: " stringByAppendingString:at]);
   Check([tip isEqual:expected[segment]], [NSString stringWithFormat:@"Exact text: %@ (expected %@)", at, expected[segment]]);
   if (![language isEqual:@"en"]) Check(![tip isEqual:english[segment]], [@"Translated: " stringByAppendingString:at]);
   [seen addObject:tip];
   Check([control tagForSegment:segment] == segment + 1, [@"Tag unchanged: " stringByAppendingString:at]);
   Check(control.target == d && control.action == @selector(changeMouseMode:), [@"Command unchanged: " stringByAppendingString:at]);
  }
  Check(seen.count == 5, [@"Five different tool tips: " stringByAppendingString:where]);
 }
 NSLog(@"%@ PASS: five translated tool tips, one per mouse tool, in both preview toolbars", language);
}}
'''
# Each tool tip starts with the tool's name as the toolbar item's Mouse Mode menu shows it.
expected = {
 'en': ['Scroll: drag to move the document',
        'Select Text: drag to select text for copying',
        'Magnify: press and hold to look through a small magnifying glass',
        'Magnify (Large): press and hold to look through a large magnifying glass',
        'Select PDF: drag to select an area for copying as a graphic'],
 'de': ['Verschieben: Dokument durch Ziehen bewegen',
        'Textauswahl: Text zum Kopieren durch Ziehen auswählen',
        'Lupe: Gedrückt halten, um durch eine kleine Lupe zu sehen',
        'Lupe (groß): Gedrückt halten, um durch eine große Lupe zu sehen',
        'PDF-Auswahl: Bereich zum Kopieren als Grafik durch Ziehen auswählen'],
 'es': ['Desplazar: arrastrar para mover el documento',
        'Seleccionar texto: arrastrar para seleccionar texto y copiarlo',
        'Aumentar: mantener pulsado para ver a través de una lupa pequeña',
        'Aumentar (Grande): mantener pulsado para ver a través de una lupa grande',
        'Seleccionar PDF: arrastrar para seleccionar un área y copiarla como imagen'],
 'fr': ['Dérouler : faire glisser pour déplacer le document',
        'Sélectionner le texte : faire glisser pour sélectionner du texte à copier',
        'Agrandir : maintenir enfoncé pour regarder à travers une petite loupe',
        'Agrandissement maximal : maintenir enfoncé pour regarder à travers une grande loupe',
        'Sélectionner (PDF) : faire glisser pour sélectionner une zone à copier comme image'],
 'it': ['Scorrimento: trascina per spostare il documento',
        'Selezione testo: trascina per selezionare il testo da copiare',
        'Ingrandimento: tieni premuto per guardare attraverso una lente piccola',
        'Ingrandimento (maggiore): tieni premuto per guardare attraverso una lente grande',
        "Selezione PDF: trascina per selezionare un'area da copiare come immagine"],
 'ja': ['スクロール：ドラッグして書類を動かします',
        'テキスト選択：ドラッグしてコピーするテキストを選択します',
        '拡大鏡：押したままにすると小さい拡大鏡で拡大します',
        '拡大鏡（大）：押したままにすると大きい拡大鏡で拡大します',
        '範囲選択：ドラッグして画像としてコピーする範囲を選択します'],
 'ko': ['스크롤: 드래그하여 문서 이동',
        '텍스트 선택: 드래그하여 복사할 텍스트 선택',
        '확대경: 누르고 있는 동안 작은 확대경으로 보기',
        '확대경 (크게): 누르고 있는 동안 큰 확대경으로 보기',
        '범위 선택: 드래그하여 이미지로 복사할 영역 선택'],
 'nl': ['Scrollen: sleep om het document te verplaatsen',
        'Tekst selecteren: sleep om tekst te selecteren om te kopiëren',
        'Vergroten: houd ingedrukt om door een kleine loep te kijken',
        'Vergroten (groter): houd ingedrukt om door een grote loep te kijken',
        'PDF selecteren: sleep om een gebied te selecteren om als afbeelding te kopiëren'],
 'pt-PT': ['Deslocar: arrastar para mover o documento',
        'Selecionar texto: arrastar para selecionar texto a copiar',
        'Ampliar: manter premido para ver através de uma lupa pequena',
        'Ampliar mais: manter premido para ver através de uma lupa grande',
        'Selecionar PDF: arrastar para selecionar uma área a copiar como imagem'],
 'pt': ['Rolar: arrastar para mover o documento',
        'Selecionar texto: arrastar para selecionar texto para copiar',
        'Ampliar: manter pressionado para ver através de uma lupa pequena',
        'Ampliar (grande): manter pressionado para ver através de uma lupa grande',
        'Selecionar PDF: arrastar para selecionar uma área para copiar como imagem'],
 'ro': ['Derulare: trageți pentru a muta documentul',
        'Selectează textul: trageți pentru a selecta textul de copiat',
        'Lupă: țineți apăsat pentru a privi printr-o lupă mică',
        'Lupă (mare): țineți apăsat pentru a privi printr-o lupă mare',
        'Selectează PDF: trageți pentru a selecta o zonă de copiat ca imagine'],
 'zh_CN': ['滚动：拖移以移动文稿',
        '选择文本：拖移以选择要拷贝的文本',
        '放大镜：按住以通过小放大镜查看',
        '放大镜 (大号)：按住以通过大放大镜查看',
        '选择PDF：拖移以选择要作为图像拷贝的区域'],
}
objc = lambda text: '@"' + text.replace('\\', '\\\\').replace('"', '\\"') + '"'
table = '@{' + ', '.join('@"%s": @[%s]' % (language, ', '.join(map(objc, items))) for language, items in expected.items()) + '}'
languages = sorted(p.parent.stem for p in (root/'Resources/Interfaces').glob('*.lproj/ToolbarItems.strings'))
assert len(languages) == 12 and set(expected) == set(languages), languages
program = program.replace('CONSTANTS', constants).replace('METHODS', methods).replace('EXPECTED_TEXT', table)
if not args.mutation:
    verify_embedded(program, fragments)
with tempfile.TemporaryDirectory(prefix='TeXShop-mouse-mode-tips-') as tmp:
    tmp = Path(tmp)
    app = tmp/'MouseModeTipTest.app'; mac = app/'Contents/MacOS'; mac.mkdir(parents=True)
    (app/'Contents/Info.plist').write_bytes(plistlib.dumps({'CFBundleIdentifier': 'org.texshop.MouseModeTipTest.'+tmp.name,
        'CFBundleExecutable': 'MouseModeTipTest', 'CFBundlePackageType': 'APPL', 'LSUIElement': True, 'CFBundleDevelopmentRegion': 'en'}))
    for language in languages:
        res = app/f'Contents/Resources/{language}.lproj'; res.mkdir(parents=True)
        source = root/f'Resources/Interfaces/{language}.lproj/ToolbarItems.strings'
        if args.mutation == 'untranslated' and language == 'ja':
            source = root/'Resources/Interfaces/en.lproj/ToolbarItems.strings'
        shutil.copy(source, res/'ToolbarItems.strings')
    source = tmp/'Test.m'; source.write_text(program)
    subprocess.run(['xcrun', 'clang', '-fobjc-arc', '-fmodules', '-w', *include_args(root), '-I'+str(root/'Tests'),
                    '-framework', 'Cocoa', str(source), '-o', str(mac/'MouseModeTipTest')], check=True)
    home = tmp/'Home'; (home/'Library/Preferences').mkdir(parents=True)
    try:
        for language in languages:
            result = subprocess.run([str(mac/'MouseModeTipTest'), language, '-AppleLanguages', f'({language})'],
                                    env={**os.environ, 'CFFIXED_USER_HOME': str(home)}, capture_output=True, text=True)
            sys.stderr.write(result.stderr)
            if result.returncode:
                sys.exit(result.returncode)
    finally:
        subprocess.run(['/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister', '-u', str(app)],
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
