// SPDX-License-Identifier: GPL-2.0-or-later
// The window of the TeX sources of a root (Issue #45, spec §2.7): the model (collecting, generations, the pause,
// stopping, files and items on or off), the window (modes, shared strings, status, Replace All, the question mark,
// files not read), the tree and the list (checks, marks, highlights, VoiceOver labels), the entry rules, the panel's
// and the Multiple Replace window's items, and the main thread kept free. Built by Tests/run-texroot-search-window.py;
// nothing is shown and the defaults stay in memory.
#import "TestAppKitIsolation.h"
#import "TSTeXRootSearchWindowController.h"
#import "TSTeXRootEntryRules.h"
#import "TSAdvancedFindPanelController.h"
#import "TSMultipleReplaceWindowController.h"
#import "TSRegexMultipleReplace.h"
#import "TSRegexReplacementRule.h"
#import <sys/stat.h>

static int failures;
static void Check(BOOL ok, NSString *name)
{
    if (!ok) {
        printf("FAIL %s\n", name.UTF8String);
        failures++;
    }
}

static BOOL Spin(BOOL (^done)(void), NSTimeInterval timeout)
{
    NSDate *limit = [NSDate dateWithTimeIntervalSinceNow:timeout];
    while (!done() && limit.timeIntervalSinceNow > 0)
        [NSRunLoop.currentRunLoop runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.005]];
    return done();
}

#pragma mark Fixture

static NSString *Folder;
static NSString *Write(NSString *relative, NSString *text)
{
    NSString *path = [Folder stringByAppendingPathComponent:relative];
    [NSFileManager.defaultManager createDirectoryAtPath:path.stringByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:NULL];
    [text writeToFile:path atomically:NO encoding:NSUTF8StringEncoding error:NULL];
    return path;
}

static TSTeXRootSourceCodec *Codec(void)
{
    return [[TSTeXRootSourceCodec alloc] initWithEncodingForData:^NSStringEncoding(NSData *data, NSURL *url) { return NSUTF8StringEncoding; }
                                                  textForEditing:^NSString *(NSString *text, NSStringEncoding encoding) { return text; }
                                                   textForSaving:^NSString *(NSString *text, NSStringEncoding encoding) { return text; }];
}

/// The environment of the tests: delayed blocks wait in `Pending` until RunPending(); open documents are texts by
/// relative path in `OpenTexts` (and read-only ones in `ReadOnly`).
static NSMutableArray<dispatch_block_t> *Pending;
static NSMutableDictionary<NSString *, NSString *> *OpenTexts;
static NSMutableSet<NSString *> *ReadOnly;
static NSMutableArray<NSArray<NSString *> *> *SourceRequests;
static BOOL DelayRunsAtOnce;
/// What the environment says of the open documents (which are open, on which files).
static NSString *DocumentsSignature = @"start";
/// A slow file system while the collector is prepared (the identities of the open documents' files).
static useconds_t PrepareDelay;
static BOOL PreparedOnMain;

static void RunPending(void)
{
    NSArray<dispatch_block_t> *blocks = [Pending copy];
    [Pending removeAllObjects];
    for (dispatch_block_t block in blocks)
        block();
}

static TSTeXRootSearchEnvironment *Environment(void)
{
    TSTeXRootSearchEnvironment *environment = [TSTeXRootSearchEnvironment new];
    environment.codec = Codec();
    environment.collectorForRoot = ^TSTeXRootProjectCollector *(NSURL *rootURL) {
        TSTeXRootProjectCollector *collector = [[TSTeXRootProjectCollector alloc] initWithRootURL:rootURL codec:Codec() allowsSourceDoc:NO jobNameToken:@"\\jobname"];
        NSMutableDictionary *texts = [NSMutableDictionary dictionary];
        for (NSString *relative in OpenTexts) {
            id identifier = nil;
            [[NSURL fileURLWithPath:[Folder stringByAppendingPathComponent:relative]] getResourceValue:&identifier forKey:NSURLFileResourceIdentifierKey error:NULL];
            if (identifier)
                texts[identifier] = OpenTexts[relative];
        }
        collector.openDocumentTexts = texts;
        return collector;
    };
    environment.sourcesForFiles = ^NSArray<TSTeXRootSearchSource *> *(NSArray<TSTeXRootProjectFile *> *files) {
        NSMutableArray *sources = [NSMutableArray array], *names = [NSMutableArray array];
        for (TSTeXRootProjectFile *file in files) {
            [names addObject:file.relativePath];
            NSString *open = OpenTexts[file.relativePath];
            [sources addObject:open ? [[TSTeXRootSearchSource alloc] initWithFile:file openDocumentText:open lineEnding:@"\n"
                                                                searchOnlyReason:[ReadOnly containsObject:file.relativePath] ? TSTeXRootSearchOnlyReasonNotEditable : TSTeXRootSearchOnlyReasonNone]
                                    : [[TSTeXRootSearchSource alloc] initWithFile:file]];
        }
        [SourceRequests addObject:names];
        return sources;
    };
    environment.documentsSignature = ^id<NSObject> { return [DocumentsSignature copy]; };
    environment.prepareCollector = ^(TSTeXRootProjectCollector *collector) {
        if (NSThread.isMainThread)
            PreparedOnMain = YES;
        if (PrepareDelay)
            usleep(PrepareDelay);
    };
    environment.performAfterDelay = ^(NSTimeInterval delay, dispatch_block_t block) {
        if (DelayRunsAtOnce)
            dispatch_async(dispatch_get_main_queue(), block);
        else
            [Pending addObject:block];
    };
    return environment;
}

static NSURL *RootURL(void) { return [NSURL fileURLWithPath:[Folder stringByAppendingPathComponent:@"thesis.tex"]]; }

static void MakeProject(void)
{
    Folder = [[NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString] stringByResolvingSymlinksInPath];
    NSString *head = @"% !TEX root = ../thesis.tex\n";
    Write(@"thesis.tex", @"\\documentclass{book}\n% TODO check eq:main numbering\n\\input{chapters/one}\n");
    Write(@"chapters/one.tex", [head stringByAppendingString:@"\\begin{equation}\\label{eq:main}\nwhich proves \\eqref{eq:main} for all $t$.\n% old: \\label{eq:main}\n"]);
    Write(@"chapters/two.tex", [head stringByAppendingString:@"By \\eqref{eq:main} and Lemma~\\ref{lem:a},\n"]);
    Write(@"chapters/three.tex", [head stringByAppendingString:@"nothing here\n"]);
    Write(@"auxiliary/conventions.tex", [head stringByAppendingString:@"see \\eqref{eq:main}.\n"]);
    Write(@"other.tex", @"% !TEX root = another.tex\neq:main\n");
    NSString *locked = Write(@"chapters/locked.tex", [head stringByAppendingString:@"eq:main\n"]);
    chmod(locked.fileSystemRepresentation, 0);
}

static TSTeXRootSearchModel *OpenModel(TSTeXRootSearchMode mode, NSString *find, NSString *replace)
{
    TSTeXRootSearchModel *model = [[TSTeXRootSearchModel alloc] initWithRootURL:RootURL() environment:Environment()];
    [model setMode:mode findString:find replaceString:replace options:0 syntax:TSRegexReplacementSyntaxICU multipleReplace:nil];
    [model collect];
    Spin(^BOOL { return model.activity == TSTeXRootSearchActivityIdle; }, 30);
    return model;
}

static TSTeXRootProjectFile *FileNamed(TSTeXRootSearchModel *model, NSString *relative)
{
    for (TSTeXRootProjectFile *file in model.project.files)
        if ([file.relativePath isEqualToString:relative])
            return file;
    return nil;
}

static TSTeXRootSearchFileResult *ResultNamed(TSTeXRootSearchModel *model, NSString *relative)
{
    for (TSTeXRootSearchFileResult *file in model.results)
        if ([file.source.file.relativePath isEqualToString:relative])
            return file;
    return nil;
}

#pragma mark Model

