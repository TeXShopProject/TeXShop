// SPDX-License-Identifier: GPL-2.0-or-later
#import "TSTeXRootDocumentApplier.h"

static NSMutableArray<TSTeXRootDocumentApplier *> *TSAppliers;
static NSMutableArray<dispatch_block_t> *TSWaitingForNotApplying;
static NSPointerArray *TSLockedStorages;
static BOOL TSRunning;

/// The changes that take `replacements` (ascending, in `text`) back after the first `applied` of them, counted from
/// the end, and `inserted` characters of the next one's string are in: in the text of now, ascending.
static NSArray<TSRegexFindReplacement *> *TSTakingBack(NSArray<TSRegexFindReplacement *> *replacements, NSString *text, NSUInteger applied, NSUInteger inserted)
{
    NSMutableArray<TSRegexFindReplacement *> *back = [NSMutableArray array];
    NSUInteger total = replacements.count;
    if (applied > total)
        applied = total;
    NSInteger shift = 0;
    // Those before the one partly in are as they were; the parts went from the end.
    NSUInteger first = total - applied;
    if (inserted > 0 && first > 0) {
        TSRegexFindReplacement *partial = replacements[first - 1];
        [back addObject:[[TSRegexFindReplacement alloc] initWithRange:NSMakeRange(partial.range.location, inserted)
                                                                string:[text substringWithRange:partial.range]]];
        shift += (NSInteger)inserted - (NSInteger)partial.range.length;
    }
    for (NSUInteger i = first; i < total; i++) {
        TSRegexFindReplacement *replacement = replacements[i];
        NSRange now = NSMakeRange((NSUInteger)((NSInteger)replacement.range.location + shift), replacement.string.length);
        [back addObject:[[TSRegexFindReplacement alloc] initWithRange:now string:[text substringWithRange:replacement.range]]];
        shift += (NSInteger)replacement.string.length - (NSInteger)replacement.range.length;
    }
    return back;
}

/// Registers `changes` (ascending, in the text of now) as the Undo (or, while undoing, the Redo), with `inverse` (in the
/// text after them) as what that one registers in turn. Both are made at once through the text view; NSTextView's own
/// registration is not used, as the Redo it registers while undoing a change made this way is wrong (macOS 27).
static void TSRegisterChanges(NSUndoManager *undo, NSTextView *view, NSArray<TSRegexFindReplacement *> *changes,
                              NSArray<TSRegexFindReplacement *> *inverse, NSString *name)
{
    __weak NSTextView *weakView = view;
    [undo registerUndoWithTarget:(NSTextStorage *_Nonnull)view.textStorage handler:^(NSTextStorage *storage) {
        NSTextView *textView = weakView;
        NSUndoManager *manager = textView.undoManager;
        if (!textView || textView.textStorage != storage || !manager)
            return;
        NSMutableArray<NSValue *> *ranges = [NSMutableArray array];
        NSMutableArray<NSString *> *strings = [NSMutableArray array];
        for (TSRegexFindReplacement *change in changes) {
            [ranges addObject:[NSValue valueWithRange:change.range]];
            [strings addObject:change.string];
        }
        [manager disableUndoRegistration];
        BOOL allowed = [textView shouldChangeTextInRanges:ranges replacementStrings:strings];
        if (allowed) {
            [storage beginEditing];
            for (TSRegexFindReplacement *change in changes.reverseObjectEnumerator)
                [storage replaceCharactersInRange:change.range withString:change.string];
            [storage endEditing];
            [textView didChangeText];
        }
        [manager enableUndoRegistration];
        // Refused (read-only, for one): the step stays where it is, and comes back for the next try.
        TSRegisterChanges(manager, textView, allowed ? inverse : changes, allowed ? changes : inverse, name);
        [manager setActionName:name];
    }];
    [undo setActionName:name];
}

@interface TSTeXRootDocumentApplier ()
@property (nonatomic, readwrite, weak) NSTextView *textView;
@property (nonatomic, weak) NSTextStorage *storage;
@property (nonatomic, copy) NSArray<TSRegexFindReplacement *> *replacements;
@property (nonatomic, copy) NSString *actionName;
@property (nonatomic, readwrite) BOOL applying;
@property (nonatomic, readwrite) TSTeXRootApplyOutcome outcome;
@property (nonatomic, readwrite) TSTeXRootApplyReason reason;
@property (nonatomic, readwrite) NSUInteger numberOfParts;
@property (nonatomic, copy, nullable) void (^completion)(TSTeXRootDocumentApplier *applier);
/// What the parts put in now: the replacements, or the changes that take them back.
@property (nonatomic, copy) NSArray<TSRegexFindReplacement *> *changes;
/// The next change, counted from the last one (the parts go from the end of the text to its start, so that the ranges
/// of those not yet made stay as they are), and how much of its string is in the text already.
@property (nonatomic) NSUInteger nextFromEnd;
@property (nonatomic) NSUInteger insertedOfNext;
@property (nonatomic) BOOL takingBack;
@property (nonatomic) TSTeXRootApplyReason takingBackReason;
@property (nonatomic) BOOL changingText;
@property (nonatomic) BOOL changedUnexpectedly;
@property (nonatomic) BOOL stopRequested;
@property (nonatomic) BOOL ended;
@end

