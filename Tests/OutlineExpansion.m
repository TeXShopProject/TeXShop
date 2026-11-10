// Checks that open entries of the Preview drawer's PDF outline stay open when
// the outline is rebuilt, as after typesetting. Nothing is shown on screen:
// the outline view lives in a scroll view that is never put in a window.
#import <Cocoa/Cocoa.h>
#import <Quartz/Quartz.h>
#import <objc/runtime.h>
#import "TSOutlineExpansion.h"
#import "TestAppKitIsolation.h"

static int failures = 0;
#define CHECK(cond, ...) do { if (cond) { printf("ok   "); } else { printf("FAIL "); failures++; } printf(__VA_ARGS__); printf("\n"); } while (0)

// Option-click is simulated by answering +[NSEvent modifierFlags].
static NSEventModifierFlags heldModifiers = 0;
@implementation NSEvent (OutlineExpansionTest)
+ (NSEventModifierFlags)test_modifierFlags { return heldModifiers; }
@end

// The same data source methods as MyPDFKitView.
@interface OutlineSource : NSObject <NSOutlineViewDataSource>
@property (strong) PDFOutline *root;
@end

@implementation OutlineSource
- (NSInteger)outlineView:(NSOutlineView *)v numberOfChildrenOfItem:(id)item
{ return item ? [(PDFOutline *)item numberOfChildren] : (NSInteger)[self.root numberOfChildren]; }
- (id)outlineView:(NSOutlineView *)v child:(NSInteger)i ofItem:(id)item
{ return item ? [(PDFOutline *)item childAtIndex:i] : [self.root childAtIndex:i]; }
- (BOOL)outlineView:(NSOutlineView *)v isItemExpandable:(id)item
{ return [(PDFOutline *)item numberOfChildren] > 0; }
- (id)outlineView:(NSOutlineView *)v objectValueForTableColumn:(NSTableColumn *)c byItem:(id)item
{ return [(PDFOutline *)item label]; }
@end

// A tree from nested arrays: @[@"Title", @[children...]] or @"Title".
static PDFOutline *Entry(id spec)
{
    PDFOutline *entry = [[PDFOutline alloc] init];
    if ([spec isKindOfClass:[NSString class]]) { entry.label = spec; return entry; }
    entry.label = spec[0];
    NSArray *children = [spec count] > 1 ? spec[1] : @[];
    for (NSUInteger i = 0; i < children.count; i++)
        [entry insertChild:Entry(children[i]) atIndex:i];
    return entry;
}

static PDFOutline *Tree(NSArray *top) { return Entry(@[@"", top]); }

static NSArray *SampleTree(BOOL preface)
{
    NSMutableArray *top = [NSMutableArray array];
    if (preface) [top addObject:@"Preface"];
    [top addObjectsFromArray:@[
        @[@"1 Groups", @[@"1.1 Definitions", @[@"Exercises", @[@"Easy", @"Hard"]]]],
        @[@"2 Rings", @[@[@"2.1 Ideals", @[@"Prime ideals", @"Maximal ideals"]], @"2.2 Quotients", @[@"Exercises", @[@"Easy", @"Hard"]]]],
        @[@"3 Fields", @[@[@"Appendix", @[@"Tables"]], @[@"Appendix", @[@"Proofs"]]]],
    ]];
    return top;
}

// Labels of the visible rows, indented by level.
static NSArray<NSString *> *Rows(NSOutlineView *v)
{
    NSMutableArray *rows = [NSMutableArray array];
    for (NSInteger r = 0; r < v.numberOfRows; r++) {
        id item = [v itemAtRow:r];
        [rows addObject:[[@"" stringByPaddingToLength:2 * [v levelForItem:item] withString:@" " startingAtIndex:0]
                          stringByAppendingString:[(PDFOutline *)item label] ?: @""]];
    }
    return rows;
}

static id Find(NSOutlineView *v, NSString *label, NSInteger nth)
{
    for (NSInteger r = 0; r < v.numberOfRows; r++) {
        id item = [v itemAtRow:r];
        if ([[(PDFOutline *)item label] isEqualToString:label] && nth-- == 0) return item;
    }
    return nil;
}