static void TestModel(void)
{
    TSTeXRootSearchModel *model = OpenModel(TSTeXRootSearchModeFind, @"eq:main", @"eq:central");
    Check(model.project.files.count == 5, [NSString stringWithFormat:@"collected %lu files", (unsigned long)model.project.files.count]);
    Check(model.project.unreadableItems.count == 1, @"the locked file is listed as not read");
    Check(model.numberOfItems == 6 && model.results.count == 4 && [model.results.firstObject.source.file.relativePath isEqualToString:@"thesis.tex"],
          [NSString stringWithFormat:@"find mode: %lu items in %lu files", (unsigned long)model.numberOfItems, (unsigned long)model.results.count]);
    Check(model.resultGeneration == model.generation && !model.canReplaceAll, @"find mode never replaces");

    // A change: the generation moves at once, Replace All waits for the pause and the search.
    model.mode = TSTeXRootSearchModeReplace;
    Check(model.activity == TSTeXRootSearchActivityWaiting && model.resultGeneration != model.generation && !model.canReplaceAll && Pending.count == 1,
          @"a change waits for the pause, and Replace All cannot be pressed meanwhile");
    RunPending();
    Spin(^BOOL { return model.activity == TSTeXRootSearchActivityIdle; }, 30);
    Check(model.canReplaceAll && model.numberOfIncludedItems == 6, @"after the search Replace All can be pressed");
    TSTeXRootSearchFileResult *one = ResultNamed(model, @"chapters/one.tex");
    [model setItems:@[one.items[2]] inFile:one included:NO];
    Check(model.numberOfIncludedItems == 5 && model.numberOfFilesWithIncludedItems == 4 && model.canReplaceAll && ![model isItemIncluded:one.items[2] inFile:one],
          @"an item turned off: still the list of the conditions");

    // A late result is dropped: the search ends and its result waits on the main queue while the conditions change.
    [model searchNow];
    usleep(300000); // the background search is done; its result is queued, not yet taken
    model.replaceString = @"eq:other";
    Spin(^BOOL { return NO; }, 0.2);
    Check(model.activity == TSTeXRootSearchActivityWaiting && model.resultGeneration != model.generation && !model.canReplaceAll,
          @"the result of a search that ended before a change is dropped: Replace All cannot be pressed");
    RunPending();
    Spin(^BOOL { return model.activity == TSTeXRootSearchActivityIdle; }, 30);
    TSTeXRootSearchFileResult *oneAgain = ResultNamed(model, @"chapters/one.tex");
    Check([oneAgain.items.firstObject.replacement isEqualToString:@"eq:other"] && model.numberOfIncludedItems == 6 && model.canReplaceAll,
          @"new conditions: every item is on again, with the new replacement");
    // Items turned on or off while a search runs: the search still gives the list.
    [model setItems:@[oneAgain.items[1]] inFile:oneAgain included:NO];
    model.options = TSRegexFindIgnoreCase; // the same matches and replacements: the item would stay off if not reset
    RunPending();
    Check(model.activity == TSTeXRootSearchActivityComputing, @"searching for the new option");
    [model setItems:@[ResultNamed(model, @"chapters/two.tex").items[0]] inFile:ResultNamed(model, @"chapters/two.tex") included:NO];
    Spin(^BOOL { return model.activity == TSTeXRootSearchActivityIdle; }, 30);
    oneAgain = ResultNamed(model, @"chapters/one.tex");
    Check(model.activity == TSTeXRootSearchActivityIdle && model.resultGeneration == model.generation && [model isItemIncluded:oneAgain.items[1] inFile:oneAgain],
          @"a check changed while searching does not keep the search from ending, and a new condition turned every item on again");
    model.options = 0;
    RunPending();
    Spin(^BOOL { return model.activity == TSTeXRootSearchActivityIdle; }, 30);

    // Files off and on; the items stay off when only the tree changes.
    [model setItems:@[oneAgain.items[0]] inFile:oneAgain included:NO];
    TSTeXRootProjectFile *two = FileNamed(model, @"chapters/two.tex");
    [SourceRequests removeAllObjects];
    [model setFiles:@[two] included:NO];
    Check(!ResultNamed(model, @"chapters/two.tex") && model.resultGeneration == model.generation && model.activity == TSTeXRootSearchActivityIdle && SourceRequests.count == 0,
          @"a file turned off leaves the list at once, without a search");
    [model setFiles:@[two] included:YES];
    Spin(^BOOL { return model.activity == TSTeXRootSearchActivityIdle; }, 30);
    Check(ResultNamed(model, @"chapters/two.tex") && [SourceRequests.lastObject isEqual:@[@"chapters/two.tex"]] && model.numberOfIncludedItems == 5,
          [NSString stringWithFormat:@"a file turned on is searched alone (%@), and the item off stays off", SourceRequests]);

    // Collecting again: files off stay off.
    [model setFiles:@[FileNamed(model, @"auxiliary/conventions.tex")] included:NO];
    [model collect];
    Spin(^BOOL { return model.activity == TSTeXRootSearchActivityIdle; }, 30);
    Check(![model isFileIncluded:FileNamed(model, @"auxiliary/conventions.tex")] && !ResultNamed(model, @"auxiliary/conventions.tex") && model.numberOfIncludedFiles == 4,
          @"after collecting again a file off stays off");
    Check(![model isItemIncluded:ResultNamed(model, @"chapters/one.tex").items[0] inFile:ResultNamed(model, @"chapters/one.tex")],
          @"after collecting again an item off stays off");
    [model setFiles:model.project.files included:YES];
    Spin(^BOOL { return model.activity == TSTeXRootSearchActivityIdle; }, 30);

    // An open document: its text on screen is searched; an edit searches it alone again, after the pause.
    OpenTexts[@"chapters/two.tex"] = @"% !TEX root = ../thesis.tex\neq:main eq:main\n";
    [model documentsDidChange];
    Spin(^BOOL { return model.activity == TSTeXRootSearchActivityIdle; }, 30);
    TSTeXRootSearchFileResult *open = ResultNamed(model, @"chapters/two.tex");
    Check(open.source.isOpenDocument && open.items.count == 2, @"an open document is searched in its text on screen");
    [model setItems:@[open.items[1]] inFile:open included:NO];
    OpenTexts[@"chapters/two.tex"] = @"% !TEX root = ../thesis.tex\neq:main eq:main\nadded eq:main\n";
    [SourceRequests removeAllObjects];
    [model textDidChangeForFileWithIdentifier:open.source.file.identifier];
    Check(model.activity == TSTeXRootSearchActivityWaiting && !model.canReplaceAll, @"an edit waits for the pause");
    RunPending();
    Spin(^BOOL { return model.activity == TSTeXRootSearchActivityIdle; }, 30);
    TSTeXRootSearchFileResult *edited = ResultNamed(model, @"chapters/two.tex");
    Check([SourceRequests isEqual:@[@[@"chapters/two.tex"]]] && edited.items.count == 3 && ![model isItemIncluded:edited.items[1] inFile:edited]
          && [model isItemIncluded:edited.items[2] inFile:edited], @"only the edited document is searched again; the item off on an unchanged line stays off");
    ReadOnly = [NSMutableSet setWithObject:@"chapters/two.tex"];
    [model documentsDidChange];
    Spin(^BOOL { return model.activity == TSTeXRootSearchActivityIdle; }, 30);
    edited = ResultNamed(model, @"chapters/two.tex");
    Check(edited.searchOnlyReason == TSTeXRootSearchOnlyReasonNotEditable && ![model isItemIncluded:edited.items[0] inFile:edited]
          && [model searchOnlyReasonOfFile:edited.source.file] == TSTeXRootSearchOnlyReasonNotEditable, @"a read-only document is search only");
    [ReadOnly removeAllObjects];
    [OpenTexts removeAllObjects];

    // Errors and the limit.
    model.options = TSRegexFindRegularExpression;
    model.findString = @"(";
    RunPending();
    Spin(^BOOL { return model.activity == TSTeXRootSearchActivityIdle; }, 30);
    Check(model.queryError.code == TSRegexFindErrorInvalidPattern && model.results.count == 0 && !model.canReplaceAll, @"an invalid pattern empties the list");
    model.options = 0;
    model.findString = @"eq:main";
    model.maximumItems = 3;
    RunPending();
    Spin(^BOOL { return model.activity == TSTeXRootSearchActivityIdle; }, 30);
    Check(model.reachedLimit && model.numberOfItems == 3 && !model.canReplaceAll, @"at the limit nothing can be replaced");
    [SourceRequests removeAllObjects];
    [model setFiles:@[FileNamed(model, @"thesis.tex")] included:NO];
    Spin(^BOOL { return model.activity == TSTeXRootSearchActivityIdle; }, 30);
    Check(SourceRequests.count == 1 && [SourceRequests.firstObject count] == 4, @"with the limit reached, turning a file off searches every file on again");
    model.maximumItems = 500000;
    [model setFiles:model.project.files included:YES];
    Spin(^BOOL { return model.activity == TSTeXRootSearchActivityIdle; }, 30);

    // Multiple replacement: a rule that cannot be used is shown, the others apply.
    TSRegexReplacementRule *good = [[TSRegexReplacementRule alloc] initWithFindString:@"eq:main" replaceString:@"eq:x" usesRegularExpression:NO ignoresCase:NO enabled:YES note:nil];
    TSRegexReplacementRule *bad = [[TSRegexReplacementRule alloc] initWithFindString:@"(" replaceString:@"" usesRegularExpression:YES ignoresCase:NO enabled:YES note:nil];
    model.multipleReplace = [[TSRegexMultipleReplace alloc] initWithRules:@[good, bad] textualOptions:0 regularExpressionOptions:0 replacementSyntax:TSRegexReplacementSyntaxICU];
    model.mode = TSTeXRootSearchModeMultipleReplace;
    RunPending();
    Spin(^BOOL { return model.activity == TSTeXRootSearchActivityIdle; }, 30);
    Check(model.queryError && model.numberOfItems == 4 && model.canReplaceAll, [NSString stringWithFormat:@"a set with a bad rule (three lines in a row are one hunk): %lu hunks", (unsigned long)model.numberOfItems]);

    // Stopping while searching a long text, and while collecting.
    NSMutableString *big = [NSMutableString stringWithString:@"% !TEX root = ../thesis.tex\n"];
    for (NSUInteger k = 0; k < 200000; k++) [big appendString:@"eq:main and more text to search through here\n"];
    OpenTexts[@"chapters/three.tex"] = big;
    model.mode = TSTeXRootSearchModeReplace;
    [model searchNow];
    Check(model.activity == TSTeXRootSearchActivityComputing, @"searching");
    [model stop];
    Check(model.stopped && model.results.count == 0 && model.activity == TSTeXRootSearchActivityIdle && !model.canReplaceAll, @"stopping empties the list");
    Spin(^BOOL { return NO; }, 0.5);
    Check(model.results.count == 0, @"the stopped search delivers nothing later");
    [OpenTexts removeAllObjects];
    [model collect];
    [model stop];
    Check(model.stopped && model.activity == TSTeXRootSearchActivityIdle, @"collecting can be stopped");
    Spin(^BOOL { return NO; }, 0.3);
    Check(model.activity == TSTeXRootSearchActivityIdle && model.results.count == 0, @"the stopped collection delivers nothing later");
    [model collect];
    Check(!model.stopped, @"collecting again clears the note of the stop");
    Spin(^BOOL { return model.activity == TSTeXRootSearchActivityIdle; }, 30);
    model.eventMessage = @"Replaced";
    [model searchNow];
    Spin(^BOOL { return model.activity == TSTeXRootSearchActivityIdle; }, 30);
    Check([model.eventMessage isEqualToString:@"Replaced"], @"the event line stays over a search");
    model.replaceString = @"changed";
    Check(model.eventMessage == nil, @"the event line goes with the next change");

    // A document closed while collecting, its unsaved text thrown away: that text is never listed (Codex 3b F1).
    TSTeXRootSearchModel *closing = [[TSTeXRootSearchModel alloc] initWithRootURL:RootURL() environment:Environment()];
    OpenTexts[@"chapters/two.tex"] = @"% !TEX root = ../thesis.tex\nUNSAVED text\n";
    DocumentsSignature = @"two open";
    [closing setMode:TSTeXRootSearchModeReplace findString:@"UNSAVED" replaceString:@"x" options:0 syntax:TSRegexReplacementSyntaxICU multipleReplace:nil];
    [closing collect]; // the open document's text is taken now
    [OpenTexts removeAllObjects];
    DocumentsSignature = @"two closed";
    Spin(^BOOL { return closing.activity == TSTeXRootSearchActivityIdle && closing.project && closing.resultGeneration == closing.generation; }, 30);
    Check(closing.numberOfCollections == 2 && closing.numberOfItems == 0 && !closing.canReplaceAll,
          [NSString stringWithFormat:@"a document closed while collecting: collected again (%lu), its unsaved text not listed (%lu items)",
           (unsigned long)closing.numberOfCollections, (unsigned long)closing.numberOfItems]);
    // Opened while collecting: told by the entry, collecting starts again.
    OpenTexts[@"chapters/two.tex"] = @"% !TEX root = ../thesis.tex\nUNSAVED again\n";
    [closing collect];
    DocumentsSignature = @"two open again";
    [closing openDocumentsDidChange];
    Spin(^BOOL { return closing.activity == TSTeXRootSearchActivityIdle && closing.resultGeneration == closing.generation; }, 30);
    Check(closing.numberOfCollections == 4 && closing.numberOfItems == 1, [NSString stringWithFormat:@"a document opened while collecting is searched in its text (%lu items)", (unsigned long)closing.numberOfItems]);
    // Closed after the files were collected: searching collects again first.
    [OpenTexts removeAllObjects];
    DocumentsSignature = @"two closed again";
    [closing searchNow];
    Spin(^BOOL { return closing.activity == TSTeXRootSearchActivityIdle && closing.resultGeneration == closing.generation; }, 30);
    Check(closing.numberOfCollections == 5 && closing.numberOfItems == 0, @"a document closed since collecting: searching collects again first");
    DocumentsSignature = @"start";
}

