// SPDX-License-Identifier: GPL-2.0-or-later
#import "TSKeyboardShortcuts.h"
#import "TSShortcutPaneController.h"
#import <Carbon/Carbon.h>
NS_ASSUME_NONNULL_BEGIN
FOUNDATION_EXPORT const NSEventModifierFlags TSShortcutModifiers;
NSString * _Nullable TSTranslateKey(CFDataRef _Nullable data, UInt16 keyCode, BOOL shifted, UInt32 keyboardType);
TSShortcutBinding *TSBinding(NSString * _Nullable key, NSEventModifierFlags flags);
// NSEventModifierFlagFunction when flags hold the Globe (fn) key and key is a character key, else 0.
NSEventModifierFlags TSGlobeModifier(NSString * _Nullable key, NSEventModifierFlags flags);
NSEventModifierFlags TSEventGlobeModifier(NSEvent *event);
// Why a key pressed while recording a shortcut cannot have the Globe key; nil when it has none.
NSString * _Nullable TSGlobeRecordingRefusal(NSEvent *event);
// The key a menu item was given, before AppKit adapts it to the keyboard layout.
TSShortcutBinding *TSGivenBinding(NSMenuItem *item);
// The key AppKit shows for a menu item on the current keyboard layout.
TSShortcutBinding *TSShownBinding(NSMenuItem *item);
NSString *TSKeyboardLayoutID(void);
NSString *TSShortcutCharacterForEvent(NSEvent *event);
TSShortcutBinding *TSRecordedBinding(NSEvent *event, NSString * _Nullable unshifted);
NSArray<TSShortcutBinding *> *TSEventBindings(NSEvent *event, NSString * _Nullable unshifted);
BOOL TSRestorationSymbol(NSString *key);
NSString *TSRestorationCharacters(CFDataRef _Nullable data, UInt16 code, NSEventModifierFlags flags, UInt32 keyboardType);
NSArray<TSShortcutBinding *> *TSRestorationBindings(NSString *key, NSEventModifierFlags flags, CFDataRef _Nullable data, UInt32 keyboardType);
void TSVisitMenu(NSMenu * _Nullable menu, NSString *path, void (^visit)(NSMenuItem *, NSString *));
NSString * _Nullable TSFindCommandID(NSMenuItem *item);
void TSPrepareMenuIdentifiers(NSMenu *menu);
SEL TSMacroAction(void);
@interface TSShortcutCommand ()
// The default as AppKit showed it on each keyboard layout, by layout identifier.
@property (nonatomic, readonly) NSMutableDictionary<NSString *, TSShortcutBinding *> *shownDefaults;
@end
// Hidden items that let AppKit show a key for one pass of the run loop are kept in a hidden
// menu with this identifier, which TSVisitMenu skips.
FOUNDATION_EXPORT NSString * const TSShortcutLearningIdentifier;
@interface TSShortcutStore (MenuAccess)
@property (readonly) NSMenu *menu;
@property (readonly) NSUserDefaults *defaults;
- (NSArray<TSShortcutMatch *> *)menuMatchesKey:(NSString *)key modifiers:(NSEventModifierFlags)flags excluding:(nullable NSMenuItem *)excluded;
- (nullable NSString *)conflictForKey:(NSString *)key modifiers:(NSEventModifierFlags)flags except:(nullable NSMenuItem *)excluded restoring:(nullable TSShortcutCommand *)restoring;
- (nullable NSString *)conflictForRestoringCommand:(TSShortcutCommand *)command;
// A command's default as AppKit shows it on the current keyboard layout, and the key it shows now.
- (TSShortcutBinding *)shownDefaultForCommand:(TSShortcutCommand *)command;
- (TSShortcutBinding *)shownBindingForCommand:(TSShortcutCommand *)command;
// The key a command and its default show in Settings › Keyboard: 🌐︎F for Enter Full Screen.
- (NSString *)displayKeyForCommand:(TSShortcutCommand *)command;
- (NSString *)displayDefaultKeyForCommand:(TSShortcutCommand *)command;
// The default as given and as shown on the current keyboard layout.
- (NSSet<TSShortcutBinding *> *)defaultBindingsForCommand:(TSShortcutCommand *)command;
// AppKit shows, for one pass of the run loop, the keys of the current layout for every key
// given with Command and with Command and Shift; YES when it learned them.
- (void)learnLayoutKeysThen:(void (^)(BOOL learned))completion;
// Whether the keys of the current layout have been worked out.
- (BOOL)knowsKeysOfCurrentLayout;
// A key as AppKit shows it on the current layout, or the key itself while that is not known.
- (TSShortcutBinding *)shownBindingForGivenKey:(NSString *)key modifiers:(NSEventModifierFlags)flags;
// Called when AppKit has adapted the keys: the defaults items show are taken as shown.
- (void)noteShownDefaultsSettled;
// Called when AppKit has adapted the keys: whether the shown keys of defaults, other items or
// macros differ from those the last assignment went by.
- (BOOL)shownKeysChangedSinceAssignment;
- (TSShortcutBinding *)givenBindingForMacroItem:(NSMenuItem *)item;
// The same, for the item at this path of the menu (the macro there).
- (TSShortcutBinding *)givenBindingForMacroItem:(NSMenuItem *)item path:(nullable NSString *)path;
// A macro's key as its file names it and as AppKit shows it on the current layout, when known.
- (NSArray<TSShortcutBinding *> *)bindingsForMacroKey:(NSString *)key modifiers:(NSEventModifierFlags)flags;
// Edit › Complete Label or Citation Key: its default key gives way to a menu command or a macro.
- (BOOL)commandYieldsDefault:(TSShortcutCommand *)command;
// The macro, as its file names its key, that has the key; nil when none.
- (nullable NSString *)macroNamingKey:(NSString *)key modifiers:(NSEventModifierFlags)flags;
@end
NS_ASSUME_NONNULL_END
