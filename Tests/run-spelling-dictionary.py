#!/usr/bin/env python3
"""Check the spelling dictionary chosen in Settings and how documents follow it.

Production TSDocument methods, and the TSAppDelegate statements that give the
checker the Settings choice at launch, are copied verbatim into a probe with a
fake spell checker (it names "en_US" "en", as macOS 27 does) and in-memory
defaults. Its main bundle is a fixture carrying the twelve real
Localizable.strings files. No window is ordered, and the system spell checker
and its settings are not used.
"""
from pathlib import Path
import argparse, plistlib, shutil, subprocess, sys, tempfile
from production_fragments import method, verify_embedded
from source_tree import include_args

root = Path(__file__).resolve().parents[1]
sources = {path: (root/path).read_text() for path in
           ('Sources/Document/TSDocument.m', 'Sources/Editor/TSSpellingLanguage.h', 'Sources/App/TSAppDelegate.m')}

MUTATIONS = {
    'resign-ignores-panel': ('Sources/Document/TSDocument.m',
        '        self.spellLanguageFollowsDefault = NO;\n    self.automaticSpelling = identifiesLanguages;',
        '        ;\n    self.automaticSpelling = identifiesLanguages;'),
    'resign-raw-language': ('Sources/Document/TSDocument.m',
        '    self.appliedSpellLanguage = [theChecker language];',
        '    self.appliedSpellLanguage = self.spellLanguage;'),
    'no-follow': ('Sources/Document/TSDocument.m',
        '    if (! self.spellLanguageFollowsDefault)\n        return;\n    NSString *defaultSpellLanguage',
        '    return;\n    NSString *defaultSpellLanguage'),
    'tex-line-follows': ('Sources/Document/TSDocument.m',
        '                self.spellLanguageFollowsDefault = NO;\n', ''),
    'tex-line-resets-other': ('Sources/Document/TSDocument.m',
        '                if ([self spellingWindowIsMain])\n                    [self resetSpelling];',
        '                [self resetSpelling];'),
    'no-region-fallback': ('Sources/Editor/TSSpellingLanguage.h',
        '            if ([TSSpellingLanguageNormalized(language) caseInsensitiveCompare:base] == NSOrderedSame) return language;',
        '            ;'),
    'document-raw-stored': ('Sources/Editor/TSSpellingLanguage.h',
        '(TSSpellingLanguageMatching(stored, available ?: @[]) ?: stored)', 'stored'),
    'no-automatic-title': ('Sources/Editor/TSSpellingLanguage.h',
        '|| TSSpellingLanguageIsAutomaticTitle(stored)', ''),
    'launch-not-applied': ('Sources/App/TSAppDelegate.m',
        '[TSDocument applySpellingDefaultUnlessDocumentIsMain];\n    [[NSNotificationCenter', '[[NSNotificationCenter'),
    'app-ignores-settings-change': ('Sources/App/TSAppDelegate.m',
        '{\n    [TSDocument applySpellingDefaultUnlessDocumentIsMain];\n}', '{\n}'),
    'applies-over-main-document': ('Sources/Document/TSDocument.m',
        '[document isKindOfClass:self] && [document spellingWindowIsMain]', 'NO'),
    'close-not-applied': ('Sources/Document/TSDocument.m',
        '\t[super close];\n    [TSDocument applySpellingDefaultUnlessDocumentIsMain];\n', '\t[super close];\n'),
    'unknown-changes-checker': ('Sources/Document/TSDocument.m',
        '    if (! automatic && ! [available containsObject:defaultSpellLanguage])\n        return;\n', ''),
    'original-spelling-at-launch': ('Sources/Document/TSDocument.m',
        '+ (void)applySpellingDefaultUnlessDocumentIsMain {\n    \n    if ([SUD boolForKey: originalSpellingKey])\n        return;\n',
        '+ (void)applySpellingDefaultUnlessDocumentIsMain {\n    \n'),
}

parser = argparse.ArgumentParser()
parser.add_argument('--mutation', choices=sorted(MUTATIONS))
args = parser.parse_args()
if args.mutation:
    path, old, new = MUTATIONS[args.mutation]
    assert sources[path].count(old) == 1, args.mutation
    sources[path] = sources[path].replace(old, new)
