// SPDX-License-Identifier: GPL-2.0-or-later
#import "TSPrefPaneController.h"
NS_ASSUME_NONNULL_BEGIN
@interface TSPrefMiscTwoController : TSPrefPaneController
@property (strong, nullable) IBOutlet NSButton *XMLchapter NS_SWIFT_NAME(xMLchapter);
@property (strong, nullable) IBOutlet NSButton *XMLconclusion NS_SWIFT_NAME(xMLconclusion);
@property (strong, nullable) IBOutlet NSButton *XMLexercises NS_SWIFT_NAME(xMLexercises);
@property (strong, nullable) IBOutlet NSButton *XMLfigure NS_SWIFT_NAME(xMLfigure);
@property (strong, nullable) IBOutlet NSButton *XMLintroduction NS_SWIFT_NAME(xMLintroduction);
@property (strong, nullable) IBOutlet NSButton *XMLmark NS_SWIFT_NAME(xMLmark);
@property (strong, nullable) IBOutlet NSButton *XMLproject NS_SWIFT_NAME(xMLproject);
@property (strong, nullable) IBOutlet NSButton *XMLsection NS_SWIFT_NAME(xMLsection);
@property (strong, nullable) IBOutlet NSButton *XMLsubsection NS_SWIFT_NAME(xMLsubsection);
@property (strong, nullable) IBOutlet NSButton *XMLsubsubsection NS_SWIFT_NAME(xMLsubsubsection);
@property (strong, nullable) IBOutlet NSButton *XMLtable NS_SWIFT_NAME(xMLtable);
@property (strong, nullable) IBOutlet NSTextField *alternateEngineTextField;
@property (strong, nullable) IBOutlet NSButton *convertUTFButton;
@property (strong, nullable) IBOutlet NSMatrix *distillerMatrix;
@property (strong, nullable) IBOutlet NSTextField *latexScriptCommandTextField;
@property (strong, nullable) IBOutlet NSButton *miniaturizeRootFileButton;
@property (strong, nullable) IBOutlet NSButton *openRootFileButton;
@property (strong, nullable) IBOutlet NSButton *ptexUtfOutputButton;
@property (strong, nullable) IBOutlet NSButton *sparkleAutomaticButton;
@property (strong, nullable) IBOutlet NSMatrix *sparkleIntervalMatrix;
@property (strong, nullable) IBOutlet NSTextField *texScriptCommandTextField;
@end
NS_ASSUME_NONNULL_END
