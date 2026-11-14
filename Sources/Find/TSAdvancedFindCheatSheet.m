// SPDX-License-Identifier: GPL-2.0-or-later
#import "TSAdvancedFindCheatSheet.h"
#import "TSAdvancedFindController.h"
#import "TSRegexOnigmoIncompatibility.h"

#define TSLocalized TSAdvancedFindLocalized

typedef struct {
    __unsafe_unretained NSString *term;
    __unsafe_unretained NSString *key;
    __unsafe_unretained NSString *english;
} TSCheatRow;

static const TSCheatRow TSCharacterRows[] = {
    {@".", @"AdvancedFind.Cheat.AnyCharacter", @"any character but a line break"},
    {@"\\R", @"AdvancedFind.Cheat.LineBreak", @"a line break (LF, CR LF, CR …)"},
    {@"\\w", @"AdvancedFind.Cheat.WordCharacter", @"a letter, digit or _, also kanji and kana"},
    {@"\\s", @"AdvancedFind.Cheat.Space", @"a space, tab or line break, also the full-width space"},
    {@"\\d", @"AdvancedFind.Cheat.Digit", @"a digit, also full-width digits"},
    {@"[abc]", @"AdvancedFind.Cheat.AnyOf", @"a, b or c"},
    {@"[^abc]", @"AdvancedFind.Cheat.NoneOf", @"any character but a, b and c"},
    {@"[a-z]", @"AdvancedFind.Cheat.Range", @"a character from a to z"},
    {@"\\p{Han}", @"AdvancedFind.Cheat.Han", @"a kanji (\\p{Hiragana}, \\p{Katakana} likewise)"},
    {@"\\. \\\\ \\(", @"AdvancedFind.Cheat.Escaped", @"the character . \\ ( itself"},
};

static const TSCheatRow TSAnchorRows[] = {
    {@"^", @"AdvancedFind.Cheat.LineStart", @"start of a line"},
    {@"$", @"AdvancedFind.Cheat.LineEnd", @"end of a line"},
    {@"\\b", @"AdvancedFind.Cheat.WordBoundary", @"word boundary"},
};

static const TSCheatRow TSQuantifierRows[] = {
    {@"?", @"AdvancedFind.Cheat.ZeroOrOne", @"0 or 1 time"},
    {@"*", @"AdvancedFind.Cheat.ZeroOrMore", @"0 or more times"},
    {@"+", @"AdvancedFind.Cheat.OneOrMore", @"1 or more times"},
    {@"{n}", @"AdvancedFind.Cheat.Exactly", @"n times"},
    {@"{n,m}", @"AdvancedFind.Cheat.Between", @"n to m times"},
    {@"{0,n}", @"AdvancedFind.Cheat.AtMost", @"up to n times ({,n} is an error)"},
    {@"*? +? ??", @"AdvancedFind.Cheat.Lazy", @"as few times as possible"},
};

static const TSCheatRow TSGroupRows[] = {
    {@"(…)", @"AdvancedFind.Cheat.Group", @"a group, numbered from 1"},
    {@"(?<name>…)", @"AdvancedFind.Cheat.NamedGroup", @"a named group"},
    {@"(?:…)", @"AdvancedFind.Cheat.NonCapturing", @"a group without a number"},
    {@"a|b", @"AdvancedFind.Cheat.Alternation", @"a or b"},
    {@"(?=…) (?!…)", @"AdvancedFind.Cheat.LookAhead", @"followed or not followed by …"},
    {@"(?<=…) (?<!…)", @"AdvancedFind.Cheat.LookBehind", @"preceded or not preceded by …"},
    {@"(?i)", @"AdvancedFind.Cheat.CaseFlag", @"ignore case from here on"},
};

static const TSCheatRow TSICURows[] = {
    {@"$0", @"AdvancedFind.Cheat.WholeMatch", @"the whole match"},
    {@"$1", @"AdvancedFind.Cheat.GroupOne", @"group 1"},
    {@"\\$", @"AdvancedFind.Cheat.Dollar", @"a $ (in TeX math, write \\$…\\$)"},
    {@"\\\\", @"AdvancedFind.Cheat.Backslash", @"one \\ (write \\\\section for \\section)"},
    {@"\\n \\t", @"AdvancedFind.Cheat.LineBreakTabUnescaped", @"a line break and a tab, when the replacement's \\n and \\t are read"},
    {@"\\1 \\g<name>", @"AdvancedFind.Cheat.OgreKitStyle", @"OgreKit style: choose it in More Options"},
};

