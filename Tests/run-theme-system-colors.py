#!/usr/bin/env python3
"""The cursor and selection of a theme, with their "Use system color" switches (TSThemeSystemColor.h).

The production code is compiled as it is: the header, the color readers of TSColorSupport, TSLibraryRepair.m and
TSThemeFileStore.m, and -themeStore and -themeListAcceptsData: of the Settings window. Checked:
- a switch is read as its number (true, false, 1, 0, a real), and as what TeXShop drew before the switches existed
  when it is missing or not a number: the theme's cursor, the system's selection;
- the cursor and selection colors: the system's while the switch is on, the theme's while it is off, the built-in
  selection color (#B3D7FF or #3F638B) for a theme without one;
- a text view given a theme color, then the system's, then another color keeps its other selection attributes;
- a switch of any kind never makes a theme damaged at launch (it would go to the backups), a bad selection color does;
- Settings edits a theme of a title and switches only, but it cannot be exported or imported; a theme with one color,
  the selection color too, can;
- the bundled themes (and the copies kept inside TeXShop) have the switches and the selection colors chosen for them,
  and their text reads on the selection.
- in a split, the part a reverse sync marked keeps its mark through a change of theme and gets the theme's selection
  back, also when the other part is in use by then.
Nothing is shown on screen. --mutations changes key parts of the production code and the test must then fail."""
from pathlib import Path
import plistlib, re, shutil, subprocess, sys, tempfile
from production_fragments import method, verify_embedded
from source_tree import include_args, source_file

root = Path(__file__).resolve().parents[1]
header = source_file(root, 'TSThemeSystemColor.h').read_text(encoding='utf-8')
support = source_file(root, 'TSColorSupport.m').read_text(encoding='utf-8')
signatures = ['- (NSArray *) colorArrayFromDictionary:', '- (NSColor *) colorFromDictionary:', '- (NSColor *)liteColorWithKey:',
              '- (NSColor *)darkColorWithKey:', '- (NSColor *)opaqueColorForKey: (NSString *)theKey fromDictionary:',
              '- (NSColor *)insertionPointColorFromDictionary:', '- (NSColor *)selectionColorFromDictionary:']
readers = [method(support, s) for s in signatures]
settings = source_file(root, 'TSPreferences-Color.m').read_text(encoding='utf-8')
store_method = method(settings, '- (TSThemeFileStore *)themeStore\n{')
accepts_method = method(settings, '- (BOOL)themeListAcceptsData:(NSData *)data\n{')
repair = source_file(root, 'TSLibraryRepair.m').read_text(encoding='utf-8')
# The reverse sync's mark of the selection, and the selection colors a document gives its views.
color_source = source_file(root, 'TSDocument-Color.m').read_text(encoding='latin1')
document_source = source_file(root, 'TSDocument.m').read_text(encoding='latin1')
apply_method = method(color_source, '- (void) applySourceSelectionColorToTextView: (NSTextView *)aTextView\n{')
end_method = method(color_source, '- (void) endReverseSyncSelection\n{')
loop_start = color_source.index('    // The selection; a view the reverse sync has marked')
loop_end = color_source.index('    }\n', loop_start) + len('    }\n')
selection_loop = color_source[loop_start:loop_end]
yellow_methods = method(document_source, '- (BOOL) textSelectionYellow\n{') + '\n' + method(document_source, '- (void) setTextSelectionYellow:(BOOL)value\n{')

