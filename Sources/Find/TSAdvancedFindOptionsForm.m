// SPDX-License-Identifier: GPL-2.0-or-later
#import "TSAdvancedFindOptionsForm.h"
#import "TSAdvancedFindController.h"

typedef struct {
    TSRegexFindOptions option;
    __unsafe_unretained NSString *key;
    __unsafe_unretained NSString *english;
} TSOptionItem;

static const TSOptionItem TSTextItems[] = {
    {TSRegexFindWholeWord, @"AdvancedFind.WholeWord", @"Match whole words only"},
    {TSRegexFindDelimitByWhitespace, @"AdvancedFind.DelimitByWhitespace", @"Find any of the words separated by spaces"},
    {TSRegexFindIgnoreDiacritics, @"AdvancedFind.IgnoreDiacritics", @"Ignore diacritical marks"},
    {TSRegexFindIgnoreWidth, @"AdvancedFind.IgnoreWidth", @"Ignore full-width and half-width differences"},
    {TSRegexFindLiteral, @"AdvancedFind.Literal", @"Distinguish characters strictly"},
};

static const TSOptionItem TSRegexItems[] = {
    {TSRegexFindIgnoreMetacharacters, @"AdvancedFind.IgnoreMetacharacters", @"Treat the find pattern literally"},
    {TSRegexFindDotMatchesLineSeparators, @"AdvancedFind.DotMatchesLineSeparators", @". matches line breaks"},
    {TSRegexFindAnchorsMatchLines, @"AdvancedFind.AnchorsMatchLines", @"^ and $ match at each line"},
    {TSRegexFindUseUnixLineSeparators, @"AdvancedFind.UseUnixLineSeparators", @"Only Unix line breaks (LF) end lines"},
    {TSRegexFindAllowCommentsAndWhitespace, @"AdvancedFind.Extended", @"Ignore spaces and # comments in the pattern"},
    {TSRegexFindUnicodeWordBoundaries, @"AdvancedFind.UnicodeWordBoundaries", @"Use Unicode word boundaries"},
    {TSRegexFindIgnoreEmptyMatches, @"AdvancedFind.IgnoreEmptyMatches", @"Ignore empty matches"},
};

static NSString *const TSSideText = @"text";
static NSString *const TSSideRegex = @"regex";
static NSString *const TSSideBoth = @"both";
static NSString *const TSUnescapes = @"unescapes";
static NSString *const TSSyntax = @"replacementSyntax";

@interface TSAdvancedFindOptionsForm ()
@property (nonatomic, readwrite) TSRegexFindOptions textualOptions;
@property (nonatomic, readwrite) TSRegexFindOptions regularExpressionOptions;
@property (nonatomic, readwrite) TSRegexReplacementSyntax replacementSyntax;
@property (nonatomic, readonly) NSMutableArray<NSControl *> *controls;
@property (nonatomic, readonly) NSHashTable<NSView *> *pinnedRows;
@end

@implementation TSAdvancedFindOptionsForm

+ (TSRegexFindOptions)textualItemOptions
{
    TSRegexFindOptions options = 0;
    for (size_t i = 0; i < sizeof TSTextItems / sizeof TSTextItems[0]; i++)
        options |= TSTextItems[i].option;
    return options;
}

- (instancetype)initWithStyle:(TSAdvancedFindOptionsFormStyle)style textualOptions:(TSRegexFindOptions)textualOptions
     regularExpressionOptions:(TSRegexFindOptions)regularExpressionOptions replacementSyntax:(TSRegexReplacementSyntax)replacementSyntax
{
    if ((self = [super init])) {
        _style = style;
        _textualOptions = textualOptions;
        _regularExpressionOptions = regularExpressionOptions;
        _replacementSyntax = replacementSyntax;
        _usesRegularExpression = (regularExpressionOptions & TSRegexFindRegularExpression) != 0;
        _controls = [NSMutableArray array];
        _pinnedRows = [NSHashTable weakObjectsHashTable];
        _view = [self makeView];
        [self updateEnabled];
    }
    return self;
}

/// A section title: bold, in the size of the small check boxes under it (CotEditor's options).
- (NSTextField *)sectionTitle:(NSString *)key english:(NSString *)english
{
    NSTextField *title = [NSTextField labelWithString:TSAdvancedFindLocalized(key, english)];
    title.font = [NSFont boldSystemFontOfSize:NSFont.smallSystemFontSize];
    title.identifier = @"section";
    return title;
}

