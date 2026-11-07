/*
 * TeXShop - TeX editor for Mac OS
 * Copyright (C) 2026 Ralph Martin and Yusuke Terada
 * SPDX-License-Identifier: GPL-2.0-or-later
 * TeX-aware spelling implementation by Ralph Martin.
 *
 * See TSSpellSupport.h.
 *
 * This file is part of the TeX-aware spell checking added to TeXShop. It is
 * distributed under the same GNU General Public License as TeXShop.
 */

#import "TSSpellSupport.h"
#import "TSSpellExclusions.h"
#import <objc/runtime.h>

// Text views that can check spelling TeX-aware (TSTextView).
@protocol TSTeXAwareTextView
- (BOOL)usesTeXAwareSpellChecking;
@end

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

@implementation TSSpellSupport

#pragma mark - Find Next

// Scroll so the line containing `range` is vertically centred in the visible
// area, as far as the ends of the document allow.
+ (void)centerRange:(NSRange)range inTextView:(NSTextView *)tv
{
    NSScrollView *sv = tv.enclosingScrollView;
    if (!sv) { [tv scrollRangeToVisible:range]; return; }
    NSLayoutManager *lm = tv.layoutManager;
    // Lay out only as much as is needed to place the range, not the whole text.
    [lm ensureLayoutForCharacterRange:range];
    NSRange glyphs = [lm glyphRangeForCharacterRange:range actualCharacterRange:NULL];
    NSRect r = [lm boundingRectForGlyphRange:glyphs inTextContainer:tv.textContainer];
    CGFloat midY = NSMidY(r) + tv.textContainerOrigin.y;
    NSClipView *clip = sv.contentView;
    CGFloat viewH = clip.bounds.size.height;
    CGFloat docH = MAX(tv.frame.size.height, NSMaxY(r) + 2 * tv.textContainerOrigin.y);
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
    // The checker is called once for each run of segments that are checked in
    // the same language. Segments without a letter or digit (blanks, and the
    // braces left between language commands) have no words to check; they are
    // left out, and the runs on either side of one can join.
    NSCharacterSet *wordCharacters = [NSCharacterSet alphanumericCharacterSet];
    NSRange run = NSMakeRange(NSNotFound, 0);
    NSString *runLanguage = nil;
    for (NSUInteger k = 0; k <= [segments count]; k++) {
        TSSpellLanguageSegment *segment = (k < [segments count]) ? segments[k] : nil;
        NSString *language = nil;
        BOOL checked = YES;
        if (segment) {
            if (NSMaxRange(segment.range) <= from) continue;
            if ([masked rangeOfCharacterFromSet:wordCharacters options:NSLiteralSearch range:segment.range].location == NSNotFound) continue;
            if (segment.language) {
                BOOL isDocument;
                language = [self checkerLanguageForCode:segment.language isDocumentLanguage:&isDocument];
                if (!isDocument && !language) checked = NO;     // no checker for this language
                if (isDocument) language = nil;
            }
            if (checked && run.location != NSNotFound && (language == runLanguage || [language isEqualToString:runLanguage])) {
                run.length = NSMaxRange(segment.range) - run.location;
                continue;
            }
        }
        if (run.location != NSNotFound) {
            NSString *text = [masked substringWithRange:run];
            NSUInteger offset = from > run.location ? from - run.location : 0;
            NSRange bad = [checker checkSpellingOfString:text startingAt:(NSInteger)offset language:runLanguage wrap:NO
                                  inSpellDocumentWithTag:tag wordCount:NULL];
            if (bad.location != NSNotFound && bad.length > 0)
                return NSMakeRange(bad.location + run.location, bad.length);
        }
        run = (segment && checked) ? segment.range : NSMakeRange(NSNotFound, 0);
        runLanguage = language;
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

+ (BOOL)mask:(TSSpellMask *)mask excludesSpellingInRange:(NSRange)range
{
    if ([mask rangeTouchesExclusion:range] || [mask rangeIsNextToAccent:range]) return YES;
    // Text in another language than the document's (\foreignlanguage, ...) is
    // checked by the review, in its own language, but not marked while typing.
    return [self rangeIsInOtherLanguage:range mask:mask];
}

#pragma mark - Change All

// The text view and the (masked) word last offered to the Spelling and Grammar
// panel, which "Change All" works on.
static __weak NSTextView *sReviewView;
static NSString *sReviewWord;

// Bind replacement to the document and snapshot reviewed.
static NSString *sReviewText;
static NSRange sReviewSelection;
static NSTextField *sReplacementField;
static NSTextField *sReplacementStatus;
static BOOL sUpdatingSpellingPanel;
static __weak NSEvent *sPanelUpdateEvent;

static BOOL ReviewIsCurrent(NSTextView *view)
{
    return view && view.window && view.window == NSApp.mainWindow &&
        view.window.firstResponder == view &&
        [view.string isEqualToString:sReviewText] &&
        NSEqualRanges(view.selectedRange, sReviewSelection);
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
    NSString *replacement = [sReplacementField.stringValue stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (!ReviewIsCurrent(tv) || word.length == 0) {
        sReplacementStatus.stringValue = NSLocalizedString(@"Return to the word and choose Find Next before replacing.", @"");
        NSBeep(); return;
    }
    if (replacement.length == 0 || [replacement isEqualToString:word]) {
        sReplacementStatus.stringValue = NSLocalizedString(@"Enter a different replacement in the Change All field.", @"");
        NSBeep(); return;
    }
    sReplacementStatus.stringValue = @"";
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

// Find the current panel's table in its view hierarchy. Its contents are
// checked separately before copying a suggestion.
static NSTableView *SuggestionTable(NSView *view)
{
    if ([view isKindOfClass:NSTableView.class]) return (NSTableView *)view;
    for (NSView *sub in view.subviews) {
        NSTableView *found = SuggestionTable(sub);
        if (found) return found;
    }
    return nil;
}

// The suggestion in the given row of the panel's table, or nil.
static NSString *SuggestionAtRow(NSTableView *table, NSInteger row)
{
    id<NSTableViewDataSource> source = table.dataSource;
    if (row < 0 || row >= table.numberOfRows || table.tableColumns.count != 1 ||
        ![source respondsToSelector:@selector(tableView:objectValueForTableColumn:row:)]) return nil;
    id value = [source tableView:table objectValueForTableColumn:table.tableColumns.firstObject row:row];
    return ([value isKindOfClass:NSString.class] && [value length]) ? value : nil;
}

// Experimental bridge: AppKit currently uses a one-column, cell-based table
// for spelling suggestions. Its selection is not an NSSpellChecker API contract.
// Observe public table notifications without replacing AppKit's delegate or
// action. If the structure changes, leave manual replacement entry available.
+ (void)spellingSuggestionSelectionDidChange:(NSNotification *)notification
{
    if (sUpdatingSpellingPanel || !sReplacementField || !sReviewWord.length ||
        ![notification.object isKindOfClass:NSTableView.class]) return;
    NSSpellChecker *checker = NSSpellChecker.sharedSpellChecker;
    NSPanel *panel = checker.spellingPanel;
    NSTableView *table = notification.object;
    if (checker.accessoryView != sReplacementField.superview ||
        !panel.isVisible || table.window != panel ||
        table.tableColumns.count != 1 || table.numberOfSelectedRows != 1) return;
    // The standard panel's suggestion table can refuse first-responder status.
    // Identify candidate input by its event instead of requiring table focus.

    // Suppress our synchronous panel update and notifications still associated
    // with the event that started it. This does not identify every possible
    // asynchronous AppKit update. Require later input in the candidate list.
    NSEvent *event = NSApp.currentEvent;
    if (!event || event == sPanelUpdateEvent || event.window != panel) return;
    if (event.type == NSEventTypeLeftMouseDown || event.type == NSEventTypeLeftMouseUp) {
        NSPoint point = [table convertPoint:event.locationInWindow fromView:nil];
        if (!NSPointInRect(point, NSIntersectionRect(table.bounds, table.visibleRect))) return;
    } else {
        // Typing can also refresh the list. Only arrow navigation counts as
        // choosing a candidate; arrows in our replacement editor must not copy.
        if (event.type != NSEventTypeKeyDown ||
            (event.modifierFlags & NSEventModifierFlagCommand) ||
            (sReplacementField.currentEditor &&
             panel.firstResponder == sReplacementField.currentEditor)) return;
        NSString *keys = event.charactersIgnoringModifiers;
        if (keys.length != 1 ||
            ([keys characterAtIndex:0] != NSUpArrowFunctionKey &&
             [keys characterAtIndex:0] != NSDownArrowFunctionKey)) return;
    }
    if (!ReviewIsCurrent(sReviewView)) return;

    NSString *value = SuggestionAtRow(table, table.selectedRow);
    if (!value) return;
    sReplacementField.stringValue = value;
    sReplacementStatus.stringValue = @"";
}

// The replacement field remains a documented accessoryView and can always be
// edited manually. Selecting a suggestion only fills it; it does not replace text.
+ (void)installChangeAllButton
{
    if (sReplacementField) return;
    NSView *accessory = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 431, 76)];
    sReplacementField = [[NSTextField alloc] initWithFrame:NSMakeRect(8, 47, 290, 22)];
    sReplacementField.placeholderString = NSLocalizedString(@"Replacement for Change All", @"");
    sReplacementField.autoresizingMask = NSViewWidthSizable;
    sReplacementField.target = self;
    sReplacementField.action = @selector(changeAll:);
    [accessory addSubview:sReplacementField];
    sReplacementStatus = [NSTextField wrappingLabelWithString:@""];
    sReplacementStatus.frame = NSMakeRect(8, 3, 415, 38);
    sReplacementStatus.font = [NSFont systemFontOfSize:NSFont.smallSystemFontSize];
    sReplacementStatus.textColor = NSColor.secondaryLabelColor;
    sReplacementStatus.autoresizingMask = NSViewWidthSizable;
    [accessory addSubview:sReplacementStatus];
    NSButton *button = [NSButton buttonWithTitle:NSLocalizedString(@"Change All", @"")
                                        target:self action:@selector(changeAll:)];
    button.frame = NSMakeRect(307, 45, 116, 26);
    button.autoresizingMask = NSViewMinXMargin;
    [accessory addSubview:button];
    [NSSpellChecker sharedSpellChecker].accessoryView = accessory;
    [NSNotificationCenter.defaultCenter addObserver:self
        selector:@selector(spellingSuggestionSelectionDidChange:)
        name:NSTableViewSelectionDidChangeNotification object:nil];
}

+ (NSString *)findNextMisspellingInTextView:(NSTextView *)tv mask:(TSSpellMask *)mask
{
    [self installChangeAllButton];
    NSSpellChecker *checker = [NSSpellChecker sharedSpellChecker];
    NSString *masked = mask.masked;
    NSInteger tag = tv.spellCheckerDocumentTag;
    sReviewView = tv;
    sReviewWord = nil;
    sReviewText = nil;
    sReplacementField.stringValue = @"";
    sReplacementStatus.stringValue = @"";
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
    sReviewText = [tv.string copy];
    sReviewSelection = tv.selectedRange;
    sUpdatingSpellingPanel = YES;
    sPanelUpdateEvent = NSApp.currentEvent;
    @try {
        [checker updateSpellingPanelWithMisspelledWord:word];
    } @finally {
        sUpdatingSpellingPanel = NO;
    }
    // When there is only one suggestion the panel selects it itself, while the
    // observer above is ignoring its own update, so copy it here.
    NSTableView *table = SuggestionTable(checker.spellingPanel.contentView);
    if (checker.accessoryView == sReplacementField.superview &&
        ReviewIsCurrent(tv) && sReplacementField.stringValue.length == 0 &&
        table.numberOfRows == 1 && table.numberOfSelectedRows == 1) {
        NSString *selected = SuggestionAtRow(table, table.selectedRow);
        if (selected) sReplacementField.stringValue = selected;
    }
    return word;
}

+ (void)showSpellingPanelForTextView:(NSTextView *)tv mask:(TSSpellMask *)mask openPanel:(void (^)(void))openPanel
{
    NSRange before = tv.selectedRange;
    [self installChangeAllButton];
    openPanel();                        // shows the panel; the system also selects "its" first misspelling
    tv.selectedRange = before;          // undo that markup-blind search
    NSString *word = [self findNextMisspellingInTextView:tv mask:mask];

    // Do not schedule another search with a captured mask: the document or
    // selection can change before it executes. Find Next starts a fresh review.
    (void)word;
}

#pragma mark - Menu items

// The different words of `text` that are longer than one letter.
static NSArray<NSString *> *CandidateWords(NSString *text)
{
    NSMutableSet<NSString *> *candidates = [NSMutableSet set];
    if ([text length]) {
        [text enumerateSubstringsInRange:NSMakeRange(0, [text length])
                                 options:NSStringEnumerationByWords
                              usingBlock:^(NSString *w, NSRange r, NSRange er, BOOL *stop) {
            if ([w length] > 1) [candidates addObject:w];
        }];
    }
    return [candidates allObjects];
}

static void SortWords(NSMutableArray<NSString *> *words)
{
    [words sortUsingComparator:^NSComparisonResult(NSString *a, NSString *b) {
        return [a localizedCaseInsensitiveCompare:b];
    }];
}

+ (NSArray<NSString *> *)learnedWordsInText:(NSString *)text
{
    NSSpellChecker *checker = [NSSpellChecker sharedSpellChecker];
    NSMutableArray<NSString *> *learned = [NSMutableArray array];
    for (NSString *w in CandidateWords(text))
        if ([checker hasLearnedWord:w]) [learned addObject:w];
    SortWords(learned);
    return learned;
}

// Look up words[start...] a batch at a time, letting the main run loop handle
// events between batches.
+ (void)lookUpWords:(NSArray<NSString *> *)words from:(NSUInteger)start learned:(NSMutableArray<NSString *> *)learned
         completion:(void (^)(NSArray<NSString *> *))completion
{
    NSSpellChecker *checker = [NSSpellChecker sharedSpellChecker];
    NSUInteger end = MIN([words count], start + 200);
    for (NSUInteger k = start; k < end; k++)
        if ([checker hasLearnedWord:words[k]]) [learned addObject:words[k]];
    if (end < [words count]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self lookUpWords:words from:end learned:learned completion:completion];
        });
        return;
    }
    SortWords(learned);
    completion(learned);
}

