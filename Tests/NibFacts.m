#import "TestAppKitIsolation.h"
// List what a compiled nib does at run time: the class of every object, every outlet,
// action, tag, identifier, delegate and binding. Custom classes get stand-in subclasses
// of the class the nib names, so their names stay visible. Nothing is shown on screen.
#import <Cocoa/Cocoa.h>
#import <PDFKit/PDFKit.h>
#import <objc/runtime.h>

static NSMutableArray<NSArray *> *recordedOutlets;   // @[source, key, destination]
static void RecordOutlet(id self, SEL cmd, id value, NSString *key) {
    if (value) [recordedOutlets addObject:@[self, key, value]];
}
// The nib connects an outlet only when its owner answers to the setter, so answer to every
// one-argument setter and record what is set.
static void RecordSetter(id self, SEL cmd, id value) {
    NSString *name = NSStringFromSelector(cmd);
    NSString *key = [[[name substringWithRange:NSMakeRange(3, 1)] lowercaseString] stringByAppendingString:[name substringWithRange:NSMakeRange(4, name.length - 5)]];
    RecordOutlet(self, cmd, value, key);
}
static BOOL ResolveSetter(id self, SEL cmd, SEL selector) {
    NSString *name = NSStringFromSelector(selector);
    if (name.length < 5 || ![name hasPrefix:@"set"] || ![name hasSuffix:@":"] || [[name componentsSeparatedByString:@":"] count] != 2) return NO;
    return class_addMethod(self, selector, (IMP)RecordSetter, "v@:@");
}
static void RegisterStandIn(NSString *name, Class base) {
    if (!name.length || NSClassFromString(name) || !base) return;
    Class c = objc_allocateClassPair(base, name.UTF8String, 0);
    if (!c) return;
    class_addMethod(c, @selector(setValue:forUndefinedKey:), (IMP)RecordOutlet, "v@:@@");
    class_addMethod(object_getClass((id)c), @selector(resolveInstanceMethod:), (IMP)ResolveSetter, "c@::");
    objc_registerClassPair(c);
}

// Every connection the nib makes, as written in it, whether or not AppKit keeps it:
// AppKit drops an action whose target does not answer to it.
static NSMutableArray<NSArray *> *connections;     // @[kind, source, label, destination]
typedef void (*Establish)(id, SEL);
static NSMutableDictionary<NSString *, NSValue *> *originalEstablish;
static void RecordConnection(id self, SEL cmd) {
    NSString *kind = NSStringFromClass([self class]);
    id source = [self respondsToSelector:@selector(source)] ? [self source] : nil;
    id destination = [self respondsToSelector:@selector(destination)] ? [self destination] : nil;
    NSString *label = [self respondsToSelector:@selector(label)] ? [self label] : @"";
    if ([self respondsToSelector:@selector(keyPath)]) label = [NSString stringWithFormat:@"%@=%@", label, [self keyPath]];
    [connections addObject:@[kind, source ?: NSNull.null, label ?: @"", destination ?: NSNull.null]];
    for (Class c = [self class]; c; c = class_getSuperclass(c)) {
        NSValue *original = originalEstablish[NSStringFromClass(c)];
        if (original) { ((Establish)original.pointerValue)(self, cmd); return; }
    }
}
static void HookConnectors(void) {
    connections = [NSMutableArray array]; originalEstablish = [NSMutableDictionary dictionary];
    for (NSString *name in @[@"NSNibOutletConnector", @"NSNibControlConnector", @"NSNibBindingConnector", @"NSIBUserDefinedRuntimeAttributesConnector", @"NSNibAXRelationshipConnector"]) {
        Class c = NSClassFromString(name);
        Method m = c ? class_getInstanceMethod(c, @selector(establishConnection)) : NULL;
        if (!m) continue;
        originalEstablish[name] = [NSValue valueWithPointer:method_getImplementation(m)];
        if (!class_addMethod(c, @selector(establishConnection), (IMP)RecordConnection, method_getTypeEncoding(m)))
            method_setImplementation(class_getInstanceMethod(c, @selector(establishConnection)), (IMP)RecordConnection);
    }
}

