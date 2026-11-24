#import <Cocoa/Cocoa.h>
#import "TSPreferenceKey.h"

NS_ASSUME_NONNULL_BEGIN
FOUNDATION_EXPORT TSPreferenceKey const TSMenuShortcutOverridesKey;
FOUNDATION_EXPORT NSNotificationName const TSRebuildMacrosNotification;
FOUNDATION_EXPORT NSNotificationName const TSMacroShortcutsChangedNotification;
// First button is the safe choice for both Return and Escape.
NSModalResponse TSRunShortcutAlert(NSAlert *alert);

/// A key and its modifiers as menus show them, such as ⌃⌥⌘T; an em dash when there is no key.
/// Inline, so that a view showing a menu item's key needs no shortcut store.
static inline NSString *TSShortcutDisplayKey(NSString *key, NSEventModifierFlags flags)
{
    if (!key.length) return @"—";
    // Display the actual menu definition. Canonicalization is for comparison only.
    if (key.length == 1 && [key characterAtIndex:0] >= 'A' && [key characterAtIndex:0] <= 'Z')
        flags |= NSEventModifierFlagShift;
    NSMutableString *text = [NSMutableString string];
    if (flags & NSEventModifierFlagControl) [text appendString:@"⌃"];
    if (flags & NSEventModifierFlagOption) [text appendString:@"⌥"];
    if (flags & NSEventModifierFlagShift) [text appendString:@"⇧"];
    if (flags & NSEventModifierFlagCommand) [text appendString:@"⌘"];
    unichar c = [key characterAtIndex:0];
    // The Globe (fn) key, which only menu items macOS provides can have (Enter Full Screen), as AppKit shows it
    // since macOS 27. Arrows and the function keys carry the flag of their own.
    if ((flags & NSEventModifierFlagFunction) && c < 0xf700) [text appendString:@"\U0001F310︎"];
    NSDictionary *symbols = @{@(NSLeftArrowFunctionKey):@"←", @(NSRightArrowFunctionKey):@"→", @(NSUpArrowFunctionKey):@"↑", @(NSDownArrowFunctionKey):@"↓", @13:@"↩", @9:@"⇥", @27:@"⎋", @32:@"␣", @127:@"⌫", @(NSDeleteFunctionKey):@"⌦"};
    if (c >= NSF1FunctionKey && c <= NSF20FunctionKey) [text appendFormat:@"F%u", c - NSF1FunctionKey + 1];
    else [text appendString:symbols[@(c)] ?: key.uppercaseString];
    return text;
}

/// Immutable key/modifier value. NSDictionary primitives preserve the existing
/// property-list representation at persistence and macro-editor boundaries.
@class TSShortcutMacro;
@interface TSShortcutBinding : NSDictionary<NSString *, id>
@property (copy, readonly) NSString *key;
@property (readonly) NSEventModifierFlags modifiers;
- (instancetype)initWithKey:(NSString *)key modifiers:(NSEventModifierFlags)modifiers NS_DESIGNATED_INITIALIZER;
- (instancetype)initWithObjects:(const id _Nonnull [_Nullable])objects forKeys:(const id<NSCopying> _Nonnull [_Nullable])keys count:(NSUInteger)count NS_UNAVAILABLE;
- (instancetype)initWithCoder:(NSCoder *)coder NS_UNAVAILABLE;
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;
@end

@interface TSShortcutCommand : NSObject
@property (nonatomic, readonly, strong) NSMenuItem *item;
@property (nonatomic, readonly, copy) NSString *commandID;
@property (nonatomic, readonly, copy) NSString *path;
/// The default key as the menu gives it, before AppKit adapts it to the keyboard layout
/// (1 for the & that a French layout shows); see -[TSShortcutStore shownDefaultForCommand:].
@property (nonatomic, readonly, copy) NSString *defaultKey;
@property (nonatomic, readonly) NSEventModifierFlags defaultModifiers;
@property (nonatomic, readonly) BOOL defaultLocalization;
/// macOS keeps this command's shortcut (Save As… while documents autosave, Enter Full Screen with Globe-F); it is shown, not changed.
@property (nonatomic, readonly) BOOL managedBySystem;
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;
- (instancetype)initWithItem:(NSMenuItem *)item identifier:(NSString *)identifier path:(NSString *)path NS_DESIGNATED_INITIALIZER;
@end

