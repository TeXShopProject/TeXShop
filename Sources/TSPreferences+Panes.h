// SPDX-License-Identifier: GPL-2.0-or-later
#import "TSPreferences.h"
#import "TSPrefPaneController.h"
NS_ASSUME_NONNULL_BEGIN
@interface TSPreferences (Panes)
- (NSArray<TSPrefPaneController *> *)makeSettingsPanes;
@end
NS_ASSUME_NONNULL_END
