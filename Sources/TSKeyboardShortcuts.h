#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN
extern NSString * const TSMenuShortcutOverridesKey;
extern NSString * const TSRebuildMacrosNotification;
extern NSString * const TSMacroShortcutsChangedNotification;
// First button is the safe choice for both Return and Escape.
NSModalResponse TSRunShortcutAlert(NSAlert *alert);

@interface TSShortcutCommand : NSObject
@property (nonatomic, strong) NSMenuItem *item;
@property (nonatomic, copy) NSString *commandID;
@property (nonatomic, copy) NSString *path;
@property (nonatomic, copy) NSString *defaultKey;
@property (nonatomic) NSEventModifierFlags defaultModifiers;
@property (nonatomic) BOOL defaultLocalization;
@end

@interface TSShortcutStore : NSObject
@property (nonatomic, readonly) NSArray<TSShortcutCommand *> *commands;
@property (nonatomic, readonly) NSArray<NSString *> *unavailableCommands;
- (void)refreshMenu;
- (NSArray<NSString *> *)settingsSearchCommandNames;

- (instancetype)initWithMenu:(NSMenu *)menu defaults:(NSUserDefaults *)defaults;
- (nullable NSString *)setKey:(NSString *)key modifiers:(NSEventModifierFlags)flags forCommand:(TSShortcutCommand *)command;
- (nullable NSString *)restoreCommand:(TSShortcutCommand *)command;
- (void)restoreAll;
- (NSArray<NSString *> *)macrosUsingKey:(NSString *)key modifiers:(NSEventModifierFlags)flags;
- (NSArray<NSString *> *)macrosAffectedByRestoringAll;
- (NSArray<NSDictionary *> *)conflictsForMacroShortcuts:(NSArray<NSDictionary *> *)candidates;
+ (NSDictionary *)normalizedKey:(NSString *)key modifiers:(NSEventModifierFlags)flags;
+ (NSArray<NSDictionary *> *)menuBindings:(NSMenu *)menu;
+ (NSString *)reasonForMacroConflict:(NSDictionary *)conflict;
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
- (void)beginMenuRebuild;
- (void)endMenuRebuild;
- (void)refreshMenuAndMacros;
- (NSArray<NSDictionary *> *)conflictsForMacroShortcuts:(NSArray<NSDictionary *> *)candidates;
- (void)showKeyboardShortcuts:(nullable id)sender;
+ (BOOL)event:(NSEvent *)event matchesAction:(SEL)action tag:(NSInteger)tag;
@end
NS_ASSUME_NONNULL_END
