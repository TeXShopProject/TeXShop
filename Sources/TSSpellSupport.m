/*
 * TeXShop - TeX editor for Mac OS
 *
 * See TSSpellSupport.h.
 *
 * This file is part of the TeX-aware spell checking added to TeXShop. It is
 * distributed under the same GNU General Public License as TeXShop.
 */

#import "TSSpellSupport.h"
#import "TSSpellExclusions.h"

// Data for the list of learned words in the "Forget Learned Words" sheet.
@interface TSLearnedWordsList : NSObject <NSTableViewDataSource>
@property (nonatomic, copy) NSArray<NSString *> *words;
@end
@implementation TSLearnedWordsList
- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView { return (NSInteger)[self.words count]; }
- (id)tableView:(NSTableView *)tableView objectValueForTableColumn:(NSTableColumn *)column row:(NSInteger)row
{
    return self.words[(NSUInteger)row];
}
@end

// Keeps Change All directly under the panel's Change button. The panel lays its
// own buttons out again whenever it likes (when it is resized, when it is given a
// new word), putting Find Next straight back where it was, so this watches the
// frames of the buttons and puts things back: Find Next one step lower, Change All
// in the place Find Next leaves.
@interface TSChangeAllPlacement : NSObject
@property (weak) NSButton *change, *findNext, *changeAll;
@property BOOL flipped, placing;
@property CGFloat step;
- (void)place:(NSNotification *)note;
@end
@implementation TSChangeAllPlacement
- (void)place:(NSNotification *)note
{
    if (self.placing || !self.change || !self.findNext || !self.changeAll) return;
    self.placing = YES;
    CGFloat sign = self.flipped ? 1 : -1;
    NSRect change = self.change.frame;
    CGFloat step = _step;
    NSRect all = change, next = change;
    all.origin.y = change.origin.y + sign * step;
    next.origin.y = change.origin.y + 2 * sign * step;
    if (!NSEqualRects(self.changeAll.frame, all)) self.changeAll.frame = all;
    if (!NSEqualRects(self.findNext.frame, next)) self.findNext.frame = next;
    self.placing = NO;
}
@end

@implementation TSSpellSupport

#pragma mark - Find Next

// Scroll so the line containing `range` is vertically centred in the visible
// area, as far as the ends of the document allow.
+ (void)centerRange:(NSRange)range inTextView:(NSTextView *)tv
{
    NSScrollView *sv = tv.enclosingScrollView;
    if (!sv) { [tv scrollRangeToVisible:range]; return; }
    NSLayoutManager *lm = tv.layoutManager;
    [lm ensureLayoutForTextContainer:tv.textContainer];
    NSRange glyphs = [lm glyphRangeForCharacterRange:range actualCharacterRange:NULL];
    NSRect r = [lm boundingRectForGlyphRange:glyphs inTextContainer:tv.textContainer];
    CGFloat midY = NSMidY(r) + tv.textContainerOrigin.y;
    NSClipView *clip = sv.contentView;
    CGFloat viewH = clip.bounds.size.height;
    CGFloat docH = MAX(tv.frame.size.height,
                       [lm usedRectForTextContainer:tv.textContainer].size.height + 2 * tv.textContainerOrigin.y);
    CGFloat topY = midY - viewH / 2;
    topY = MAX(0, MIN(topY, MAX(docH - viewH, 0)));
    [clip scrollToPoint:NSMakePoint(clip.bounds.origin.x, topY)];
    [sv reflectScrolledClipView:clip];
}

