// SPDX-License-Identifier: GPL-2.0-or-later
#import <Foundation/Foundation.h>
NS_ASSUME_NONNULL_BEGIN
@interface TSThemeFileStore : NSObject
@property (readonly, copy) NSURL *directory;
// Whether a dictionary read from a theme file is a theme (nil: every dictionary is). A file that is not is read as
// nil, like one that cannot be read, and is never written into.
@property (copy, nullable) BOOL (^acceptsColors)(NSDictionary<NSString *, id> *colors);
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;
- (instancetype)initWithDirectory:(NSURL *)directory NS_DESIGNATED_INITIALIZER;
- (nullable NSURL *)URLForTitle:(NSString *)title;
- (nullable NSDictionary<NSString *, id> *)readTitle:(NSString *)title;
- (BOOL)writeColors:(NSDictionary<NSString *, id> *)colors title:(NSString *)title error:(NSError * _Nullable * _Nullable)error;
// Writes the colors that differ between before and after into the theme file as it is at that moment, and keeps its
// other colors. Returns the colors written, or nil; nil also when the file is no longer there (renamed or deleted
// elsewhere), which is not made again, and when it cannot be read as a theme, which is kept as it is. The title
// inside the file is written as the folder names the file (after a rename elsewhere in case only, its new name).
- (nullable NSDictionary<NSString *, id> *)writeChangesFrom:(NSDictionary<NSString *, id> *)before to:(NSDictionary<NSString *, id> *)after title:(NSString *)title error:(NSError * _Nullable * _Nullable)error;

// The themes in the folder (files, not folders), with composed names, in the order of the Finder.
- (NSArray<NSString *> *)titles;
// The listed title of the theme that `title` names (the same, or differing only in case after a rename elsewhere, or
// in its Unicode form), or nil when there is none.
- (nullable NSString *)existingTitleForTitle:(NSString *)title;
// The title itself when no item of the folder has it (in any case, also of the extension), else the title followed by
// the first free number from 2.
- (NSString *)availableTitleForTitle:(NSString *)title;
// Adds a theme under the title or, when it is taken (also meanwhile, by another TeXShop), the next free one; never
// replaces a file. Returns the title given, or nil.
- (nullable NSString *)addColors:(NSDictionary<NSString *, id> *)colors title:(NSString *)title error:(NSError * _Nullable * _Nullable)error;
// Renames a theme's file, composing the new title. A change of case only is allowed; another theme with the new title
// is never replaced. The colors are those of the file when it is moved.
- (BOOL)renameTitle:(NSString *)title to:(NSString *)newTitle error:(NSError * _Nullable * _Nullable)error;
// Moves a theme's file (never a folder) to the Trash.
- (BOOL)trashTitle:(NSString *)title error:(NSError * _Nullable * _Nullable)error;
// Copies the theme's file as it is to url, when it can be read as a theme and `check` (what an import of it would
// require) accepts it; else fails (NSFileReadCorruptFileError, or the error of reading the file) and makes or
// replaces nothing at url.
- (BOOL)exportTitle:(NSString *)title toURL:(NSURL *)url check:(nullable BOOL (^)(NSData *data))check error:(NSError * _Nullable * _Nullable)error;
// Adds the colors of a theme file under the file's name (composed), as addColors:title:error: does. The file must be a
// property list of colors that `check` accepts. Returns the title given, or nil.
- (nullable NSString *)importFileAtURL:(NSURL *)url check:(BOOL (^)(NSData *data))check error:(NSError * _Nullable * _Nullable)error;
@end
NS_ASSUME_NONNULL_END