static const TSCheatRow TSOgreKitRows[] = {
    {@"\\0 \\&", @"AdvancedFind.Cheat.WholeMatch", @"the whole match"},
    {@"\\1", @"AdvancedFind.Cheat.GroupOne", @"group 1"},
    {@"\\g<name>", @"AdvancedFind.Cheat.NamedReference", @"the group named name"},
    {@"$", @"AdvancedFind.Cheat.DollarAsIs", @"a $ as it is (TeX math as it is)"},
    {@"\\\\", @"AdvancedFind.Cheat.Backslash", @"one \\ (write \\\\section for \\section)"},
    {@"\\n \\t", @"AdvancedFind.Cheat.LineBreakTab", @"a line break and a tab"},
    {@"$1", @"AdvancedFind.Cheat.ICUStyle", @"ICU style: choose it in More Options"},
};

#define TSCount(array) (sizeof array / sizeof array[0])

/// The width of a description column: long ones wrap, so the popover keeps its size in every language.
static const CGFloat TSDescriptionWidth = 170;

@interface TSAdvancedFindCheatSheet ()
/// Find, Replace, Differences from OgreKit; one is shown at a time, in a room as large as the largest.
@property (nonatomic, copy) NSArray<NSView *> *pages;
@property (nonatomic, strong) NSView *pageArea;
/// The width of the find page, which the other pages take too.
@property (nonatomic) CGFloat pageWidth;
@property (nonatomic, strong) NSSegmentedControl *tabs;
@property (nonatomic, readwrite) NSInteger selectedPage;
@property (nonatomic, readwrite, copy) NSArray<NSString *> *terms;
@end

@implementation TSAdvancedFindCheatSheet

+ (NSURL *)icuGuideURL
{
    return (NSURL *_Nonnull)[NSURL URLWithString:@"https://unicode-org.github.io/icu/userguide/strings/regexp.html"];
}

- (instancetype)initWithReplacementSyntax:(TSRegexReplacementSyntax)syntax
{
    if ((self = [super initWithNibName:nil bundle:nil]))
        _replacementSyntax = syntax;
    return self;
}

#pragma mark Parts

+ (NSTextField *)termLabel:(NSString *)term
{
    NSTextField *label = [NSTextField labelWithString:term];
    label.font = [NSFont monospacedSystemFontOfSize:NSFont.smallSystemFontSize weight:NSFontWeightMedium];
    label.selectable = YES; // to copy a term into the field
    [label setContentCompressionResistancePriority:NSLayoutPriorityRequired forOrientation:NSLayoutConstraintOrientationHorizontal];
    [label setContentCompressionResistancePriority:NSLayoutPriorityRequired forOrientation:NSLayoutConstraintOrientationVertical];
    return label;
}

+ (NSTextField *)descriptionLabel:(NSString *)text width:(CGFloat)width
{
    NSTextField *label = [NSTextField wrappingLabelWithString:text];
    NSFont *font = [NSFont systemFontOfSize:NSFont.smallSystemFontSize];
    label.font = font;
    label.textColor = NSColor.secondaryLabelColor;
    label.selectable = NO;
    // Its own width up to `width`, then it wraps: a grid would otherwise squeeze it to its narrowest.
    CGFloat natural = ceil([text sizeWithAttributes:@{NSFontAttributeName: font}].width) + 4;
    CGFloat fixed = MIN(natural, width);
    label.preferredMaxLayoutWidth = fixed;
    [label.widthAnchor constraintEqualToConstant:fixed].active = YES;
    [label setContentCompressionResistancePriority:NSLayoutPriorityRequired forOrientation:NSLayoutConstraintOrientationVertical];
    return label;
}

+ (NSTextField *)heading:(NSString *)title
{
    NSTextField *label = [NSTextField labelWithString:title];
    label.font = [NSFont boldSystemFontOfSize:NSFont.smallSystemFontSize];
    label.textColor = NSColor.secondaryLabelColor;
    label.identifier = @"section";
    // Not squeezed when the sheet is measured: the fitting size would leave a heading a few points high.
    [label setContentCompressionResistancePriority:NSLayoutPriorityRequired forOrientation:NSLayoutConstraintOrientationVertical];
    return label;
}

