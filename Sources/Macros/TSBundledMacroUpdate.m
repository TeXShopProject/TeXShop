#import "TSBundledMacroUpdate.h"

static NSString * const TSCurrentHomePage = @"https://texshop.app/";

// The addresses that earlier versions bundled in place of the current one.
static NSArray<NSString *> *TSFormerHomePages(void)
{
    return @[@"https://pages.uoregon.edu/koch/texshop/texshop.html",
             @"http://pages.uoregon.edu/koch/texshop/texshop.html",
             @"http://www.uoregon.edu/~koch/texshop/texshop.html"];
}

// Bundled macros reworded since earlier versions: the current name, the changes from each
// earlier text to the current one (current text, earlier text), and the earlier name when the
// macro was renamed too. "TeX Live" is written with the space, and the ConTeXt macro that
// opened the teTeX page of Gerben Wierda opens the TeX Live home page. Program no longer offers
// metafont and context, which typesetting does not know without an engine file of that name, and
// Encoding offers DOSKorean, as the encoding menus do.
static NSArray<NSDictionary *> *TSRewordedMacros(void)
{
    return @[
        @{@"name": @"Program",
          @"changes": @[@[@"\"personallatex\", \"metapost\"} & engines", @"\"personallatex\", \"metapost\", \"metafont\", \"context\"} & engines"]]},
        @{@"name": @"Encoding",
          @"changes": @[@[@"\"MacKorean\", \"DOSKorean\", \"UTF-8 Unicode\"", @"\"MacKorean\", \"UTF-8 Unicode\""]]},
        @{@"name": @"View TeX Live file",
          @"changes": @[@[@"-- OPEN TeX Live FILE", @"-- OPEN TeXLive FILE"],
                        @[@"a file in the TeX Live tree, for", @"a file in the TeXLive tree, for"],
                        @[@"any files in the TeX Live tree with", @"any files in the teTeX tree with"]]},
        @{@"name": @"TeX Live home page", @"formerName": @"teTeX/TeXLive home page",
          @"changes": @[@[@"open location \"https://tug.org/texlive/\"", @"open location \"http://www.rna.nl/tex.html\""]]},
    ];
}

// Maps each earlier bundled text to the current macro: its content, and its name and earlier
// name when it was renamed.
static void TSCollectBundledTexts(id node, NSMutableDictionary<NSString *, NSDictionary *> *earlier)
{
    if (![node isKindOfClass:[NSDictionary class]])
        return;
    NSString *content = node[@"content"];
    NSString *name = node[@"name"];
    NSString *current = [NSString stringWithFormat:@"open location \"%@\"", TSCurrentHomePage];
    if ([content isKindOfClass:[NSString class]] && [content containsString:current])
        for (NSString *former in TSFormerHomePages())
            earlier[[content stringByReplacingOccurrencesOfString:TSCurrentHomePage withString:former]] = @{@"content": content};
    if ([content isKindOfClass:[NSString class]] && [name isKindOfClass:[NSString class]])
        for (NSDictionary *macro in TSRewordedMacros()) {
            if (![name isEqualToString:macro[@"name"]])
                continue;
            NSString *former = content;
            for (NSArray<NSString *> *change in macro[@"changes"])
                former = [former stringByReplacingOccurrencesOfString:change[0] withString:change[1]];
            if ([former isEqualToString:content])
                continue;
            NSMutableDictionary *target = [@{@"content": content} mutableCopy];
            if (macro[@"formerName"]) {
                target[@"name"] = name;
                target[@"formerName"] = macro[@"formerName"];
            }
            earlier[former] = target;
        }
    NSArray *submenu = node[@"submenu"];
    if ([submenu isKindOfClass:[NSArray class]])
        for (id child in submenu)
            TSCollectBundledTexts(child, earlier);
}

static NSUInteger TSReplaceEarlierTexts(id node, NSDictionary<NSString *, NSDictionary *> *earlier)
{
    if (![node isKindOfClass:[NSMutableDictionary class]])
        return 0;
    NSUInteger count = 0;
    NSString *content = node[@"content"];
    NSDictionary *target = [content isKindOfClass:[NSString class]] ? earlier[content] : nil;
    // A renamed macro is updated only under its earlier name; one the user renamed stays.
    if (target && (target[@"formerName"] == nil || [node[@"name"] isEqual:target[@"formerName"]])) {
        node[@"content"] = target[@"content"];
        if (target[@"name"])
            node[@"name"] = target[@"name"];
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
    NSMutableDictionary<NSString *, NSDictionary *> *earlier = [NSMutableDictionary dictionary];
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