PROGRAM = r'''
#import <Cocoa/Cocoa.h>
#import "TSThemeSystemColor.h"
#import "TSThemeFileStore.h"
#import "TSLibraryRepair.h"
#define REQUIRE(...) do { if (!(__VA_ARGS__)) { fprintf(stderr, "FAIL line %d: %s\n", __LINE__, #__VA_ARGS__); exit(1); } } while (0)
NSString *ColorPath;
@interface TSColorSupport : NSObject
+ (instancetype)sharedInstance;
- (NSColor *)opaqueColorForKey:(NSString *)theKey fromDictionary:(NSDictionary *)theDictionary isWindowDark:(BOOL)mode;
- (NSColor *)colorFromDictionary:(NSDictionary *)theDictionary andKey:(NSString *)theKey;
- (NSArray *)colorArrayFromDictionary:(NSDictionary *)theDictionary andKey:(NSString *)theKey;
- (NSColor *)liteColorWithKey:(NSString *)theKey;
- (NSColor *)darkColorWithKey:(NSString *)theKey;
- (NSColor *)insertionPointColorFromDictionary:(NSDictionary *)theDictionary isWindowDark:(BOOL)mode;
- (NSColor *)selectionColorFromDictionary:(NSDictionary *)theDictionary isWindowDark:(BOOL)mode;
@end
@implementation TSColorSupport
+ (instancetype)sharedInstance { static id shared; if (!shared) shared = [self new]; return shared; }
__READERS__
@end
// -themeStore and -themeListAcceptsData: of the Settings window.
@interface Settings : NSObject
@end
@implementation Settings
__STORE__
__ACCEPTS__
@end

// A document with the production marks of the reverse sync and the selection colors it gives its two views.
@interface Document : NSObject {
@public
    BOOL textSelectionYellow;
    NSTextView *textView, *textView1, *textView2;
}
@property (weak, readonly) NSTextView *reverseSyncTextView;
@property (strong) NSColor *sourceSelectionColor;
@end
@implementation Document
- (id)textView { return textView; }
__YELLOW__
__APPLY__
__END__
- (void)applyColors:(NSDictionary *)colorDictionary dark:(BOOL)withDarkColors
{
__LOOP__
}
@end

static BOOL SameRGB(NSColor *a, NSColor *b)
{
    NSColor *x = [a colorUsingColorSpace:NSColorSpace.sRGBColorSpace], *y = [b colorUsingColorSpace:NSColorSpace.sRGBColorSpace];
    return x && y && fabs(x.redComponent - y.redComponent) < 2e-3 && fabs(x.greenComponent - y.greenComponent) < 2e-3 && fabs(x.blueComponent - y.blueComponent) < 2e-3;
}
static NSColor *Hex(unsigned v) { return [NSColor colorWithSRGBRed:((v >> 16) & 255) / 255.0 green:((v >> 8) & 255) / 255.0 blue:(v & 255) / 255.0 alpha:1]; }
static NSData *Plist(NSDictionary *d) { return [NSPropertyListSerialization dataWithPropertyList:d format:NSPropertyListXMLFormat_v1_0 options:0 error:NULL]; }

int main(int argc, char **argv) { @autoreleasepool {
    NSString *themes = @(argv[1]);
    TSColorSupport *colors = [TSColorSupport new];
    NSArray *red = @[@1, @0, @0, @1], *green = @[@0, @1, @0, @1];
    NSString *cursorSwitch = TSThemeInsertionPointUsesSystemColorKey, *selectionSwitch = TSThemeSelectionUsesSystemColorKey;

    // The switches as they are read.
    NSArray *notNumbers = @[@"YES", @"true", @[], @[@1, @1, @1, @1], @{}, NSDate.date, [NSData data]];
    for (NSString *key in @[cursorSwitch, selectionSwitch]) {
        BOOL before = [key isEqualToString:selectionSwitch];
        REQUIRE(TSThemeUsesSystemColor(@{}, key) == before);
        REQUIRE(TSThemeUsesSystemColor(nil, key) == before);
        REQUIRE(TSThemeUsesSystemColor((NSDictionary *)@[], key) == before);
        for (id value in notNumbers) REQUIRE(TSThemeUsesSystemColor(@{key: value}, key) == before);
        REQUIRE(TSThemeUsesSystemColor(@{key: @YES}, key) && !TSThemeUsesSystemColor(@{key: @NO}, key));
        REQUIRE(TSThemeUsesSystemColor(@{key: @1}, key) && !TSThemeUsesSystemColor(@{key: @0}, key));
        REQUIRE(TSThemeUsesSystemColor(@{key: @0.5}, key) && !TSThemeUsesSystemColor(@{key: @0.0}, key));
    }
    REQUIRE(TSThemeIsSystemColorSwitch(cursorSwitch) && TSThemeIsSystemColorSwitch(selectionSwitch));
    REQUIRE(!TSThemeIsSystemColorSwitch(@"EditorInsertionPoint") && !TSThemeIsSystemColorSwitch(TSThemeSelectionKey) && !TSThemeIsSystemColorSwitch(@"Title"));

    // The colors.
    for (int dark = 0; dark < 2; dark++) {
        NSDictionary *theme = @{@"EditorInsertionPoint": red, TSThemeSelectionKey: green};
        REQUIRE(SameRGB([colors insertionPointColorFromDictionary:theme isWindowDark:dark], NSColor.redColor));
        REQUIRE([colors selectionColorFromDictionary:theme isWindowDark:dark] == NSColor.selectedTextBackgroundColor);
        NSMutableDictionary *on = [theme mutableCopy]; on[cursorSwitch] = @YES; on[selectionSwitch] = @YES;
        REQUIRE([colors insertionPointColorFromDictionary:on isWindowDark:dark] == NSColor.textInsertionPointColor);
        REQUIRE([colors selectionColorFromDictionary:on isWindowDark:dark] == NSColor.selectedTextBackgroundColor);
        NSMutableDictionary *off = [theme mutableCopy]; off[cursorSwitch] = @NO; off[selectionSwitch] = @NO;
        REQUIRE(SameRGB([colors insertionPointColorFromDictionary:off isWindowDark:dark], NSColor.redColor));
        REQUIRE(SameRGB([colors selectionColorFromDictionary:off isWindowDark:dark], NSColor.greenColor));
        // The cursor without the switch: the color drawn before (opaqueColorForKey:, as for a theme without a cursor).
        NSDictionary *bare = @{@"EditorText": @[@0, @0, @0, @1], @"EditorBackground": @[@1, @1, @1, @1]};
        REQUIRE([[colors insertionPointColorFromDictionary:bare isWindowDark:dark] isEqual:[colors opaqueColorForKey:@"EditorInsertionPoint" fromDictionary:bare isWindowDark:dark]]);
        // A theme without a selection color, switched off: the built-in one.
        REQUIRE(SameRGB([colors selectionColorFromDictionary:@{selectionSwitch: @NO} isWindowDark:dark], Hex(dark ? 0x3F638B : 0xB3D7FF)));
        // A transparent selection color is drawn opaque.
        NSColor *opaque = [colors selectionColorFromDictionary:@{selectionSwitch: @NO, TSThemeSelectionKey: @[@0, @0, @1, @0]} isWindowDark:dark];
        REQUIRE(SameRGB(opaque, NSColor.blueColor) && opaque.alphaComponent == 1);
    }

    // A view given its selection color each time: the other attributes stay.
    NSTextView *view = [[NSTextView alloc] initWithFrame:NSMakeRect(0, 0, 100, 40)];
    view.selectedTextAttributes = @{NSForegroundColorAttributeName: NSColor.orangeColor, NSBackgroundColorAttributeName: NSColor.yellowColor};
    TSThemeSetSelectionColor(view, NSColor.greenColor);
    REQUIRE([view.selectedTextAttributes[NSBackgroundColorAttributeName] isEqual:NSColor.greenColor]);
    TSThemeSetSelectionColor(view, NSColor.selectedTextBackgroundColor);
    REQUIRE(view.selectedTextAttributes[NSBackgroundColorAttributeName] == NSColor.selectedTextBackgroundColor);
    TSThemeSetSelectionColor(view, nil);
    REQUIRE(view.selectedTextAttributes[NSBackgroundColorAttributeName] == NSColor.selectedTextBackgroundColor);
    TSThemeSetSelectionColor(view, NSColor.purpleColor);
    REQUIRE([view.selectedTextAttributes[NSBackgroundColorAttributeName] isEqual:NSColor.purpleColor]);
    REQUIRE([view.selectedTextAttributes[NSForegroundColorAttributeName] isEqual:NSColor.orangeColor]);
    TSThemeSetSelectionColor(nil, NSColor.purpleColor);

    // The launch check, against the Lite theme that comes with TeXShop.
    NSData *lite = [NSData dataWithContentsOfFile:[themes stringByAppendingPathComponent:@"LiteTheme.plist"]];
    NSDictionary *liteTheme = [NSPropertyListSerialization propertyListWithData:lite options:0 format:NULL error:NULL];
    REQUIRE([liteTheme[cursorSwitch] isEqual:@NO] && [liteTheme[selectionSwitch] isEqual:@YES]);
    TSLibraryFileCheck check = TSLibraryThemeCheck();
    for (NSString *key in @[cursorSwitch, selectionSwitch])
        for (id value in [notNumbers arrayByAddingObjectsFromArray:@[@1, @0, @YES, @2.5, @"", @[@"x"]]]) {
            NSData *own = Plist(@{@"Title": @"Mine", @"EditorText": red, key: value});
            REQUIRE(check(own, lite));
            REQUIRE(check(own, nil));
        }
    REQUIRE(!check(Plist(@{@"Title": @"Mine", TSThemeSelectionKey: @[@1, @0, @0]}), lite));
    REQUIRE(!check(Plist(@{@"Title": @"Mine", TSThemeSelectionKey: @"red"}), lite));
    REQUIRE(!check(Plist(@{@"Title": @"Mine", @"EditorText": @YES}), lite));
    for (NSString *name in [NSFileManager.defaultManager contentsOfDirectoryAtPath:themes error:NULL])
        REQUIRE(check([NSData dataWithContentsOfFile:[themes stringByAppendingPathComponent:name]], lite));

    // Settings: what it edits, and what it exports or imports.
    NSString *folder = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSUUID UUID].UUIDString];
    [NSFileManager.defaultManager createDirectoryAtPath:folder withIntermediateDirectories:YES attributes:nil error:NULL];
    [lite writeToFile:[folder stringByAppendingPathComponent:@"LiteTheme.plist"] atomically:YES];
    ColorPath = folder;
    Settings *window = [Settings new];
    BOOL (^accepts)(NSDictionary *) = [window themeStore].acceptsColors;
    REQUIRE(accepts != nil);
    NSArray *edited = @[@{@"Title": @"T"}, @{@"Title": @"T", cursorSwitch: @YES}, @{@"Title": @"T", cursorSwitch: @YES, selectionSwitch: @NO},
                        @{@"Title": @"T", selectionSwitch: @"no"}, @{@"Title": @"T", @"EditorText": red},
                        @{@"Title": @"T", TSThemeSelectionKey: green}, @{@"Title": @"T", @"EditorText": red, cursorSwitch: @YES}];
    for (NSDictionary *theme in edited) REQUIRE(accepts(theme));
    REQUIRE(!accepts(@{@"Title": @"T", @"Other": @"x"}));
    NSArray *exchanged = @[@{@"Title": @"T", @"EditorText": red}, @{@"Title": @"T", TSThemeSelectionKey: green},
                           @{@"Title": @"T", @"EditorText": red, cursorSwitch: @YES, selectionSwitch: @NO}];
    for (NSDictionary *theme in exchanged) REQUIRE([window themeListAcceptsData:Plist(theme)]);
    NSArray *refused = @[@{@"Title": @"T"}, @{@"Title": @"T", cursorSwitch: @YES}, @{@"Title": @"T", cursorSwitch: @NO, selectionSwitch: @YES},
                         @{}, @{cursorSwitch: @YES}];
    for (NSDictionary *theme in refused) REQUIRE(![window themeListAcceptsData:Plist(theme)]);
    // A title and a switch: saved by Settings (TSThemeFileStore) and read again, then the switch turned off again.
    TSThemeFileStore *store = [window themeStore];
    NSError *error = nil;
    REQUIRE([store addColors:@{@"Title": @"Plain"} title:@"Plain" error:&error] != nil);
    NSDictionary *saved = [store readTitle:@"Plain"];
    REQUIRE(saved != nil);
    NSMutableDictionary *on = [saved mutableCopy]; on[cursorSwitch] = @YES;
    REQUIRE([store writeChangesFrom:saved to:on title:@"Plain" error:&error] != nil);
    NSDictionary *read = [store readTitle:@"Plain"];
    REQUIRE([read[cursorSwitch] isEqual:@YES]);
    NSMutableDictionary *offAgain = [read mutableCopy]; offAgain[cursorSwitch] = @NO;
    REQUIRE([store writeChangesFrom:read to:offAgain title:@"Plain" error:&error] != nil);
    REQUIRE([[store readTitle:@"Plain"][cursorSwitch] isEqual:@NO]);
    [NSFileManager.defaultManager removeItemAtPath:folder error:NULL];
    // The reverse sync in a split: the part it marked keeps its mark through a change of theme, and gets the theme's
    // selection back even when the other part is in use by then; a part that has gone leaves the one in use.
    {
        Document *doc = [Document new];
        NSTextView *one = [[NSTextView alloc] initWithFrame:NSMakeRect(0, 0, 100, 40)], *two = [[NSTextView alloc] initWithFrame:NSMakeRect(0, 0, 100, 40)];
        doc->textView1 = one; doc->textView2 = two; doc->textView = one;
        NSDictionary *greenTheme = @{selectionSwitch: @NO, TSThemeSelectionKey: green}, *redTheme = @{selectionSwitch: @NO, TSThemeSelectionKey: red};
        [doc applyColors:greenTheme dark:NO];
        REQUIRE(SameRGB(one.selectedTextAttributes[NSBackgroundColorAttributeName], NSColor.greenColor) && SameRGB(two.selectedTextAttributes[NSBackgroundColorAttributeName], NSColor.greenColor));
        // The reverse sync marks the part in use (as -[TSDocument(SyncTeX) ...] does).
        [doc setTextSelectionYellow:YES];
        TSThemeSetSelectionColor(doc.textView, NSColor.yellowColor);
        REQUIRE(doc.reverseSyncTextView == one);
        // The other part is clicked: it is now in use.
        doc->textView = two;
        [doc applyColors:redTheme dark:NO];
        REQUIRE([one.selectedTextAttributes[NSBackgroundColorAttributeName] isEqual:NSColor.yellowColor]);
        REQUIRE(SameRGB(two.selectedTextAttributes[NSBackgroundColorAttributeName], NSColor.redColor));
        [doc endReverseSyncSelection];
        REQUIRE(![doc textSelectionYellow] && doc.reverseSyncTextView == nil);
        REQUIRE(SameRGB(one.selectedTextAttributes[NSBackgroundColorAttributeName], NSColor.redColor));
        // The system's selection comes back the same way.
        [doc applyColors:@{} dark:NO];
        [doc setTextSelectionYellow:YES];
        TSThemeSetSelectionColor(two, NSColor.yellowColor);
        doc->textView = one;
        [doc endReverseSyncSelection];
        REQUIRE(two.selectedTextAttributes[NSBackgroundColorAttributeName] == NSColor.selectedTextBackgroundColor);
        // The marked part has gone (its split closed): the part in use gets the selection.
        @autoreleasepool {
            NSTextView *gone = [[NSTextView alloc] initWithFrame:NSMakeRect(0, 0, 10, 10)];
            doc->textView = gone;
            [doc setTextSelectionYellow:YES];
            doc->textView = one;
            gone = nil;
        }
        TSThemeSetSelectionColor(one, NSColor.yellowColor);
        [doc applyColors:redTheme dark:NO];
        [doc endReverseSyncSelection];
        REQUIRE(SameRGB(one.selectedTextAttributes[NSBackgroundColorAttributeName], NSColor.redColor));
    }
    puts("PASS: switches read, colors, selection attributes, launch check, Settings editing and exchange, the reverse sync in a split");
} return 0; }
'''

