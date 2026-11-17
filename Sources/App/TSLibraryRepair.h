// SPDX-License-Identifier: GPL-2.0-or-later
// The settings files of ~/Library/TeXShop that TeXShop needs, each restored from the copy inside TeXShop when it is
// missing or damaged. A damaged file is kept in ~/Library/TeXShop/Backups before it is replaced. Nothing is shown:
// TeXShop goes on with the restored file.
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Decides whether the contents of a settings file can be used; `bundled` is the contents of the copy inside TeXShop.
typedef BOOL (^TSLibraryFileCheck)(NSData *data, NSData *_Nullable bundled);

/// A property list whose root is a dictionary.
FOUNDATION_EXPORT TSLibraryFileCheck TSLibraryDictionaryCheck(void);
/// A dictionary that has every array and dictionary the copy inside TeXShop has, each array at least as long (the
/// LaTeX and Matrix panels take their buttons from fixed positions).
FOUNDATION_EXPORT TSLibraryFileCheck TSLibraryShapeOfBundledCheck(void);
/// The macros: a dictionary whose `submenu`, when there, is an array.
FOUNDATION_EXPORT TSLibraryFileCheck TSLibraryMacrosCheck(void);
/// The completions of the keyboard: a dictionary of strings.
FOUNDATION_EXPORT TSLibraryFileCheck TSLibraryStringDictionaryCheck(void);
/// A theme: a dictionary whose color values are arrays of at least three numbers.
FOUNDATION_EXPORT TSLibraryFileCheck TSLibraryThemeCheck(void);
/// Text in UTF-8.
FOUNDATION_EXPORT TSLibraryFileCheck TSLibraryUTF8TextCheck(void);
/// Any file that can be read.
FOUNDATION_EXPORT TSLibraryFileCheck TSLibraryReadableCheck(void);

/// Restores `path`, a file in ~/Library/TeXShop, from `bundledPath` when it is missing or `check` refuses it, and
/// returns `path`. A file behind a symbolic link is restored where the link points. With `bundledPath` nil a damaged
/// file is only moved to the backups, so that the caller falls back to another file. Returns whether the file at
/// `path` can now be used.
FOUNDATION_EXPORT BOOL TSLibraryRepairFile(NSString *path, NSString *_Nullable bundledPath, TSLibraryFileCheck check);

/// The copy inside TeXShop of a file of ~/Library/TeXShop, by its path below that folder ("Macros/Macros_Latex.plist").
FOUNDATION_EXPORT NSString *_Nullable TSLibraryBundledPath(NSString *relativePath);

/// The settings files TeXShop needs, checked once at launch after ~/Library/TeXShop has been filled.
FOUNDATION_EXPORT void TSLibraryRepairAll(void);

/// Where damaged files go (~/Library/TeXShop/Backups). For tests.
FOUNDATION_EXPORT NSString *TSLibraryBackupFolder(void);

NS_ASSUME_NONNULL_END