typedef id (*InitWithCoder)(id, SEL, NSCoder *);
static NSMutableDictionary<NSString *, NSValue *> *originalInits;
static id StandInInit(id self, SEL cmd, NSCoder *coder) {
    for (Class c = object_getClass(self); c; c = class_getSuperclass(c)) {
        NSString *name = NSStringFromClass(c);
        if ([name isEqual:@"NSClassSwapper"]) {
            NSString *custom = [coder decodeObjectForKey:@"NSClassName"], *original = [coder decodeObjectForKey:@"NSOriginalClassName"];
            RegisterStandIn(custom, NSClassFromString(original));
        } else if ([name isEqual:@"NSCustomObject"]) {
            RegisterStandIn([coder decodeObjectForKey:@"NSClassName"], NSObject.class);
        } else if ([name isEqual:@"NSCustomView"]) {
            RegisterStandIn([coder decodeObjectForKey:@"NSClassName"], NSView.class);
        } else if ([name isEqual:@"NSWindowTemplate"]) {
            RegisterStandIn([coder decodeObjectForKey:@"NSWindowClass"], NSWindow.class);
        } else continue;
        InitWithCoder original = (InitWithCoder)originalInits[name].pointerValue;
        return original(self, cmd, coder);
    }
    return nil;
}
static void HookTemplates(void) {
    originalInits = [NSMutableDictionary dictionary];
    for (NSString *name in @[@"NSClassSwapper", @"NSCustomObject", @"NSCustomView", @"NSWindowTemplate"]) {
        Class c = NSClassFromString(name);
        Method m = c ? class_getInstanceMethod(c, @selector(initWithCoder:)) : NULL;
        if (!m) continue;
        originalInits[name] = [NSValue valueWithPointer:method_getImplementation(m)];
        // Give the class its own method so that a subclass hook calls the right original.
        if (!class_addMethod(c, @selector(initWithCoder:), (IMP)StandInInit, method_getTypeEncoding(m)))
            method_setImplementation(class_getInstanceMethod(c, @selector(initWithCoder:)), (IMP)StandInInit);
    }
}

@interface NibOwner : NSObject
@end
@implementation NibOwner
+ (BOOL)resolveInstanceMethod:(SEL)selector { return ResolveSetter(self, _cmd, selector) || [super resolveInstanceMethod:selector]; }
- (void)setValue:(id)value forUndefinedKey:(NSString *)key { if (value) [recordedOutlets addObject:@[self, key, value]]; }
@end

static NibOwner *owner;
static NSString *ClassName(id object) { return NSStringFromClass([object class]); }
static BOOL Automatic(NSString *ident) { return [ident hasPrefix:@"_NS:"] || [ident hasPrefix:@"__NS"] || [ident isEqual:@"Automatic"]; }
static NSMapTable<id, NSString *> *labels;     // outlet-named objects
static NSMapTable<id, id> *parents;
static NSMutableArray<NSString *> *facts;
static NSHashTable *visited;