document, header, delegate = (sources[path] for path in
    ('Sources/Document/TSDocument.m', 'Sources/Editor/TSSpellingLanguage.h', 'Sources/App/TSAppDelegate.m'))

init_block = document[document.index('    NSString *defaultSpellLanguage = nil;\n    self.automaticSpelling = TSSpellingDefaultIsAutomatic'):]
init_block = init_block[:init_block.index('name:TSSpellingLanguageChangedNotification object:nil];\n') + len('name:TSSpellingLanguageChangedNotification object:nil];\n')]
tex_block = document[document.index('                self.automaticSpelling = NO;\n                self.spellLanguage = spellcheckString;\n'):]
tex_block = tex_block[:tex_block.index('[self resetSpelling];\n') + len('[self resetSpelling];\n')]
methods = [method(document, s) for s in ('- (void)resetSpelling {', '- (void)resignSpelling {',
    '- (void)spellingLanguageDefaultChanged:(NSNotification *)notification {', '- (BOOL)spellingWindowIsMain {',
    '+ (void)applySpellingDefaultUnlessDocumentIsMain {')]
close_method = method(document, '- (void)close\n{')
close_tail = close_method[close_method.index('\t[super close];\n'):]
launch_marker = "    // Until a document's source window is main, the Spelling panel shows the dictionary chosen in Settings.\n"
launch_block = delegate[delegate.index(launch_marker):]
launch_block = launch_block[:launch_block.index('name:TSSpellingLanguageChangedNotification object:nil];\n') + len('name:TSSpellingLanguageChangedNotification object:nil];\n')]
delegate_method = method(delegate, '- (void)spellingLanguageDefaultChanged:(NSNotification *)notification\n{')

