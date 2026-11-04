// Prints the text that the spell checker would see (markup masked out).
// usage: mask RULES-FILE SOURCE.tex [languages]
// With "languages" it prints instead each stretch of the masked text that is
// in another language, as "code: words".
#import <Foundation/Foundation.h>
#import "TSSpellExclusions.h"
int main(int argc, char **argv) {
    @autoreleasepool {
        if (argc < 3) { fprintf(stderr, "usage: mask RULES SOURCE\n"); return 2; }
        TSSpellExclusions *ex = [[TSSpellExclusions alloc] initWithRulesFile:@(argv[1])];
        if (ex.problems) fprintf(stderr, "PROBLEMS:\n%s", [ex.problems UTF8String]);
        NSString *text = [NSString stringWithContentsOfFile:@(argv[2]) encoding:NSUTF8StringEncoding error:nil];
        TSSpellMask *mask = [ex maskForText:text];
        if (argc > 3) {
            for (TSSpellLanguageSegment *seg in [mask languageSegments]) {
                NSString *words = [[[mask.masked substringWithRange:seg.range] componentsSeparatedByCharactersInSet:
                                    [NSCharacterSet whitespaceAndNewlineCharacterSet]] componentsJoinedByString:@" "];
                words = [[words componentsSeparatedByString:@"  "] componentsJoinedByString:@" "];
                while ([words containsString:@"  "]) words = [words stringByReplacingOccurrencesOfString:@"  " withString:@" "];
                words = [words stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
                if (words.length) printf("%s: %s\n", seg.language ? [seg.language UTF8String] : "-", [words UTF8String]);
            }
        } else {
            fputs(mask.masked.UTF8String, stdout);
        }
    }
    return 0;
}
