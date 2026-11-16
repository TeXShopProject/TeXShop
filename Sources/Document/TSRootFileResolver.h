// SPDX-License-Identifier: GPL-2.0-or-later
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// How a source file names its root file.
typedef NS_ENUM(NSInteger, TSRootFileSpecifierKind) {
    /// "%!TEX root =" or "% !TEX root =" in the first 20 lines.
    TSRootFileSpecifierKindTeXRoot = 1,
    /// The old "%SourceDoc " line, read only when UseOldHeadingCommands is on.
    TSRootFileSpecifierKindSourceDoc = 2,
} NS_SWIFT_NAME(RootFileSpecifierKind);

/// The root file named in a source, as written there (not yet resolved to a path).
NS_SWIFT_NAME(RootFileSpecifier)
@interface TSRootFileSpecifier : NSObject
@property (nonatomic, readonly) TSRootFileSpecifierKind kind;
/// The name after "=" (or after "%SourceDoc "), trimmed as TeXShop has always trimmed it.
@property (nonatomic, readonly, copy) NSString *value;
- (instancetype)initWithKind:(TSRootFileSpecifierKind)kind value:(NSString *)value NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;
@end

/// Finds the root file a source names, with no side effects and Foundation only. It reads the source exactly as
/// TeXShop's typesetting, printing, syncing and opening always have, quirks included:
/// - "%!TEX root =" is looked for before "% !TEX root =" on each of the first 20 lines, anywhere on the line, case
///   sensitive. A line whose value is empty is skipped (it still counts toward the 20 lines).
/// - Only when nothing was found and `allowsSourceDoc` is set (UseOldHeadingCommands), the first "%SourceDoc " of the
///   whole source counts if it starts a line. Its value is the line from the 12th character, one character shorter than
///   the rest of the line, so a last line without a line break loses its last character.
NS_SWIFT_NAME(RootFileResolver)
@interface TSRootFileResolver : NSObject

+ (nullable TSRootFileSpecifier *)specifierInSource:(nullable NSString *)source allowingSourceDoc:(BOOL)allowsSourceDoc;
/// Only the "%SourceDoc " part of the above, as if no "% !TEX root" had been found in the first 20 lines.
+ (nullable TSRootFileSpecifier *)sourceDocSpecifierInSource:(NSString *)source;

/// The full path of `name`, relative to the folder `home`, as TeXShop's -decodeFile:homePath:job: has always made it:
/// the name is trimmed of spaces; "~" is expanded; a name starting with "/" is absolute; leading "../" climb from
/// `home`; symbolic links are then resolved; last, every `jobNameToken` (TeXShop's "\jobname", after the yen filter)
/// becomes `jobName`. An empty name raises, as it always has.
+ (NSString *)pathForName:(NSString *)name homePath:(nullable NSString *)home jobName:(nullable NSString *)jobName
             jobNameToken:(NSString *)jobNameToken;

/// The full path of the root that `source`, the text of the file at `documentPath`, names; nil if it names none.
+ (nullable NSString *)rootPathInSource:(nullable NSString *)source documentPath:(nullable NSString *)documentPath
                      allowingSourceDoc:(BOOL)allowsSourceDoc jobNameToken:(NSString *)jobNameToken
                              specifier:(TSRootFileSpecifier * _Nullable * _Nullable)specifier;

- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
