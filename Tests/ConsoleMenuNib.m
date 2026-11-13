// Check the shipped localized menus using AppKit's key-equivalent dispatch.
#import <Cocoa/Cocoa.h>
#import <objc/runtime.h>
#import "TestAppKitIsolation.h"
static void IgnoreOutlet(id self,SEL cmd,id value,NSString *key) {}
static NSMenuItem *FindConsole(NSMenu *menu) {
 for(NSMenuItem *item in menu.itemArray) {
  if(item.action==@selector(displayConsole:)) return item;
  NSMenuItem *found=FindConsole(item.submenu); if(found) return found;
 }return nil;
}
@interface Receiver:NSWindow
@property NSUInteger calls;
- (void)displayConsole:(id)sender;
@end
@implementation Receiver
- (BOOL)canBecomeMainWindow { return YES; }
- (void)displayConsole:(id)sender {self.calls++;}
@end
int main(int argc,char **argv) { @autoreleasepool {
 TSInstallAppKitIsolation();
 [NSApplication sharedApplication];
 for(NSString *name in @[@"HelpDocuments",@"TSAppDelegate",@"TSDocumentController",@"TSMacroEditor",@"TSMacroMenuController",@"TSMovie",@"TSPreferences",@"TSSparkleController",@"TSStationery",@"TextFinder"]) {
  Class c=objc_allocateClassPair(NSObject.class,name.UTF8String,0);
  class_addMethod(c,@selector(setValue:forUndefinedKey:),(IMP)IgnoreOutlet,"v@:@@");objc_registerClassPair(c);
 }
 for(int i=1;i<argc;i++) {
  NSNib *nib=[[NSNib alloc] initWithNibData:[NSData dataWithContentsOfFile:@(argv[i])] bundle:nil];
  NSArray *objects;if(![nib instantiateWithOwner:NSApp topLevelObjects:&objects]) return 1;
  NSMenu *menu=NSApp.mainMenu;
  if(!menu) for(id o in objects) if([o isKindOfClass:NSMenu.class]) {menu=o;break;}
  NSMenuItem *item=FindConsole(menu);
  if(!item || ![item.keyEquivalent isEqualToString:@"0"] || item.keyEquivalentModifierMask!=NSEventModifierFlagCommand || item.target) return 2;
  Receiver *r=[[Receiver alloc] initWithContentRect:NSMakeRect(-20000,-20000,400,300) styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
  r.releasedWhenClosed=NO;
  NSApp.nextResponder=r;
  item.enabled=YES;
  NSEvent *e=[NSEvent keyEventWithType:NSEventTypeKeyDown location:NSZeroPoint modifierFlags:NSEventModifierFlagCommand timestamp:0 windowNumber:0 context:nil characters:@"0" charactersIgnoringModifiers:@"0" isARepeat:NO keyCode:29];
  if(![menu performKeyEquivalent:e] || r.calls!=1) return 3;
  NSApp.nextResponder=nil; [r close];
  printf("PASS %s: %s Command-0 dispatch\n",argv[i],item.title.UTF8String);
 }
}return 0;}
