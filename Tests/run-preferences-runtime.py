#!/usr/bin/env python3
"""Exercise preference actions without an application, windows, or persistent defaults."""
from pathlib import Path
import re
import subprocess
import tempfile
import sys

ROOT = Path(__file__).resolve().parents[1]
source = (ROOT / 'Sources/TSPreferences.m').read_text()

def method(signature):
    start = source.index(signature)
    return source[start:source.index('\n}', start) + 2]

xml_names = ['Chapter', 'Section', 'Subsection', 'Subsubsection', 'Introduction',
             'Conclusion', 'Exercises', 'Project', 'Figure', 'Table', 'Mark']
actions = [method('- (IBAction)XML' + name + 'ButtonChanged:') for name in xml_names]
editor = method('- (IBAction)editorAddBracketsPressed:')
refresh = method('- (void)refreshRuntimePreferences\n')
delegate_source = (ROOT / 'Sources/TSAppDelegate.m').read_text(encoding='latin1')
start = delegate_source.index('- (void)updateXMLTabs\n')
xml_reader = delegate_source[start:delegate_source.index('\n}', start) + 2]
xml_reader = xml_reader.replace('updateXMLTabs', 'readXMLDefaults', 1)
assert '[self refreshRuntimePreferences];' in method('- (void)applyPreferenceProfile:')
assert 'cancelButtonPressed:' not in source and 'undoDefaultPrefs:' not in source

mutation = sys.argv[1] if len(sys.argv) > 1 else ''
if mutation.startswith('xml-'):
    index = xml_names.index(mutation[4:])
    assert '[(TSAppDelegate *)NSApp.delegate updateXMLTabs];' in actions[index]
    actions[index] = actions[index].replace('[(TSAppDelegate *)NSApp.delegate updateXMLTabs];', '')
elif mutation in ('editor', 'refresh-editor', 'refresh-xml'):
    snippet = ('[(TSAppDelegate *)NSApp.delegate updateXMLTabs];' if mutation == 'refresh-xml'
               else 'editorCanAddBrackets = [SUD boolForKey:EditorCanAddBracketsKey];')
    if mutation == 'editor':
        assert snippet in editor
        editor = editor.replace(snippet, '')
    else:
        assert snippet in refresh
        refresh = refresh.replace(snippet, '')
elif mutation:
    raise SystemExit('Unknown mutation: ' + mutation)

