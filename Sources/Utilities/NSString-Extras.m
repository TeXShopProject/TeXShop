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
 * $Id: NSString-Extras.m 108 2006-02-10 13:50:25Z fingolfin $
 *
 */

#import "NSString-Extras.h"


@implementation NSString (TeXShop)

- (BOOL)contains:(NSString *)str {
	NSRange range;
	range = [self rangeOfString:str];

	return range.location != NSNotFound;
}

// Terada
// NFC except for characters with the Unicode property Full_Composition_Exclusion,
// such as CJK compatibility ideographs, which NFC would replace by other
// characters. Only the runs between such characters are composed, as in
// CotEditor's precomposedStringWithHFSPlusMapping.
- (NSString*)normalizedStringWithModifiedNFC
{
    static NSRegularExpression *composable;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        composable = [NSRegularExpression regularExpressionWithPattern:@"\\P{Full_Composition_Exclusion}+" options:0 error:NULL];
    });
    NSMutableString *result = [self mutableCopy];
    NSArray<NSTextCheckingResult *> *runs = [composable matchesInString:self options:0 range:NSMakeRange(0, self.length)];
    for (NSTextCheckingResult *run in runs.reverseObjectEnumerator)
        [result replaceCharactersInRange:run.range withString:[[self substringWithRange:run.range] precomposedStringWithCanonicalMapping]];
    return result;
}

// The decomposition used by HFS+ file names: like NFD, but CJK
// compatibility ideographs and some other ranges stay as they are.
- (NSString*)normalizedStringWithModifiedNFD
{
    CFStringRef sourceStr = (__bridge CFStringRef)self;
    CFIndex length = CFStringGetMaximumSizeOfFileSystemRepresentation(sourceStr);
    char *destStr = (char*)malloc(length);
    Boolean success = destStr && CFStringGetFileSystemRepresentation(sourceStr, destStr, length);
    NSString *result = success ? [NSString stringWithUTF8String:destStr] : nil;
    free(destStr);
    return result ?: [self copy];
}

// Terada (based on CotEditor)
- (NSUInteger)numberOfComposedCharacters
{
    // normalize using NFC
    NSString *string = [self precomposedStringWithCanonicalMapping];
    
    // count composed chars
    __block NSUInteger count = 0;
    __block BOOL isRegionalIndicator = NO;
    NSRange regionalIndicatorRange = NSMakeRange(0xDDE6, 0xDDFF - 0xDDE6 + 1);
    [string enumerateSubstringsInRange:NSMakeRange(0, [string length])
                               options:NSStringEnumerationByComposedCharacterSequences | NSStringEnumerationSubstringNotRequired
                            usingBlock:^(NSString *substring, NSRange substringRange, NSRange enclosingRange, BOOL *stop)
     {
         // skip if the last composed character was a regional indicator surrogate-pair
         // 'Cause the so-called national flag emojis consist of two such surrogate pairs
         // and the first one is already counted in the last loop.
         // (To simplify the process, we don't check whether this character is also a regional indicator.)
         if (isRegionalIndicator) {
             isRegionalIndicator = NO;
             return;
         }
         
         // detect regional surrogate pair.
         if ((substringRange.length == 2) &&
             (NSLocationInRange([string characterAtIndex:substringRange.location + 1], regionalIndicatorRange)))
         {
             isRegionalIndicator = YES;
         }
         
         count++;
     }];
    
    return count;
}


@end
