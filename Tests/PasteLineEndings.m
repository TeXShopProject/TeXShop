// Pasted text gets LF line endings when ConvertLF is on (the default), in every document, not only in the
// Japanese modes, and in the Experiment source; so does the clipboard text that #PASTE# puts in macros and command
// completion. In documents the Japanese modes still turn backslashes into yen signs, or yen signs into backslashes;
// in the Experiment source both stay as they were pasted, as before. The key bindings checked for pasting apply in
// both while key bindings are on, rows with a placeholder or a mark never do, and #PASTE# keeps the clipboard text.
// Undo takes a paste away. Nothing is shown on screen, and the clipboard is a private pasteboard.
#import <Cocoa/Cocoa.h>
#import <OgreKit/OgreKit.h>
#import "TestAppKitIsolation.h"
#import "NSMutableString-Extras.h"
#import "GlobalData.h"
#define REQUIRE(...) do { if (!(__VA_ARGS__)) { fprintf(stderr, "FAIL %s %d: %s\n", where, __LINE__, #__VA_ARGS__); exit(1); } } while (0)
static const char *where = "";
typedef enum { kNoFilterMode = 0, kMacJapaneseFilterMode = 1, kOtherJapaneseFilterMode = 2 } TSFilterMode;
static TSFilterMode g_shouldFilter = kNoFilterMode;
#define SUD TSIsolatedAppKitDefaults
static NSString *ConvertLFKey = @"ConvertLF";
static NSString *yenString = @"\u00a5";
NSMutableString *filterBackslashToYen(NSString *aString);
NSMutableString *filterYenToBackslash(NSString *aString);
FILTERS

@interface NSTextView (TeXShop)
- (BOOL)pasteFilteredTextFromPasteboard:(NSPasteboard *)pboard type:(NSString *)type japaneseFilter:(BOOL)japaneseFilter keyBindings:(BOOL)keyBindings;
@end

// The document's Key Bindings switch.
static BOOL keyBindingsOn = NO;
@interface StubDocument : NSObject @end
@implementation StubDocument
- (BOOL)isDoAutoCompleteEnabled { return keyBindingsOn; }
@end
@implementation NSTextView (TeXShop)
CATEGORY
@end

// The document source (TSTextView) and the Experiment source (ScrapTextView), with their production paste methods.
@interface DocumentText : NSTextView @end
@implementation DocumentText
- (id)document { return [StubDocument new]; }
DOCUMENT_PASTE
@end
@interface ScrapText : NSTextView @end
@implementation ScrapText
- (id)document { return [StubDocument new]; }
SCRAP_PASTE
@end

@interface UndoSource : NSObject <NSTextViewDelegate>
@property (strong) NSUndoManager *manager;
@end
@implementation UndoSource
- (NSUndoManager *)undoManagerForTextView:(NSTextView *)view { return self.manager; }
@end

static NSPasteboard *clipboard;
static id PrivateGeneralPasteboard(id receiver, SEL selector) { return clipboard; }

static void Clip(NSString *text)
{
    [clipboard clearContents];
    [clipboard setString:text forType:NSPasteboardTypeString];
}

// The text of a view after pasting the clipboard into "x|y", and whether Undo puts "xy" back.
static NSString *Paste(Class kind, NSString *text, BOOL *undone)
{
    Clip(text);
    NSUndoManager *undo = [NSUndoManager new];
    undo.groupsByEvent = NO;
    UndoSource *source = [UndoSource new];
    source.manager = undo;
    NSTextView *view = [[kind alloc] initWithFrame:NSMakeRect(0, 0, 300, 100)];
    view.richText = NO;
    view.allowsUndo = YES;
    view.delegate = source;
    view.string = @"xy";
    view.selectedRange = NSMakeRange(1, 0);
    [undo beginUndoGrouping];
    [view paste:nil];
    [undo endUndoGrouping];
    NSString *pasted = [view.string copy];
    [undo undo];
    if (undone) *undone = [view.string isEqualToString:@"xy"];
    return pasted;
}

