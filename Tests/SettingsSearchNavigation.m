// SPDX-License-Identifier: GPL-2.0-or-later
#import "TestAppKitIsolation.h"
#import "TSSettingsWindowController.h"

static void Check(BOOL value, NSString *message) {
    if (!value) { fprintf(stderr, "FAIL: %s\n", message.UTF8String); exit(1); }
}
@interface TSSettingsWindowController (Inspection)
@property (readonly) NSTableView *categoryTable;
@property (readonly) NSSegmentedControl *navigationControl;
@end
NSString *TSSettingsSelectedCategoryKey = @"TSSettingsSelectedCategory";
static NSString *nibPath;
@interface SearchPaneView:NSView
@property NSRect lastSearchScroll;
@end
@implementation SearchPaneView
- (BOOL)scrollRectToVisible:(NSRect)rect {self.lastSearchScroll=rect;return [super scrollRectToVisible:rect];}
@end
@interface SearchController : TSSettingsWindowController @end
@implementation SearchController
- (void)loadWindow {
    NSNib *nib = [[NSNib alloc] initWithNibData:[NSData dataWithContentsOfFile:nibPath] bundle:nil];
    NSArray *objects;
    Check([nib instantiateWithOwner:self topLevelObjects:&objects], @"Production shell loads");
}
@end
@interface SearchDelegate : NSObject<TSSettingsWindowDelegate>
@property BOOL valid;
@end
@implementation SearchDelegate
- (BOOL)settingsMayChangeCategory { return self.valid; }
- (void)settingsChangeFont:(NSFontManager *)sender {}
@end
@interface SearchBundle : NSBundle @end
@implementation SearchBundle
- (NSString *)localizedStringForKey:(NSString *)key value:(NSString *)value table:(NSString *)table {
    if (![table isEqual:@"SettingsCategories"]) return @"";
    return @{@"general":@"General", @"editor":@"Editor", @"console":@"Console",
             @"catalog.general.0.0.title":@"Alpha setting", @"catalog.general.0.1.title":@"Beta setting",
             @"catalog.editor.0.0.title":@"Gamma setting"}[key] ?: @"";
}
@end
static void Choose(SearchController *controller, NSString *title) {
    NSUInteger index = [controller.searchResults indexOfObjectPassingTest:^BOOL(TSSettingsSearchResult *result, NSUInteger idx, BOOL *stop) { return [result.title isEqual:title]; }];
    Check(index != NSNotFound, @"Named item exists");
    [controller.categoryTable selectRowIndexes:[NSIndexSet indexSetWithIndex:index] byExtendingSelection:NO];
}
int main(int argc, char **argv) { @autoreleasepool {
    TSInstallAppKitIsolation(); [NSApplication sharedApplication];
    nibPath = [NSString stringWithUTF8String:argv[1]];
    TSMemoryDefaults *defaults = [TSMemoryDefaults new];
    SearchController *controller = [[SearchController alloc] initWithDefaults:defaults];
    SearchDelegate *delegate = [SearchDelegate new]; delegate.valid = YES; controller.settingsDelegate = delegate;
    NSMutableDictionary *panes = [NSMutableDictionary dictionary];
    for (NSString *category in controller.categoryIdentifiers) {
        NSViewController *pane = [NSViewController new]; pane.title = category;
        pane.view = [[SearchPaneView alloc] initWithFrame:NSMakeRect(0,0,700,600)];
        NSArray *ids = [category isEqual:@"general"] ? @[@"row.catalog.general.0.0",@"row.catalog.general.0.1"] : ([category isEqual:@"editor"] ? @[@"row.catalog.editor.0.0"] : @[]);
        for (NSUInteger i=0;i<ids.count;i++) {
            NSView *row = [[NSView alloc] initWithFrame:NSMakeRect(12,100+60*i,600,38)]; row.identifier = ids[i]; [pane.view addSubview:row];
        }
        panes[category] = pane;
    }
    NSView *footer = [NSView new]; footer.hidden = YES;
    [controller hostPaneControllers:panes footer:footer]; controller.searchBundle = [SearchBundle new]; [controller beginSession];
    [controller selectCategoryIdentifier:@"editor"]; [controller selectCategoryIdentifier:@"console"]; [controller goBack:nil];
    NSUInteger count = controller.history.count;
    [controller setSettingsSearchQuery:@"setting"];
    Check([controller.history.currentIdentifier isEqual:@"editor"] && controller.history.count==count, @"Typing does not move the pane or add history");
    Check(controller.searchResults.count==3, @"Two settings in one category produce separate results");
    Check([controller.navigationControl isEnabledForSegment:0] && [controller.navigationControl isEnabledForSegment:1], @"Search preserves both directions of existing history");
    Check([[controller valueForKey:@"searchHighlights"] count]==0, @"Typing alone does not select an arbitrary result");
    Choose(controller,@"Alpha setting");
    Check([controller.history.currentIdentifier isEqual:@"general"] && controller.history.forwardIdentifier==nil, @"Result visit appends and discards old forward branch");
    Check([[defaults stringForKey:@"TSSettingsSelectedCategory"] isEqual:@"general"], @"Search navigation persists its current category");
    NSArray<NSView *> *highlights = [controller valueForKey:@"searchHighlights"];
    Check(highlights.count==1 && [highlights.firstObject.superview.identifier isEqual:@"row.catalog.general.0.0"], @"Only the selected setting is highlighted");
    count=controller.history.count; Choose(controller,@"Beta setting");
    highlights=[controller valueForKey:@"searchHighlights"];
    Check(controller.history.count==count && highlights.count==1 && [highlights.firstObject.superview.identifier isEqual:@"row.catalog.general.0.1"], @"A second result in the same pane changes the target without duplicating category history");
    [controller goBack:nil];
    Check([controller.history.currentIdentifier isEqual:@"editor"] && [controller.searchQuery isEqual:@"setting"], @"Back navigates while keeping search active");
    [controller goForward:nil];
    Check([controller.history.currentIdentifier isEqual:@"general"] && [controller.searchQuery isEqual:@"setting"], @"Forward navigates while keeping search active");
    Check(![controller.navigationControl isEnabledForSegment:1], @"Search cannot enable unavailable forward navigation");
    delegate.valid=NO; [controller goBack:nil];
    Check([controller.history.currentIdentifier isEqual:@"general"], @"Invalid edited values still block navigation");
    Check([controller setSettingsSearchQuery:@""] && [controller.history.currentIdentifier isEqual:@"general"] && controller.history.count==count, @"Clearing search stays in the current pane and does not require a navigation commit");
    Check([[controller valueForKey:@"searchHighlights"] count]==0, @"Clear removes highlighting");
    delegate.valid=YES; [controller goBack:nil];
    Check([controller.history.currentIdentifier isEqual:@"editor"], @"Search visits remain in normal history after clearing");
    [controller setSettingsSearchQuery:@"setting"];
    NSTableCellView *cell=(id)[(id<NSTableViewDelegate>)controller tableView:controller.categoryTable viewForTableColumn:nil row:0];
    Check([cell.toolTip containsString:controller.searchResults[0].title] && [cell.toolTip containsString:controller.searchResults[0].category], @"Result exposes its item and category names");
    [controller setSettingsSearchQuery:@"General"];
    SearchPaneView *general=(SearchPaneView *)[panes[@"general"] view];general.lastSearchScroll=NSMakeRect(-1,-1,0,0);
    Choose(controller,@"General");
    Check(NSEqualRects(general.lastSearchScroll,NSMakeRect(0,MAX(0,NSHeight(general.bounds)-1),1,1)) && [[controller valueForKey:@"searchHighlights"] count]==0,@"Category doorway scrolls to pane top without item highlights");
    Check(!controller.window.visible, @"No settings window was ordered");
    puts("PASS: item results, selected-row highlighting, normal history, clear, persistence and validation");
} return 0; }
