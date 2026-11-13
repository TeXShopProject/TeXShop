// SPDX-License-Identifier: GPL-2.0-or-later
// Shared by the controller's files; not for other classes.
#import "TSAdvancedFindController.h"
#import "TSRegexTextFind.h"
#import "TSAdvancedFindTask.h"

NS_ASSUME_NONNULL_BEGIN

@interface TSAdvancedFindController ()
@property (nonatomic, readwrite, nullable) TSAdvancedFindTask *runningTask;
@end

@interface TSAdvancedFindController (Shared)
- (void)report:(NSString *)message isError:(BOOL)isError;
- (nullable TSRegexTextFind *)textFindForTextView:(NSTextView *)textView inSelection:(BOOL)inSelection quiet:(BOOL)quiet;
- (BOOL)applyReplacements:(NSArray<TSRegexFindReplacement *> *)replacements
               toTextView:(NSTextView *)textView
           selectedRanges:(nullable NSArray<NSValue *> *)selectedRanges
               actionName:(NSString *)actionName;
/// Runs `work` as the controller's task. `completion` gets nil when the task was cancelled or the text changed
/// meanwhile (both are reported); otherwise the work's result, after the text views are editable again.
- (void)runTaskNamed:(NSString *)title inTextView:(NSTextView *)textView
                work:(id _Nullable (^)(TSAdvancedFindTask *task))work
          completion:(void (^)(id _Nullable result))completion;
/// The same for a work that only reads (Find All): when the text changed meanwhile (a console receiving output),
/// `completion` gets the result with the changes, to move it to the text as it is now.
- (void)runTaskNamed:(NSString *)title inTextView:(NSTextView *)textView
  followingEditsWork:(id _Nullable (^)(TSAdvancedFindTask *task))work
          completion:(void (^)(id _Nullable result, NSArray<TSAdvancedFindTextEdit *> *edits))completion;
@end

@interface TSAdvancedFindController (Tasks)
- (BOOL)replaceAllInTextView:(NSTextView *)textView inSelection:(BOOL)inSelection;
- (BOOL)findAllInTextView:(NSTextView *)textView;
@end

NS_ASSUME_NONNULL_END
