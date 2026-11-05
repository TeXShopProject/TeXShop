// Snapshot placement per volume, the in-place fallback and stale directory cleanup.
#import "TSExternalPDFReload.h"
#include <unistd.h>
static void Check(BOOL ok, NSString *message) { if(!ok){NSLog(@"FAIL: %@",message);exit(1);} }
static NSData *PDF(void) {
    NSMutableData *data=[NSMutableData data];CGDataConsumerRef sink=CGDataConsumerCreateWithCFData((__bridge CFMutableDataRef)data);
    CGRect box=CGRectMake(0,0,300,400);CGContextRef ctx=CGPDFContextCreate(sink,&box,NULL);
    for(int i=0;i<3;i++){CGPDFContextBeginPage(ctx,NULL);CGContextSetRGBFillColor(ctx,0,0,1,1);CGContextFillRect(ctx,box);CGPDFContextEndPage(ctx);}
    CGPDFContextClose(ctx);CGContextRelease(ctx);CGDataConsumerRelease(sink);return data;
}
static dev_t Device(NSString *path) { struct stat info; return stat(path.fileSystemRepresentation,&info) ? (dev_t)-1 : info.st_dev; }
static NSArray<NSString *> *OwnSnapshots(NSString *root) {
    NSMutableArray *found=[NSMutableArray array];NSString *prefix=[NSString stringWithFormat:@"TeXShop-PDF-%d-",getpid()];
    NSDirectoryEnumerator *walk=[NSFileManager.defaultManager enumeratorAtPath:root];
    for(NSString *item in walk) if([item.lastPathComponent hasPrefix:prefix]) [found addObject:item];
    return found;
}
int main(int argc,char **argv) { @autoreleasepool {
    NSString *mode=@(argv[1]);NSFileManager *fm=NSFileManager.defaultManager;
    if([mode isEqual:@"stale"]) {
        NSString *parent=@(argv[2]);int dead=atoi(argv[3]);NSString *uuid=NSUUID.UUID.UUIDString;
        NSArray *removed=@[[NSString stringWithFormat:@"TeXShop-PDF-%d-%@",dead,uuid]];
        NSArray *kept=@[[NSString stringWithFormat:@"TeXShop-PDF-%d-%@",getpid(),uuid],[NSString stringWithFormat:@"TeXShop-PDF-1-%@",uuid],
                        [NSString stringWithFormat:@"TeXShop-PDF-%@",uuid],[NSString stringWithFormat:@"TeXShop-PDF-%d-not-a-uuid",dead],
                        [NSString stringWithFormat:@"Other-PDF-%d-%@",dead,uuid],[NSString stringWithFormat:@"TeXShop-PDF-x%d-%@",dead,uuid]];
        for(NSString *name in [removed arrayByAddingObjectsFromArray:kept])
            Check([fm createDirectoryAtPath:[parent stringByAppendingPathComponent:name] withIntermediateDirectories:NO attributes:nil error:NULL],@"Create fixture");
        NSString *file=[NSString stringWithFormat:@"TeXShop-PDF-%d-%@",dead,NSUUID.UUID.UUIDString];
        Check([NSData.data writeToFile:[parent stringByAppendingPathComponent:file] atomically:NO],@"Create file fixture");
        kept=[kept arrayByAddingObject:file];
        TSRemoveStalePDFSnapshots(parent);
        for(NSString *name in removed) Check(![fm fileExistsAtPath:[parent stringByAppendingPathComponent:name]],[@"Stale directory removed: " stringByAppendingString:name]);
        for(NSString *name in kept) Check([fm fileExistsAtPath:[parent stringByAppendingPathComponent:name]],[@"Unrelated or live item kept: " stringByAppendingString:name]);
        puts("PASS: stale snapshot directories of dead processes removed; live, foreign and malformed names kept");
        return 0;
    }
    NSString *path=@(argv[2]),*volume=@(argv[3]);
    [fm createDirectoryAtPath:path.stringByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:NULL];
    NSData *data=PDF();Check([data writeToFile:path atomically:NO],@"Write PDF");
    NSString *temporary=NSTemporaryDirectory().stringByResolvingSymlinksInPath;
    NSUInteger before=OwnSnapshots(temporary).count;
    for(int initial=0;initial<2;initial++) {
        __weak PDFDocument *weakDocument;NSString *snapshot;
        @autoreleasepool {
            PDFDocument *document=initial?TSInitialPDFSnapshot(path,TSExternalPDFSignature(path)):TSExternalPDFSnapshot(path,TSExternalPDFSignature(path));
            weakDocument=document;snapshot=document.documentURL.path.stringByResolvingSymlinksInPath;
            Check(document.pageCount==3,@"Snapshot loads");
            if([mode isEqual:@"direct"]) {
                Check([document.documentURL.path isEqual:path],@"Volume without clones reads the PDF in place");
                Check(OwnSnapshots(volume).count==0 && OwnSnapshots(temporary).count==before,@"No private copy is made");
            } else {
                NSString *directory=snapshot.stringByDeletingLastPathComponent;
                Check(![document.documentURL.path isEqual:path],@"Private clone");
                Check([directory.lastPathComponent hasPrefix:[NSString stringWithFormat:@"TeXShop-PDF-%d-",getpid()]],@"Directory names the owning process");
                Check(Device(snapshot)==Device(path),@"Clone lives on the PDF's volume");
                Check([mode isEqual:@"temp"]==[directory.stringByDeletingLastPathComponent isEqual:temporary],
                      [NSString stringWithFormat:@"Snapshot parent %@",directory.stringByDeletingLastPathComponent]);
                Check([[NSData data] writeToFile:path atomically:NO],@"Truncate original");
                Check([[document pageAtIndex:2] thumbnailOfSize:NSMakeSize(90,120) forBox:kPDFDisplayBoxMediaBox]!=nil && document.pageCount==3,@"Clone survives truncation");
                [data writeToFile:path atomically:NO];
            }
        }
        Check(weakDocument==nil,@"Document released");
        if(![mode isEqual:@"direct"]) Check(![fm fileExistsAtPath:snapshot.stringByDeletingLastPathComponent],@"Snapshot directory removed on release");
        printf("PASS: %s %s %s\n",mode.UTF8String,initial?"initial":"reload",snapshot.UTF8String);
    }
    Check(OwnSnapshots(volume).count==0 && OwnSnapshots(temporary).count==before,@"Nothing left behind");
}return 0;}
