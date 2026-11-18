#!/usr/bin/env python3
# added by Terada: Independently test PDFView drawing, CPU tile coordinates, and vector printing.
"""Default/--headless: isolated CPU checks. --screen [PDF]: explicitly displays a window.

A dark preview inverts its pages as they are drawn: the page drawn inverted equals the page
drawn as it is and then inverted, pixel for pixel, at the resolution of the destination, so
a magnified page stays sharp; white paper comes out at about RGB(45,45,45)."""
import argparse
parser=argparse.ArgumentParser(description=__doc__)
modes=parser.add_mutually_exclusive_group()
modes.add_argument('--headless',action='store_true')
modes.add_argument('--screen',action='store_true')
parser.add_argument('pdf',nargs='?')
parser.add_argument('--mutation',choices=['no-inversion','unmagnified'])
args=parser.parse_args()
if args.pdf and not args.screen: parser.error('a PDF path requires --screen; this displays a window')
from pathlib import Path
import subprocess, tempfile, sys, os
from source_tree import include_args
root=Path(__file__).resolve().parents[1]
s=(root/'Sources/Preview/MyPDFKitView.m').read_bytes().decode('utf-8',errors='replace')
start=s.index('- (void)drawPage:(PDFPage *)page toContext:')
method=s[start:s.index('\n}',start)+2]
if args.mutation=='no-inversion':
    old='    if (screen && TSPreviewPagesInverted(self)) {\n'
    assert method.count(old)==1, args.mutation
    method=method.replace(old,'    if (0) {\n')
elif args.mutation=='unmagnified':
    # The inverted page is drawn at the page's own size and scaled up, as a filter on a magnified view is.
    old='        TSDrawPDFScreenTilesProcessed(context, ^(CGContextRef target) {\n'
    assert method.count(old)==1, args.mutation
    method=method.replace(old,'        CGContextScaleCTM(context, 4, 4); CGContextScaleCTM(context, .25, .25); CGContextSetInterpolationQuality(context, kCGInterpolationNone);\n        TSDrawPDFScreenTilesProcessed(CGBitmapContextCreate(NULL, 1, 1, 8, 0, CGColorSpaceCreateDeviceRGB(), (CGBitmapInfo)kCGImageAlphaPremultipliedLast), ^(CGContextRef target) {\n')