+ (void)findLearnedWordsInText:(NSString *)text masked:(BOOL)masked completion:(void (^)(NSArray<NSString *> *))completion
{
    NSString *copy = [text copy];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSString *checked = (masked && copy) ? [[TSSpellExclusions sharedExclusions] maskForText:copy].masked : copy;
        NSArray<NSString *> *words = CandidateWords(checked);
        dispatch_async(dispatch_get_main_queue(), ^{
            [self lookUpWords:words from:0 learned:[NSMutableArray array] completion:completion];
        });
    });
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

// The text view of the document being edited, for finding learned words in it.
static NSTextView *FrontTextView(void)
{
    NSTextView *tv = nil;
    NSWindow *window = NSApp.mainWindow ?: NSApp.keyWindow;
    if ([window.firstResponder isKindOfClass:[NSTextView class]]) tv = (NSTextView *)window.firstResponder;
    if (!tv) {
        @try { tv = [[[NSDocumentController sharedDocumentController] currentDocument] valueForKey:@"textView"]; }
        @catch (NSException *e) { tv = nil; }
    }
    return [tv isKindOfClass:[NSTextView class]] ? tv : nil;
}

+ (void)forgetLearnedWords:(id)sender
{
    NSTextView *tv = FrontTextView();
    // Only the words the spell checker is given can have been learned from
    // this document: with TeX-aware spelling, those of the masked text.
    BOOL masked = [tv respondsToSelector:@selector(usesTeXAwareSpellChecking)] &&
                  [(id<TSTeXAwareTextView>)tv usesTeXAwareSpellChecking];
    [self forgetLearnedWordsFoundInText:tv.string masked:masked];
}