// The system spell checker's language for a language code from the rules file
// (for example "de", or "pt_BR"), as NSSpellChecker names its languages, nil if
// it has none. *isDocument is set to YES if the code is the language the document
// is being checked in, so that no special treatment is needed.
+ (NSString *)checkerLanguageForCode:(NSString *)code isDocumentLanguage:(BOOL *)isDocument
{
    NSSpellChecker *checker = [NSSpellChecker sharedSpellChecker];
    NSString *document = [[checker language] stringByReplacingOccurrencesOfString:@"-" withString:@"_"] ?: @"";
    NSString *wanted = [code stringByReplacingOccurrencesOfString:@"-" withString:@"_"];

    static NSMutableDictionary<NSString *, NSArray *> *cache;
    if (!cache) cache = [NSMutableDictionary dictionary];
    NSString *key = [NSString stringWithFormat:@"%@|%@", wanted, document];
    NSArray *known = cache[key];
    if (!known) {
        BOOL hasRegion = [wanted rangeOfString:@"_"].location != NSNotFound;
        BOOL same = hasRegion ? [document isEqualToString:wanted]
                              : ([document isEqualToString:wanted] || [document hasPrefix:[wanted stringByAppendingString:@"_"]]);
        NSString *found = nil;
        if (!same) {
            NSString *base = hasRegion ? [wanted substringToIndex:[wanted rangeOfString:@"_"].location] : wanted;
            NSString *prefixed = nil;
            for (NSString *available in [checker availableLanguages]) {
                NSString *a = [available stringByReplacingOccurrencesOfString:@"-" withString:@"_"];
                if ([a isEqualToString:wanted]) { found = available; break; }
                if (!found && hasRegion && [a isEqualToString:base]) found = available;
                if (!prefixed && [a hasPrefix:[base stringByAppendingString:@"_"]]) prefixed = available;
            }
            if (!found) found = prefixed;
        }
        known = @[@(same), found ?: [NSNull null]];
        cache[key] = known;
    }
    *isDocument = [known[0] boolValue];
    return [known[1] isKindOfClass:[NSString class]] ? known[1] : nil;
}

// The first misspelling at or after `from` in the masked text. Text marked as
// being in another language is checked in that language (and not at all if the
// system has no spell checker for it); the rest in the document's language.
+ (NSRange)misspellingInMask:(TSSpellMask *)mask from:(NSUInteger)from tag:(NSInteger)tag
{
    NSSpellChecker *checker = [NSSpellChecker sharedSpellChecker];
    NSString *masked = mask.masked;
    NSArray<TSSpellLanguageSegment *> *segments = [mask languageSegments];
    if (!segments) {
        if (from >= masked.length) return NSMakeRange(NSNotFound, 0);
        return [checker checkSpellingOfString:masked startingAt:(NSInteger)from language:nil wrap:NO
                       inSpellDocumentWithTag:tag wordCount:NULL];
    }
    for (TSSpellLanguageSegment *segment in segments) {
        if (NSMaxRange(segment.range) <= from) continue;
        NSString *language = nil;
        if (segment.language) {
            BOOL isDocument;
            language = [self checkerLanguageForCode:segment.language isDocumentLanguage:&isDocument];
            if (!isDocument && !language) continue;         // no checker for this language
            if (isDocument) language = nil;
        }
        NSString *text = [masked substringWithRange:segment.range];
        NSUInteger offset = from > segment.range.location ? from - segment.range.location : 0;
        NSRange bad = [checker checkSpellingOfString:text startingAt:(NSInteger)offset language:language wrap:NO
                              inSpellDocumentWithTag:tag wordCount:NULL];
        if (bad.location != NSNotFound && bad.length > 0)
            return NSMakeRange(bad.location + segment.range.location, bad.length);
    }
    return NSMakeRange(NSNotFound, 0);
}

// YES if the text at `range` in the original text is in a language other than
// the document's, so that the system's check (in the document's language) is not
// to be trusted for it.
+ (BOOL)rangeIsInOtherLanguage:(NSRange)range mask:(TSSpellMask *)mask
{
    if (!mask.hasLanguages) return NO;
    NSString *code = [mask languageForOriginalIndex:range.location];
    if (!code) return NO;
    BOOL isDocument;
    [self checkerLanguageForCode:code isDocumentLanguage:&isDocument];
    return !isDocument;
}