/// A heading and a grid of terms and their descriptions.
- (NSStackView *)section:(NSString *)title terms:(NSArray<NSString *> *)terms descriptions:(NSArray<NSString *> *)descriptions width:(CGFloat)width
{
    NSMutableArray<NSArray<NSView *> *> *rows = [NSMutableArray array];
    for (NSUInteger i = 0; i < terms.count; i++)
        [rows addObject:@[[TSAdvancedFindCheatSheet termLabel:terms[i]], [TSAdvancedFindCheatSheet descriptionLabel:descriptions[i] width:width]]];
    NSGridView *grid = [NSGridView gridViewWithViews:rows];
    grid.rowSpacing = 3;
    grid.columnSpacing = 10;
    grid.rowAlignment = NSGridRowAlignmentFirstBaseline;
    [grid setContentHuggingPriority:NSLayoutPriorityDefaultHigh forOrientation:NSLayoutConstraintOrientationVertical];
    NSStackView *section = [NSStackView stackViewWithViews:@[[TSAdvancedFindCheatSheet heading:title], grid]];
    section.orientation = NSUserInterfaceLayoutOrientationVertical;
    section.alignment = NSLayoutAttributeLeading;
    section.spacing = 4;
    return section;
}

- (NSStackView *)section:(NSString *)title rows:(const TSCheatRow *)rows count:(size_t)count
{
    return [self section:title rows:rows count:count pageWidth:0];
}

/// With a page width, the descriptions take what the widest term leaves of it; otherwise a column's width.
- (NSStackView *)section:(NSString *)title rows:(const TSCheatRow *)rows count:(size_t)count pageWidth:(CGFloat)pageWidth
{
    NSMutableArray<NSString *> *terms = [NSMutableArray array], *descriptions = [NSMutableArray array];
    CGFloat termWidth = 0;
    NSFont *termFont = [TSAdvancedFindCheatSheet termLabel:@""].font;
    for (size_t i = 0; i < count; i++) {
        [terms addObject:rows[i].term];
        [descriptions addObject:TSLocalized(rows[i].key, rows[i].english)];
        termWidth = MAX(termWidth, ceil([rows[i].term sizeWithAttributes:@{NSFontAttributeName: termFont}].width) + 4);
    }
    CGFloat width = pageWidth > 0 ? pageWidth - termWidth - 14 : TSDescriptionWidth;
    return [self section:title terms:terms descriptions:descriptions width:width];
}

- (NSStackView *)makeReplacementSectionWithWidth:(CGFloat)width
{
    BOOL ogreKit = self.replacementSyntax == TSRegexReplacementSyntaxOgreKit;
    NSString *title = ogreKit ? TSLocalized(@"AdvancedFind.Cheat.ReplacementOgreKit", @"Replacement (OgreKit style)")
                              : TSLocalized(@"AdvancedFind.Cheat.ReplacementICU", @"Replacement (ICU style)");
    return ogreKit ? [self section:title rows:TSOgreKitRows count:TSCount(TSOgreKitRows) pageWidth:width]
                   : [self section:title rows:TSICURows count:TSCount(TSICURows) pageWidth:width];
}

- (NSStackView *)column:(NSArray<NSView *> *)sections
{
    // An empty view last takes the height the other column is taller by, so the sections stay together at the top.
    NSView *rest = [NSView new];
    [rest setContentHuggingPriority:1 forOrientation:NSLayoutConstraintOrientationVertical];
    NSStackView *column = [NSStackView stackViewWithViews:[sections arrayByAddingObject:rest]];
    column.distribution = NSStackViewDistributionFill;
    column.orientation = NSUserInterfaceLayoutOrientationVertical;
    column.alignment = NSLayoutAttributeLeading;
    column.spacing = 14;
    return column;
}

/// The everyday syntax in two columns.
- (NSView *)makeFindPage
{
    NSStackView *left = [self column:@[[self section:TSLocalized(@"AdvancedFind.Cheat.Characters", @"Characters") rows:TSCharacterRows count:TSCount(TSCharacterRows)],
                                       [self section:TSLocalized(@"AdvancedFind.Cheat.Anchors", @"Anchors") rows:TSAnchorRows count:TSCount(TSAnchorRows)]]];
    NSStackView *right = [self column:@[[self section:TSLocalized(@"AdvancedFind.Cheat.Quantifiers", @"Repetition") rows:TSQuantifierRows count:TSCount(TSQuantifierRows)],
                                        [self section:TSLocalized(@"AdvancedFind.Cheat.Groups", @"Groups") rows:TSGroupRows count:TSCount(TSGroupRows)]]];
    NSBox *divider = [NSBox new];
    divider.boxType = NSBoxSeparator;
    divider.titlePosition = NSNoTitle; // its hidden title label would be laid out with no height
    NSStackView *columns = [NSStackView stackViewWithViews:@[left, divider, right]];
    columns.alignment = NSLayoutAttributeTop;
    columns.spacing = 14;
    [divider.heightAnchor constraintEqualToAnchor:columns.heightAnchor].active = YES;
    return columns;
}

