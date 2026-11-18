// Edit › Marks › Insert Mark and the two commands that delete a mark change the text as typing does, in a
// document and in the Experiment source: Undo puts the text back, and only the mark (an Undo after them does not
// take other characters away), Redo does them again, and the document counts as edited. Nothing is shown on screen.
#import <Cocoa/Cocoa.h>
#import "TestAppKitIsolation.h"
#define REQUIRE(...) do { if (!(__VA_ARGS__)) { fprintf(stderr, "FAIL %s %d: %s\n", where, __LINE__, #__VA_ARGS__); exit(1); } } while (0)
NSString *placeholderString = @"•", *startcommentString = @"•‹", *endcommentString = @"›";
static const char *where = "";

@interface UndoSource : NSObject <NSTextViewDelegate>
@property (strong) NSUndoManager *manager;
@property NSUInteger changes;
@end
@implementation UndoSource
- (NSUndoManager *)undoManagerForTextView:(NSTextView *)view { return self.manager; }
// The document recolors and counts the text when it is told of a change (didChangeText).
- (void)textDidChange:(NSNotification *)notification { self.changes++; }
@end

// The document's methods, with its text view.
@interface DocumentMarks : NSObject { @public NSTextView *textView; }
@end
@implementation DocumentMarks
DOCUMENT_METHODS
@end

// The Experiment source's methods, on the text view itself.
@interface ScrapMarks : NSTextView
@end
@implementation ScrapMarks
SCRAP_METHODS
@end

@interface EditedDocument : NSDocument
@end
@implementation EditedDocument
- (NSData *)dataOfType:(NSString *)type error:(NSError **)error { return [NSData data]; }
@end

static NSUndoManager *undo;
static NSTextView *view;
static id marks;
static UndoSource *source;

static void Fresh(BOOL experiment, NSString *text, NSRange selection, NSUndoManager *manager)
{
    undo = manager;
    undo.groupsByEvent = NO;
    source = [UndoSource new];
    source.manager = undo;
    view = experiment ? [[ScrapMarks alloc] initWithFrame:NSMakeRect(0, 0, 300, 100)] : [[NSTextView alloc] initWithFrame:NSMakeRect(0, 0, 300, 100)];
    view.allowsUndo = YES;
    view.richText = NO;
    view.delegate = source;
    view.string = text;
    view.selectedRange = selection;
    if (experiment) {
        marks = view;
    } else {
        DocumentMarks *document = [DocumentMarks new];
        document->textView = view;
        marks = document;
    }
}

// One user action: an undo group, as the event loop makes one.
static void Act(void (^action)(void))
{
    [undo beginUndoGrouping];
    action();
    [undo endUndoGrouping];
}

static void Check(BOOL experiment)
{
    where = experiment ? "Experiment" : "document";
    // Typing, then a mark at the start of the line, then Undo twice: the mark goes, then the typing, and nothing else.
    Fresh(experiment, @"x^2 + y^2 = r^2", NSMakeRange(3, 0), [NSUndoManager new]);
    Act(^{ [view insertText:@" + 2xy" replacementRange:view.selectedRange]; });
    REQUIRE([view.string isEqual:@"x^2 + 2xy + y^2 = r^2"]);
    view.selectedRange = NSMakeRange(0, 0);
    Act(^{ [marks placeBullet:nil]; });
    REQUIRE([view.string isEqual:@"•x^2 + 2xy + y^2 = r^2"] && NSEqualRanges(view.selectedRange, NSMakeRange(1, 0)));
    REQUIRE(undo.canUndo && [undo.undoActionName isEqual:@"Insert Mark"]);
    [undo undo];
    REQUIRE([view.string isEqual:@"x^2 + 2xy + y^2 = r^2"]);
    [undo undo];
    REQUIRE([view.string isEqual:@"x^2 + y^2 = r^2"]);
    [undo redo];
    [undo redo];
    REQUIRE([view.string isEqual:@"•x^2 + 2xy + y^2 = r^2"]);

    // Insert Mark replaces the selection, and Undo brings it back.
    Fresh(experiment, @"a sel b", NSMakeRange(2, 3), [NSUndoManager new]);
    Act(^{ [marks placeBullet:nil]; });
    REQUIRE([view.string isEqual:@"a • b"] && NSEqualRanges(view.selectedRange, NSMakeRange(3, 0)) && source.changes == 1);
    [undo undo];
    REQUIRE([view.string isEqual:@"a sel b"]);

    // Next Mark (Del): the mark goes and its note is selected; Undo puts the mark back.
    NSString *text = @"a •‹one› b •‹two› c";
    Fresh(experiment, text, NSMakeRange(0, 0), [NSUndoManager new]);
    Act(^{ [marks doNextBulletAndDelete:nil]; });
    REQUIRE([view.string isEqual:@"a ‹one› b •‹two› c"] && NSEqualRanges(view.selectedRange, NSMakeRange(2, 5)));
    REQUIRE([undo.undoActionName isEqual:@"Delete Mark"] && source.changes == 1);
    [undo undo];
    REQUIRE([view.string isEqual:text]);
    [undo redo];
    REQUIRE([view.string isEqual:@"a ‹one› b •‹two› c"]);

    // Previous Mark (Del), from the end.
    Fresh(experiment, text, NSMakeRange(text.length, 0), [NSUndoManager new]);
    Act(^{ [marks doPreviousBulletAndDelete:nil]; });
    REQUIRE([view.string isEqual:@"a •‹one› b ‹two› c"] && NSEqualRanges(view.selectedRange, NSMakeRange(11, 5)));
    REQUIRE([undo.undoActionName isEqual:@"Delete Mark"] && source.changes == 1);
    [undo undo];
    REQUIRE([view.string isEqual:text]);

    // A mark that is deleted after typing: Undo restores the mark, then the typing, at their places.
    Fresh(experiment, @"ab •c", NSMakeRange(2, 0), [NSUndoManager new]);
    Act(^{ [view insertText:@"XY" replacementRange:view.selectedRange]; });
    view.selectedRange = NSMakeRange(0, 0);
    Act(^{ [marks doNextBulletAndDelete:nil]; });
    REQUIRE([view.string isEqual:@"abXY c"]);
    [undo undo];
    REQUIRE([view.string isEqual:@"abXY •c"]);
    [undo undo];
    REQUIRE([view.string isEqual:@"ab •c"]);

    // The document whose undo manager the source uses counts as edited.
    EditedDocument *document = [EditedDocument new];
    document.hasUndoManager = YES;
    Fresh(experiment, @"abc", NSMakeRange(1, 0), document.undoManager);
    REQUIRE(!document.isDocumentEdited);
    Act(^{ [marks placeBullet:nil]; });
    REQUIRE([view.string isEqual:@"a•bc"] && document.isDocumentEdited);
    [undo undo];
    REQUIRE([view.string isEqual:@"abc"] && !document.isDocumentEdited);
    printf("PASS: %s: Insert Mark and the mark deletions undo and redo, and leave other text to its own Undo\n", where);
}

int main(int argc, char **argv) { @autoreleasepool {
    TSInstallAppKitIsolation();
    [NSApplication sharedApplication];
    Check(NO);
    Check(YES);
} return 0; }
