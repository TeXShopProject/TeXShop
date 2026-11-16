// SPDX-License-Identifier: GPL-2.0-or-later
#import <Cocoa/Cocoa.h>
#import "TSAdvancedFindController.h"
#import "TSMultipleReplaceLibrary.h"
#import "TSTeXRootSearchModel.h"
#import "TSTeXRootSearchFileTree.h"
#import "TSTeXRootSearchResultsList.h"
#import "TSTeXRootReplaceRun.h"

NS_ASSUME_NONNULL_BEGIN

/// The user default of "Save backups" beside Replace All; on when it was never set.
static NSString *const TSTeXRootSearchSavesBackupsKey = @"TeXRootSearchSavesBackups";

/// The window "Find in TeX Sources" (spec §2.7): one for the application, tied to the root it was last opened for.
/// From the top: the modes, the root's name and ↻; the line that says what is searched, with ?; the find and
/// replacement fields and the options shared with the Advanced Find panel (or, for Multiple Replace, the set); the
/// tree of the files on the left and the results on the right; and the line of the progress, ■, the status, the
/// files that could not be read, and in the replacing modes "Save backups" and Replace All. Built in code.
NS_SWIFT_NAME(TeXRootSearchWindowController)
@interface TSTeXRootSearchWindowController : NSWindowController <TSTeXRootSearchModelDelegate, NSTextViewDelegate, NSMenuItemValidation>

- (instancetype)initWithFindController:(TSAdvancedFindController *)findController library:(TSMultipleReplaceLibrary *)library NS_DESIGNATED_INITIALIZER;
- (instancetype)initWithWindow:(nullable NSWindow *)window NS_UNAVAILABLE;
- (nullable instancetype)initWithCoder:(NSCoder *)coder NS_UNAVAILABLE;
- (instancetype)init NS_UNAVAILABLE;

@property (nonatomic, readonly) TSAdvancedFindController *findController;
@property (nonatomic, readonly) TSMultipleReplaceLibrary *library;

/// Ties the window to `rootURL`, in Find mode or, with a set's name, in Multiple Replace mode with that set (spec
/// §2.7.1), and collects the files and searches them. Files and checks of another root are forgotten. Does not show
/// the window.
- (void)openForRootURL:(NSURL *)rootURL environment:(TSTeXRootSearchEnvironment *)environment
                  mode:(TSTeXRootSearchMode)mode setName:(nullable NSString *)setName;
/// The window's state; nil before the window was first opened for a root.
@property (nonatomic, readonly, nullable) TSTeXRootSearchModel *model;
/// The question mark's popover adds the %SourceDoc line (the hidden setting UseOldHeadingCommands).
@property (nonatomic) BOOL mentionsSourceDoc;

/// A result row was clicked (`front` NO) or double-clicked (`front` YES).
@property (nonatomic, copy, nullable) void (^showItemHandler)(TSTeXRootSearchFileResult *file, TSTeXRootSearchItem *item, BOOL front);
/// "Open Help" in the question mark's popover.
@property (nonatomic, copy, nullable) void (^openHelpHandler)(void);
/// "Edit…" of Multiple Replace mode: shows the set in the Multiple Replace window.
@property (nonatomic, copy, nullable) void (^editSetHandler)(NSString *name);
/// Replace All, when it can be pressed: TeXShop calls -beginReplaceAll.
@property (nonatomic, copy, nullable) void (^replaceAllHandler)(TSTeXRootSearchWindowController *controller);

#pragma mark Replace All (spec §2.5)

/// The text view of the open document of a file of the plan, nil when it is not open any more.
@property (nonatomic, copy, nullable) NSTextView *_Nullable (^textViewForFile)(TSTeXRootReplaceFile *file);
/// For the backup of an open document (main thread): what turns its text as approved into bytes in its encoding, or in
/// UTF-8 (`usedUTF8`) when that cannot hold it, on a background queue.
@property (nonatomic, copy, nullable) NSData *_Nullable (^_Nonnull (^backupEncoderForOpenDocument)(TSTeXRootReplaceFile *file))(BOOL *usedUTF8);
/// "Open the Original Text in a New Document" of the report: an untitled document with `text`.
@property (nonatomic, copy, nullable) void (^openTextHandler)(NSString *text);
/// From the press of Replace All until its report: only ■ (and Escape, ⌘.) can be used, which stops it.
@property (nonatomic, readonly, getter=isReplacing) BOOL replacing;
/// The run after the confirmation, while it runs.
@property (nonatomic, readonly, nullable) TSTeXRootReplaceRun *run;
/// For the tests: the sheets go here instead of the window; `answer` gives the button pressed.
@property (nonatomic, copy, nullable) void (^alertPresenter)(NSAlert *alert, void (^answer)(NSModalResponse response));
/// For the tests: the run is made, before it starts.
@property (nonatomic, copy, nullable) void (^runMade)(TSTeXRootReplaceRun *run);

- (IBAction)collectAgain:(nullable id)sender;
- (IBAction)stop:(nullable id)sender;
- (IBAction)replaceAll:(nullable id)sender;
/// Escape and ⌘.: stops collecting or searching.
- (void)cancelOperation:(nullable id)sender;
/// The contents of the question mark's popover and of the list of files that could not be read.
- (NSViewController *)makeExplanationViewController;
- (NSViewController *)makeUnreadableViewController;
/// Brings every control up to date with the model now (as after each change of the model).
- (void)updateFromModel;

@end

@interface TSTeXRootSearchWindowController (ReplaceAll)
/// Check 1, the confirmation sheet, then the run and its report (spec §2.5.1, §2.5.5). Beeps when Replace All cannot
/// be pressed.
- (void)beginReplaceAll;
@end

/// For the tests and images; not used by the application itself.
@interface TSTeXRootSearchWindowController (Testing)
@property (nonatomic, readonly) NSSegmentedControl *modeControl;
@property (nonatomic, readonly) NSTextField *rootLabel;
@property (nonatomic, readonly) NSTextField *explanationLabel;
@property (nonatomic, readonly) NSButton *helpButton;
@property (nonatomic, readonly) NSButton *refreshButton;
@property (nonatomic, readonly) NSTextView *findField;
@property (nonatomic, readonly) NSTextView *replaceField;
@property (nonatomic, readonly) NSView *findRow;
@property (nonatomic, readonly) NSView *replaceRow;
@property (nonatomic, readonly) NSView *optionsRow;
@property (nonatomic, readonly) NSView *setRow;
@property (nonatomic, readonly) NSButton *regexBox;
@property (nonatomic, readonly) NSButton *ignoreCaseBox;
@property (nonatomic, readonly) NSPopUpButton *setPopUp;
@property (nonatomic, readonly) NSTextField *ruleCountLabel;
@property (nonatomic, readonly) NSButton *editSetButton;
@property (nonatomic, readonly) NSProgressIndicator *spinner;
@property (nonatomic, readonly) NSButton *stopButton;
@property (nonatomic, readonly) NSTextField *statusField;
@property (nonatomic, readonly) NSButton *unreadableButton;
@property (nonatomic, readonly) NSButton *backupBox;
@property (nonatomic, readonly) NSButton *replaceAllButton;
@property (nonatomic, readonly) TSTeXRootSearchFileTree *fileTree;
@property (nonatomic, readonly) TSTeXRootSearchResultsList *resultsList;
@end

NS_ASSUME_NONNULL_END