+ (void)makeSmall:(NSControl *)control
{
    control.controlSize = NSControlSizeSmall;
    control.font = [NSFont systemFontOfSize:NSFont.smallSystemFontSize];
}

- (NSButton *)box:(TSOptionItem)item side:(NSString *)side on:(BOOL)on
{
    NSButton *box = [NSButton checkboxWithTitle:TSAdvancedFindLocalized(item.key, item.english) target:self action:@selector(changed:)];
    box.tag = (NSInteger)item.option;
    box.identifier = side;
    box.state = on ? NSControlStateValueOn : NSControlStateValueOff;
    [TSAdvancedFindOptionsForm makeSmall:box];
    [self.controls addObject:box];
    return box;
}

- (NSStackView *)makeView
{
    NSMutableArray<NSView *> *rows = [NSMutableArray array];
    [rows addObject:[self sectionTitle:@"AdvancedFind.Section.Text" english:@"Text Search"]];
    for (size_t i = 0; i < sizeof TSTextItems / sizeof TSTextItems[0]; i++)
        [rows addObject:[self box:TSTextItems[i] side:TSSideText on:(self.textualOptions & TSTextItems[i].option) != 0]];
    [rows addObject:[self sectionTitle:@"AdvancedFind.Section.Regex" english:@"Regular Expression"]];
    for (size_t i = 0; i < sizeof TSRegexItems / sizeof TSRegexItems[0]; i++)
        [rows addObject:[self box:TSRegexItems[i] side:TSSideRegex on:(self.regularExpressionOptions & TSRegexItems[i].option) != 0]];

    NSPopUpButton *syntax = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    [syntax addItemsWithTitles:@[TSAdvancedFindLocalized(@"AdvancedFind.Syntax.ICU", @"ICU ($1)"),
                                 TSAdvancedFindLocalized(@"AdvancedFind.Syntax.OgreKit", @"OgreKit (\\1)")]];
    [syntax selectItemAtIndex:self.replacementSyntax == TSRegexReplacementSyntaxOgreKit ? 1 : 0];
    syntax.identifier = TSSyntax;
    [TSAdvancedFindOptionsForm makeSmall:syntax];
    syntax.target = self;
    syntax.action = @selector(changed:);
    [self.controls addObject:syntax];
    NSTextField *syntaxLabel = [NSTextField labelWithString:TSAdvancedFindLocalized(@"AdvancedFind.SyntaxLabel", @"Replacement syntax:")];
    syntaxLabel.font = [NSFont systemFontOfSize:NSFont.smallSystemFontSize];
    [rows addObject:[NSStackView stackViewWithViews:@[syntaxLabel, syntax]]];
    TSOptionItem unescapes = {TSRegexFindUnescapesReplacement, @"AdvancedFind.Unescapes", @"Read \\n, \\t and other escapes in the replacement"};
    [rows addObject:[self box:unescapes side:TSUnescapes on:(self.regularExpressionOptions & TSRegexFindUnescapesReplacement) != 0]];

    [rows addObject:[self sectionTitle:@"AdvancedFind.Section.Common" english:@"Both"]];
    TSOptionItem yen = {TSRegexFindYenIsBackslash, @"AdvancedFind.YenIsBackslash", @"Treat ¥ as \\"};
    [rows addObject:[self box:yen side:TSSideBoth on:((self.textualOptions | self.regularExpressionOptions) & TSRegexFindYenIsBackslash) != 0]];

    NSStackView *stack = [NSStackView stackViewWithViews:rows];
    stack.orientation = NSUserInterfaceLayoutOrientationVertical;
    stack.alignment = NSLayoutAttributeLeading;
    stack.spacing = 5;
    // More room on the right: the popover's rounded edge comes close to the longest rows.
    stack.edgeInsets = NSEdgeInsetsMake(14, 18, 16, 26);
    [self spaceSectionsOf:stack];
    return stack;
}

