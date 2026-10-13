#!/usr/bin/env python3
# added by Terada: Independently test PDFView drawing, CPU tile coordinates, and vector printing.
from pathlib import Path
import subprocess, tempfile, sys, os
root=Path(__file__).resolve().parents[1]
s=(root/'Sources/MyPDFKitView.m').read_bytes().decode('utf-8',errors='replace')
start=s.index('- (void)drawPage:(PDFPage *)page toContext:')
method=s[start:s.index('\n}',start)+2]
program=r'''
#import <Cocoa/Cocoa.h>
#import <PDFKit/PDFKit.h>
#import "TSPDFScreenRendering.h"
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
 [NSApplication sharedApplication];[NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];
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
 PDFDocument*d=argc>1?[[PDFDocument alloc]initWithURL:[NSURL fileURLWithPath:[NSString stringWithUTF8String:argv[1]]]]:sampleDoc;check(d.pageCount>0,@"Input PDF");
 NSWindow*w=[[NSWindow alloc]initWithContentRect:NSMakeRect(50,50,800,950) styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
 PDFView*v=[[SafeView alloc]initWithFrame:w.contentView.bounds];w.contentView=v;v.document=d;v.displayMode=kPDFDisplaySinglePage;v.scaleFactor=1.5;[w orderFront:nil];
 for(NSUInteger p=0;p<d.pageCount;p++){[v goToPage:[d pageAtIndex:p]];[v display];[[NSRunLoop currentRunLoop]runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.15]];}
 check(draws>d.pageCount,@"PDF screen drawing executed");fprintf(stderr,"PASS: %lu pages; Metal validation, tile pixels, rotation, clipping, vector printing\n",d.pageCount);
}}
'''.replace('METHOD',method)
with tempfile.TemporaryDirectory(prefix='texshop-screen-render-') as folder:
    p=Path(folder);(p/'test.m').write_text(program)
    subprocess.run(['xcrun','clang','-fobjc-arc','-framework','Cocoa','-framework','PDFKit','-I',str(root/'Sources'),str(p/'test.m'),'-o',str(p/'test')],check=True)
    subprocess.run([str(p/'test'),*sys.argv[1:]],env={**os.environ,'MTL_DEBUG_LAYER':'1'},check=True)
