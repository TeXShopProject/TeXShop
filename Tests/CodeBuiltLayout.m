// The windows, panels and accessory views the application builds in code,
// checked with the checks of LayoutChecks.inc in each language given, as the
// production code builds them:
//   * the Experiment console (TSExperimentConsoleController), as it opens and at
//     its smallest size;
//   * the view below the Spelling and Grammar panel with Change All
//     (TSChangeAllAccessory in TSSpellSupport.m), with each message it shows;
//   * the alert that lists the TeX and Ghostscript installations found
//     (TSEnginePathAlert in TSPreferences.m), laid out by NSAlert, with several
//     installations, with one, and with none (Detect Paths and the first step of
//     first launch); the window that chooses an engine profile (the second
//     step) and the sheet that applies one (TSEngineProfileSheet), each with
//     the list of what a profile sets (TSEngineProfileList), for every
//     profile and both forms;
//   * the alerts that list macro shortcut conflicts (TSShortcutConflictsAlert in
//     TSMacroEditor.m) and the learned words of a document (TSLearnedWordsAlert
//     in TSSpellSupport.m), laid out by NSAlert;
//   * the overlay that shows the size of a selection in the preview: its text
//     for the largest selection must fit (SIZE_WINDOW_* in globals.h).
// run-code-built-layout.py appends this file to the production Experiment
// console controller and the stubs it needs (experiment_console_source.py), and
// supplies the copied production functions as SpellAccessory.inc,
// EnginePathAlert.inc, ShortcutConflictsAlert.inc, LearnedWordsAlert.inc and
// SizeWindow.inc. Nothing is ordered on screen, frames
// are not saved and AppKit defaults stay in memory.
// Usage: CodeBuiltLayout [--images DIR [--focus-rings]] <language>|<Localizable.strings> ...
#import <objc/runtime.h>
#include "LayoutChecks.inc"
#include "SizeWindow.inc"

#include "SpellAccessory.inc"
@interface ChangeAllTarget : NSObject @end
@implementation ChangeAllTarget
- (IBAction)changeAll:(id)sender {}
@end

#import "MemoryDefaults.h"
#include "EnginePathAlert.inc"
static NSView *FindView(NSView *root, NSString *identifier) {
    if ([root.identifier isEqual:identifier]) return root;
    for (NSView *view in root.subviews) { NSView *found = FindView(view, identifier); if (found) return found; }
    return nil;
}
#include "ShortcutConflictsAlert.inc"
#include "LearnedWordsAlert.inc"
@interface WordList : NSObject <NSTableViewDataSource> @end
@implementation WordList
- (NSInteger)numberOfRowsInTableView:(NSTableView *)t { return 3; }
- (id)tableView:(NSTableView *)t objectValueForTableColumn:(NSTableColumn *)c row:(NSInteger)r { return @[@"texshop", @"synctex", @"latexmk"][r]; }
@end

// Installations as TSEnginePathDiscovery reports them.
static NSDictionary *Candidate(NSString *version, NSString *path) {
    return version ? @{@"version": version, @"path": path} : @{@"path": path};
}

