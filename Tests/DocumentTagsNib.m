#import "TestAppKitIsolation.h"
// Inspect actual compiled nibs without starting TeXShop or loading its preferences.
#import <Cocoa/Cocoa.h>
#import <PDFKit/PDFKit.h>
#import <objc/runtime.h>
static NSMutableDictionary *outlets;
@interface TSDocument : NSObject
@property NSPopUpButton *tags;
@property NSPopUpButton *stags;
@end
@implementation TSDocument
- (void)setValue:(id)value forUndefinedKey:(NSString *)key {}
@end
static void SetOutlet(id self,SEL cmd,id value,NSString *key) { if(value) outlets[key]=value; }
static void Register(NSString *name,Class base) {
 Class c=objc_allocateClassPair(base,name.UTF8String,0);
 class_addMethod(c,@selector(setValue:forUndefinedKey:),(IMP)SetOutlet,"v@:@@");
 objc_registerClassPair(c);
}
int main(int argc,char **argv) { @autoreleasepool {
 TSInstallAppKitIsolation(); [NSApplication sharedApplication];outlets=[NSMutableDictionary dictionary];

 for(NSString *name in @[@"TSConsoleWindow",@"TSFullSplitWindow",@"TSFullscreenWindow",@"TSHTMLWindow",@"TSLogWindow",@"TSPreviewWindow",@"TSTextEditorWindow"]) Register(name,NSWindow.class);
 Register(@"MyPDFView",NSView.class);
 Register(@"MyPDFKitView",PDFView.class);Register(@"ScrapPDFKitView",PDFView.class);
 Register(@"TSTextView",NSTextView.class);Register(@"ScrapTextView",NSTextView.class);
 for(int i=1;i<argc;i++) {
  [outlets removeAllObjects];
  NSNib *nib=[[NSNib alloc] initWithNibData:[NSData dataWithContentsOfFile:@(argv[i])] bundle:nil];
  NSArray *objects;id owner=[NSClassFromString(@"TSDocument") new];
  if(![nib instantiateWithOwner:owner topLevelObjects:&objects]) return 1;
  for(NSString *key in @[@"tags",@"stags"]) {
   NSPopUpButton *button=[owner valueForKey:key];
   if(!button) { fprintf(stderr,"Missing outlet %s\n",key.UTF8String); return 2; }
   NSString *expected=@(getenv("TS_EXPECT_TAGS"));
   if(![button.title isEqual:expected] || ![button.itemArray.firstObject.title isEqual:expected]) return 3;
   printf("%s %s title=%s first=%s\n",argv[i],key.UTF8String,button.title.UTF8String,button.itemArray.firstObject.title.UTF8String);
  }
  for(id object in objects) if([object isKindOfClass:NSWindow.class]) [object orderOut:nil];
 }
}return 0;}
