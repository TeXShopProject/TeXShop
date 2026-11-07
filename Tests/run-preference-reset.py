#!/usr/bin/env python3
"""Restoring default settings recolors open documents when @ changes its meaning.

The production -setDefaults: and -undoDefaultPrefs: of TSPreferences run on every bundled
defaults file, with settings kept in memory (no user defaults are read or written). When
MakeatletterEnabled changes, open documents must be told to color commands again, both when
the defaults are restored and when that is undone; when it does not change, they are not.
--mutation=reset or --mutation=undo removes one of the two and the test must then fail.
A profile keeps what is not a setting of the window: keyboard shortcuts, the App Shortcuts and
app language chosen in System Settings, and AppKit's window, toolbar and split view state. Other settings missing from the profile are still removed, and
undoing restores the earlier settings exactly. --mutation=keep drops nothing and must fail."""
from pathlib import Path
import subprocess, sys, tempfile
root = Path(__file__).resolve().parents[1]
mutation = next((a.split('=', 1)[1] for a in sys.argv[1:] if a.startswith('--mutation=')), None)
s = (root/'Sources/TSPreferences.m').read_text(encoding='latin1')
def method(signature):
    a = s.index('\n' + signature) + 1
    return s[a:s.index('\n}', a) + 2]
setDefaults = method('- (IBAction)setDefaults:sender')
undoDefaults = method('- (void)undoDefaultPrefs:')
recolor = '    if (oldMakeatletter != [SUD boolForKey:MakeatletterEnabledKey])\n'
if mutation == 'reset':
    assert recolor in setDefaults; setDefaults = setDefaults.replace(recolor, '    if (NO)\n')
elif mutation == 'undo':
    assert recolor in undoDefaults; undoDefaults = undoDefaults.replace(recolor, '    if (NO)\n')
elif mutation == 'keep':
    kept = 'profile[key] = value;'
    assert setDefaults.count(kept) == 1; setDefaults = setDefaults.replace(kept, ';')
elif mutation:
    raise SystemExit('unknown mutation ' + mutation)