/// As wide as the find page.
- (NSView *)makeReplacePage
{
    return [self column:@[[self makeReplacementSectionWithWidth:self.pageWidth]]];
}

/// The differences from OgreKit, from the engine's table that the find field's marks use too; as wide as the find page.
- (NSView *)makeDifferencesPageWithWidth:(CGFloat)width
{
    NSMutableArray<NSString *> *terms = [NSMutableArray array], *messages = [NSMutableArray array];
    CGFloat termWidth = 0;
    NSFont *termFont = [TSAdvancedFindCheatSheet termLabel:@""].font;
    for (TSRegexOnigmoIncompatibility *entry in TSRegexFindPattern.onigmoIncompatibilities) {
        [terms addObject:entry.term];
        [messages addObject:entry.message];
        termWidth = MAX(termWidth, ceil([entry.term sizeWithAttributes:@{NSFontAttributeName: termFont}].width) + 4);
    }
    NSStackView *section = [self section:TSLocalized(@"AdvancedFind.Cheat.Differences", @"Differences from OgreKit")
                                   terms:terms descriptions:messages width:width - termWidth - 10];
    return [self column:@[section]];
}

- (void)loadView
{
    self.tabs = [NSSegmentedControl segmentedControlWithLabels:@[TSLocalized(@"AdvancedFind.Cheat.FindTab", @"Find"),
                                                                 TSLocalized(@"AdvancedFind.Cheat.ReplaceTab", @"Replace"),
                                                                 TSLocalized(@"AdvancedFind.Cheat.Differences", @"Differences from OgreKit")]
                                                  trackingMode:NSSegmentSwitchTrackingSelectOne target:self action:@selector(tabChanged:)];
    self.tabs.controlSize = NSControlSizeSmall;
    self.tabs.font = [NSFont systemFontOfSize:NSFont.smallSystemFontSize];
    self.tabs.selectedSegment = 0;
    self.tabs.accessibilityLabel = TSLocalized(@"AdvancedFind.Cheat.Title", @"Regular Expression Reference");

    NSView *find = [self makeFindPage];
    [find layoutSubtreeIfNeeded];
    self.pageWidth = find.fittingSize.width;
    NSView *replace = [self makeReplacePage];
    NSView *differences = [self makeDifferencesPageWithWidth:self.pageWidth];
    self.pages = @[find, replace, differences];
    // Every page stays in the room, the others hidden: the room is as large as the largest page, so the popover
    // keeps its size when the tab changes.
    self.pageArea = [NSView new];
    for (NSView *page in self.pages)
        [self addPage:page];
    NSTextField *conforms = [NSTextField labelWithString:TSLocalized(@"AdvancedFind.Cheat.Conforms", @"The syntax is that of ICU regular expressions.")];
    conforms.font = [NSFont systemFontOfSize:NSFont.smallSystemFontSize];
    conforms.textColor = NSColor.secondaryLabelColor;
    NSButton *link = [NSButton buttonWithTitle:@"" target:self action:@selector(openICUGuide:)];
    link.bordered = NO;
    link.attributedTitle = [[NSAttributedString alloc] initWithString:TSLocalized(@"AdvancedFind.Cheat.ICUGuide", @"ICU User Guide")
        attributes:@{NSFontAttributeName: [NSFont systemFontOfSize:NSFont.smallSystemFontSize], NSForegroundColorAttributeName: NSColor.linkColor,
                     NSUnderlineStyleAttributeName: @(NSUnderlineStyleSingle)}];
    link.toolTip = TSAdvancedFindCheatSheet.icuGuideURL.absoluteString;
    NSStackView *footer = [NSStackView stackViewWithViews:@[conforms, link]];
    footer.spacing = 4;
    footer.alignment = NSLayoutAttributeFirstBaseline;

    NSStackView *content = [NSStackView stackViewWithViews:@[self.tabs, self.pageArea, footer]];
    content.orientation = NSUserInterfaceLayoutOrientationVertical;
    content.alignment = NSLayoutAttributeCenterX;
    content.spacing = 12;
    content.edgeInsets = NSEdgeInsetsMake(12, 16, 14, 16);
    // NSStackView's right inset is only a weak constraint: each row is kept inside it.
    for (NSView *row in @[self.tabs, self.pageArea, footer])
        [row.trailingAnchor constraintLessThanOrEqualToAnchor:content.trailingAnchor constant:-16].active = YES;
    [footer.leadingAnchor constraintEqualToAnchor:self.pageArea.leadingAnchor].active = YES;
    self.view = content;
    [self showPage:0];
    [self noteTerms];
    [self fitToContent];
}