#pragma mark - Change All

// The text view and the (masked) word last offered to the Spelling and Grammar
// panel, which "Change All" works on.
static __weak NSTextView *sReviewView;
static NSString *sReviewWord;

// The panel's editable field: the correction that Change would use. It holds the
// misspelled word until the user types, or picks a suggestion from the list.
static NSTextField *CorrectionField(NSView *view)
{
    if ([view isKindOfClass:[NSTextField class]] && ((NSTextField *)view).isEditable) return (NSTextField *)view;
    for (NSView *sub in view.subviews) {
        NSTextField *found = CorrectionField(sub);
        if (found) return found;
    }
    return nil;
}

static NSTableView *SuggestionsTable(NSView *view)
{
    if ([view isKindOfClass:[NSTableView class]]) return (NSTableView *)view;
    for (NSView *sub in view.subviews) {
        NSTableView *found = SuggestionsTable(sub);
        if (found) return found;
    }
    return nil;
}

// What Change All replaces the word with: the panel's correction field if it holds
// something other than the misspelled word (the user typed it, or picked a
// suggestion, which the panel copies there); otherwise the suggestion selected in
// the list or, if none is, the first one: what Change itself would use.
static NSString *ReplacementFromPanel(NSString *word)
{
    NSView *content = [[NSSpellChecker sharedSpellChecker] spellingPanel].contentView;
    NSString *typed = [[CorrectionField(content) stringValue]
                       stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if ([typed length] && ![typed isEqualToString:word]) return typed;
    NSTableView *table = SuggestionsTable(content);
    if (!table || table.numberOfRows == 0 || table.tableColumns.count == 0) return nil;
    NSInteger row = table.selectedRow >= 0 ? table.selectedRow : 0;
    id source = table.dataSource;
    id value = nil;
    if ([source respondsToSelector:@selector(tableView:objectValueForTableColumn:row:)])
        value = [source tableView:table objectValueForTableColumn:table.tableColumns[0] row:row];
    return [value isKindOfClass:[NSString class]] ? value : nil;
}

static BOOL IsWordCharacter(NSString *s, NSUInteger i)
{
    unichar c = [s characterAtIndex:i];
    return [[NSCharacterSet alphanumericCharacterSet] characterIsMember:c];
}

// YES if the word at `range` in `s` is a whole word: not part of a longer word,
// counting an apostrophe between letters (don't, Anne's) as part of the word.
static BOOL IsWholeWord(NSString *s, NSRange range)
{
    NSUInteger n = [s length];
    if (range.location > 0) {
        if (IsWordCharacter(s, range.location - 1)) return NO;
        unichar p = [s characterAtIndex:range.location - 1];
        if ((p == '\'' || p == 0x2019) && range.location > 1 && IsWordCharacter(s, range.location - 2)) return NO;
    }
    NSUInteger end = NSMaxRange(range);
    if (end < n) {
        if (IsWordCharacter(s, end)) return NO;
        unichar f = [s characterAtIndex:end];
        if ((f == '\'' || f == 0x2019) && end + 1 < n && IsWordCharacter(s, end + 1)) return NO;
    }
    return YES;
}

// The panel's "Change All" button: replace the misspelling the panel is showing
// everywhere in the document (outside the text the rules exclude) by the text in
// the panel's correction field, as one undoable change, then go on to the next
// misspelling.
+ (void)changeAll:(id)sender
{
    NSTextView *tv = sReviewView;
    NSString *word = sReviewWord;
    NSString *replacement = [ReplacementFromPanel(word) stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (!tv || [word length] == 0 || [replacement length] == 0 || [replacement isEqualToString:word]) {
        NSBeep();
        return;
    }
    TSSpellExclusions *exclusions = [TSSpellExclusions sharedExclusions];
    [exclusions reloadIfChanged];
    TSSpellMask *mask = [exclusions maskForText:tv.string];
    NSString *masked = mask.masked;

    NSMutableArray<NSValue *> *ranges = [NSMutableArray array];
    NSRange search = NSMakeRange(0, [masked length]);
    for (;;) {
        NSRange r = [masked rangeOfString:word options:NSLiteralSearch range:search];
        if (r.location == NSNotFound) break;
        search = NSMakeRange(NSMaxRange(r), [masked length] - NSMaxRange(r));
        if (!IsWholeWord(masked, r)) continue;
        NSRange original = [mask originalRangeForMaskedRange:r];
        if (original.length == 0 || [mask rangeTouchesExclusion:original]) continue;
        [ranges addObject:[NSValue valueWithRange:original]];
    }
    if ([ranges count] == 0) { NSBeep(); return; }

    NSMutableArray<NSString *> *strings = [NSMutableArray arrayWithCapacity:[ranges count]];
    for (NSUInteger k = 0; k < [ranges count]; k++) [strings addObject:replacement];
    if (![tv shouldChangeTextInRanges:ranges replacementStrings:strings]) return;
    NSUInteger firstLocation = [ranges[0] rangeValue].location;
    [tv.textStorage beginEditing];
    for (NSValue *v in [ranges reverseObjectEnumerator])
        [tv.textStorage replaceCharactersInRange:[v rangeValue] withString:replacement];
    [tv.textStorage endEditing];
    [tv didChangeText];
    [tv.undoManager setActionName:NSLocalizedString(@"Change All", @"")];

    tv.selectedRange = NSMakeRange(firstLocation + [replacement length], 0);
    TSSpellMask *fresh = [exclusions maskForText:tv.string];
    [self findNextMisspellingInTextView:tv mask:fresh];
}

static void CollectButtons(NSView *view, NSMutableArray<NSButton *> *buttons)
{
    if ([view isKindOfClass:[NSButton class]]) [buttons addObject:(NSButton *)view];
    for (NSView *sub in view.subviews) CollectButtons(sub, buttons);
}


// Put a "Change All" button in the panel (it has none of its own), directly under
// its Change button: the column of buttons at the right of the panel is Change,
// Find Next, (a gap), Ignore, Learn ..., so Find Next is moved down into the gap
// and Change All takes its place. The buttons are found by their positions, not by
// their titles, which are translated. If the panel does not look like that (a
// different layout in another system version), the button goes under the language
// pop-up instead, as the panel's accessory view. Done once.
+ (void)installChangeAllButton
{
    static BOOL installed;
    static TSChangeAllPlacement *placement;      // kept for as long as the panel
    if (installed) return;
    installed = YES;
    NSSpellChecker *checker = [NSSpellChecker sharedSpellChecker];
    NSString *title = NSLocalizedString(@"Change All", @"");

    NSView *content = [checker spellingPanel].contentView;
    NSMutableArray<NSButton *> *buttons = [NSMutableArray array];
    CollectButtons(content, buttons);
    // The column of buttons: those at the right-most x, top to bottom.
    CGFloat right = -1;
    for (NSButton *b in buttons) right = MAX(right, b.frame.origin.x);
    NSMutableArray<NSButton *> *column = [NSMutableArray array];
    for (NSButton *b in buttons)
        if (fabs(b.frame.origin.x - right) < 1 && b.superview == content) [column addObject:b];
    BOOL flipped = content.isFlipped;
    [column sortUsingComparator:^NSComparisonResult(NSButton *x, NSButton *y) {
        CGFloat a = x.frame.origin.y, c = y.frame.origin.y;
        if (a == c) return NSOrderedSame;
        return (a > c) != flipped ? NSOrderedAscending : NSOrderedDescending;     // top first
    }];
    if ([column count] >= 5) {
        NSButton *change = column[0], *findNext = column[1], *third = column[2];
        CGFloat step = fabs(change.frame.origin.y - findNext.frame.origin.y);
        CGFloat gap = fabs(findNext.frame.origin.y - third.frame.origin.y);
        if (step > 0 && gap >= 2 * step) {
            NSButton *button = [NSButton buttonWithTitle:title target:self action:@selector(changeAll:)];
            button.bezelStyle = change.bezelStyle;
            button.controlSize = change.controlSize;
            button.font = change.font;
            button.autoresizingMask = change.autoresizingMask;
            [content addSubview:button];
            placement = [[TSChangeAllPlacement alloc] init];
            placement.change = change;
            placement.findNext = findNext;
            placement.changeAll = button;
            placement.flipped = flipped;
            placement.step = step;
            for (NSView *v in @[change, findNext, content]) {
                v.postsFrameChangedNotifications = YES;
                [[NSNotificationCenter defaultCenter] addObserver:placement selector:@selector(place:)
                                                             name:NSViewFrameDidChangeNotification object:v];
            }
            [placement place:nil];
            return;
        }
    }
    NSButton *button = [NSButton buttonWithTitle:title target:self action:@selector(changeAll:)];
    button.frame = NSMakeRect(309.5, 3, 101.5, 22);
    button.autoresizingMask = NSViewMinXMargin;
    NSView *accessory = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 431, 28)];
    [accessory addSubview:button];
    [checker setAccessoryView:accessory];
}