#pragma mark Window

static TSAdvancedFindController *MakeController(void)
{
    TSAdvancedFindSettings *settings = [[TSAdvancedFindSettings alloc] initWithDefaults:[TSMemoryDefaults new] findPasteboard:[NSPasteboard pasteboardWithUniqueName]];
    return [[TSAdvancedFindController alloc] initWithSettings:settings];
}

static NSArray<NSView *> *AllViews(NSView *root)
{
    NSMutableArray<NSView *> *all = [NSMutableArray array], *pending = [NSMutableArray arrayWithObject:root];
    while (pending.count) {
        NSView *view = pending.lastObject;
        [pending removeLastObject];
        [all addObject:view];
        [pending addObjectsFromArray:view.subviews];
    }
    return all;
}

/// A label shows all of its text.
static BOOL LabelFits(NSTextField *label)
{
    [label.window.contentView layoutSubtreeIfNeeded];
    NSSize needed = [label.cell cellSizeForBounds:NSMakeRect(0, 0, NSWidth(label.bounds), CGFLOAT_MAX)];
    return needed.height <= NSHeight(label.bounds) + 1 && NSWidth(label.bounds) > 0;
}

/// As Tests/MultipleReplace.m writes its images: the materials drawn within the window, the controls' cells drawn again.
static void DrawMaterialsWithinWindow(NSView *view)
{
    NSMutableArray<NSView *> *pendingEffects = [view.subviews mutableCopy];
    while (pendingEffects.count) {
        NSView *v = pendingEffects.lastObject;
        [pendingEffects removeLastObject];
        [pendingEffects addObjectsFromArray:v.subviews];
        if ([v isKindOfClass:[NSVisualEffectView class]])
            ((NSVisualEffectView *)v).blendingMode = NSVisualEffectBlendingModeWithinWindow;
        if ([v isKindOfClass:[NSVisualEffectView class]] && [v.superview isKindOfClass:[NSTableRowView class]]) {
            v.hidden = YES;
            ((NSTableRowView *)v.superview).backgroundColor = NSColor.unemphasizedSelectedContentBackgroundColor;
        }
    }
}

