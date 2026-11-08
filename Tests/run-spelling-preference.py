#!/usr/bin/env python3
"""Check the production spelling preference, file scope, live saving, and factory presets.
Uses in-memory defaults; does not start TeXShop or touch spelling dictionaries.
"""
from pathlib import Path
import plistlib, subprocess, tempfile
from pane_fixtures import bundles, sources
root = Path(__file__).resolve().parents[1]
def method(path, signature):
    source = (root / path).read_text()
    start = source.index(signature)
    opening = source.index('{', start)
    depth = 1
    end = opening + 1
    while depth:
        depth += (source[end] == '{') - (source[end] == '}')
        end += 1
    return source[start:end]
methods = '\n'.join(method('Sources/TSPreferences.m', signature) for signature in [
    '- (void)updateSpellingControlsFromDefaults:', '- (IBAction)texAwareSpellCheckPressed:'])
scope = method('Sources/TSTextView.m', '- (BOOL)usesTeXAwareSpellChecking')
for p in (root / 'Resources/Shellscripts').glob('*Defaults*.plist'):
    assert plistlib.loads(p.read_bytes())['TeXAwareSpellChecking'] is True, p
program = r'''
#import <Cocoa/Cocoa.h>
#import "TestAppKitIsolation.h"
#define REQUIRE(x) do { if (!(x)) { NSLog(@"FAIL at line %d", __LINE__); exit(1); } } while(0)
@interface MemoryDefaults : NSUserDefaults
@property NSMutableDictionary *values;
@end
@implementation MemoryDefaults
- (BOOL)boolForKey:(NSString *)key { return self.values[key] ? [self.values[key] boolValue] : YES; }
- (void)setBool:(BOOL)value forKey:(NSString *)key { self.values[key] = @(value); }
- (void)setPersistentDomain:(NSDictionary *)domain forName:(NSString *)name { self.values = [domain mutableCopy]; }
- (BOOL)synchronize { return YES; }
@end
static MemoryDefaults *settings;
#define SUD settings
#define MakeatletterEnabledKey @"MakeatletterEnabled"
static NSString *TSPreferencesDomainName(void) { return @"test.memory"; }
static int refreshes;
@interface TSSpellSupport:NSObject
+ (void)preferencesDidChange;
@end
@implementation TSSpellSupport
+ (void)preferencesDidChange { refreshes++; }
@end
@interface PreferenceProbe:NSObject {
@public

    NSButton *_texAwareSpellCheckButton, *_editSpellingExclusionsButton;
    NSButtonCell *_spellCheckCommands, *_spellCheckParameters, *_spellCheckComments;
}
@end
@interface PreferenceProbe (LegacyProbe)
@property NSButton *legacySpellCheckButton;
@end
@implementation PreferenceProbe
- (NSButton *)legacySpellCheckButton { return nil; }
- (void)cancelForColor {}
- (void)cancelEnginePathDiscovery {}
- (void)updateControlsFromUserDefaults:(NSUserDefaults *)defaults { [self updateSpellingControlsFromDefaults:defaults]; }
METHODS
@end
static int isTeX = 1;
static unichar g_texChar = '\\';
@interface DocumentProbe:NSObject
@property int documentType;
@property NSURL *fileURL;
@end
@implementation DocumentProbe
@end
@interface ViewProbe:NSObject
@property DocumentProbe *document;
@end
@implementation ViewProbe
SCOPE
@end
int main(void) { @autoreleasepool {
    TSInstallAppKitIsolation();
    settings = [MemoryDefaults new]; settings.values = [NSMutableDictionary dictionary];
    PreferenceProbe *p = [PreferenceProbe new];

    p->_texAwareSpellCheckButton = [NSButton new];
    p->_editSpellingExclusionsButton = [NSButton new];
    p->_spellCheckCommands = [NSButtonCell new];
    p->_spellCheckParameters = [NSButtonCell new];
    p->_spellCheckComments = [NSButtonCell new];
    [p updateSpellingControlsFromDefaults:settings];
    REQUIRE(p->_texAwareSpellCheckButton.state == NSControlStateValueOn);
    REQUIRE(!p->_spellCheckComments.enabled);
    REQUIRE(p->_editSpellingExclusionsButton.enabled);
    [settings setBool:NO forKey:@"SpellCheckEnabled"];
    [settings setBool:YES forKey:@"TurnOffCommandSpellCheck"];
    [settings setBool:NO forKey:@"TurnOffParameterSpellCheck"];
    [settings setBool:YES forKey:@"TurnOffCommentSpellCheck"];
    for (NSNumber *initial in @[@YES, @NO]) {
        [settings setBool:initial.boolValue forKey:@"TeXAwareSpellChecking"];

        p->_texAwareSpellCheckButton.state = !initial.boolValue;
        [p texAwareSpellCheckPressed:p->_texAwareSpellCheckButton];
        REQUIRE([settings boolForKey:@"TeXAwareSpellChecking"] == !initial.boolValue);
        REQUIRE(p->_spellCheckCommands.enabled == initial.boolValue);
        REQUIRE(p->_spellCheckParameters.enabled == initial.boolValue);
        REQUIRE(p->_spellCheckComments.enabled == initial.boolValue);
        REQUIRE(p->_editSpellingExclusionsButton.enabled == !initial.boolValue);

        [p updateSpellingControlsFromDefaults:settings];
        REQUIRE([settings boolForKey:@"TeXAwareSpellChecking"] == !initial.boolValue);
        REQUIRE(p->_texAwareSpellCheckButton.state == !initial.boolValue);
        REQUIRE(![settings boolForKey:@"SpellCheckEnabled"]);
        REQUIRE([settings boolForKey:@"TurnOffCommandSpellCheck"]);
        REQUIRE(![settings boolForKey:@"TurnOffParameterSpellCheck"]);
        REQUIRE([settings boolForKey:@"TurnOffCommentSpellCheck"]);
    }
    REQUIRE(refreshes == 2);
    puts("PASS: reloading controls keeps the saved choice; child settings follow the selected mode");
    ViewProbe *v = [ViewProbe new];
    [settings setBool:YES forKey:@"TeXAwareSpellChecking"];
    REQUIRE(![v usesTeXAwareSpellChecking]);
    v.document = [DocumentProbe new]; v.document.documentType = isTeX;
    REQUIRE([v usesTeXAwareSpellChecking]);
    for (NSString *ext in @[@"tex", @"TEX", @"ltx", @"latex", @"dtx", @"ins", @"sty", @"cls", @"clo", @"bbx", @"cbx", @"lbx"]){
        v.document.fileURL = [NSURL fileURLWithPath:[@"/tmp/document." stringByAppendingString:ext]];
        REQUIRE([v usesTeXAwareSpellChecking]);
    }
    for (NSString *ext in @[@"txt", @"md", @"py", @"sh", @"xml", @"html", @"lua", @"typ", @"adoc", @"bib", @"pdf", @""]){
        v.document.fileURL = [NSURL fileURLWithPath:[@"/tmp/document." stringByAppendingString:ext]];
        REQUIRE(![v usesTeXAwareSpellChecking]);
    }
    v.document.fileURL = [NSURL fileURLWithPath:@"/tmp/document.tex"];
    [settings setBool:NO forKey:@"TeXAwareSpellChecking"];
    REQUIRE(![v usesTeXAwareSpellChecking]);
    [settings setBool:YES forKey:@"TeXAwareSpellChecking"];
    v.document.documentType = 2; REQUIRE(![v usesTeXAwareSpellChecking]);
    v.document.documentType = isTeX; g_texChar = 0xa5; REQUIRE(![v usesTeXAwareSpellChecking]);
    puts("PASS: default ON, explicit OFF, live saving, independent continuous spelling, and TeX-only scope");
} }
'''.replace('METHODS', methods).replace('SCOPE', scope)
with tempfile.TemporaryDirectory(prefix='texshop-spelling-preference-') as td:
    t = Path(td); (t/'probe.m').write_text(program)
    subprocess.run(['xcrun','clang','-fobjc-arc','-I',str(root/'Tests'),'-framework','Cocoa',str(t/'probe.m'),'-o',str(t/'probe')],check=True)
    subprocess.run([str(t/'probe')],check=True)

    subprocess.run(['xcrun','clang','-fobjc-arc','-framework','Cocoa',
        '-I',str(root/'Sources'),str(root/'Tests/SpellCheck/preferences.m'),*map(str,sources(root,('Source',))),'-o',str(t/'nibs')],check=True)
    nibs = bundles(root,t,('Source',))
    assert len(nibs) == 12
    subprocess.run([str(t/'nibs'), *map(str,nibs)],check=True)
