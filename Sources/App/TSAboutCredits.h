//
//  TSAboutCredits.h
//
//  The credits shown in About TeXShop, led by a link to the TeXShop web site.
//

#import <AppKit/AppKit.h>

static NSString * const TSAboutWebsiteAddress = @"https://texshop.app/";

// The credits with the web site address on its own centered line at the top,
// in the font of the credits, as a link that opens the site.
static inline NSAttributedString *TSAboutCreditsWithWebsiteLink(NSAttributedString *credits)
{
    NSURL *url = [NSURL URLWithString:TSAboutWebsiteAddress];
    NSFont *font = nil;
    if (credits.length > 0)
        font = [credits attribute:NSFontAttributeName atIndex:0 effectiveRange:NULL];
    if (font == nil)
        font = [NSFont systemFontOfSize:NSFont.smallSystemFontSize];

    NSMutableParagraphStyle *centered = [[NSMutableParagraphStyle alloc] init];
    centered.alignment = NSTextAlignmentCenter;

    NSMutableAttributedString *result = [[NSMutableAttributedString alloc] init];
    [result appendAttributedString:[[NSAttributedString alloc] initWithString:TSAboutWebsiteAddress attributes:@{
        NSLinkAttributeName: url,
        NSFontAttributeName: font,
        NSParagraphStyleAttributeName: centered,
    }]];
    [result appendAttributedString:[[NSAttributedString alloc] initWithString:@"\n\n" attributes:@{
        NSFontAttributeName: font,
        NSParagraphStyleAttributeName: centered,
    }]];
    if (credits != nil)
        [result appendAttributedString:credits];
    return result;
}

// The localized Credits.rtf of the bundle, or nil when it cannot be read.
static inline NSAttributedString *TSAboutBundleCredits(NSBundle *bundle)
{
    NSURL *url = [bundle URLForResource:@"Credits" withExtension:@"rtf"];
    if (url == nil)
        return nil;
    return [[NSAttributedString alloc] initWithURL:url options:@{} documentAttributes:NULL error:NULL];
}
