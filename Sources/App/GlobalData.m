//
//  GlobalData.m
//  TeXShop
//
//  Created by Richard Koch on 3/20/14.
//
//

#import "GlobalData.h"

@implementation GlobalData

static GlobalData *sharedGlobalData = nil;

+ (GlobalData*)sharedGlobalData {
    if (sharedGlobalData == nil) {
        sharedGlobalData = [[super allocWithZone:NULL] init];
        
        // initialize your variables here
    }
    return sharedGlobalData;
}

- (NSDictionary<NSString *, NSString *> *)pasteKeyBindings
{
    NSMutableDictionary *bindings = [NSMutableDictionary dictionary];
    NSDictionary *all = self.g_autocompletionDictionary;
    for (id key in self.g_autocompletionPasteKeys) {
        if (![key isKindOfClass:NSString.class] || [key length] == 0) continue;
        id output = all[key];
        // A file edited by hand may mark a row with a placeholder: it is left out.
        if (![output isKindOfClass:NSString.class] || TSKeyBindingOutputHasPlaceholder(output)) continue;
        bindings[key] = output;
    }
    return bindings;
}

@end

BOOL TSKeyBindingOutputHasPlaceholder(NSString *output)
{
    for (NSString *symbol in @[@"#SEL#", @"#INS#", @"#PASTE#", @"•"])
        if ([output rangeOfString:symbol options:NSLiteralSearch].location != NSNotFound) return YES;
    return NO;
}

NSString *TSApplyKeyBindings(NSString *text, NSDictionary<NSString *, NSString *> *bindings)
{
    if (text.length == 0 || bindings.count == 0) return text;
    // Longer input characters first; each is replaced only as whole characters.
    NSArray<NSString *> *keys = [bindings.allKeys sortedArrayUsingComparator:^NSComparisonResult(NSString *a, NSString *b) {
        return a.length > b.length ? NSOrderedAscending : (a.length < b.length ? NSOrderedDescending : [a compare:b options:NSLiteralSearch]);
    }];
    // The first UTF-16 unit of each input character; a character outside the
    // Basic Multilingual Plane starts with its high surrogate.
    NSMutableIndexSet *starts = [NSMutableIndexSet indexSet];
    for (NSString *key in keys) [starts addIndex:[key characterAtIndex:0]];
    NSMutableString *result = nil;
    NSUInteger copied = 0, index = 0, length = text.length;
    while (index < length) {
        if (![starts containsIndex:[text characterAtIndex:index]]) { index++; continue; }
        NSString *match = nil;
        if ([text rangeOfComposedCharacterSequenceAtIndex:index].location == index) {
            for (NSString *key in keys) {
                NSUInteger end = index + key.length;
                if (end > length || [text compare:key options:NSLiteralSearch range:NSMakeRange(index, key.length)] != NSOrderedSame) continue;
                if (end < length && [text rangeOfComposedCharacterSequenceAtIndex:end].location != end) continue;
                match = key;
                break;
            }
        }
        if (match == nil) { index++; continue; }
        if (result == nil) result = [NSMutableString stringWithCapacity:length];
        [result appendString:[text substringWithRange:NSMakeRange(copied, index - copied)]];
        [result appendString:bindings[match]];
        index += match.length;
        copied = index;
    }
    if (result == nil) return text;
    [result appendString:[text substringFromIndex:copied]];
    return result;
}
