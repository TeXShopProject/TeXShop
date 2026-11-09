// SPDX-License-Identifier: GPL-2.0-or-later
#import <Foundation/Foundation.h>
typedef NSString *TSPreferenceKey NS_TYPED_EXTENSIBLE_ENUM;

// Shared by preference controls and the shortcut provider.
static NSNotificationName const TSCompletionChangedNotification = @"CommandCompletionCharNotification";
