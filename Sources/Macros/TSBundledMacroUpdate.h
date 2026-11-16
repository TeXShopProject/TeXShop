// Earlier versions of TeXShop bundled macros that open Richard Koch's former web site.
// When TeXShop is updated, a macro in ~/Library/TeXShop/Macros whose content is still exactly
// one of those bundled texts takes the current bundled text. Macros that were edited, and
// every other macro, stay as they are.
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// The bundled macros that open https://texshop.app/ give the current texts; their earlier
// texts differ only in the address. Returns the number of macros updated in the file at
// userPath. The file is written only when a macro changed; a symbolic link stays a link.
NSUInteger TSUpdateUnchangedBundledMacros(NSString *userPath, NSString *bundledPath);

NS_ASSUME_NONNULL_END