plists = sorted(str(p) for p in (root/'Resources/Shellscripts').glob('*.plist') if p.name.startswith(('FactoryDefaults', 'Defaults_')))
program = r'''
#import <Cocoa/Cocoa.h>
@interface MemoryDefaults : NSObject
@property NSMutableDictionary *values;
@end
@implementation MemoryDefaults
- (instancetype)init { if ((self = [super init])) _values = [NSMutableDictionary new]; return self; }
- (NSDictionary *)persistentDomainForName:(NSString *)n { return [self.values copy]; }
- (void)setPersistentDomain:(NSDictionary *)d forName:(NSString *)n { self.values = [d mutableCopy]; }
- (void)synchronize {}
- (BOOL)boolForKey:(NSString *)k { return [self.values[k] boolValue]; }
- (void)setBool:(BOOL)v forKey:(NSString *)k { self.values[k] = @(v); }
- (id)objectForKey:(NSString *)k { return self.values[k]; }
- (void)setObject:(id)v forKey:(NSString *)k { if (v) self.values[k] = v; else [self.values removeObjectForKey:k]; }
- (NSString *)stringForKey:(NSString *)k { id v = self.values[k]; return [v isKindOfClass:[NSString class]] ? v : [v description]; }
- (float)floatForKey:(NSString *)k { return [self.values[k] floatValue]; }
- (void)setFloat:(float)v forKey:(NSString *)k { self.values[k] = @(v); }
@end
static MemoryDefaults *memory;
#define SUD memory
#define MakeatletterEnabledKey @"MakeatletterEnabled"
#define TSMenuShortcutOverridesKey @"TSMenuShortcutOverrides"
#define DocumentFontKey @"DocumentFont"
#define DocumentFontAttributesKey @"DocumentFontAttributes"
#define ConsoleFontNameKey @"ConsoleFontName"
#define ConsoleFontSizeKey @"ConsoleFontSize"
#define DocumentFontChangedNotification @"DocumentFontChanged"
#define ConsoleFontChangedNotification @"ConsoleFontChanged"
#define DocumentFontRememberNotification @"DocumentFontRemember"
static NSString *TSPreferencesDomainName(void) { return @"memory-only"; }
@interface TSSpellSupport : NSObject
+ (void)preferencesDidChange;
@end
@implementation TSSpellSupport
+ (void)preferencesDidChange {}
@end
static NSString *gDefaultsFile;
@interface TestBundle : NSObject
+ (instancetype)mainBundle;
- (NSString *)pathForResource:(NSString *)name ofType:(NSString *)ext;
@end
@implementation TestBundle
+ (instancetype)mainBundle { return [self new]; }
- (NSString *)pathForResource:(NSString *)name ofType:(NSString *)ext { return gDefaultsFile; }
@end
#define NSBundle TestBundle
@interface TSPreferences : NSObject {
@public
    NSUndoManager *_undoManager;
}
@property NSFont *documentFont, *consoleFont;
@property NSDictionary *fontAttributes;
@end
@implementation TSPreferences
- (void)updateControlsFromUserDefaults:(id)defaults {}
- (void)updateDocumentFontTextField {}
- (void)updateConsoleFontTextField {}
SETDEFAULTS
UNDODEFAULTS
@end
#undef NSBundle
static int failures = 0, recolors = 0;
static void check(BOOL ok, NSString *what) { printf("%s %s\n", ok ? "ok  " : "FAIL", what.UTF8String); failures += ! ok; }
int main(int argc, char **argv) { @autoreleasepool {
    memory = [MemoryDefaults new];
    [[NSNotificationCenter defaultCenter] addObserverForName:@"NeedsForRecolorNotification" object:nil queue:nil
        usingBlock:^(NSNotification *n) { recolors++; }];
    TSPreferences *p = [TSPreferences new];
    p->_undoManager = [NSUndoManager new];
    p.documentFont = [NSFont userFontOfSize:12];
    for (int i = 1; i < argc; i++) {
        gDefaultsFile = @(argv[i]);
        NSDictionary *bundled = [[NSString stringWithContentsOfFile:gDefaultsFile usedEncoding:NULL error:NULL] propertyList];
        BOOL bundledAt = [bundled[@"MakeatletterEnabled"] boolValue];
        for (int before = 0; before <= 1; before++) {
            [p->_undoManager removeAllActions];
            NSDictionary *shortcuts = @{@"TSShortcut.doTypeset:.-1": @{@"key": @"r", @"modifiers": @(NSEventModifierFlagCommand)}};
            NSDictionary *earlier = @{@"MakeatletterEnabled": @(before), @"TSMenuShortcutOverrides": shortcuts,
                @"NSWindow Frame PrefPane": @"10 10 600 500 0 0 1440 900 ", @"NSToolbar Configuration TSPdfToolbar": @{@"TB Is Shown": @1},
                @"NSSplitView Subview Frames Split": @[@"0, 0, 100, 100, NO"], @"TeXAwareSpellChecking": @NO, @"EncodingAutoDetection": @NO,
                @"NSUserKeyEquivalents": @{@"Typeset": @"@r"}, @"AppleLanguages": @[@"ja"]};
            memory.values = [earlier mutableCopy];
            NSButton *sender = [NSButton new]; sender.tag = 0;
            recolors = 0;
            [p->_undoManager beginUndoGrouping]; [p setDefaults:sender]; [p->_undoManager endUndoGrouping];
            BOOL changed = (before != bundledAt);
            check(recolors == (changed ? 1 : 0) && [memory boolForKey:@"MakeatletterEnabled"] == bundledAt,
                  [NSString stringWithFormat:@"%@, @ was %s: restoring %s", gDefaultsFile.lastPathComponent, before ? "on" : "off",
                   changed ? "recolors once" : "does not recolor"]);
            check([memory.values[@"TSMenuShortcutOverrides"] isEqual:shortcuts] && memory.values[@"NSWindow Frame PrefPane"] &&
                  memory.values[@"NSToolbar Configuration TSPdfToolbar"] && memory.values[@"NSSplitView Subview Frames Split"] &&
                  [memory.values[@"NSUserKeyEquivalents"] isEqual:earlier[@"NSUserKeyEquivalents"]] && [memory.values[@"AppleLanguages"] isEqual:@[@"ja"]],
                  [NSString stringWithFormat:@"%@: keyboard shortcuts, App Shortcuts, app language and window, toolbar and split view state are kept", gDefaultsFile.lastPathComponent]);
            check((bundled[@"TeXAwareSpellChecking"] != nil || memory.values[@"TeXAwareSpellChecking"] == nil) &&
                  (bundled[@"EncodingAutoDetection"] != nil || memory.values[@"EncodingAutoDetection"] == nil),
                  [NSString stringWithFormat:@"%@: other settings missing from the profile are still removed", gDefaultsFile.lastPathComponent]);
            recolors = 0;
            [p->_undoManager undo];
            check([memory.values isEqual:earlier], [NSString stringWithFormat:@"%@: undoing restores the earlier settings exactly", gDefaultsFile.lastPathComponent]);
            check(recolors == (changed ? 1 : 0) && [memory boolForKey:@"MakeatletterEnabled"] == before,
                  [NSString stringWithFormat:@"%@, @ was %s: undoing it %s", gDefaultsFile.lastPathComponent, before ? "on" : "off",
                   changed ? "recolors once" : "does not recolor"]);
        }
    }
    return failures ? 1 : 0;
}}
'''.replace('SETDEFAULTS', setDefaults).replace('UNDODEFAULTS', undoDefaults)
with tempfile.TemporaryDirectory(prefix='texshop-preference-reset-') as folder:
    f = Path(folder); (f/'test.m').write_text(program, encoding='latin1')
    subprocess.run(['xcrun', 'clang', '-fobjc-arc', '-w', '-framework', 'Cocoa', str(f/'test.m'), '-o', str(f/'test')], check=True)
    r = subprocess.run([str(f/'test'), *plists], timeout=60)
    if r.returncode:
        raise SystemExit('FAIL: restoring default settings does not behave as it should')
    print('PASS: restoring default settings, and undoing it, recolors open documents exactly when @ changes and keeps keyboard shortcuts and window state')
