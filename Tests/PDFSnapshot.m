// Terada: measure file-backed snapshots and validate their lifetime in isolation.
#import "TSExternalPDFReload.h"
#import <mach/mach.h>
static double Footprint(void) {
    task_vm_info_data_t info; mach_msg_type_number_t count=TASK_VM_INFO_COUNT;
    task_info(mach_task_self(),TASK_VM_INFO,(task_info_t)&info,&count);
    return info.phys_footprint/1048576.0;
}
static void Check(BOOL ok, NSString *message) { if(!ok){NSLog(@"FAIL: %@",message);exit(1);} }
int main(int argc,char **argv) { @autoreleasepool {
    NSString *path=@(argv[1]), *mode=@(argv[2]);
    if([mode isEqual:@"generate"]) {
        CGRect box=CGRectMake(0,0,612,792);
        CGContextRef pdf=CGPDFContextCreateWithURL((__bridge CFURLRef)[NSURL fileURLWithPath:path],&box,NULL);
        CGColorSpaceRef rgb=CGColorSpaceCreateDeviceRGB();
        for(int page=0;page<25;page++) { @autoreleasepool {
            NSMutableData *pixels=[NSMutableData dataWithLength:2000*2000*3];arc4random_buf(pixels.mutableBytes,pixels.length);
            CGDataProviderRef provider=CGDataProviderCreateWithCFData((__bridge CFDataRef)pixels);
            CGImageRef image=CGImageCreate(2000,2000,8,24,6000,rgb,(CGBitmapInfo)kCGImageAlphaNone,provider,NULL,NO,kCGRenderingIntentDefault);
            CGPDFContextBeginPage(pdf,NULL);CGContextDrawImage(pdf,box,image);CGPDFContextEndPage(pdf);
            CGImageRelease(image);CGDataProviderRelease(provider);
        }}
        CGPDFContextClose(pdf);CGContextRelease(pdf);CGColorSpaceRelease(rgb);return 0;
    }
    [NSApplication sharedApplication];
    double before=Footprint();__weak PDFDocument *weakDocument; NSString *privatePath;
    @autoreleasepool {
        PDFDocument *document;
        if([mode isEqual:@"snapshot"]) document=TSExternalPDFSnapshot(path,TSExternalPDFSignature(path));
        else if([mode isEqual:@"data"]) document=[[PDFDocument alloc] initWithData:[NSData dataWithContentsOfFile:path]];
        else document=[[PDFDocument alloc] initWithURL:[NSURL fileURLWithPath:path]];
        Check(document.pageCount==25,@"25 pages loaded");weakDocument=document;
        if([mode isEqual:@"snapshot"]) {
            privatePath=document.documentURL.path;
            Check(![privatePath isEqual:path],@"PDF backed by private file");
            Check([[NSFileManager defaultManager] fileExistsAtPath:privatePath],@"Snapshot lives with document");
            Check([[NSData data] writeToFile:path atomically:NO],@"Overwrite external PDF after snapshot");
            NSImage *last=[[document pageAtIndex:24] thumbnailOfSize:NSMakeSize(150,200) forBox:kPDFDisplayBoxMediaBox];
            Check(last != nil && document.pageCount==25,@"Private snapshot survives original truncation and lazy last-page rendering");
        }
        PDFView *first=[PDFView new],*second=[PDFView new];first.document=document;second.document=document;
        NSImage *thumbnail=[[document pageAtIndex:0] thumbnailOfSize:NSMakeSize(150,200) forBox:kPDFDisplayBoxMediaBox];
        Check(thumbnail!=nil,@"Lazy page rendered");
        printf("%s footprintDeltaMB=%.1f pages=%lu\n",mode.UTF8String,Footprint()-before,(unsigned long)document.pageCount);
        first.document=nil;second.document=nil;
    }
    if([mode isEqual:@"snapshot"]) {
        Check(weakDocument==nil,@"Document released");
        Check(![[NSFileManager defaultManager] fileExistsAtPath:privatePath],@"Snapshot removed on release");
        puts("PASS: file-backed snapshot lifetime");
    }
} return 0; }
