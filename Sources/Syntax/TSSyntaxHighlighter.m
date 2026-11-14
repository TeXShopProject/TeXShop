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

// While following edits, each attribute this highlighter adds comes with a mark of its own: the key prefixed, and the
// same value. The marks move with the text as the attributes do, and tell where an attribute is this highlighter's:
// the mark is there and the attribute still has the value it was given. Another feature's attribute is never marked,
// even if it has the same color, and one added over this highlighter's keeps its own value.
static NSString *const TSSyntaxOwnMarkPrefix = @"TSSyntaxHighlighter.";

static NSAttributedStringKey TSSyntaxOwnMark(NSAttributedStringKey key)
{
    return [TSSyntaxOwnMarkPrefix stringByAppendingString:key];
}

static NSDictionary<NSAttributedStringKey, id> *TSSyntaxMarkedAttributes(NSDictionary<NSAttributedStringKey, id> *attributes)
{
    NSMutableDictionary<NSAttributedStringKey, id> *marked = [attributes mutableCopy];
    [attributes enumerateKeysAndObjectsUsingBlock:^(NSAttributedStringKey key, id value, BOOL *stop) {
        marked[TSSyntaxOwnMark(key)] = value;
    }];
    return [marked copy];
}

@interface TSSyntaxHighlighter ()
/// The attribute keys this highlighter has added while following edits.
@property (nonatomic, readonly) NSMutableSet<NSAttributedStringKey> *ownKeys;
/// The marked attributes of each role, made once per scheme.
@property (nonatomic, readonly) NSMutableDictionary<NSNumber *, NSDictionary<NSAttributedStringKey, id> *> *markedRoles;
@property (nonatomic) BOOL followsEdits, scheduled, waitsForMarkedText;
@end

@implementation TSSyntaxHighlighter

- (instancetype)initWithTextView:(NSTextView *)textView scanner:(nullable id<TSSyntaxScanner>)scanner scheme:(nullable TSSyntaxColorScheme *)scheme
{
    if ((self = [super init])) {
        _textView = textView;
        _scanner = scanner;
        _scheme = scheme;
        _ownKeys = [NSMutableSet set];
        _markedRoles = [NSMutableDictionary dictionary];
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
    [self.markedRoles removeAllObjects];
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
    // The source (not following edits) adds the scheme's attributes as they are; text that follows edits marks them.
    NSDictionary<NSAttributedStringKey, id> *(^attributesForRole)(TSSyntaxRole) = ^NSDictionary<NSAttributedStringKey, id> *(TSSyntaxRole role) {
        return [self.scheme attributesForRole:role];
    };
    if (self.followsEdits) {
        attributesForRole = ^NSDictionary<NSAttributedStringKey, id> *(TSSyntaxRole role) {
            NSDictionary<NSAttributedStringKey, id> *marked = self.markedRoles[@(role)];
            if (!marked) {
                NSDictionary<NSAttributedStringKey, id> *attributes = [self.scheme attributesForRole:role];
                [self.ownKeys addObjectsFromArray:attributes.allKeys];
                marked = TSSyntaxMarkedAttributes(attributes);
                self.markedRoles[@(role)] = marked;
            }
            return marked;
        };
    }
    __unsafe_unretained NSDictionary<NSAttributedStringKey, id> *roles[TSSyntaxRoleCacheSize] = {nil};
    __unsafe_unretained NSDictionary<NSAttributedStringKey, id> **cache = roles;
    [scanner enumerateTokensInString:textView.string range:range usingBlock:^(NSRange token, TSSyntaxRole role, TSSyntaxTokenFlags flags) {
        if (role != TSSyntaxRoleNone) {
            NSDictionary<NSAttributedStringKey, id> *attributes;
            if (role >= 0 && role < TSSyntaxRoleCacheSize) {
                if (!cache[role])
                    cache[role] = attributesForRole(role);
                attributes = cache[role];
            } else
                attributes = attributesForRole(role);
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
    [center addObserver:self selector:@selector(storageDidFinishEditing:) name:NSTextStorageDidProcessEditingNotification object:textView.textStorage];
    [center addObserver:self selector:@selector(textViewDidChangeSelection:) name:NSTextViewDidChangeSelectionNotification object:textView];
    [self highlightWholeText];
}

// A new string, typing, pasting, undo: the whole text is colored again once the edit is done (temporary attributes
// cannot change while the text storage is still processing it).
- (void)storageDidFinishEditing:(NSNotification *)notification
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
    if (!layoutManager || length == 0 || self.ownKeys.count == 0)
        return;
    NSRange all = NSMakeRange(0, length);
    for (NSAttributedStringKey key in self.ownKeys) {
        NSAttributedStringKey mark = TSSyntaxOwnMark(key);
        for (NSUInteger i = 0; i < length; ) {
            NSRange marked;
            id markValue = [layoutManager temporaryAttribute:mark atCharacterIndex:i longestEffectiveRange:&marked inRange:all];
            if (markValue) {
                // Within the mark, only where the attribute still has the value this highlighter gave it.
                for (NSUInteger j = marked.location; j < NSMaxRange(marked); ) {
                    NSRange effective;
                    id value = [layoutManager temporaryAttribute:key atCharacterIndex:j longestEffectiveRange:&effective inRange:marked];
                    if (value == markValue)
                        [layoutManager removeTemporaryAttribute:key forCharacterRange:effective];
                    j = MAX(NSMaxRange(effective), j + 1);
                }
                [layoutManager removeTemporaryAttribute:mark forCharacterRange:marked];
            }
            i = MAX(NSMaxRange(marked), i + 1);
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
    NSUInteger length = textView.textStorage.length;
    if (length > 0 && self.scanner)
        [self applyTokensInRange:[self.scanner lineAlignedRangeForEditedRange:NSMakeRange(0, length) inString:textView.string]];
}

- (void)invalidate
{
    [NSNotificationCenter.defaultCenter removeObserver:self];
    [self removeOwnAttributes];
    self.followsEdits = NO;
    self.waitsForMarkedText = NO;
}

@end
