// Edit menu text commands: Character Type Conversion, Unicode Normalization and
// Swap with Clipboard (exchangePaste:). A private pasteboard stands in for the clipboard.
// Built by run-edit-text-commands.py together with the TSTextView source section.
#import <Cocoa/Cocoa.h>
#import <objc/runtime.h>
#import "TestAppKitIsolation.h"
#import "globals.h"
#import "NSString-Extras.h"
#import "NSString-CharacterConversion.h"
#import "NSMutableString-Extras.h"

NSInteger g_texChar = 0x005C;

static void IgnoreOutlet(id self, SEL cmd, id value, NSString *key) {}
static int failures;
static void Check(NSString *name, NSString *got, NSString *expected)
{
    if ([got isEqualToString:expected]) return;
    printf("FAIL %s: got \"%s\" expected \"%s\"\n", name.UTF8String, got.UTF8String, expected.UTF8String);
    failures++;
}
static void Require(NSString *name, BOOL condition)
{
    if (condition) return;
    printf("FAIL %s\n", name.UTF8String);
    failures++;
}

// Answers for the whole-document question, so that no alert is ever shown.
static NSModalResponse alertAnswer;
static NSUInteger alertsAsked;
static NSString *lastAlertText;
static NSModalResponse TestRunModal(NSAlert *alert, SEL cmd) { alertsAsked++; lastAlertText = alert.messageText; return alertAnswer; }
static void TestBeginSheet(NSAlert *alert, SEL cmd, NSWindow *window, void (^handler)(NSModalResponse))
{
    alertsAsked++; lastAlertText = alert.messageText;
    if (handler) handler(alertAnswer);
}

static NSPasteboard *testPasteboard;
static NSPasteboard *TestGeneralPasteboard(id receiver, SEL cmd) { return testPasteboard; }
static void SetClipboard(NSString *text) { [testPasteboard clearContents]; if (text) [testPasteboard setString:text forType:NSPasteboardTypeString]; }

@interface TestDocument : NSObject
@property NSUInteger characterInfoShown;
@end
@implementation TestDocument
- (IBAction)showCharacterInfo:(id)sender { self.characterInfoShown++; }
@end
@interface TSTextView : NSTextView
@property (weak) TestDocument *document;
@end
@interface TestDelegate : NSObject <NSTextViewDelegate>
@property NSUndoManager *undo;
@end
@implementation TestDelegate
- (NSUndoManager *)undoManagerForTextView:(NSTextView *)view { return self.undo; }
@end

#include "TSTextViewEditCommands.inc"
// Stands in for TeXShop's yen/backslash filtering on copy.
- (BOOL)writeSelectionToPasteboard:(NSPasteboard *)pboard type:(NSPasteboardType)type
{
    BOOL written = [super writeSelectionToPasteboard:pboard type:type];
    NSString *text = [pboard stringForType:NSPasteboardTypeString];
    if (written && text) [pboard setString:[text stringByReplacingOccurrencesOfString:@"¥" withString:@"\\"] forType:NSPasteboardTypeString];
    return written;
}
- (BOOL)validateMenuItem:(NSMenuItem *)anItem
{
    BOOL enabled;
    if ([self validateEditTextCommand:anItem enabled:&enabled]) return enabled;
    return [super validateMenuItem:anItem];
}
@end

static NSMenuItem *ActionItem(SEL action, NSInteger tag, NSString *title)
{
    NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:title action:action keyEquivalent:@""];
    item.tag = tag;
    return item;
}
static NSMenuItem *Item(NSInteger tag, NSString *title) { return ActionItem(@selector(convertCharacterType:), tag, title); }