# The selection colors chosen for the bundled themes (the switch off), and their switches.
CHOSEN = {'LiteTheme': 'B3D7FF', 'GLG-Lite': 'B3D7FF', 'Manteuffel': 'B3D7FF', 'TransparentTheme': 'B3D7FF', 'SolarizedLite': 'B3D7FF',
          'DarkTheme': '3F638B', 'PreTeXt-Dark': '3F638B', 'Dracula': '44475A', 'SolarizedDark': '274642'}


def luminance(c):
    v = [x / 12.92 if x <= 0.03928 else ((x + 0.055) / 1.055) ** 2.4 for x in c[:3]]
    return 0.2126 * v[0] + 0.7152 * v[1] + 0.0722 * v[2]


def contrast(a, b):
    x, y = luminance(a), luminance(b)
    return (max(x, y) + 0.05) / (min(x, y) + 0.05)


def bundled():
    folder = root / 'Resources/TeXShop/Themes'
    names = sorted(p.stem for p in folder.glob('*.plist'))
    assert names == sorted(CHOSEN), names
    for name, chosen in CHOSEN.items():
        theme = plistlib.loads((folder / (name + '.plist')).read_bytes())
        assert theme['EditorInsertionPointUsesSystemColor'] is False, name
        assert theme['EditorSelectionUsesSystemColor'] is True, name
        selection = theme['EditorSelection']
        assert len(selection) == 4 and selection[3] == 1, name
        assert '%02X%02X%02X' % tuple(round(x * 255) for x in selection[:3]) == chosen, name
        assert contrast(theme['EditorText'], selection) >= 3, (name, contrast(theme['EditorText'], selection))
        text = (folder / (name + '.plist')).read_text(encoding='utf-8')
        assert '<key>EditorInsertionPointUsesSystemColor</key>\n\t<false/>' in text and '<key>EditorSelectionUsesSystemColor</key>\n\t<true/>' in text, name
    for name in ('LiteTheme', 'DarkTheme'):
        assert (root / 'Resources/Themes' / (name + '.plist')).read_bytes() == (folder / (name + '.plist')).read_bytes(), name
    print('PASS: %d bundled themes and the 2 copies inside TeXShop have the switches and selection colors chosen' % len(CHOSEN))


