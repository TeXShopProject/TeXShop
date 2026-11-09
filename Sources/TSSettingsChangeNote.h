// SPDX-License-Identifier: GPL-2.0-or-later
#import <Cocoa/Cocoa.h>
NS_ASSUME_NONNULL_BEGIN
// Called by the launch-time consumer, never by the settings window.
FOUNDATION_EXPORT void TSSettingsRememberLaunchValue(NSString *key, id value);
FOUNDATION_EXPORT NSDictionary<NSString *, id> *TSSettingsLaunchValues(void);

@interface TSSettingsChangeNote : NSStackView
- (instancetype)initWithText:(NSString *)text;
- (void)setShown:(BOOL)shown announce:(BOOL)announce;
@end

@interface TSSettingsChangeNotes : NSObject
@property (copy) BOOL (^hasSourceWindow)(void);
@property (copy) BOOL (^hasPDFWindow)(void);
- (instancetype)initWithDefaults:(NSUserDefaults *)defaults launchValues:(NSDictionary<NSString *, id> *)launchValues bundle:(NSBundle *)bundle;
- (void)attachToPanes:(NSDictionary<NSString *, NSViewController *> *)panes;
- (id)currentValueForKey:(NSString *)key;
- (void)beginSession;
- (void)leaveCategory;
- (void)endSession;
- (void)valuesReplaced;
- (void)refreshRestartNotes;
- (void)recordUserChangeForKey:(NSString *)key previousValue:(id)value;
@end
NS_ASSUME_NONNULL_END