/// 4 points under a section title, 14 above the next one: the sections read as groups.
- (void)spaceSectionsOf:(NSStackView *)stack
{
    NSArray<NSView *> *rows = stack.arrangedSubviews;
    for (NSUInteger i = 0; i < rows.count; i++) {
        BOOL title = [rows[i] isKindOfClass:[NSTextField class]] && ((NSTextField *)rows[i]).font.pointSize <= NSFont.smallSystemFontSize
            && [rows[i].identifier isEqualToString:@"section"];
        if (title) {
            [stack setCustomSpacing:4 afterView:rows[i]];
            if (i > 0)
                [stack setCustomSpacing:14 afterView:rows[i - 1]];
        }
        [rows[i] setContentCompressionResistancePriority:NSLayoutPriorityRequired forOrientation:NSLayoutConstraintOrientationHorizontal];
        // The stack keeps its right inset only weakly: without this, the longest row touched the popover's edge.
        if (![self.pinnedRows containsObject:rows[i]]) {
            [rows[i].trailingAnchor constraintLessThanOrEqualToAnchor:stack.trailingAnchor constant:-stack.edgeInsets.right].active = YES;
            [self.pinnedRows addObject:rows[i]];
        }
    }
}

- (void)addSectionTitle:(NSString *)title rows:(NSArray<NSView *> *)rows
{
    NSTextField *label = [NSTextField labelWithString:title];
    label.font = [NSFont boldSystemFontOfSize:NSFont.smallSystemFontSize];
    label.identifier = @"section";
    [self.view addArrangedSubview:label];
    for (NSView *row in rows) {
        if ([row isKindOfClass:[NSControl class]])
            [TSAdvancedFindOptionsForm makeSmall:(NSControl *)row];
        [self.view addArrangedSubview:row];
    }
    [self spaceSectionsOf:self.view];
}

- (void)insertTitle:(NSString *)title rows:(NSArray<NSView *> *)rows
{
    NSStackView *stack = self.view;
    NSTextField *label = [NSTextField labelWithString:title];
    label.font = [NSFont boldSystemFontOfSize:NSFont.systemFontSize];
    label.textColor = NSColor.secondaryLabelColor;
    label.alignment = NSTextAlignmentCenter;
    [stack insertArrangedSubview:label atIndex:0];
    [label.widthAnchor constraintEqualToAnchor:stack.widthAnchor constant:-(stack.edgeInsets.left + stack.edgeInsets.right)].active = YES;
    [stack setCustomSpacing:10 afterView:label];
    NSUInteger index = 1;
    for (NSView *row in rows) {
        if ([row isKindOfClass:[NSControl class]])
            [TSAdvancedFindOptionsForm makeSmall:(NSControl *)row];
        [stack insertArrangedSubview:row atIndex:index++];
    }
    [self spaceSectionsOf:stack];
}

- (void)setUsesRegularExpression:(BOOL)usesRegularExpression
{
    _usesRegularExpression = usesRegularExpression;
    [self updateEnabled];
}

- (void)updateEnabled
{
    BOOL panel = self.style == TSAdvancedFindOptionsFormStylePanel;
    BOOL regex = !panel || self.usesRegularExpression;
    BOOL text = !panel || !self.usesRegularExpression;
    for (NSControl *control in self.controls) {
        NSString *side = control.identifier;
        if ([side isEqualToString:TSSideText])
            control.enabled = text;
        else if ([side isEqualToString:TSUnescapes])
            control.enabled = regex && self.replacementSyntax == TSRegexReplacementSyntaxICU;
        else if ([side isEqualToString:TSSideRegex] || [side isEqualToString:TSSyntax])
            control.enabled = regex;
    }
}

- (void)changed:(NSControl *)sender
{
    NSString *side = sender.identifier;
    if ([side isEqualToString:TSSyntax]) {
        self.replacementSyntax = ((NSPopUpButton *)sender).indexOfSelectedItem == 1 ? TSRegexReplacementSyntaxOgreKit : TSRegexReplacementSyntaxICU;
    } else {
        TSRegexFindOptions bit = (TSRegexFindOptions)sender.tag;
        BOOL on = ((NSButton *)sender).state == NSControlStateValueOn;
        if ([side isEqualToString:TSSideText] || [side isEqualToString:TSSideBoth])
            self.textualOptions = on ? self.textualOptions | bit : self.textualOptions & ~bit;
        if (![side isEqualToString:TSSideText])
            self.regularExpressionOptions = on ? self.regularExpressionOptions | bit : self.regularExpressionOptions & ~bit;
    }
    [self updateEnabled];
    if (self.changeHandler)
        self.changeHandler(self);
}

@end
