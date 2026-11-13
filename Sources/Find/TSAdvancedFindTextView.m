// SPDX-License-Identifier: GPL-2.0-or-later
#import "TSAdvancedFindTextView.h"
#import "TSAdvancedFindHighlights.h"

@implementation TSAdvancedFindLayoutManager

- (void)drawBackgroundForGlyphRange:(NSRange)glyphsToShow atPoint:(NSPoint)origin
{
    [super drawBackgroundForGlyphRange:glyphsToShow atPoint:origin];
    [TSAdvancedFindHighlights drawInLayoutManager:self forGlyphRange:glyphsToShow atPoint:origin];
}

+ (void)installInTextView:(NSTextView *)textView
{
    NSLayoutManager *old = textView.layoutManager;
    if (!old || [old conformsToProtocol:@protocol(TSAdvancedFindHighlightDrawing)])
        return;
    TSAdvancedFindLayoutManager *layout = [self new];
    layout.allowsNonContiguousLayout = old.allowsNonContiguousLayout;
    layout.backgroundLayoutEnabled = old.backgroundLayoutEnabled;
    layout.showsInvisibleCharacters = old.showsInvisibleCharacters;
    layout.showsControlCharacters = old.showsControlCharacters;
    layout.usesFontLeading = old.usesFontLeading;
    layout.delegate = old.delegate;
    // Moves the text storage and every text container of the old layout manager over to the new one.
    [textView.textContainer replaceLayoutManager:layout];
}

@end

@implementation TSAdvancedFindController (TextViews)

static __weak NSTextView *TSTestTargetTextView;

+ (nullable NSTextView *)testTargetTextView
{
    return TSTestTargetTextView;
}

+ (void)setTestTargetTextView:(nullable NSTextView *)textView
{
    TSTestTargetTextView = textView;
}

+ (nullable NSTextView *)targetTextView
{
    if (TSTestTargetTextView)
        return TSTestTargetTextView;
    NSResponder *responder = NSApp.mainWindow.firstResponder;
    return [responder isKindOfClass:[NSTextView class]] ? (NSTextView *)responder : nil;
}

- (void)performFindPanelAction:(id)sender inTextView:(NSTextView *)textView
{
    NSInteger tag = [sender respondsToSelector:@selector(tag)] ? [sender tag] : 0;
    [self performAction:(TSAdvancedFindAction)tag inTextView:textView];
}

- (BOOL)validateFindMenuItem:(NSMenuItem *)item inTextView:(NSTextView *)textView
{
    return [self validateAction:(TSAdvancedFindAction)item.tag forTextView:textView];
}

@end

@implementation TSAdvancedFindTextView

- (instancetype)initWithFrame:(NSRect)frame textContainer:(nullable NSTextContainer *)container
{
    if ((self = [super initWithFrame:frame textContainer:container]))
        [TSAdvancedFindLayoutManager installInTextView:self];
    return self;
}

/// Made in code as TeXShop's Experiment output is ([NSTextView initWithFrame:]): the text system is Apple's, and asking
/// for its layout manager makes it the TextKit 1 one that TeXShop uses everywhere.
- (instancetype)initWithFrame:(NSRect)frame
{
    if ((self = [super initWithFrame:frame]))
        [TSAdvancedFindLayoutManager installInTextView:self];
    return self;
}

- (void)awakeFromNib
{
    [super awakeFromNib];
    [TSAdvancedFindLayoutManager installInTextView:self]; // from a nib (the console): the text system is complete now
}

- (void)performFindPanelAction:(id)sender
{
    TSAdvancedFindController *controller = self.findController;
    if (controller)
        [controller performFindPanelAction:sender inTextView:self];
    else
        [super performFindPanelAction:sender];
}

- (void)performTextFinderAction:(id)sender
{
    if (self.findController)
        [self performFindPanelAction:sender];
    else
        [super performTextFinderAction:sender];
}

- (BOOL)validateMenuItem:(NSMenuItem *)item
{
    TSAdvancedFindController *controller = self.findController;
    if (controller && (item.action == @selector(performFindPanelAction:) || item.action == @selector(performTextFinderAction:)))
        return [controller validateFindMenuItem:item inTextView:self];
    return [super validateMenuItem:item];
}

@end
