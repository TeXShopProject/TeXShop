#!/usr/bin/env python3
"""Press Change in the real Spelling and Grammar panel, which also searches on.
Uses the production TSSpellSupport and the production -changeSpelling:,
-checkSpelling: and -showGuessPanel: of TSTextView on a real NSTextView. The
panel is never ordered on screen; finding, guessing and the language are
stand-ins, and learning, unlearning or ignoring a word aborts the test.
"""
import argparse, os, subprocess, tempfile
from pathlib import Path
from production_fragments import method, verify_embedded
from source_tree import include_args
root = Path(__file__).resolve().parents[1]
p = argparse.ArgumentParser()
p.add_argument('--mutation', choices=['no-guard', 'no-skip', 'skip-sticky'])
args = p.parse_args()
view_source = (root/'Sources/Editor/TSTextView.m').read_text(encoding='latin1')
support_source = (root/'Sources/Editor/TSSpellSupport.m').read_text(encoding='utf-8')
change = method(view_source, '- (void)changeSpelling:(id)sender')
check = method(view_source, '- (void)checkSpelling:(id)sender')
guess = method(view_source, '- (void)showGuessPanel:(id)sender')
program = r'''
#import <Cocoa/Cocoa.h>
#import "TestAppKitIsolation.h"
#import "TSSpellSupport.h"
#import "TSSpellExclusions.h"
#define REQUIRE(x, what) do { if (!(x)) { fprintf(stderr, "FAIL: %s\n", what); exit(1); } } while(0)
static NSEventModifierFlags flags;
static NSEventModifierFlags TestModifierFlags(id o, SEL s) { return flags; }
static NSString *Language(id o, SEL s) { return @"en"; }
static NSArray *Languages(id o, SEL s) { return @[@"en"]; }
static NSArray *Guesses(id o, SEL s, NSRange r, NSString *t, NSString *l, NSInteger tag) { return @[@"fixed"]; }
static NSRange Find(id o, SEL s, NSString *t, NSInteger start, NSString *l, BOOL wrap, NSInteger tag, NSInteger *count)
{ return [t rangeOfString:@"zzqq[ab]" options:NSRegularExpressionSearch range:NSMakeRange(start, t.length - start)]; }
static void NoLearn(id o, SEL s, NSString *w) { fputs("FORBIDDEN dictionary change\n", stderr); abort(); }
static void NoIgnore(id o, SEL s, NSString *w, NSInteger tag) { fputs("FORBIDDEN ignore\n", stderr); abort(); }
static NSWindow *documentWindow;
@interface PanelApplication : NSApplication @end
@implementation PanelApplication
- (NSWindow *)mainWindow { return documentWindow; }
- (NSWindow *)keyWindow { return documentWindow; }
@end
@interface PanelWindow : NSWindow @end
@implementation PanelWindow
- (BOOL)canBecomeMainWindow { return YES; }
@end
@interface PanelTextView : NSTextView
@property BOOL texAware;
@end
@implementation PanelTextView
- (BOOL)usesTeXAwareSpellChecking { return self.texAware; }
- (TSSpellMask *)freshSpellMask { return [[TSSpellExclusions sharedExclusions] maskForText:self.string]; }
- (void)showFindIndicatorForRange:(NSRange)range {}
CHANGE
CHECK
GUESS
@end
static PanelTextView *View(NSString *text, BOOL texAware) {
    NSWindow *w = [[PanelWindow alloc] initWithContentRect:NSMakeRect(0,0,600,400) styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
    w.releasedWhenClosed = NO;
    PanelTextView *v = [[PanelTextView alloc] initWithFrame:NSMakeRect(0,0,600,400)];
    w.contentView = v; v.texAware = texAware; v.string = text; v.allowsUndo = YES;
    v.continuousSpellCheckingEnabled = NO; v.grammarCheckingEnabled = NO; v.automaticSpellingCorrectionEnabled = NO;
    documentWindow = w; [w makeMainWindow]; [w makeFirstResponder:v];
    return v;
}
static void Front(NSTextView *v) { documentWindow = v.window; [v.window makeMainWindow]; [v.window makeFirstResponder:v]; }
static NSPanel *Panel(void) { return NSSpellChecker.sharedSpellChecker.spellingPanel; }
static id Control(NSView *view, Class cls, NSString *title) {
    if ([view isKindOfClass:cls] && (!title || [[(id)view title] isEqual:title])) return view;
    for (NSView *child in view.subviews) { id found = Control(child, cls, title); if (found) return found; }
    return nil;
}
static NSTextField *WordField(void) {
    NSTextField *field = nil;
    for (NSView *child in Panel().contentView.subviews) if ([child isKindOfClass:NSTextField.class]) field = (id)child;
    return field;
}
static NSString *Status(void) {
    for (NSView *child in NSSpellChecker.sharedSpellChecker.accessoryView.subviews)
        if ([child isKindOfClass:NSTextField.class] && ![(NSTextField *)child isEditable]) return [(NSTextField *)child stringValue];
    return nil;
}
static void PressChange(void) {
    WordField().stringValue = @"fixed";
    [(NSButton *)Control(Panel().contentView, NSButton.class, @"Change") performClick:nil];
}
static void FinishAction(void) { [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.05]]; }
int main(void) { @autoreleasepool {
    TSInstallAppKitIsolation(); [PanelApplication sharedApplication];
    [NSApp setActivationPolicy:NSApplicationActivationPolicyProhibited];
    class_replaceMethod(NSSpellChecker.class, @selector(language), (IMP)Language, "@@:");
    class_replaceMethod(NSSpellChecker.class, @selector(availableLanguages), (IMP)Languages, "@@:");
    method_setImplementation(class_getInstanceMethod(NSSpellChecker.class, @selector(guessesForWordRange:inString:language:inSpellDocumentWithTag:)), (IMP)Guesses);
    method_setImplementation(class_getInstanceMethod(NSSpellChecker.class, @selector(checkSpellingOfString:startingAt:language:wrap:inSpellDocumentWithTag:wordCount:)), (IMP)Find);
    method_setImplementation(class_getInstanceMethod(NSSpellChecker.class, @selector(learnWord:)), (IMP)NoLearn);
    method_setImplementation(class_getInstanceMethod(NSSpellChecker.class, @selector(unlearnWord:)), (IMP)NoLearn);
    method_setImplementation(class_getInstanceMethod(NSSpellChecker.class, @selector(ignoreWord:inSpellDocumentWithTag:)), (IMP)NoIgnore);
    method_setImplementation(class_getClassMethod(NSEvent.class, @selector(modifierFlags)), (IMP)TestModifierFlags);

    PanelTextView *v = View(@"zzqqa other zzqqb", YES);
    [v checkSpelling:nil];
    REQUIRE(NSEqualRanges(v.selectedRange, NSMakeRange(0,5)), "Find Next shows the first word");
    REQUIRE([[(NSButton *)Control(Panel().contentView, NSButton.class, @"Change") target] isKindOfClass:NSSpellChecker.class], "Change belongs to the system panel");

    // Change on the word just found replaces it, and the button goes on to the next one.
    PressChange(); FinishAction();
    REQUIRE([v.string isEqual:@"fixed other zzqqb"], "Change replaces the word just found");
    REQUIRE(NSEqualRanges(v.selectedRange, NSMakeRange(12,5)), "after Change the panel goes on to the next word");

    // Other text selected: nothing is replaced, the panel does not move on,
    // and the notice stays.
    v.string = @"zzqqa other zzqqb"; v.selectedRange = NSMakeRange(0,0); [v checkSpelling:nil]; FinishAction();
    v.selectedRange = NSMakeRange(6,5);
    PressChange();
    REQUIRE([v.string isEqual:@"zzqqa other zzqqb"], "a refused Change replaces nothing");
    REQUIRE(NSEqualRanges(v.selectedRange, NSMakeRange(6,5)), "a refused Change leaves the selection");
    REQUIRE(Status().length > 0, "a refused Change leaves its notice");
    FinishAction();
    REQUIRE(Status().length > 0, "the notice stays after the action");
    // Return in the panel's word field presses Change too.
    NSTextField *word = WordField(); word.stringValue = @"fixed";
    [NSApp sendAction:word.action to:word.target from:word];
    REQUIRE([v.string isEqual:@"zzqqa other zzqqb"] && NSEqualRanges(v.selectedRange, NSMakeRange(6,5)), "Return in the word field is refused alike");
    FinishAction();
    // A later Find Next is not skipped.
    [v checkSpelling:nil];
    REQUIRE(NSEqualRanges(v.selectedRange, NSMakeRange(12,5)) && Status().length == 0, "Find Next after a refusal works");
    PressChange(); FinishAction();
    REQUIRE([v.string isEqual:@"zzqqa other fixed"], "Change works again after Find Next");

    // A refused Change sent without the panel's search must not swallow a later Find Next.
    v.string = @"zzqqa other zzqqb"; v.selectedRange = NSMakeRange(0,0); [v checkSpelling:nil]; FinishAction();
    v.selectedRange = NSMakeRange(6,5);
    NSMatrix *sender = [[NSMatrix alloc] initWithFrame:NSMakeRect(0,0,100,30) mode:NSRadioModeMatrix prototype:[NSTextFieldCell new] numberOfRows:1 numberOfColumns:1];
    sender.selectedCell.stringValue = @"fixed";
    [v changeSpelling:sender]; FinishAction();
    [v checkSpelling:nil];
    REQUIRE(NSEqualRanges(v.selectedRange, NSMakeRange(12,5)), "Find Next after a direct refusal works");

    // Another document without TeX-aware checking: refused while the review
    // belongs to the first document; its own system search then allows Change.
    v.string = @"zzqqa other zzqqb"; v.selectedRange = NSMakeRange(0,0); [v checkSpelling:nil]; FinishAction();
    PanelTextView *plain = View(@"zzqqb", NO); plain.selectedRange = NSMakeRange(0,5);
    PressChange(); FinishAction();
    REQUIRE([plain.string isEqual:@"zzqqb"] && NSEqualRanges(plain.selectedRange, NSMakeRange(0,5)), "Change in another document is refused and stays");
    plain.selectedRange = NSMakeRange(0,0); [plain checkSpelling:nil]; FinishAction();
    REQUIRE(NSEqualRanges(plain.selectedRange, NSMakeRange(0,5)), "the system search finds the word");
    PressChange(); FinishAction();
    REQUIRE([plain.string isEqual:@"fixed"], "Change works after the system search");

    // Option: the system search ends the review, and its Change works.
    Front(v); v.string = @"zzqqa other zzqqb"; v.selectedRange = NSMakeRange(0,0); [v checkSpelling:nil]; FinishAction();
    v.selectedRange = NSMakeRange(6,0);
    flags = NSEventModifierFlagOption; [v checkSpelling:nil]; flags = 0; FinishAction();
    REQUIRE(NSEqualRanges(v.selectedRange, NSMakeRange(12,5)), "the Option search finds the next word");
    PressChange(); FinishAction();
    REQUIRE([v.string isEqual:@"zzqqa other fixed"], "Change works after the Option search");
    puts("PASS: real panel Change replaces the word found and moves on; a refused Change replaces nothing, stays put and keeps its notice; later Find Next works");
} return 0; }
'''.replace('CHANGE', change).replace('CHECK', check).replace('GUESS', guess)
verify_embedded(program, [('complete method: changeSpelling', view_source, change),
                          ('complete method: checkSpelling', view_source, check),
                          ('complete method: showGuessPanel', view_source, guess)])
