// SPDX-License-Identifier: GPL-2.0-or-later
// Inert boundaries for the complete production TSPreferences translation unit.
// No preference action body is copied into the test. Unimplemented external
// services deliberately raise an unrecognized-selector exception if reached.
#import <Cocoa/Cocoa.h>
#import "TSPreferenceProfile.h"
#define INERT_CLASS(Name, Parent) @interface Name : Parent @end @implementation Name @end
INERT_CLASS(TSConsoleWindow,NSWindow)
INERT_CLASS(TSDocument,NSObject)
INERT_CLASS(TSEnginePathDiscovery,NSObject)
#ifndef TS_TEST_REAL_SHORTCUTS
INERT_CLASS(TSShortcutPaneController,NSViewController)
#endif
@interface TSSparkleController:NSObject @end
@implementation TSSparkleController
+ (id)sharedUpdater { return nil; }
+ (id)sharedController { return nil; }
@end
NSNotificationName const TSSparkleUpdateCheckDidFinishNotification = @"TSSparkleUpdateCheckDidFinishNotification";
#ifndef TS_TEST_REAL_SHORTCUTS
@interface TSKeyboardShortcuts : NSObject
+ (id)sharedController;
@end
@implementation TSKeyboardShortcuts
+ (id)sharedController { return nil; }
@end
#endif
@interface TSWindowManager : NSObject
@property (strong) NSWindow *activeTextWindow, *activePDFWindow, *activeHTMLWindow;
+ (id)sharedInstance;
@end
@implementation TSWindowManager
+ (id)sharedInstance { static TSWindowManager *instance; if(!instance)instance=[self new]; return instance; }
@end
@interface TSEncodingSupport : NSObject
+ (id)sharedInstance;
- (NSString *)keyForStringEncoding:(NSStringEncoding)encoding;
@end
NSUInteger TSSettingsEncodingPreparations;
@implementation TSEncodingSupport
+ (id)sharedInstance { static TSEncodingSupport *instance; if(!instance)instance=[self new]; return instance; }
- (NSString *)keyForStringEncoding:(NSStringEncoding)encoding {
    if(encoding==NSUTF8StringEncoding)return @"UTF-8 Unicode";
    if(encoding==NSMacOSRomanStringEncoding)return @"MacOSRoman";
    [NSException raise:NSInternalInconsistencyException format:@"Unexpected encoding fixture"];return nil;
}
- (void)addEncodingsToMenu:(NSMenu *)menu withTarget:(id)target action:(SEL)action {
    for(NSNumber *code in @[@(NSUTF8StringEncoding),@(NSMacOSRomanStringEncoding)]) {
        NSMenuItem *item=[[NSMenuItem alloc]initWithTitle:[NSString localizedNameOfStringEncoding:code.unsignedIntegerValue] action:action keyEquivalent:@""];item.tag=code.integerValue;item.target=target;[menu addItem:item];
    }
}
- (NSStringEncoding)defaultEncoding { return NSUTF8StringEncoding; }
- (void)setupForEncoding {TSSettingsEncodingPreparations++;}
@end
#ifndef TS_TEST_REAL_PROFILE
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wincomplete-implementation"
@implementation TSPreferenceProfile @end
#pragma clang diagnostic pop
NSSet<TSPreferenceKey> *TSKnownPreferenceKeys(void) { [NSException raise:NSInternalInconsistencyException format:@"Unexpected profile lookup"]; return [NSSet set]; }

TSPreferenceKey const TSSettingsSelectedCategoryKey = @"TSSettingsSelectedCategory";

#endif
