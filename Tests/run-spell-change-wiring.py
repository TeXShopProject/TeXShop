#!/usr/bin/env python3
"""Check how the text view's spelling actions use the review guard.
The panel's Change asks TSSpellSupport first; the search the panel's Change
button runs after a refused Change is skipped; the system's own search
(Option, or a view without TeX-aware checking) ends the TeX-aware review. Runs the
production methods against a recording stand-in; opens no panel or window.
The document's source (TSTextView) and the Experiment source (ScrapTextView)
are checked alike; --view runs only one of them.
"""
import argparse, subprocess, tempfile
from pathlib import Path
from production_fragments import method, verify_embedded
root = Path(__file__).resolve().parents[1]
p = argparse.ArgumentParser()
p.add_argument('--mutation', choices=['no-refuse', 'no-end-check', 'no-end-guess', 'end-tex-aware', 'no-skip', 'system-search'])
p.add_argument('--view', choices=['source', 'experiment'])
args = p.parse_args()
VIEWS = {'source': 'Sources/Editor/TSTextView.m', 'experiment': 'Sources/Editor/ScrapTextView.m'}
template = r'''
#import <Cocoa/Cocoa.h>
#import "TestAppKitIsolation.h"
#define REQUIRE(x, what) do { if (!(x)) { NSLog(@"FAIL: %s (%@)", what, steps); exit(1); } } while(0)
@class TSSpellMask;
static NSMutableArray<NSString *> *steps;
static BOOL refuse, skip, panelShown;
static NSEventModifierFlags flags;
static NSEventModifierFlags TestModifierFlags(id receiver, SEL selector) { return flags; }
@interface TSSpellSupport : NSObject @end
@implementation TSSpellSupport
+ (BOOL)refuseStaleChangeInTextView:(NSTextView *)view { [steps addObject:@"refuse?"]; return refuse; }
+ (void)endReview { [steps addObject:@"end"]; }
+ (BOOL)skipsSearchAfterRefusedChange { [steps addObject:@"skip?"]; return skip; }
+ (NSString *)findNextMisspellingInTextView:(NSTextView *)view mask:(TSSpellMask *)mask { [steps addObject:@"find"]; return nil; }
+ (void)showSpellingPanelForTextView:(NSTextView *)view mask:(TSSpellMask *)mask hidePanel:(void (^)(void))hidePanel
{ [steps addObject:@"panel"]; if (panelShown) hidePanel(); }
@end
@interface SystemTextView : NSTextView @end
@implementation SystemTextView
- (void)changeSpelling:(id)sender { [steps addObject:@"system change"]; }
- (void)checkSpelling:(id)sender { [steps addObject:@"system search"]; }
- (void)showGuessPanel:(id)sender { [steps addObject:@"system panel"]; }
@end
@interface ProbeTextView : SystemTextView
@property BOOL texAware;
@end
@implementation ProbeTextView
- (BOOL)usesTeXAwareSpellChecking { return self.texAware; }
- (TSSpellMask *)freshSpellMask { return nil; }
CHANGE
CHECK
GUESS
@end
static NSArray *Run(void (^action)(void)) { steps = [NSMutableArray array]; action(); return steps; }
int main(void) { @autoreleasepool {
    TSInstallAppKitIsolation();
    method_setImplementation(class_getClassMethod(NSEvent.class, @selector(modifierFlags)), (IMP)TestModifierFlags);
    ProbeTextView *v = [ProbeTextView new];
    for (int aware = 0; aware < 2; aware++) {
        v.texAware = aware;
        refuse = YES;
        REQUIRE([Run(^{ [v changeSpelling:nil]; }) isEqual:(@[@"refuse?"])], "a refused Change does nothing");
        refuse = NO;
        REQUIRE([Run(^{ [v changeSpelling:nil]; }) isEqual:(@[@"refuse?", @"system change"])], "an allowed Change replaces");
    }
    v.texAware = YES; flags = 0;
    REQUIRE([Run(^{ [v checkSpelling:nil]; }) isEqual:(@[@"skip?", @"find"])], "TeX-aware Find Next keeps the review");
    REQUIRE([Run(^{ [v showGuessPanel:nil]; }) isEqual:(@[@"panel"])], "TeX-aware panel opens without the system's search");
    panelShown = YES;
    REQUIRE([Run(^{ [v showGuessPanel:nil]; }) isEqual:(@[@"panel", @"system panel"])], "a shown panel is hidden by the system");
    panelShown = NO;
    flags = NSEventModifierFlagOption;
    REQUIRE([Run(^{ [v checkSpelling:nil]; }) isEqual:(@[@"skip?", @"end", @"system search"])], "Option search ends the review");
    REQUIRE([Run(^{ [v showGuessPanel:nil]; }) isEqual:(@[@"end", @"system panel"])], "Option panel ends the review");
    v.texAware = NO; flags = 0;
    REQUIRE([Run(^{ [v checkSpelling:nil]; }) isEqual:(@[@"skip?", @"end", @"system search"])], "system search ends the review");
    REQUIRE([Run(^{ [v showGuessPanel:nil]; }) isEqual:(@[@"end", @"system panel"])], "system panel ends the review");
    skip = YES;
    for (int aware = 0; aware < 2; aware++) {
        v.texAware = aware;
        flags = aware ? 0 : NSEventModifierFlagOption;
        REQUIRE([Run(^{ [v checkSpelling:nil]; }) isEqual:(@[@"skip?"])], "the search after a refused Change is skipped");
        REQUIRE([Run(^{ [v showGuessPanel:nil]; }) count] > 0 && ![steps containsObject:@"skip?"], "opening the panel is never skipped");
    }
    skip = NO; flags = 0;
    puts("PASS: Change asks the review guard; the system's own search ends the review; the search after a refusal is skipped");
} return 0; }
'''
def run(view):
    source = (root/VIEWS[view]).read_text(encoding='latin1')
    change = method(source, '- (void)changeSpelling:(id)sender')
    check = method(source, '- (void)checkSpelling:(id)sender')
    guess = method(source, '- (void)showGuessPanel:(id)sender')
    program = template.replace('CHANGE', change).replace('CHECK', check).replace('GUESS', guess)
    verify_embedded(program, [('complete method: %s changeSpelling' % view, source, change),
                              ('complete method: %s checkSpelling' % view, source, check),
                              ('complete method: %s showGuessPanel' % view, source, guess)])
    mutations = {
        'no-refuse': (change, change.replace('if ([TSSpellSupport refuseStaleChangeInTextView:self]) return;', '')),
        'no-end-check': (check, check.replace('[TSSpellSupport endReview];', '')),
        'no-end-guess': (guess, guess.replace('[TSSpellSupport endReview];', '')),
        # Open the panel with the system's own search first, as before #38.
        'system-search': (guess, guess.replace('    [TSSpellSupport showSpellingPanelForTextView:', '    [super showGuessPanel:sender];\n    [TSSpellSupport showSpellingPanelForTextView:')),
        'no-skip': (check, check.replace('if ([TSSpellSupport skipsSearchAfterRefusedChange]) return;', '')),
        'end-tex-aware': (check, check.replace('[TSSpellSupport findNextMisspellingInTextView:',
                                               '[TSSpellSupport endReview]; [TSSpellSupport findNextMisspellingInTextView:')),
    }
    if args.mutation:
        old, new = mutations[args.mutation]
        assert old != new and program.count(old) == 1
        program = program.replace(old, new)
    with tempfile.TemporaryDirectory(prefix='texshop-spell-change-wiring-') as td:
        t = Path(td); (t/'probe.m').write_text(program)
        subprocess.run(['xcrun', 'clang', '-fobjc-arc', '-I', str(root/'Tests'), '-framework', 'Cocoa',
                        str(t/'probe.m'), '-o', str(t/'probe')], check=True)
        subprocess.run([str(t/'probe')], check=True, timeout=30)

for view in ([args.view] if args.view else ['source', 'experiment']):
    print('VIEW', view, flush=True)
    run(view)
