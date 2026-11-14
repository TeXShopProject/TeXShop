// SPDX-License-Identifier: GPL-2.0-or-later
#import "TSAdvancedFindTask.h"
#import "TSAdvancedFindProgressSheet.h"

@implementation TSAdvancedFindTextEdit

- (instancetype)initWithRange:(NSRange)range replacementLength:(NSUInteger)replacementLength
{
    if ((self = [super init])) {
        _range = range;
        _replacementLength = replacementLength;
    }
    return self;
}

@end

@interface TSAdvancedFindTask ()
@property (nonatomic, readwrite) BOOL sheetWasDue;
@property (atomic, readwrite, getter=isCancelled) BOOL cancelled;
@property (nonatomic, readwrite, getter=isFinished) BOOL finished;
@property (nonatomic, strong, nullable) TSAdvancedFindProgressSheet *progressSheet;
/// The text views made read-only, to make editable again at the end.
@property (nonatomic, strong) NSMutableArray<NSTextView *> *lockedViews;
/// Every text view of the text storage while the task runs.
@property (nonatomic, copy) NSArray<NSTextView *> *watchedViews;
@property (nonatomic, strong) NSMutableArray<TSAdvancedFindTextEdit *> *edits;
@property (nonatomic, weak, nullable) NSTextStorage *watchedStorage;
@end

@implementation TSAdvancedFindTask

- (instancetype)initWithTitle:(NSString *)title textView:(NSTextView *)textView
{
    if ((self = [super init])) {
        _title = [title copy];
        _textView = textView;
        _progress = -1;
        _message = @"";
        _sheetDelay = 0.4;
        _lockedViews = [NSMutableArray array];
        _watchedViews = @[];
        _edits = [NSMutableArray array];
    }
    return self;
}

- (BOOL (^)(void))cancellation
{
    __weak typeof(self) weakSelf = self;
    return ^BOOL { return weakSelf.isCancelled; };
}

- (void)cancel
{
    self.cancelled = YES;
}

- (nullable NSWindow *)sheet
{
    return self.progressSheet.window;
}

static void *TSLockedViewContext = &TSLockedViewContext;

/// Every view of the text storage: the two of a split window, for example. Each is watched until the end: TeXShop may
/// set the editability of any of them meanwhile.
- (void)lockTextViews
{
    NSTextStorage *storage = self.textView.textStorage;
    NSMutableArray<NSTextView *> *views = [NSMutableArray array];
    for (NSLayoutManager *layout in storage.layoutManagers)
        for (NSTextContainer *container in layout.textContainers) {
            NSTextView *view = container.textView;
            if (!view)
                continue;
            [views addObject:view];
            if (view.isEditable) {
                view.editable = NO;
                [self.lockedViews addObject:view];
            }
        }
    for (NSTextView *view in views)
        [view addObserver:self forKeyPath:@"editable" options:0 context:TSLockedViewContext];
    self.watchedViews = views;
}

/// TeXShop set a view's editability meanwhile (a typesetting that starts makes the console read-only): that stands.
/// The views of one layout manager share it, so none of them is made editable at the end.
- (void)observeValueForKeyPath:(nullable NSString *)keyPath ofObject:(nullable id)object change:(nullable NSDictionary<NSKeyValueChangeKey, id> *)change
                       context:(nullable void *)context
{
    if (context != TSLockedViewContext) {
        [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
        return;
    }
    NSTextView *changed = object;
    NSLayoutManager *layout = changed.layoutManager;
    for (NSTextView *view in [self.lockedViews copy])
        if (view == changed || (layout && view.layoutManager == layout))
            [self.lockedViews removeObject:view];
}

- (void)unlockTextViews
{
    for (NSTextView *view in self.watchedViews)
        [view removeObserver:self forKeyPath:@"editable" context:TSLockedViewContext];
    self.watchedViews = @[];
    for (NSTextView *view in self.lockedViews)
        view.editable = YES;
    [self.lockedViews removeAllObjects];
}

- (NSArray<TSAdvancedFindTextEdit *> *)editsMeanwhile
{
    return [self.edits copy];
}

/// Before the edit is processed: afterwards the edited range may have been widened to whole paragraphs.
- (void)textStorageWillProcessEdit:(NSNotification *)notification
{
    NSTextStorage *storage = notification.object;
    if (!(storage.editedMask & NSTextStorageEditedCharacters))
        return;
    NSRange edited = storage.editedRange;
    NSUInteger oldLength = (NSUInteger)((NSInteger)edited.length - storage.changeInLength);
    [self.edits addObject:[[TSAdvancedFindTextEdit alloc] initWithRange:NSMakeRange(edited.location, oldLength) replacementLength:edited.length]];
}

- (void)watchEdits:(BOOL)watch
{
    if (watch) {
        self.watchedStorage = self.textView.textStorage;
        if (self.watchedStorage)
            [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(textStorageWillProcessEdit:)
                                                       name:NSTextStorageWillProcessEditingNotification object:self.watchedStorage];
    } else if (self.watchedStorage) {
        [NSNotificationCenter.defaultCenter removeObserver:self name:NSTextStorageWillProcessEditingNotification object:self.watchedStorage];
        self.watchedStorage = nil;
    }
}

- (void)runWork:(id _Nullable (^)(TSAdvancedFindTask *task))work completion:(void (^)(id _Nullable result, BOOL cancelled))completion
{
    [self lockTextViews];
    [self watchEdits:YES];
    __weak typeof(self) weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(self.sheetDelay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        TSAdvancedFindTask *task = weakSelf;
        if (!task || task.finished)
            return;
        task.sheetWasDue = YES;
        NSWindow *window = task.textView.window;
        if (window.isVisible) { // never a sheet on a window that is not on screen (it would come out on its own)
            task.progressSheet = [[TSAdvancedFindProgressSheet alloc] initWithTask:task];
            [task.progressSheet beginOnWindow:window];
        }
    });
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        id result = work(self);
        dispatch_async(dispatch_get_main_queue(), ^{
            self.finished = YES;
            [self.progressSheet end];
            self.progressSheet = nil;
            [self unlockTextViews];
            [self watchEdits:NO];
            completion(self.isCancelled ? nil : result, self.isCancelled);
        });
    });
}

@end