keys = {name + 'Key': name for name in ['EditorCanAddBrackets', 'AutoSaveEnabled', 'WatchServer', 'TagMenuInMenuBar', 'PdfPageBack_R', 'PdfPageBack_G', 'PdfPageBack_B']}
keys.update({'XML' + name + 'TagKey': 'XML' + name + 'Tag' for name in xml_names})
program = r'''
#import <Cocoa/Cocoa.h>
#import "MemoryDefaults.h"
TSMemoryDefaults *memory;
#define SUD memory
BOOL editorCanAddBrackets, doAutoSave, activateBauerPatch;
NSColor *PreviewBackgroundColor;
BOOL g_activeXMLTags[11];
KEYS
@interface TSAppDelegate : NSObject
@property NSUInteger updates;
@property NSDictionary<NSString *, NSNumber *> *xml;
- (void)updateXMLTabs;
- (void)readXMLDefaults;
@end
@implementation TSAppDelegate
XMLREADER
- (void)updateXMLTabs {
    self.updates++;
    NSMutableDictionary *result = [NSMutableDictionary dictionary];
    [self readXMLDefaults];
    NSUInteger index = 0;
    for (NSString *key in XMLKEYS) result[key] = @(g_activeXMLTags[index++]);
    self.xml = result;
}
@end
@interface FakeApp : NSObject
@property TSAppDelegate *delegate;
@property NSMenu *mainMenu;
@end
@implementation FakeApp @end
FakeApp *fakeApp;
#undef NSApp
#define NSApp fakeApp
// Stand-ins intentionally have no NSWindow, NSApplication, or NSButton lifecycle.
@interface Control : NSObject
@property NSControlStateValue state;
@property BOOL enabled;
- (id)selectedCell;
@end
@implementation Control
- (id)selectedCell { return self; }
@end
@interface Preferences : NSObject {
@public

}
@end
@implementation Preferences
METHODS
@end
static void check(BOOL success, const char *message) {
    if (!success) { fprintf(stderr, "FAIL: %s\n", message); exit(1); }
}
int main(void) { @autoreleasepool {
    memory = [TSMemoryDefaults new];
    fakeApp = [FakeApp new]; fakeApp.delegate = [TSAppDelegate new];
    Preferences *p = [Preferences new];

    Control *control = [Control new];
    // Both directions must update the already-running application without OK.
    for (NSNumber *value in @[@YES, @NO, @YES]) {
        BOOL flag = value.boolValue;
        control.state = flag;
        [p editorAddBracketsPressed:control];
        check([SUD boolForKey:EditorCanAddBracketsKey] == flag, "editor persisted");
        check(editorCanAddBrackets == flag, "editor runtime immediate");
        XMLTESTS
    }
    // A profile has already changed the source of truth. The
    // copied globals must follow it, not stale control states.
    for (NSNumber *value in @[@NO, @YES]) {
        BOOL flag = value.boolValue;
        [SUD setBool:flag forKey:EditorCanAddBracketsKey];
        [SUD setBool:flag forKey:AutoSaveEnabledKey];
        [SUD setObject:@0.25 forKey:PdfPageBack_RKey];
        for (NSString *key in XMLKEYS) [SUD setBool:flag forKey:key];
        NSUInteger count = fakeApp.delegate.updates;
        [p refreshRuntimePreferences];
        check(editorCanAddBrackets == flag && doAutoSave == flag, "bulk runtime refresh");
        check(fabs(PreviewBackgroundColor.redComponent - 0.25) < 0.001, "preview background copy");
        check(fakeApp.delegate.updates == count + 1, "bulk XML refresh once");
        for (NSString *key in XMLKEYS) check([fakeApp.delegate.xml[key] boolValue] == flag, "bulk XML value");
    }
    puts("PASS: immediate runtime copies, 11 XML controls, and bulk refresh");
} return 0; }
'''
xmlkeys = '@[' + ', '.join('XML' + name + 'TagKey' for name in xml_names) + ']'
xmltests = []
for name in xml_names:
    xmltests.append('''{
        NSUInteger count = fakeApp.delegate.updates;
        [p XMLNAMEButtonChanged:(id)control];
        check(fakeApp.delegate.updates == count + 1, "XML NAME notification");
        check([SUD boolForKey:XMLNAMETagKey] == flag &&
              [fakeApp.delegate.xml[XMLNAMETagKey] boolValue] == flag, "XML NAME saved before refresh");
    }'''.replace('NAME', name))
program = program.replace('XMLREADER', xml_reader)
program = program.replace('XMLKEYS', xmlkeys).replace('XMLTESTS', '\n'.join(xmltests))
program = program.replace('KEYS', '\n'.join('NSString *const %s = @"%s";' % pair for pair in keys.items()))
program = program.replace('METHODS', '\n'.join(actions + [editor, refresh]))
with tempfile.TemporaryDirectory(prefix='texshop-preferences-runtime-') as temp:
    src = Path(temp) / 'probe.m'
    src.write_text(program)
    binary = Path(temp) / 'probe'
    subprocess.run(['xcrun', 'clang', '-fobjc-arc', '-Wall', '-Wextra', '-Werror',
                    '-Wno-unused-parameter', '-I', str(ROOT / 'Tests'), '-framework', 'Cocoa',
                    str(src), '-o', str(binary)], check=True)
    subprocess.run([str(binary)], check=True)
