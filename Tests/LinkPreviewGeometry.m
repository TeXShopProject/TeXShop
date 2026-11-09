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
            NSMakePoint(200,150), YES, NO, YES, &source, &output), "rotated destination crop");
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
                                  enlarged,NO,YES,&source,&output), "A4 equation preview");
        require(source.origin.x < 89, "A4 line beginning is included despite centered equation anchor");
        require(NSPointInRect(destination,source), "A4 equation anchor remains visible");
        // Widely separated text and destination must both remain visible; scale uniformly.
        destination.x=570;
        require(TSLinkPreviewRects(size,destination,text,NSMakeRect(0,0,1000,1000),NSMakePoint(500,500),
                                  enlarged,NO,YES,&source,&output), "distant text and destination");
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
                enlarged,NO,YES,&source,&output),"column preview");
            require(contains(source,equationBounds),"complete right-column formula remains visible");
            require(output.size.width/source.size.width >= (enlarged?1:2.0/3.0)*0.75-0.001,
                    "wide page context does not reduce readability below floor");
        }
    }
    // If all surrounding context is unavoidably wide, retain a local destination crop.
    for (NSInteger enlarged=0;enlarged<2;enlarged++) {
        NSRect source,output;
        require(TSLinkPreviewRects(NSMakeSize(2400,1000),NSMakePoint(1300,700),NSMakeRect(50,400,2200,300),
            NSMakeRect(0,0,2000,1200),NSMakePoint(800,500),enlarged,NO,YES,&source,&output),"poster fallback");
        require(source.origin.x>1200 && NSMaxX(source)>1500,"poster keeps destination and right-hand expression");
        require(near(output.size.width/source.size.width,enlarged?1:2.0/3.0),"poster fallback retains nominal scale");
    }
    NSRect source,output;
    require(TSLinkPreviewRects(NSMakeSize(800,900),NSMakePoint(200,700),NSMakeRect(80,400,500,300),
        NSMakeRect(0,0,2000,1200),NSMakePoint(800,500),YES,NO,YES,&source,&output),"command full text width");
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
            NSMakeRect(0,0,2000,2000),NSMakePoint(500,500),enlarged,above,flipped,&source,&output), "placement");
        require(near(output.size.width,(enlarged?445:400)*scale) &&
                near(output.size.height,(enlarged?360:120)*scale), "normal and command default scale");
        require(near(output.origin.x,500+(enlarged?-5:10)), "horizontal cursor anchor");
        CGFloat expectedY=above!=flipped ? 510 : 490-output.size.height;
        require(near(output.origin.y,expectedY), "Shift and flipped direction");
        NSPoint edge=NSMakePoint(500,above!=flipped ? 980 : 20);
        require(TSLinkPreviewRects(NSMakeSize(600,900),NSMakePoint(100,700),NSZeroRect,
            NSMakeRect(0,0,1000,1000),edge,enlarged,above,flipped,&source,&output), "opposite-side placement");
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
                              enlarged,NO,YES,source,output),"sized preview");
}
// The popup widens to the destination's text column instead of shrinking it.
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
            require(TSLinkPreviewRects(page,destination,text,visible,NSMakePoint(width/2,500),enlarged,NO,YES,
                                      &source,&output),"continuous geometry");
            CGFloat scale=output.size.width/source.size.width;
            require(contains(NSInsetRect(visible,5,5),output),"continuous output stays visible");
            require(scale>=floor-0.0001 && scale<=nominal+0.0001,"scale between floor and nominal");
            require(destination.x>=NSMinX(source)-0.001 && destination.x<=NSMaxX(source)+0.001,
                    "destination stays in the crop");
            CGFloat full=428+2*(enlarged?10:5);
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
                                  NO,NO,YES,&source,&output),"real link preview");
        require(NSIsEmptyRect(local) || (NSMinX(local)>=NSMinX(source)-0.5 && NSMaxX(local)<=NSMaxX(source)+0.5),
                "real link lines are not cut");
        require(near(output.size.width/source.size.width,2.0/3.0),"real link shown at nominal scale");
        links++;
    }
    require(links>200,"real document links checked");
    printf("checked %lu links in %s\n",(unsigned long)links,[[@(path) lastPathComponent] UTF8String]);
}
int main(int argc, const char **argv) { @autoreleasepool {
    NSRect source, output;
    require(TSLinkPreviewRects(NSMakeSize(418.431,637.609), NSMakePoint(91.009,598.328), NSZeroRect,
        NSMakeRect(0,0,418.431,637.609), NSMakePoint(396,500), YES, NO, YES, &source,&output), "reported example");
    require(near(source.origin.x,0) && near(source.size.width,418.431), "narrow page includes full width");
    require(contains(NSMakeRect(5,5,408.431,627.609), output), "reported output remains visible");
    for (NSInteger enlarged=0; enlarged<2; enlarged++) for (NSInteger flipped=0; flipped<2; flipped++)
    for (NSInteger above=0; above<2; above++) for (NSInteger corner=0; corner<4; corner++)
    for (NSInteger n=0; n<4; n++) {
        NSSize size=NSMakeSize((CGFloat[]){300,418.431,595,1000}[n], (CGFloat[]){200,638,842,1200}[n]);
        NSRect visible=NSMakeRect(-100,230,(CGFloat[]){80,418,445,1000}[n],(CGFloat[]){70,250,360,900}[n]);
        NSPoint cursor=NSMakePoint(corner&1 ? NSMaxX(visible) : NSMinX(visible), corner&2 ? NSMaxY(visible) : NSMinY(visible));
        NSPoint destination=NSMakePoint(corner&1 ? size.width : 0, corner&2 ? size.height : 0);
        require(TSLinkPreviewRects(size,destination,NSZeroRect,visible,cursor,enlarged,above,flipped,&source,&output), "valid geometry");
        require(contains(NSMakeRect(0,0,size.width,size.height),source), "source in page");
        require(contains(NSInsetRect(visible,5,5),output), "output in viewport");
        require(near(source.size.width/source.size.height,output.size.width/output.size.height), "uniform scale");
        require(near(source.size.height,MIN(size.height,enlarged?360:120)), "left/right use same command height");
    }
    require(!TSLinkPreviewRects(NSMakeSize(400,600),NSMakePoint(NAN,1),NSZeroRect,NSMakeRect(0,0,800,600),NSZeroPoint,0,0,0,&source,&output), "invalid destination rejected");
    require(!TSLinkPreviewRects(NSMakeSize(400,600),NSZeroPoint,NSZeroRect,NSMakeRect(0,0,8,8),NSZeroPoint,0,0,0,&source,&output), "empty viewport rejected");
    testDrawing();
    testTextContext();
    testPlacementAndUnspecified();
    testColumnsAndWidePages();
    testRotatedTextContext();
    testColumnWidth();
    testContinuousShrinking();
    require(argc>1,"real document path");
    testDocument(argv[1]);
    puts("PASS: link preview bounds, aspect ratio, command sizing, CropBox and rotations");
} }
