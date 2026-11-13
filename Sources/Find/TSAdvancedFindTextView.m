// SPDX-License-Identifier: GPL-2.0-or-later
#import "TSAdvancedFindTextView.h"
#import "TSAdvancedFindHighlights.h"
#import "TSAdvancedFindPanelController.h"
#import "TSFindInterface.h"
#import "globals.h"

TSAdvancedFindController *_Nullable TSAdvancedFindControllerForFindMethod(void)
{
    if ([SUD integerForKey:FindMethodKey] != TSFindMethodAdvancedPanel)
        return nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        // The text of a document has LF line endings unless ConvertLF is off; then its own line endings are kept.
        TSAdvancedFindController.sharedController.lineEndingHandler = ^NSString *(NSTextView *textView) {
            return [SUD boolForKey:ConvertLFKey] ? @"\n" : nil;
        };
        [TSAdvancedFindController trackTargetTextViews];
    });
    return TSAdvancedFindPanelController.sharedPanelController.findController;
}

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
static __weak NSTextView *TSLastTargetTextView;

+ (nullable NSTextView *)testTargetTextView
{
    return TSTestTargetTextView;
}

+ (void)setTestTargetTextView:(nullable NSTextView *)textView
{
    TSTestTargetTextView = textView;
}

/// The window's first responder if it is a text view whose find menu goes to the panel (not the panel's own fields).
static NSTextView *_Nullable TSFocusedTarget(NSWindow *_Nullable window)
{
    NSResponder *responder = window.firstResponder;
    return [responder conformsToProtocol:@protocol(TSAdvancedFindTarget)] ? (NSTextView *)responder : nil;
}

+ (void)trackTargetTextViews
{
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        void (^note)(NSNotification *) = ^(NSNotification *notification) {
            NSWindow *window = notification.object;
            if ([window isKindOfClass:[NSWindow class]])
                [TSAdvancedFindController noteKeyWindowChange:window];
        };
        NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
        [center addObserverForName:NSWindowDidBecomeKeyNotification object:nil queue:nil usingBlock:note];
        [center addObserverForName:NSWindowDidResignKeyNotification object:nil queue:nil usingBlock:note];
    });
}

/// A window with a focused find target leaves it as the last target. A window that can be main but has none (the
/// preview, the document with the focus in its PDF) clears it, as the main window's first responder did before. A
/// panel without one (the Advanced Find panel, the Experiment preview) leaves it as it is.
+ (void)noteKeyWindowChange:(NSWindow *)window
{
    NSTextView *target = TSFocusedTarget(window);
    if (target)
        TSLastTargetTextView = target;
    else if (window.canBecomeMainWindow)
        TSLastTargetTextView = nil;
}

+ (nullable NSTextView *)targetTextView
{
    if (TSTestTargetTextView)
        return TSTestTargetTextView;
    NSTextView *key = TSFocusedTarget(NSApp.keyWindow);
    if (key)
        return key;
    NSTextView *last = TSLastTargetTextView;
    if (last.window.isVisible)
        return last;
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

/// Made in code; -initWithFrame: (the Experiment output) comes here too. Asking for the layout manager of Apple's text
/// system makes it the TextKit 1 one that TeXShop uses everywhere.
- (instancetype)initWithFrame:(NSRect)frame textContainer:(nullable NSTextContainer *)container
{
    if ((self = [super initWithFrame:frame textContainer:container]))
        [TSAdvancedFindLayoutManager installInTextView:self];
    return self;
}

- (void)awakeFromNib
{
    [super awakeFromNib];
    [TSAdvancedFindLayoutManager installInTextView:self]; // from a nib (the console, the log): the text system is complete now
}

- (nullable TSAdvancedFindController *)findController
{
    return TSAdvancedFindControllerForFindMethod();
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
    TSAdvancedFindController *controller = self.findController;
    if (controller)
        [controller performFindPanelAction:sender inTextView:self];
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
