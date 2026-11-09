// SPDX-License-Identifier: GPL-2.0-or-later
#import "TSSettingsContentView.h"
@implementation TSSettingsContentView
- (BOOL)isFlipped { return YES; }
- (instancetype)initWithContent:(NSView *)content
{
    self = [super initWithFrame:NSMakeRect(0, 0, NSWidth(content.frame), NSHeight(content.frame))];
    if (self == nil) { return nil; }
    content.frame = self.bounds;
    [self addSubview:content];
    return self;
}
@end
