#import <Cocoa/Cocoa.h>
#import "TSPreferenceKey.h"

NS_ASSUME_NONNULL_BEGIN
FOUNDATION_EXPORT TSPreferenceKey const TSMenuShortcutOverridesKey;
FOUNDATION_EXPORT NSNotificationName const TSRebuildMacrosNotification;
FOUNDATION_EXPORT NSNotificationName const TSMacroShortcutsChangedNotification;
// First button is the safe choice for both Return and Escape.
NSModalResponse TSRunShortcutAlert(NSAlert *alert);

/// Immutable key/modifier value. NSDictionary primitives preserve the existing
/// property-list representation at persistence and macro-editor boundaries.
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
@property (nonatomic, readonly, copy) NSString *defaultKey;
@property (nonatomic, readonly) NSEventModifierFlags defaultModifiers;
@property (nonatomic, readonly) BOOL defaultLocalization;
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;
- (instancetype)initWithItem:(NSMenuItem *)item identifier:(NSString *)identifier path:(NSString *)path NS_DESIGNATED_INITIALIZER;
@end

@interface TSShortcutStore : NSObject
@property (nonatomic, readonly, copy) NSArray<TSShortcutCommand *> *commands;
@property (nonatomic, readonly, copy) NSArray<NSString *> *unavailableCommands;
- (void)refreshMenu;
- (NSArray<NSString *> *)settingsSearchCommandNames;

- (instancetype)initWithMenu:(NSMenu *)menu defaults:(NSUserDefaults *)defaults;
- (nullable NSString *)setKey:(NSString *)key modifiers:(NSEventModifierFlags)flags forCommand:(TSShortcutCommand *)command;
- (nullable NSString *)restoreCommand:(TSShortcutCommand *)command;
- (void)restoreAll;
- (NSArray<NSString *> *)macrosUsingKey:(NSString *)key modifiers:(NSEventModifierFlags)flags;
- (NSArray<NSString *> *)macrosAffectedByRestoringAll;
- (NSArray<NSDictionary<NSString *, id> *> *)conflictsForMacroShortcuts:(NSArray<NSDictionary<NSString *, id> *> *)candidates;
+ (TSShortcutBinding *)normalizedKey:(NSString *)key modifiers:(NSEventModifierFlags)flags;
+ (NSArray<NSDictionary<NSString *, id> *> *)menuBindings:(NSMenu *)menu;
+ (NSString *)reasonForMacroConflict:(NSDictionary<NSString *, id> *)conflict;
+ (NSString *)displayKey:(NSString *)key modifiers:(NSEventModifierFlags)flags;
+ (BOOL)isAllowedKey:(NSString *)key modifiers:(NSEventModifierFlags)flags;
+ (BOOL)event:(NSEvent *)event matchesItem:(NSMenuItem *)item;
@end

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
