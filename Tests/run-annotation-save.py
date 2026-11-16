#!/usr/bin/env python3
"""Execute the production annotation-save method with noninteractive save/alert doubles."""
from pathlib import Path
import subprocess,tempfile,sys
r=Path(__file__).resolve().parents[1]
s=(r/'Sources/Preview/MyPDFKitView-Annotations.m').read_text()
a=s.index('- (void) saveAnnotations:');b=s.index('- (PDFDocument *)constructOutput',a)
method=s[a:b].replace('NSSavePanel','SavePanelProbe').replace('NSAlert *','AlertProbe *').replace('[[NSAlert alloc]','[[AlertProbe alloc]')
if '--mutation' in sys.argv: method=method.replace('self.myDocument.annotationsExist = NO;', ';')
if '--mutation-no-commit' in sys.argv:
    assert method.count('[self.myDocument annotationsWillBeSaved];')==1
    method=method.replace('[self.myDocument annotationsWillBeSaved];', ';')
source=r'''#import <Cocoa/Cocoa.h>
#import "TestAppKitIsolation.h"
static NSInteger response=NSModalResponseOK; static BOOL writeOK=YES, found=YES;static NSUInteger writes,alerts;
static void Check(BOOL b,NSString *s){if(!b){NSLog(@"FAIL: %@",s);exit(1);}}
@interface PDFDocument:NSObject
- (BOOL)writeToURL:(NSURL *)url;
@end
@implementation PDFDocument
- (BOOL)writeToURL:(NSURL *)url { writes++;return writeOK; }
@end
@interface SavePanelProbe:NSObject
@property(copy)NSString *nameFieldStringValue;
@property(strong)NSURL *directoryURL;
+ (instancetype)savePanel;
- (void)setAllowedFileTypes:(id)types;
- (NSInteger)runModal;
- (NSURL *)URL;
@end
@implementation SavePanelProbe
+ (instancetype)savePanel {return [self new];}
- (void)setAllowedFileTypes:(id)types {}
- (NSInteger)runModal {return response;}
- (NSURL *)URL {return [NSURL fileURLWithPath:@"/tmp/annotation-test-output.pdf"];}
@end
@interface AlertProbe:NSObject
- (void)addButtonWithTitle:(id)title; - (void)setMessageText:(id)text; - (void)setAlertStyle:(NSInteger)style; - (NSInteger)runModal;
@end
@implementation AlertProbe
- (void)addButtonWithTitle:(id)title {} - (void)setMessageText:(id)text {} - (void)setAlertStyle:(NSInteger)style {}
- (NSInteger)runModal {alerts++;return NSAlertFirstButtonReturn;}
@end
@interface Owner:NSObject
@property BOOL annotationsExist;
@property(strong)NSURL *fileURL;
@property BOOL annotationSaveAllPages;
@property NSUInteger committed, runModes, writesAtCommit, alertsAtCommit;
- (void)annotationsWillBeSaved;
- (void)setAnnotationEditMode:(BOOL)on;
@end
@implementation Owner
// The text being edited is committed before the save panel runs; edit mode ends through the document.
- (void)annotationsWillBeSaved { self.committed++; self.writesAtCommit=writes; self.alertsAtCommit=alerts; }
- (void)setAnnotationEditMode:(BOOL)on { if(!on) self.runModes++; }
@end
@interface Probe:NSObject {
BOOL fromTypesetOrQuit,annotationsFound,firstTimeSave;
NSString *nameValue;NSURL *locationURL;
}
@property(strong) Owner *myDocument;
@property(strong) PDFDocument *document;
- (void)saveAnnotations:(id)sender;
- (PDFDocument *)constructOutput;
- (void)deSelectAll;
@end
@implementation Probe
- (instancetype)init {if((self=[super init])){firstTimeSave=YES;self.myDocument=[Owner new];self.myDocument.fileURL=[NSURL fileURLWithPath:@"/tmp/input.custom-extension"];self.document=[PDFDocument new];}return self;}
- (void)deSelectAll {}
- (PDFDocument *)constructOutput {annotationsFound=found;return self.document;}
'''+method+r'''
@end
int main(){@autoreleasepool {
TSInstallAppKitIsolation(); [NSApplication sharedApplication];Probe *p=[Probe new];
for(int full=0;full<2;full++) for(int success=0;success<2;success++) for(int cancel=0;cancel<2;cancel++) {
p.myDocument.annotationsExist=YES;p.myDocument.annotationSaveAllPages=full;
response=cancel?NSModalResponseCancel:NSModalResponseOK;writeOK=success;found=YES;writes=0;alerts=0;
NSUInteger committed=p.myDocument.committed, runModes=p.myDocument.runModes;
[p saveAnnotations:nil];
Check(p.myDocument.committed==committed+1,@"Saving commits the text being edited");
Check(p.myDocument.writesAtCommit==0 && p.myDocument.alertsAtCommit==0,@"The text is committed before anything is written or asked");
Check(p.myDocument.runModes==runModes+1,@"Saving ends edit mode through the document");
Check(p.myDocument.annotationsExist == !(success && !cancel),@"Unsaved flag matches actual save outcome");
Check(writes==(cancel?0:1),@"Only accepted panels write; all file extensions supported");
}
p.myDocument.annotationsExist=YES;p.myDocument.annotationSaveAllPages=NO;found=NO;writes=0;alerts=0;[p saveAnnotations:nil];
Check(!p.myDocument.annotationsExist && writes==0 && alerts==1,@"No annotations clears stale flag after alert");
p.myDocument.fileURL=nil;p.myDocument.annotationsExist=YES;[p saveAnnotations:nil];Check(p.myDocument.annotationsExist,@"No file URL retains unsaved edits");
puts("PASS: production saveAnnotations full/annotated-only, success/failure/cancel, no annotations, nonstandard extension, no URL");
}return 0;}
'''
with tempfile.TemporaryDirectory(prefix='texshop-annotation-') as tmp:
 p=Path(tmp);(p/'main.m').write_text(source)
 subprocess.run(['xcrun','clang', '-I', str(r/'Tests'),'-fobjc-arc','-Wno-unused-variable','-framework','Cocoa',str(p/'main.m'),'-o',str(p/'probe')],check=True)
 subprocess.run([str(p/'probe')],check=True,timeout=20)
