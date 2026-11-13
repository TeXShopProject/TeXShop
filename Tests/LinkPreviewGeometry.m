#import "TSLinkPreviewGeometry.h"

static void require(BOOL value, const char *message) {
    if (!value) { fprintf(stderr, "FAIL: %s\n", message); exit(1); }
}
static BOOL near(CGFloat a, CGFloat b) { return fabs(a-b) < 0.001; }
static BOOL contains(NSRect outer, NSRect inner) {
    return NSMinX(inner) >= NSMinX(outer)-0.001 && NSMinY(inner) >= NSMinY(outer)-0.001 &&
        NSMaxX(inner) <= NSMaxX(outer)+0.001 && NSMaxY(inner) <= NSMaxY(outer)+0.001;
}
static NSBitmapImageRep *bitmap(NSSize size) {
    return [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL pixelsWide:(NSInteger)size.width
        pixelsHigh:(NSInteger)size.height bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO
        colorSpaceName:NSDeviceRGBColorSpace bytesPerRow:0 bitsPerPixel:0];
}
static void redMark(CGContextRef context) {
    CGContextSetRGBFillColor(context, 1, 0, 0, 1);
    CGContextFillRect(context, CGRectMake(90, 110, 40, 30));
}
static PDFDocument *fixture(void) {
    NSMutableData *data = [NSMutableData data];
    CGDataConsumerRef consumer = CGDataConsumerCreateWithCFData((__bridge CFMutableDataRef)data);
    CGRect media = CGRectMake(10, 20, 600, 800), crop = CGRectMake(60, 70, 418, 638);
    CGContextRef context = CGPDFContextCreate(consumer, &media, NULL);
    NSDictionary *info = @{(__bridge NSString *)kCGPDFContextCropBox:
        [NSData dataWithBytes:&crop length:sizeof(crop)]};
    CGPDFContextBeginPage(context, (__bridge CFDictionaryRef)info);
    redMark(context);
    CGPDFContextEndPage(context); CGPDFContextClose(context);
    CGContextRelease(context); CGDataConsumerRelease(consumer);
    return [[PDFDocument alloc] initWithData:data];
}
static void testDrawing(void) {
    for (NSInteger rotation = 0; rotation < 360; rotation += 90) {
        PDFDocument *document = fixture();
        [document pageAtIndex:0].rotation = rotation;
        // Materialize the changed /Rotate into the CGPDFPage as in a file loaded from disk.
        document = [[PDFDocument alloc] initWithData:document.dataRepresentation];
        PDFPage *page = [document pageAtIndex:0];
        NSSize size; CGAffineTransform transform;
        require(TSLinkPreviewPageGeometry(page, &size, &transform), "page geometry");
        require(near(size.width, rotation % 180 ? 638 : 418), "rotated width uses CropBox");
        require(near(size.height, rotation % 180 ? 418 : 638), "rotated height uses CropBox");
        NSImage *image = TSLinkPreviewImage(page, size);
        NSBitmapImageRep *actual = bitmap(size), *expected = bitmap(size);
        for (NSInteger kind=0; kind<2; kind++) {
            NSBitmapImageRep *rep = kind ? expected : actual;
            [NSGraphicsContext saveGraphicsState];
            NSGraphicsContext.currentContext = [NSGraphicsContext graphicsContextWithBitmapImageRep:rep];
            [[NSColor whiteColor] set]; NSRectFill(NSMakeRect(0,0,size.width,size.height));
            if (kind) {
                CGContextRef context = NSGraphicsContext.currentContext.CGContext;
                CGContextConcatCTM(context, transform);
                redMark(context);
            } else {
                [image drawInRect:NSMakeRect(0,0,size.width,size.height) fromRect:NSZeroRect
                       operation:NSCompositingOperationSourceOver fraction:1 respectFlipped:YES hints:nil];
            }
            [NSGraphicsContext restoreGraphicsState];
        }
        NSUInteger redPixels=0, mismatch=0;
        for (NSInteger y=0; y<size.height; y++) for (NSInteger x=0; x<size.width; x++) {
            NSColor *a=[actual colorAtX:x y:y], *e=[expected colorAtX:x y:y];
            BOOL ar=a.redComponent>0.8 && a.greenComponent<0.2;
            BOOL er=e.redComponent>0.8 && e.greenComponent<0.2;
            redPixels += ar; mismatch += ar != er;
        }
        require(redPixels > 1000, "page marker rendered");
        require(mismatch < 10, "image and destination transform agree for CropBox and rotation");
        CGPoint destination = CGPointApplyAffineTransform(CGPointMake(110,125), transform);
        NSRect source, output;
        require(TSLinkPreviewRects(size, NSPointFromCGPoint(destination), NSZeroRect, NSMakeRect(30,40,300,220),
            NSMakePoint(200,150), YES, NO, YES, NO, &source, &output), "rotated destination crop");
        require(NSPointInRect(NSPointFromCGPoint(destination), source), "destination stays in crop");
        NSSize canvas = NSMakeSize(300,220);
        actual = bitmap(canvas); expected = bitmap(canvas);
        for (NSInteger kind=0; kind<2; kind++) {
            NSBitmapImageRep *rep = kind ? expected : actual;
            [NSGraphicsContext saveGraphicsState];
            NSGraphicsContext.currentContext = [NSGraphicsContext graphicsContextWithBitmapImageRep:rep];
            [[NSColor whiteColor] set]; NSRectFill(NSMakeRect(0,0,300,220));
            NSRect target = NSMakeRect(5,5,output.size.width,output.size.height);
            if (kind) {
                CGContextRef context = NSGraphicsContext.currentContext.CGContext;
                CGFloat scale = target.size.width / source.size.width;
                CGContextClipToRect(context, NSRectToCGRect(target));
                CGContextTranslateCTM(context, target.origin.x, target.origin.y);
                CGContextScaleCTM(context, scale, scale);
                CGContextTranslateCTM(context, -source.origin.x, -source.origin.y);
                CGContextConcatCTM(context, transform);
                redMark(context);
            } else {
                [image drawInRect:target fromRect:source operation:NSCompositingOperationSourceOver
                        fraction:1 respectFlipped:YES hints:nil];
            }
            [NSGraphicsContext restoreGraphicsState];
        }
        redPixels=0; mismatch=0;
        for (NSInteger y=0; y<220; y++) for (NSInteger x=0; x<300; x++) {
            NSColor *a=[actual colorAtX:x y:y], *e=[expected colorAtX:x y:y];
            BOOL ar=a.redComponent>0.8 && a.greenComponent<0.2;
            BOOL er=e.redComponent>0.8 && e.greenComponent<0.2;
            redPixels += ar; mismatch += ar != er;
        }
        require(redPixels > 100, "cropped preview retains the marker");
        require(mismatch < 80, "cropping and uniform downscaling retain destination alignment");
    }
}
static void testTextContext(void) {
    NSMutableData *data = [NSMutableData data];
    CGDataConsumerRef consumer = CGDataConsumerCreateWithCFData((__bridge CFMutableDataRef)data);
    CGRect media = CGRectMake(0,0,595,842);
    CGContextRef context = CGPDFContextCreate(consumer, &media, NULL);
    CGPDFContextBeginPage(context, NULL);
    [NSGraphicsContext saveGraphicsState];
    NSGraphicsContext.currentContext = [NSGraphicsContext graphicsContextWithCGContext:context flipped:NO];
    NSDictionary *attributes = @{NSFontAttributeName:[NSFont systemFontOfSize:12]};
    [@"LEFTBODY text after an equation" drawAtPoint:NSMakePoint(89,500) withAttributes:attributes];
    [@"E = mc²" drawAtPoint:NSMakePoint(196,600) withAttributes:attributes];
    [NSGraphicsContext restoreGraphicsState];
    CGPDFContextEndPage(context); CGPDFContextClose(context);
    CGContextRelease(context); CGDataConsumerRelease(consumer);
    PDFDocument *document = [[PDFDocument alloc] initWithData:data];
    PDFPage *page=[document pageAtIndex:0];
    NSSize size; CGAffineTransform transform;
    require(TSLinkPreviewPageGeometry(page,&size,&transform), "A4 text page geometry");
    NSPoint destination=TSLinkPreviewDestinationPoint(NSMakePoint(196,600),size,transform);
    for (NSInteger enlarged=0; enlarged<2; enlarged++) {
        NSRect text=TSLinkPreviewTextBounds(page,size,destination,transform,enlarged);
        require(!NSIsEmptyRect(text) && NSMinX(text)<95, "extract actual PDF text line beginning");
        NSRect source,output;
        require(TSLinkPreviewRects(size,destination,text,NSMakeRect(0,0,1000,1000),NSMakePoint(500,500),
                                  enlarged,NO,YES,NO,&source,&output), "A4 equation preview");
        require(source.origin.x < 89, "A4 line beginning is included despite centered equation anchor");
        require(NSPointInRect(destination,source), "A4 equation anchor remains visible");
        // Widely separated text and destination must both remain visible; scale uniformly.
        destination.x=570;
        require(TSLinkPreviewRects(size,destination,text,NSMakeRect(0,0,1000,1000),NSMakePoint(500,500),
                                  enlarged,NO,YES,NO,&source,&output), "distant text and destination");
        require(source.origin.x < 89 && NSPointInRect(destination,source), "keep left context and far right anchor");
        require(near(output.size.width/source.size.width,enlarged?1:2.0/3.0), "wider context widens popup at nominal scale");
        require(source.size.width <= MIN(size.width-10,TSLinkPreviewMaximumColumn)+2*(enlarged?10:5)+0.001,
                "context width stays within the column limit");
        destination.x=196;
    }
    NSSize emptySize; CGAffineTransform emptyTransform;
    PDFPage *empty=[fixture() pageAtIndex:0];
    require(TSLinkPreviewPageGeometry(empty,&emptySize,&emptyTransform), "graphics page geometry");
    require(NSIsEmptyRect(TSLinkPreviewTextBounds(empty,emptySize,NSMakePoint(100,300),emptyTransform,YES)),
            "graphics-only PDF falls back without text bounds");
}
// Build real selectable text so column and coordinate regressions are observable.
static PDFDocument *textFixture(NSSize size, NSRect crop, NSArray<NSDictionary *> *lines) {
    NSMutableData *data=[NSMutableData data];
    CGDataConsumerRef consumer=CGDataConsumerCreateWithCFData((__bridge CFMutableDataRef)data);
    CGRect media=CGRectMake(0,0,size.width,size.height), box=NSRectToCGRect(crop);
    CGContextRef context=CGPDFContextCreate(consumer,&media,NULL);
    NSDictionary *info=@{(__bridge NSString *)kCGPDFContextCropBox:[NSData dataWithBytes:&box length:sizeof(box)]};
    CGPDFContextBeginPage(context,(__bridge CFDictionaryRef)info);
    [NSGraphicsContext saveGraphicsState];
    NSGraphicsContext.currentContext=[NSGraphicsContext graphicsContextWithCGContext:context flipped:NO];
    for (NSDictionary *line in lines)
        [line[@"text"] drawAtPoint:[line[@"point"] pointValue]
             withAttributes:@{NSFontAttributeName:[NSFont fontWithName:@"Helvetica" size:12]}];
    [NSGraphicsContext restoreGraphicsState];
    CGPDFContextEndPage(context); CGPDFContextClose(context);
    CGContextRelease(context); CGDataConsumerRelease(consumer);
    return [[PDFDocument alloc] initWithData:data];
}
static NSDictionary *textLine(NSString *text, CGFloat x, CGFloat y) {
    return @{@"text":text,@"point":[NSValue valueWithPoint:NSMakePoint(x,y)]};
}
static void testColumnsAndWidePages(void) {
    for (NSInteger wide=0;wide<2;wide++) {
        NSSize size=NSMakeSize(wide?2400:612,842);
        CGFloat x=wide?1500:380;
        PDFDocument *document=textFixture(size,NSMakeRect(0,0,size.width,size.height),@[
            textLine(@"LEFT COLUMN wrong equation (1)",49,600),
            textLine(@"RIGHT COLUMN context surrounding formula",wide?1450:312,560),
            textLine(@"x² + y² = z² (2)",x,600),
            textLine(wide ? [@"Wide poster prose " stringByPaddingToLength:300 withString:@"abcdefghijk " startingAtIndex:0] : @"Left lower column",49,530)]);
        PDFPage *page=[document pageAtIndex:0]; CGAffineTransform transform;
        require(TSLinkPreviewPageGeometry(page,&size,&transform),"column geometry");
        NSPoint destination=NSMakePoint(x,610);
        PDFSelection *equation=[document findString:@"x² + y² = z² (2)" withOptions:0].firstObject;
        require(equation!=nil,"real formula selected");
        NSRect equationBounds=[equation boundsForPage:page];
        for (NSInteger enlarged=0;enlarged<2;enlarged++) {
            NSRect text=TSLinkPreviewTextBounds(page,size,destination,transform,enlarged);
            require(NSMinX(text)>=(wide?1449:311),"context excludes unrelated left column and wide prose");
            NSRect source,output;
            require(TSLinkPreviewRects(size,destination,text,NSMakeRect(0,0,2000,1200),NSMakePoint(800,500),
                enlarged,NO,YES,NO,&source,&output),"column preview");
            require(contains(source,equationBounds),"complete right-column formula remains visible");
            require(output.size.width/source.size.width >= (enlarged?1:2.0/3.0)*0.75-0.001,
                    "wide page context does not reduce readability below floor");
        }
    }
    // If all surrounding context is unavoidably wide, retain a local destination crop.
    for (NSInteger enlarged=0;enlarged<2;enlarged++) {
        NSRect source,output;
        require(TSLinkPreviewRects(NSMakeSize(2400,1000),NSMakePoint(1300,700),NSMakeRect(50,400,2200,300),
            NSMakeRect(0,0,2000,1200),NSMakePoint(800,500),enlarged,NO,YES,NO,&source,&output),"poster fallback");
        require(source.origin.x>1200 && NSMaxX(source)>1500,"poster keeps destination and right-hand expression");
        require(near(output.size.width/source.size.width,enlarged?1:2.0/3.0),"poster fallback retains nominal scale");
    }
    NSRect source,output;
    require(TSLinkPreviewRects(NSMakeSize(800,900),NSMakePoint(200,700),NSMakeRect(80,400,500,300),
        NSMakeRect(0,0,2000,1200),NSMakePoint(800,500),YES,NO,YES,NO,&source,&output),"command full text width");
    require(NSMaxX(source)>=590 && source.origin.x<=70,"Command includes right edge of same-column text");
}
static void testRotatedTextContext(void) {
    NSRect crop=NSMakeRect(150,170,500,650);
    for (NSInteger rotation=0;rotation<360;rotation+=90) {
        PDFDocument *document=textFixture(NSMakeSize(800,1000),crop,@[textLine(@"TARGET",240,540)]);
        [document pageAtIndex:0].rotation=rotation;
        document=[[PDFDocument alloc] initWithData:document.dataRepresentation];
        PDFPage *page=[document pageAtIndex:0]; NSSize size; CGAffineTransform transform;
        require(TSLinkPreviewPageGeometry(page,&size,&transform),"rotated text geometry");
        PDFSelection *selection=[document findString:@"TARGET" withOptions:0].firstObject;
        require(selection!=nil,"rotated text is selectable");
        NSRect raw=[selection boundsForPage:page];
        // Explicit quarter-turn formulas, independent of the production CG transform.
        NSRect r=NSOffsetRect(raw,-crop.origin.x,-crop.origin.y),expected;
        switch(rotation) {
            case 90: expected=NSMakeRect(r.origin.y,crop.size.width-NSMaxX(r),r.size.height,r.size.width);break;
            case 180: expected=NSMakeRect(crop.size.width-NSMaxX(r),crop.size.height-NSMaxY(r),r.size.width,r.size.height);break;
            case 270: expected=NSMakeRect(crop.size.height-NSMaxY(r),r.origin.x,r.size.height,r.size.width);break;
            default: expected=r;
        }
        NSPoint destination=NSMakePoint(NSMidX(expected),NSMaxY(expected));
        NSRect text=TSLinkPreviewTextBounds(page,size,destination,transform,YES);
        require(near(text.origin.x,expected.origin.x) && near(text.origin.y,expected.origin.y) &&
                near(text.size.width,expected.size.width) && near(text.size.height,expected.size.height),
                "text band inverse and text bounds forward transforms agree with rotated CropBox");
        NSPoint unspecified=NSMakePoint(kPDFDestinationUnspecifiedValue,kPDFDestinationUnspecifiedValue);
        require(!TSLinkPreviewHasHorizontalDestination(unspecified,transform),"Fit has no horizontal anchor");
        NSPoint missingX=NSMakePoint(kPDFDestinationUnspecifiedValue,500);
        require(TSLinkPreviewHasHorizontalDestination(missingX,transform)==(rotation%180!=0),
                "quarter turns use raw y for horizontal destination");
    }
    PDFDocument *document=textFixture(NSMakeSize(650,900),NSMakeRect(0,0,650,900),@[
        textLine(@"E = mc²",200,650),textLine(@"LOWER surrounding context reaches leftward",80,410)]);
    PDFPage *page=[document pageAtIndex:0]; NSSize size; CGAffineTransform transform;
    require(TSLinkPreviewPageGeometry(page,&size,&transform),"long context geometry");
    NSPoint point=NSMakePoint(205,660);
    NSRect normal=TSLinkPreviewTextBounds(page,size,point,transform,NO);
    NSRect enlarged=TSLinkPreviewTextBounds(page,size,point,transform,YES);
    require(NSMinX(normal)>190 && NSMinX(enlarged)<90,"Command reads full 360 point vertical text band");
}
static void testPlacementAndUnspecified(void) {
    for (NSInteger enlarged=0; enlarged<2; enlarged++) for (NSInteger flipped=0; flipped<2; flipped++)
    for (NSInteger above=0; above<2; above++) {
        NSRect source,output; CGFloat scale=enlarged?1:2.0/3.0;
        require(TSLinkPreviewRects(NSMakeSize(600,900),NSMakePoint(100,700),NSZeroRect,
            NSMakeRect(0,0,2000,2000),NSMakePoint(500,500),enlarged,above,flipped,NO,&source,&output), "placement");
        require(near(output.size.width,(enlarged?445:400)*scale) &&
                near(output.size.height,(enlarged?360:120)*scale), "normal and command default scale");
        require(near(output.origin.x,500+(enlarged?-5:10)), "horizontal cursor anchor");
        CGFloat expectedY=above!=flipped ? 510 : 490-output.size.height;
        require(near(output.origin.y,expectedY), "Shift and flipped direction");
        NSPoint edge=NSMakePoint(500,above!=flipped ? 980 : 20);
        require(TSLinkPreviewRects(NSMakeSize(600,900),NSMakePoint(100,700),NSZeroRect,
            NSMakeRect(0,0,1000,1000),edge,enlarged,above,flipped,NO,&source,&output), "opposite-side placement");
        require(!NSPointInRect(edge,output), "use opposite side before covering cursor");
    }
    for (NSInteger rotation=0; rotation<360; rotation+=90) {
        PDFDocument *document=fixture(); [document pageAtIndex:0].rotation=rotation;
        document=[[PDFDocument alloc] initWithData:document.dataRepresentation];
        NSSize size; CGAffineTransform transform;
        require(TSLinkPreviewPageGeometry([document pageAtIndex:0],&size,&transform), "unspecified rotated page");
        NSPoint point=TSLinkPreviewDestinationPoint(NSMakePoint(kPDFDestinationUnspecifiedValue,
                kPDFDestinationUnspecifiedValue),size,transform);
        require(near(point.x,0) && near(point.y,size.height), "Fit defaults to normalized top left");
        CGPoint raw=CGPointApplyAffineTransform(CGPointMake(0,size.height),CGAffineTransformInvert(transform));
        point=TSLinkPreviewDestinationPoint(NSMakePoint(kPDFDestinationUnspecifiedValue,raw.y),size,transform);
        require(near(point.x,0) && near(point.y,size.height), "omitted x defaults before rotation");
        point=TSLinkPreviewDestinationPoint(NSMakePoint(raw.x,kPDFDestinationUnspecifiedValue),size,transform);
        require(near(point.x,0) && near(point.y,size.height), "omitted y defaults before rotation");
    }
}
static NSString *lineOfWidth(CGFloat width) {
    NSDictionary *attributes=@{NSFontAttributeName:[NSFont fontWithName:@"Helvetica" size:12]};
    NSArray *words=@[@"lorem",@"ipsum",@"dolor",@"sit",@"amet"];
    NSMutableString *line=[NSMutableString stringWithString:@"Body"];
    for (NSUInteger i=0; [[line stringByAppendingFormat:@" %@",words[i%5]] sizeWithAttributes:attributes].width<=width; i++)
        [line appendFormat:@" %@",words[i%5]];
    return line;
}
static NSArray *bodyLines(CGFloat x, CGFloat width, CGFloat top, NSInteger count) {
    NSMutableArray *lines=[NSMutableArray array];
    for (NSInteger i=0;i<count;i++) [lines addObject:textLine(lineOfWidth(width),x,top-14*i)];
    return lines;
}
static void sizedPreview(PDFDocument *document, NSPoint raw, NSRect visible, BOOL enlarged,
                         NSRect *column, NSRect *source, NSRect *output) {
    PDFPage *page=[document pageAtIndex:0]; NSSize size; CGAffineTransform transform;
    require(TSLinkPreviewPageGeometry(page,&size,&transform),"sized page geometry");
    NSPoint destination=TSLinkPreviewDestinationPoint(raw,size,transform);
    *column=TSLinkPreviewColumnBounds(page,size,transform,
                                     TSLinkPreviewTextBounds(page,size,destination,transform,enlarged));
    require(TSLinkPreviewRects(size,destination,*column,visible,NSMakePoint(NSMidX(visible),NSMidY(visible)),
                              enlarged,NO,YES,NO,source,output),"sized preview");
}
// The popup widens to the destination's text column instead of shrinking it.
// In the continuous displays the popup keeps to its side of the link, below it or above it
// with Shift, even when part of it then lies outside the visible area, and keeps its size;
// it still moves sideways to stay in view (#14).
static void testKeptSide(void) {
    NSSize page=NSMakeSize(600,900);
    NSRect visible=NSMakeRect(0,0,1000,1000), available=NSInsetRect(visible,5,5);
    for (NSInteger enlarged=0; enlarged<2; enlarged++) for (NSInteger flipped=0; flipped<2; flipped++)
    for (NSInteger above=0; above<2; above++) {
        BOOL positiveY=above!=flipped;
        CGFloat scale=enlarged?1:2.0/3.0, height=(enlarged?360:120)*scale;
        for (CGFloat y=NSMinY(available); y<=NSMaxY(available); y+=7) {
            NSPoint cursor=NSMakePoint(500,y);
            NSRect keptSource, kept, fittedSource, fitted;
            require(TSLinkPreviewRects(page,NSMakePoint(100,700),NSZeroRect,visible,cursor,enlarged,above,flipped,
                                       YES,&keptSource,&kept),"kept-side geometry");
            require(TSLinkPreviewRects(page,NSMakePoint(100,700),NSZeroRect,visible,cursor,enlarged,above,flipped,
                                       NO,&fittedSource,&fitted),"fitted geometry");
            require(near(NSMinY(kept),positiveY ? y+10 : y-height-10),"popup stays on its side of the link");
            require(near(NSHeight(kept),height) && near(NSWidth(kept),NSWidth(fitted)),"popup keeps its size");
            require(NSEqualRects(keptSource,fittedSource) && near(NSMinX(kept),NSMinX(fitted)),
                    "only the vertical position differs from the fitted popup");
            require(!NSPointInRect(cursor,kept),"popup never covers the link");
            if (contains(available,kept))
                require(near(NSMinY(kept),NSMinY(fitted)),"a popup that fits is placed as before");
        }
        // Near the edge on its side, the fitted popup moves to the other side; the kept one does not.
        NSPoint edge=NSMakePoint(500,positiveY ? 980 : 20);
        NSRect source, kept, fitted;
        require(TSLinkPreviewRects(page,NSMakePoint(100,700),NSZeroRect,visible,edge,enlarged,above,flipped,
                                   YES,&source,&kept),"kept-side geometry near the edge");
        require(TSLinkPreviewRects(page,NSMakePoint(100,700),NSZeroRect,visible,edge,enlarged,above,flipped,
                                   NO,&source,&fitted),"fitted geometry near the edge");
        require(positiveY ? NSMinY(kept)>edge.y && NSMaxY(kept)>NSMaxY(available)
                          : NSMaxY(kept)<edge.y && NSMinY(kept)<NSMinY(available),
                "near the edge the popup stays on its side, partly outside the visible area");
        require(positiveY ? NSMaxY(fitted)<edge.y : NSMinY(fitted)>edge.y,
                "near the edge the fitted popup moves to the other side");
        // A low window shrinks the fitted popup to its height, but not the kept one.
        NSRect low=NSMakeRect(0,0,1000,enlarged?200:60);
        NSPoint middle=NSMakePoint(500,NSMidY(low));
        require(TSLinkPreviewRects(page,NSMakePoint(100,700),NSZeroRect,low,middle,enlarged,above,flipped,
                                   YES,&source,&kept),"kept-side geometry in a low window");
        require(TSLinkPreviewRects(page,NSMakePoint(100,700),NSZeroRect,low,middle,enlarged,above,flipped,
                                   NO,&source,&fitted),"fitted geometry in a low window");
        require(near(NSHeight(kept),height) && NSHeight(fitted)<height-1,"only the fitted popup shrinks to the window height");
        require(near(NSMinY(kept),positiveY ? middle.y+10 : middle.y-height-10),"a low window keeps the side");
        // Sideways, the popup still stays in view.
        for (CGFloat x=NSMinX(available); x<=NSMaxX(available); x+=13) {
            require(TSLinkPreviewRects(page,NSMakePoint(100,700),NSZeroRect,visible,NSMakePoint(x,500),enlarged,above,
                                       flipped,YES,&source,&kept),"kept-side geometry across the window");
            require(NSMinX(kept)>=NSMinX(available)-0.001 && NSMaxX(kept)<=NSMaxX(available)+0.001,
                    "the kept popup still moves sideways to stay in view");
        }
    }
}
// Near the bottom of its page the popup becomes lower instead of filling up with what comes
// before the destination; with the next page below it, as in the continuous displays, it
// goes on with that page instead (#14).
static void testBottomAndStrip(void) {
    NSSize page=NSMakeSize(600,800);
    NSRect visible=NSMakeRect(0,0,1000,1000);
    for (NSInteger enlarged=0; enlarged<2; enlarged++) for (NSInteger keepSide=0; keepSide<2; keepSide++) {
        CGFloat full=enlarged?360:120, scale=enlarged?1:2.0/3.0;
        for (CGFloat y=0; y<=page.height; y+=2.5) {
            NSRect source, output;
            require(TSLinkPreviewRects(page,NSMakePoint(100,y),NSZeroRect,visible,NSMakePoint(500,500),enlarged,NO,YES,
                                       keepSide,&source,&output),"bottom geometry");
            CGFloat top=MIN(MAX(y+10,TSLinkPreviewMinimumCrop),page.height);
            require(near(NSMaxY(source),top) && NSMinY(source)>=-0.001,"the popup starts just above the destination");
            require(near(NSHeight(source),MIN(full,top)),"near the bottom the popup shows less, not what comes before");
            require(near(NSHeight(output),NSHeight(source)*scale) && near(NSMinY(output),510),
                    "a lower popup keeps its scale and its place below the link");
        }
    }
    // The strip: the linked page above the next one, centered, with a gap.
    NSRect first, second;
    NSSize strip=TSLinkPreviewStrip(NSMakeSize(600,800),NSMakeSize(500,700),&first,&second);
    require(near(strip.width,600) && near(strip.height,800+TSLinkPreviewPageGap+700),"strip size");
    require(NSEqualRects(first,NSMakeRect(0,700+TSLinkPreviewPageGap,600,800)) && NSEqualRects(second,NSMakeRect(50,0,500,700)),
            "the next page lies below the linked one, centered");
    strip=TSLinkPreviewStrip(page,page,&first,&second);
    for (NSInteger enlarged=0; enlarged<2; enlarged++) {
        CGFloat full=enlarged?360:120;
        for (CGFloat y=0; y<=page.height; y+=5) {
            NSRect source, output;
            NSPoint destination=NSMakePoint(100,NSMinY(first)+y);
            require(TSLinkPreviewRects(strip,destination,NSZeroRect,visible,NSMakePoint(500,500),enlarged,NO,YES,YES,
                                       &source,&output),"strip geometry");
            require(near(NSHeight(source),full) && near(NSMaxY(source),MIN(destination.y+10,strip.height)),
                    "with the next page below, the popup keeps its height and goes on with that page");
            if (y+10+TSLinkPreviewPageGap<full) require(NSMinY(source)<NSMaxY(second),"a destination near the bottom shows the next page");
        }
    }
    // The image draws each page at its place in the strip.
    PDFDocument *document=fixture();
    [document insertPage:[[fixture() pageAtIndex:0] copy] atIndex:1];
    document=[[PDFDocument alloc] initWithData:document.dataRepresentation];
    NSSize size; CGAffineTransform transform;
    require(document.pageCount==2 && TSLinkPreviewPageGeometry([document pageAtIndex:0],&size,&transform),"strip pages");
    strip=TSLinkPreviewStrip(size,size,&first,&second);
    NSRect rects[2]={first,second};
    NSImage *image=TSLinkPreviewStripImage(@[[document pageAtIndex:0],[document pageAtIndex:1]],rects,strip);
    NSBitmapImageRep *rep=bitmap(strip);
    [NSGraphicsContext saveGraphicsState];
    NSGraphicsContext.currentContext=[NSGraphicsContext graphicsContextWithBitmapImageRep:rep];
    [image drawInRect:NSMakeRect(0,0,strip.width,strip.height) fromRect:NSZeroRect
            operation:NSCompositingOperationCopy fraction:1 respectFlipped:YES hints:nil];
    [NSGraphicsContext restoreGraphicsState];
    for (NSInteger i=0; i<2; i++) {
        // Compare with the page drawn alone, as a popup without the next page shows it.
        NSBitmapImageRep *alone=bitmap(size);
        [NSGraphicsContext saveGraphicsState];
        NSGraphicsContext.currentContext=[NSGraphicsContext graphicsContextWithBitmapImageRep:alone];
        [[NSColor whiteColor] set]; NSRectFill(NSMakeRect(0,0,size.width,size.height));
        [TSLinkPreviewImage([document pageAtIndex:i],size) drawInRect:NSMakeRect(0,0,size.width,size.height) fromRect:NSZeroRect
              operation:NSCompositingOperationSourceOver fraction:1 respectFlipped:YES hints:nil];
        [NSGraphicsContext restoreGraphicsState];
        NSUInteger red=0, mismatch=0;
        for (NSInteger y=0; y<(NSInteger)size.height; y++) for (NSInteger x=0; x<(NSInteger)size.width; x++) {
            NSColor *a=[alone colorAtX:x y:y];
            // Bitmap rows run from the top.
            NSColor *b=[rep colorAtX:x+(NSInteger)NSMinX(rects[i]) y:y+(NSInteger)(strip.height-NSMaxY(rects[i]))];
            BOOL ar=a.redComponent>0.8 && a.greenComponent<0.2, br=b.redComponent>0.8 && b.greenComponent<0.2;
            red+=ar; mismatch+=ar!=br;
        }
        require(red>1000 && mismatch<10,"each page is drawn at its place in the strip");
        NSColor *paper=[rep colorAtX:(NSInteger)NSMidX(rects[i]) y:(NSInteger)(strip.height-NSMaxY(rects[i])+5)];
        require(paper.redComponent>0.95 && paper.greenComponent>0.95,"the pages are white");
    }
    NSColor *gap=[rep colorAtX:(NSInteger)NSMidX(first) y:(NSInteger)(strip.height-NSMinY(first)+TSLinkPreviewPageGap/2)];
    require(gap.redComponent<0.8 && gap.alphaComponent>0.9,"the gap between the pages is gray");
}
static void testColumnWidth(void) {
    NSRect wide=NSMakeRect(0,0,1500,1200), column, source, output;
    // A heading and short display lines near the destination; full body lines further down.
    NSMutableArray *lines=[NSMutableArray arrayWithObjects:textLine(@"1 Heading",92,700),
        textLine(@"x = 1",250,680),textLine(@"y = 2",250,662),nil];
    [lines addObjectsFromArray:bodyLines(92,428,560,12)];
    PDFDocument *document=textFixture(NSMakeSize(612,792),NSMakeRect(0,0,612,792),lines);
    for (NSInteger enlarged=0;enlarged<2;enlarged++) {
        CGFloat nominal=enlarged?1:2.0/3.0;
        sizedPreview(document,NSMakePoint(92,712),wide,enlarged,&column,&source,&output);
        require(NSMaxX(column)>=500 && NSMinX(column)<=93,"page-level column reaches the right margin");
        require(NSMinX(source)<=92 && NSMaxX(source)>=500,"whole body line is cropped");
        require(near(output.size.width/source.size.width,nominal),"column shown at nominal scale");
        require(output.size.width>(enlarged?445:400*2.0/3.0)+1 || enlarged,"standard popup widens for a 428 point column");
    }
    // Narrow-margin notes: a 550 point column on A4 is shown whole.
    document=textFixture(NSMakeSize(595,842),NSMakeRect(0,0,595,842),bodyLines(22,550,700,12));
    sizedPreview(document,NSMakePoint(22,712),wide,NO,&column,&source,&output);
    require(NSMinX(source)<=22 && NSMaxX(source)>=550,"550 point column is cropped whole");
    require(near(output.size.width/source.size.width,2.0/3.0),"550 point column at nominal scale");
    // Two columns: each preview shows only its own column.
    lines=[NSMutableArray arrayWithArray:bodyLines(72,205,700,10)];
    [lines addObjectsFromArray:bodyLines(312,205,700,10)];
    document=textFixture(NSMakeSize(595,842),NSMakeRect(0,0,595,842),lines);
    sizedPreview(document,NSMakePoint(312,712),wide,NO,&column,&source,&output);
    require(NSMinX(source)>=300 && NSMaxX(source)>=505,"right column preview excludes the left column");
    sizedPreview(document,NSMakePoint(72,712),wide,NO,&column,&source,&output);
    require(NSMaxX(source)<=300 && NSMinX(source)<=72,"left column preview excludes the right column");
    require(near(output.size.width/source.size.width,2.0/3.0),"column preview at nominal scale");
    // A column narrower than the minimum keeps the nominal 400 point crop.
    document=textFixture(NSMakeSize(612,792),NSMakeRect(0,0,612,792),bodyLines(92,110,700,10));
    sizedPreview(document,NSMakePoint(92,712),wide,NO,&column,&source,&output);
    require(near(source.size.width,400),"narrow text keeps the nominal crop");
    // Short lines without a neighbouring column (lists, tables) keep the nominal crop too.
    document=textFixture(NSMakeSize(612,792),NSMakeRect(0,0,612,792),bodyLines(92,200,700,12));
    sizedPreview(document,NSMakePoint(92,712),wide,NO,&column,&source,&output);
    require(source.size.width>=399.999,"single-column short lines keep the nominal crop");
}
// Narrowing the window changes the popup continuously: first the scale, down to the floor,
// then the crop from the right; the destination always stays visible.
static void testContinuousShrinking(void) {
    NSSize page=NSMakeSize(612,792);
    NSRect text=NSMakeRect(92,600,428,120);
    for (NSInteger enlarged=0;enlarged<2;enlarged++) for (NSInteger far=0;far<2;far++) {
        NSPoint destination=NSMakePoint(far?500:92,700);
        CGFloat nominal=enlarged?1:2.0/3.0, floor=enlarged?0.75:0.5;
        NSRect previousSource=NSZeroRect, previousOutput=NSZeroRect, source, output; CGFloat previousScale=0;
        for (CGFloat width=700; width>=40; width-=0.5) {
            NSRect visible=NSMakeRect(0,0,width,1000);
            require(TSLinkPreviewRects(page,destination,text,visible,NSMakePoint(width/2,500),enlarged,NO,YES,NO,
                                      &source,&output),"continuous geometry");
            CGFloat scale=output.size.width/source.size.width;
            require(contains(NSInsetRect(visible,5,5),output),"continuous output stays visible");
            require(scale>=floor-0.0001 && scale<=nominal+0.0001,"scale between floor and nominal");
            require(destination.x>=NSMinX(source)-0.001 && destination.x<=NSMaxX(source)+0.001,
                    "destination stays in the crop");
            // A column wider than the nominal crop is shown at about 105% of its width.
            CGFloat full=428+2*MAX(enlarged?10:5,round(428*TSLinkPreviewColumnMargin));
            require(full/428>1.04 && full/428<1.06,"a wide column's preview is about 105% of its width");
            if (width-10>=full*nominal) require(near(scale,nominal) && near(source.size.width,full),
                                              "no shrinking while the column fits");
            if (previousScale>0) {
                require(fabs(scale-previousScale)<=0.01,"scale changes continuously");
                require(fabs(output.size.width-previousOutput.size.width)<=0.51,"popup width changes continuously");
                require(fabs(NSMinX(source)-NSMinX(previousSource))<=1.01 &&
                        fabs(source.size.width-previousSource.size.width)<=1.01,"crop changes continuously");
            }
            previousScale=scale; previousSource=source; previousOutput=output;
        }
        require(near(previousScale,floor),"narrowest window uses the floor scale");
    }
}
// Every internal link of a real document is shown with complete lines at the nominal scale.
static void testDocument(const char *path) {
    PDFDocument *document=[[PDFDocument alloc] initWithURL:[NSURL fileURLWithPath:@(path)]];
    require(document.pageCount>100,"real document loaded");
    NSUInteger links=0;
    for (NSInteger index=0;index<document.pageCount;index++)
    for (PDFAnnotation *annotation in [document pageAtIndex:index].annotations) {
        PDFDestination *target=annotation.destination; PDFPage *page=target.page;
        if (!page) continue;
        NSSize size; CGAffineTransform transform;
        if (!TSLinkPreviewPageGeometry(page,&size,&transform)) continue;
        NSPoint destination=TSLinkPreviewDestinationPoint(target.point,size,transform);
        NSRect local=TSLinkPreviewTextBounds(page,size,destination,transform,NO);
        NSRect text=TSLinkPreviewColumnBounds(page,size,transform,local);
        if (!TSLinkPreviewHasHorizontalDestination(target.point,transform) && !NSIsEmptyRect(text))
            destination.x=NSMinX(text);
        NSRect source,output;
        require(TSLinkPreviewRects(size,destination,text,NSMakeRect(0,0,1000,1200),NSMakePoint(400,500),
                                  NO,NO,YES,NO,&source,&output),"real link preview");
        require(NSIsEmptyRect(local) || (NSMinX(local)>=NSMinX(source)-0.5 && NSMaxX(local)<=NSMaxX(source)+0.5),
                "real link lines are not cut");
        require(near(output.size.width/source.size.width,2.0/3.0),"real link shown at nominal scale");
        links++;
    }
    require(links>200,"real document links checked");
    printf("checked %lu links in %s\n",(unsigned long)links,[[@(path) lastPathComponent] UTF8String]);
}