+ (void)forgetLearnedWordsFoundInText:(NSString *)text
{
    [self forgetLearnedWordsFoundInText:text masked:NO];
}

+ (void)forgetLearnedWordsFoundInText:(NSString *)text masked:(BOOL)masked
{
    // The words are looked up without blocking the application; a second
    // request while that is going on is ignored.
    static BOOL looking;
    if (looking) { NSBeep(); return; }
    looking = YES;
    [self findLearnedWordsInText:text masked:masked completion:^(NSArray<NSString *> *words) {
        looking = NO;
        [self showLearnedWords:words];
    }];
}

+ (void)showLearnedWords:(NSArray<NSString *> *)words
{
    NSSpellChecker *checker = [NSSpellChecker sharedSpellChecker];
    NSString *language = checker.language ?: @"";

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

// The exclusion rules apply only to TeX-aware spell checking, so they can be
// edited only while it is on.
+ (BOOL)validateMenuItem:(NSMenuItem *)item
{
    if (item.action == @selector(editSpellingExclusions:))
        return [[NSUserDefaults standardUserDefaults] boolForKey:@"TeXAwareSpellChecking"];
    return YES;
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

// A mode change invalidates the review and its replacement field. Only remove
// our own accessory; AppKit or another component may have installed one.
+ (void)preferencesDidChange
{
    [NSNotificationCenter.defaultCenter removeObserver:self
        name:NSTableViewSelectionDidChangeNotification object:nil];
    sPanelUpdateEvent = nil;
    sReviewView = nil;
    sReviewWord = nil;
    sReviewText = nil;
    if (sReplacementField) {
        NSView *accessory = sReplacementField.superview;
        NSSpellChecker *checker = NSSpellChecker.sharedSpellChecker;
        if (checker.accessoryView == accessory) checker.accessoryView = nil;
        sReplacementField = nil;
        sReplacementStatus = nil;
    }
    for (NSWindow *window in NSApp.windows)
        [self refreshSpellingInView:window.contentView];
}

+ (void)refreshSpellingInView:(NSView *)view
{
    if ([view isKindOfClass:NSTextView.class] &&
        [view respondsToSelector:@selector(usesTeXAwareSpellChecking)]) {
        NSTextView *textView = (NSTextView *)view;
        NSRange range = NSMakeRange(0, textView.string.length);
        [textView setSpellingState:0 range:range];
        if (textView.continuousSpellCheckingEnabled && range.length)
            [textView checkTextInRange:range types:NSTextCheckingTypeSpelling options:@{}];
    }
    for (NSView *child in view.subviews) [self refreshSpellingInView:child];
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


#pragma mark - Mask cache

@implementation TSSpellMaskCache {
    __weak NSTextStorage *_storage;
    TSSpellMask *_mask;                         // nil when the text or the rules changed since it was made
    NSUInteger _rulesGeneration;                // of the rules _mask was made with
    NSUInteger _edits;                          // changes to the characters so far
    NSTimeInterval _lastEdit;
    NSUInteger _job;                            // number of the latest masking started
    BOOL _waiting;                              // a long text is to be masked when editing pauses
    NSMutableArray<NSValue *> *_unmasked;       // ranges checked while there was no mask
}

static char sCacheKey;
static NSUInteger sDeferredLength = 200000;
static NSTimeInterval sPauseDelay = 0.5;

+ (NSUInteger)deferredLength { return sDeferredLength; }
+ (void)setDeferredLength:(NSUInteger)length { sDeferredLength = length; }
+ (NSTimeInterval)pauseDelay { return sPauseDelay; }
+ (void)setPauseDelay:(NSTimeInterval)delay { sPauseDelay = delay; }

+ (TSSpellMaskCache *)cacheForTextStorage:(NSTextStorage *)storage
{
    if (!storage) return nil;
    TSSpellMaskCache *cache = objc_getAssociatedObject(storage, &sCacheKey);
    if (!cache) {
        cache = [[self alloc] initWithTextStorage:storage];
        objc_setAssociatedObject(storage, &sCacheKey, cache, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    return cache;
}

- (instancetype)initWithTextStorage:(NSTextStorage *)storage
{
    if ((self = [super init])) {
        _storage = storage;
        _unmasked = [NSMutableArray array];
        // Edits in any pane, undo and reloads all go through the storage.
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(storageEdited:)
                                                     name:NSTextStorageDidProcessEditingNotification object:storage];
    }
    return self;
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)storageEdited:(NSNotification *)notification
{
    NSTextStorage *storage = notification.object;
    if (!(storage.editedMask & NSTextStorageEditedCharacters)) return;
    _edits++;
    _lastEdit = NSProcessInfo.processInfo.systemUptime;
    _mask = nil;
    // Keep the ranges waiting for a mask in step with the text; those the edit
    // touches are checked again by the system anyway.
    NSRange edited = storage.editedRange;
    NSInteger delta = storage.changeInLength;
    NSUInteger replacedEnd = (NSUInteger)((NSInteger)NSMaxRange(edited) - delta);
    NSMutableArray<NSValue *> *kept = [NSMutableArray arrayWithCapacity:_unmasked.count];
    for (NSValue *value in _unmasked) {
        NSRange r = value.rangeValue;
        if (NSMaxRange(r) < edited.location) [kept addObject:value];
        else if (r.location > replacedEnd) [kept addObject:[NSValue valueWithRange:NSMakeRange((NSUInteger)((NSInteger)r.location + delta), r.length)]];
    }
    _unmasked = kept;
    if (_waiting) [self scheduleMasking];
}

- (void)invalidate
{
    _mask = nil;
}

- (TSSpellMask *)maskForCheckingRange:(NSRange)range
{
    NSTextStorage *storage = _storage;
    if (!storage) return nil;
    TSSpellExclusions *exclusions = [TSSpellExclusions sharedExclusions];
    [exclusions reloadIfChanged];
    if (_mask && _rulesGeneration == exclusions.generation) return _mask;
    if (storage.length < sDeferredLength) return [self freshMask];
    if (range.location != NSNotFound) [_unmasked addObject:[NSValue valueWithRange:range]];
    if (!_waiting) {
        _waiting = YES;
        [self scheduleMasking];
    }
    return nil;
}

- (TSSpellMask *)freshMask
{
    NSTextStorage *storage = _storage;
    if (!storage) return nil;
    TSSpellExclusions *exclusions = [TSSpellExclusions sharedExclusions];
    [exclusions reloadIfChanged];
    NSUInteger generation = exclusions.generation;
    _job++;                                     // any masking under way is out of date
    TSSpellMask *mask = [exclusions maskForText:[storage.string copy]];
    [self installMask:mask rulesGeneration:generation];
    return mask;
}

// Mask the text once editing has paused.
- (void)scheduleMasking
{
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(startMasking) object:nil];
    NSTimeInterval delay = MAX(0, _lastEdit + sPauseDelay - NSProcessInfo.processInfo.systemUptime);
    [self performSelector:@selector(startMasking) withObject:nil afterDelay:delay inModes:@[NSRunLoopCommonModes]];
}

// Mask a copy of the text off the main thread. The result is used only if the
// text has not changed in the meantime; if it has, the edit has scheduled
// another masking.
- (void)startMasking
{
    NSTextStorage *storage = _storage;
    if (!storage || !_waiting) return;
    TSSpellExclusions *exclusions = [TSSpellExclusions sharedExclusions];
    NSString *text = [storage.string copy];
    NSUInteger edits = _edits, generation = exclusions.generation, job = ++_job;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        TSSpellMask *mask = [exclusions maskForText:text];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (job != self->_job || edits != self->_edits) return;
            [self installMask:mask rulesGeneration:generation];
        });
    });
}

