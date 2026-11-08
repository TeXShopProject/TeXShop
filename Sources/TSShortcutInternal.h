// SPDX-License-Identifier: GPL-2.0-or-later
#import "TSKeyboardShortcuts.h"
#import "TSShortcutPaneController.h"
#import <Carbon/Carbon.h>
NS_ASSUME_NONNULL_BEGIN
FOUNDATION_EXPORT const NSEventModifierFlags TSShortcutModifiers;
NSString * _Nullable TSTranslateKey(CFDataRef _Nullable data, UInt16 keyCode, BOOL shifted, UInt32 keyboardType);
NSDictionary *TSBinding(NSString * _Nullable key, NSEventModifierFlags flags);
NSString *TSShortcutCharacterForEvent(NSEvent *event);
NSDictionary *TSRecordedBinding(NSEvent *event, NSString * _Nullable unshifted);
NSArray<NSDictionary *> *TSEventBindings(NSEvent *event, NSString * _Nullable unshifted);
BOOL TSRestorationSymbol(NSString *key);
NSString *TSRestorationCharacters(CFDataRef _Nullable data, UInt16 code, NSEventModifierFlags flags, UInt32 keyboardType);
NSArray<NSDictionary *> *TSRestorationBindings(NSString *key, NSEventModifierFlags flags, CFDataRef _Nullable data, UInt32 keyboardType);
void TSVisitMenu(NSMenu * _Nullable menu, NSString *path, void (^visit)(NSMenuItem *, NSString *));
NSString * _Nullable TSFindCommandID(NSMenuItem *item);
void TSPrepareMenuIdentifiers(NSMenu *menu);
SEL TSMacroAction(void);
@interface TSShortcutStore (MenuAccess)
@property (readonly) NSMenu *menu;
- (NSArray<TSShortcutMatch *> *)menuMatchesKey:(NSString *)key modifiers:(NSEventModifierFlags)flags excluding:(nullable NSMenuItem *)excluded;
- (nullable NSString *)conflictForKey:(NSString *)key modifiers:(NSEventModifierFlags)flags except:(nullable NSMenuItem *)excluded restoring:(nullable TSShortcutCommand *)restoring;
- (nullable NSString *)conflictForRestoringCommand:(TSShortcutCommand *)command;
@end
NS_ASSUME_NONNULL_END
