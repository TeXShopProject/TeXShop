// SPDX-License-Identifier: GPL-2.0-or-later
#import "TSSyntaxHighlighter.h"

// More than the number of roles; looked up once per role while a range is colored.
enum { TSSyntaxRoleCacheSize = 64 };

// Whether a view of the text storage holds text being composed with an input method.
static BOOL TSSyntaxStorageHasMarkedText(NSTextStorage *storage)
{
    for (NSLayoutManager *layoutManager in storage.layoutManagers)
        for (NSTextContainer *container in layoutManager.textContainers)
            if (container.textView.hasMarkedText)
                return YES;
    return NO;
}

@interface TSSyntaxHighlighter ()
/// Every attribute value this highlighter has added while following edits, compared by identity: removing only these
/// leaves the temporary attributes of other features alone, even after edits have moved them.
@property (nonatomic, readonly) NSHashTable *ownValues;
@property (nonatomic) BOOL followsEdits, scheduled, waitsForMarkedText;
@end

@implementation TSSyntaxHighlighter

- (instancetype)initWithTextView:(NSTextView *)textView scanner:(nullable id<TSSyntaxScanner>)scanner scheme:(nullable TSSyntaxColorScheme *)scheme
{
    if ((self = [super init])) {
        _textView = textView;
        _scanner = scanner;
        _scheme = scheme;
        _ownValues = [NSHashTable hashTableWithOptions:NSPointerFunctionsStrongMemory | NSPointerFunctionsObjectPointerPersonality];
    }
    return self;
}

- (void)dealloc
{
    [NSNotificationCenter.defaultCenter removeObserver:self];
}

- (void)setScanner:(nullable id<TSSyntaxScanner>)scanner
{
    _scanner = scanner;
    if (self.followsEdits)
        [self highlightWholeText];
}

- (void)setScheme:(nullable TSSyntaxColorScheme *)scheme
{
    _scheme = scheme;
    if (self.followsEdits)
        [self highlightWholeText];
}

- (void)applyTokensInRange:(NSRange)range
{
    NSTextView *textView = self.textView;
    NSLayoutManager *layoutManager = textView.layoutManager;
    id<TSSyntaxScanner> scanner = self.scanner;
    if (!textView || !layoutManager || !scanner)
        return;
    TSSyntaxColorScheme *scheme = self.scheme;
    NSHashTable *ownValues = self.followsEdits ? self.ownValues : nil;
    __unsafe_unretained NSDictionary<NSAttributedStringKey, id> *roles[TSSyntaxRoleCacheSize] = {nil};
    __unsafe_unretained NSDictionary<NSAttributedStringKey, id> **cache = roles;
    [scanner enumerateTokensInString:textView.string range:range usingBlock:^(NSRange token, TSSyntaxRole role, TSSyntaxTokenFlags flags) {
        if (role != TSSyntaxRoleNone) {
            NSDictionary<NSAttributedStringKey, id> *attributes;
            if (role >= 0 && role < TSSyntaxRoleCacheSize) {
                if (!cache[role]) {
                    cache[role] = [scheme attributesForRole:role];
                    for (id value in cache[role].allValues)
                        [ownValues addObject:value];
                }
                attributes = cache[role];
            } else {
                attributes = [scheme attributesForRole:role];
                for (id value in attributes.allValues)
                    [ownValues addObject:value];
            }
            if (attributes.count)
                [layoutManager addTemporaryAttributes:attributes forCharacterRange:token];
        }
        if (flags & TSSyntaxTokenFlagsNoSpellCheck)
            [textView setSpellingState:0 range:token];
    }];
}

- (void)followEdits
{
    NSTextView *textView = self.textView;
    if (!textView || self.followsEdits)
        return;
    self.followsEdits = YES;
    NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
    [center addObserver:self selector:@selector(textStorageDidProcessEditing:) name:NSTextStorageDidProcessEditingNotification object:textView.textStorage];
    [center addObserver:self selector:@selector(textViewDidChangeSelection:) name:NSTextViewDidChangeSelectionNotification object:textView];
    [self highlightWholeText];
}

// A new string, typing, pasting, undo: the whole text is colored again once the edit is done (temporary attributes
// cannot change while the text storage is still processing it).
- (void)textStorageDidProcessEditing:(NSNotification *)notification
{
    NSTextStorage *storage = notification.object;
    if (storage.editedMask & NSTextStorageEditedCharacters)
        [self scheduleHighlight];
}

// The selection changes whenever composed text changes, is committed or is removed.
- (void)textViewDidChangeSelection:(NSNotification *)notification
{
    if (self.waitsForMarkedText)
        [self scheduleHighlight];
}

- (void)scheduleHighlight
{
    if (self.scheduled)
        return;
    self.scheduled = YES;
    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        TSSyntaxHighlighter *highlighter = weakSelf;
        highlighter.scheduled = NO;
        if (highlighter.followsEdits)
            [highlighter highlightWholeText];
    });
}

- (void)removeOwnAttributes
{
    NSTextView *textView = self.textView;
    NSLayoutManager *layoutManager = textView.layoutManager;
    NSUInteger length = textView.textStorage.length;
    if (!layoutManager || length == 0 || self.ownValues.count == 0)
        return;
    NSRange all = NSMakeRange(0, length);
    for (NSAttributedStringKey key in @[NSForegroundColorAttributeName, NSBackgroundColorAttributeName, NSUnderlineColorAttributeName]) {
        for (NSUInteger i = 0; i < length; ) {
            NSRange effective;
            id value = [layoutManager temporaryAttribute:key atCharacterIndex:i longestEffectiveRange:&effective inRange:all];
            if (value && [self.ownValues containsObject:value]) {
                [layoutManager removeTemporaryAttribute:key forCharacterRange:effective];
                // The underline style is a plain number; it goes with the underline color it came with.
                if ([key isEqualToString:NSUnderlineColorAttributeName])
                    [layoutManager removeTemporaryAttribute:NSUnderlineStyleAttributeName forCharacterRange:effective];
            }
            i = MAX(NSMaxRange(effective), i + 1);
        }
    }
}

- (void)highlightWholeText
{
    NSTextView *textView = self.textView;
    if (!textView.layoutManager)
        return;
    if (TSSyntaxStorageHasMarkedText(textView.textStorage)) {
        self.waitsForMarkedText = YES;
        return;
    }
    self.waitsForMarkedText = NO;
    [self removeOwnAttributes];
    [self.ownValues removeAllObjects];
    NSUInteger length = textView.textStorage.length;
    if (length > 0 && self.scanner)
        [self applyTokensInRange:[self.scanner lineAlignedRangeForEditedRange:NSMakeRange(0, length) inString:textView.string]];
}

- (void)invalidate
{
    [NSNotificationCenter.defaultCenter removeObserver:self];
    [self removeOwnAttributes];
    [self.ownValues removeAllObjects];
    self.followsEdits = NO;
    self.waitsForMarkedText = NO;
}

@end