// The user clicks a disclosure triangle.
static void Toggle(NSOutlineView *v, NSString *label, NSInteger nth, BOOL open)
{
    id item = Find(v, label, nth);
    if (item == nil) { printf("FAIL no row %s\n", label.UTF8String); failures++; return; }
    if (open) [v expandItem:item]; else [v collapseItem:item];
}

int main(int argc, char **argv)
{
    @autoreleasepool {
        TSInstallAppKitIsolation();
        [NSApplication sharedApplication];
        method_exchangeImplementations(class_getClassMethod([NSEvent class], @selector(modifierFlags)),
                                       class_getClassMethod([NSEvent class], @selector(test_modifierFlags)));
        NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(0, 0, 240, 120)];
        NSOutlineView *view = [[NSOutlineView alloc] initWithFrame:scroll.bounds];
        NSTableColumn *column = [[NSTableColumn alloc] initWithIdentifier:@"label"];
        column.width = 220;
        [view addTableColumn:column];
        view.outlineTableColumn = column;
        view.headerView = nil;
        scroll.documentView = view;
        // A window that is never ordered front, so that the clip view behaves as in TeXShop.
        NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 240, 120) styleMask:NSWindowStyleMaskBorderless
                                                         backing:NSBackingStoreBuffered defer:NO];
        window.releasedWhenClosed = NO;
        window.contentView = scroll;
        OutlineSource *source = [OutlineSource new];
        view.dataSource = source;
        TSOutlineExpansion *expansion = [[TSOutlineExpansion alloc] initWithOutlineView:view];

        // 1. A rebuilt outline with the same entries looks the same.
        source.root = Tree(SampleTree(NO));
        [expansion reloadOutline];
        CHECK(Rows(view).count == 3, "starts collapsed: %s", [Rows(view) componentsJoinedByString:@" | "].UTF8String);
        Toggle(view, @"2 Rings", 0, YES);
        Toggle(view, @"2.1 Ideals", 0, YES);
        Toggle(view, @"Exercises", 0, YES);
        NSArray *before = Rows(view);
        id oldItem = [view itemAtRow:1];
        source.root = Tree(SampleTree(NO));
        [expansion reloadOutline];
        CHECK([Rows(view) isEqual:before], "same rows after rebuilding: %s", [Rows(view) componentsJoinedByString:@" | "].UTF8String);
        CHECK([view itemAtRow:1] != oldItem, "the rows show the new outline's items");

        // 2. Of two entries with the same title, only the one that was open opens.
        Toggle(view, @"1 Groups", 0, YES);
        Toggle(view, @"1.1 Definitions", 0, YES);
        NSInteger exercisesInGroups = [view rowForItem:Find(view, @"Exercises", 0)];
        CHECK(![view isItemExpanded:[view itemAtRow:exercisesInGroups]], "Exercises under 1.1 is still closed");
        source.root = Tree(SampleTree(NO));
        [expansion reloadOutline];
        CHECK(![view isItemExpanded:Find(view, @"Exercises", 0)] && [view isItemExpanded:Find(view, @"Exercises", 1)],
              "after rebuilding, only the second Exercises is open");

        // 2b. The same for two entries with the same title under one entry.
        Toggle(view, @"3 Fields", 0, YES);
        Toggle(view, @"Appendix", 1, YES);
        source.root = Tree(SampleTree(NO));
        [expansion reloadOutline];
        CHECK(![view isItemExpanded:Find(view, @"Appendix", 0)] && [view isItemExpanded:Find(view, @"Appendix", 1)] &&
              Find(view, @"Proofs", 0) != nil && Find(view, @"Tables", 0) == nil,
              "of the two Appendix entries under 3 Fields, only the second is open");

        // 3. An entry added above does not change which entries open.
        NSArray *withoutPreface = Rows(view);
        source.root = Tree(SampleTree(YES));
        [expansion reloadOutline];
        NSArray *rows = Rows(view);
        CHECK([rows.firstObject isEqual:@"Preface"] &&
              [[rows subarrayWithRange:NSMakeRange(1, rows.count - 1)] isEqual:withoutPreface],
              "an added Preface leaves the open entries open");

        // 4. A closed entry stays closed.
        Toggle(view, @"1 Groups", 0, NO);
        source.root = Tree(SampleTree(YES));
        [expansion reloadOutline];
        CHECK(![view isItemExpanded:Find(view, @"1 Groups", 0)], "1 Groups stays closed");

        // 5. Entries open inside a closed entry open again with it, as before rebuilding.
        Toggle(view, @"2 Rings", 0, NO);
        source.root = Tree(SampleTree(YES));
        [expansion reloadOutline];
        CHECK(Find(view, @"2.1 Ideals", 0) == nil, "2 Rings stays closed, hiding 2.1");
        Toggle(view, @"2 Rings", 0, YES);
        CHECK([view isItemExpanded:Find(view, @"2.1 Ideals", 0)] && [view isItemExpanded:Find(view, @"Exercises", 0)],
              "opening 2 Rings again shows 2.1 Ideals and Exercises open");

        // 6. Option-click closes the entries inside too.
        heldModifiers = NSEventModifierFlagOption;
        [view collapseItem:Find(view, @"2 Rings", 0) collapseChildren:YES];
        heldModifiers = 0;
        Toggle(view, @"2 Rings", 0, YES);
        CHECK(![view isItemExpanded:Find(view, @"2.1 Ideals", 0)] && ![view isItemExpanded:Find(view, @"Exercises", 0)],
              "after Option-closing 2 Rings, opening it shows 2.1 Ideals and Exercises closed");
        source.root = Tree(SampleTree(YES));
        [expansion reloadOutline];
        CHECK(![view isItemExpanded:Find(view, @"2.1 Ideals", 0)], "and they stay closed after rebuilding");
        Toggle(view, @"2.1 Ideals", 0, YES);
        Toggle(view, @"Exercises", 0, YES);

        // 7. A document without an outline, then the outline again.
        before = Rows(view);
        source.root = nil;
        [expansion reloadOutline];
        CHECK(view.numberOfRows == 0, "no outline, no rows");
        source.root = Tree(SampleTree(YES));
        [expansion reloadOutline];
        CHECK([Rows(view) isEqual:before], "the outline comes back with the same entries open");

        // 8. The scroll position is kept.
        NSClipView *clip = scroll.contentView;
        // Scrolled to the end, which a collapsed outline cannot reach.
        [clip scrollToPoint:NSMakePoint(0, NSHeight(view.frame) - NSHeight(clip.bounds))];
        [scroll reflectScrolledClipView:clip];
        CGFloat y = clip.bounds.origin.y;
        source.root = Tree(SampleTree(YES));
        [expansion reloadOutline];
        CHECK(y > 0 && fabs(clip.bounds.origin.y - y) < 0.5, "scroll position %.1f kept (now %.1f)", y, clip.bounds.origin.y);

        // 9. A real PDF outline, read again from the file as after typesetting.
        if (argc > 1) {
            NSURL *url = [NSURL fileURLWithPath:@(argv[1])];
            PDFDocument *first = [[PDFDocument alloc] initWithURL:url];
            source.root = first.outlineRoot;
            [expansion reloadOutline];
            NSInteger top = view.numberOfRows;
            id chapter = nil;
            for (NSInteger r = top - 1; r >= 0 && chapter == nil; r--)
                if ([view isExpandable:[view itemAtRow:r]]) chapter = [view itemAtRow:r];
            [view expandItem:chapter];
            for (NSInteger r = [view rowForItem:chapter] + 1; r < view.numberOfRows; r++)
                if ([view isExpandable:[view itemAtRow:r]]) { [view expandItem:[view itemAtRow:r]]; break; }
            before = Rows(view);
            PDFDocument *second = [[PDFDocument alloc] initWithURL:url];
            source.root = second.outlineRoot;
            first = nil;
            [expansion reloadOutline];
            CHECK(before.count > top && [Rows(view) isEqual:before],
                  "%s: %ld rows with an open chapter and section, the same after reading the PDF again",
                  url.lastPathComponent.UTF8String, (long)before.count);
        }
    }
    printf(failures ? "%d failed\n" : "all passed\n", failures);
    return failures ? 1 : 0;
}
