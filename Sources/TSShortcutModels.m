// SPDX-License-Identifier: GPL-2.0-or-later
#import "TSShortcutInternal.h"
@implementation TSShortcutBinding
- (instancetype)initWithKey:(NSString *)key modifiers:(NSEventModifierFlags)modifiers {
    self=[super init];if(self){_key=[key copy];_modifiers=modifiers;}return self;
}
- (NSUInteger)count { return 2; }
- (NSEnumerator<NSString *> *)keyEnumerator { return [@[@"key",@"modifiers"] objectEnumerator]; }
- (nullable id)objectForKey:(id)key {
    if([key isEqual:@"key"])return self.key;
    if([key isEqual:@"modifiers"])return @(self.modifiers);
    return nil;
}
- (id)copyWithZone:(NSZone *)zone { return self; }
@end

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
@interface TSShortcutCommand ()
@property (nonatomic, readwrite, copy) NSString *path;
@end
@implementation TSShortcutCommand
- (instancetype)initWithItem:(NSMenuItem *)item identifier:(NSString *)identifier path:(NSString *)path {
    self=[super init];if(!self)return nil;
    _item=item;_commandID=[identifier copy];_path=[path copy];
    _defaultKey=[item.keyEquivalent copy];_defaultModifiers=item.keyEquivalentModifierMask;
    _defaultLocalization=item.allowsAutomaticKeyEquivalentLocalization;
    return self;
}
@end