def run(parts, label):
    program = (PROGRAM.replace('__READERS__', '\n'.join(parts['readers'])).replace('__STORE__', parts['store'])
               .replace('__ACCEPTS__', parts['accepts']).replace('__YELLOW__', parts['yellow']).replace('__APPLY__', parts['apply'])
               .replace('__END__', parts['end']).replace('__LOOP__', parts['loop']))
    with tempfile.TemporaryDirectory(prefix='texshop-theme-system-colors-') as folder:
        folder = Path(folder)
        (folder / 'test.m').write_text(program, encoding='utf-8')
        (folder / 'TSLibraryRepair.m').write_text(parts['repair'], encoding='utf-8')
        include = folder / 'include'; include.mkdir()
        (include / 'TSThemeSystemColor.h').write_text(parts['header'], encoding='utf-8')
        subprocess.run(['xcrun', 'clang', '-fobjc-arc', '-w', '-framework', 'Cocoa', '-I', str(include), *include_args(root),
                        str(folder / 'test.m'), str(folder / 'TSLibraryRepair.m'), str(source_file(root, 'TSThemeFileStore.m')),
                        '-o', str(folder / 'test')], check=True)
        if label == 'production':
            verify_embedded(program, fragments)
        home = folder / 'home'; (home / 'Library').mkdir(parents=True)
        tmp = folder / 'tmp'; tmp.mkdir()
        return subprocess.run([str(folder / 'test'), str(root / 'Resources/TeXShop/Themes')], capture_output=True, text=True, timeout=300,
                              env={'CFFIXED_USER_HOME': str(home), 'HOME': str(home), 'TMPDIR': str(tmp) + '/', 'PATH': '/usr/bin:/bin'})