static NSString *Label(id object) {
    if (!object) return @"nil";
    if (object == owner) return @"Owner";
    if (object == NSApp) return @"App";
    NSString *label = [labels objectForKey:object];
    if (label) return label;
    NSString *ident = [object respondsToSelector:@selector(identifier)] && ![object isKindOfClass:NSTableColumn.class] ? [object identifier] : nil;
    return ident.length && !Automatic(ident) ? [NSString stringWithFormat:@"%@#%@", ClassName(object), ident] : ClassName(object);
}
static NSString *Place(id object) {
    // The nearest outlet-named object around this one, or the top-level object it is in.
    id last = object;
    for (id p = [parents objectForKey:object]; p; p = [parents objectForKey:p]) {
        if ([labels objectForKey:p]) return [labels objectForKey:p];
        last = p;
    }
    if (last == object) return @"top";
    NSString *ident = [last respondsToSelector:@selector(identifier)] ? [last identifier] : nil;
    return [NSString stringWithFormat:@"top:%@%@", ClassName(last), ident.length && !Automatic(ident) ? [@"#" stringByAppendingString:ident] : @""];
}
static NSString *Target(id target) {
    if (!target) return @"FirstResponder";
    return Label(target);
}
static NSMutableArray *ordered;
static void Visit(id object, id parent);
static void Child(id child, id parent) { if (child) Visit(child, parent); }
// First pass: find every object and what contains it. An object that the nib also lists at
// the top level still belongs to the window, drawer or menu that holds it.
static void Visit(id object, id parent) {
    if (!object) return;
    if (parent && ![parents objectForKey:object] && object != parent) [parents setObject:parent forKey:object];
    if ([visited containsObject:object]) return;
    [visited addObject:object]; [ordered addObject:object];
    if ([object isKindOfClass:NSWindow.class]) {
        Child([object contentView], object);
        Child([object toolbar], object);
    }
    if ([object isKindOfClass:NSDrawer.class]) Child([object contentView], object);
    if ([object isKindOfClass:NSToolbar.class]) for (id item in [object items]) Child(item, object);
    if ([object isKindOfClass:NSToolbarItem.class]) Child([object view], object);
    if ([object isKindOfClass:NSView.class]) {
        for (NSView *sub in [object subviews])
            if (![ClassName(sub) hasPrefix:@"_"]) Child(sub, object);   // AppKit's private parts
        // A text view's menu is AppKit's standard context menu unless the nib sets one.
        if ([object menu] && !([object isKindOfClass:NSTextView.class] && [object menu] == [[object class] defaultMenu])) Child([object menu], object);
    }
    if ([object isKindOfClass:NSTabView.class]) for (NSTabViewItem *item in [object tabViewItems]) Child(item.view, object);
    if ([object isKindOfClass:NSMatrix.class]) for (id cell in [object cells]) Child(cell, object);
    if ([object isKindOfClass:NSPopUpButton.class]) Child([object menu], object);
    if ([object isKindOfClass:NSTableView.class]) for (id column in [object tableColumns]) Child(column, object);
    if ([object isKindOfClass:NSMenu.class]) for (NSMenuItem *item in [object itemArray]) Child(item, object);
    if ([object isKindOfClass:NSMenuItem.class]) Child([object submenu], object);
}
// Second pass: what each object does.
static void Describe(id object) {
    NSMutableArray *parts = [NSMutableArray arrayWithObject:ClassName(object)];
    if ([object isKindOfClass:NSTableColumn.class]) [parts addObject:[@"column=" stringByAppendingString:[object identifier] ?: @""]];
    else if ([object respondsToSelector:@selector(identifier)]) {
        NSString *ident = [object identifier];
        if (ident.length && !Automatic(ident)) [parts addObject:[@"id=" stringByAppendingString:ident]];
    }
    if ([object isKindOfClass:NSControl.class] || [object isKindOfClass:NSCell.class] || [object isKindOfClass:NSMenuItem.class]) {
        SEL action = [object action];
        if (action) [parts addObject:[NSString stringWithFormat:@"action=%@>%@", NSStringFromSelector(action), Target([object target])]];
        NSInteger tag = [object tag];
        if (tag) [parts addObject:[NSString stringWithFormat:@"tag=%ld", (long)tag]];
    }
    if ([object isKindOfClass:NSMenuItem.class]) {
        NSMenuItem *item = object;
        if (item.isSeparatorItem) [parts addObject:@"separator"];
        if (item.isAlternate) [parts addObject:@"alternate"];
        if (item.keyEquivalent.length) [parts addObject:[NSString stringWithFormat:@"key=%@+%lu", item.keyEquivalent, (unsigned long)item.keyEquivalentModifierMask]];
    }
    if ([object respondsToSelector:@selector(delegate)] && ![object isKindOfClass:NSApplication.class]) {
        id delegate = [object delegate];
        if (delegate && delegate != object) [parts addObject:[@"delegate=" stringByAppendingString:Label(delegate)]];
    }
    if ([object respondsToSelector:@selector(dataSource)]) {
        id source = [object dataSource];
        if (source) [parts addObject:[@"dataSource=" stringByAppendingString:Label(source)]];
    }
    if (![object isKindOfClass:NSMenu.class])
        for (NSString *binding in [object exposedBindings]) {
            NSDictionary *info = [object infoForBinding:binding];
            if (info) [parts addObject:[NSString stringWithFormat:@"bind %@=%@.%@", binding, Label(info[NSObservedObjectKey]), info[NSObservedKeyPathKey]]];
        }
    [facts addObject:[NSString stringWithFormat:@"%@ | %@ | %@", [labels objectForKey:object] ?: @"-", Place(object), [parts componentsJoinedByString:@" "]]];
    if ([object isKindOfClass:NSSegmentedControl.class]) {
        NSSegmentedControl *seg = object;
        for (NSInteger i = 0; i < seg.segmentCount; i++)
            [facts addObject:[NSString stringWithFormat:@"%@ | %@ | segment %ld tag=%ld menu=%d", Label(seg), Place(seg), (long)i, (long)[seg.cell tagForSegment:i], [seg menuForSegment:i] != nil]];
    }
}

