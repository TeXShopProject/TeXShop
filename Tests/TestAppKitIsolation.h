#pragma once
#import <Cocoa/Cocoa.h>
#import <objc/runtime.h>
#import "MemoryDefaults.h"
// Install before NSApplication or any nib. Never order a test window or save
// AppKit's frame preferences, including secondary windows in a compiled nib.
static TSMemoryDefaults *TSIsolatedAppKitDefaults;
static id TSInMemoryStandardDefaults(id receiver, SEL selector) { return TSIsolatedAppKitDefaults; }
static void TSPreventTestOrdering(id receiver, SEL selector, NSWindowOrderingMode mode, NSInteger relative) {}
static void TSPreventTestFrameSave(id receiver, SEL selector, NSString *name) {}
static BOOL TSPreventTestFrameName(id receiver, SEL selector, NSString *name) { return NO; }
static void TSInstallAppKitIsolation(void) {
    TSIsolatedAppKitDefaults = [TSMemoryDefaults new];
    method_setImplementation(class_getClassMethod(NSUserDefaults.class, @selector(standardUserDefaults)), (IMP)TSInMemoryStandardDefaults);
    method_setImplementation(class_getInstanceMethod(NSWindow.class, @selector(orderWindow:relativeTo:)), (IMP)TSPreventTestOrdering);
    method_setImplementation(class_getInstanceMethod(NSWindow.class, @selector(saveFrameUsingName:)), (IMP)TSPreventTestFrameSave);
    method_setImplementation(class_getInstanceMethod(NSWindow.class, @selector(setFrameAutosaveName:)), (IMP)TSPreventTestFrameName);
    NSCAssert(NSUserDefaults.standardUserDefaults == TSIsolatedAppKitDefaults, @"AppKit defaults must remain in memory");
}
