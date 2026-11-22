// Earlier versions of TeXShop bundled macros that open Richard Koch's former web site, and
// macros since reworded (TeX Live written with the space, the ConTeXt macro for the teTeX page
// that now opens the TeX Live home page). When TeXShop is updated, a macro in
// ~/Library/TeXShop/Macros whose content is still exactly one of those bundled texts takes the
// current bundled text, and the current name when it was renamed. Macros that were edited or
// renamed, and every other macro, stay as they are.
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// The bundled macros give the current texts; their earlier texts differ in the address of the
// web site or in the reworded lines. Returns the number of macros updated in the file at
// userPath. The file is written only when a macro changed; a symbolic link stays a link.
NSUInteger TSUpdateUnchangedBundledMacros(NSString *userPath, NSString *bundledPath);

NS_ASSUME_NONNULL_END
