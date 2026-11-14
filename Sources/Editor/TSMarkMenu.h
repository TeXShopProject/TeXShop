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
// Where showMarkHelp: goes in a localization: nil in English, for the help
// book's anchor "marks"; in every other language, the English page with that
// section, opened as a link (most languages have no help book, and those that
// have one do not explain marks in their language).
+ (nullable NSURL *)markHelpPageForLocalization:(NSString *)localization inBundle:(NSBundle *)bundle;
// One sentence explaining • and •‹note›, naming the Edit › Mark menu as it is titled.
+ (NSString *)markGuide;
@end
NS_ASSUME_NONNULL_END
