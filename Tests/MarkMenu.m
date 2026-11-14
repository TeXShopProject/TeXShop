// Edit › Mark: the mark commands move from Source › Command Completion to Edit,
// after Find, keep their identifiers and shortcuts, gain Insert Mark with Note
// and How to Use Marks, and explain themselves in tooltips. Insert Mark with Note
// wraps the selection and can be undone. Nothing is shown on screen.
#import <Cocoa/Cocoa.h>
#import "TestAppKitIsolation.h"
#import "TSMarkMenu.h"
#define REQUIRE(...) do { if (!(__VA_ARGS__)) { fprintf(stderr,"FAIL %d: %s\n",__LINE__,#__VA_ARGS__); exit(1); } } while(0)
NSString *placeholderString = @"•", *startcommentString = @"•‹", *endcommentString = @"›";
@interface MarkOwner : NSObject @end
@implementation MarkOwner
- (void)setValue:(id)v forUndefinedKey:(NSString *)k {}
- (id)valueForUndefinedKey:(NSString *)k { return nil; }
@end
@interface UndoSource : NSObject <NSTextViewDelegate> @property (strong) NSUndoManager *manager; + (instancetype)sourceWith:(NSUndoManager *)m; @end
@implementation UndoSource
+ (instancetype)sourceWith:(NSUndoManager *)m { static NSMutableArray *keep; if (!keep) keep = [NSMutableArray array]; UndoSource *s = [self new]; s.manager = m; [keep addObject:s]; return s; }
- (NSUndoManager *)undoManagerForTextView:(NSTextView *)view { return self.manager; }
@end
@interface MarkTextView : NSTextView @end
@implementation MarkTextView
#include "PlaceComment.inc"
@end
static NSMenuItem *Find(NSMenu *menu, SEL action) {
    for (NSMenuItem *item in menu.itemArray) { if (item.action == action) return item; if (item.submenu) { NSMenuItem *f = Find(item.submenu, action); if (f) return f; } }
    return nil;
}
static NSString *Describe(NSMenu *menu) {
    NSMutableArray *parts = [NSMutableArray array];
    for (NSMenuItem *item in menu.itemArray) [parts addObject:item.isSeparatorItem ? @"-" : NSStringFromSelector(item.action) ?: @"?"];
    return [parts componentsJoinedByString:@" "];
}
int main(int argc, char **argv) { @autoreleasepool {
    TSInstallAppKitIsolation();
    [NSApplication sharedApplication];
    for (int i = 1; i < argc; i++) {
        NSNib *nib = [[NSNib alloc] initWithNibData:[NSData dataWithContentsOfFile:@(argv[i])] bundle:nil];
        NSArray *objects = nil; REQUIRE([nib instantiateWithOwner:[MarkOwner new] topLevelObjects:&objects]);
        NSMenu *main = nil;
        for (id object in objects) if ([object isKindOfClass:NSMenu.class] && [object numberOfItems] > 5) main = object;
        REQUIRE(main != nil);
        NSMutableDictionary *before = [NSMutableDictionary dictionary];
        for (NSString *name in @[@"placeBullet:", @"placeComment:", @"doNextBullet:", @"doPreviousBullet:", @"doNextBulletAndDelete:", @"doPreviousBulletAndDelete:"]) {
            NSMenuItem *item = Find(main, NSSelectorFromString(name)); REQUIRE(item != nil);
            before[name] = @[item, item.identifier ?: @"", item.keyEquivalent, @(item.keyEquivalentModifierMask)];
        }
        NSApp.mainMenu = main;
        [TSMarkMenu installInMenu:main];
        NSMenuItem *next = Find(main, @selector(doNextBullet:));
        NSMenu *marks = next.menu, *edit = marks.supermenu;
        REQUIRE(Find(edit, @selector(undo:)) != nil && edit.supermenu == main);
        REQUIRE(Find(main, @selector(changeAutoComplete:)).menu != marks.supermenu);
        NSInteger index = [edit indexOfItemWithSubmenu:marks], find = -1;
        for (NSInteger j = 0; j < edit.numberOfItems; j++) if ([edit itemAtIndex:j].submenu) { find = j; break; }
        REQUIRE(index == find + 1);
        REQUIRE([Describe(marks) isEqual:@"placeBullet: placeComment: - doNextBullet: doNextBulletAndDelete: doPreviousBullet: doPreviousBulletAndDelete: - showMarkHelp:"]);
        for (NSString *name in before) {
            NSArray *was = before[name]; NSMenuItem *item = Find(main, NSSelectorFromString(name));
            REQUIRE(item == was[0] && [item.identifier isEqual:was[1]] && [item.keyEquivalent isEqual:was[2]] && item.keyEquivalentModifierMask == [was[3] unsignedIntegerValue]);
            REQUIRE(item.toolTip.length > 10);
        }
        NSMenuItem *note = Find(main, @selector(placeComment:)), *help = Find(main, @selector(showMarkHelp:));
        REQUIRE([note.identifier isEqual:@"TSShortcut.placeComment:.0"] && note.title.length && note.toolTip.length > 10 && !note.isAlternate);
        REQUIRE(Find(main, @selector(doNextBulletAndDelete:)).isAlternate && Find(main, @selector(doPreviousBulletAndDelete:)).isAlternate);
        REQUIRE([help.identifier isEqual:@"TSShortcut.showMarkHelp:.0"] && help.target == [TSMarkMenu sharedInstance] && help.title.length);
        NSString *shape = Describe(main);
        [TSMarkMenu installInMenu:main];
        REQUIRE([Describe(main) isEqual:shape] && [Describe(marks) isEqual:@"placeBullet: placeComment: - doNextBullet: doNextBulletAndDelete: doPreviousBullet: doPreviousBulletAndDelete: - showMarkHelp:"]);
        NSString *guide = [TSMarkMenu markGuide];
        REQUIRE([guide containsString:@"•‹"] && [guide containsString:edit.title ?: @"?"] && [guide containsString:[edit itemAtIndex:index].title]);
        NSApp.mainMenu = nil;
        printf("PASS: %s Edit › Mark: %s\n", argv[i], Describe(marks).UTF8String);
    }
    // How to Use Marks: the help book's anchor in English; the English page with the section, as a link, in every
    // other language of the interface.
    if (getenv("MARK_HELP_BUNDLE")) {
        NSBundle *bundle = [NSBundle bundleWithPath:@(getenv("MARK_HELP_BUNDLE"))];
        REQUIRE(bundle);
        REQUIRE([TSMarkMenu markHelpPageForLocalization:@"en" inBundle:bundle] == nil);
        for (NSString *language in @[@"ja", @"ko", @"de", @"es", @"fr", @"it", @"nl", @"pt", @"pt-PT", @"ro", @"zh_CN"]) {
            NSURL *page = [TSMarkMenu markHelpPageForLocalization:language inBundle:bundle];
            REQUIRE(page.isFileURL && [page.fragment isEqual:@"marks"] && [page.path hasSuffix:@"/en.lproj/TeXShopHelp/pgs/basic_commandcompletion.htm"]);
            NSString *text = [NSString stringWithContentsOfURL:[NSURL fileURLWithPath:page.path] encoding:NSUTF8StringEncoding error:NULL]
                ?: [NSString stringWithContentsOfURL:[NSURL fileURLWithPath:page.path] encoding:NSISOLatin1StringEncoding error:NULL];
            REQUIRE([text containsString:@"name=\"marks\""]);
        }
        printf("PASS: How to Use Marks opens the help book in English, the English page in the 11 other languages\n");
    }
    // Insert Mark with Note.
    MarkTextView *view = [[MarkTextView alloc] initWithFrame:NSMakeRect(0, 0, 200, 100)];
    view.allowsUndo = YES;
    NSWindow *host = [[NSWindow alloc] initWithContentRect:NSMakeRect(0,0,200,100) styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:YES];
    host.contentView = view;
    view.string = @"ab"; view.selectedRange = NSMakeRange(1, 0);
    [view placeComment:nil];
    REQUIRE([view.string isEqual:@"a•‹›b"] && NSEqualRanges(view.selectedRange, NSMakeRange(3, 0)));
    view.string = @"x note y"; view.selectedRange = NSMakeRange(2, 4);
    [view placeComment:nil];
    REQUIRE([view.string isEqual:@"x •‹note› y"] && NSEqualRanges(view.selectedRange, NSMakeRange(9, 0)));
    // Undo, in a fresh view whose undo groups are closed by hand (no event loop).
    NSUndoManager *undo = [NSUndoManager new]; undo.groupsByEvent = NO;
    MarkTextView *fresh = [[MarkTextView alloc] initWithFrame:NSMakeRect(0, 0, 200, 100)];
    fresh.allowsUndo = YES; fresh.delegate = (id)[UndoSource sourceWith:undo];
    fresh.string = @"x note y"; fresh.selectedRange = NSMakeRange(2, 4);
    [undo beginUndoGrouping]; [fresh placeComment:nil]; [undo endUndoGrouping];
    REQUIRE([fresh.string isEqual:@"x •‹note› y"] && undo.canUndo);
    [undo undo];
    REQUIRE([fresh.string isEqual:@"x note y"]);
    puts("PASS: Insert Mark with Note inserts •‹› or wraps the selection, and undoes");
} return 0; }
