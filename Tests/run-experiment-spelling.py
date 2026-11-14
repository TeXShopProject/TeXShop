#!/usr/bin/env python3
"""The check while typing in the Experiment source is TeX-aware, as in the document's source.

The Experiment source (ScrapTextView) has no delegate, so the document's
-textView:shouldSetSpellingState:range: never sees it; ScrapTextView asks the
mask itself. Commands, maths, the arguments of \\ref and \\label and comments are
not marked there, ordinary words are, and the Experiment follows the document's
source: when that is not TeX-aware (TeX-aware spelling off, or not a TeX file),
the Experiment marks every misspelling as the system does.

The production methods of ScrapTextView and the document's delegate method are
compiled unchanged onto small stand-ins with the real TSSpellSupport,
TSSpellExclusions and the shipped SpellingExclusions.txt. One part sets the
spelling state as the system does and reads it back; the other runs the system's
own check while typing (-checkTextInRange:types:options:) on the Experiment
source and records what reaches NSTextView. No window, panel or alert is shown,
and preferences stay in memory.
"""
from pathlib import Path
import argparse, os, shutil, subprocess, tempfile
from source_tree import include_args
from production_fragments import method, verify_embedded

root = Path(__file__).resolve().parents[1]
SCRAP = 'Sources/Editor/ScrapTextView.m'
DOCUMENT = 'Sources/Document/TSDocument.m'
scrap = (root/SCRAP).read_text(encoding='latin1')
document = (root/DOCUMENT).read_text(encoding='latin1')

uses = method(scrap, '- (BOOL)usesTeXAwareSpellChecking')
set_state = method(scrap, '- (void)setSpellingState:(NSInteger)value range:(NSRange)charRange')
checking_mask = method(scrap, '- (TSSpellMask *)spellMaskForCheckingRange:(NSRange)range')
fresh_mask = method(scrap, '- (TSSpellMask *)freshSpellMask')
delegate = method(document, '- (NSInteger)textView:(NSTextView *)aTextView shouldSetSpellingState:(NSInteger)value range:(NSRange)affectedCharRange')

MUTATIONS = {
    # The Experiment source checks spelling as the system does (before the fix).
    'no-override': (set_state, '- (void)setSpellingState:(NSInteger)value range:(NSRange)charRange\n{\n    [super setSpellingState:value range:charRange];\n}'),
    # TeX-aware always, whatever the document's source does.
    'always-aware': (uses, '- (BOOL)usesTeXAwareSpellChecking\n{\n    return YES;\n}'),
    # The mask is asked, but its answer is not used.
    'mask-ignored': (set_state, set_state.replace('value = 0;', ';')),
}
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--mutation', choices=sorted(MUTATIONS))
args = parser.parse_args()