program = r'''
#import <Cocoa/Cocoa.h>
#import <objc/runtime.h>
#import "MemoryDefaults.h"
NSString *spellingLanguageDefaultKey = @"SpellingLanguageDefault";
NSString *spellingAutomaticDefaultKey = @"SpellingAutomaticDefault";
NSString *originalSpellingKey = @"OriginalSpelling";
static NSNotificationName const TSSpellingLanguageChangedNotification = @"TSSpellingLanguageChangedNotification";
@@HEADER@@
static TSMemoryDefaults *defaults;
#define SUD defaults
static int failures;
static void Check(BOOL ok, const char *what) { if (!ok) { fprintf(stderr, "FAIL: %s\n", what); failures++; } }

// The system checker on macOS 27.2: "en_US" and "English" are taken as "en",
// "de_DE" as "de"; an unknown name leaves the language as it was.
@interface FakeChecker : NSObject {
    NSString *_language;
}
@property (readonly) NSString *language;
- (void)reportLanguage:(NSString *)language;
@property BOOL automaticallyIdentifiesLanguages;
@property NSUInteger sets;
@property (readonly) NSArray *availableLanguages;
+ (instancetype)sharedSpellChecker;
- (BOOL)setLanguage:(NSString *)language;
@end
@implementation FakeChecker
+ (instancetype)sharedSpellChecker { static FakeChecker *c; if (!c) { c = [FakeChecker new]; [c reportLanguage:@"fr"]; } return c; }
- (NSString *)language { return _language; }
- (NSArray *)availableLanguages { return @[@"en", @"en_GB", @"de", @"fr", @"ja"]; }
- (void)reportLanguage:(NSString *)language { _language = [language copy]; }
- (BOOL)setLanguage:(NSString *)language {
    self.sets++;
    NSDictionary *names = @{@"en": @"en", @"en_US": @"en", @"en-US": @"en", @"English": @"en", @"German": @"de", @"en_GB": @"en_GB",
                            @"de": @"de", @"de_DE": @"de", @"fr": @"fr", @"ja": @"ja"};
    if (!names[language]) return NO;
    _language = names[language];
    return YES;
}
@end
#define NSSpellChecker FakeChecker
#define TSDocument ProbeDocument

// The documents that are open, as TSDocumentController lists them.
static NSMutableArray *documentsForTest;
@interface TSDocumentController : NSObject
+ (instancetype)sharedDocumentController;
@property (readonly) NSArray *documents;
@end
@implementation TSDocumentController
+ (instancetype)sharedDocumentController { static TSDocumentController *c; if (!c) c = [TSDocumentController new]; return c; }
- (NSArray *)documents { return [documentsForTest copy]; }
@end

static NSBundle *strings;
static id StringsBundle(id bundleClass, SEL selector) { return strings; }
static NSWindow *mainWindowForTest;
static id MainWindow(id app, SEL selector) { return mainWindowForTest; }

// NSDocument's close: the document's windows close and it leaves the list.
@interface ProbeBaseDocument : NSObject {
@public
    NSWindow *textWindow;
    NSWindow *fullSplitWindow;
}
- (void)close;
@end
@implementation ProbeBaseDocument
- (void)close {
    if (mainWindowForTest == textWindow) mainWindowForTest = nil;
    [documentsForTest removeObject:self];
}
@end

@interface ProbeDocument : ProbeBaseDocument
@property (retain) NSString *spellLanguage;
@property BOOL automaticSpelling;
@property BOOL spellLanguageFollowsDefault;
@property (copy) NSString *appliedSpellLanguage;
@property BOOL appliedAutomaticSpelling;
- (void)resetSpelling;
@end
@implementation ProbeDocument
- (instancetype)init {
    if ((self = [super init])) {
@@INIT@@
    }
    return self;
}
- (void)dealloc { [[NSNotificationCenter defaultCenter] removeObserver:self]; }
- (void)applySpellcheckLine:(NSString *)spellcheckString {
@@TEX@@
}
@@METHODS@@
- (void)close {
@@CLOSE@@
// The document's source window becomes main or resigns, as TSTextEditorWindow does.
- (void)becomeMain { mainWindowForTest = textWindow; [self resetSpelling]; }
- (void)resignMain { [self resignSpelling]; mainWindowForTest = nil; }
@end

@interface ProbeAppDelegate : NSObject
@end
@implementation ProbeAppDelegate
- (void)applicationWillFinishLaunching {
@@LAUNCH@@
}
@@DELEGATE@@
@end

static void ChooseInSettings(NSString *language) {
    if (language) { [defaults setBool:NO forKey:spellingAutomaticDefaultKey]; [defaults setObject:language forKey:spellingLanguageDefaultKey]; }
    else { [defaults setBool:YES forKey:spellingAutomaticDefaultKey]; [defaults setObject:@" " forKey:spellingLanguageDefaultKey]; }
    [[NSNotificationCenter defaultCenter] postNotificationName:TSSpellingLanguageChangedNotification object:nil];
}

static ProbeDocument *NewDocument(void) {
    ProbeDocument *d = [ProbeDocument new];
    d->textWindow = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 10, 10) styleMask:NSWindowStyleMaskBorderless backing:NSBackingStoreBuffered defer:YES];
    d->textWindow.releasedWhenClosed = NO;
    [documentsForTest addObject:d];
    return d;
}

int main(int argc, char **argv) { @autoreleasepool {
    strings = [NSBundle bundleWithPath:@(argv[1])];
    method_setImplementation(class_getClassMethod(NSBundle.class, @selector(mainBundle)), (IMP)StringsBundle);
    [NSApplication sharedApplication];
    [NSApp setActivationPolicy:NSApplicationActivationPolicyProhibited];
    method_setImplementation(class_getInstanceMethod(NSApplication.class, @selector(mainWindow)), (IMP)MainWindow);
    defaults = [TSMemoryDefaults new];
    documentsForTest = [NSMutableArray array];
    FakeChecker *checker = [FakeChecker sharedSpellChecker];
    NSArray *available = @[@"en", @"en_GB", @"en_AU", @"de", @"fr", @"pt_BR", @"pt_PT", @"ja"];

    // Names and matching.
    Check([TSSpellingLanguageDisplayName(@"en") isEqual:@"English (United States)"], "en is U.S. English");
    Check([TSSpellingLanguageDisplayName(@"en_GB") isEqual:@"English (United Kingdom)"], "en_GB in its own language");
    Check([TSSpellingLanguageDisplayName(@"de") isEqual:@"Deutsch"] && [TSSpellingLanguageDisplayName(@"fr") isEqual:@"Français"], "Languages are shown in their own names, capitalized");
    Check([TSSpellingLanguageDisplayName(@"ja") isEqual:@"日本語"], "Japanese in its own name");
    NSDictionary *matches = @{@"en": @"en", @"en_US": @"en", @"en-US": @"en", @" en_us ": @"en", @"English": @"en", @"english": @"en",
                              @"German": @"de", @"de_DE": @"de", @"en_GB": @"en_GB", @"en-GB": @"en_GB", @"en_NZ": @"en", @"pt_BR": @"pt_BR"};
    for (NSString *stored in matches) Check([TSSpellingLanguageMatching(stored, available) isEqual:matches[stored]], stored.UTF8String);
    for (NSString *stored in @[@"", @" ", @"pt", @"xx", @"xx_YY", @"Automatic Language"]) Check(TSSpellingLanguageMatching(stored, available) == nil, "No match for an unknown value");

    // Stored automatic titles of every localization (5.60 beta-3 to beta-9).
    NSUInteger titles = 0;
    for (NSString *localization in NSBundle.mainBundle.localizations) {
        NSString *path = [NSBundle.mainBundle pathForResource:@"Localizable" ofType:@"strings" inDirectory:nil forLocalization:localization];
        NSString *title = [NSDictionary dictionaryWithContentsOfFile:path][@"Automatic Language"];
        if (!title) continue;
        titles++;
        NSString *language = @"unset";
        [defaults setBool:NO forKey:spellingAutomaticDefaultKey]; [defaults setObject:title forKey:spellingLanguageDefaultKey];
        Check(TSSpellingDefaultIsAutomatic(defaults, nil, &language) && language.length == 0, title.UTF8String);
    }
    Check(titles == 12, "Twelve localized automatic titles");
    NSString *language = nil;
    [defaults setObject:@"de" forKey:spellingLanguageDefaultKey];
    Check(!TSSpellingDefaultIsAutomatic(defaults, nil, &language) && [language isEqual:@"de"], "A stored identifier is not automatic");
    [defaults setBool:YES forKey:spellingAutomaticDefaultKey];
    Check(TSSpellingDefaultIsAutomatic(defaults, nil, &language) && language.length == 0, "Automatic detection");

    // A document follows the dictionary chosen in Settings, also while open.
    ChooseInSettings(@"en_US");
    ProbeDocument *a = NewDocument();
    Check(a.spellLanguageFollowsDefault && [a.spellLanguage isEqual:@"en"] && !a.automaticSpelling, "New document takes the Settings choice as the checker names it");
    [a becomeMain];
    Check([checker.language isEqual:@"en"] && !checker.automaticallyIdentifiesLanguages, "Main document gives the checker its language");
    [a resignMain];
    Check(a.spellLanguageFollowsDefault, "The checker's own name for the language is not a panel choice");
    ChooseInSettings(@"de");
    Check([a.spellLanguage isEqual:@"de"] && [checker.language isEqual:@"en"], "Open document takes the new choice; the checker changes when it is main");
    [a becomeMain];
    Check([checker.language isEqual:@"de"], "The new choice reaches the checker");
    ChooseInSettings(@"en_GB");
    Check([checker.language isEqual:@"en_GB"], "A change while the document is main reaches the checker at once");
    ChooseInSettings(nil);
    Check(a.automaticSpelling && checker.automaticallyIdentifiesLanguages && [checker.language isEqual:@"en_GB"], "Automatic detection reaches an open document");
    [checker reportLanguage:@"ja"];   // Automatic detection may report another language.
    [a resignMain];
    Check(a.spellLanguageFollowsDefault, "Automatic detection is not a panel choice");

    // A language chosen in the Spelling panel belongs to that document.
    ChooseInSettings(@"en");
    [a becomeMain];
    [checker setLanguage:@"fr"];
    [a resignMain];
    Check(!a.spellLanguageFollowsDefault && [a.spellLanguage isEqual:@"fr"], "Panel choice is kept by the document");
    ChooseInSettings(@"de");
    Check([a.spellLanguage isEqual:@"fr"], "A Settings change does not replace a panel choice");
    [a becomeMain];
    Check([checker.language isEqual:@"fr"], "The panel choice comes back with the document");
    [a resignMain];
    ProbeDocument *b = NewDocument();
    Check([b.spellLanguage isEqual:@"de"], "Other new documents use Settings");
    [b becomeMain];
    checker.automaticallyIdentifiesLanguages = YES;
    [b resignMain];
    Check(!b.spellLanguageFollowsDefault && b.automaticSpelling, "Turning on automatic detection in the panel is a panel choice");

    // Stored values that Settings reads as an installed language are given to the
    // checker as that language, also when the checker would not take them.
    NSDictionary *stored = @{@"en_US": @"en", @" en_us ": @"en", @"english": @"en", @"german": @"de", @"German": @"de", @"de_DE": @"de"};
    for (NSString *value in stored) {
        [defaults setBool:NO forKey:spellingAutomaticDefaultKey]; [defaults setObject:value forKey:spellingLanguageDefaultKey];
        [checker setLanguage:@"fr"];
        ProbeDocument *d = NewDocument();
        [d becomeMain];
        Check([checker.language isEqual:stored[value]], value.UTF8String);
        [d resignMain];
        Check(d.spellLanguageFollowsDefault && [d.spellLanguage isEqual:stored[value]], "The document keeps following Settings");
        ChooseInSettings(@"en_GB"); [checker setLanguage:@"fr"];
        [defaults setObject:value forKey:spellingLanguageDefaultKey];
        [[NSNotificationCenter defaultCenter] postNotificationName:TSSpellingLanguageChangedNotification object:nil];
        [d becomeMain];
        Check([checker.language isEqual:stored[value]], "A changed stored value is read the same way");
        [d resignMain];
    }
    // A dictionary that is not installed: the checker keeps its language, and the
    // document still follows Settings.
    ChooseInSettings(@"tlh_XX");
    ProbeDocument *missing = NewDocument();
    [missing becomeMain];
    [missing resignMain];
    Check(missing.spellLanguageFollowsDefault, "A language the checker refuses is not a panel choice");
    ChooseInSettings(@"de");
    Check([missing.spellLanguage isEqual:@"de"], "The document follows the next Settings choice");
    [defaults setObject:@"tlh_XX" forKey:spellingLanguageDefaultKey];
    language = nil;
    Check(!TSSpellingDefaultIsAutomatic(defaults, @[@"en"], &language) && [language isEqual:@"tlh_XX"], "An unknown stored value is not replaced");

    // "% !TEX spellcheck" lines.
    ChooseInSettings(@"en");
    ProbeDocument *c = NewDocument();
    [c becomeMain];
    ProbeDocument *opening = NewDocument();
    NSUInteger sets = checker.sets;
    [opening applySpellcheckLine:@"de_DE"];
    Check(checker.sets == sets && [checker.language isEqual:@"en"], "Opening a file does not change the main document's language");
    [c resignMain];
    Check(c.spellLanguageFollowsDefault && [c.spellLanguage isEqual:@"en"], "The main document keeps its language");
    [opening becomeMain];
    Check([checker.language isEqual:@"de"], "The line applies when its document is main");
    [opening applySpellcheckLine:@"fr"];
    Check([checker.language isEqual:@"fr"], "A line read while the document is main applies at once");
    [opening resignMain];
    ChooseInSettings(@"en_GB");
    Check(!opening.spellLanguageFollowsDefault && [opening.spellLanguage isEqual:@"fr"], "A line wins over Settings");
    Check([c.spellLanguage isEqual:@"en_GB"], "Documents without a line follow");

    // The hidden OriginalSpelling setting leaves the checker alone.
    [defaults setBool:YES forKey:originalSpellingKey];
    sets = checker.sets;
    ProbeDocument *original = NewDocument();
    [original becomeMain];
    ChooseInSettings(@"de");
    [original resignMain];
    Check(checker.sets == sets, "OriginalSpelling never sets the checker");
    [defaults setBool:NO forKey:originalSpellingKey];

    // At launch the checker has the Settings choice before any document is main.
    for (ProbeDocument *d in [documentsForTest copy]) [d close];
    mainWindowForTest = nil;
    [defaults setBool:NO forKey:spellingAutomaticDefaultKey]; [defaults setObject:@"en_US" forKey:spellingLanguageDefaultKey];
    [checker reportLanguage:@"fr"]; checker.automaticallyIdentifiesLanguages = YES;
    ProbeAppDelegate *app = [ProbeAppDelegate new];
    [app applicationWillFinishLaunching];
    Check([checker.language isEqual:@"en"] && !checker.automaticallyIdentifiesLanguages, "At launch the checker has the Settings choice");
    NSDictionary *atLaunch = @{@"german": @"de", @" en-GB ": @"en_GB", @"de_DE": @"de"};
    for (NSString *value in atLaunch) {
        [defaults setObject:value forKey:spellingLanguageDefaultKey];
        [checker reportLanguage:@"fr"]; checker.automaticallyIdentifiesLanguages = YES;
        [ProbeDocument applySpellingDefaultUnlessDocumentIsMain];
        Check([checker.language isEqual:atLaunch[value]] && !checker.automaticallyIdentifiesLanguages, value.UTF8String);
    }
    for (NSString *value in @[@" ", @"Automatic Language", @"言語を自動判別"]) {
        [defaults setBool:[value isEqual:@" "] forKey:spellingAutomaticDefaultKey]; [defaults setObject:value forKey:spellingLanguageDefaultKey];
        [checker reportLanguage:@"fr"]; checker.automaticallyIdentifiesLanguages = NO;
        sets = checker.sets;
        [ProbeDocument applySpellingDefaultUnlessDocumentIsMain];
        Check(checker.automaticallyIdentifiesLanguages && checker.sets == sets && [checker.language isEqual:@"fr"], "Automatic detection at launch");
    }
    // A dictionary that is not installed leaves the checker alone.
    [defaults setBool:NO forKey:spellingAutomaticDefaultKey]; [defaults setObject:@"tlh_XX" forKey:spellingLanguageDefaultKey];
    [checker reportLanguage:@"fr"]; checker.automaticallyIdentifiesLanguages = YES;
    sets = checker.sets;
    [ProbeDocument applySpellingDefaultUnlessDocumentIsMain];
    Check(checker.sets == sets && [checker.language isEqual:@"fr"] && checker.automaticallyIdentifiesLanguages, "An unknown dictionary does not change the checker at launch");

    // A document opened at launch, with a "% !TEX spellcheck" line or without, gets its own language.
    ChooseInSettings(@"en");
    Check([checker.language isEqual:@"en"] && !checker.automaticallyIdentifiesLanguages, "A Settings change with no document reaches the checker");
    ProbeDocument *texLine = NewDocument();
    [texLine applySpellcheckLine:@"de_DE"];
    Check([checker.language isEqual:@"en"], "The line waits for its document");
    [texLine becomeMain];
    Check([checker.language isEqual:@"de"], "The line wins over the launch choice");
    [texLine resignMain];   // Settings comes to the front.
    Check(!texLine.spellLanguageFollowsDefault && [texLine.spellLanguage isEqual:@"de"], "The line's document keeps its language");
    ProbeDocument *plain = NewDocument();
    [plain becomeMain];
    Check([checker.language isEqual:@"en"], "A document without a line uses Settings");
    [checker setLanguage:@"fr"];   // Chosen in the Spelling panel for this document.
    [plain resignMain];
    Check(!plain.spellLanguageFollowsDefault && [plain.spellLanguage isEqual:@"fr"], "Panel choice kept");

    // With Settings in front, a new choice reaches the checker; documents get theirs back.
    ProbeDocument *follower = NewDocument();
    [follower becomeMain]; [follower resignMain];
    ChooseInSettings(@"en_GB");
    Check([checker.language isEqual:@"en_GB"], "A Settings change with no document main reaches the checker at once");
    [texLine becomeMain];
    Check([checker.language isEqual:@"de"], "The TeX line document gets its language back");
    [texLine resignMain];
    Check(!texLine.spellLanguageFollowsDefault && [texLine.spellLanguage isEqual:@"de"], "Returning is not a panel choice");
    [plain becomeMain];
    Check([checker.language isEqual:@"fr"], "The panel choice comes back");
    [plain resignMain];
    Check([plain.spellLanguage isEqual:@"fr"], "The panel choice is kept");
    [follower becomeMain];
    Check([checker.language isEqual:@"en_GB"], "A following document has the new choice");
    [follower resignMain];
    Check(follower.spellLanguageFollowsDefault, "The Settings choice applied without a document is not a panel choice");
    ChooseInSettings(nil);
    Check(checker.automaticallyIdentifiesLanguages, "Automatic detection chosen with no document main");
    [follower becomeMain]; [follower resignMain];
    Check(follower.spellLanguageFollowsDefault && follower.automaticSpelling, "Still following");

    // While a document is main, only that document decides the checker's language.
    ChooseInSettings(@"en");
    [plain becomeMain];
    sets = checker.sets;
    ChooseInSettings(@"de");
    Check(checker.sets == sets && [checker.language isEqual:@"fr"], "A Settings change does not reach the checker under a document's own language");
    [plain resignMain];
    Check(!plain.spellLanguageFollowsDefault && [plain.spellLanguage isEqual:@"fr"], "The main document keeps its language");
    [follower becomeMain];
    ChooseInSettings(@"en_GB");
    Check([checker.language isEqual:@"en_GB"], "A following main document takes the change");
    [follower resignMain];
    Check(follower.spellLanguageFollowsDefault, "Not a panel choice");

    // Closing documents: the checker returns to Settings when none is main.
    [plain becomeMain];
    [follower close];   // A document in the background closes.
    Check([checker.language isEqual:@"fr"], "Closing another document leaves the main document's language");
    [plain resignMain];
    [plain close];
    Check([checker.language isEqual:@"en_GB"] && !checker.automaticallyIdentifiesLanguages, "After closing, no document is main: Settings");
    [texLine becomeMain];
    [texLine resignMain];
    [texLine close];
    Check(documentsForTest.count == 0 && [checker.language isEqual:@"en_GB"], "After the last document the checker has the Settings choice");

    // The hidden OriginalSpelling setting: TeXShop leaves the checker alone at launch,
    // on a Settings change and after closing.
    [defaults setBool:YES forKey:originalSpellingKey];
    [checker reportLanguage:@"fr"]; checker.automaticallyIdentifiesLanguages = YES;
    sets = checker.sets;
    [app applicationWillFinishLaunching];
    ChooseInSettings(@"de");
    ProbeDocument *last = NewDocument();
    [last becomeMain]; [last resignMain]; [last close];
    Check(checker.sets == sets && [checker.language isEqual:@"fr"] && checker.automaticallyIdentifiesLanguages, "OriginalSpelling leaves the checker alone");
    [defaults setBool:NO forKey:originalSpellingKey];
    [[NSNotificationCenter defaultCenter] removeObserver:app];

    if (failures) return 1;
    puts("PASS: language names, stored values, automatic titles, open documents follow Settings, panel choices and TeX lines kept, Settings choice with no document main");
} return 0; }
'''
program = (program.replace('@@HEADER@@', header.replace('#import "globals.h"\n', ''))
           .replace('@@INIT@@', init_block).replace('@@TEX@@', tex_block).replace('@@METHODS@@', '\n'.join(methods))
           .replace('@@CLOSE@@', close_tail).replace('@@LAUNCH@@', launch_block).replace('@@DELEGATE@@', delegate_method))
