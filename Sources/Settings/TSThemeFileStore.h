// SPDX-License-Identifier: GPL-2.0-or-later
#import <Foundation/Foundation.h>
NS_ASSUME_NONNULL_BEGIN
@interface TSThemeFileStore : NSObject
@property (readonly, copy) NSURL *directory;
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;
- (instancetype)initWithDirectory:(NSURL *)directory NS_DESIGNATED_INITIALIZER;
- (nullable NSURL *)URLForTitle:(NSString *)title;
- (nullable NSDictionary<NSString *, id> *)readTitle:(NSString *)title;
- (BOOL)writeColors:(NSDictionary<NSString *, id> *)colors title:(NSString *)title error:(NSError * _Nullable * _Nullable)error;
// Writes the colors that differ between before and after into the theme file as it is at that moment, and keeps its
// other colors. Returns the colors written, or nil.
- (nullable NSDictionary<NSString *, id> *)writeChangesFrom:(NSDictionary<NSString *, id> *)before to:(NSDictionary<NSString *, id> *)after title:(NSString *)title error:(NSError * _Nullable * _Nullable)error;

// The themes in the folder, in the order of the Finder (case and numbers as people read them).
- (NSArray<NSString *> *)titles;
// The title itself when no theme has it (in any case), else the title followed by the first free number from 2.
- (NSString *)availableTitleForTitle:(NSString *)title;
// Renames a theme's file. A change of case only is allowed; another theme with the new title is never replaced.
- (BOOL)renameTitle:(NSString *)title to:(NSString *)newTitle error:(NSError * _Nullable * _Nullable)error;
// Moves a theme's file to the Trash.
- (BOOL)trashTitle:(NSString *)title error:(NSError * _Nullable * _Nullable)error;
// Copies the theme's file as it is to url.
- (BOOL)exportTitle:(NSString *)title toURL:(NSURL *)url error:(NSError * _Nullable * _Nullable)error;
// Adds the colors of a theme file under the file's name, made free with availableTitleForTitle:. The file must be a
// property list of colors that `check` accepts. Returns the title given, or nil.
- (nullable NSString *)importFileAtURL:(NSURL *)url check:(BOOL (^)(NSData *data))check error:(NSError * _Nullable * _Nullable)error;
@end
NS_ASSUME_NONNULL_END