static BOOL WritePNG(NSView *view, NSAppearance *appearance, NSString *path)
{
    __block BOOL written = NO;
    [appearance performAsCurrentDrawingAppearance:^{
        DrawMaterialsWithinWindow(view);
        [view layoutSubtreeIfNeeded];
        [view displayIfNeeded];
        DrawMaterialsWithinWindow(view); // the rows made by the layout too
        NSBitmapImageRep *raw = [view bitmapImageRepForCachingDisplayInRect:view.bounds];
        if (!raw)
            return;
        [view cacheDisplayInRect:view.bounds toBitmapImageRep:raw];
        NSImage *image = [[NSImage alloc] initWithSize:view.bounds.size];
        [image lockFocus];
        [NSColor.windowBackgroundColor setFill];
        NSRectFill(view.bounds);
        NSImage *cached = [[NSImage alloc] initWithSize:view.bounds.size];
        [cached addRepresentation:raw];
        [cached drawInRect:view.bounds fromRect:NSZeroRect operation:NSCompositingOperationSourceOver fraction:1];
        NSMutableArray<NSView *> *pending = [view.subviews mutableCopy];
        while (pending.count) {
            NSView *v = pending.lastObject;
            [pending removeLastObject];
            [pending addObjectsFromArray:v.subviews];
            if (!([v isKindOfClass:[NSButton class]] || [v isKindOfClass:[NSSegmentedControl class]]) || v.isHiddenOrHasHiddenAncestor)
                continue;
            NSRect frame = [v convertRect:v.bounds toView:view];
            // Only the part that the scroll views show: rows scrolled out of a table are not drawn.
            NSRect visible = [v convertRect:v.visibleRect toView:view];
            if (NSIsEmptyRect(visible))
                continue;
            [NSGraphicsContext saveGraphicsState];
            NSRectClip(NSMakeRect(NSMinX(visible), view.isFlipped ? NSHeight(view.bounds) - NSMaxY(visible) : NSMinY(visible), NSWidth(visible), NSHeight(visible)));
            NSAffineTransform *transform = [NSAffineTransform transform];
            [transform translateXBy:frame.origin.x yBy:view.isFlipped ? NSHeight(view.bounds) - NSMaxY(frame) : frame.origin.y];
            if (v.isFlipped) {
                [transform translateXBy:0 yBy:frame.size.height];
                [transform scaleXBy:1 yBy:-1];
            }
            [transform concat];
            [[(NSControl *)v cell] drawWithFrame:v.bounds inView:v];
            [NSGraphicsContext restoreGraphicsState];
        }
        [image unlockFocus];
        NSBitmapImageRep *painted = [[NSBitmapImageRep alloc] initWithData:image.TIFFRepresentation];
        written = [[painted representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:path atomically:YES];
    }];
    return written;
}

static void TestWindow(NSString *images)
{
    TSAdvancedFindController *controller = MakeController();
    controller.settings.findString = @"eq:main";
    controller.settings.replaceString = @"eq:central";
    controller.settings.options = 0;
    NSURL *libraryDirectory = [NSURL fileURLWithPath:[Folder stringByAppendingPathComponent:@".sets"] isDirectory:YES];
    TSMultipleReplaceLibrary *library = [[TSMultipleReplaceLibrary alloc] initWithDirectory:libraryDirectory];
    TSRegexReplacementRule *rule = [[TSRegexReplacementRule alloc] initWithFindString:@"\\eqref" replaceString:@"\\cref" usesRegularExpression:NO ignoresCase:NO enabled:YES note:nil];
    TSRegexMultipleReplace *set = [[TSRegexMultipleReplace alloc] initWithRules:@[rule] textualOptions:0 regularExpressionOptions:0 replacementSyntax:TSRegexReplacementSyntaxICU];
    [library saveSet:set named:@"Refs" error:NULL];
    TSTeXRootSearchWindowController *window = [[TSTeXRootSearchWindowController alloc] initWithFindController:controller library:library];
    __block NSUInteger helps = 0, edits = 0, replaces = 0, shows = 0;
    window.openHelpHandler = ^{ helps++; };
    window.editSetHandler = ^(NSString *name) { if ([name isEqualToString:@"Refs"]) edits++; };
    window.showItemHandler = ^(TSTeXRootSearchFileResult *file, TSTeXRootSearchItem *item, BOOL front) { shows++; };
    DelayRunsAtOnce = YES;
    [window openForRootURL:RootURL() environment:Environment() mode:TSTeXRootSearchModeFind setName:nil];
    TSTeXRootSearchModel *model = window.model;
    Spin(^BOOL { return model.activity == TSTeXRootSearchActivityIdle && model.project; }, 30);
    [window updateFromModel];
    Check(!window.window.isVisible, @"the window is never shown");
    Check(window.modeControl.selectedSegment == 0 && !window.findRow.hidden && window.replaceRow.hidden && !window.optionsRow.hidden && window.setRow.hidden
          && window.replaceAllButton.hidden && window.backupBox.hidden, @"Find mode: the find field and the options, no replacement and no Replace All");
    Check([window.rootLabel.stringValue containsString:@"thesis.tex"] && [window.rootLabel.toolTip isEqualToString:RootURL().path], @"the root's name, its path in the tool tip");
    Check([window.explanationLabel.stringValue containsString:@"thesis.tex"] && [window.explanationLabel.stringValue containsString:@"TEX root"], @"the line says what is searched");
    Check([window.findField.string isEqualToString:@"eq:main"], @"the find string is the panel's");
    Check([window.statusField.stringValue isEqualToString:@"Found: 6 · Files: 4 of 5"], [@"status: " stringByAppendingString:window.statusField.stringValue]);
    Check(!window.unreadableButton.hidden && [window.unreadableButton.title containsString:@"1"], @"the file not read is shown");
    NSViewController *unreadable = [window makeUnreadableViewController];
    BOOL listsLocked = NO;
    for (NSView *view in AllViews(unreadable.view))
        if ([view isKindOfClass:[NSTextField class]] && [((NSTextField *)view).stringValue isEqualToString:@"chapters/locked.tex"])
            listsLocked = YES;
    Check(listsLocked, @"the list of files not read names the locked file");

    // The shared strings: what the panel sets shows here, what is typed here goes to the panel.
    controller.settings.findString = @"lem:a";
    Check([window.findField.string isEqualToString:@"lem:a"] && [model.findString isEqualToString:@"lem:a"], @"a find string set elsewhere is shown and searched");
    window.findField.string = @"eq:main";
    [NSNotificationCenter.defaultCenter postNotificationName:NSTextDidChangeNotification object:window.findField];
    Check([controller.settings.findString isEqualToString:@"eq:main"] && [model.findString isEqualToString:@"eq:main"], @"typing here sets the shared string");
    Spin(^BOOL { return model.activity == TSTeXRootSearchActivityIdle && model.resultGeneration == model.generation; }, 30);

    // Replace mode: the second field, Replace All after the search.
    window.modeControl.selectedSegment = 1;
    [window.modeControl sendAction:window.modeControl.action to:window.modeControl.target];
    Check(!window.replaceRow.hidden && !window.replaceAllButton.hidden && !window.backupBox.hidden && !window.replaceAllButton.enabled, @"Replace mode: Replace All is gray until a handler and a search");
    window.replaceAllHandler = ^(TSTeXRootSearchWindowController *c) { replaces++; };
    Spin(^BOOL { return model.activity == TSTeXRootSearchActivityIdle && model.resultGeneration == model.generation; }, 30);
    [window updateFromModel];
    Check(window.replaceAllButton.enabled && [window.statusField.stringValue isEqualToString:@"To replace: 6 · Files: 4"], [@"Replace All can be pressed: " stringByAppendingString:window.statusField.stringValue]);
    [window replaceAll:nil];
    Check(replaces == 1, @"Replace All calls its handler");
    controller.settings.replaceString = @"eq:new";
    Check(!window.replaceAllButton.enabled, @"right after a change Replace All is gray");
    Spin(^BOOL { return model.activity == TSTeXRootSearchActivityIdle && model.resultGeneration == model.generation; }, 30);
    [window updateFromModel];

    // The list: rows, highlights, checks and the spoken labels.
    NSTableView *list = window.resultsList.tableView;
    Check(list.numberOfRows == 10, [NSString stringWithFormat:@"the list has 4 headings and 6 items (%ld rows)", (long)list.numberOfRows]);
    TSTeXRootSearchFileResult *one = nil;
    for (TSTeXRootSearchFileResult *file in model.results)
        if ([file.source.file.relativePath isEqualToString:@"chapters/one.tex"])
            one = file;
    NSAttributedString *before = [window.resultsList shownTextOfItem:one.items[0] inFile:one after:NO];
    NSAttributedString *after = [window.resultsList shownTextOfItem:one.items[0] inFile:one after:YES];
    NSRange beforeMark = [before.string rangeOfString:@"eq:main"], afterMark = [after.string rangeOfString:@"eq:new"];
    Check([before attribute:NSBackgroundColorAttributeName atIndex:beforeMark.location effectiveRange:NULL] != nil
          && [after attribute:NSBackgroundColorAttributeName atIndex:afterMark.location effectiveRange:NULL] != nil
          && [before attribute:NSBackgroundColorAttributeName atIndex:0 effectiveRange:NULL] == nil, @"the match and what is put in are marked");
    NSInteger itemRow = [window.resultsList rowOfObject:one.items[0]];
    NSString *spoken = [window.resultsList accessibilityLabelOfRow:itemRow];
    Check([spoken containsString:@"Line 2"] && [spoken containsString:@"eq:new"] && [spoken hasSuffix:@"replaced"], [@"spoken row: " stringByAppendingString:spoken]);
    NSButton *box = nil;
    for (NSView *view in AllViews(list))
        if ([view isKindOfClass:[NSButton class]] && [view.identifier isEqualToString:@"checkBox"] && [list rowForView:view] == itemRow)
            box = (NSButton *)view;
    [list layoutSubtreeIfNeeded];
    if (!box) {
        box = [list viewAtColumn:[list columnWithIdentifier:@"check"] row:itemRow makeIfNecessary:YES];
    }
    Check([box isKindOfClass:[NSButton class]] && box.state == NSControlStateValueOn, @"an item's check box is on");
    box.state = NSControlStateValueOff;
    [box sendAction:box.action to:box.target];
    Check(![model isItemIncluded:one.items[0] inFile:one] && [[window.resultsList accessibilityLabelOfRow:itemRow] hasSuffix:@"not replaced"]
          && [[window.resultsList shownTextOfItem:one.items[0] inFile:one after:YES].string containsString:@"eq:main"], @"turned off: kept as it is, and said so");
    [list selectRowIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)[window.resultsList rowOfObject:one]] byExtendingSelection:NO];
    NSEvent *space = [NSEvent keyEventWithType:NSEventTypeKeyDown location:NSZeroPoint modifierFlags:0 timestamp:0 windowNumber:0 context:nil
                                    characters:@" " charactersIgnoringModifiers:@" " isARepeat:NO keyCode:49];
    [list keyDown:space];
    Check([model isItemIncluded:one.items[0] inFile:one] && [model isItemIncluded:one.items[2] inFile:one], @"Space on a file's heading with an item off turns all on");
    [list keyDown:space];
    Check(![model isItemIncluded:one.items[0] inFile:one] && ![model isItemIncluded:one.items[1] inFile:one] && ![model isItemIncluded:one.items[2] inFile:one],
          @"and with all on, all off");
    [list keyDown:space];
    [list selectRowIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)itemRow] byExtendingSelection:NO];
    NSEvent *enter = [NSEvent keyEventWithType:NSEventTypeKeyDown location:NSZeroPoint modifierFlags:0 timestamp:0 windowNumber:0 context:nil
                                    characters:@"\r" charactersIgnoringModifiers:@"\r" isARepeat:NO keyCode:36];
    [list keyDown:enter];
    Check(shows == 1, @"Return shows the item in its document");

    // An item longer than 20 lines: the row says how many more, and the whole change shows every line (Codex 3b F3).
    {
        NSMutableString *before = [NSMutableString stringWithString:@"BEGIN\n"], *after = [NSMutableString stringWithString:@"BEGIN\n"];
        for (NSUInteger k = 2; k <= 23; k++) {
            [before appendFormat:@"line %lu\n", (unsigned long)k];
            [after appendFormat:k == 21 ? @"SECRET_REPLACEMENT_21\n" : @"line %lu\n", (unsigned long)k];
        }
        [before appendString:@"END"];
        [after appendString:@"END"];
        OpenTexts[@"chapters/three.tex"] = [NSString stringWithFormat:@"%% !TEX root = ../thesis.tex\n%@\n", before];
        controller.settings.findString = before;
        controller.settings.replaceString = after;
        [model documentsDidChange];
        Spin(^BOOL { return model.activity == TSTeXRootSearchActivityIdle && model.resultGeneration == model.generation; }, 30);
        [window updateFromModel];
        TSTeXRootSearchFileResult *three = nil;
        for (TSTeXRootSearchFileResult *file in model.results)
            if ([file.source.file.relativePath isEqualToString:@"chapters/three.tex"])
                three = file;
        TSTeXRootSearchItem *longItem = three.items.firstObject;
        NSString *shownAfter = [window.resultsList shownTextOfItem:longItem inFile:three after:YES].string;
        NSInteger longRow = [window.resultsList rowOfObject:longItem];
        NSString *spokenLong = [window.resultsList accessibilityLabelOfRow:longRow];
        NSViewController *wholeChange = [window.resultsList wholeChangeViewControllerForRow:longRow];
        NSString *wholeAfter = nil;
        for (NSView *view in AllViews(wholeChange.view))
            if ([view isKindOfClass:[NSTextView class]] && [view.accessibilityLabel isEqualToString:@"After"])
                wholeAfter = ((NSTextView *)view).string;
        Check(three && ![shownAfter containsString:@"SECRET"] && [shownAfter hasSuffix:@"⋯ 4 more lines"] && [spokenLong containsString:@"4 more lines"]
              && [wholeAfter containsString:@"SECRET_REPLACEMENT_21"] && [wholeAfter hasSuffix:@"END"],
              [NSString stringWithFormat:@"a long item: the row says 4 more lines, the whole change shows line 21 (%@)", shownAfter]);
        if (images) {
            [NSFileManager.defaultManager createDirectoryAtPath:images withIntermediateDirectories:YES attributes:nil error:NULL];
            NSString *language = NSBundle.mainBundle.preferredLocalizations.firstObject ?: @"en";
            for (NSAppearanceName name in @[NSAppearanceNameAqua, NSAppearanceNameDarkAqua]) {
                NSAppearance *appearance = [NSAppearance appearanceNamed:name];
                NSViewController *shown = [window.resultsList wholeChangeViewControllerForRow:longRow];
                shown.view.appearance = appearance;
                NSString *path = [images stringByAppendingPathComponent:[NSString stringWithFormat:@"%@-%@-whole-change.png", language,
                                                                         [name isEqualToString:NSAppearanceNameAqua] ? @"light" : @"dark"]];
                Check(WritePNG(shown.view, appearance, path), @"whole change image");
                window.window.appearance = appearance;
                [window updateFromModel];
                [window.resultsList.tableView scrollRowToVisible:longRow];
                Check(WritePNG((NSView *_Nonnull)window.window.contentView, appearance,
                               [path stringByReplacingOccurrencesOfString:@"-whole-change" withString:@"-long-item"]), @"long item image");
            }
            window.window.appearance = nil;
        }
        // 21 lines are shown whole: one line more fits where its count would go.
        NSMutableString *twentyOne = [NSMutableString string];
        for (NSUInteger k = 1; k <= 21; k++)
            [twentyOne appendFormat:k < 21 ? @"row %lu\n" : @"row %lu", (unsigned long)k];
        OpenTexts[@"chapters/three.tex"] = [NSString stringWithFormat:@"%% !TEX root = ../thesis.tex\n%@\n", twentyOne];
        controller.settings.findString = twentyOne;
        controller.settings.replaceString = [twentyOne stringByReplacingOccurrencesOfString:@"row 21" withString:@"ROW 21"];
        [model documentsDidChange];
        Spin(^BOOL { return model.activity == TSTeXRootSearchActivityIdle && model.resultGeneration == model.generation; }, 30);
        TSTeXRootSearchFileResult *twentyOneFile = nil;
        for (TSTeXRootSearchFileResult *file in model.results)
            if ([file.source.file.relativePath isEqualToString:@"chapters/three.tex"])
                twentyOneFile = file;
        NSString *shown21 = [window.resultsList shownTextOfItem:twentyOneFile.items.firstObject inFile:twentyOneFile after:YES].string;
        Check([shown21 containsString:@"ROW 21"] && ![shown21 containsString:@"more lines"],
              [NSString stringWithFormat:@"21 lines are shown whole (%@)", [shown21 substringFromIndex:shown21.length > 30 ? shown21.length - 30 : 0]]);
        [OpenTexts removeAllObjects];
        controller.settings.findString = @"eq:main";
        controller.settings.replaceString = @"eq:new";
        [model documentsDidChange];
        Spin(^BOOL { return model.activity == TSTeXRootSearchActivityIdle && model.resultGeneration == model.generation; }, 30);
        [window updateFromModel];
    }

    // The tree: three states, the spoken labels.
    NSOutlineView *tree = window.fileTree.outlineView;
    NSInteger chapters = -1, twoRow = -1;
    for (NSInteger row = 0; row < tree.numberOfRows; row++) {
        NSArray *files = [window.fileTree filesOfRow:row];
        if (files.count == 3)
            chapters = row;
        if (files.count == 1 && [((TSTeXRootProjectFile *)files.firstObject).relativePath isEqualToString:@"chapters/two.tex"])
            twoRow = row;
    }
    Check(tree.numberOfRows == 8 && chapters >= 0 && twoRow >= 0, [NSString stringWithFormat:@"the tree: folder, root, 2 folders, 4 files (%ld rows)", (long)tree.numberOfRows]);
    [window.fileTree toggleRow:twoRow];
    Check([window.fileTree stateOfRow:chapters] == NSControlStateValueMixed && [window.fileTree stateOfRow:0] == NSControlStateValueMixed
          && [[window.fileTree accessibilityLabelOfRow:chapters] hasSuffix:@"partly searched"], @"a file off: its folders are mixed");
    [window.fileTree toggleRow:chapters];
    Check([window.fileTree stateOfRow:chapters] == NSControlStateValueOn && [window.fileTree stateOfRow:twoRow] == NSControlStateValueOn, @"a mixed folder turns all on");
    [window.fileTree toggleRow:chapters];
    Check([window.fileTree stateOfRow:chapters] == NSControlStateValueOff && [[window.fileTree accessibilityLabelOfRow:chapters] hasSuffix:@"not searched"], @"an on folder turns all off");
    [window.fileTree toggleRow:chapters];
    Spin(^BOOL { return model.activity == TSTeXRootSearchActivityIdle; }, 30);

    // An invalid pattern: said in red and in the find field's description.
    controller.settings.options = TSRegexFindRegularExpression;
    controller.settings.findString = @"(";
    Spin(^BOOL { return model.activity == TSTeXRootSearchActivityIdle && model.resultGeneration == model.generation; }, 30);
    [window updateFromModel];
    Check(window.findField.accessibilityHelp.length > 0 && [window.statusField.textColor isEqual:NSColor.systemRedColor] && model.results.count == 0,
          @"an invalid pattern is said in red and in the field's description, and the list is empty");
    controller.settings.options = 0;
    controller.settings.findString = @"eq:main";
    Spin(^BOOL { return model.activity == TSTeXRootSearchActivityIdle && model.resultGeneration == model.generation; }, 30);
    [window updateFromModel];
    Check(window.findField.accessibilityHelp.length == 0, @"a valid pattern clears the description");

    // The question mark, Help, stopping with Escape.
    NSViewController *explanation = [window makeExplanationViewController];
    NSString *texts = @"";
    NSButton *helpButton = nil;
    for (NSView *view in AllViews(explanation.view)) {
        if ([view isKindOfClass:[NSTextField class]])
            texts = [texts stringByAppendingString:((NSTextField *)view).stringValue];
        if ([view isKindOfClass:[NSButton class]])
            helpButton = (NSButton *)view;
    }
    Check([texts containsString:@"20 lines"] && ![texts containsString:@"SourceDoc"], @"the question mark says the rule");
    window.mentionsSourceDoc = YES;
    explanation = [window makeExplanationViewController];
    texts = @"";
    for (NSView *view in AllViews(explanation.view))
        if ([view isKindOfClass:[NSTextField class]])
            texts = [texts stringByAppendingString:((NSTextField *)view).stringValue];
    Check([texts containsString:@"%SourceDoc"], @"with the old heading commands it names %SourceDoc too");
    [helpButton sendAction:helpButton.action to:helpButton.target];
    Check(helps == 1, @"Open Help calls its handler");
    [model searchNow];
    [window.findField cancelOperation:nil]; // Escape in the find field
    Spin(^BOOL { return NO; }, 0.05);
    Check(model.stopped && [window.statusField.stringValue isEqualToString:@"Stopped"], @"Escape stops, and the status says so");

    // Multiple replacement: the set, its rules, Edit…, a change of the set searches again.
    window.modeControl.selectedSegment = 2;
    [window.modeControl sendAction:window.modeControl.action to:window.modeControl.target];
    Check(window.findRow.hidden && !window.setRow.hidden && [window.setPopUp.titleOfSelectedItem isEqualToString:@"Refs"]
          && [window.ruleCountLabel.stringValue isEqualToString:@"Rules: 1"], @"Multiple Replace mode shows the set");
    Spin(^BOOL { return model.activity == TSTeXRootSearchActivityIdle && model.resultGeneration == model.generation; }, 30);
    Check(model.numberOfItems == 3, [NSString stringWithFormat:@"the set's hunks: %lu", (unsigned long)model.numberOfItems]);
    [window.editSetButton sendAction:window.editSetButton.action to:window.editSetButton.target];
    Check(edits == 1, @"Edit… shows the set");
    TSRegexReplacementRule *more = [[TSRegexReplacementRule alloc] initWithFindString:@"\\label" replaceString:@"\\tag" usesRegularExpression:NO ignoresCase:NO enabled:YES note:nil];
    [library saveSet:[[TSRegexMultipleReplace alloc] initWithRules:@[rule, more] textualOptions:0 regularExpressionOptions:0 replacementSyntax:TSRegexReplacementSyntaxICU] named:@"Refs" error:NULL];
    Spin(^BOOL { return model.activity == TSTeXRootSearchActivityIdle && model.resultGeneration == model.generation; }, 30);
    Check(model.multipleReplace.rules.count == 2 && [window.ruleCountLabel.stringValue isEqualToString:@"Rules: 2"], @"a saved change of the set is searched again");

    // The line that says what is searched wraps in a narrow window.
    [window.window setContentSize:NSMakeSize(720, 420)];
    Check(LabelFits(window.explanationLabel), @"the line that says what is searched is never cut");

    if (images) {
        [NSFileManager.defaultManager createDirectoryAtPath:images withIntermediateDirectories:YES attributes:nil error:NULL];
        NSString *language = NSBundle.mainBundle.preferredLocalizations.firstObject ?: @"en";
        [window.window setContentSize:NSMakeSize(900, 580)];
        [window.window.contentView layoutSubtreeIfNeeded];
        Check(NSWidth(window.fileTree.scrollView.frame) < 260, [NSString stringWithFormat:@"the tree starts narrow (%.0f)", NSWidth(window.fileTree.scrollView.frame)]);
        for (NSNumber *mode in @[@0, @1, @2]) {
            window.modeControl.selectedSegment = mode.integerValue;
            [window.modeControl sendAction:window.modeControl.action to:window.modeControl.target];
            Spin(^BOOL { return model.activity == TSTeXRootSearchActivityIdle && model.resultGeneration == model.generation; }, 30);
            [window updateFromModel];
            for (NSAppearanceName name in @[NSAppearanceNameAqua, NSAppearanceNameDarkAqua]) {
                NSAppearance *appearance = [NSAppearance appearanceNamed:name];
                window.window.appearance = appearance;
                NSString *path = [images stringByAppendingPathComponent:[NSString stringWithFormat:@"%@-%@-mode%@.png", language,
                                                                         [name isEqualToString:NSAppearanceNameAqua] ? @"light" : @"dark", mode]];
                Check(WritePNG((NSView *_Nonnull)window.window.contentView, appearance, path), [@"image " stringByAppendingString:path]);
                if (mode.integerValue == 0) {
                    NSViewController *pop = [window makeExplanationViewController];
                    pop.view.appearance = appearance;
                    Check(WritePNG(pop.view, appearance, [path stringByReplacingOccurrencesOfString:@"-mode0" withString:@"-explanation"]), @"explanation image");
                }
            }
        }
    }
    [window close];
    DelayRunsAtOnce = NO;
}

