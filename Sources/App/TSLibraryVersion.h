// The version of the bundled files last copied into ~/Library/TeXShop.
// It is kept in ~/Library/TeXShop/New/.Version as the application's display version
// (CFBundleShortVersionString), so another build of the same version copies nothing again.
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// The version written in .Version of the folder, or nil when there is none.
NSString * _Nullable TSLibraryVersionInFolder(NSString *folder);

// YES when the application is a later version than the files in ~/Library/TeXShop,
// or another release of the same number (6.00 beta-1, 6.00 beta-2, 6.00).
BOOL TSLibraryNeedsUpdating(NSString * _Nullable libraryVersion, NSString * _Nullable applicationVersion);

// Write the application's version to .Version of the folder.
BOOL TSLibraryRecordVersion(NSString *folder, NSString *applicationVersion);

NS_ASSUME_NONNULL_END
