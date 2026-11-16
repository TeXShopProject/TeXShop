// SPDX-License-Identifier: GPL-2.0-or-later
#import "TSTeXRootSearchWindowController.h"
#import "TSAdvancedFindPanelController+Private.h"
#import "TSAdvancedFindInputBox.h"

NS_ASSUME_NONNULL_BEGIN

@interface TSTeXRootSearchWindowController () <NSWindowDelegate>
@property (nonatomic, readwrite, nullable) TSTeXRootSearchModel *model;
@property (nonatomic, strong) NSSegmentedControl *modeControl;
@property (nonatomic, strong) NSTextField *rootLabel;
@property (nonatomic, strong) NSTextField *explanationLabel;
@property (nonatomic, strong) NSButton *helpButton;
@property (nonatomic, strong) NSButton *refreshButton;
@property (nonatomic, strong) TSAdvancedFindFieldView *findFieldView;
@property (nonatomic, strong) TSAdvancedFindFieldView *replaceFieldView;
@property (nonatomic, strong) TSAdvancedFindInputBox *findBox;
@property (nonatomic, strong) TSAdvancedFindInputBox *replaceBox;
@property (nonatomic, strong) NSView *optionsRow;
@property (nonatomic, strong) NSView *setRow;
@property (nonatomic, strong) NSButton *regexBox;
@property (nonatomic, strong) NSButton *ignoreCaseBox;
@property (nonatomic, strong) NSButton *moreOptionsButton;
@property (nonatomic, strong, nullable) NSPopover *popover;
@property (nonatomic, strong, nullable) TSAdvancedFindOptionsForm *optionsForm;
@property (nonatomic, strong) NSPopUpButton *setPopUp;
@property (nonatomic, strong) NSTextField *ruleCountLabel;
@property (nonatomic, strong) NSButton *editSetButton;
@property (nonatomic, copy, nullable) NSString *setName;
@property (nonatomic, strong) NSProgressIndicator *spinner;
@property (nonatomic, strong) NSButton *stopButton;
@property (nonatomic, strong) NSTextField *statusField;
@property (nonatomic, strong) NSButton *unreadableButton;
@property (nonatomic, strong) NSButton *backupBox;
@property (nonatomic, strong) NSButton *replaceAllButton;
@property (nonatomic, strong) NSStackView *topStack;
@property (nonatomic, strong) NSStackView *bottomStack;
@property (nonatomic, strong) NSSplitView *splitView;
@property (nonatomic, strong, nullable) TSTeXRootSearchFileTree *fileTree;
@property (nonatomic, strong, nullable) TSTeXRootSearchResultsList *resultsList;
@property (nonatomic, strong) NSView *treeHolder;
@property (nonatomic, strong) NSView *resultsHolder;
/// What the list shows, to rebuild it only when the results or the mode changed.
@property (nonatomic, copy, nullable) NSArray *shownResults;
@property (nonatomic) TSTeXRootSearchMode shownMode;
@property (nonatomic) BOOL showsAnyResults;
@property (nonatomic) BOOL updatePending;
/// Replace All (stage 4): from the press of the button until its report.
@property (nonatomic, readwrite, getter=isReplacing) BOOL replacing;
@property (nonatomic, readwrite, strong, nullable) TSTeXRootReplaceRun *run;
/// The collector of check 1 while it runs; Stop cancels it.
@property (nonatomic, strong, nullable) TSTeXRootProjectCollector *checkCollector;
@end

@interface TSTeXRootSearchWindowController (ReplaceAllPrivate)
/// Enables or disables what changes the search while a Replace All runs (spec §2.5.1a): only ■ is left.
- (void)updateControlsForReplacing;
- (void)stopReplacing;
@end

NS_ASSUME_NONNULL_END
