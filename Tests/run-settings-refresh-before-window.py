#!/usr/bin/env python3
"""First launch applies the chosen engine profile before the Settings window exists. Refreshing the controls then
must not touch the nil outlets (the invisible-character popups threw on a nil array element); with the window
built, every category still refreshes. The production methods run verbatim, and removing the guard must fail."""
from pathlib import Path
import subprocess, sys, tempfile
from production_fragments import method, verify_embedded
from source_tree import include_args, source_file

root = Path(__file__).resolve().parents[1]
prefs = source_file(root, 'TSPreferences.m').read_text(encoding='latin1')
refresh = source_file(root, 'TSSettingsPaneRefresh.inc').read_text(encoding='latin1')
GUARD = '    if (_prefsWindow == nil) return;\n'
CATEGORIES = ['General', 'Documents', 'Editor', 'Spelling', 'Appearance', 'Preview', 'Typesetting', 'Console', 'Keyboard', 'Updates']

fragments = [
    ('updateSettingsCategory', refresh, method(refresh, '- (void)updateSettingsCategory:(TSSettingsCategoryID)identifier fromDefaults:(NSUserDefaults *)defaults')),
    ('updateControlsFromUserDefaults', refresh, method(refresh, '- (void)updateControlsFromUserDefaults:(NSUserDefaults *)defaults')),
    ('applyEngineProfileValues', prefs, method(prefs, '- (void)applyEngineProfileValues:(NSDictionary<NSString *, id> *)values')),
    ('updateInvisibleCharacterControls', prefs, method(prefs, '- (void)updateInvisibleCharacterControls:(NSUserDefaults *)defaults')),
]
assert GUARD in fragments[0][2], 'the refresh guard is missing'

stubs = '\n'.join('- (void)refresh%sSettingsFromDefaults:(NSUserDefaults *)defaults { [self.refreshed addObject:@"%s"];%s }'
                  % (c, c, ' [self updateInvisibleCharacterControls:defaults];' if c == 'Editor' else '') for c in CATEGORIES)

PROGRAM = r'''
#import <Cocoa/Cocoa.h>
#import "TSSettingsCategory.h"
#import "TSInvisibleCharacters.h"
#import "globals.h"
static NSUserDefaults *TestDefaults;
#undef SUD
#define SUD TestDefaults
static NSSet *TSEngineProfileApply(NSUserDefaults *defaults, NSDictionary *values) { return [NSSet set]; }
@interface ChangeNotes : NSObject
- (void)valuesReplaced;
@end
@implementation ChangeNotes
- (void)valuesReplaced {}
@end
@interface Harness : NSObject {
@public
    NSWindow *_prefsWindow;
    NSPopUpButton *_SpaceCharacterKindPopup, *_FullwidthSpaceCharacterKindPopup, *_NewLineCharacterKindPopup, *_TabCharacterKindPopup;
    NSButton *_showSpaceCharacterButton, *_showFullwidthSpaceCharacterButton, *_showNewLineCharacterButton, *_showTabCharacterButton;
}
@property NSMutableArray *refreshed;
@property ChangeNotes *settingsChangeNotes;
@end
@implementation Harness
- (void)refreshRuntimePreferences {}
- (void)applyEffectsForPreferenceKeys:(NSSet *)changed {}
- (void)updateSettingsDependenciesForCategory:(TSSettingsCategoryID)category defaults:(NSUserDefaults *)defaults {}
__STUBS__
__METHODS__
@end
int main(void) { @autoreleasepool {
    NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:@"TeXShop.SettingsRefreshBeforeWindow.test"];
    [defaults removePersistentDomainForName:@"TeXShop.SettingsRefreshBeforeWindow.test"];
    TestDefaults = defaults;
    Harness *h = [Harness new]; h.refreshed = [NSMutableArray array];
    // First launch: the profile chooser applies its values while no Settings window has been built.
    @try { [h applyEngineProfileValues:@{}]; }
    @catch (NSException *e) { fprintf(stderr, "FAIL: refresh before the window threw %s\n", e.reason.UTF8String); return 1; }
    if (h.refreshed.count) { fprintf(stderr, "FAIL: refreshed %s without a window\n", h.refreshed.description.UTF8String); return 1; }
    // With the window and its outlets, every category refreshes, the invisible-character popups included.
    h->_prefsWindow = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 10, 10) styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:YES];
    NSPopUpButton * __strong *popups[] = {&h->_SpaceCharacterKindPopup, &h->_FullwidthSpaceCharacterKindPopup, &h->_NewLineCharacterKindPopup, &h->_TabCharacterKindPopup};
    NSButton * __strong *buttons[] = {&h->_showSpaceCharacterButton, &h->_showFullwidthSpaceCharacterButton, &h->_showNewLineCharacterButton, &h->_showTabCharacterButton};
    for (int i = 0; i < 4; i++) { *popups[i] = [NSPopUpButton new]; *buttons[i] = [NSButton checkboxWithTitle:@"x" target:nil action:nil]; }
    [h updateControlsFromUserDefaults:defaults];
    NSArray *all = @[__ALL__];
    if (![h.refreshed isEqual:all]) { fprintf(stderr, "FAIL: refreshed %s\n", h.refreshed.description.UTF8String); return 1; }
    if (h->_SpaceCharacterKindPopup.numberOfItems == 0) { fprintf(stderr, "FAIL: popup not filled\n"); return 1; }
    [defaults removePersistentDomainForName:@"TeXShop.SettingsRefreshBeforeWindow.test"];
    puts("PASS settings refresh before the window");
} return 0; }
'''


def build_and_run(td, methods, name):
    program = PROGRAM.replace('__STUBS__', stubs).replace('__METHODS__', methods) \
                     .replace('__ALL__', ', '.join('@"%s"' % c for c in CATEGORIES))
    src = td / (name + '.m'); exe = td / name
    src.write_text(program)
    subprocess.run(['clang', '-fobjc-arc', '-w', '-framework', 'Cocoa', *include_args(root), str(src),
                    str(source_file(root, 'TSSettingsCategory.m')), str(source_file(root, 'globals.m')), '-o', str(exe)], check=True)
    return subprocess.run([str(exe)], capture_output=True, text=True, timeout=20), program


with tempfile.TemporaryDirectory() as td:
    td = Path(td)
    methods = '\n'.join(f for _, _, f in fragments)
    result, program = build_and_run(td, methods, 'normal')
    verify_embedded(program, fragments)
    sys.stdout.write(result.stdout); sys.stderr.write(result.stderr)
    assert result.returncode == 0, 'normal harness failed'
    mutated, _ = build_and_run(td, methods.replace(GUARD, '', 1), 'mutated')
    assert mutated.returncode != 0, 'removing the guard went unnoticed'
    print('PASS mutation: without the guard the refresh fails (%s)' % (mutated.stderr.strip().splitlines() or ['crash'])[-1])
