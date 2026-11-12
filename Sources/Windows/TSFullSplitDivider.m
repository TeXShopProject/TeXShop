// SPDX-License-Identifier: GPL-2.0-or-later
#import "TSFullSplitDivider.h"
#import "TSPreviewSplitDivider.h"
#import "globals.h"

// Neither side opens narrower than this share of the window.
static const CGFloat TSFullSplitMinimumFraction = 0.1;

@interface TSFullSplitDivider ()
@property (weak) NSSplitView *splitView;
@property (weak) NSView *sourceView;
@property BOOL restoring;
@end

@implementation TSFullSplitDivider

- (instancetype)initWithSplitView:(NSSplitView *)splitView sourceView:(NSView *)sourceView
{
    self = [super init];
    if (self) {
        _splitView = splitView;
        _sourceView = sourceView;
        [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(splitViewDidResizeSubviews:)
                                                   name:NSSplitViewDidResizeSubviewsNotification object:splitView];
    }
    return self;
}

- (void)dealloc
{
    [NSNotificationCenter.defaultCenter removeObserver:self];
}

+ (CGFloat)usableFraction:(double)fraction
{
    if (!isfinite(fraction) || fraction <= 0 || fraction >= 1)
        return 0;
    return MIN(MAX(fraction, TSFullSplitMinimumFraction), 1 - TSFullSplitMinimumFraction);
}

// The side that holds the source, when the split view has its two sides.
- (nullable NSView *)sourceSide
{
    NSSplitView *splitView = self.splitView;
    NSView *sourceView = self.sourceView;
    if (splitView == nil || sourceView == nil || splitView.subviews.count != 2)
        return nil;
    for (NSView *side in splitView.subviews)
        if ([sourceView isDescendantOf:side])
            return side;
    return nil;
}

// The width the two sides share, without the divider.
- (CGFloat)sharedWidth
{
    NSSplitView *splitView = self.splitView;
    return NSWidth(splitView.bounds) - splitView.dividerThickness;
}

- (void)splitViewDidResizeSubviews:(NSNotification *)notification
{
    if (self.restoring || ![TSPreviewSplitDivider isDividerDrag:notification])
        return;
    NSSplitView *splitView = self.splitView;
    NSView *source = [self sourceSide];
    CGFloat width = [self sharedWidth];
    if (source == nil || !splitView.isVertical || width <= 0)
        return;
    // A folded side says nothing about how wide the user wants the source.
    for (NSView *side in splitView.subviews)
        if ([splitView isSubviewCollapsed:side] || side.isHidden)
            return;
    CGFloat fraction = MIN(MAX(NSWidth(source.frame) / width, TSFullSplitMinimumFraction), 1 - TSFullSplitMinimumFraction);
    [NSUserDefaults.standardUserDefaults setDouble:fraction forKey:FullSplitSourceFractionKey];
}

- (void)restore
{
    CGFloat fraction = [TSFullSplitDivider usableFraction:
                        [NSUserDefaults.standardUserDefaults doubleForKey:FullSplitSourceFractionKey]];
    NSSplitView *splitView = self.splitView;
    NSView *source = [self sourceSide];
    CGFloat width = [self sharedWidth];
    if (fraction == 0 || source == nil || !splitView.isVertical || width <= 0)
        return;
    CGFloat left = source == splitView.subviews.firstObject ? fraction : 1 - fraction;
    self.restoring = YES;
    [splitView setPosition:round(left * width) ofDividerAtIndex:0];
    self.restoring = NO;
}

@end
