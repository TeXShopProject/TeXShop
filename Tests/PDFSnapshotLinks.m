// Terada: symlinks must produce a private regular file, never another symlink.
#import "TSExternalPDFReload.h"
#include <unistd.h>
static void Check(BOOL ok, NSString *message) { if(!ok){NSLog(@"FAIL: %@",message);exit(1);} }
static PDFDocument *retainedAtExit;
int main(int argc,char **argv) { @autoreleasepool {
    NSString *dir=@(argv[1]);NSFileManager *fm=NSFileManager.defaultManager;
    NSString *target=[dir stringByAppendingPathComponent:@"out/file.pdf"];
    [fm createDirectoryAtPath:target.stringByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:NULL];
    NSMutableData *data=[NSMutableData data];CGDataConsumerRef sink=CGDataConsumerCreateWithCFData((__bridge CFMutableDataRef)data);
    CGRect box=CGRectMake(0,0,300,400);CGContextRef ctx=CGPDFContextCreate(sink,&box,NULL);
    for(int i=0;i<3;i++){CGPDFContextBeginPage(ctx,NULL);CGContextSetRGBFillColor(ctx,1,0,0,1);CGContextFillRect(ctx,box);CGPDFContextEndPage(ctx);}
    CGPDFContextClose(ctx);CGContextRelease(ctx);CGDataConsumerRelease(sink);
    for(NSString *kind in @[@"relative",@"absolute",@"exit"]) {
        [data writeToFile:target atomically:NO];
        NSString *link=[dir stringByAppendingPathComponent:kind];
        NSString *dest=[kind isEqual:@"relative"]?@"out/file.pdf":target;
        Check(symlink(dest.fileSystemRepresentation,link.fileSystemRepresentation)==0,@"Create link");
        __weak PDFDocument *weakDoc;NSString *snapshot;
        @autoreleasepool {
            PDFDocument *doc=TSExternalPDFSnapshot(link,TSExternalPDFSignature(link));weakDoc=doc;
            Check(doc.pageCount==3,@"Read through symlink");snapshot=doc.documentURL.path;
            struct stat st;Check(lstat(snapshot.fileSystemRepresentation,&st)==0 && S_ISREG(st.st_mode),@"Snapshot is regular file");
            [[NSData data] writeToFile:target atomically:NO];
            NSImage *image=[[doc pageAtIndex:2] thumbnailOfSize:NSMakeSize(90,120) forBox:kPDFDisplayBoxMediaBox];
            Check(image!=nil && doc.pageCount==3,@"Lazy last page survives target truncation");
            if([kind isEqual:@"exit"]) {retainedAtExit=doc;[snapshot writeToFile:[dir stringByAppendingPathComponent:@"exit-path"] atomically:YES encoding:NSUTF8StringEncoding error:NULL];}
        }
        if(![kind isEqual:@"exit"]) Check(!weakDoc && ![fm fileExistsAtPath:snapshot],@"Removed on release");
        printf("PASS: %s symlink isolation\n",kind.UTF8String);
    }
}return 0;}