@implementation TSTeXRootDocumentApplier

- (instancetype)initWithTextView:(NSTextView *)textView replacements:(NSArray<TSRegexFindReplacement *> *)replacements
                    originalText:(NSString *)originalText actionName:(NSString *)actionName
{
    if (!(self = [super init]))
        return nil;
    _textView = textView;
    _storage = textView.textStorage;
    _replacements = [replacements copy];
    _changes = _replacements;
    _originalText = [originalText copy];
    _actionName = [actionName copy];
    _maximumReplacements = 1000;
    _maximumCharacters = 50000;
    _outcome = TSTeXRootApplyOutcomeNotApplied;
    return self;
}

- (void)dealloc
{
    [NSNotificationCenter.defaultCenter removeObserver:self];
}

- (void)startWithCompletion:(void (^)(TSTeXRootDocumentApplier *applier))completion
{
    self.completion = completion;
    NSTextStorage *storage = self.storage;
    NSTextView *view = self.textView;
    if (!view || !storage || view.textStorage != storage) {
        [self endWithOutcome:TSTeXRootApplyOutcomeNotApplied reason:TSTeXRootApplyReasonChanged];
        return;
    }
    // From now on any change of the text is seen; the text of now is compared with the one approved on a background
    // queue (a whole 10 MB text takes some 50 ms to compare, the copy nothing).
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(storageWillProcessEditing:)
                                               name:NSTextStorageWillProcessEditingNotification object:storage];
    self.applying = YES;
    [TSTeXRootReplaceGuard addApplier:self];
    [self text:storage isOriginal:^(BOOL same) {
        // The version approved (spec §2.5.1a): the same text, in the same text storage, shown by the same view.
        if (!same || self.changedUnexpectedly || self.textView.textStorage != storage) {
            [self endWithOutcome:TSTeXRootApplyOutcomeNotApplied reason:TSTeXRootApplyReasonChanged];
            return;
        }
        // The typing before is an Undo step of its own.
        [self.textView breakUndoCoalescing];
        [self scheduleNextPart];
    }];
}

/// Whether the text of `storage` now is the one approved, told on the main thread.
- (void)text:(NSTextStorage *)storage isOriginal:(void (^)(BOOL same))answer
{
    NSString *now = [storage.string copy];
    NSString *original = self.originalText;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        BOOL same = [now isEqualToString:original];
        dispatch_async(dispatch_get_main_queue(), ^{
            answer(same);
        });
    });
}

- (void)stop
{
    self.stopRequested = YES;
}

/// Any change of the text that is not one of the parts.
- (void)storageWillProcessEditing:(NSNotification *)notification
{
    NSTextStorage *storage = notification.object;
    if (!self.changingText && (storage.editedMask & NSTextStorageEditedCharacters))
        self.changedUnexpectedly = YES;
}

- (void)scheduleNextPart
{
    // After the events waiting: ■ and Escape are handled between two parts.
    [self performSelector:@selector(applyNextPart) withObject:nil afterDelay:0 inModes:@[NSRunLoopCommonModes]];
}

