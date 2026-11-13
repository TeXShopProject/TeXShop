// SPDX-License-Identifier: GPL-2.0-or-later
#import <Foundation/Foundation.h>
#import "TSRegexFindOptions.h"
#import "TSRegexReplacementTemplate.h"

@class NSPasteboard;

NS_ASSUME_NONNULL_BEGIN

/// The state of the Advanced Find panel kept between launches (the AdvancedFind… settings, plan §5).
/// The defaults are passed in, so tests can use their own.
NS_SWIFT_NAME(AdvancedFindSettings)
@interface TSAdvancedFindSettings : NSObject

@property (nonatomic) TSRegexFindOptions options;
@property (nonatomic) TSRegexReplacementSyntax replacementSyntax;
@property (nonatomic) BOOL inSelection;
@property (nonatomic) BOOL wraps;
/// The next search starts at the top of the text, then this turns itself off (OgreKit's "Origin: Top").
@property (nonatomic) BOOL startsFromTop;
@property (nonatomic) BOOL closesWhenDone;
/// "Live Update" of the Find All list: the list searches again shortly after each edit.
@property (nonatomic) BOOL updatesResultsLive;
@property (nonatomic, readonly) NSUInteger historyLimit;
@property (nonatomic, readonly, copy) NSArray<NSString *> *findHistory;
@property (nonatomic, readonly, copy) NSArray<NSString *> *replaceHistory;

/// Shared with other applications through the find pasteboard.
@property (nonatomic, copy) NSString *findString;
@property (nonatomic, copy) NSString *replaceString;

- (instancetype)initWithDefaults:(NSUserDefaults *)defaults findPasteboard:(nullable NSPasteboard *)pasteboard NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;

/// Reads the find pasteboard, which another application may have changed.
- (void)reloadFindStringFromPasteboard;
- (void)noteFindString;
- (void)noteReplaceString;
- (void)clearHistories;
- (void)clearFindHistory;
- (void)clearReplaceHistory;

@end

NS_ASSUME_NONNULL_END