program = r'''
#import <Cocoa/Cocoa.h>
#import "TestAppKitIsolation.h"
#import "TSSpellExclusions.h"
#import "TSSpellSupport.h"
#define REQUIRE(x, what) do { if (!(x)) { printf("FAIL: %s\n", what); exit(1); } } while (0)

// The document's source: TeX-aware or not, as -[TSTextView usesTeXAwareSpellChecking] decides.
@interface TSTextView : NSTextView
@property BOOL texAware;
- (BOOL)usesTeXAwareSpellChecking;
- (TSSpellMask *)spellMaskForCheckingRange:(NSRange)range;
@end
@implementation TSTextView
- (BOOL)usesTeXAwareSpellChecking { return self.texAware; }
- (TSSpellMask *)spellMaskForCheckingRange:(NSRange)range
{
    return [[TSSpellMaskCache cacheForTextStorage:self.textStorage] maskForCheckingRange:range];
}
@end

@interface TSDocument : NSObject <NSTextViewDelegate>
@property (strong) TSTextView *textView;
@end
@implementation TSDocument
DELEGATE
@end

@interface ScrapTextView : NSTextView
@property (weak) TSDocument *document;
@end
@implementation ScrapTextView
USES
SET_STATE
CHECKING_MASK
FRESH_MASK
@end

// What reaches NSTextView's own -setSpellingState:range: with a mark.
static NSMutableArray<NSString *> *sMarked;
static IMP sSetSpellingState;
static void RecordSpellingState(NSTextView *self, SEL _cmd, NSInteger value, NSRange range)
{
    if (value != 0 && NSMaxRange(range) <= self.string.length)
        [sMarked addObject:[self.string substringWithRange:range]];
    ((void (*)(id, SEL, NSInteger, NSRange))sSetSpellingState)(self, _cmd, value, range);
}

static NSString *const kText = @"Body zzqbody text \\ref{zzqref} and $zzqmath$ \\zzqcommand \\infty\n% zzqcomment\n";
static NSArray<NSString *> *Words(void) { return @[@"zzqbody", @"zzqref", @"zzqmath", @"zzqcommand", @"infty", @"zzqcomment"]; }

// Mark each word as the system's check would, and read back which marks stayed.
static NSArray<NSString *> *MarkedBySettingState(NSTextView *view)
{
    // The state can be read back only with the check while typing off, once it has been on.
    view.continuousSpellCheckingEnabled = YES;
    view.continuousSpellCheckingEnabled = NO;
    view.string = kText;
    // Marks set before the text is laid out are lost when it is.
    [view.layoutManager ensureLayoutForTextContainer:view.textContainer];
    NSMutableArray<NSString *> *kept = [NSMutableArray array];
    for (NSString *word in Words()) {
        NSRange range = [view.string rangeOfString:word];
        [view setSpellingState:NSSpellingStateSpellingFlag range:range];
        if ([view.layoutManager temporaryAttribute:NSSpellingStateAttributeName atCharacterIndex:range.location effectiveRange:NULL])
            [kept addObject:word];
    }
    return kept;
}

static NSString *Joined(NSArray<NSString *> *words) { return [words componentsJoinedByString:@" "]; }

int main(void) { @autoreleasepool {
    TSInstallAppKitIsolation();
    [NSApplication sharedApplication];
    Method set = class_getInstanceMethod(NSTextView.class, @selector(setSpellingState:range:));
    sSetSpellingState = method_setImplementation(set, (IMP)RecordSpellingState);

    TSDocument *document = [TSDocument new];
    document.textView = [[TSTextView alloc] initWithFrame:NSMakeRect(0, 0, 400, 400)];
    document.textView.delegate = document;
    ScrapTextView *experiment = [[ScrapTextView alloc] initWithFrame:NSMakeRect(0, 0, 400, 400)];
    experiment.document = document;

    sMarked = [NSMutableArray array];
    document.textView.texAware = YES;
    NSString *source = Joined(MarkedBySettingState(document.textView));
    NSString *shown = Joined(MarkedBySettingState(experiment));
    printf("TeX-aware: document source keeps [%s], Experiment keeps [%s]\n", source.UTF8String, shown.UTF8String);
    REQUIRE([source isEqualToString:@"zzqbody"], "the document's source marks only the ordinary word");
    REQUIRE([shown isEqualToString:source], "the Experiment source marks what the document's source marks");

    document.textView.texAware = NO;
    source = Joined(MarkedBySettingState(document.textView));
    shown = Joined(MarkedBySettingState(experiment));
    printf("not TeX-aware: document source keeps [%s], Experiment keeps [%s]\n", source.UTF8String, shown.UTF8String);
    REQUIRE([source isEqualToString:Joined(Words())], "without TeX-aware spelling the source marks every word");
    REQUIRE([shown isEqualToString:source], "the Experiment source follows the document's source");

    document.textView.texAware = YES;
    experiment.document = nil;
    shown = Joined(MarkedBySettingState(experiment));
    REQUIRE([shown isEqualToString:Joined(Words())], "an Experiment source without a document is not TeX-aware");
    experiment.document = document;

    // The system's own check while typing goes through ScrapTextView's -setSpellingState:range:.
    experiment.string = kText;
    experiment.continuousSpellCheckingEnabled = YES;
    sMarked = [NSMutableArray array];
    [experiment checkTextInRange:NSMakeRange(0, experiment.string.length) types:NSTextCheckingTypeSpelling options:@{}];
    for (int k = 0; k < 200 && ![sMarked containsObject:@"zzqbody"]; k++)
        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
    printf("system check while typing marks [%s] in the Experiment source\n", Joined(sMarked).UTF8String);
    REQUIRE([sMarked containsObject:@"zzqbody"], "the system's check marks the ordinary misspelling");
    for (NSString *word in Words())
        if (![word isEqualToString:@"zzqbody"])
            REQUIRE(![sMarked containsObject:word], "the system's check marks no command, maths, argument or comment");
    puts("PASS: the Experiment source checks spelling TeX-aware, as the document's source does");
} return 0; }
'''
program = (program.replace('DELEGATE', delegate).replace('USES', uses).replace('SET_STATE', set_state)
           .replace('CHECKING_MASK', checking_mask).replace('FRESH_MASK', fresh_mask))
verify_embedded(program, [('complete method: Experiment usesTeXAwareSpellChecking', scrap, uses),
                          ('complete method: Experiment setSpellingState', scrap, set_state),
                          ('complete method: Experiment spellMaskForCheckingRange', scrap, checking_mask),
                          ('complete method: Experiment freshSpellMask', scrap, fresh_mask),
                          ('complete method: document shouldSetSpellingState', document, delegate)])
if args.mutation:
    old, new = MUTATIONS[args.mutation]
    assert old != new and program.count(old) == 1, args.mutation
    program = program.replace(old, new)

with tempfile.TemporaryDirectory(prefix='texshop-experiment-spelling-') as td:
    t = Path(td)
    (t/'Library').mkdir()
    rules = t/'SpellingExclusions.txt'
    shutil.copyfile(root/'Resources/TeXShop/SpellCheck/SpellingExclusions.txt', rules)
    (t/'probe.m').write_text(program)
    subprocess.run(['xcrun', 'clang', '-fobjc-arc', '-w', '-DTSSPELL_STANDALONE_TEST', '-I', str(root/'Tests'),
                    *include_args(root), '-framework', 'Cocoa', str(t/'probe.m'),
                    str(root/'Sources/Editor/TSSpellSupport.m'), str(root/'Sources/Editor/TSSpellExclusions.m'),
                    '-o', str(t/'probe')], check=True)
    result = subprocess.run([str(t/'probe')], env=dict(os.environ, HOME=str(t), TSSPELL_RULES=str(rules)), timeout=60)
    if args.mutation:
        if result.returncode == 0:
            raise SystemExit('FAIL: mutation %s was not detected' % args.mutation)
        print('PASS: mutation %s detected (exit %d).' % (args.mutation, result.returncode))
        raise SystemExit(0)
    raise SystemExit(result.returncode)
