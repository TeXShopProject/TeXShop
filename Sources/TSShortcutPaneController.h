// SPDX-License-Identifier: GPL-2.0-or-later
#import <Cocoa/Cocoa.h>
#import "TSKeyboardShortcuts.h"
#import "TSSettingsWindowController.h"
NS_ASSUME_NONNULL_BEGIN
@interface TSShortcutMacro : NSObject
@property (copy, readonly) NSString *name;
@property (copy, readonly) NSString *path;
@property (copy, readonly) NSIndexPath *indexPath;
@property (copy, readonly) NSString *serializedKey;
@property (copy, readonly) NSString *key;
@property (readonly) NSEventModifierFlags modifiers;
- (instancetype)initWithName:(NSString *)name path:(NSString *)path indexPath:(NSIndexPath *)indexPath serializedKey:(NSString *)serializedKey key:(NSString *)key modifiers:(NSEventModifierFlags)modifiers NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;
@end
@interface TSShortcutMatch : NSObject
@property (copy, readonly) NSString *path;
@property (strong, readonly, nullable) NSMenuItem *menuItem;
@property (strong, readonly, nullable) TSShortcutCommand *command;
@property (strong, readonly, nullable) TSShortcutMacro *macro;
@property (readonly) BOOL winner;
- (instancetype)initWithPath:(NSString *)path menuItem:(nullable NSMenuItem *)menuItem command:(nullable TSShortcutCommand *)command macro:(nullable TSShortcutMacro *)macro winner:(BOOL)winner NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;
@end
@interface TSShortcutSearch : NSObject
+ (NSArray<TSShortcutMatch *> *)matchesEvent:(NSEvent *)event store:(TSShortcutStore *)store macros:(NSArray<TSShortcutMacro *> *)macros;
+ (NSArray<TSShortcutMatch *> *)matchesKey:(NSString *)key modifiers:(NSEventModifierFlags)flags store:(TSShortcutStore *)store macros:(NSArray<TSShortcutMacro *> *)macros;
@end
@interface TSShortcutPaneController : NSViewController <TSSettingsKeyboardPane>
@property (readonly) BOOL searchingByKey;
@property (strong, nullable) NSView *settingsHeader;
- (instancetype)initWithShortcuts:(TSKeyboardShortcuts *)shortcuts NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;
- (instancetype)initWithNibName:(nullable NSNibName)name bundle:(nullable NSBundle *)bundle NS_UNAVAILABLE;
- (instancetype)initWithCoder:(NSCoder *)coder NS_UNAVAILABLE;
- (void)stopKeySearch;
- (BOOL)handleKeySearchEvent:(NSEvent *)event;
@end
NS_ASSUME_NONNULL_END