/// Every language: the strings are found, the line that says what is searched is whole.
static void TestLanguage(void)
{
    TSAdvancedFindController *controller = MakeController();
    controller.settings.findString = @"eq:main";
    NSURL *libraryDirectory = [NSURL fileURLWithPath:[Folder stringByAppendingPathComponent:@".sets2"] isDirectory:YES];
    TSTeXRootSearchWindowController *window = [[TSTeXRootSearchWindowController alloc] initWithFindController:controller library:[[TSMultipleReplaceLibrary alloc] initWithDirectory:libraryDirectory]];
    DelayRunsAtOnce = YES;
    [window openForRootURL:RootURL() environment:Environment() mode:TSTeXRootSearchModeFind setName:nil];
    Spin(^BOOL { return window.model.activity == TSTeXRootSearchActivityIdle && window.model.project; }, 30);
    [window updateFromModel];
    NSString *language = NSBundle.mainBundle.preferredLocalizations.firstObject ?: @"en";
    for (NSString *text in @[window.window.title, window.explanationLabel.stringValue, window.rootLabel.stringValue, window.statusField.stringValue,
                             [window.modeControl labelForSegment:0], window.unreadableButton.title])
        Check(![text containsString:@"TeXRootSearch."] && text.length > 0, [NSString stringWithFormat:@"%@: a string is missing (%@)", language, text]);
    if (![language hasPrefix:@"en"])
        Check(![window.window.title isEqualToString:@"Find in TeX Sources"], [language stringByAppendingString:@": the title is translated"]);
    [window.window setContentSize:NSMakeSize(720, 420)];
    Check(LabelFits(window.explanationLabel), [language stringByAppendingString:@": the line that says what is searched is never cut"]);
    for (TSTeXRootEntryState state = TSTeXRootEntryStateNoDocument; state <= TSTeXRootEntryStateRoot; state++)
        for (NSNumber *applying in @[@NO, @YES]) {
            NSString *title = [TSTeXRootEntryRules titleForState:state applying:applying.boolValue];
            Check([title containsString:@"TEX root"] && [title hasSuffix:@"…"], [NSString stringWithFormat:@"%@: the item %@ keeps TEX root as written", language, title]);
        }
    [window close];
    DelayRunsAtOnce = NO;
}