int main(int argc, char **argv) { @autoreleasepool {
    TSInstallAppKitIsolation();
    [NSApplication sharedApplication];
    clipboard = [NSPasteboard pasteboardWithUniqueName];
    method_setImplementation(class_getClassMethod(NSPasteboard.class, @selector(generalPasteboard)), (IMP)PrivateGeneralPasteboard);
    REQUIRE(NSPasteboard.generalPasteboard == clipboard);
    NSString *endings = @"a\r\nb\rc\u2028d\u2029e\nf";
    for (Class kind in @[DocumentText.class, ScrapText.class]) {
        where = kind == DocumentText.class ? "document" : "Experiment";
        BOOL undone = NO;
        g_shouldFilter = kNoFilterMode;
        [SUD setBool:YES forKey:ConvertLFKey];
        REQUIRE([Paste(kind, endings, &undone) isEqualToString:@"xa\nb\nc\nd\ne\nfy"] && undone);
        REQUIRE([Paste(kind, @"plain \\text", &undone) isEqualToString:@"xplain \\texty"] && undone);
        // ConvertLF off: the text keeps its line endings.
        [SUD setBool:NO forKey:ConvertLFKey];
        REQUIRE([Paste(kind, endings, &undone) isEqualToString:[NSString stringWithFormat:@"x%@y", endings]] && undone);
        // The Japanese modes, with and without ConvertLF: a document turns the yen signs or the backslashes into the
        // mode's, the Experiment source keeps both, as it did before.
        BOOL document = kind == DocumentText.class;
        for (int convert = 0; convert <= 1; convert++) {
            [SUD setBool:convert forKey:ConvertLFKey];
            NSString *lf = convert ? @"\n" : @"\r\n";
            g_shouldFilter = kMacJapaneseFilterMode;
            NSString *expected = [NSString stringWithFormat:@"x%@\u00a5a%@by", document ? @"\u00a5" : @"\\", lf];
            REQUIRE([Paste(kind, @"\\\u00a5a\r\nb", &undone) isEqualToString:expected] && undone);
            REQUIRE([Paste(kind, @"\\\u00a5", &undone) isEqualToString:document ? @"x\u00a5\u00a5y" : @"x\\\u00a5y"] && undone);
            g_shouldFilter = kOtherJapaneseFilterMode;
            expected = [NSString stringWithFormat:@"x\\%@a%@by", document ? @"\\" : @"\u00a5", lf];
            REQUIRE([Paste(kind, @"\\\u00a5a\r\nb", &undone) isEqualToString:expected] && undone);
            REQUIRE([Paste(kind, @"\\\u00a5", &undone) isEqualToString:document ? @"x\\\\y" : @"x\\\u00a5y"] && undone);
        }
        [SUD setBool:YES forKey:ConvertLFKey];
        g_shouldFilter = kNoFilterMode;
        printf("PASS: %s: a paste gets LF line endings with ConvertLF, keeps them without, and undoes\n", where);

        // Key bindings checked for pasting: each input character becomes its output, as one paste for Undo, with
        // and without ConvertLF; not while key bindings are off; never a row with a placeholder or a mark.
        GlobalData *data = [GlobalData sharedGlobalData];
        data.g_autocompletionDictionary = @{@"\u00a5": @"\\", @"\u2265": @"\\geq ", @"\u00a7": @"\\S", @"{": @"{#INS#}", @"\u2020": @"\\dag\u2022", @"^": @"^{#SEL#}", @"\"": @"#PASTE#", @"\u00e9": @"\\'e", @"ab": @"[ab]"};
        data.g_autocompletionPasteKeys = @[@"\u00a5", @"\u2265", @"{", @"\u2020", @"^", @"\"", @"\u00e9", @"ab", @"gone"];
        NSString *source = @"\u00a5alpha\u2265{x}\u2020^\"\u00a7 e\u0301\u00e9 ab \u00a5\u0301\r\n";
        for (int convert = 0; convert <= 1; convert++) {
            [SUD setBool:convert forKey:ConvertLFKey];
            keyBindingsOn = YES;
            NSString *expected = [NSString stringWithFormat:@"x\\alpha\\geq {x}\u2020^\"\u00a7 e\u0301\\'e [ab] \u00a5\u0301%@y", convert ? @"\n" : @"\r\n"];
            REQUIRE([Paste(kind, source, &undone) isEqualToString:expected] && undone);
            keyBindingsOn = NO;
            expected = [NSString stringWithFormat:@"x%@y", convert ? [source stringByReplacingOccurrencesOfString:@"\r\n" withString:@"\n"] : source];
            REQUIRE([Paste(kind, source, &undone) isEqualToString:expected] && undone);
        }
        // Before the yen filter of a Japanese mode, so that the output is written as the mode writes it.
        keyBindingsOn = YES;
        g_shouldFilter = kMacJapaneseFilterMode;
        REQUIRE([Paste(kind, @"\u2265", &undone) isEqualToString:document ? @"x\u00a5geq y" : @"x\\geq y"] && undone);
        g_shouldFilter = kNoFilterMode;
        keyBindingsOn = NO;
        [SUD setBool:YES forKey:ConvertLFKey];
        printf("PASS: %s: a paste gets the key bindings checked for pasting while key bindings are on, without placeholders and marks\n", where);
    }
    // #PASTE# keeps the clipboard text: the key bindings are not applied inside a key binding or a macro.
    where = "#PASTE# key bindings";
    Clip(@"\u00a5");
    NSMutableString *kept = [@"#PASTE#" mutableCopy];
    [kept replacePasteMarkersWithClipboardText];
    REQUIRE([kept isEqualToString:@"\u00a5"]);
    [GlobalData sharedGlobalData].g_autocompletionPasteKeys = @[];
    // #PASTE# in macros and command completion.
    where = "#PASTE#";
    [SUD setBool:YES forKey:ConvertLFKey];
    Clip(endings);
    NSMutableString *macro = [@"[#PASTE#|#PASTE#]" mutableCopy];
    [macro replacePasteMarkersWithClipboardText];
    REQUIRE([macro isEqualToString:@"[a\nb\nc\nd\ne\nf|a\nb\nc\nd\ne\nf]"]);
    [SUD setBool:NO forKey:ConvertLFKey];
    macro = [@"[#PASTE#]" mutableCopy];
    [macro replacePasteMarkersWithClipboardText];
    REQUIRE([macro isEqualToString:[NSString stringWithFormat:@"[%@]", endings]]);
    [clipboard clearContents];
    macro = [@"[#PASTE#]" mutableCopy];
    [macro replacePasteMarkersWithClipboardText];
    REQUIRE([macro isEqualToString:@"[]"]);
    // The same line endings become LF as with OgreKit, which reads files and typed and pasted text.
    NSString *every = [NSString stringWithFormat:@"1\r\n2\r3\n4\u2028" "5\u2029" "6%C7\r\r\n\n8", (unichar)0x85];
    NSMutableString *mine = [every mutableCopy];
    REQUIRE([mine respondsToSelector:@selector(replaceLineEndingsWithLF)]);
    [mine performSelector:@selector(replaceLineEndingsWithLF)];
    REQUIRE([mine isEqualToString:[OGRegularExpression replaceNewlineCharactersInString:every withCharacter:OgreLfNewlineCharacter]]);
    printf("PASS: #PASTE# gets LF line endings with ConvertLF, as OgreKit makes them, and keeps them without\n");
} return 0; }
