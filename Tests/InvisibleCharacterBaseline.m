// added by Terada: Render invisible characters and verify baseline and drawing-origin alignment.
#import <Cocoa/Cocoa.h>
#import <objc/runtime.h>
#import "TSLayoutManager.h"
NSString *showTabCharacterKey=@"testTab", *showNewLineCharacterKey=@"testNewline";
NSString *showFullwidthSpaceCharacterKey=@"testFullwidth", *showSpaceCharacterKey=@"testSpace";
NSString *TabCharacterKindKey=@"testTabKind", *NewLineCharacterKindKey=@"testNewlineKind";
NSString *FullwidthSpaceCharacterKindKey=@"testFullwidthKind", *SpaceCharacterKindKey=@"testSpaceKind";
NSColor *InvisibleColor;
static NSMutableArray *expected;
static NSUInteger verified;
static void (*originalDraw)(id,SEL,NSRange,NSPoint);
static void observeDraw(NSLayoutManager *layout, SEL cmd, NSRange range, NSPoint origin) {
    if (layout.textStorage.length == 1 && expected.count) {
        NSPoint position = [layout locationForGlyphAtIndex:0];
        NSRect line = [layout lineFragmentRectForGlyphAtIndex:0 effectiveRange:NULL];
        NSPoint target = [expected[0] pointValue];
        NSCAssert(fabs(origin.x + line.origin.x + position.x - target.x) < 0.01, @"横位置");
        NSCAssert(fabs(origin.y + line.origin.y + position.y - target.y) < 0.01, @"ベースライン");
        [expected removeObjectAtIndex:0]; verified++;
    }
    originalDraw(layout,cmd,range,origin);
}
int main(int argc, const char **argv) {
 @autoreleasepool {
    [NSApplication sharedApplication];
    [[NSUserDefaults standardUserDefaults] registerDefaults:@{showTabCharacterKey:@YES, showNewLineCharacterKey:@YES, showFullwidthSpaceCharacterKey:@YES, showSpaceCharacterKey:@YES}];
    InvisibleColor=NSColor.systemRedColor;
    Method method=class_getInstanceMethod(NSLayoutManager.class,@selector(drawGlyphsForGlyphRange:atPoint:));
    originalDraw=(void*)method_getImplementation(method);method_setImplementation(method,(IMP)observeDraw);
    NSImage *image=[[NSImage alloc]initWithSize:NSMakeSize(760,640)];
    [image lockFocusFlipped:YES];[NSColor.whiteColor setFill];NSRectFill(NSMakeRect(0,0,760,640));
    expected=[NSMutableArray array];
    for (int i=0;i<4;i++) {
        NSFont *font=[NSFont fontWithName:(i%2 ? @"HiraginoSans-W3":@"Menlo-Regular") size:14+6*i];
        NSCAssert(font!=nil,@"テスト用フォント");
        NSMutableParagraphStyle *style=[NSMutableParagraphStyle new];style.lineSpacing=3*i;style.firstLineHeadIndent=11;
        NSString *text=@"ABC あいう　XYZ \t終わり\n次の行　 xyz\n";
        NSTextStorage *storage=[[NSTextStorage alloc]initWithString:text attributes:@{NSFontAttributeName:font,NSForegroundColorAttributeName:NSColor.blackColor,NSParagraphStyleAttributeName:style}];
        [storage addAttribute:NSFontAttributeName value:[NSFont systemFontOfSize:font.pointSize+5] range:NSMakeRange(7,1)];
        TSLayoutManager *layout=[TSLayoutManager new];[layout setInvisibleCharactersEnabled:YES];
        NSTextContainer *container=[[NSTextContainer alloc]initWithContainerSize:NSMakeSize(690,140)];
        [storage addLayoutManager:layout];[layout addTextContainer:container];[layout ensureLayoutForTextContainer:container];
        NSPoint origin=NSMakePoint(23+i*3,20+i*150);
        for(NSUInteger g=0;g<layout.numberOfGlyphs;g++) {
            NSUInteger c=[layout characterIndexForGlyphAtIndex:g];unichar ch=[text characterAtIndex:c];
            if(ch==' '||ch=='\t'||ch=='\n'||ch==0x3000) {
                NSPoint base=[layout locationForGlyphAtIndex:g];NSRect line=[layout lineFragmentRectForGlyphAtIndex:g effectiveRange:NULL];
                [expected addObject:[NSValue valueWithPoint:NSMakePoint(origin.x+line.origin.x+base.x,origin.y+line.origin.y+base.y)]];
            }
        }
        [layout drawGlyphsForGlyphRange:NSMakeRange(0,layout.numberOfGlyphs) atPoint:origin];
        NSCAssert(expected.count==0,@"すべての不可視記号が検証されたこと");
    }
    [image unlockFocus];
    NSBitmapImageRep *rep=[NSBitmapImageRep imageRepWithData:image.TIFFRepresentation];
    [[rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:[NSString stringWithUTF8String:argv[1]] atomically:YES];
    [[NSData dataWithBytes:rep.bitmapData length:rep.bytesPerRow * rep.pixelsHigh] writeToFile:[[NSString stringWithUTF8String:argv[1]] stringByAppendingString:@".pixels"] atomically:YES];
    printf("PASS: %lu marker baselines (four fonts/sizes, mixed font, line spacing, nonzero origins)\n",(unsigned long)verified);
 }
}
