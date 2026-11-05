// Verify runtime Tags lookup in each compiled MainMenu.
#import <Cocoa/Cocoa.h>
#import <objc/runtime.h>
static void IgnoreOutlet(id self,SEL cmd,id value,NSString *key) {}
int main(int argc,char **argv){@autoreleasepool{
 [NSApplication sharedApplication];
 for(NSString *name in @[@"HelpDocuments",@"TSAppDelegate",@"TSAutoCompletionListEditor",@"TSDocumentController",@"TSMacroEditor",@"TSMacroMenuController",@"TSMovie",@"TSPreferences",@"TSSparkleController",@"TSStationery",@"TextFinder"]){
  Class c=objc_allocateClassPair(NSObject.class,name.UTF8String,0);
  class_addMethod(c,@selector(setValue:forUndefinedKey:),(IMP)IgnoreOutlet,"v@:@@");objc_registerClassPair(c);}
 NSNib *nib=[[NSNib alloc] initWithNibData:[NSData dataWithContentsOfFile:@(argv[1])] bundle:nil];
 NSArray *objs; if(![nib instantiateWithOwner:NSApp topLevelObjects:&objs]) return 1;
 NSMenu *m=NSApp.mainMenu; if(!m) for(id o in objs) if([o isKindOfClass:NSMenu.class]){m=o;break;}
 NSString *t=@(argv[2]); NSMenuItem *it=[m itemWithTitle:t];
 NSMutableArray *a=[NSMutableArray array]; for(NSMenuItem *i in m.itemArray)[a addObject:i.title];
 printf("%s\t%s\tfound=%s\tsubmenu=%s\t[%s]\n",argv[1],argv[2],it?"YES":"NO",it.submenu.title.UTF8String?:"-",[[a componentsJoinedByString:@","] UTF8String]);
 return it?0:4;}}
