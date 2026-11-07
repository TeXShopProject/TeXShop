// Never learns, ignores or removes dictionary entries.
#import <Cocoa/Cocoa.h>
#import <objc/runtime.h>
#import "TSSpellSupport.h"
#import "TSSpellExclusions.h"
// An inert public-API checker prevents panel-frame and personal-dictionary writes.
#import "SessionChecker.h"
@implementation SessionChecker
+ (instancetype)sharedSpellChecker { static SessionChecker *checker; if(!checker) checker=[self new]; return checker; }
- (BOOL)hasLearnedWord:(NSString *)word { abort(); }
- (void)unlearnWord:(NSString *)word { abort(); }
- (NSString *)language { return @"en"; }
- (NSArray *)availableLanguages { return @[@"en"]; }
- (NSArray *)guessesForWordRange:(NSRange)range inString:(NSString *)string language:(NSString *)language inSpellDocumentWithTag:(NSInteger)tag { self.guessedWord=[string substringWithRange:range]; return self.guesses; }
- (void)updateSpellingPanelWithMisspelledWord:(NSString *)word { if (self.panelUpdate) self.panelUpdate(); }
- (NSRange)checkSpellingOfString:(NSString *)s startingAt:(NSInteger)start language:(NSString *)language
                          wrap:(BOOL)wrap inSpellDocumentWithTag:(NSInteger)tag wordCount:(NSInteger *)count {
    return [s rangeOfString:@"zzqq[ab]" options:NSRegularExpressionSearch range:NSMakeRange(start,s.length-start)];
}
@end
@interface SessionTextView : NSTextView @end
@implementation SessionTextView
- (void)showFindIndicatorForRange:(NSRange)range {}
@end
@interface SessionApplication : NSApplication
@property NSWindow *reviewWindow;
@property NSEvent *inputEvent;
@end
@implementation SessionApplication
- (NSWindow *)mainWindow { return self.reviewWindow; }
- (NSEvent *)currentEvent { return self.inputEvent; }
@end
@interface SessionWindow : NSWindow @end
@implementation SessionWindow
- (BOOL)canBecomeMainWindow { return YES; }
@end
static NSTextView *View(NSString *text) {
    SessionWindow *window = [[SessionWindow alloc] initWithContentRect:NSMakeRect(-20000,-20000,500,300)
        styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
    window.releasedWhenClosed = NO;
    NSTextView *view = [[SessionTextView alloc] initWithFrame:NSMakeRect(0,0,500,300)];
    window.contentView = view; view.string = text; view.allowsUndo = YES;
    view.continuousSpellCheckingEnabled=NO;view.grammarCheckingEnabled=NO;view.automaticSpellingCorrectionEnabled=NO;
    [window makeMainWindow]; [window makeFirstResponder:view];
    return view;
}
static NSTextField *Replacement(void) {
    for (NSView *view in SessionChecker.sharedSpellChecker.accessoryView.subviews)
        if ([view isKindOfClass:NSTextField.class]) return (NSTextField *)view;
    abort();
}
static void Review(NSTextView *v) {
    [(SessionApplication *)NSApp setReviewWindow:v.window]; [v.window makeMainWindow]; [v.window makeFirstResponder:v]; v.selectedRange=NSMakeRange(0,0);
    NSString *word=[TSSpellSupport findNextMisspellingInTextView:v mask:[[TSSpellExclusions sharedExclusions] maskForText:v.string]];
    NSCAssert(word.length, @"fixture must contain a misspelling");
    Replacement().stringValue=@"fixed";
}
// A synthetic panel exercises the production observer without modifying the
// system spelling panel, dictionaries, or user preferences.
@interface SuggestionPanel : NSPanel
@property BOOL testHidden;
@end
@implementation SuggestionPanel
- (BOOL)isVisible { return !self.testHidden; }
@end
@interface SuggestionSource : NSObject<NSTableViewDataSource>
@property id value;
@property NSInteger reads;
@property NSInteger rowCount;
@end
@implementation SuggestionSource
- (NSInteger)numberOfRowsInTableView:(NSTableView *)table { return self.rowCount; }
- (id)tableView:(NSTableView *)table objectValueForTableColumn:(NSTableColumn *)column row:(NSInteger)row {
    self.reads++; return self.value;
}
@end
// Match the standard spelling panel: selection does not transfer focus.
@interface SuggestionTable : NSTableView @end
@implementation SuggestionTable
- (BOOL)acceptsFirstResponder { return NO; }
@end
// A view-based/bindings-backed table need not implement the cell-value method.
@interface RowOnlySuggestionSource : NSObject<NSTableViewDataSource> @end
@implementation RowOnlySuggestionSource
- (NSInteger)numberOfRowsInTableView:(NSTableView *)table { return 2; }
@end
static NSEvent *CandidateKey(NSWindow *window, NSEventModifierFlags flags) {
    static NSTimeInterval serial=100;
    return [NSEvent keyEventWithType:NSEventTypeKeyDown location:NSZeroPoint modifierFlags:flags timestamp:serial++
        windowNumber:window.windowNumber context:nil characters:@"\uF701" charactersIgnoringModifiers:@"\uF701" isARepeat:NO keyCode:125];
}
static void ReviewThenInput(NSTextView *view, NSPanel *panel) {
    Review(view);
    [(SessionApplication *)NSApp setInputEvent:CandidateKey(panel,0)];
}
static void TestSuggestionSync(void) {
    SessionApplication *app=(SessionApplication *)NSApp;
    SuggestionPanel *panel=[[SuggestionPanel alloc] initWithContentRect:NSMakeRect(-20000,-20000,430,300)
        styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
    SessionChecker.sharedSpellChecker.spellingPanel=panel;
    NSTableView *table=[[SuggestionTable alloc] initWithFrame:NSMakeRect(0,0,400,200)];
    [table addTableColumn:[[NSTableColumn alloc] initWithIdentifier:@"candidate"]];
    SuggestionSource *source=[SuggestionSource new]; source.value=@"suggestion"; source.rowCount=2;
    table.dataSource=source; [panel.contentView addSubview:table]; [table reloadData];
    [table selectRowIndexes:[NSIndexSet indexSetWithIndex:0] byExtendingSelection:NO];
    [panel makeFirstResponder:panel];
    NSCAssert(!table.acceptsFirstResponder && panel.firstResponder != table,
              @"realistic suggestion table must not receive focus");
    // Start Find Next with an event that would otherwise qualify as candidate input.
    app.inputEvent=CandidateKey(panel,0);
    NSTextView *view=View(@"zzqqa zzqqa"); Review(view);
    void (^notify)(void)=^{[NSNotificationCenter.defaultCenter postNotificationName:NSTableViewSelectionDidChangeNotification object:table];};
    SessionChecker.sharedSpellChecker.panelUpdate=^{
        NSEvent *saved=app.inputEvent;
        // A nested run loop can deliver another event while AppKit is updating.
        app.inputEvent=CandidateKey(panel,0); notify(); app.inputEvent=saved;
    };
    [TSSpellSupport findNextMisspellingInTextView:view mask:[[TSSpellExclusions sharedExclusions] maskForText:view.string]];
    NSCAssert(Replacement().stringValue.length==0, @"panel refresh does not preload a candidate");
    SessionChecker.sharedSpellChecker.panelUpdate=nil;
    // Rebuilding candidates after the synchronous update has returned must not
    // reuse the input that started Find Next, even if it has no Command flag.
    notify();
    NSCAssert(Replacement().stringValue.length==0, @"same event after Find Next ignored");
    app.inputEvent=CandidateKey(panel,0);
    source.reads=0; notify();
    NSCAssert(source.reads==1 && [Replacement().stringValue isEqual:@"suggestion"], @"candidate copies once");
    NSCAssert([view.string isEqual:@"zzqqa zzqqa"], @"selection does not replace document text");
    Replacement().stringValue=@"manual"; source.value=@"next"; notify();
    NSCAssert([Replacement().stringValue isEqual:@"next"], @"another selection replaces manual field content");
    [TSSpellSupport changeAll:nil];
    NSCAssert([view.string isEqual:@"next next"], @"copied candidate works with Change All");
    [view.undoManager undo];
    NSCAssert([view.string isEqual:@"zzqqa zzqqa"], @"candidate Change All is undoable");
    ReviewThenInput(view,panel); view.selectedRange=NSMakeRange(6,5); notify();
    NSCAssert([Replacement().stringValue isEqual:@"fixed"], @"stale selection ignored");
    ReviewThenInput(view,panel); view.string=@"zzqqa changed"; notify();
    NSCAssert([Replacement().stringValue isEqual:@"fixed"], @"edited document ignored");
    ReviewThenInput(view,panel); app.reviewWindow=View(@"another document").window; notify();
    NSCAssert([Replacement().stringValue isEqual:@"fixed"], @"other document ignored");
    ReviewThenInput(view,panel); app.inputEvent=nil; notify();
    NSCAssert([Replacement().stringValue isEqual:@"fixed"], @"non-input selection ignored");
    app.inputEvent=CandidateKey(panel,0);
    NSEvent *keyboard=app.inputEvent;
    app.inputEvent=[NSEvent mouseEventWithType:NSEventTypeLeftMouseUp location:NSMakePoint(20,20)
        modifierFlags:0 timestamp:0 windowNumber:panel.windowNumber context:nil eventNumber:1 clickCount:1 pressure:0];
    notify(); NSCAssert([Replacement().stringValue isEqual:@"next"], @"mouse selection copies");
    Replacement().stringValue=@"fixed";
    app.inputEvent=[NSEvent mouseEventWithType:NSEventTypeLeftMouseUp location:NSMakePoint(425,290)
        modifierFlags:0 timestamp:0 windowNumber:panel.windowNumber context:nil eventNumber:2 clickCount:1 pressure:0];
    notify(); NSCAssert([Replacement().stringValue isEqual:@"fixed"], @"click outside candidates ignored");
    app.inputEvent=keyboard;
    panel.testHidden=YES; notify();
    NSCAssert([Replacement().stringValue isEqual:@"fixed"], @"hidden panel ignored");
    panel.testHidden=NO;
    app.inputEvent=nil; table.allowsMultipleSelection=YES;
    [table selectRowIndexes:[NSIndexSet indexSetWithIndexesInRange:NSMakeRange(0,2)] byExtendingSelection:NO];
    app.inputEvent=keyboard; notify();
    NSCAssert([Replacement().stringValue isEqual:@"fixed"], @"multiple candidates ignored");
    [table deselectAll:nil]; notify();
    NSCAssert([Replacement().stringValue isEqual:@"fixed"], @"empty selection ignored");
    app.inputEvent=nil;
    [table selectRowIndexes:[NSIndexSet indexSetWithIndex:0] byExtendingSelection:NO];
    app.inputEvent=keyboard;
    NSWindow *otherWindow=View(@"unrelated").window;
    app.inputEvent=CandidateKey(otherWindow,0); notify();
    NSCAssert([Replacement().stringValue isEqual:@"fixed"], @"other window event ignored");
    app.inputEvent=[NSEvent mouseEventWithType:NSEventTypeRightMouseUp location:NSMakePoint(20,20)
        modifierFlags:0 timestamp:0 windowNumber:panel.windowNumber context:nil eventNumber:3 clickCount:1 pressure:0];
    notify(); NSCAssert([Replacement().stringValue isEqual:@"fixed"], @"unsupported event type ignored");
    app.inputEvent=CandidateKey(panel,NSEventModifierFlagCommand); notify();
    NSCAssert([Replacement().stringValue isEqual:@"fixed"], @"menu shortcut ignored");
    app.inputEvent=keyboard;
    [table removeFromSuperview]; [otherWindow.contentView addSubview:table]; notify();
    NSCAssert([Replacement().stringValue isEqual:@"fixed"], @"unrelated window ignored");
    [table removeFromSuperview]; [panel.contentView addSubview:table]; [panel makeFirstResponder:table];
    source.value=@42; notify();
    NSCAssert([Replacement().stringValue isEqual:@"fixed"], @"unsupported table values ignored");
    source.value=@""; notify();
    NSCAssert([Replacement().stringValue isEqual:@"fixed"], @"empty candidate leaves manual replacement intact");
    RowOnlySuggestionSource *rowOnly=[RowOnlySuggestionSource new];
    app.inputEvent=nil;
    table.dataSource=rowOnly; [table reloadData];
    [table selectRowIndexes:[NSIndexSet indexSetWithIndex:0] byExtendingSelection:NO];
    app.inputEvent=CandidateKey(panel,0);
    NSCAssert(table.numberOfSelectedRows==1 && panel.firstResponder!=table &&
              ![table.dataSource respondsToSelector:@selector(tableView:objectValueForTableColumn:row:)],
              @"missing-method fixture must otherwise qualify for copying");
    notify();
    NSCAssert([Replacement().stringValue isEqual:@"fixed"], @"unsupported data source leaves manual replacement intact");
    app.inputEvent=nil;
    table.dataSource=source; [table reloadData];
    [table selectRowIndexes:[NSIndexSet indexSetWithIndex:0] byExtendingSelection:NO];
    app.inputEvent=CandidateKey(panel,0);
    source.value=@"valid";
    [table addTableColumn:[[NSTableColumn alloc] initWithIdentifier:@"other"]]; notify();
    NSCAssert([Replacement().stringValue isEqual:@"fixed"], @"unexpected table shape ignored");
    [table removeTableColumn:table.tableColumns.lastObject];
    [panel.contentView addSubview:SessionChecker.sharedSpellChecker.accessoryView];
    [panel makeFirstResponder:Replacement()];
    NSCAssert(Replacement().currentEditor == panel.firstResponder, @"replacement editor fixture");
    notify();
    NSCAssert([Replacement().stringValue isEqual:@"fixed"], @"arrows in a text editor must not copy candidates");
    [panel makeFirstResponder:panel];
    app.inputEvent=[NSEvent keyEventWithType:NSEventTypeKeyDown location:NSZeroPoint modifierFlags:0 timestamp:1000
        windowNumber:panel.windowNumber context:nil characters:@"x" charactersIgnoringModifiers:@"x" isARepeat:NO keyCode:7];
    notify();
    NSCAssert([Replacement().stringValue isEqual:@"fixed"], @"typing must not copy candidates");
    // The real panel keeps its word field focused and moves the list from there.
    NSTextField *wordField=[[NSTextField alloc] initWithFrame:NSMakeRect(0,250,200,22)];
    [panel.contentView addSubview:wordField]; [panel makeFirstResponder:wordField];
    NSCAssert([panel.firstResponder isKindOfClass:NSTextView.class] && Replacement().currentEditor==nil, @"word field fixture");
    app.inputEvent=CandidateKey(panel,0); notify();
    NSCAssert([Replacement().stringValue isEqual:@"valid"], @"arrow from the panel word field copies");
    Replacement().stringValue=@"fixed";
    app.inputEvent=[NSEvent keyEventWithType:NSEventTypeKeyDown location:NSZeroPoint modifierFlags:0 timestamp:2000
        windowNumber:panel.windowNumber context:nil characters:@"\uF700" charactersIgnoringModifiers:@"\uF700" isARepeat:NO keyCode:126];
    notify();
    NSCAssert([Replacement().stringValue isEqual:@"valid"], @"up arrow copies");
    Replacement().stringValue=@"fixed";
    [wordField removeFromSuperview]; [panel makeFirstResponder:panel];
    app.inputEvent=keyboard;
    NSView *ownAccessory=SessionChecker.sharedSpellChecker.accessoryView;
    SessionChecker.sharedSpellChecker.accessoryView=[NSView new]; source.reads=0; notify();
    NSCAssert(source.reads==0, @"replaced accessory ignored");
    SessionChecker.sharedSpellChecker.accessoryView=ownAccessory;
    [TSSpellSupport preferencesDidChange]; source.reads=0; notify();
    NSCAssert(source.reads==0, @"mode change removes observer");
    ReviewThenInput(view,panel); source.reads=0; notify();
    NSCAssert(source.reads==1 && [Replacement().stringValue isEqual:@"valid"], @"reinstall has exactly one observer");
    // Find Next only preloads a sole, selected suggestion. This also exercises
    // synchronous AppKit notifications while the panel is being populated.
    app.inputEvent=nil;
    SessionChecker.sharedSpellChecker.panelUpdate=^{
        [table reloadData];
        [table selectRowIndexes:[NSIndexSet indexSetWithIndex:0] byExtendingSelection:NO];
        notify();
    };
    source.rowCount=1; source.value=@"sole suggestion";
    SessionChecker.sharedSpellChecker.guesses=@[@"sole suggestion"];
    [TSSpellSupport findNextMisspellingInTextView:view mask:[[TSSpellExclusions sharedExclusions] maskForText:view.string]];
    NSCAssert([Replacement().stringValue isEqual:@"sole suggestion"], @"sole selected candidate is preloaded");
    NSCAssert([view.string isEqual:@"zzqqa changed"], @"preloading leaves document unchanged");
    Replacement().stringValue=@"hand edited"; notify();
    NSCAssert([Replacement().stringValue isEqual:@"hand edited"], @"later non-input update preserves manual entry");
    void (^findNext)(void)=^{
        [TSSpellSupport findNextMisspellingInTextView:view mask:[[TSSpellExclusions sharedExclusions] maskForText:view.string]];
    };
    NSCAssert([SessionChecker.sharedSpellChecker.guessedWord isEqual:@"zzqqa"], @"query uses current misspelled word");
    panel.testHidden=YES; findNext();
    NSCAssert(Replacement().stringValue.length==0, @"hidden panel must not preload");
    panel.testHidden=NO;
    view.string=@"zzqqb changed";
    SessionChecker.sharedSpellChecker.guesses=@[@"new suggestion"]; findNext();
    NSCAssert([SessionChecker.sharedSpellChecker.guessedWord isEqual:@"zzqqb"], @"next word is queried afresh");
    NSCAssert(Replacement().stringValue.length==0, @"stale sole candidate must not preload");
    source.value=@"new suggestion"; findNext();
    NSCAssert([Replacement().stringValue isEqual:@"new suggestion"], @"updated sole candidate replaces previous one");
    SessionChecker.sharedSpellChecker.guesses=@[@"new suggestion",@"alternative"]; findNext();
    NSCAssert(Replacement().stringValue.length==0, @"stale single row with multiple current guesses must not preload");
    SessionChecker.sharedSpellChecker.guesses=nil; findNext();
    NSCAssert(Replacement().stringValue.length==0, @"unavailable current guesses must not preload");
    SessionChecker.sharedSpellChecker.guesses=@[@"new suggestion"];
    [table addTableColumn:[[NSTableColumn alloc] initWithIdentifier:@"extra"]]; findNext();
    NSCAssert(Replacement().stringValue.length==0, @"unexpected table shape must not preload");
    [table removeTableColumn:table.tableColumns.lastObject];
    ownAccessory=SessionChecker.sharedSpellChecker.accessoryView;
    void (^populate)(void)=SessionChecker.sharedSpellChecker.panelUpdate;
    SessionChecker.sharedSpellChecker.panelUpdate=^{ populate(); app.reviewWindow=otherWindow; };
    findNext();
    NSCAssert(Replacement().stringValue.length==0, @"changed review must not preload");
    app.reviewWindow=view.window;
    SessionChecker.sharedSpellChecker.panelUpdate=^{ populate(); SessionChecker.sharedSpellChecker.accessoryView=[NSView new]; };
    findNext();
    SessionChecker.sharedSpellChecker.accessoryView=ownAccessory;
    NSCAssert(Replacement().stringValue.length==0, @"replaced accessory must not preload");
    SessionChecker.sharedSpellChecker.panelUpdate=populate;
    source.rowCount=2;
    [TSSpellSupport findNextMisspellingInTextView:view mask:[[TSSpellExclusions sharedExclusions] maskForText:view.string]];
    NSCAssert(Replacement().stringValue.length==0, @"multiple suggestions must not be preloaded");
    source.rowCount=0;
    [TSSpellSupport findNextMisspellingInTextView:view mask:[[TSSpellExclusions sharedExclusions] maskForText:view.string]];
    NSCAssert(Replacement().stringValue.length==0, @"no suggestions clears the previous replacement");
    source.rowCount=1;
    SessionChecker.sharedSpellChecker.panelUpdate=^{
        [table reloadData]; [table deselectAll:nil];
    };
    [TSSpellSupport findNextMisspellingInTextView:view mask:[[TSSpellExclusions sharedExclusions] maskForText:view.string]];
    NSCAssert(Replacement().stringValue.length==0, @"unselected sole candidate must not be preloaded");
    SessionChecker.sharedSpellChecker.panelUpdate=^{
        [table selectRowIndexes:[NSIndexSet indexSetWithIndex:0] byExtendingSelection:NO];
        Replacement().stringValue=@"nested manual entry";
    };
    [TSSpellSupport findNextMisspellingInTextView:view mask:[[TSSpellExclusions sharedExclusions] maskForText:view.string]];
    NSCAssert([Replacement().stringValue isEqual:@"nested manual entry"], @"nested input is not overwritten");
    SessionChecker.sharedSpellChecker.panelUpdate=nil;
    [TSSpellSupport preferencesDidChange]; app.inputEvent=nil;
    puts("PASS: suggestion sync, explicit Change All/Undo, stale-state rejection and observer lifecycle");
}
int main(void) {@autoreleasepool {
    [SessionApplication sharedApplication]; [NSApp setActivationPolicy:NSApplicationActivationPolicyProhibited];
    NSTextView *a=View(@"zzqqa zzqqa"), *b=View(@"zzqqb zzqqb");
    Review(a); [(SessionApplication *)NSApp setReviewWindow:b.window]; [b.window makeMainWindow]; [b.window makeFirstResponder:b];
    [TSSpellSupport changeAll:nil];
    NSCAssert([a.string isEqual:@"zzqqa zzqqa"] && [b.string isEqual:@"zzqqb zzqqb"], @"switch must invalidate replacement");
    Review(a); [a.textStorage replaceCharactersInRange:NSMakeRange(6,1) withString:@"x"];
    [TSSpellSupport changeAll:nil]; NSCAssert([a.string isEqual:@"zzqqa xzqqa"], @"edit must invalidate replacement");
    a.string=@"zzqqa zzqqa"; Review(a); a.selectedRange=NSMakeRange(6,5);
    [TSSpellSupport changeAll:nil];
    NSCAssert([a.string isEqual:@"zzqqa zzqqa"], @"selection-only change must invalidate replacement");
    Review(a); NSTextView *split=[[SessionTextView alloc] initWithFrame:NSMakeRect(0,0,10,10)];
    [a.window.contentView addSubview:split]; [a.window makeFirstResponder:split];
    [TSSpellSupport changeAll:nil];
    NSCAssert([a.string isEqual:@"zzqqa zzqqa"], @"first-responder-only change must invalidate replacement");
    [split removeFromSuperview];
    a.string=@"zzqqa zzqqa"; Review(a); [TSSpellSupport changeAll:nil];
    NSCAssert([a.string isEqual:@"fixed fixed"], @"current review must replace both words");
    [a.undoManager undo]; NSCAssert([a.string isEqual:@"zzqqa zzqqa"], @"single undo must restore original");
    a.selectedRange=NSMakeRange(1,0);
    NSDate *until=[NSDate dateWithTimeIntervalSinceNow:.8];
    while(until.timeIntervalSinceNow>0) [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.01]];
    NSCAssert(NSEqualRanges(a.selectedRange,NSMakeRange(1,0)), @"no stale delayed selection");
    Review(a);
    [TSSpellSupport preferencesDidChange];
    NSCAssert(SessionChecker.sharedSpellChecker.accessoryView == nil, @"mode change removes our replacement field");
    [TSSpellSupport changeAll:nil];
    NSCAssert([a.string isEqual:@"zzqqa zzqqa"], @"mode change invalidates the pending replacement");
    Review(a);
    [TSSpellSupport changeAll:nil];
    NSCAssert([a.string isEqual:@"fixed fixed"], @"review works again after a mode change");
    NSView *otherAccessory = [NSView new];
    SessionChecker.sharedSpellChecker.accessoryView = otherAccessory;
    [TSSpellSupport preferencesDidChange];
    NSCAssert(SessionChecker.sharedSpellChecker.accessoryView == otherAccessory, @"do not remove someone else's accessory");
    TestSuggestionSync();
    puts("PASS: switched/edited documents and mode changes protected; current Change All and Undo work");
}return 0;}
