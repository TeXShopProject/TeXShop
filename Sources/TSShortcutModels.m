// SPDX-License-Identifier: GPL-2.0-or-later
#import "TSShortcutInternal.h"
@implementation TSShortcutMacro
- (instancetype)initWithName:(NSString *)name path:(NSString *)path indexPath:(NSIndexPath *)indexPath serializedKey:(NSString *)serializedKey key:(NSString *)key modifiers:(NSEventModifierFlags)modifiers {
    self = [super init];
    if (self == nil) { return nil; }
    _name = [name copy]; _path = [path copy]; _indexPath = [indexPath copy];
    _serializedKey = [serializedKey copy]; _key = [key copy]; _modifiers = modifiers;
    return self;
}
@end
@implementation TSShortcutMatch
- (instancetype)initWithPath:(NSString *)path menuItem:(NSMenuItem *)menuItem command:(TSShortcutCommand *)command macro:(TSShortcutMacro *)macro winner:(BOOL)winner {
    self = [super init];
    if (self == nil) { return nil; }
    _path = [path copy]; _menuItem = menuItem; _command = command; _macro = macro; _winner = winner;
    return self;
}
@end
@implementation TSShortcutCommand
@end

