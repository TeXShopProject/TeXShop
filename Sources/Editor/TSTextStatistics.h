// SPDX-License-Identifier: GPL-2.0-or-later
/*
 * TSTextStatistics.h
 *
 * One count of Text Statistics: the characters, words and lines of the source as the
 * status bar counts them, and of the text that detex leaves when it removes the TeX
 * commands, with the files read by \input and \include. The text (the selection, when
 * there is one) is written to a temporary file that detex reads from the document's
 * folder, so the document need not be saved; the file is removed afterwards. detex's
 * output is counted here, as the status bar counts, not with wc.
 */

#import <Foundation/Foundation.h>
#import "TSStatusBarCounting.h"

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, TSTextStatisticsState) {
    TSTextStatisticsCounting,
    TSTextStatisticsDone,
    TSTextStatisticsDetexMissing,
    TSTextStatisticsDetexFailed,
};

@interface TSTextStatisticsResult : NSObject
@property (nonatomic, readonly) TSTextStatisticsState state;
/// YES when the selection was counted, NO for the whole document.
@property (nonatomic, readonly) BOOL selection;
/// The source as the status bar counts it (lines, characters, words).
@property (nonatomic, readonly) TSStatusBarCounts source;
/// The text that detex leaves; NSNotFound while counting or when detex did not run.
@property (nonatomic, readonly) TSStatusBarCounts text;
/// When the count started.
@property (nonatomic, readonly) NSDate *date;
@end

@interface TSTextStatistics : NSObject

/// The detex that the TeX bin folder (the TetexBinPath setting) holds, or nil.
+ (nullable NSURL *)detexInFolder:(nullable NSString *)binFolder;

/// Starts a count of `ranges` of `string` (the whole text when no range holds characters). `folder` is where detex
/// looks for the files of \input and \include (nil: the temporary folder); `encoding` is the document's, for the file
/// detex reads and for what it writes. A count already running is stopped first. `completion` runs on the main
/// queue, once, unless the count is stopped.
- (void)countString:(NSString *)string ranges:(NSArray<NSValue *> *)ranges folder:(nullable NSURL *)folder
              detex:(nullable NSURL *)detex encoding:(NSStringEncoding)encoding
         completion:(void (^)(TSTextStatisticsResult *result))completion;
/// Stops the running count, if any: detex is terminated and the temporary file removed.
- (void)stop;
/// YES while detex runs or its output is counted.
@property (nonatomic, readonly, getter=isRunning) BOOL running;
/// The temporary file of the running count, for the tests.
@property (nonatomic, readonly, nullable) NSURL *temporaryFile;

/// The text that `ranges` select in `string`, the ranges joined by a line end, or the whole string when none holds characters.
+ (NSString *)countedTextOfString:(NSString *)string ranges:(NSArray<NSValue *> *)ranges selection:(BOOL *_Nullable)selection;

@end

NS_ASSUME_NONNULL_END
