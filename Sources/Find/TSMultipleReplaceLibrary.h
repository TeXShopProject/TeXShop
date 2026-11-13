// SPDX-License-Identifier: GPL-2.0-or-later
#import <Foundation/Foundation.h>
#import "TSRegexMultipleReplace.h"

NS_ASSUME_NONNULL_BEGIN

/// The saved multiple replacement sets: one file per set in one folder (in TeXShop ~/Library/TeXShop/MultipleReplace/).
/// The file is CotEditor's replacement definition, so the name of a set is the name of its file. Foundation only.
NS_SWIFT_NAME(MultipleReplaceLibrary)
@interface TSMultipleReplaceLibrary : NSObject

/// "json": the content is CotEditor's replacement definition. Defined in one place (TSMultipleReplaceFileExtension).
@property (class, nonatomic, readonly) NSString *fileExtension;
@property (nonatomic, readonly, copy) NSURL *directory;
/// Removed sets go to the Trash (the default); the self test removes them for good.
@property (nonatomic) BOOL usesTrash;

- (instancetype)initWithDirectory:(NSURL *)directory NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;

/// In the Finder's order.
@property (nonatomic, readonly, copy) NSArray<NSString *> *setNames;
- (nullable TSRegexMultipleReplace *)setNamed:(NSString *)name error:(NSError **)error;
- (BOOL)saveSet:(TSRegexMultipleReplace *)set named:(NSString *)name error:(NSError **)error;
- (BOOL)removeSetNamed:(NSString *)name error:(NSError **)error;
/// Fails when the new name is taken or cannot be a file name.
- (BOOL)renameSetNamed:(NSString *)name to:(NSString *)newName error:(NSError **)error;
/// `name`, or `name 2`, `name 3`… when it is taken.
- (NSString *)availableNameForName:(NSString *)name;
/// YES for a name that can be a file name here: not empty, no slash or colon, not starting with a dot.
+ (BOOL)isValidName:(NSString *)name;

/// Reads a replacement definition (.json, or CotEditor's .cotrpl) or tab-separated text (any other extension) and
/// saves it under the file's name, or "Imported" when that cannot be a name. Returns the name it was saved under.
- (nullable NSString *)importFileAtURL:(NSURL *)url error:(NSError **)error;
- (BOOL)exportSetNamed:(NSString *)name toURL:(NSURL *)url error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