+ (NSString *)findNextMisspellingInTextView:(NSTextView *)tv mask:(TSSpellMask *)mask
{
    [self installChangeAllButton];
    NSSpellChecker *checker = [NSSpellChecker sharedSpellChecker];
    NSString *masked = mask.masked;
    NSInteger tag = tv.spellCheckerDocumentTag;
    sReviewView = tv;
    sReviewWord = nil;
    NSUInteger startMasked = [mask maskedIndexForOriginalIndex:NSMaxRange(tv.selectedRange)];

    // Look from the end of the selection, then wrap round to the top.
    NSRange bad = NSMakeRange(NSNotFound, 0);
    if (startMasked < masked.length) bad = [self misspellingInMask:mask from:startMasked tag:tag];
    if (bad.location == NSNotFound && startMasked > 0) bad = [self misspellingInMask:mask from:0 tag:tag];

    if (bad.location == NSNotFound || bad.length == 0) {
        [checker updateSpellingPanelWithMisspelledWord:@""];
        NSBeep();
        return nil;
    }

    NSRange original = [mask originalRangeForMaskedRange:bad];
    [tv setSelectedRange:original];
    [self centerRange:original inTextView:tv];
    [tv showFindIndicatorForRange:original];
    // The panel looks up the suggestions and fills in its word field.
    NSString *word = [masked substringWithRange:bad];
    sReviewWord = word;
    [checker updateSpellingPanelWithMisspelledWord:word];
    return word;
}

