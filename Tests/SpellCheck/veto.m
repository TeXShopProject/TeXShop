// Which words the "check while typing" path would not underline: markup and
// fragments next to accent commands are vetoed, ordinary words are kept.
// usage: veto RULES-FILE   (prints: word:veto|keep ...)
#import <Foundation/Foundation.h>
#import "TSSpellExclusions.h"
int main(int argc, char **argv) { @autoreleasepool {
    TSSpellExclusions *ex = [[TSSpellExclusions alloc] initWithRulesFile:@(argv[1])];
    NSString *text = @"sentense M\\\"unchen caf\\'e na\\\"{i}ve Stra\\ss e \\textbf{boldd} \\label{lbl}";
    TSSpellMask *m = [ex maskForText:text];
    for (NSString *w in @[@"sentense", @"unchen", @"caf", @"boldd", @"lbl", @"Stra", @"e"]) {
        NSRange r = [text rangeOfString:w];
        if ([w isEqualToString:@"e"]) r = [text rangeOfString:@" e " options:0 range:NSMakeRange(30, text.length - 30)], r = NSMakeRange(r.location + 1, 1);
        BOOL veto = [m rangeTouchesExclusion:r] || [m rangeIsNextToAccent:r];
        printf("%s:%s ", [w UTF8String], veto ? "veto" : "keep");
    }
    printf("\n");
} return 0; }
