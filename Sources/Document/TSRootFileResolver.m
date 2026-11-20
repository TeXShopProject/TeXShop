// SPDX-License-Identifier: GPL-2.0-or-later
#import "TSRootFileResolver.h"

@implementation TSRootFileSpecifier

- (instancetype)initWithKind:(TSRootFileSpecifierKind)kind value:(NSString *)value
{
    if ((self = [super init])) {
        _kind = kind;
        _value = [value copy];
    }
    return self;
}

@end

@implementation TSRootFileResolver

+ (nullable TSRootFileSpecifier *)specifierInSource:(nullable NSString *)source allowingSourceDoc:(BOOL)allowsSourceDoc
{
    if (source == nil)
        return nil;

    // The first 20 lines, as -checkMasterFile:forTask: has always read them.
    NSUInteger length = source.length;
    NSRange lineProbe = NSMakeRange(0, 1);
    NSInteger linesTested = 0;
    while (lineProbe.location < length && linesTested < 20) {
        NSUInteger start, end, contentsEnd;
        [source getLineStart:&start end:&end contentsEnd:&contentsEnd forRange:lineProbe];
        lineProbe = NSMakeRange(end, 1);
        linesTested++;

        NSString *line = [source substringWithRange:NSMakeRange(start, end - start)];
        NSRange marker = [line rangeOfString:@"%!TEX root ="];
        NSUInteger offset = 12;
        if (marker.location == NSNotFound) {
            marker = [line rangeOfString:@"% !TEX root ="];
            offset = 13;
        }
        if (marker.location == NSNotFound)
            continue;
        NSUInteger valueStart = marker.location + offset;
        if (valueStart >= line.length)
            continue;
        NSString *value = [[line substringFromIndex:valueStart]
                           stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        if (value.length > 0)
            return [[TSRootFileSpecifier alloc] initWithKind:TSRootFileSpecifierKindTeXRoot value:value];
    }

    if (!allowsSourceDoc)
        return nil;
    return [self sourceDocSpecifierInSource:(NSString *)source];   // not nil: checked above
}

+ (nullable TSRootFileSpecifier *)sourceDocSpecifierInSource:(NSString *)source
{
    // The old heading: only the first "%SourceDoc " of the whole source, and only when it starts its line.
    NSRange marker = [source rangeOfString:@"%SourceDoc "];
    if (marker.location == NSNotFound)
        return nil;
    NSRange line = [source lineRangeForRange:marker];
    if (line.length <= 12 || marker.location != line.location)
        return nil;
    NSString *value = [source substringWithRange:NSMakeRange(line.location + 11, line.length - 12)];
    if (value.length == 0)
        return nil;
    return [[TSRootFileSpecifier alloc] initWithKind:TSRootFileSpecifierKindSourceDoc value:value];
}

+ (NSString *)pathForName:(NSString *)name homePath:(nullable NSString *)home jobName:(nullable NSString *)jobName
             jobNameToken:(NSString *)jobNameToken
{
    NSString *relative = [name stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
    NSString *path;
    // A name of only spaces names no file.
    if (relative.length == 0)
        return @"";
    unichar firstChar = [relative characterAtIndex:0];
    if (firstChar == '~')
        path = [relative stringByExpandingTildeInPath];
    else if (firstChar == '/')
        path = relative;
    else if (firstChar == '.') {
        while ([relative hasPrefix:@"../"]) {
            home = [home stringByDeletingLastPathComponent];
            relative = [relative substringFromIndex:3];
        }
        path = [NSString stringWithFormat:@"%@/%@", home, relative];
    } else
        path = [NSString stringWithFormat:@"%@/%@", home, relative];

    path = [path stringByResolvingSymlinksInPath];

    // An untitled document has no job name: the name stays as it is (and names no file).
    if (jobName == nil || [path rangeOfString:jobNameToken options:NSLiteralSearch].location == NSNotFound)
        return path;
    NSMutableString *replaced = [path mutableCopy];
    [replaced replaceOccurrencesOfString:jobNameToken withString:(NSString *)jobName options:NSLiteralSearch
                                   range:NSMakeRange(0, path.length)];
    return [replaced copy];
}

+ (nullable NSString *)rootPathInSource:(nullable NSString *)source documentPath:(nullable NSString *)documentPath
                      allowingSourceDoc:(BOOL)allowsSourceDoc jobNameToken:(NSString *)jobNameToken
                              specifier:(TSRootFileSpecifier * _Nullable * _Nullable)specifier
{
    TSRootFileSpecifier *found = [self specifierInSource:source allowingSourceDoc:allowsSourceDoc];
    if (specifier)
        *specifier = found;
    if (found == nil)
        return nil;
    return [self pathForName:found.value homePath:[documentPath stringByDeletingLastPathComponent]
                     jobName:[documentPath.lastPathComponent stringByDeletingPathExtension] jobNameToken:jobNameToken];
}

@end