static NSTimeInterval LongestPause(void (^start)(void), BOOL (^done)(void));

#pragma mark Entry rules, panel and Multiple Replace items

@interface TSFakeTeXRootTarget : NSObject <TSTeXRootSearchActions>
@property (nonatomic) NSUInteger shown, applied;
@end
@implementation TSFakeTeXRootTarget
- (IBAction)showTeXRootSearch:(id)sender { self.shown++; }
- (IBAction)applySetToTeXRootSources:(id)sender { self.applied++; }
- (BOOL)validateMenuItem:(NSMenuItem *)item { item.title = @"validated"; return YES; }
@end

static void TestEntry(void)
{
    NSURL *root = RootURL();
    NSURL *child = [NSURL fileURLWithPath:[Folder stringByAppendingPathComponent:@"chapters/one.tex"]];
    NSURL *found = nil;
    Check([TSTeXRootEntryRules stateForDocumentURL:nil text:@"x" allowingSourceDoc:NO jobNameToken:@"\\jobname" rootURL:&found] == TSTeXRootEntryStateUntitled && !found,
          @"an untitled document cannot be used");
    Check([TSTeXRootEntryRules stateForDocumentURL:[NSURL fileURLWithPath:@"/tmp/a.TEX"] text:@"" allowingSourceDoc:NO jobNameToken:@"\\jobname" rootURL:NULL] == TSTeXRootEntryStateNotTeX
          && [TSTeXRootEntryRules stateForDocumentURL:[NSURL fileURLWithPath:@"/tmp/a.bib"] text:@"" allowingSourceDoc:NO jobNameToken:@"\\jobname" rootURL:NULL] == TSTeXRootEntryStateNotTeX,
          @"only the lowercase tex extension");
    Check([TSTeXRootEntryRules stateForDocumentURL:child text:@"% !TEX root = ../thesis.tex\n" allowingSourceDoc:NO jobNameToken:@"\\jobname" rootURL:&found] == TSTeXRootEntryStateChild
          && [found.path isEqualToString:root.path], @"a child names its root");
    Check([TSTeXRootEntryRules stateForDocumentURL:child text:@"% !TeX root = ../thesis.tex\n" allowingSourceDoc:NO jobNameToken:@"\\jobname" rootURL:&found] == TSTeXRootEntryStateRoot
          && [found isEqual:child], @"% !TeX root is not a root line: the file is its own root");
    Check([[TSTeXRootEntryRules titleForState:TSTeXRootEntryStateChild applying:NO] isEqualToString:@"Find in TeX Sources with the Same TEX root…"]
          && [[TSTeXRootEntryRules titleForState:TSTeXRootEntryStateRoot applying:YES] isEqualToString:@"Apply to TeX Sources with This File as TEX root…"],
          @"the titles of the items");
    Check([TSTeXRootProjectCollector problemWithRootURL:[NSURL fileURLWithPath:[Folder stringByAppendingPathComponent:@"missing.tex"]]] == TSTeXRootProblemMissing
          && [[TSTeXRootEntryRules messageForProblem:TSTeXRootProblemMissing] containsString:@"TEX root"], @"a missing root is warned of");

    // The menus decide from the text alone; choosing an item reads and checks on a background queue (Codex 3b F2).
    NSURL *nowhere = [NSURL fileURLWithPath:@"/nonexistent/folder/child.tex"];
    Check([TSTeXRootEntryRules menuStateForDocumentURL:nowhere text:@"% !TEX root = main.tex\n" allowingSourceDoc:NO] == TSTeXRootEntryStateChild
          && [TSTeXRootEntryRules menuStateForDocumentURL:nowhere text:@"x" allowingSourceDoc:NO] == TSTeXRootEntryStateRoot
          && [TSTeXRootEntryRules menuStateForDocumentURL:nil text:@"x" allowingSourceDoc:NO] == TSTeXRootEntryStateUntitled, @"the menus' state from the text alone");
    __block TSTeXRootEntryState resolved = TSTeXRootEntryStateNoDocument;
    __block NSURL *resolvedRoot = nil;
    __block TSTeXRootProblem resolvedProblem = TSTeXRootProblemNone;
    __block BOOL loadedOnMain = NO;
    NSTimeInterval choosing = LongestPause(^{
        [TSTeXRootEntryRules resolveRootForDocumentURL:child textLoader:^NSString *{
            loadedOnMain = NSThread.isMainThread;
            usleep(150000); // a slow disk
            return @"% !TEX root = ../missing.tex\n";
        } allowingSourceDoc:NO jobNameToken:@"\\jobname" completion:^(TSTeXRootEntryState state, NSURL *root, TSTeXRootProblem problem) {
            resolved = state;
            resolvedRoot = root;
            resolvedProblem = problem;
        }];
    }, ^BOOL { return resolvedRoot != nil; });
    Check(!loadedOnMain && choosing < 0.05 && resolved == TSTeXRootEntryStateChild && resolvedProblem == TSTeXRootProblemMissing
          && [resolvedRoot.lastPathComponent isEqualToString:@"missing.tex"],
          [NSString stringWithFormat:@"choosing an item reads on a background queue (%.0f ms on the main thread), and finds the root missing", choosing * 1000]);
    __block TSTeXRootEntryState menuState = TSTeXRootEntryStateNoDocument;
    __block BOOL menuDone = NO;
    NSTimeInterval validating = LongestPause(^{
        [TSTeXRootEntryRules menuStateForDocumentURL:child textLoader:^NSString *{ usleep(150000); return @"no root line\n"; } allowingSourceDoc:NO
                                          completion:^(TSTeXRootEntryState state) { menuState = state; menuDone = YES; }];
    }, ^BOOL { return menuDone; });
    Check(validating < 0.05 && menuState == TSTeXRootEntryStateRoot, [NSString stringWithFormat:@"the external editor's file is read for the menus in the background (%.0f ms)", validating * 1000]);

    // The panel's Find All menu and the Multiple Replace window's Replace All menu go to the opener.
    TSFakeTeXRootTarget *target = [TSFakeTeXRootTarget new];
    TSAdvancedFindController.texRootSearchTarget = target;
    TSAdvancedFindPanelController *panel = [[TSAdvancedFindPanelController alloc] initWithFindController:MakeController()];
    NSComboButton *findAll = nil;
    for (NSControl *control in panel.buttons)
        if ([control isKindOfClass:[NSComboButton class]] && control.action == NSSelectorFromString(@"advancedFindAll:"))
            findAll = (NSComboButton *)control;
    NSMenuItem *panelItem = nil;
    for (NSMenuItem *item in findAll.menu.itemArray)
        if (item.action == @selector(showTeXRootSearch:))
            panelItem = item;
    [findAll.menu.delegate menuNeedsUpdate:findAll.menu];
    Check(panelItem && panelItem.target == target && [findAll.menu itemAtIndex:[findAll.menu indexOfItem:panelItem] - 1].separatorItem,
          @"the panel's Find All menu ends with the item, after a separator");
    NSURL *libraryDirectory = [NSURL fileURLWithPath:[Folder stringByAppendingPathComponent:@".sets3"] isDirectory:YES];
    TSMultipleReplaceLibrary *library = [[TSMultipleReplaceLibrary alloc] initWithDirectory:libraryDirectory];
    TSMultipleReplaceWindowController *multiple = [[TSMultipleReplaceWindowController alloc] initWithFindController:MakeController() library:library];
    NSComboButton *replaceAll = nil;
    for (NSView *view in AllViews((NSView *_Nonnull)multiple.window.contentView))
        if ([view isKindOfClass:[NSComboButton class]] && ((NSComboButton *)view).action == NSSelectorFromString(@"replaceAll:"))
            replaceAll = (NSComboButton *)view;
    NSMenuItem *applyItem = replaceAll.menu.itemArray.firstObject;
    [replaceAll.menu.delegate menuNeedsUpdate:replaceAll.menu];
    Check(replaceAll && applyItem.action == @selector(applySetToTeXRootSources:) && applyItem.target == target, @"Replace All of the Multiple Replace window has the item under ▾");
    NSEvent *enter = [NSEvent keyEventWithType:NSEventTypeKeyDown location:NSZeroPoint modifierFlags:0 timestamp:0 windowNumber:0 context:nil
                                    characters:@"\r" charactersIgnoringModifiers:@"\r" isARepeat:NO keyCode:36];
    Check(!replaceAll.enabled || [replaceAll performKeyEquivalent:enter], @"Return still presses Replace All");
    TSAdvancedFindController.texRootSearchTarget = nil;
}

