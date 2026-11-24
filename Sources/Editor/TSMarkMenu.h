// SPDX-License-Identifier: GPL-2.0-or-later
#import <Cocoa/Cocoa.h>
NS_ASSUME_NONNULL_BEGIN
// Marks (•) and marks with a note (•‹note›) work in any source, with or without
// command completion, so their commands live in Edit › Mark: inserting a mark,
// inserting a mark with a note, moving to the next or previous mark, and a
// link to the help page that explains them.
@interface TSMarkMenu : NSObject
+ (instancetype)sharedInstance;
// Moves the Mark submenu from Source › Command Completion to Edit, after Find,
// and completes it. The menu items keep their identifiers, so customized
// shortcuts stay with them. Calling it again changes nothing.
+ (void)installInMenu:(NSMenu *)mainMenu;
- (IBAction)showMarkHelp:(nullable id)sender;
// Edit › Complete Label or Citation Key: the text completion of macOS (complete:, F5)
// in the source or Experiment text the user is typing in. After \ref{ and similar
// commands it offers the labels of the file, after \cite{ the citation keys of BibDesk
// when Settings › Keyboard allows it, and elsewhere the words macOS proposes.
- (IBAction)completeLabelOrCitationKey:(nullable id)sender;
// The editable text view, not a field editor, that is the first responder of the key
// window; the menu item is dimmed without one.
+ (nullable NSTextView *)completionTarget;
// Where showMarkHelp: goes in a localization: nil when the localization has its
// own help book, for that book's anchor "marks"; otherwise the English page with
// that section, opened as a link.
+ (nullable NSURL *)markHelpPageForLocalization:(NSString *)localization inBundle:(NSBundle *)bundle;
// One sentence explaining • and •‹note›, naming the Edit › Mark menu as it is titled.
+ (NSString *)markGuide;
@end
NS_ASSUME_NONNULL_END