static void CheckStrings(void)
{
    Check(@"hiragana", [@"ひらがな・ゔゖ" stringByReplacingHiraganaWithKatakana], @"ヒラガナ・ヴヶ");
    Check(@"katakana", [@"カタカナ・ヴヶ" stringByReplacingKatakanaWithHiragana], @"かたかな・ゔゖ");
    Check(@"fullwidth digits", [@"０１２９\n１\n" stringByReplacingFullwidthDigitsWithHalfwidthDigits], @"0129%\n1%\n");
    Check(@"halfwidth digits", [@"x09" stringByReplacingHalfwidthDigitsWithFullwidthDigits], @"x０９");
    Check(@"fullwidth letters", [@"ＡｚＺａ" stringByReplacingFullwidthAlphabetsWithHalfwidthAlphabets], @"AzZa");
    Check(@"halfwidth letters", [@"Az!" stringByReplacingHalfwidthAlphabetsWithFullwidthAlphabets], @"Ａｚ!");
    Check(@"to ajmacros", [@"①㊿❶⑴Ⓐⓐ㍿\n②\n" stringByReplacingUnicodeCharactersWithAjMacros],
          @"\\ajMaru{1}\\ajMaru{50}\\ajKuroMaru{1}\\ajKakko{1}\\ajMaruAlph{1}\\ajMarualph{1}\\ajLig{株式会社}%\n\\ajMaru{2}%\n");
    Check(@"from ajmacros", [@"\\ajMaru{1}\\ajMaru{50}\\ajKakko{20}\\ajLig{株式会社}\\ajHotSpring \\ajTsuchiYoshi" stringByReplacingAjMacrosWithUnicodeCharacters],
          @"①㊿⒇㍿♨𠮷");
    Check(@"to UTF", [@"髙島屋―\n𠮷\nあ" stringByReplacingUnicodeCharactersWithUTF], @"\\UTF{9AD9}島屋—%\n\\CID{13706}%\nあ");
    Check(@"from UTF", [@"\\UTF{9AD9}\\UTF{9ad9}\\UTF{ZZZZ}" stringByReplacingUTFWithUnicodeCharacters], @"髙髙\\UTF{ZZZZ}");
    Check(@"from CID", [@"\\CID{1}|\\CID{13706}|\\CID{23057}|\\CID{99999}|\\CID{0}" stringByReplacingUTFWithUnicodeCharacters],
          @" |𠮷|\u9FA3|\\CID{99999}|\\CID{0}");
    // Reading decodes only what saving with utf.sty output writes: commands for characters
    // outside JIS X 0208 (and ～/－). JIS characters, escaped backslashes and surrogates stay.
    Check(@"UTF commands when reading", [@"\\UTF{9AD9}\\UTFK{FF5E}\\UTFC{ff0d}\\UTFT{3042}\\UTF{ZZZZ}～－" stringByDecodingUTFCommandsForReading],
          @"髙〜−\\UTFT{3042}\\UTF{ZZZZ}～－");
    Check(@"literal UTF examples when reading", [@"\\verb|\\UTF{0041}| \\\\UTF{0041} \\\\UTF{9DD7} \\\\\\UTF{9DD7}" stringByDecodingUTFCommandsForReading],
          @"\\verb|\\UTF{0041}| \\\\UTF{0041} \\\\UTF{9DD7} \\\\鷗");
    Check(@"surrogate boundaries when reading", [@"\\UTF{D7FF}\\UTF{D800}\\UTF{DBFF}\\UTF{DC00}\\UTF{DFFF}\\UTF{E000}" stringByDecodingUTFCommandsForReading],
          @"\uD7FF\\UTF{D800}\\UTF{DBFF}\\UTF{DC00}\\UTF{DFFF}\uE000");
    Check(@"surrogate boundaries from UTF", [@"\\UTF{D7FF}\\UTF{D800}\\UTF{DBFF}\\UTF{DC00}\\UTF{DFFF}\\UTF{E000}\\UTF{0041}\\\\UTF{0041}" stringByReplacingUTFWithUnicodeCharacters],
          @"\uD7FF\\UTF{D800}\\UTF{DBFF}\\UTF{DC00}\\UTF{DFFF}\uE000A\\\\UTF{0041}");
    Require(@"decoded text is valid Unicode", [[@"\\UTF{D800}x" stringByDecodingUTFCommandsForReading] UTF8String] != NULL && [[@"\\UTF{D800}x" stringByReplacingUTFWithUnicodeCharacters] UTF8String] != NULL);
    // Variation sequences become \CID only when Hiragino registers them (format 14 cmap).
    Check(@"variation sequences", [@"\u845B\U000E01EF|\u845B\uFE0F|\u845B\U000E0100|\u8FBB\U000E0101" stringByReplacingUnicodeCharactersWithUTF],
          @"\u845B\U000E01EF|\u845B\uFE0F|\\CID{1481}|\\CID{8267}");
    // Manual decoding reads the original text once: escaped commands stay, and a command
    // produced by a replacement is not decoded again.
    Check(@"escaped CID", [@"\\CID{13706}|\\\\CID{13706}|\\\\\\CID{13706}|\\\\\\\\CID{13706}|\\CID{99999}" stringByReplacingUTFWithUnicodeCharacters],
          @"\U00020BB7|\\\\CID{13706}|\\\\\U00020BB7|\\\\\\\\CID{13706}|\\CID{99999}");
    Check(@"no second pass", [@"\\UTF{005C}CID{13706}|\\UTF{005C}UTF{9AD9}" stringByReplacingUTFWithUnicodeCharacters],
          @"\\CID{13706}|\\UTF{9AD9}");
    // Only sequences that Hiragino (Adobe-Japan1) draws as one glyph of its own become \CID.
    Check(@"CID only for Adobe-Japan1 glyphs", [@"\U0001F600|e\u0301|\U0001F468\u200D\U0001F469\u200D\U0001F467|\u8FBB\U000E0101|\U0002000B" stringByReplacingUnicodeCharactersWithUTF],
          @"\U0001F600|\\CID{201}|\U0001F468\u200D\U0001F469\u200D\U0001F467|\\CID{8267}|\\CID{13839}");
    // ㊐..㊡ are \ajMaruYobi (they were written as \ajKakkoYobi, and ㊡ was read as ㊗).
    Check(@"to ajMaruYobi", [@"㊐㊊㊏㊗㊡|㈰㈪㈷㉁" stringByReplacingUnicodeCharactersWithAjMacros],
          @"\\ajMaruYobi{1}\\ajMaruYobi{2}\\ajMaruYobi{7}\\ajMaruYobi{8}\\ajMaruYobi{9}|\\ajKakkoYobi{1}\\ajKakkoYobi{2}\\ajKakkoYobi{8}\\ajKakkoYobi{9}");
    Check(@"from ajMaruYobi", [@"\\ajMaruYobi{1}\\ajMaruYobi{2}\\ajMaruYobi7\\ajMaruYobi{8}\\ajMaruYobi{9}\\ajMaruYobi9|\\ajKakkoYobi{1}\\ajKakkoYobi{9}" stringByReplacingAjMacrosWithUnicodeCharacters],
          @"㊐㊊㊏㊗㊡㊡|㈰㉁");
    Check(@"modified NFC composes", [@"か\u3099は\u309A\uFA19" normalizedStringWithModifiedNFC], @"がぱ\uFA19");
    Check(@"modified NFC keeps text made only of excluded characters", [@"\uFA19\uFA19" normalizedStringWithModifiedNFC], @"\uFA19\uFA19");
    Check(@"modified NFD keeps compatibility ideographs", [@"が\uFA19" normalizedStringWithModifiedNFD], @"か\u3099\uFA19");
    Check(@"quotes", [@"‘“a”’ “b” ‘c’" stringByReplacingFullwidthQuotesWithHalfwidthQuotes], @"`\\,``a''\\,' ``b'' `c'");
}