/// The changes and inserts of the next part, in the coordinates of the text before it, from the end of the text.
- (BOOL)nextPartRanges:(NSMutableArray<NSValue *> *)ranges strings:(NSMutableArray<NSString *> *)strings
{
    NSUInteger count = 0, characters = 0;
    NSUInteger total = self.changes.count;
    while (self.nextFromEnd < total && count < self.maximumReplacements) {
        TSRegexFindReplacement *change = self.changes[total - 1 - self.nextFromEnd];
        NSString *string = change.string;
        NSUInteger done = self.insertedOfNext;
        NSUInteger room = self.maximumCharacters > characters ? self.maximumCharacters - characters : 0;
        if (string.length - done > room && count > 0)
            break; // its own part
        NSUInteger take = string.length - done;
        if (take > self.maximumCharacters) {
            take = self.maximumCharacters;
            // Never between the two halves of a composed character.
            NSRange composed = [string rangeOfComposedCharacterSequenceAtIndex:done + take];
            if (composed.location > done)
                take = composed.location - done;
        }
        NSString *piece = [string substringWithRange:NSMakeRange(done, take)];
        // The first piece takes the place of the match; the others follow what is in already.
        NSRange range = done == 0 ? change.range : NSMakeRange(change.range.location + done, 0);
        [ranges addObject:[NSValue valueWithRange:range]];
        [strings addObject:piece];
        count++;
        characters += take;
        if (done + take < string.length) {
            self.insertedOfNext = done + take;
            break; // the rest goes in at a place this part moves
        }
        self.insertedOfNext = 0;
        self.nextFromEnd++;
    }
    return ranges.count > 0;
}

- (void)applyNextPart
{
    if (self.ended)
        return;
    NSTextView *view = self.textView;
    NSTextStorage *storage = self.storage;
    if (self.changedUnexpectedly || !view || !storage || view.textStorage != storage) {
        [self endPartially];
        return;
    }
    if (self.stopRequested && !self.takingBack) {
        [self takeBackWithReason:TSTeXRootApplyReasonStopped];
        return;
    }
    NSMutableArray<NSValue *> *ranges = [NSMutableArray array];
    NSMutableArray<NSString *> *strings = [NSMutableArray array];
    NSUInteger nextFromEnd = self.nextFromEnd, insertedOfNext = self.insertedOfNext;
    if (![self nextPartRanges:ranges strings:strings]) {
        [self finish];
        return;
    }
    if (!self.takingBack)
        self.numberOfParts++;
    BOOL refused = !self.takingBack && self.refusesFromPart > 0 && self.numberOfParts >= self.refusesFromPart;
    if (![self changeText:view ranges:ranges strings:strings refused:refused]) {
        if (self.takingBack) {
            [self endPartially];
            return;
        }
        self.numberOfParts--;
        // Nothing of this part is in: the parts before are taken back.
        self.nextFromEnd = nextFromEnd;
        self.insertedOfNext = insertedOfNext;
        [self takeBackWithReason:TSTeXRootApplyReasonRefused];
        return;
    }
    if (self.betweenParts && !self.takingBack)
        self.betweenParts(self);
    [self scheduleNextPart];
}

/// One part, through the text view, with no Undo registered.
- (BOOL)changeText:(NSTextView *)view ranges:(NSArray<NSValue *> *)ranges strings:(NSArray<NSString *> *)strings refused:(BOOL)refused
{
    NSTextStorage *storage = view.textStorage;
    NSUndoManager *undo = view.allowsUndo ? view.undoManager : nil;
    BOOL editable = view.isEditable;
    self.changingText = YES;
    view.editable = YES;
    [undo disableUndoRegistration];
    // Asked in ascending order, as NSTextView wants them; changed from the end, so that each range is still in place.
    BOOL allowed = !refused && [view shouldChangeTextInRanges:ranges.reverseObjectEnumerator.allObjects
                                           replacementStrings:strings.reverseObjectEnumerator.allObjects];
    if (allowed) {
        [storage beginEditing];
        for (NSUInteger i = 0; i < ranges.count; i++)
            [storage replaceCharactersInRange:ranges[i].rangeValue withString:strings[i]];
        [storage endEditing];
        [view didChangeText];
    }
    [undo enableUndoRegistration];
    view.editable = editable;
    self.changingText = NO;
    return allowed;
}

/// Stopped, or a later part refused: the parts in are taken back, a part at a time; the text must then be the one
/// approved.
- (void)takeBackWithReason:(TSTeXRootApplyReason)reason
{
    if (self.numberOfParts == 0) {
        [self endWithOutcome:TSTeXRootApplyOutcomeNotApplied reason:reason];
        return;
    }
    self.changes = TSTakingBack(self.replacements, self.originalText, self.nextFromEnd, self.insertedOfNext);
    self.nextFromEnd = 0;
    self.insertedOfNext = 0;
    self.takingBack = YES;
    self.takingBackReason = reason;
    [self scheduleNextPart];
}

