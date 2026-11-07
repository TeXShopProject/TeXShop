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
        require(output.size.width <= (enlarged?445:400*2.0/3.0)+0.001, "expanded source does not enlarge popup");
        destination.x=196;
    }
    NSSize emptySize; CGAffineTransform emptyTransform;
    PDFPage *empty=[fixture() pageAtIndex:0];
    require(TSLinkPreviewPageGeometry(empty,&emptySize,&emptyTransform), "graphics page geometry");
    require(NSIsEmptyRect(TSLinkPreviewTextBounds(empty,emptySize,NSMakePoint(100,300),emptyTransform,YES)),
            "graphics-only PDF falls back without text bounds");
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
int main(void) { @autoreleasepool {
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
    puts("PASS: link preview bounds, aspect ratio, command sizing, CropBox and rotations");
} }