static TSTextView *NewView(NSString *text, TestDelegate *delegate)
{
    TSTextView *view = [[TSTextView alloc] initWithFrame:NSMakeRect(0, 0, 400, 200)];
    view.allowsUndo = YES;
    view.richText = NO;
    view.delegate = delegate;
    [view.textStorage replaceCharactersInRange:NSMakeRange(0, 0) withString:text];
    return view;
}

static void CheckConversionCommand(void)
{
    TestDelegate *delegate = [TestDelegate new];
    delegate.undo = [NSUndoManager new];
    delegate.undo.groupsByEvent = NO;
    [delegate.undo beginUndoGrouping];

    // A selection is converted at once, selected afterwards, and undoable.
    TSTextView *view = NewView(@"ひらがな ひらがな", delegate);
    view.selectedRange = NSMakeRange(0, 4);
    alertsAsked = 0;
    [view convertCharacterType:Item(TSHiraganaToKatakanaTag, @"Hiragana → Katakana")];
    [delegate.undo endUndoGrouping];
    Check(@"selection converted", view.string, @"ヒラガナ ひらがな");
    Require(@"selection asks nothing", alertsAsked == 0);
    Require(@"converted text stays selected", NSEqualRanges(view.selectedRange, NSMakeRange(0, 4)));
    Check(@"undo name is the menu title", delegate.undo.undoActionName, @"Hiragana → Katakana");
    [delegate.undo undo];
    Check(@"undo restores", view.string, @"ひらがな ひらがな");
    [delegate.undo beginUndoGrouping];

    // Length changes keep the converted text selected.
    view = NewView(@"x①y", delegate);
    view.selectedRange = NSMakeRange(1, 1);
    [view convertCharacterType:Item(TSUnicodeToAJMacrosTag, @"to ajmacros")];
    Check(@"growing conversion", view.string, @"x\\ajMaru{1}y");
    Require(@"growing selection", NSEqualRanges(view.selectedRange, NSMakeRange(1, 10)));

    // No selection: the whole document after the user agrees, nothing otherwise.
    view = NewView(@"１２\nＡＢ", delegate);
    view.selectedRange = NSMakeRange(1, 0);
    alertAnswer = NSAlertSecondButtonReturn; alertsAsked = 0;
    [view convertCharacterType:Item(TSFullwidthToHalfwidthDigitsTag, @"Digits")];
    Require(@"whole document asks", alertsAsked == 1);
    Require(@"question names the command", [lastAlertText containsString:@"Digits"]);
    Check(@"cancel leaves the text", view.string, @"１２\nＡＢ");
    alertAnswer = NSAlertFirstButtonReturn;
    [view convertCharacterType:Item(TSFullwidthToHalfwidthDigitsTag, @"Digits")];
    Check(@"OK converts the whole document", view.string, @"12%\nＡＢ");

    // A read-only view refuses the command, and an empty one only beeps.
    view = NewView(@"ひ", delegate);
    view.editable = NO;
    Require(@"read-only view disables the command", ![view validateMenuItem:Item(TSHiraganaToKatakanaTag, @"x")]);
    view = NewView(@"", delegate);
    alertsAsked = 0;
    [view convertCharacterType:Item(TSHiraganaToKatakanaTag, @"x")];
    Require(@"empty document asks nothing", alertsAsked == 0);

    // Every menu tag maps to a conversion.
    for (NSInteger tag = TSHiraganaToKatakanaTag; tag <= TSFullwidthToHalfwidthQuotesTag; tag++) {
        view = NewView(@"ひカ１Ａ①\\ajMaru{2}髙\\UTF{9AD9}“", delegate);
        [view selectAll:nil];
        [view convertCharacterType:Item(tag, @"x")];
        Require([NSString stringWithFormat:@"tag %ld changes the sample", (long)tag], ![view.string isEqualToString:@"ひカ１Ａ①\\ajMaru{2}髙\\UTF{9AD9}“"]);
    }
}