static CGFloat upMinY(NSRect rect, BOOL flipped) { return NSMinY(TSLinkPreviewUpward(rect, flipped)); }
static void testPinnedInteraction(void) {
    for (NSInteger flipped=0; flipped<2; flipped++) {
        NSRect frame=NSMakeRect(100,100,200,100);
        CGFloat top=flipped ? 101 : 199, bottom=flipped ? 199 : 101;
        require(TSLinkPreviewEdgeAt(frame,NSMakePoint(200,150),6,flipped)==TSLinkPreviewEdgeNone,"interior moves");
        require(TSLinkPreviewEdgeAt(frame,NSMakePoint(101,150),6,flipped)==TSLinkPreviewEdgeLeft,"left edge");
        require(TSLinkPreviewEdgeAt(frame,NSMakePoint(299,150),6,flipped)==TSLinkPreviewEdgeRight,"right edge");
        require(TSLinkPreviewEdgeAt(frame,NSMakePoint(200,top),6,flipped)==TSLinkPreviewEdgeTop,"visual top edge");
        require(TSLinkPreviewEdgeAt(frame,NSMakePoint(200,bottom),6,flipped)==TSLinkPreviewEdgeBottom,"visual bottom edge");
        require(TSLinkPreviewEdgeAt(frame,NSMakePoint(299,top),6,flipped)==(TSLinkPreviewEdgeRight|TSLinkPreviewEdgeTop),"corner");
        require(TSLinkPreviewEdgeAt(frame,NSMakePoint(99,150),6,flipped)==TSLinkPreviewEdgeNone,"outside is not an edge");
        require(TSLinkPreviewEdgeAt(NSMakeRect(0,0,9,9),NSMakePoint(4.5,4.5),6,flipped)==TSLinkPreviewEdgeNone,
                "a tiny preview can still be moved");

        NSRect area=NSMakeRect(0,0,1000,800);
        NSSize kept=NSMakeSize(20,20);
        NSRect moved=TSLinkPreviewMove(frame,NSMakeSize(30,-40),area,kept,flipped);
        require(near(NSMinX(moved),130) && near(NSMinY(moved),60) && near(NSWidth(moved),200) && near(NSHeight(moved),100),
                "move follows the pointer in view coordinates");
        for (NSInteger corner=0; corner<4; corner++) {
            NSSize far=NSMakeSize(corner&1 ? 5000 : -5000, corner&2 ? 5000 : -5000);
            moved=TSLinkPreviewMove(frame,far,area,kept,flipped);
            NSRect visible=NSIntersectionRect(area,moved);
            require(near(NSWidth(visible),20) && near(NSHeight(visible),20) && near(NSWidth(moved),200) && near(NSHeight(moved),100),
                    "move may push all but the kept part out of view");
        }
        moved=TSLinkPreviewMove(frame,NSMakeSize(5000,-5000),area,frame.size,flipped);
        require(contains(area,moved) && near(NSMaxX(moved),1000) && near(NSMinY(moved),0),"keeping the whole size keeps the popup in view");
        moved=TSLinkPreviewMove(frame,NSMakeSize(-5000,0),area,NSMakeSize(500,500),flipped);
        require(near(NSMinX(moved),0) && near(NSMinY(moved),100),"kept part is at most the popup itself");
        moved=TSLinkPreviewMove(NSMakeRect(100,100,1200,900),NSMakeSize(-5000,5000),area,kept,flipped);
        require(near(NSWidth(NSIntersectionRect(area,moved)),20) && near(NSHeight(NSIntersectionRect(area,moved)),20),
                "oversized preview keeps the kept part in view");
        NSRect previous=TSLinkPreviewMove(frame,NSMakeSize(-1200,-1200),area,kept,flipped);
        for (CGFloat d=-1200; d<=1200; d+=0.5) {
            moved=TSLinkPreviewMove(frame,NSMakeSize(d,d),area,kept,flipped);
            require(fabs(NSMinX(moved)-NSMinX(previous))<=0.5001 && fabs(NSMinY(moved)-NSMinY(previous))<=0.5001,
                    "move is continuous");
            previous=moved;
        }

        NSSize page=NSMakeSize(600,800), minimum=NSMakeSize(60,20);
        NSRect source=NSMakeRect(150,300,300,150);   // scale 2/3
        CGFloat scale=NSWidth(frame)/NSWidth(source);
        NSRect wide=NSMakeRect(-500,-500,2000,2000);
        NSRect out,outSource;
        TSLinkPreviewResize(frame,source,TSLinkPreviewEdgeRight,NSMakeSize(20,0),minimum,wide,page,flipped,&out,&outSource);
        require(near(NSWidth(out),220) && near(NSMinX(out),100) && near(NSWidth(outSource),330) && near(NSMinX(outSource),150),
                "right edge reveals more of the line");
        TSLinkPreviewResize(frame,source,TSLinkPreviewEdgeTop,NSMakeSize(0,flipped ? -30 : 30),minimum,wide,page,flipped,&out,&outSource);
        require(near(NSHeight(out),130) && near(upMinY(out,flipped),upMinY(frame,flipped)) &&
                near(NSMinY(outSource),300) && near(NSHeight(outSource),195),"top edge reveals content above");
        TSLinkPreviewResize(frame,source,TSLinkPreviewEdgeBottom,NSMakeSize(0,flipped ? 30 : -30),minimum,wide,page,flipped,&out,&outSource);
        require(near(NSHeight(out),130) && near(NSMaxY(outSource),450) && near(NSMinY(outSource),255),"bottom edge reveals content below");

        for (NSUInteger edges=1; edges<16; edges++) {
            if ((edges & 3)==3 || (edges & 12)==12) continue;
            for (NSInteger limit=0; limit<2; limit++) {
                NSRect available=limit ? NSMakeRect(40,30,400,260) : wide;
                NSRect last, lastSource;
                TSLinkPreviewResize(frame,source,edges,NSMakeSize(-700,-490),minimum,available,page,flipped,&last,&lastSource);
                for (CGFloat d=-700; d<=700; d+=0.5) {
                    TSLinkPreviewResize(frame,source,edges,NSMakeSize(d,d*0.7),minimum,available,page,flipped,&out,&outSource);
                    require(near(NSWidth(out)/NSWidth(outSource),scale) && near(NSHeight(out)/NSHeight(outSource),scale),
                            "resizing keeps the text size");
                    require(near(NSMinX(out)-NSMinX(outSource)*scale,NSMinX(frame)-NSMinX(source)*scale) &&
                            near(upMinY(out,flipped)-NSMinY(outSource)*scale,upMinY(frame,flipped)-NSMinY(source)*scale),
                            "page content stays where it was on screen");
                    require(contains(NSMakeRect(0,0,page.width,page.height),outSource),"resized source stays on the page");
                    require(NSWidth(out)>=minimum.width-0.001 && NSHeight(out)>=minimum.height-0.001,"minimum size");
                    require(contains(available,out),"resized preview stays in view");
                    require(!(edges & TSLinkPreviewEdgeLeft) || !(edges & TSLinkPreviewEdgeRight),"one horizontal edge");
                    if (!(edges & 3)) require(near(NSMinX(out),NSMinX(frame)) && near(NSWidth(out),NSWidth(frame)),"width unchanged");
                    if (!(edges & 12)) require(near(NSMinY(out),NSMinY(frame)) && near(NSHeight(out),NSHeight(frame)),"height unchanged");
                    require(fabs(NSMinX(out)-NSMinX(last))<=0.5001 && fabs(NSMaxX(out)-NSMaxX(last))<=0.5001 &&
                            fabs(NSMinY(out)-NSMinY(last))<=0.3501 && fabs(NSMaxY(out)-NSMaxY(last))<=0.3501,
                            "resizing is continuous");
                    last=out; lastSource=outSource;
                }
            }
        }
        // A preview already smaller than the minimum can grow but is never forced to jump.
        NSRect small=NSMakeRect(100,100,30,10), smallSource=NSMakeRect(10,10,45,15);
        TSLinkPreviewResize(small,smallSource,TSLinkPreviewEdgeRight,NSMakeSize(-5,0),minimum,wide,page,flipped,&out,&outSource);
        require(near(NSWidth(out),30),"undersized preview does not shrink further or jump");
        TSLinkPreviewResize(small,smallSource,TSLinkPreviewEdgeRight,NSMakeSize(5,0),minimum,wide,page,flipped,&out,&outSource);
        require(near(NSWidth(out),35),"undersized preview can grow");
        // Part of the preview scrolled out of view: the edge on that side is not pulled in.
        TSLinkPreviewResize(NSMakeRect(-20,100,200,100),source,TSLinkPreviewEdgeLeft,NSMakeSize(-5,0),minimum,
                            NSMakeRect(0,0,1000,800),page,flipped,&out,&outSource);
        require(near(NSMinX(out),-20),"edge already outside the view stays put");
    }

    NSSize page=NSMakeSize(600,800);
    NSRect source=NSMakeRect(150,300,300,150);
    NSRect panned=TSLinkPreviewPan(source,NSMakeSize(0,-40),page);
    require(near(NSMinY(panned),340) && near(NSMinX(panned),150) && near(NSHeight(panned),150),
            "moving content down shows what is above");
    panned=TSLinkPreviewPan(source,NSMakeSize(25,0),page);
    require(near(NSMinX(panned),125),"moving content right shows what is to the left");
    panned=TSLinkPreviewPan(source,NSMakeSize(-5000,5000),page);
    require(near(NSMaxX(panned),600) && near(NSMinY(panned),0),"scrolling stops at the page edge");
    panned=TSLinkPreviewPan(NSMakeRect(0,0,700,900),NSMakeSize(10,10),page);
    require(near(NSMinX(panned),0) && near(NSMinY(panned),0),"source larger than the page stays at its origin");
    NSRect previous=TSLinkPreviewPan(source,NSMakeSize(-900,-900),page);
    for (CGFloat d=-900; d<=900; d+=0.5) {
        panned=TSLinkPreviewPan(source,NSMakeSize(d,d),page);
        require(contains(NSMakeRect(0,0,600,800),panned) && near(NSWidth(panned),300) && near(NSHeight(panned),150),
                "scrolling keeps the source on the page");
        require(fabs(NSMinX(panned)-NSMinX(previous))<=0.5001 && fabs(NSMinY(panned)-NSMinY(previous))<=0.5001,
                "scrolling is continuous");
        previous=panned;
    }
}
int main(int argc, const char **argv) { @autoreleasepool {
    NSRect source, output;
    require(TSLinkPreviewRects(NSMakeSize(418.431,637.609), NSMakePoint(91.009,598.328), NSZeroRect,
        NSMakeRect(0,0,418.431,637.609), NSMakePoint(396,500), YES, NO, YES, NO, &source,&output), "reported example");
    require(near(source.origin.x,0) && near(source.size.width,418.431), "narrow page includes full width");
    require(contains(NSMakeRect(5,5,408.431,627.609), output), "reported output remains visible");
    for (NSInteger enlarged=0; enlarged<2; enlarged++) for (NSInteger flipped=0; flipped<2; flipped++)
    for (NSInteger above=0; above<2; above++) for (NSInteger corner=0; corner<4; corner++)
    for (NSInteger n=0; n<4; n++) {
        NSSize size=NSMakeSize((CGFloat[]){300,418.431,595,1000}[n], (CGFloat[]){200,638,842,1200}[n]);
        NSRect visible=NSMakeRect(-100,230,(CGFloat[]){80,418,445,1000}[n],(CGFloat[]){70,250,360,900}[n]);
        NSPoint cursor=NSMakePoint(corner&1 ? NSMaxX(visible) : NSMinX(visible), corner&2 ? NSMaxY(visible) : NSMinY(visible));
        NSPoint destination=NSMakePoint(corner&1 ? size.width : 0, corner&2 ? size.height : 0);
        require(TSLinkPreviewRects(size,destination,NSZeroRect,visible,cursor,enlarged,above,flipped,NO,&source,&output), "valid geometry");
        require(contains(NSMakeRect(0,0,size.width,size.height),source), "source in page");
        require(contains(NSInsetRect(visible,5,5),output), "output in viewport");
        require(near(source.size.width/source.size.height,output.size.width/output.size.height), "uniform scale");
        CGFloat full=MIN(size.height,enlarged?360:120);
        // A destination at the bottom of its page shows only the lowest part of the page (#14).
        require(near(source.size.height,corner&2 ? full : MIN(full,TSLinkPreviewMinimumCrop)),
                "left/right use the same command height, lower at the bottom of the page");
    }
    require(!TSLinkPreviewRects(NSMakeSize(400,600),NSMakePoint(NAN,1),NSZeroRect,NSMakeRect(0,0,800,600),NSZeroPoint,0,0,0,NO,&source,&output), "invalid destination rejected");
    require(!TSLinkPreviewRects(NSMakeSize(400,600),NSZeroPoint,NSZeroRect,NSMakeRect(0,0,8,8),NSZeroPoint,0,0,0,NO,&source,&output), "empty viewport rejected");
    testDrawing();
    testTextContext();
    testPlacementAndUnspecified();
    testColumnsAndWidePages();
    testRotatedTextContext();
    testColumnWidth();
    testKeptSide();
    testBottomAndStrip();
    testContinuousShrinking();
    testPinnedInteraction();
    require(argc>1,"real document path");
    testDocument(argv[1]);
    puts("PASS: link preview bounds, aspect ratio, command sizing, CropBox and rotations");
} }
