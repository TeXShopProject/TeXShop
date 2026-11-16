// SPDX-License-Identifier: GPL-2.0-or-later
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Magic comments read from the raw bytes of a source, with no side effects and Foundation only, exactly as
/// -[TSDocument dataEncoding:] has always read them before the text is decoded.
NS_SWIFT_NAME(SourceMagicComments)
@interface TSSourceMagicComments : NSObject

/// The text in which the magic comments of `data` are looked for: UTF-16 when the data starts with a UTF-16 byte
/// order mark and reads as UTF-16, otherwise the bytes one by one as Latin 9.
+ (NSString *)headerTextOfData:(NSData *)data;

/// The encoding name of "%!TEX encoding =" or "% !TEX encoding =" (case sensitive, anywhere on the line), or with
/// `allowsOldHeading` (UseOldHeadingCommands) "%&encoding=", in the first 20 lines of `headerText`. The first line
/// with a marker ends the search: its value, trimmed, is returned even when it is empty (TeXShop then asks
/// TSEncodingSupport for the empty name, as it always has), and nil is returned only when nothing follows the marker.
/// Nil when no line has a marker.
+ (nullable NSString *)encodingNameInHeaderText:(NSString *)headerText allowingOldHeading:(BOOL)allowsOldHeading;

- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