static void CheckNormalizationCommand(void)
{
    TestDelegate *delegate = [TestDelegate new];
    delegate.undo = [NSUndoManager new];
    TestDocument *document = [TestDocument new];
    // Each tag against the same decomposed sample; ㍿ and the compatibility
    // ideograph tell the variants apart.
    NSString *sample = @"か\u3099\uFA19㍿";
    NSDictionary *expected = @{@(TSNFCTag): @"が\u795E㍿", @(TSModifiedNFCTag): @"が\uFA19㍿", @(TSNFDTag): @"か\u3099\u795E㍿",
                               @(TSModifiedNFDTag): @"か\u3099\uFA19㍿", @(TSNFKCTag): @"が\u795E株式会社", @(TSNFKDTag): @"か\u3099\u795E株式会社"};
    for (NSNumber *tag in expected) {
        TSTextView *view = NewView([@"x" stringByAppendingString:sample], delegate);
        view.document = document;
        view.selectedRange = NSMakeRange(1, sample.length);
        NSUInteger shown = document.characterInfoShown;
        [delegate.undo beginUndoGrouping];
        [view normalizeSelectedString:ActionItem(@selector(normalizeSelectedString:), tag.integerValue, @"Form")];
        [delegate.undo endUndoGrouping];
        Check([NSString stringWithFormat:@"normalization tag %@", tag], [view.string substringFromIndex:1], expected[tag]);
        Require([NSString stringWithFormat:@"normalization tag %@ selects the result", tag],
                NSEqualRanges(view.selectedRange, NSMakeRange(1, view.string.length - 1)));
        Require([NSString stringWithFormat:@"normalization tag %@ shows character info", tag], document.characterInfoShown == shown + 1);
        Require(@"normalization validates", [view validateMenuItem:ActionItem(@selector(normalizeSelectedString:), tag.integerValue, @"Form")]);
    }
    // Whole document after agreement; no character info for the whole text.
    TSTextView *view = NewView(@"か\u3099", delegate);
    view.document = document;
    NSUInteger shown = document.characterInfoShown;
    alertAnswer = NSAlertFirstButtonReturn; alertsAsked = 0;
    [delegate.undo beginUndoGrouping];
    [view normalizeSelectedString:ActionItem(@selector(normalizeSelectedString:), TSNFCTag, @"NFC")];
    [delegate.undo endUndoGrouping];
    Check(@"whole document NFC", view.string, @"が");
    Require(@"whole document NFC asked once", alertsAsked == 1 && document.characterInfoShown == shown);
    Check(@"NFC undo name", delegate.undo.undoActionName, @"NFC");
}

