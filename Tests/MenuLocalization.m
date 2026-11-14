#import "TestAppKitIsolation.h"
static void IgnoreOutlet(id self, SEL cmd, id value, NSString *key) {}
int main(int argc, char **argv) { @autoreleasepool {
    TSInstallAppKitIsolation(); [NSApplication sharedApplication];
    for (NSString *name in @[@"HelpDocuments", @"TSAppDelegate", @"TSDocumentController", @"TSMacroEditor", @"TSMacroMenuController", @"TSMovie", @"TSPreferences", @"TSSparkleController", @"TSStationery", @"TextFinder"]) {
        Class c = objc_allocateClassPair(NSObject.class, name.UTF8String, 0);
        class_addMethod(c, @selector(setValue:forUndefinedKey:), (IMP)IgnoreOutlet, "v@:@@");
        objc_registerClassPair(c);
    }
    NSNib *nib = [[NSNib alloc] initWithNibData:[NSData dataWithContentsOfFile:@(argv[1])] bundle:nil];
    NSArray *objects;
    if (![nib instantiateWithOwner:NSApp topLevelObjects:&objects]) return 2;
    NSMenu *main = NSApp.mainMenu;
    if (!main) for (id object in objects) if ([object isKindOfClass:NSMenu.class]) { main = object; break; }
    if (!main) return 3;
    NSArray *cases = [NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfFile:@(argv[2])] options:0 error:NULL];
    if (!cases.count) return 4;
    for (NSDictionary *entry in cases) {
        NSMenu *menu = main;
        for (NSString *title in entry[@"parents"]) menu = [menu itemWithTitle:title].submenu;
        BOOL found = [menu itemWithTitle:entry[@"title"]] != nil;
        if (found != [entry[@"found"] boolValue]) {
            fprintf(stderr, "FAIL: %s %s\n", argv[1], [entry[@"key"] UTF8String]); return 1;
        }
    }
    if (NSUserDefaults.standardUserDefaults != TSIsolatedAppKitDefaults) return 5;
    printf("PASS: %lu compiled menu lookups\n", cases.count);
    return 0;
} }
