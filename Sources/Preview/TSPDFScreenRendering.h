// added by Terada: Avoid Metal aborts during PDF line rendering on Golden Gate.
#import <Cocoa/Cocoa.h>

// Tile in device coordinates to preserve scale and rotation while bounding bitmap memory.
static inline void TSDrawPDFScreenTiles(CGContextRef destination, void (^draw)(CGContextRef))
{
    CGAffineTransform transform = CGContextGetCTM(destination);
    CGRect bounds = CGRectIntegral(CGRectApplyAffineTransform(CGContextGetClipBoundingBox(destination), transform));
    if (CGRectIsEmpty(bounds) || CGRectIsInfinite(bounds) || CGRectIsNull(bounds) ||
        !isfinite(bounds.origin.x) || !isfinite(bounds.origin.y) ||
        !isfinite(bounds.size.width) || !isfinite(bounds.size.height) ||
        transform.a * transform.d == transform.b * transform.c) return;
    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    for (CGFloat y = CGRectGetMinY(bounds); y < CGRectGetMaxY(bounds); y += 1024) {
        for (CGFloat x = CGRectGetMinX(bounds); x < CGRectGetMaxX(bounds); x += 1024) {
            CGRect tile = CGRectMake(x, y, MIN(1024, CGRectGetMaxX(bounds) - x), MIN(1024, CGRectGetMaxY(bounds) - y));
            CGContextRef bitmap = CGBitmapContextCreate(NULL, (size_t)tile.size.width, (size_t)tile.size.height,
                                                        8, 0, colorSpace, (CGBitmapInfo)kCGImageAlphaPremultipliedLast);
            if (!bitmap) { NSLog(@"TeXShop: PDF preview bitmap allocation failed"); continue; }
            CGContextTranslateCTM(bitmap, -x, -y);
            CGContextConcatCTM(bitmap, transform);
            draw(bitmap);
            CGImageRef image = CGBitmapContextCreateImage(bitmap);
            if (image) {
                CGContextSaveGState(destination);
                CGContextConcatCTM(destination, CGAffineTransformInvert(transform));
                CGContextSetInterpolationQuality(destination, kCGInterpolationNone);
                CGContextDrawImage(destination, tile, image);
                CGContextRestoreGState(destination);
                CGImageRelease(image);
            }
            CGContextRelease(bitmap);
        }
    }
    CGColorSpaceRelease(colorSpace);
}
