#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN
extern NSString * const TSMenuShortcutOverridesKey;

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
- (void)suspendOverridesForMenuRebuild;
- (instancetype)initWithMenu:(NSMenu *)menu defaults:(NSUserDefaults *)defaults;
- (nullable NSString *)setKey:(NSString *)key modifiers:(NSEventModifierFlags)flags forCommand:(TSShortcutCommand *)command;
- (nullable NSString *)restoreCommand:(TSShortcutCommand *)command;
- (void)restoreAll;
+ (NSString *)displayKey:(NSString *)key modifiers:(NSEventModifierFlags)flags;
+ (BOOL)isAllowedKey:(NSString *)key modifiers:(NSEventModifierFlags)flags;
+ (BOOL)event:(NSEvent *)event matchesItem:(NSMenuItem *)item;
@end

@interface TSKeyboardShortcuts : NSWindowController
+ (instancetype)sharedController;
- (void)installInMainMenu;
- (void)beginMenuRebuild;
- (void)endMenuRebuild;
- (void)showKeyboardShortcuts:(nullable id)sender;
+ (BOOL)event:(NSEvent *)event matchesAction:(SEL)action tag:(NSInteger)tag;
@end
NS_ASSUME_NONNULL_END
