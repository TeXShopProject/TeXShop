// SPDX-License-Identifier: GPL-2.0-or-later
// The XML part of the TeX scanner, for PreTeXt and other XML sources: tags with their attributes, entities, and
// comments. Moved from TSDocument (XML) with the same rules.
#import "TSSyntaxScanner.h"

NS_ASSUME_NONNULL_BEGIN

/// A tag at *location (a <): its name, and the names and values of its attributes up to the > on the same line.
/// Leaves *location after what it read.
FOUNDATION_EXPORT void TSSyntaxScanXMLTag(NSString *string, NSUInteger *location, NSUInteger lineEnd, NS_NOESCAPE TSSyntaxTokenBlock block);
/// An entity at *location (an &): the name up to the next ; before lineEnd.
FOUNDATION_EXPORT void TSSyntaxScanXMLEntity(NSString *string, NSUInteger *location, NSUInteger lineEnd, NS_NOESCAPE TSSyntaxTokenBlock block);
/// The comments <!-- --> in range, colored over everything else.
FOUNDATION_EXPORT void TSSyntaxScanXMLComments(NSString *string, NSRange range, NS_NOESCAPE TSSyntaxTokenBlock block);

NS_ASSUME_NONNULL_END
