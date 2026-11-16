#import "TSBundledMacroUpdate.h"

static NSString * const TSCurrentHomePage = @"https://texshop.app/";

// The addresses that earlier versions bundled in place of the current one.
static NSArray<NSString *> *TSFormerHomePages(void)
{
    return @[@"https://pages.uoregon.edu/koch/texshop/texshop.html",
             @"http://pages.uoregon.edu/koch/texshop/texshop.html",
             @"http://www.uoregon.edu/~koch/texshop/texshop.html"];
}

static void TSCollectBundledTexts(id node, NSMutableDictionary<NSString *, NSString *> *earlier)
{
    if (![node isKindOfClass:[NSDictionary class]])
        return;
    NSString *content = node[@"content"];
    NSString *current = [NSString stringWithFormat:@"open location \"%@\"", TSCurrentHomePage];
    if ([content isKindOfClass:[NSString class]] && [content containsString:current])
        for (NSString *former in TSFormerHomePages())
            earlier[[content stringByReplacingOccurrencesOfString:TSCurrentHomePage withString:former]] = content;
    NSArray *submenu = node[@"submenu"];
    if ([submenu isKindOfClass:[NSArray class]])
        for (id child in submenu)
            TSCollectBundledTexts(child, earlier);
}

static NSUInteger TSReplaceEarlierTexts(id node, NSDictionary<NSString *, NSString *> *earlier)
{
    if (![node isKindOfClass:[NSMutableDictionary class]])
        return 0;
    NSUInteger count = 0;
    NSString *content = node[@"content"];
    if ([content isKindOfClass:[NSString class]] && earlier[content]) {
        node[@"content"] = earlier[content];
        count++;
    }
    NSArray *submenu = node[@"submenu"];
    if ([submenu isKindOfClass:[NSArray class]])
        for (id child in submenu)
            count += TSReplaceEarlierTexts(child, earlier);
    return count;
}

NSUInteger TSUpdateUnchangedBundledMacros(NSString *userPath, NSString *bundledPath)
{
    NSData *bundledData = [NSData dataWithContentsOfFile:bundledPath];
    id bundled = bundledData ? [NSPropertyListSerialization propertyListWithData:bundledData options:NSPropertyListImmutable format:NULL error:NULL] : nil;
    NSMutableDictionary<NSString *, NSString *> *earlier = [NSMutableDictionary dictionary];
    TSCollectBundledTexts(bundled, earlier);
    if (earlier.count == 0)
        return 0;

    // Write through a symbolic link, so a Macros file kept elsewhere stays where it is.
    NSURL *file = [[NSURL fileURLWithPath:userPath] URLByResolvingSymlinksInPath];
    NSData *data = [NSData dataWithContentsOfURL:file];
    if (!data)
        return 0;
    NSPropertyListFormat format = NSPropertyListXMLFormat_v1_0;
    id macros = [NSPropertyListSerialization propertyListWithData:data options:NSPropertyListMutableContainersAndLeaves format:&format error:NULL];
    NSUInteger count = TSReplaceEarlierTexts(macros, earlier);
    if (count == 0)
        return 0;
    NSData *updated = [NSPropertyListSerialization dataWithPropertyList:macros format:format options:0 error:NULL];
    if (!updated || ![updated writeToURL:file atomically:YES])
        return 0;
    return count;
}