#pragma mark The main thread

/// The longest time the main thread did not run its timer while `work` was under way.
static NSTimeInterval LongestPause(void (^start)(void), BOOL (^done)(void))
{
    __block CFAbsoluteTime last = CFAbsoluteTimeGetCurrent();
    __block NSTimeInterval longest = 0;
    NSTimer *timer = [NSTimer scheduledTimerWithTimeInterval:0.005 repeats:YES block:^(NSTimer *t) {
        CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
        longest = MAX(longest, now - last);
        last = now;
    }];
    last = CFAbsoluteTimeGetCurrent(); // what start() does on the main thread counts too
    start();
    Spin(done, 120);
    CFAbsoluteTime end = CFAbsoluteTimeGetCurrent();
    longest = MAX(longest, end - last);
    [timer invalidate];
    return longest;
}

static void TestMainThread(void)
{
    // The collector is prepared (the open documents' files identified) on the background queue (Codex 3b F4).
    {
        PrepareDelay = 150000;
        PreparedOnMain = NO;
        __block TSTeXRootSearchModel *slow = nil;
        NSTimeInterval preparing = LongestPause(^{
            slow = [[TSTeXRootSearchModel alloc] initWithRootURL:RootURL() environment:Environment()];
            [slow setMode:TSTeXRootSearchModeFind findString:@"eq:main" replaceString:@"" options:0 syntax:TSRegexReplacementSyntaxICU multipleReplace:nil];
            [slow collect];
        }, ^BOOL { return slow.activity == TSTeXRootSearchActivityIdle && slow.project != nil; });
        printf("main thread: a slow file system while preparing to collect: longest pause %.0f ms\n", preparing * 1000);
        Check(!PreparedOnMain && preparing < 0.1, [NSString stringWithFormat:@"preparing to collect waits for the file system off the main thread (%.0f ms)", preparing * 1000]);
        PrepareDelay = 0;
    }

    // 25 files of 5,000 matches each (the limit per file), 10 MB in all: searching, listing, turning an item off.
    NSMutableString *body = [NSMutableString string];
    for (NSUInteger k = 0; k < 5000; k++)
        [body appendString:@"Some text with eq:main and more filler text here to make the line long enough, as lines in a thesis are.\n"];
    NSUInteger parts = getenv("TEXROOT_PARTS") ? (NSUInteger)atoi(getenv("TEXROOT_PARTS")) : 25;
    for (NSUInteger f = 0; f < parts; f++)
        Write([NSString stringWithFormat:@"big/part%02lu.tex", (unsigned long)f], [@"% !TEX root = ../thesis.tex\n" stringByAppendingString:body]);
    TSAdvancedFindController *controller = MakeController();
    controller.settings.findString = @"eq:main";
    controller.settings.replaceString = @"eq:central";
    NSURL *libraryDirectory = [NSURL fileURLWithPath:[Folder stringByAppendingPathComponent:@".sets4"] isDirectory:YES];
    TSTeXRootSearchWindowController *window = [[TSTeXRootSearchWindowController alloc] initWithFindController:controller library:[[TSMultipleReplaceLibrary alloc] initWithDirectory:libraryDirectory]];
    window.replaceAllHandler = ^(TSTeXRootSearchWindowController *c) {};
    DelayRunsAtOnce = YES;
    __block TSTeXRootSearchModel *model = nil;
    NSTimeInterval opening = LongestPause(^{
        [window openForRootURL:RootURL() environment:Environment() mode:TSTeXRootSearchModeReplace setName:nil];
        model = window.model;
    }, ^BOOL { return model.activity == TSTeXRootSearchActivityIdle && model.project && model.resultGeneration == model.generation && model.numberOfItems > 0; });
    printf("main thread: opening and listing %lu items: longest pause %.0f ms\n", (unsigned long)model.numberOfItems, opening * 1000);
    if (getenv("TEXROOT_PROFILE")) {
        CFAbsoluteTime t0 = CFAbsoluteTimeGetCurrent();
        NSUInteger n = model.numberOfIncludedItems;
        CFAbsoluteTime t1 = CFAbsoluteTimeGetCurrent();
        NSArray *r = model.results;
        CFAbsoluteTime t2 = CFAbsoluteTimeGetCurrent();
        [window.resultsList reload];
        CFAbsoluteTime t3 = CFAbsoluteTimeGetCurrent();
        [window.fileTree reload];
        CFAbsoluteTime t4 = CFAbsoluteTimeGetCurrent();
        [window updateFromModel];
        CFAbsoluteTime t5 = CFAbsoluteTimeGetCurrent();
        printf("profile: included %lu %.0f ms, results %lu %.0f ms, list reload %.0f ms, tree %.0f ms, update %.0f ms\n", (unsigned long)n, (t1-t0)*1000, (unsigned long)r.count, (t2-t1)*1000, (t3-t2)*1000, (t4-t3)*1000, (t5-t4)*1000);
    }
    Check(model.numberOfItems > parts * 5000, [NSString stringWithFormat:@"the big files have their matches (%lu)", (unsigned long)model.numberOfItems]);
    Check(opening < 0.1, [NSString stringWithFormat:@"opening keeps the main thread free (%.0f ms)", opening * 1000]);
    NSTimeInterval changing = LongestPause(^{ controller.settings.replaceString = @"eq:other"; },
                                           ^BOOL { return model.activity == TSTeXRootSearchActivityIdle && model.resultGeneration == model.generation; });
    printf("main thread: searching again: longest pause %.0f ms\n", changing * 1000);
    Check(changing < 0.1, [NSString stringWithFormat:@"searching again keeps the main thread free (%.0f ms)", changing * 1000]);
    TSTeXRootSearchFileResult *part = nil;
    for (TSTeXRootSearchFileResult *file in model.results)
        if (file.items.count >= 5000)
            part = file;
    CFAbsoluteTime start = CFAbsoluteTimeGetCurrent();
    [model setItems:@[part.items[5]] inFile:part included:NO];
    [window updateFromModel];
    NSTimeInterval toggling = CFAbsoluteTimeGetCurrent() - start;
    printf("main thread: one item off in a list of %lu: %.0f ms\n", (unsigned long)model.numberOfItems, toggling * 1000);
    Check(toggling < 0.1, [NSString stringWithFormat:@"turning an item off keeps the main thread free (%.0f ms)", toggling * 1000]);
    // An open 10 MB document with 100,000 matches (spec §2.9): listed up to the limit per file without stopping.
    NSMutableString *bigOpen = [NSMutableString stringWithString:@"% !TEX root = ../thesis.tex\n"];
    while (bigOpen.length < 10000000)
        [bigOpen appendString:@"eq:main eq:main eq:main eq:main eq:main eq:main eq:main eq:main eq:main eq:main and some more text\n"];
    OpenTexts[@"chapters/three.tex"] = bigOpen;
    NSTimeInterval openDocument = LongestPause(^{ [model documentsDidChange]; },
                                               ^BOOL { return model.activity == TSTeXRootSearchActivityIdle && model.resultGeneration == model.generation; });
    printf("main thread: an open 10 MB document with 100,000 matches: longest pause %.0f ms\n", openDocument * 1000);
    Check(openDocument < 0.1, [NSString stringWithFormat:@"an open 10 MB document keeps the main thread free (%.0f ms)", openDocument * 1000]);
    [OpenTexts removeAllObjects];
    start = CFAbsoluteTimeGetCurrent();
    [window.fileTree toggleRow:[window.fileTree.outlineView numberOfRows] - 1];
    [window updateFromModel];
    NSTimeInterval fileOff = CFAbsoluteTimeGetCurrent() - start;
    printf("main thread: one file off: %.0f ms\n", fileOff * 1000);
    Check(fileOff < 0.1, [NSString stringWithFormat:@"turning a file off keeps the main thread free (%.0f ms)", fileOff * 1000]);
    [window close];

    // The whole change of one item 20,000 lines long (Codex 3b F5): built without stopping the main thread.
    {
        NSMutableString *longText = [NSMutableString stringWithString:@"BEGIN\n"];
        for (NSUInteger k = 0; k < 20000; k++)
            [longText appendFormat:@"line %lu of a long environment\n", (unsigned long)k];
        [longText appendString:@"END"];
        OpenTexts[@"chapters/three.tex"] = [NSString stringWithFormat:@"%% !TEX root = ../thesis.tex\n%@\n", longText];
        TSTeXRootSearchWindowController *longWindow = [[TSTeXRootSearchWindowController alloc] initWithFindController:controller library:[[TSMultipleReplaceLibrary alloc] initWithDirectory:libraryDirectory]];
        controller.settings.options = TSRegexFindRegularExpression;
        controller.settings.findString = @"(?s)BEGIN.*?END";
        controller.settings.replaceString = @"$0!";
        [longWindow openForRootURL:RootURL() environment:Environment() mode:TSTeXRootSearchModeReplace setName:nil];
        TSTeXRootSearchModel *longModel = longWindow.model;
        Spin(^BOOL { return longModel.activity == TSTeXRootSearchActivityIdle && longModel.project && longModel.resultGeneration == longModel.generation && longModel.numberOfItems > 0; }, 60);
        [longWindow updateFromModel];
        TSTeXRootSearchFileResult *longFile = longModel.results.firstObject;
        NSInteger longRow = [longWindow.resultsList rowOfObject:longFile.items.firstObject];
        __block NSViewController *whole = nil;
        __block BOOL made = NO;
        NSTimeInterval showing = LongestPause(^{
            [longWindow.resultsList makeWholeChangeViewControllerForRow:longRow completion:^(NSViewController *controller) {
                // Shown as the popover shows it: in a window, laid out and drawn (offscreen).
                NSWindow *shown = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, controller.preferredContentSize.width, controller.preferredContentSize.height)
                                                              styleMask:NSWindowStyleMaskBorderless backing:NSBackingStoreBuffered defer:NO];
                shown.contentView = controller.view;
                [controller.view layoutSubtreeIfNeeded];
                [shown displayIfNeeded];
                whole = controller;
                made = YES;
            }];
        }, ^BOOL { return made; });
        NSString *afterText = nil;
        for (NSView *view in AllViews(whole.view))
            if ([view isKindOfClass:[NSTextView class]] && [view.accessibilityLabel isEqualToString:@"After"])
                afterText = ((NSTextView *)view).string;
        printf("main thread: the whole change of 20,000 lines: longest pause %.0f ms\n", showing * 1000);
        Check(showing < 0.1 && [afterText hasSuffix:@"END!"] && afterText.length > 500000,
              [NSString stringWithFormat:@"the whole change of 20,000 lines keeps the main thread free (%.0f ms) and has every line", showing * 1000]);
        [longWindow close];
        [OpenTexts removeAllObjects];
        controller.settings.options = 0;
        controller.settings.findString = @"eq:main";
        controller.settings.replaceString = @"eq:central";
    }

    // 1,000 files in folders 20 deep (spec §2.9): collected and searched without stopping the main thread.
    NSString *deep = @"deep";
    for (NSUInteger level = 0; level < 20; level++)
        deep = [deep stringByAppendingPathComponent:[NSString stringWithFormat:@"level%02lu", (unsigned long)level]];
    for (NSUInteger f = 0; f < 1000; f++) {
        NSString *folder = deep;
        for (NSUInteger cut = 0; cut < f % 20; cut++)
            folder = folder.stringByDeletingLastPathComponent;
        NSUInteger depth = folder.pathComponents.count;
        NSMutableString *up = [NSMutableString string];
        for (NSUInteger k = 0; k < depth; k++)
            [up appendString:@"../"];
        Write([folder stringByAppendingPathComponent:[NSString stringWithFormat:@"f%04lu.tex", (unsigned long)f]],
              [NSString stringWithFormat:@"%% !TEX root = %@thesis.tex\neq:main here\n", up]);
    }
    TSTeXRootSearchWindowController *deepWindow = [[TSTeXRootSearchWindowController alloc] initWithFindController:controller library:[[TSMultipleReplaceLibrary alloc] initWithDirectory:libraryDirectory]];
    __block TSTeXRootSearchModel *deepModel = nil;
    NSTimeInterval collecting = LongestPause(^{
        [deepWindow openForRootURL:RootURL() environment:Environment() mode:TSTeXRootSearchModeFind setName:nil];
        deepModel = deepWindow.model;
    }, ^BOOL { return deepModel.activity == TSTeXRootSearchActivityIdle && deepModel.project && deepModel.resultGeneration == deepModel.generation; });
    printf("main thread: collecting %lu files 20 folders deep: longest pause %.0f ms\n", (unsigned long)deepModel.project.files.count, collecting * 1000);
    Check(deepModel.project.files.count > 1000 && collecting < 0.1, [NSString stringWithFormat:@"1,000 files 20 deep keep the main thread free (%.0f ms)", collecting * 1000]);
    [deepWindow close];
    DelayRunsAtOnce = NO;
}

int main(int argc, const char *argv[])
{
    @autoreleasepool {
        TSInstallAppKitIsolation();
        [NSApplication sharedApplication];
        NSString *mode = argc > 1 ? @(argv[1]) : @"behavior";
        NSString *images = argc > 2 && argv[2][0] != '-' ? @(argv[2]) : nil;
        Pending = [NSMutableArray array];
        OpenTexts = [NSMutableDictionary dictionary];
        ReadOnly = [NSMutableSet set];
        SourceRequests = [NSMutableArray array];
        MakeProject();
        if ([mode isEqualToString:@"behavior"]) {
            TestModel();
            TestWindow(images);
            TestEntry();
        } else if ([mode isEqualToString:@"language"]) {
            TestLanguage();
        } else if ([mode isEqualToString:@"main-thread"]) {
            TestMainThread();
        }
        chmod([Folder stringByAppendingPathComponent:@"chapters/locked.tex"].fileSystemRepresentation, 0644);
        [NSFileManager.defaultManager removeItemAtPath:Folder error:NULL];
        if (failures)
            return 1;
        printf("PASS %s (%s)\n", mode.UTF8String, (NSBundle.mainBundle.preferredLocalizations.firstObject ?: @"en").UTF8String);
    }
    return 0;
}
