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
/// The bundled sample sets: a folder of definitions whose names and notes are English. They are written the first
/// time the sets are listed, and only when the folder of sets does not exist yet, so a sample that the user changed or
/// removed is never written again. Nil (the default): no samples.
@property (nonatomic, copy, nullable) NSURL *samplesDirectory;
/// Translates the names and notes of the samples with its table MultipleReplaceSamples; the main bundle by default.
@property (nonatomic, null_resettable) NSBundle *samplesBundle;

- (instancetype)initWithDirectory:(NSURL *)directory NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;

/// In the Finder's order. The first time, writes the samples when the folder does not exist yet.
@property (nonatomic, readonly, copy) NSArray<NSString *> *setNames;
/// Writes the samples, translated, into a new folder of sets: in a hidden folder beside it that is then renamed, so
/// the folder appears complete or not at all, and an existing folder is never replaced. YES when they were written.
- (BOOL)installSamples;
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