static void CheckExchangePaste(void)
{
    TestDelegate *delegate = [TestDelegate new];
    delegate.undo = [NSUndoManager new];
    NSMenuItem *item = ActionItem(@selector(exchangePaste:), 0, @"Swap");

    TSTextView *view = NewView(@"left right", delegate);
    view.selectedRange = NSMakeRange(0, 4);
    SetClipboard(@"NEW");
    Require(@"swap enabled with text on the clipboard", [view validateMenuItem:item]);
    [delegate.undo beginUndoGrouping];
    [view exchangePaste:item];
    [delegate.undo endUndoGrouping];
    Check(@"swap pastes the clipboard", view.string, @"NEW right");
    Check(@"swap puts the replaced text on the clipboard", [testPasteboard stringForType:NSPasteboardTypeString], @"left");
    [delegate.undo undo];
    Check(@"swap undoes the paste", view.string, @"left right");

    view = NewView(@"x¥y", delegate);
    [view selectAll:nil];
    SetClipboard(@"Z");
    [view exchangePaste:item];
    Check(@"swap copies the way Copy does", [testPasteboard stringForType:NSPasteboardTypeString], @"x\\y");

    view = NewView(@"ab", delegate);
    view.selectedRange = NSMakeRange(1, 0);
    SetClipboard(@"Q");
    [view exchangePaste:item];
    Check(@"without a selection it pastes", view.string, @"aQb");
    Check(@"without a selection the clipboard stays", [testPasteboard stringForType:NSPasteboardTypeString], @"Q");

    // Macro and key binding text: #PASTE# becomes the clipboard text.
    NSMutableString *macro = [NSMutableString stringWithString:@"\\textbf{#PASTE#}#INS# #PASTE#"];
    SetClipboard(@"word");
    [macro replacePasteMarkersWithClipboardText];
    Check(@"#PASTE# expands", macro, @"\\textbf{word}#INS# word");
    macro = [NSMutableString stringWithString:@"(#PASTE#)"];
    SetClipboard(nil);
    [macro replacePasteMarkersWithClipboardText];
    Check(@"#PASTE# with an empty clipboard", macro, @"()");

    SetClipboard(nil);
    view.selectedRange = NSMakeRange(0, 1);
    Require(@"swap disabled with an empty clipboard", ![view validateMenuItem:item]);
    SetClipboard(@"Q");
    view.editable = NO;
    Require(@"swap disabled in a read-only view", ![view validateMenuItem:item]);
}

static NSMenuItem *FindSubmenu(NSMenu *menu, SEL action)
{
    for (NSMenuItem *item in menu.itemArray) {
        for (NSMenuItem *sub in item.submenu.itemArray)
            if (sub.action == action) return item;
        NSMenuItem *found = item.submenu ? FindSubmenu(item.submenu, action) : nil;
        if (found) return found;
    }
    return nil;
}

