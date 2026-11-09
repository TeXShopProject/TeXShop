// SPDX-License-Identifier: GPL-2.0-or-later
#import <Cocoa/Cocoa.h>
#import "TestAppKitIsolation.h"
#import "TSPrefPaneLayout.h"
#import "TSSettingsCategoryList.h"
static void Check(BOOL value, NSString *message) { if (!value) { fprintf(stderr,"FAIL: %s\n",message.UTF8String); exit(1); } }
static NSView *Find(NSView *root, NSString *identifier) { if ([root.identifier isEqual:identifier]) return root; for (NSView *child in root.subviews) { NSView *found=Find(child,identifier); if(found)return found; } return nil; }
@interface PixelCanvas : NSView @end
@implementation PixelCanvas
- (void)drawRect:(NSRect)dirty { [NSColor.windowBackgroundColor setFill]; NSRectFill(self.bounds); }
@end
static CGFloat PixelGray(NSBitmapImageRep *image,NSView *view,NSPoint point) {
 CGFloat sx=image.pixelsWide/NSWidth(view.bounds),sy=image.pixelsHigh/NSHeight(view.bounds);
 NSInteger x=point.x*sx,y=(NSHeight(view.bounds)-point.y)*sy;
 NSColor *c=[[image colorAtX:x y:y]colorUsingColorSpace:NSColorSpace.deviceRGBColorSpace];
 return (c.redComponent+c.greenComponent+c.blueComponent)/3;
}
@interface ActionProbe : NSObject
@property NSUInteger calls;
@property (weak) id sender;
- (void)changed:(id)sender;
@end
@implementation ActionProbe
- (void)changed:(id)sender { self.calls++; self.sender=sender; }
@end
int main(int argc, const char **argv) { @autoreleasepool {
    TSInstallAppKitIsolation(); [NSApplication sharedApplication];
    Check(argc==2,@"Fixed design contract supplied");
    NSDictionary *design=[NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfFile:@(argv[1])] options:0 error:NULL];
    NSDictionary *categories=design[@"categories"];
    TSSettingsCategoryList *list=[TSSettingsCategoryList standardList];
    Check(categories.count==10 && list.categories.count==10,@"All reference icons covered");
    for (TSSettingsCategory *category in list.categories) {
        NSDictionary *expected=categories[category.identifier];
        Check([category.symbolName isEqual:expected[@"symbol"]],@"Category uses the exact mockup symbol");
        unsigned int rgb=0; [[NSScanner scannerWithString:[expected[@"color"] substringFromIndex:1]] scanHexInt:&rgb];
        NSColor *color=[category.color colorUsingColorSpace:NSColorSpace.sRGBColorSpace];
        Check(fabs(color.redComponent-((rgb>>16)&255)/255.0)<0.0001 && fabs(color.greenComponent-((rgb>>8)&255)/255.0)<0.0001 && fabs(color.blueComponent-(rgb&255)/255.0)<0.0001,@"Category uses the exact mockup sRGB color");
        for (NSNumber *size in @[design[@"sidebarIconSize"],design[@"overviewIconSize"]]) {
            TSSettingsIconView *icon=[[TSSettingsIconView alloc] initWithSymbolName:category.symbolName color:category.color size:size.doubleValue];
            Check(NSEqualSizes(icon.fittingSize,NSMakeSize(size.doubleValue,size.doubleValue)) && icon.isFlipped && !icon.isAccessibilityElement,@"Sidebar and overview share the reference icon geometry");
        }
    }
    ActionProbe *target=[ActionProbe new];
    NSButton *original=[NSButton checkboxWithTitle:@"Original setting" target:target action:@selector(changed:)];
    original.identifier=@"settings.238"; original.tag=37;
    NSCell *cell=original.cell;
    NSView *row=[TSPrefPaneLayout viewForRow:[[TSSettingsControlRow alloc] initWithControls:@[original] indentation:0]];
    NSSwitch *toggle=(NSSwitch *)Find(row,@"toggle.settings.238");
    Check([toggle isKindOfClass:NSSwitch.class] && toggle.controlSize==NSControlSizeSmall,@"Boolean row uses a native small slide switch");
    Check(original.cell==cell && original.tag==37 && original.hidden && !original.isAccessibilityElement,@"Cell, tag and ownership survive presentation replacement without duplicate accessibility");
    for (NSNumber *value in @[@YES,@NO,@YES]) {
        original.enabled=value.boolValue; Check(toggle.enabled==value.boolValue,@"Dependency changes propagate without a layout pass");
        original.state=value.boolValue; Check(toggle.state==original.state,@"Profile/default state propagates without a layout pass");
    }
    original.title=@"Updated setting"; original.toolTip=@"Context";
    Check([toggle.accessibilityLabel isEqual:original.title] && [toggle.toolTip isEqual:original.toolTip],@"Accessible title and tooltip follow their original control");
    for(NSNumber *value in @[@NO,@YES]) {
        NSUInteger previous=target.calls; original.enabled=YES; toggle.state=value.boolValue;
        [toggle sendAction:toggle.action to:toggle.target];
        Check(target.calls==previous+1 && target.sender==original && original.state==value.boolValue,@"A switch edit dispatches exactly once with the original sender and state");
    }
    original.enabled=NO; NSUInteger previous=target.calls; NSInteger state=original.state; toggle.state=!state;
    [toggle sendAction:toggle.action to:toggle.target];
    Check(target.calls==previous && original.state==state && toggle.state==state,@"Disabled settings reject edits and retain their stored value");
    original.enabled=YES;
    NSWindow *window=[[NSWindow alloc] initWithContentRect:NSMakeRect(0,0,700,60) styleMask:NSWindowStyleMaskBorderless backing:NSBackingStoreBuffered defer:NO];
    NSView *host=window.contentView; [host addSubview:row];
    [NSLayoutConstraint activateConstraints:@[[row.leadingAnchor constraintEqualToAnchor:host.leadingAnchor],[row.trailingAnchor constraintEqualToAnchor:host.trailingAnchor],[row.topAnchor constraintEqualToAnchor:host.topAnchor]]];
    [host layoutSubtreeIfNeeded];
    NSRect accessory=[toggle convertRect:toggle.bounds toView:row];
    Check(NSHeight(row.frame)>=38 && NSHeight(row.frame)<=44,@"Simple rows retain the mockup's compact 38-point density");
    Check(fabs(NSMaxX(accessory)-(NSWidth(row.bounds)-12))<2,@"Switch aligns with the trailing card inset");
    Check(!window.visible,@"No window is shown");
    // A short title must not constrain a long note to a vertical sliver.
    NSPopUpButton *wideChoice=[[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    [wideChoice addItemWithTitle:@"別々のウインドウで開く"];
    NSView *noted=[TSPrefPaneLayout catalogRowWithTitle:@"行番号" note:@"新しい書類の初期値です。開いている書類では、メニューで切り替えます。" accessory:wideChoice expands:NO indent:0];
    [host addSubview:noted];
    [NSLayoutConstraint activateConstraints:@[[noted.leadingAnchor constraintEqualToAnchor:host.leadingAnchor],[noted.widthAnchor constraintEqualToConstant:500],[noted.topAnchor constraintEqualToAnchor:row.bottomAnchor]]];
    [host layoutSubtreeIfNeeded];
    NSView *detail=Find(noted,@"note.catalog-row");NSRect detailRect=[detail.superview convertRect:[detail alignmentRectForFrame:detail.frame] toView:noted];
    NSRect choiceRect=[wideChoice convertRect:wideChoice.bounds toView:noted];
    Check(NSMinX(detailRect)>=11 && fabs(NSMaxX(detailRect)-(NSWidth(noted.bounds)-12))<1 && NSHeight(detailRect)<70,[NSString stringWithFormat:@"A long note fills the row below the accessory: %@ row %@",NSStringFromRect(detailRect),NSStringFromRect(noted.frame)]);
    Check(NSIsEmptyRect(NSIntersectionRect(detailRect,choiceRect)),@"Notes do not overlap controls");
    NSView *name=Find(noted,@"label.catalog-row");NSRect nameRect=[name convertRect:name.bounds toView:noted];
    Check(fabs(NSMidY(choiceRect)-NSMidY(nameRect))<1,@"Accessory follows the title when the note spans the row");
    NSButton *button=[NSButton buttonWithTitle:@"Reset" target:nil action:NULL];
    NSView *shortNote=[TSPrefPaneLayout catalogRowWithTitle:@"Quick keys" note:@"Restore defaults." accessory:button expands:NO indent:0];
    [host addSubview:shortNote];[NSLayoutConstraint activateConstraints:@[[shortNote.widthAnchor constraintEqualToConstant:500],[shortNote.topAnchor constraintEqualToAnchor:noted.bottomAnchor],[shortNote.leadingAnchor constraintEqualToAnchor:host.leadingAnchor]]];[host layoutSubtreeIfNeeded];
    NSRect buttonRect=[button convertRect:button.bounds toView:shortNote];
    Check(fabs(NSMidY(buttonRect)-NSMidY(shortNote.bounds))<1,@"Short button explanation centers the accessory beside both lines");
    Check(NSMinY(choiceRect)>=5.9 && NSMaxY(choiceRect)<=NSHeight(noted.bounds)-5.9,@"Accessory has six-point vertical inset");
    NSTextField *number=[NSTextField textFieldWithString:@"20"];[number.widthAnchor constraintEqualToConstant:64].active=YES;
    NSTextField *unit=[NSTextField labelWithString:@"pt"];
    NSStackView *parts=[TSPrefPaneLayout stackWithViews:@[number,unit] orientation:NSUserInterfaceLayoutOrientationHorizontal];
    NSView *numberRow=[TSPrefPaneLayout catalogRowWithTitle:@"Spacing" note:@"" accessory:parts expands:NO indent:0];
    [host addSubview:numberRow];[NSLayoutConstraint activateConstraints:@[[numberRow.widthAnchor constraintEqualToConstant:500],[numberRow.topAnchor constraintEqualToAnchor:noted.bottomAnchor],[numberRow.leadingAnchor constraintEqualToAnchor:host.leadingAnchor]]];[host layoutSubtreeIfNeeded];
    NSRect numberRect=[number convertRect:number.bounds toView:numberRow];
    Check(NSMinX(numberRect)>380 && NSWidth(parts.frame)<100,[NSString stringWithFormat:@"Numeric field and unit form a compact right-aligned accessory: field=%@ stack=%@ row=%@",NSStringFromRect(numberRect),NSStringFromRect(parts.frame),NSStringFromRect(numberRow.frame)]);
    NSButtonCell *prototype=[NSButtonCell new]; [prototype setButtonType:NSButtonTypeRadio];
    NSMatrix *matrix=[[NSMatrix alloc] initWithFrame:NSZeroRect mode:NSRadioModeMatrix prototype:prototype numberOfRows:3 numberOfColumns:1];
    matrix.identifier=@"settings.test-choice"; matrix.target=target; matrix.action=@selector(changed:);
    NSArray<NSCell *> *cells=matrix.cells;
    for(NSUInteger i=0;i<cells.count;i++) { cells[i].tag=40+i*7; cells[i].title=[NSString stringWithFormat:@"Option %lu",(unsigned long)i]; }
    NSView *choiceRow=[TSPrefPaneLayout viewForRow:[[TSSettingsControlRow alloc] initWithControls:@[matrix] indentation:0]];
    NSPopUpButton *popup=(NSPopUpButton *)Find(choiceRow,@"choice.settings.test-choice");
    Check([popup isKindOfClass:NSPopUpButton.class] && popup.numberOfItems==3,@"Exclusive choices use the compact popup");
    for(NSNumber *index in @[@2,@0,@1]) {
        [matrix selectCellWithTag:cells[index.unsignedIntegerValue].tag];
        Check(popup.indexOfSelectedItem==index.integerValue,@"Programmatic matrix selection updates the popup immediately");
        matrix.enabled=NO;Check(!popup.enabled,@"Disabled matrix disables popup");matrix.enabled=YES;
        NSUInteger calls=target.calls; [popup selectItemAtIndex:(index.integerValue+1)%3]; NSInteger selected=popup.indexOfSelectedItem;
        [popup sendAction:popup.action to:popup.target];
        Check(target.calls==calls+1 && target.sender==matrix && matrix.selectedCell==cells[selected],@"Popup preserves the original matrix sender, cell and tag");
    }
    Check([matrix.cells isEqual:cells],@"Choice presentation retains every original cell");
    NSView *header=[TSPrefPaneLayout categoryHeaderWithTitle:@"Title" summary:@"Category summary" symbol:@"gearshape" color:NSColor.systemGrayColor];
    Check([Find(header,@"category.title") isKindOfClass:NSTextField.class] && [Find(header,@"category.description") isKindOfClass:NSTextField.class],@"Overview contains a title and summary");
    NSBox *box=[NSBox new];[TSSettingsGroupStyle applyToBox:box];
    for(NSString *name in @[NSAppearanceNameAqua,NSAppearanceNameDarkAqua]) [[NSAppearance appearanceNamed:name] performAsCurrentDrawingAppearance:^{
        CGFloat alpha=[[box.fillColor colorUsingColorSpace:NSColorSpace.deviceRGBColorSpace] alphaComponent];
        Check(alpha>=0.039 && alpha<=0.056 && !box.transparent,@"Light and dark cards use the reference translucent fill");
    }];
    // Inspect pixels from the real layer-backed card, including its separator.
    PixelCanvas *canvas=[[PixelCanvas alloc]initWithFrame:NSMakeRect(0,0,400,180)];
    NSWindow *pixelWindow=[[NSWindow alloc]initWithContentRect:canvas.bounds styleMask:NSWindowStyleMaskBorderless backing:NSBackingStoreBuffered defer:NO];pixelWindow.contentView=canvas;
    TSSettingsGroupView *group=[TSSettingsGroupView new];group.identifier=@"group.pixel";[canvas addSubview:group];
    NSTextField *heading=[NSTextField labelWithString:@"Heading"];heading.identifier=@"heading.pixel";
    NSView *first=[NSView new],*second=[NSView new];first.identifier=@"row.first";second.identifier=@"row.second";
    [first.heightAnchor constraintEqualToConstant:38].active=YES;[second.heightAnchor constraintEqualToConstant:38].active=YES;
    NSView *content=group.contentView;[TSPrefPaneLayout attachRows:@[heading,first,second] toView:content];
    [NSLayoutConstraint activateConstraints:@[[group.leadingAnchor constraintEqualToAnchor:canvas.leadingAnchor constant:20],[group.topAnchor constraintEqualToAnchor:canvas.topAnchor constant:20],[group.widthAnchor constraintEqualToConstant:360],[content.leadingAnchor constraintEqualToAnchor:group.leadingAnchor],[content.trailingAnchor constraintEqualToAnchor:group.trailingAnchor],[content.topAnchor constraintEqualToAnchor:group.topAnchor],[content.bottomAnchor constraintEqualToAnchor:group.bottomAnchor]]];
    [TSPrefPaneLayout decorateGroupsInView:group];
    for(NSString *name in @[NSAppearanceNameAqua,NSAppearanceNameDarkAqua]){
        pixelWindow.appearance=[NSAppearance appearanceNamed:name];[canvas layoutSubtreeIfNeeded];[canvas display];
        NSBitmapImageRep *image=[canvas bitmapImageRepForCachingDisplayInRect:canvas.bounds];[canvas cacheDisplayInRect:canvas.bounds toBitmapImageRep:image];
        NSRect rowRect=[first convertRect:first.bounds toView:canvas];
        CGFloat outside=PixelGray(image,canvas,NSMakePoint(5,5));
        CGFloat inside=PixelGray(image,canvas,NSMakePoint(NSMidX(rowRect),NSMidY(rowRect)));
        Check(fabs(inside-outside)>0.015,@"Rendered card pixels differ from surrounding background in both appearances");
        NSView *backdrop=Find(group,@"card.background");NSRect card=[backdrop convertRect:backdrop.bounds toView:canvas];
        NSRect h=[heading convertRect:heading.bounds toView:canvas];Check(NSMinY(h)>=NSMaxY(card)-0.5,@"Heading lies outside and above the filled card");
        NSRect boundary=[second convertRect:second.bounds toView:canvas];CGFloat difference=0;
        for(double dy=-1;dy<=1;dy+=0.25)difference=MAX(difference,fabs(PixelGray(image,canvas,NSMakePoint(NSMidX(boundary),NSMaxY(boundary)+dy))-inside));
        Check(difference>0.025,@"Rendered rows have a visible separator");
        Check(!pixelWindow.visible,@"Pixel test never orders a window");
    }
    puts("PASS: native switch actions, external updates, disabled values, accessibility, compact alignment and card colors");
} return 0; }