int main(int argc, char **argv) { @autoreleasepool {
    TSInstallAppKitIsolation();
    InstallLocalizedStrings();
    [NSApplication sharedApplication]; [NSApp setActivationPolicy:NSApplicationActivationPolicyProhibited];
    NSApp.appearance = [NSAppearance appearanceNamed:NSAppearanceNameAqua];
    liteColors = @{@"ConsoleBackground": [NSColor colorWithSRGBRed:.9961 green:.9765 blue:.9176 alpha:1], @"ConsoleText": NSColor.blackColor};
    darkColors = @{@"ConsoleBackground": NSColor.blackColor, @"ConsoleText": NSColor.whiteColor};
    NSMutableArray<NSString *> *entries = [NSMutableArray array];
    for (int i = 1; i < argc; i++) {
        if (!strcmp(argv[i], "--images") && i + 1 < argc) { imagesDirectory = @(argv[++i]); continue; }
        if (!strcmp(argv[i], "--focus-rings")) { imagesWithFocusRings = YES; continue; }
        [entries addObject:@(argv[i])];
    }
    NSUInteger roots = 0;
    for (NSString *entry in entries) {
        NSArray<NSString *> *parts = [entry componentsSeparatedByString:@"|"];
        NSString *language = parts[0];
        UseLocalizedStrings(parts.count > 1 ? parts[1] : nil);
        // The list of what an engine profile sets names the settings as Settings does.
        if (parts.count > 1) UseLocalizedTables(parts[1], @[@"SettingsCategories", @"Encodings"]);

        // The Experiment console, with its input field enabled as while a job runs.
        TSExperimentConsoleController *console = [TSExperimentConsoleController new];
        if (!console.window || console.window.isVisible) { printf("ERROR %s the Experiment console was not built offscreen\n", language.UTF8String); return 2; }
        console.commandField.enabled = YES; console.stopButton.enabled = YES;
        CheckWindow(console.window, [NSString stringWithFormat:@"%@ [Experiment console]", language]); roots++;

        // The Change All row, and the popover with each message Change All reports.
        NSTextField *field = nil, *status = nil;
        NSView *accessory = TSChangeAllAccessory([ChangeAllTarget new], &field, &status);
        NSWindow *holder = [[NSWindow alloc] initWithContentRect:accessory.frame styleMask:NSWindowStyleMaskBorderless backing:NSBackingStoreBuffered defer:YES];
        holder.contentView = accessory;
        CheckRoot(accessory, [NSString stringWithFormat:@"%@ [Change All below the spelling panel]", language]); roots++;
        SaveImage(accessory, [NSString stringWithFormat:@"%@ [Change All below the spelling panel]", language]);
        for (NSString *message in @[NSLocalizedString(@"Return to the word and choose Find Next before replacing.", @""),
                                    NSLocalizedString(@"Enter a different replacement in the Change All field.", @"")]) {
            status.stringValue = message;
            NSView *popover = TSChangeAllStatusView(status);
            NSWindow *popoverHolder = [[NSWindow alloc] initWithContentRect:popover.frame styleMask:NSWindowStyleMaskBorderless backing:NSBackingStoreBuffered defer:YES];
            popoverHolder.contentView = popover;
            NSString *name = [NSString stringWithFormat:@"%@ [Change All message] %@", language, message];
            CheckRoot(popover, name); roots++;
            SaveImage(popover, name);
            [popover removeFromSuperview]; [popover addSubview:status];
        }

        // The installations found, laid out by NSAlert as it shows them.
        // A path longer than a line is shown with an ellipsis and in full in its
        // tooltip; these are as long as installations usually are.
        NSString *longPath = @"/opt/homebrew/Caskroom/mactex-no-gui/2026/texlive/2026/bin/universal-darwin";
        NSDictionary *cases = @{
            @"several": @{@"TeX": @[Candidate(@"TeX Live 2026", @"/usr/local/texlive/2026/bin/universal-darwin"),
                                    Candidate(@"TeX Live 2025", @"/usr/local/texlive/2025/bin/universal-darwin"),
                                    Candidate(nil, longPath), Candidate(@"MacTeX 2024", @"/Library/TeX/texbin")],
                          @"Ghostscript": @[Candidate(@"10.06.0", @"/usr/local/bin"), Candidate(@"10.04.0", @"/opt/homebrew/bin")]},
            @"one": @{@"TeX": @[Candidate(@"TeX Live 2026", @"/Library/TeX/texbin")], @"Ghostscript": @[]},
            @"none": @{@"TeX": @[], @"Ghostscript": @[]},
        };
        for (NSString *name in @[@"several", @"one", @"none"]) {
            NSAlert *alert = TSEnginePathAlert(cases[name], [NSMutableDictionary dictionary]);
            [alert layout];
            NSString *where = [NSString stringWithFormat:@"%@ [Detect Paths, %@ found]", language, name];
            CheckRoot(alert.window.contentView, where); roots++;
            SaveImage(alert.window.contentView, where);
        }
        // The engine profile: the window of the second step of first launch, with each profile chosen in its menu,
        // and the sheet shown when a profile is chosen, for each profile, with latexmk chosen either way and two of
        // the values that change turned off. The settings in use are empty, so that every value changes.
        TSMemoryDefaults *inUse = [TSMemoryDefaults new];
        TSEngineProfileSheet *choice = [[TSEngineProfileSheet alloc] initChoosingProfile:TSEngineProfileLuaLaTeXJapanese];
        for (NSMenuItem *item in choice.profileMenu.itemArray) {
            if (item.isSeparatorItem) continue;
            [choice.profileMenu selectItem:item];
            [choice.profileMenu sendAction:choice.profileMenu.action to:choice.profileMenu.target];
            for (NSInteger form = 0; form < 2; form++) {
                choice.latexmkChoice.selectedSegment = form;
                [choice.latexmkChoice sendAction:choice.latexmkChoice.action to:choice.latexmkChoice.target];
                NSString *where = [NSString stringWithFormat:@"%@ [engine profile choice, %@%@]", language, item.title, form ? @", latexmk" : @""];
                CheckRoot(choice.window.contentView, where); roots++;
                SaveImage(choice.window.contentView, where);
            }
        }
        for (NSArray<NSNumber *> *section in TSEngineProfileMenuSections()) for (NSNumber *profile in section) for (NSNumber *on in @[@NO, @YES]) {
            TSEngineProfileSheet *sheet = [[TSEngineProfileSheet alloc] initWithProfile:profile.integerValue latexmk:on.boolValue settings:inUse];
            NSGridView *rows = (NSGridView *)FindView(sheet.list, @"settings.engine-profile-list.rows");
            for (NSInteger r = 1; r < 3; r++) {
                NSButton *box = (NSButton *)[rows cellAtColumnIndex:0 rowIndex:r].contentView;
                if ([box isKindOfClass:NSButton.class]) [box performClick:nil];
            }
            for (int turn = 0; turn < 2; turn++) {
                if (turn) { sheet.latexmkChoice.selectedSegment = !on.boolValue; [sheet.latexmkChoice sendAction:sheet.latexmkChoice.action to:sheet.latexmkChoice.target]; }
                NSString *where = [NSString stringWithFormat:@"%@ [engine profile sheet, %@%@]", language, TSEngineProfileTitle(profile.integerValue), on.boolValue != turn ? @", latexmk" : @""];
                CheckRoot(sheet.window.contentView, where); roots++;
                if (!turn) SaveImage(sheet.window.contentView, where);
            }
        }

        NSArray<NSAlert *> *alerts = @[TSShortcutConflictsAlert(@"⌘T: Typeset › plain TeX\n⇧⌘M: Typeset › MetaPost"),
                                       TSLearnedWordsAlert(@"en", [WordList new], &(NSTableView *__strong){nil})];
        NSArray<NSString *> *names = @[@"macro shortcut conflicts alert", @"learned words alert"];
        for (NSUInteger i = 0; i < alerts.count; i++) {
            [alerts[i] layout];
            NSString *where = [NSString stringWithFormat:@"%@ [%@]", language, names[i]];
            CheckRoot(alerts[i].window.contentView, where); roots++;
            SaveImage(alerts[i].window.contentView, where);
        }
    }

    // The size of a selection, at most four digits by four, drawn with the default
    // attributes at SIZE_WINDOW_DRAW_X in an overlay SIZE_WINDOW_WIDTH wide.
    CGFloat need = SIZE_WINDOW_DRAW_X + [@"8888 x 8888" sizeWithAttributes:@{}].width;
    if (need > SIZE_WINDOW_WIDTH) Report([NSString stringWithFormat:@"CLIPPED [selection size overlay] \"8888 x 8888\": needs %.1f, has %d", need, SIZE_WINDOW_WIDTH]);

    if (problems) { printf("FAIL: %d problems\n", problems); return 1; }
    printf("PASS: the Experiment console, the Change All view, the engine path, engine profile, shortcut conflicts and learned words alerts and the selection size overlay show their whole text, inside their windows and apart, with room for focus rings and even margins (%lu windows and views in %lu languages)\n", (unsigned long)roots, (unsigned long)entries.count);
} return 0; }