+ (void)showSpellingPanelForTextView:(NSTextView *)tv mask:(TSSpellMask *)mask openPanel:(void (^)(void))openPanel
{
    NSRange before = tv.selectedRange;
    [self installChangeAllButton];
    openPanel();                        // shows the panel; the system also selects "its" first misspelling
    tv.selectedRange = before;          // undo that markup-blind search
    NSString *word = [self findNextMisspellingInTextView:tv mask:mask];

    // If the system's own search was slow to finish (the first time the panel is
    // shown, or in a long document) it may select its word after ours. Look again
    // shortly afterwards, and if the selection has moved into text the rules
    // exclude, do our search again.
    NSRange chosen = tv.selectedRange;
    __weak NSTextView *weakView = tv;
    for (NSNumber *delay in @[@0.15, @0.6]) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)([delay doubleValue] * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            NSTextView *view = weakView;
            if (!view) return;
            NSRange now = view.selectedRange;
            if (!NSEqualRanges(now, chosen) && now.length > 0 && [mask rangeTouchesExclusion:now]) {
                view.selectedRange = before;
                [self findNextMisspellingInTextView:view mask:mask];
            } else if (NSEqualRanges(now, chosen) && word) {
                [[NSSpellChecker sharedSpellChecker] updateSpellingPanelWithMisspelledWord:word];   // the panel may still show the system's word
            }
        });
    }
}