static void CheckCompiledMenu(NSString *path)
{
    NSNib *nib = [[NSNib alloc] initWithNibData:[NSData dataWithContentsOfFile:path] bundle:nil];
    NSArray *objects;
    if (![nib instantiateWithOwner:NSApp topLevelObjects:&objects]) { Require(path, NO); return; }
    NSMenu *menu = nil;
    for (id object in objects) if ([object isKindOfClass:NSMenu.class] && [object itemArray].count > 5) menu = object;
    NSMenuItem *convert = FindSubmenu(menu, @selector(convertCharacterType:));
    NSMenuItem *transform = FindSubmenu(menu, @selector(uppercaseWord:));
    Require([path stringByAppendingString:@": conversion submenu"], convert != nil);
    Require([path stringByAppendingString:@": conversion follows Transformations"],
            convert.menu == transform.menu && [convert.menu indexOfItem:convert] == [transform.menu indexOfItem:transform] + 1);
    NSMutableArray *tags = [NSMutableArray array];
    for (NSMenuItem *item in convert.submenu.itemArray) {
        if (item.isSeparatorItem) continue;
        [tags addObject:@(item.tag)];
        NSString *identifier = [NSString stringWithFormat:@"TSShortcut.convertCharacterType:.%ld", (long)item.tag];
        Require([NSString stringWithFormat:@"%@: tag %ld wiring", path, (long)item.tag],
                item.action == @selector(convertCharacterType:) && item.target == nil && [item.identifier isEqualToString:identifier] &&
                item.keyEquivalent.length == 0 && item.title.length > 0);
    }
    Require([path stringByAppendingString:@": tags 1-11"], [tags isEqual:@[@1, @2, @3, @4, @5, @6, @7, @8, @9, @10, @11]]);

    NSMenuItem *paste = nil, *exchange = nil;
    for (NSMenuItem *item in convert.menu.itemArray) {
        if (item.action == @selector(paste:)) paste = item;
        if (item.action == @selector(exchangePaste:)) exchange = item;
    }
    Require([path stringByAppendingString:@": swap follows Paste"],
            paste && exchange && [convert.menu indexOfItem:exchange] == [convert.menu indexOfItem:paste] + 1);
    Require([path stringByAppendingString:@": swap wiring"],
            exchange.target == nil && exchange.tag == 0 && [exchange.identifier isEqualToString:@"TSShortcut.exchangePaste:.0"] &&
            exchange.keyEquivalent.length == 0 && exchange.title.length > 0);

    NSMenuItem *normalize = FindSubmenu(menu, @selector(normalizeSelectedString:));
    Require([path stringByAppendingString:@": normalization follows conversion"],
            normalize && normalize.menu == convert.menu && [normalize.menu indexOfItem:normalize] == [convert.menu indexOfItem:convert] + 1);
    NSArray *forms = @[@"NFC", @"Modified NFC", @"NFD", @"Modified NFD", @"NFKC", @"NFKD"];
    NSArray *items = normalize.submenu.itemArray;
    Require([path stringByAppendingString:@": six normalization forms"], items.count == forms.count);
    for (NSUInteger i = 0; i < MIN(items.count, forms.count); i++) {
        NSMenuItem *item = items[i];
        NSString *identifier = [NSString stringWithFormat:@"TSShortcut.normalizeSelectedString:.%lu", (unsigned long)(i + 1)];
        Require([NSString stringWithFormat:@"%@: %@ wiring", path, forms[i]],
                item.action == @selector(normalizeSelectedString:) && item.target == nil && item.tag == (NSInteger)(i + 1) &&
                [item.identifier isEqualToString:identifier] && [item.title isEqualToString:forms[i]] && item.keyEquivalent.length == 0);
    }
}

int main(int argc, char **argv)
{
    @autoreleasepool {
        TSInstallAppKitIsolation();
        [NSApplication sharedApplication];
        method_setImplementation(class_getInstanceMethod(NSAlert.class, @selector(runModal)), (IMP)TestRunModal);
        method_setImplementation(class_getInstanceMethod(NSAlert.class, @selector(beginSheetModalForWindow:completionHandler:)), (IMP)TestBeginSheet);
        for (NSString *name in @[@"HelpDocuments", @"TSAppDelegate", @"TSAutoCompletionListEditor", @"TSDocumentController", @"TSMacroEditor",
                                 @"TSMacroMenuController", @"TSMovie", @"TSPreferences", @"TSSparkleController", @"TSStationery", @"TextFinder"]) {
            Class c = objc_allocateClassPair(NSObject.class, name.UTF8String, 0);
            class_addMethod(c, @selector(setValue:forUndefinedKey:), (IMP)IgnoreOutlet, "v@:@@");
            objc_registerClassPair(c);
        }
        CheckStrings();
        CheckConversionCommand();
        CheckNormalizationCommand();
        testPasteboard = [NSPasteboard pasteboardWithUniqueName];
        method_setImplementation(class_getClassMethod(NSPasteboard.class, @selector(generalPasteboard)), (IMP)TestGeneralPasteboard);
        CheckExchangePaste();
        [testPasteboard releaseGlobally];
        for (int i = 1; i < argc; i++) CheckCompiledMenu(@(argv[i]));
        if (failures) return 1;
        printf("PASS: conversions, normalization, swap with clipboard, command behaviour, %d compiled menus\n", argc - 1);
    }
    return 0;
}