if not args.mutation:
    verify_embedded(program, [('complete method:' + m.split('\n')[0], document, m) for m in methods] +
                    [('init statements', document, init_block), ('TeX line statements', document, tex_block),
                     ('header', header, header[header.index('NS_ASSUME_NONNULL_BEGIN'):]),
                     ('close statements', document, close_tail), ('launch statements', delegate, launch_block),
                     ('complete method: TSAppDelegate spellingLanguageDefaultChanged:', delegate, delegate_method)])

with tempfile.TemporaryDirectory(prefix='texshop-spelling-dictionary-') as temp:
    t = Path(temp)
    bundle = t/'Strings.bundle'/'Contents'
    bundle.mkdir(parents=True)
    (bundle/'Info.plist').write_bytes(plistlib.dumps({'CFBundleIdentifier': 'org.texshop.tests.spelling-dictionary',
        'CFBundlePackageType': 'BNDL', 'CFBundleDevelopmentRegion': 'en'}))
    for strings in sorted((root/'Resources/Interfaces').glob('*.lproj/Localizable.strings')):
        target = bundle/'Resources'/strings.parent.name
        target.mkdir(parents=True)
        shutil.copy2(strings, target/'Localizable.strings')
    (t/'probe.m').write_text(program)
    subprocess.run(['xcrun', 'clang', '-fobjc-arc', '-Wno-deprecated-declarations', *include_args(root), '-I', str(root/'Tests'),
                    '-framework', 'Cocoa', str(t/'probe.m'), '-o', str(t/'probe')], check=True)
    result = subprocess.run([str(t/'probe'), str(t/'Strings.bundle')], timeout=60)
    if args.mutation:
        print('MUTATION', args.mutation, 'FAILED AS INTENDED' if result.returncode else 'NOT DETECTED')
        sys.exit(0 if result.returncode else 1)
    sys.exit(result.returncode)