support = support_source
if args.mutation == 'no-guard':
    old = 'if ([TSSpellSupport refuseStaleChangeInTextView:self]) return;'
    assert program.count(old) == 1; program = program.replace(old, '')
elif args.mutation == 'no-skip':
    old = 'if ([TSSpellSupport skipsSearchAfterRefusedChange]) return;'
    assert program.count(old) == 1; program = program.replace(old, '')
elif args.mutation == 'skip-sticky':
    old = '    dispatch_async(dispatch_get_main_queue(), ^{ sSkipSearchAfterRefusal = NO; });\n'
    assert support.count(old) == 1; support = support.replace(old, '')
with tempfile.TemporaryDirectory(prefix='texshop-spell-panel-change-') as td:
    t = Path(td); (t/'probe.m').write_text(program); (t/'support.m').write_text(support)
    subprocess.run(['xcrun', 'clang', '-fobjc-arc', '-DTSSPELL_STANDALONE_TEST', *include_args(root),
                    '-I'+str(root/'Tests'), '-framework', 'Cocoa', str(t/'probe.m'), str(t/'support.m'),
                    str(root/'Sources/Editor/TSSpellExclusions.m'), '-o', str(t/'probe')], check=True)
    subprocess.run([str(t/'probe')], check=True, timeout=60,
                   env=dict(os.environ, TSSPELL_RULES=str(root/'Resources/TeXShop/SpellCheck/SpellingExclusions.txt')))
