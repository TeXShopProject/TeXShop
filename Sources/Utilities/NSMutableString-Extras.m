/*
 * TeXShop - TeX editor for Mac OS
 * Copyright (C) 2000-2005 Richard Koch
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin St, Fifth Floor, Boston, MA  02110-1301  USA
 *
 */

#import <AppKit/AppKit.h>
#import "NSMutableString-Extras.h"

@implementation NSMutableString (TeXShop)
- (void)replaceAllOccurrencesOfPattern:(NSString*)pattern withString:(NSString*)replacement
{
    NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:pattern options:0 error:nil];
    
    NSArray<NSTextCheckingResult*> *matches = [regex matchesInString:self options:0 range:NSMakeRange(0, self.length)];
    
    NSEnumerator<NSTextCheckingResult*> *enumerator = matches.reverseObjectEnumerator;
    NSTextCheckingResult *match;
    
    while ((match = [enumerator nextObject])) {
        [self replaceCharactersInRange:match.range withString:replacement];
    }
}

- (void)replaceAllOccurrencesOfPattern:(NSString*)pattern usingBlock:(NSString* (^)(NSString*, NSArray<NSString*>*))replace
{
    NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:pattern options:0 error:nil];
    
    NSArray<NSTextCheckingResult*> *matches = [regex matchesInString:self options:0 range:NSMakeRange(0, self.length)];
    
    NSEnumerator<NSTextCheckingResult*> *enumerator = matches.reverseObjectEnumerator;
    NSTextCheckingResult *match;
    
    while ((match = [enumerator nextObject])) {
        NSRange range = match.range;
        NSMutableArray<NSString*> *groups = [NSMutableArray<NSString*> array];
        for (NSUInteger i=1; i<match.numberOfRanges; i++) {
            [groups addObject:[self substringWithRange:[match rangeAtIndex:i]]];
        }
        [self replaceCharactersInRange:range withString:replace([self substringWithRange:range], groups)];
    }
}

- (void)replaceAllOccurrencesOfString:(NSString*)target withString:(NSString*)replacement addingPercentForEndOfLine:(BOOL)addingPercent
{
    // Most conversions try hundreds of targets; skip the extra passes for absent ones.
    if ([self rangeOfString:target options:0 range:NSMakeRange(0, self.length)].location == NSNotFound) {
        return;
    }

    if (addingPercent) {
        NSString *src;
        NSString *dest;
        
        src = [NSString stringWithFormat:@"%@\r\n", target];
        dest = [NSString stringWithFormat:@"%@%%\r\n", replacement];
        [self replaceOccurrencesOfString:src withString:dest options:0 range:NSMakeRange(0, self.length)];
        
        src = [NSString stringWithFormat:@"%@\r", target];
        dest = [NSString stringWithFormat:@"%@%%\r", replacement];
        [self replaceOccurrencesOfString:src withString:dest options:0 range:NSMakeRange(0, self.length)];
        
        src = [NSString stringWithFormat:@"%@\n", target];
        dest = [NSString stringWithFormat:@"%@%%\n", replacement];
        [self replaceOccurrencesOfString:src withString:dest options:0 range:NSMakeRange(0, self.length)];
    }
    
    [self replaceOccurrencesOfString:target withString:replacement options:0 range:NSMakeRange(0, self.length)];
}
- (void)replacePasteMarkersWithClipboardText
{
    if ([self rangeOfString:@"#PASTE#" options:NSLiteralSearch].location == NSNotFound)
        return;
    NSMutableString *clipboard = [([[NSPasteboard generalPasteboard] stringForType:NSPasteboardTypeString] ?: @"") mutableCopy];
    // ConvertLFKey of globals.m (this file is built without the rest of TeXShop in the tests): as a paste, the text
    // gets LF line endings.
    if ([NSUserDefaults.standardUserDefaults boolForKey:@"ConvertLF"])
        [clipboard replaceLineEndingsWithLF];
    [self replaceOccurrencesOfString:@"#PASTE#" withString:clipboard options:NSLiteralSearch range:NSMakeRange(0, self.length)];
}

// CRLF, CR, U+2028 and U+2029 become LF, as OgreKit's replaceNewlineCharactersInString: makes them when a file is
// opened or text is typed or pasted.
- (void)replaceLineEndingsWithLF
{
    for (NSString *ending in @[@"\r\n", @"\r", @"\u2028", @"\u2029"])
        [self replaceOccurrencesOfString:ending withString:@"\n" options:NSLiteralSearch range:NSMakeRange(0, self.length)];
}
@end