#pragma mark - Menu items

+ (NSArray<NSString *> *)learnedWordsInText:(NSString *)text
{
    NSSpellChecker *checker = [NSSpellChecker sharedSpellChecker];
    NSMutableSet<NSString *> *candidates = [NSMutableSet set];
    if ([text length]) {
        [text enumerateSubstringsInRange:NSMakeRange(0, [text length])
                                 options:NSStringEnumerationByWords
                              usingBlock:^(NSString *w, NSRange r, NSRange er, BOOL *stop) {
            if ([w length] > 1) [candidates addObject:w];
        }];
    }
    NSMutableArray<NSString *> *learned = [NSMutableArray array];
    for (NSString *w in candidates)
        if ([checker hasLearnedWord:w]) [learned addObject:w];
    [learned sortUsingComparator:^NSComparisonResult(NSString *a, NSString *b) {
        return [a localizedCaseInsensitiveCompare:b];
    }];
    return learned;
}

+ (NSUInteger)forgetWords:(NSArray<NSString *> *)words
{
    NSSpellChecker *checker = [NSSpellChecker sharedSpellChecker];
    NSUInteger forgotten = 0;
    for (NSString *w in words) {
        if ([checker hasLearnedWord:w]) forgotten++;
        [checker unlearnWord:w];
    }
    return forgotten;
}

// The text of the document being edited, for finding learned words in it.
static NSString *FrontDocumentText(void)
{
    NSTextView *tv = nil;
    NSWindow *window = NSApp.mainWindow ?: NSApp.keyWindow;
    if ([window.firstResponder isKindOfClass:[NSTextView class]]) tv = (NSTextView *)window.firstResponder;
    if (!tv) {
        @try { tv = [[[NSDocumentController sharedDocumentController] currentDocument] valueForKey:@"textView"]; }
        @catch (NSException *e) { tv = nil; }
    }
    return [tv isKindOfClass:[NSTextView class]] ? tv.string : nil;
}

+ (void)forgetLearnedWords:(id)sender
{
    [self forgetLearnedWordsFoundInText:FrontDocumentText()];
}

+ (void)forgetLearnedWordsFoundInText:(NSString *)text
{
    NSSpellChecker *checker = [NSSpellChecker sharedSpellChecker];
    NSString *language = checker.language ?: @"";
    NSArray<NSString *> *words = [self learnedWordsInText:text];

    NSAlert *alert = [[NSAlert alloc] init];
    if ([words count] == 0) {
        alert.messageText = NSLocalizedString(@"No learned words in this document", @"");
        alert.informativeText = [NSString stringWithFormat:NSLocalizedString(
            @"None of the words in this document have been learned for %@.", @""), language];
        [alert runModal];
        return;
    }

    alert.messageText = NSLocalizedString(@"Forget learned words", @"");
    alert.informativeText = [NSString stringWithFormat:NSLocalizedString(
        @"These words in this document have been learned for %@. Select the ones to forget. Shift-click or Command-click selects several.", @""), language];

    TSLearnedWordsList *list = [[TSLearnedWordsList alloc] init];
    list.words = words;
    NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(0, 0, 340, 220)];
    scroll.hasVerticalScroller = YES;
    scroll.borderType = NSBezelBorder;
    NSTableView *table = [[NSTableView alloc] initWithFrame:scroll.bounds];
    NSTableColumn *column = [[NSTableColumn alloc] initWithIdentifier:@"word"];
    column.width = 316;
    [table addTableColumn:column];
    table.headerView = nil;
    table.allowsMultipleSelection = YES;
    table.dataSource = list;
    [table reloadData];
    scroll.documentView = table;
    alert.accessoryView = scroll;
    [alert addButtonWithTitle:NSLocalizedString(@"Forget Selected", @"")];
    [alert addButtonWithTitle:NSLocalizedString(@"Cancel", @"")];
    alert.window.initialFirstResponder = table;

    if ([alert runModal] != NSAlertFirstButtonReturn) return;
    NSIndexSet *chosen = table.selectedRowIndexes;
    if ([chosen count] == 0) return;
    NSArray<NSString *> *selected = [list.words objectsAtIndexes:chosen];
    NSUInteger forgotten = [self forgetWords:selected];

    NSAlert *done = [[NSAlert alloc] init];
    done.messageText = [NSString stringWithFormat:forgotten == 1 ? NSLocalizedString(@"Forgot %lu word.", @"")
                                                                 : NSLocalizedString(@"Forgot %lu words.", @""), (unsigned long)forgotten];
    [done runModal];
}