/// Measured again when shown, in the appearance it is drawn in and whatever size it was given; the popover follows
/// preferredContentSize.
- (void)viewWillAppear
{
    [super viewWillAppear];
    [self fitToContent];
}

/// Lays the sheet out at its fitting size until that size holds: wrapped descriptions can change their height
/// once they have been laid out at their width.
- (void)fitToContent
{
    NSView *content = self.view;
    for (int pass = 0; pass < 4; pass++) {
        [content layoutSubtreeIfNeeded];
        NSSize size = content.fittingSize;
        if (NSEqualSizes(size, content.frame.size))
            break;
        [content setFrameSize:size];
    }
    self.preferredContentSize = content.frame.size;
}

- (void)addPage:(NSView *)page
{
    page.translatesAutoresizingMaskIntoConstraints = NO;
    [self.pageArea addSubview:page];
    [NSLayoutConstraint activateConstraints:@[
        [page.topAnchor constraintEqualToAnchor:self.pageArea.topAnchor],
        [page.leadingAnchor constraintEqualToAnchor:self.pageArea.leadingAnchor],
        // A wrapping label's frame is 2 points wider on each side than its layout rectangle.
        [page.trailingAnchor constraintLessThanOrEqualToAnchor:self.pageArea.trailingAnchor constant:-2],
        [page.bottomAnchor constraintLessThanOrEqualToAnchor:self.pageArea.bottomAnchor],
    ]];
}

- (void)showPage:(NSInteger)index
{
    for (NSUInteger i = 0; i < self.pages.count; i++)
        self.pages[i].hidden = (NSInteger)i != index;
    self.selectedPage = index;
    self.tabs.selectedSegment = index;
}

- (void)selectPage:(NSInteger)index
{
    [self view];
    [self showPage:index];
    [self.view layoutSubtreeIfNeeded];
}

- (void)tabChanged:(NSSegmentedControl *)sender
{
    [self selectPage:sender.selectedSegment];
}

/// Every term of every page, in order.
- (void)noteTerms
{
    NSMutableArray<NSString *> *terms = [NSMutableArray array];
    NSMutableArray<NSView *> *pending = [self.pages mutableCopy];
    while (pending.count) {
        NSView *view = pending.firstObject;
        [pending removeObjectAtIndex:0];
        if ([view isKindOfClass:[NSGridView class]]) {
            NSGridView *grid = (NSGridView *)view;
            for (NSInteger row = 0; row < grid.numberOfRows; row++)
                [terms addObject:((NSTextField *)[grid cellAtColumnIndex:0 rowIndex:row].contentView).stringValue];
        } else
            [pending insertObjects:view.subviews atIndexes:[NSIndexSet indexSetWithIndexesInRange:NSMakeRange(0, view.subviews.count)]];
    }
    self.terms = terms;
}

/// The replacement page is made again; the room stays as it is unless the new page needs more.
- (void)setReplacementSyntax:(TSRegexReplacementSyntax)syntax
{
    if (syntax == _replacementSyntax)
        return;
    _replacementSyntax = syntax;
    if (!self.isViewLoaded)
        return;
    NSMutableArray<NSView *> *pages = [self.pages mutableCopy];
    [pages[1] removeFromSuperview];
    pages[1] = [self makeReplacePage];
    self.pages = pages;
    [self addPage:pages[1]];
    [self showPage:self.selectedPage];
    [self noteTerms];
    [self fitToContent];
}

- (void)openICUGuide:(id)sender
{
    [NSWorkspace.sharedWorkspace openURL:TSAdvancedFindCheatSheet.icuGuideURL];
}

@end