program=r'''
#import <Cocoa/Cocoa.h>
#import "TestAppKitIsolation.h"
#import <PDFKit/PDFKit.h>
#import "TSPDFScreenRendering.h"
#import "TSPreviewAppearance.h"
static NSUInteger draws=0;
@interface SafeView:PDFView
@end
@implementation SafeView
- (void)drawPage:(PDFPage*)page {
 draws++;
 CGContextRef c=NSGraphicsContext.currentContext.CGContext;
 CGContextSetRGBFillColor(c,1,1,1,1);CGContextFillRect(c,[page boundsForBox:self.displayBox]);
 [page drawWithBox:self.displayBox toContext:c];
}
METHOD
@end
static void check(BOOL v,NSString*m){if(!v){NSLog(@"FAIL %@",m);exit(1);}}
static void shape(CGContextRef c){
 CGContextSetRGBFillColor(c,1,1,1,1);CGContextFillRect(c,CGRectMake(-1000,-1000,4000,4000));
 CGContextSetRGBFillColor(c,.8,.1,.2,1);CGContextFillRect(c,CGRectMake(15,25,180,75));
 CGContextSetRGBStrokeColor(c,0,.2,.8,1);CGContextSetLineWidth(c,3);CGContextStrokeRect(c,CGRectMake(50,70,210,190));
}
static NSData *sample(void){
 NSMutableData*d=[NSMutableData data];CGDataConsumerRef consumer=CGDataConsumerCreateWithCFData((__bridge CFMutableDataRef)d);
 CGRect box=CGRectMake(0,0,400,600);CGContextRef c=CGPDFContextCreate(consumer,&box,NULL);
 CGPDFContextBeginPage(c,NULL);shape(c);CGPDFContextEndPage(c);CGPDFContextClose(c);CGContextRelease(c);CGDataConsumerRelease(consumer);return d;
}
int main(int argc,char**argv){@autoreleasepool{
 BOOL screen = argc>1 && strcmp(argv[1],"--screen")==0;
 if(!screen) TSInstallAppKitIsolation();[NSApplication sharedApplication];[NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];
 // Keep original vector drawing for non-screen contexts.
 SafeView *printView=[SafeView new];PDFDocument*sampleDoc=[[PDFDocument alloc]initWithData:sample()];
 NSMutableData*out=[NSMutableData data];CGDataConsumerRef consumer=CGDataConsumerCreateWithCFData((__bridge CFMutableDataRef)out);CGRect box=CGRectMake(0,0,400,600);CGContextRef pdf=CGPDFContextCreate(consumer,&box,NULL);
 CGPDFContextBeginPage(pdf,NULL);[printView drawPage:[sampleDoc pageAtIndex:0] toContext:pdf];CGPDFContextEndPage(pdf);CGPDFContextClose(pdf);CGContextRelease(pdf);CGDataConsumerRelease(consumer);
 CGDataProviderRef provider=CGDataProviderCreateWithCFData((__bridge CFDataRef)out);CGPDFDocumentRef printed=CGPDFDocumentCreateWithProvider(provider);CGPDFDictionaryRef resources=NULL,xobjects=NULL;
 CGPDFDictionaryGetDictionary(CGPDFPageGetDictionary(CGPDFDocumentGetPage(printed,1)),"Resources",&resources);
 check(!CGPDFDictionaryGetDictionary(resources,"XObject",&xobjects)||CGPDFDictionaryGetCount(xobjects)==0,@"No raster images added to print output");CGPDFDocumentRelease(printed);CGDataProviderRelease(provider);
 for(int rotation=0;rotation<4;rotation++){
 CGColorSpaceRef space=CGColorSpaceCreateDeviceRGB();CGContextRef a=CGBitmapContextCreate(NULL,1400,1400,8,0,space,(CGBitmapInfo)kCGImageAlphaPremultipliedLast),b=CGBitmapContextCreate(NULL,1400,1400,8,0,space,(CGBitmapInfo)kCGImageAlphaPremultipliedLast);CGColorSpaceRelease(space);
 for(int n=0;n<2;n++){CGContextRef c=n?b:a;CGContextTranslateCTM(c,700,700);CGContextRotateCTM(c,rotation*M_PI_2);CGContextScaleCTM(c,1.75,1.75);CGContextTranslateCTM(c,-200,-200);CGContextClipToRect(c,CGRectMake(-150,-150,700,700));}
 shape(a);TSDrawPDFScreenTiles(b,^(CGContextRef c){shape(c);});
 size_t bytes=CGBitmapContextGetBytesPerRow(a)*1400;check(memcmp(CGBitmapContextGetData(a),CGBitmapContextGetData(b),bytes)==0,@"Matching pixels for scale, rotation, clipping, and tile boundaries");CGContextRelease(a);CGContextRelease(b);
 }
 {
 // A dark preview: the page drawn inverted at 4x equals the page drawn as it is at 4x and then inverted.
 SafeView *plain=[SafeView new], *dark=[SafeView new];
 objc_setAssociatedObject(dark, TSPreviewPagesInvertedKey, @YES, OBJC_ASSOCIATION_RETAIN);
 PDFPage *page=[sampleDoc pageAtIndex:0];
 CGColorSpaceRef srgb=CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
 CGContextRef a=CGBitmapContextCreate(NULL,1600,2400,8,0,srgb,(CGBitmapInfo)kCGImageAlphaPremultipliedLast),
  b=CGBitmapContextCreate(NULL,1600,2400,8,0,srgb,(CGBitmapInfo)kCGImageAlphaPremultipliedLast),
  c=CGBitmapContextCreate(NULL,1600,2400,8,0,srgb,(CGBitmapInfo)kCGImageAlphaPremultipliedLast);
 CGContextScaleCTM(a,4,4);CGContextScaleCTM(b,4,4);
 check([NSGraphicsContext graphicsContextWithCGContext:b flipped:NO].drawingToScreen,@"a bitmap counts as drawing to the screen");
 [plain drawPage:page toContext:a];[dark drawPage:page toContext:b];
 CGImageRef drawn=CGBitmapContextCreateImage(a),inverted=TSPreviewCreateInvertedImage(drawn);
 check(inverted!=NULL,@"the inverted image is made");
 CGContextDrawImage(c,CGRectMake(0,0,1600,2400),inverted);CGImageRelease(drawn);CGImageRelease(inverted);
 const unsigned char *pb=CGBitmapContextGetData(b),*pc=CGBitmapContextGetData(c);size_t row=CGBitmapContextGetBytesPerRow(b),worst=0;
 for(size_t y=0;y<2400;y++)for(size_t x=0;x<1600*4;x++){size_t d=abs((int)pb[y*row+x]-(int)pc[y*row+x]);if(d>worst)worst=d;}
 const unsigned char *paper=pb+(2400-40)*row+4*40;
 fprintf(stderr,"inverted page: worst difference %zu, paper %d %d %d\n",worst,paper[0],paper[1],paper[2]);
 check(abs(paper[0]-45)<=2&&abs(paper[1]-45)<=2&&abs(paper[2]-45)<=2,@"white paper of a dark preview is drawn at about RGB(45,45,45)");
 check(worst<=1,@"the page drawn inverted equals the page drawn at the same resolution and then inverted, so it is as sharp");
 CGContextRelease(a);CGContextRelease(b);CGContextRelease(c);CGColorSpaceRelease(srgb);
 }
 if (!screen) { puts("PASS: headless tile pixels, rotation, clipping, vector printing; screen/Metal check requires a displayed window"); return 0; }
 PDFDocument*d=argc>2?[[PDFDocument alloc]initWithURL:[NSURL fileURLWithPath:[NSString stringWithUTF8String:argv[2]]]]:sampleDoc;check(d.pageCount>0,@"Input PDF");
 NSWindow*w=[[NSWindow alloc]initWithContentRect:NSMakeRect(50,50,800,950) styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
 PDFView*v=[[SafeView alloc]initWithFrame:w.contentView.bounds];w.contentView=v;v.document=d;v.displayMode=kPDFDisplaySinglePage;v.scaleFactor=1.5;[w orderFront:nil];
 for(NSUInteger p=0;p<d.pageCount;p++){[v goToPage:[d pageAtIndex:p]];[v display];[[NSRunLoop currentRunLoop]runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.15]];}
 check(draws>d.pageCount,@"PDF screen drawing executed");fprintf(stderr,"PASS: %lu pages; Metal validation, tile pixels, rotation, clipping, vector printing\n",d.pageCount);
}}
'''.replace('METHOD',method)
with tempfile.TemporaryDirectory(prefix='texshop-screen-render-') as folder:
    p=Path(folder);(p/'test.m').write_text(program)
    subprocess.run(['xcrun','clang','-I',str(root/'Tests'),'-fobjc-arc','-framework','Cocoa','-framework','PDFKit','-framework','Quartz','-framework','CoreImage',*include_args(root),str(p/'test.m'),'-o',str(p/'test')],check=True)
    run=subprocess.run([str(p/'test'),*[x for x in sys.argv[1:] if not x.startswith('--mutation') and x not in ('no-inversion','unmagnified')]],env={**os.environ,'MTL_DEBUG_LAYER':'1'},capture_output=True,text=True)
    if args.mutation:
        assert run.returncode!=0 and 'FAIL' in run.stderr, run.stdout+run.stderr
        print('PASS: detected',args.mutation)
    else:
        sys.stderr.write(run.stderr);sys.stdout.write(run.stdout)
        if run.returncode: sys.exit(run.returncode)