+ (void)editSpellingExclusions:(id)sender
{
    [TSSpellExclusions installDefaultRulesIfNeeded];
    NSString *path = [TSSpellExclusions userRulesPath];
    if (![[NSFileManager defaultManager] fileExistsAtPath:path]) return;
    [[NSWorkspace sharedWorkspace] openURL:[NSURL fileURLWithPath:path]];
}

// The help text for the first of the languages for which the directory holds a
// SpellCheckingHelp-<language>.html (named like the Interfaces folders: de, pt-PT,
// zh_CN, ...), otherwise the English SpellCheckingHelp.html. A language such as
// pt-BR or zh-Hans-CN falls back to pt or zh_CN.
+ (NSString *)helpPathInDirectory:(NSString *)directory forLanguages:(NSArray<NSString *> *)languages
{
    NSFileManager *fm = [NSFileManager defaultManager];
    for (NSString *language in languages) {
        NSString *code = [language stringByReplacingOccurrencesOfString:@"-" withString:@"_"];
        NSMutableArray<NSString *> *candidates = [NSMutableArray array];
        for (NSString *c = code; c.length > 0; ) {
            [candidates addObject:c];
            NSRange r = [c rangeOfString:@"_" options:NSBackwardsSearch];
            c = (r.location == NSNotFound) ? @"" : [c substringToIndex:r.location];
        }
        if ([code hasPrefix:@"zh"]) [candidates addObject:@"zh_CN"];
        for (NSString *c in candidates) {
            for (NSString *name in @[c, [c stringByReplacingOccurrencesOfString:@"_" withString:@"-"]]) {
                NSString *path = [directory stringByAppendingPathComponent:
                                  [NSString stringWithFormat:@"SpellCheckingHelp-%@.html", name]];
                if ([fm fileExistsAtPath:path]) return path;
            }
        }
        if ([code isEqualToString:@"en"] || [code hasPrefix:@"en_"]) break;
    }
    return [directory stringByAppendingPathComponent:@"SpellCheckingHelp.html"];
}