fragments = [('complete method:' + s, support, m) for s, m in zip(signatures, readers)]
fragments += [('complete method:themeStore', settings, store_method), ('complete method:themeListAcceptsData', settings, accepts_method),
              ('complete method:applySourceSelectionColorToTextView', color_source, apply_method), ('complete method:endReverseSyncSelection', color_source, end_method),
              ('statement span:selection of the views', color_source, selection_loop)]
parts = {'readers': readers, 'store': store_method, 'accepts': accepts_method, 'repair': repair, 'header': header,
         'yellow': yellow_methods, 'apply': apply_method, 'end': end_method, 'loop': selection_loop}
bundled()
result = run(parts, 'production')
print(result.stdout, end='')
if result.returncode:
    print(result.stderr, end='')
    raise SystemExit('FAIL: the cursor and selection colors of a theme')
if '--mutations' in sys.argv:
    mutations = {
        'no switch: the selection as the cursor': ('header', '    return [switchKey isEqualToString:TSThemeSelectionUsesSystemColorKey];', '    return NO;'),
        'the switches checked as their type': ('repair', '            if (TSThemeIsSystemColorSwitch(key)) continue;\n', ''),
        'switches exported': ('accepts', '    [colors removeObjectsForKeys:@[TSThemeInsertionPointUsesSystemColorKey, TSThemeSelectionUsesSystemColorKey]];\n', ''),
        'switches counted as entries': ('store', '            if ([key isEqual:@"Title"] || TSThemeIsSystemColorSwitch(key)) continue;', '            if ([key isEqual:@"Title"]) continue;'),
        'no system selection': ('readers', '        return NSColor.selectedTextBackgroundColor;\n', ''),
        'the part in use given back its color': ('end', 'self.reverseSyncTextView ?: [self textView]', '[self textView]'),
        'the marked part recolored by a theme': ('loop', ' && !([self textSelectionYellow] && view == self.reverseSyncTextView)', ''),
        'the marked part not kept': ('yellow', '_reverseSyncTextView = value ? textView : nil;', '(void)value;'),
    }
    for name, (where, before, after) in mutations.items():
        changed = dict(parts)
        if where == 'readers':
            changed['readers'] = [m.replace(before, after) if before in m else m for m in parts['readers']]
            assert changed['readers'] != parts['readers'], name
        else:
            assert changed[where].count(before) == 1, name
            changed[where] = changed[where].replace(before, after)
        r = run(changed, name)
        assert r.returncode and 'FAIL' in r.stderr, (name, r.stdout, r.stderr)
        print('DETECTED', name, r.stderr.strip().splitlines()[-1])
print('PASS: the cursor and selection colors of themes and their system color switches')