- (void)finish
{
    NSTextView *view = self.textView;
    NSTextStorage *storage = view.textStorage;
    if (self.takingBack && storage) {
        [self text:(NSTextStorage *_Nonnull)storage isOriginal:^(BOOL same) {
            if (!same || self.changedUnexpectedly) {
                [self.textView.undoManager removeAllActions];
                [self endWithOutcome:TSTeXRootApplyOutcomePartial reason:self.changedUnexpectedly ? TSTeXRootApplyReasonUnexpectedChange : self.takingBackReason];
                return;
            }
            [self endWithOutcome:TSTeXRootApplyOutcomeNotApplied reason:self.takingBackReason];
        }];
        return;
    }
    if (self.takingBack) {
        [self endWithOutcome:TSTeXRootApplyOutcomePartial reason:TSTeXRootApplyReasonUnexpectedChange];
        return;
    }
    [self registerUndo];
    [self endWithOutcome:TSTeXRootApplyOutcomeApplied reason:TSTeXRootApplyReasonNone];
}

/// One Undo for the whole document: the replacements taken back at once (spec §2.5.3).
- (void)registerUndo
{
    NSTextView *view = self.textView;
    NSUndoManager *undo = view.allowsUndo ? view.undoManager : nil;
    if (!undo)
        return;
    NSArray<TSRegexFindReplacement *> *back = TSTakingBack(self.replacements, self.originalText, self.replacements.count, 0);
    TSRegisterChanges(undo, view, back, self.replacements, self.actionName);
}

/// Something else changed the text: it stays as it is, and the Undo history goes, as it no longer fits the text
/// (spec §2.5.3a).
- (void)endPartially
{
    if (self.numberOfParts == 0) {
        [self endWithOutcome:TSTeXRootApplyOutcomeNotApplied reason:TSTeXRootApplyReasonChanged];
        return;
    }
    [self.textView.undoManager removeAllActions];
    [self endWithOutcome:TSTeXRootApplyOutcomePartial reason:TSTeXRootApplyReasonUnexpectedChange];
}

- (void)endWithOutcome:(TSTeXRootApplyOutcome)outcome reason:(TSTeXRootApplyReason)reason
{
    if (self.ended)
        return;
    self.ended = YES;
    self.outcome = outcome;
    self.reason = reason;
    [NSNotificationCenter.defaultCenter removeObserver:self name:NSTextStorageWillProcessEditingNotification object:nil];
    self.applying = NO;
    void (^completion)(TSTeXRootDocumentApplier *) = self.completion;
    self.completion = nil;
    [TSTeXRootReplaceGuard removeApplier:self];
    if (completion)
        completion(self);
}

@end

@implementation TSTeXRootReplaceGuard

+ (BOOL)isRunning
{
    return TSRunning;
}

+ (void)setRunning:(BOOL)running
{
    TSRunning = running;
}

+ (BOOL)isApplyingToTextStorage:(nullable NSTextStorage *)storage
{
    if (!storage)
        return NO;
    for (TSTeXRootDocumentApplier *applier in TSAppliers)
        if (applier.applying && applier.storage == storage)
            return YES;
    return NO;
}

+ (BOOL)isApplying
{
    return TSAppliers.count > 0;
}

+ (BOOL)locksTextStorage:(nullable NSTextStorage *)storage
{
    if (!storage)
        return NO;
    if ([self isApplyingToTextStorage:storage])
        return YES;
    for (NSTextStorage *locked in TSLockedStorages)
        if (locked == storage)
            return YES;
    return NO;
}

+ (void)setLockedTextStorages:(nullable NSArray<NSTextStorage *> *)storages
{
    TSLockedStorages = [NSPointerArray weakObjectsPointerArray];
    for (NSTextStorage *storage in storages)
        [TSLockedStorages addPointer:(__bridge void *)storage];
}

+ (void)performWhenNotApplying:(dispatch_block_t)block
{
    if (!TSAppliers.count) {
        block();
        return;
    }
    if (!TSWaitingForNotApplying)
        TSWaitingForNotApplying = [NSMutableArray array];
    [TSWaitingForNotApplying addObject:[block copy]];
}

+ (void)addApplier:(TSTeXRootDocumentApplier *)applier
{
    if (!TSAppliers)
        TSAppliers = [NSMutableArray array];
    [TSAppliers addObject:applier];
}

+ (void)removeApplier:(TSTeXRootDocumentApplier *)applier
{
    [TSAppliers removeObjectIdenticalTo:applier];
    if (TSAppliers.count || !TSWaitingForNotApplying.count)
        return;
    NSArray<dispatch_block_t> *waiting = TSWaitingForNotApplying;
    TSWaitingForNotApplying = nil;
    // After the applier's own completion: what waited sees the outcome.
    dispatch_async(dispatch_get_main_queue(), ^{
        for (dispatch_block_t block in waiting)
            block();
    });
}

@end
