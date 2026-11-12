// The OgreKit syntax of replacement strings gives what OgreKit itself gives, for generated
// templates on simple patterns that Onigmo and ICU match alike. Foundation and OgreKit only.
#import <Foundation/Foundation.h>
#import <OgreKit/OGRegularExpression.h>
#import "TSRegexTextFind.h"

static NSString *Ours(NSString *find, NSString *replace, NSString *text)
{
    TSRegexFindPattern *pattern = [[TSRegexFindPattern alloc] initWithFindString:find options:TSRegexFindRegularExpression error:NULL];
    TSRegexTextFind *finder = [[TSRegexTextFind alloc] initWithString:text pattern:pattern selectedRanges:@[[NSValue valueWithRange:NSMakeRange(0, 0)]] inSelection:NO error:NULL];
    TSRegexReplaceAllResult *result = [finder replaceAllWithTemplate:[[TSRegexReplacementTemplate alloc] initWithString:replace pattern:pattern syntax:TSRegexReplacementSyntaxOgreKit] cancellation:nil];
    NSMutableString *output = [text mutableCopy];
    for (TSRegexFindReplacement *replacement in result.replacements.reverseObjectEnumerator)
        [output replaceCharactersInRange:replacement.range withString:replacement.string];
    return output;
}

int main(void)
{
    @autoreleasepool {
        // Escapes are drawn often, so that most templates contain several of them.
        NSString *alphabet = @"\\\\\\\\\\\\0123&+`'-gx<>{}9aAtnr$z";
        NSArray<NSArray<NSString *> *> *cases = @[@[@"(a)(b)?(c)", @"xacy abcz ac"], @[@"(?<p>a)(?<q>b)", @"-ab-ab-"], @[@"b", @"abcbd"]];
        uint32_t state = 3;
        NSUInteger compared = 0, mismatches = 0;
        for (NSArray<NSString *> *c in cases) {
            OGRegularExpression *ogre = [OGRegularExpression regularExpressionWithString:c[0] options:OgreCaptureGroupOption];
            for (NSUInteger k = 0; k < 3000; k++) {
                NSMutableString *replace = [NSMutableString string];
                state = state * 1664525u + 1013904223u;
                NSUInteger length = (state >> 24) % 9;
                for (NSUInteger j = 0; j < length; j++) {
                    state = state * 1664525u + 1013904223u;
                    [replace appendFormat:@"%C", [alphabet characterAtIndex:(state >> 16) % alphabet.length]];
                }
                NSString *expected = [ogre replaceAllMatchesInString:c[1] withString:replace options:OgreNoneOption];
                NSString *actual = Ours(c[0], replace, c[1]);
                compared++;
                if (![actual isEqualToString:expected] && mismatches++ < 8)
                    printf("FAIL OgreKit template [%s] on %s: got [%s], OgreKit gives [%s]\n", replace.UTF8String, c[0].UTF8String, actual.UTF8String, expected.UTF8String);
            }
        }
        if (mismatches)
            return 1;
        printf("PASS: %lu generated OgreKit replacement strings give what OgreKit gives (with Always Capture)\n", (unsigned long)compared);
    }
    return 0;
}