// Make `mask` the current one, and remove the marks the check while typing set,
// while there was no mask, where the mask excludes the text.
- (void)installMask:(TSSpellMask *)mask rulesGeneration:(NSUInteger)generation
{
    _mask = mask;
    _rulesGeneration = generation;
    _waiting = NO;
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(startMasking) object:nil];
    NSArray<NSValue *> *ranges = _unmasked;
    _unmasked = [NSMutableArray array];
    NSTextStorage *storage = _storage;
    if (!storage || ranges.count == 0) return;
    NSMutableArray<NSTextView *> *views = [NSMutableArray array];
    for (NSLayoutManager *layoutManager in storage.layoutManagers)
        for (NSTextContainer *container in layoutManager.textContainers) {
            NSTextView *view = container.textView;
            if ([view respondsToSelector:@selector(usesTeXAwareSpellChecking)] &&
                [(id<TSTeXAwareTextView>)view usesTeXAwareSpellChecking])
                [views addObject:view];
        }
    for (NSValue *value in ranges) {
        NSRange r = value.rangeValue;
        if (r.length == 0 || NSMaxRange(r) > storage.length) continue;
        if (![TSSpellSupport mask:mask excludesSpellingInRange:r]) continue;
        for (NSTextView *view in views) [view setSpellingState:0 range:r];
    }
}

@end