int main(int argc, char **argv) { @autoreleasepool {
    TSInstallAppKitIsolation(); [NSApplication sharedApplication];
    HookTemplates(); HookConnectors();
    recordedOutlets = [NSMutableArray array];
    owner = [NibOwner new];
    NSData *data = [NSData dataWithContentsOfFile:@(argv[1])];
    if (!data) { fprintf(stderr, "Cannot read %s\n", argv[1]); return 2; }
    NSNib *nib = [[NSNib alloc] initWithNibData:data bundle:nil];
    NSArray *objects = nil;
    if (![nib instantiateWithOwner:owner topLevelObjects:&objects]) { fprintf(stderr, "Cannot load %s\n", argv[1]); return 3; }
    labels = [NSMapTable strongToStrongObjectsMapTable]; parents = [NSMapTable strongToStrongObjectsMapTable];
    facts = [NSMutableArray array]; visited = [NSHashTable hashTableWithOptions:NSPointerFunctionsObjectPointerPersonality];
    // Name objects by the owner's outlets first, then by other objects' outlets.
    NSArray *sorted = [recordedOutlets sortedArrayUsingComparator:^(NSArray *a, NSArray *b) {
        BOOL ao = a[0] == owner, bo = b[0] == owner;
        if (ao != bo) return ao ? NSOrderedAscending : NSOrderedDescending;
        return [a[1] compare:b[1]];
    }];
    for (NSArray *o in sorted) if (o[0] == owner && ![labels objectForKey:o[2]]) [labels setObject:[@"@" stringByAppendingString:o[1]] forKey:o[2]];
    // Visit everything, then describe every outlet with the place of its destination.
    NSMutableArray *roots = [NSMutableArray array];
    for (id object in objects) if (object != NSApp) [roots addObject:object];
    for (NSArray *o in sorted) [roots addObject:o[2]];
    ordered = [NSMutableArray array];
    for (id object in roots) Visit(object, nil);
    for (id object in ordered) Describe(object);
    for (NSArray *o in sorted) {
        id destination = o[2];
        if ([destination isKindOfClass:NSNumber.class] || [destination isKindOfClass:NSString.class])
            [facts addObject:[NSString stringWithFormat:@"attribute %@ in %@ .%@ = %@", Label(o[0]), Place(o[0]), o[1], destination]];
        else
            [facts addObject:[NSString stringWithFormat:@"outlet %@.%@ -> %@ in %@", Label(o[0]), o[1], ClassName(destination), Place(destination)]];
    }
    for (NSArray *c in connections) {
        id source = c[1] == NSNull.null ? nil : c[1], destination = c[3] == NSNull.null ? nil : c[3];
        if ([c[0] isEqual:@"NSNibOutletConnector"]) continue;   // listed above from what was set
        NSString *kind = [c[0] isEqual:@"NSNibControlConnector"] ? @"action" : c[0];
        [facts addObject:[NSString stringWithFormat:@"%@ %@ (%@ in %@) %@ -> %@", kind, Label(source), ClassName(source), Place(source), c[2], [c[0] isEqual:@"NSNibControlConnector"] ? Target(destination) : Label(destination)]];
    }
    for (id object in objects) if ([object isKindOfClass:NSWindow.class]) [object orderOut:nil];
    NSArray *out = [facts sortedArrayUsingSelector:@selector(compare:)];
    NSData *json = [NSJSONSerialization dataWithJSONObject:out options:0 error:nil];
    fwrite(json.bytes, 1, json.length, stdout);
}
return 0; }
