// SPDX-License-Identifier: GPL-2.0-or-later
#import "TSSourceMagicComments.h"

/// Latin 9, which TeXShop reads unreadable bytes in (the same value as its global NSISOLatin9StringEncoding).
static NSStringEncoding TSLatin9Encoding(void)
{
    return CFStringConvertEncodingToNSStringEncoding(kCFStringEncodingISOLatin9);
}

@implementation TSSourceMagicComments

+ (NSString *)headerTextOfData:(NSData *)data
{
    const unsigned char *bytes = data.bytes;
    BOOL utf16 = data.length >= 2 && ((bytes[0] == 0xFE && bytes[1] == 0xFF) || (bytes[0] == 0xFF && bytes[1] == 0xFE));
    NSString *text = utf16 ? [[NSString alloc] initWithData:data encoding:NSUnicodeStringEncoding] : nil;
    if (text == nil)
        text = [[NSString alloc] initWithData:data encoding:TSLatin9Encoding()];
    return text ?: @"";
}

+ (nullable NSString *)encodingNameInHeaderText:(NSString *)headerText allowingOldHeading:(BOOL)allowsOldHeading
{
    NSUInteger length = headerText.length;
    NSRange lineProbe = NSMakeRange(0, 1);
    NSInteger linesTested = 0;
    while (lineProbe.location < length && linesTested < 20) {
        NSUInteger start, end;
        [headerText getLineStart:&start end:&end contentsEnd:NULL forRange:lineProbe];
        lineProbe = NSMakeRange(end, 1);
        linesTested++;

        NSString *line = [headerText substringWithRange:NSMakeRange(start, end - start)];
        NSRange marker = [line rangeOfString:@"%!TEX encoding ="];
        NSUInteger offset = 16;
        if (marker.location == NSNotFound) {
            marker = [line rangeOfString:@"% !TEX encoding ="];
            offset = 17;
        }
        if (marker.location == NSNotFound && allowsOldHeading) {
            marker = [line rangeOfString:@"%&encoding="];
            offset = 11;
        }
        if (marker.location == NSNotFound)
            continue;
        NSUInteger valueStart = marker.location + offset;
        if (valueStart >= line.length)
            return nil;
        return [[line substringFromIndex:valueStart]
                stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    }
    return nil;
}

@end