@interface TSShortcutStore : NSObject
@property (nonatomic, readonly, copy) NSArray<TSShortcutCommand *> *commands;
@property (nonatomic, readonly, copy) NSArray<NSString *> *unavailableCommands;
- (void)refreshMenu;
// The macros as their files name their keys. A command that yields its default key
// (Edit › Complete Label or Citation Key) leaves that key to a macro that names it.
@property (copy, nullable) NSArray<TSShortcutMacro *> * (^macroProvider)(void);
- (NSArray<NSString *> *)settingsSearchCommandNames;

- (instancetype)initWithMenu:(NSMenu *)menu defaults:(NSUserDefaults *)defaults;
- (nullable NSString *)setKey:(NSString *)key modifiers:(NSEventModifierFlags)flags forCommand:(TSShortcutCommand *)command;
- (nullable NSString *)restoreCommand:(TSShortcutCommand *)command;
- (void)restoreAll;
- (NSArray<NSString *> *)macrosUsingKey:(NSString *)key modifiers:(NSEventModifierFlags)flags;
- (NSArray<NSString *> *)macrosAffectedByRestoringAll;
- (NSArray<NSDictionary<NSString *, id> *> *)conflictsForMacroShortcuts:(NSArray<NSDictionary<NSString *, id> *> *)candidates;
+ (TSShortcutBinding *)normalizedKey:(NSString *)key modifiers:(NSEventModifierFlags)flags;
/// The identifier of the Macros menu item made for the macro at this place in the macro file.
FOUNDATION_EXPORT NSString *TSMacroItemIdentifier(NSIndexPath *indexPath);
/// A macro key as its file names it and, when known, as the keyboard layout shows it.
+ (NSArray<TSShortcutBinding *> *)bindingsForMacroKey:(NSString *)key modifiers:(NSEventModifierFlags)flags;
+ (NSArray<NSDictionary<NSString *, id> *> *)menuBindings:(NSMenu *)menu;
+ (NSString *)reasonForMacroConflict:(NSDictionary<NSString *, id> *)conflict;
+ (NSString *)displayKey:(NSString *)key modifiers:(NSEventModifierFlags)flags;
+ (BOOL)isAllowedKey:(NSString *)key modifiers:(NSEventModifierFlags)flags;
+ (BOOL)event:(NSEvent *)event matchesItem:(NSMenuItem *)item;
@end

/// Window › Enter Full Screen gets Globe-F (🌐F), as in Finder and Preview; the nibs give it no key. AppKit takes the
/// Globe (fn) key only for its own items, and only once the item has its action, which a nib sets after the key. A nib
/// key would also make AppKit add a hidden copy of the item that keeps it (Control-Command-F, Next Mark's key).
/// Called at launch, after the main menu is loaded and before the shortcuts read the default keys; again does no harm.
void TSGiveFullScreenGlobeKey(NSMenu * _Nullable menu);

@class TSShortcutMacro;
@interface TSKeyboardShortcuts : NSObject
@property (strong, readonly, nullable) TSShortcutStore *store;
@property (copy, nullable) NSArray<TSShortcutMacro *> * (^macroProvider)(void);
@property (copy, nullable) void (^showMacro)(TSShortcutMacro *macro);
@property (copy, nullable) void (^showSettings)(void);
+ (instancetype)sharedController;
- (void)startObservingMenu;
- (void)startAfterLaunchWithConfiguration:(void (^)(TSKeyboardShortcuts *shortcuts))configuration;
- (void)beginMenuRebuild;
- (void)endMenuRebuild;
- (void)refreshMenuAndMacros;
- (NSArray<NSDictionary<NSString *, id> *> *)conflictsForMacroShortcuts:(NSArray<NSDictionary<NSString *, id> *> *)candidates;
- (void)showKeyboardShortcuts:(nullable id)sender;
+ (BOOL)event:(NSEvent *)event matchesAction:(SEL)action tag:(NSInteger)tag;
@end
NS_ASSUME_NONNULL_END
