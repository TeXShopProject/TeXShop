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
/// A dictionary that has every array and dictionary the copy inside TeXShop has, the arrays of strings holding strings.
/// Each array is at least as long as TeXShop's (the LaTeX and Matrix panels take their buttons from fixed positions),
/// except the arrays named in `anyLength`.
FOUNDATION_EXPORT TSLibraryFileCheck TSLibraryShapeOfBundledCheck(NSSet<NSString *> *_Nullable anyLength);
/// The arrays of the LaTeX panel that may have any length.
FOUNDATION_EXPORT NSSet<NSString *> *TSLibraryLaTeXPanelAnyLength(void);
/// The macros: a dictionary whose `submenu`, when there, holds items with a name, string contents and keys, and
/// submenus of the same.
FOUNDATION_EXPORT TSLibraryFileCheck TSLibraryMacrosCheck(void);
/// The completions of the keyboard: a dictionary of strings.
FOUNDATION_EXPORT TSLibraryFileCheck TSLibraryStringDictionaryCheck(void);
/// A theme: a dictionary whose colors are arrays of four numbers (red, green, blue, alpha); the keys that TeXShop's own
/// theme (the same name, else LiteTheme) has as something else keep that type.
FOUNDATION_EXPORT TSLibraryFileCheck TSLibraryThemeCheck(void);
/// Text in UTF-8.
FOUNDATION_EXPORT TSLibraryFileCheck TSLibraryUTF8TextCheck(void);
/// Any file that can be read, empty or not.
FOUNDATION_EXPORT TSLibraryFileCheck TSLibraryReadableCheck(void);
/// A file that is not empty.
FOUNDATION_EXPORT TSLibraryFileCheck TSLibraryNonEmptyCheck(void);

/// Restores `path`, a file in ~/Library/TeXShop, from `bundledPath` when it is missing or `check` refuses it. A file
/// behind a symbolic link is restored where the link points. With `bundledPath` nil a damaged file is only moved to
/// the backups. A damaged file is left as it is when it changed in the last `TSLibraryQuietSeconds` (it may be being
/// saved), when it changes while it is read, when it cannot be moved to the backups, or when its links do not end.
/// Returns whether the file at `path` can now be used; when not, the caller reads TeXShop's copy instead.
FOUNDATION_EXPORT BOOL TSLibraryRepairFile(NSString *path, NSString *_Nullable bundledPath, TSLibraryFileCheck check);

/// While TeXShop runs: restores `path` from `bundledPath` only when nothing is there (a missing file is not being
/// saved by anyone). A file that is there is never changed; returns whether it passes `check`, and when not, the
/// caller reads TeXShop's copy until the next launch repairs it (TSLibraryRepairAll).
FOUNDATION_EXPORT BOOL TSLibraryRestoreMissingFile(NSString *path, NSString *_Nullable bundledPath, TSLibraryFileCheck check);

/// Whether the file at `path` (where its links point) passes `check`, without changing anything.
FOUNDATION_EXPORT BOOL TSLibraryFileIsUsable(NSString *path, NSString *_Nullable bundledPath, TSLibraryFileCheck check);

/// How recently a damaged file may have changed and still be left alone (it may be being saved). 5 seconds.
FOUNDATION_EXPORT NSTimeInterval TSLibraryQuietSeconds;

/// The copy inside TeXShop of a file of ~/Library/TeXShop, by its path below that folder ("Macros/Macros_Latex.plist").
FOUNDATION_EXPORT NSString *_Nullable TSLibraryBundledPath(NSString *relativePath);

/// The settings files TeXShop needs, checked once at launch after ~/Library/TeXShop has been filled; the only place
/// where damaged files are replaced. Also the themes in use and the macros of the other engines.
FOUNDATION_EXPORT void TSLibraryRepairAll(void);

/// Where damaged files go (~/Library/TeXShop/Backups). For tests.
FOUNDATION_EXPORT NSString *TSLibraryBackupFolder(void);

NS_ASSUME_NONNULL_END