// Brief help for the spell checking, shown in a small window from the Help menu.
// The text is SpellCheckingHelp.html, or a translation of it, in the application bundle.
+ (void)showSpellCheckingHelp:(id)sender
{
    static NSWindow *helpWindow;
    if (helpWindow) {
        [helpWindow makeKeyAndOrderFront:nil];
        return;
    }
    NSString *directory = [[[NSBundle mainBundle] resourcePath] stringByAppendingPathComponent:@"TeXShop/SpellCheck"];
    NSMutableArray<NSString *> *languages = [[[NSBundle mainBundle] preferredLocalizations] mutableCopy];
    [languages addObjectsFromArray:[NSLocale preferredLanguages]];
    NSString *path = [self helpPathInDirectory:directory forLanguages:languages];
#ifdef TSSPELL_STANDALONE_TEST
    if (getenv("TSSPELL_HELP")) path = [NSString stringWithUTF8String:getenv("TSSPELL_HELP")];
#endif
    NSData *data = path ? [NSData dataWithContentsOfFile:path] : nil;
    NSAttributedString *text = data
        ? [[NSAttributedString alloc] initWithData:data
                                           options:@{NSDocumentTypeDocumentAttribute: NSHTMLTextDocumentType,
                                                     NSCharacterEncodingDocumentAttribute: @(NSUTF8StringEncoding)}
                                documentAttributes:NULL error:NULL]
        : nil;
    if (!text) {
        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText = NSLocalizedString(@"The spell checking help could not be found", @"");
        [alert runModal];
        return;
    }
    // The imported text is black; use the system text colour so dark mode works.
    NSMutableAttributedString *shown = [text mutableCopy];
    [shown addAttribute:NSForegroundColorAttributeName value:[NSColor textColor]
                  range:NSMakeRange(0, shown.length)];

    NSScrollView *scroll = [NSTextView scrollableTextView];
    NSTextView *view = scroll.documentView;
    view.editable = NO;
    view.textContainerInset = NSMakeSize(16, 12);
    [view.textStorage setAttributedString:shown];
    helpWindow = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 560, 640)
                                             styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable |
                                                       NSWindowStyleMaskResizable | NSWindowStyleMaskMiniaturizable
                                               backing:NSBackingStoreBuffered defer:NO];
    helpWindow.title = NSLocalizedString(@"Spell Checking Help", @"");
    helpWindow.releasedWhenClosed = NO;
    helpWindow.contentView = scroll;
    [helpWindow center];
    [helpWindow makeKeyAndOrderFront:nil];
}

static NSMenuItem *FindMenuItemWithAction(NSMenu *menu, SEL action)
{
    for (NSMenuItem *item in menu.itemArray) {
        if (item.action == action) return item;
        if (item.submenu) {
            NSMenuItem *found = FindMenuItemWithAction(item.submenu, action);
            if (found) return found;
        }
    }
    return nil;
}

+ (void)installMenuItems
{
    NSMenuItem *check = FindMenuItemWithAction([NSApp mainMenu], @selector(checkSpelling:));
    NSMenu *menu = check.menu;
    if (!menu) return;
    if ([menu indexOfItemWithTarget:self andAction:@selector(forgetLearnedWords:)] >= 0) return;

    NSInteger at = [menu indexOfItem:check] + 1;
    NSMenuItem *forget = [[NSMenuItem alloc] initWithTitle:NSLocalizedString(@"Forget Learned Words…", @"")
                                                    action:@selector(forgetLearnedWords:) keyEquivalent:@""];
    forget.target = self;
    NSMenuItem *edit = [[NSMenuItem alloc] initWithTitle:NSLocalizedString(@"Edit Spelling Exclusions…", @"")
                                                  action:@selector(editSpellingExclusions:) keyEquivalent:@""];
    edit.target = self;
    [menu insertItem:forget atIndex:at];
    [menu insertItem:edit atIndex:at + 1];

    // A Help menu entry, after TeXShop's own "Getting Started" item. The item is
    // found by its action so this works whatever language the menu is in.
    NSMenuItem *anchor = FindMenuItemWithAction([NSApp mainMenu], NSSelectorFromString(@"displayGettingStartedTeXShop:"));
    NSMenu *helpMenu = anchor.menu ?: NSApp.helpMenu;
    if (helpMenu && [helpMenu indexOfItemWithTarget:self andAction:@selector(showSpellCheckingHelp:)] < 0) {
        NSMenuItem *help = [[NSMenuItem alloc] initWithTitle:NSLocalizedString(@"Spell Checking Help", @"")
                                                      action:@selector(showSpellCheckingHelp:) keyEquivalent:@""];
        help.target = self;
        NSInteger index = anchor ? [helpMenu indexOfItem:anchor] + 1 : (NSInteger)helpMenu.numberOfItems;
        [helpMenu insertItem:help atIndex:index];
    }
}

@end
