// added by Terada: Render invisible characters and verify baseline and drawing-origin alignment.
#import <Cocoa/Cocoa.h>
#import <objc/runtime.h>
#import "TSLayoutManager.h"
#import "MarkerKeys.h"
#import "MemoryDefaults.h"
#import "TSInvisibleCharacters.h"
static TSMemoryDefaults *settings;
static id MemoryStandardDefaults(id self, SEL cmd) { return settings; }
NSColor *InvisibleColor;
static NSMutableArray *expected;
static NSMutableArray *expectedMarkers;
static NSUInteger verified;
static void (*originalDraw)(id,SEL,NSRange,NSPoint);
static void observeDraw(NSLayoutManager *layout, SEL cmd, NSRange range, NSPoint origin) {
    if (layout.textStorage.length == 1 && expected.count) {
        NSCAssert([layout.textStorage.string isEqual:expectedMarkers[0]], @"Selected marker reaches actual drawing");
        [expectedMarkers removeObjectAtIndex:0];
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
    settings=[TSMemoryDefaults new];
    method_setImplementation(class_getClassMethod(NSUserDefaults.class,@selector(standardUserDefaults)),(IMP)MemoryStandardDefaults);
    [settings registerDefaults:@{showTabCharacterKey:@YES, showNewLineCharacterKey:@YES, showFullwidthSpaceCharacterKey:@YES, showSpaceCharacterKey:@YES}];
    InvisibleColor=NSColor.systemRedColor;
    Method method=class_getInstanceMethod(NSLayoutManager.class,@selector(drawGlyphsForGlyphRange:atPoint:));
    originalDraw=(void*)method_getImplementation(method);method_setImplementation(method,(IMP)observeDraw);
    NSImage *image=[[NSImage alloc]initWithSize:NSMakeSize(760,640)];
    [image lockFocusFlipped:YES];[NSColor.whiteColor setFill];NSRectFill(NSMakeRect(0,0,760,640));
    expected=[NSMutableArray array]; expectedMarkers=[NSMutableArray array];
    NSArray *keys=@[SpaceCharacterKindKey,FullwidthSpaceCharacterKindKey,NewLineCharacterKindKey,TabCharacterKindKey];
    NSArray *choices=@[@[@"␣",@"·"],@[@"□",@"■"],@[@"↵",@"¶",@"↩",@"⏎"],@[@"‣",@"▹",@"⇥"]];
    NSArray *values=@[@0,@1,@2,@3,@(-1),@99,@"junk"];
    for (int variant=0;variant<9;variant++) for (int i=0;i<5;i++) {
        NSInteger raw = variant<7 ? [values[variant] integerValue] : variant-5;
        for (NSString *key in keys) {
            [settings removeObjectForKey:TSInvisibleExtendedKey(key)];
            [settings setObject:variant<7?values[variant]:@0 forKey:key];
            if (variant>=7) [settings setInteger:raw forKey:TSInvisibleExtendedKey(key)];
        }
        NSFont *font=[NSFont fontWithName:(@[@"Menlo-Regular", @"HiraginoSans-W3", @"Osaka-Mono", @"Courier", @"SFMono-Regular"][i]) size:14+6*i];
        if (!font && i==4) font=[NSFont monospacedSystemFontOfSize:14+6*i weight:NSFontWeightRegular];
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
                NSInteger kind = ch==' ' ? 0 : ch==0x3000 ? 1 : ch=='\n' ? 2 : 3;
                NSArray *markers=choices[kind];
                [expectedMarkers addObject:markers[raw>=0 && raw<markers.count ? raw : 0]];
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
    printf("PASS: %lu marker baselines (five fonts, all candidates, legacy/extended/invalid values, mixed font, line spacing, nonzero origins)\n",(unsigned long)verified);
 }
}
