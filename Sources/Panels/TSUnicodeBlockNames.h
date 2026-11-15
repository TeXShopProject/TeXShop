/*
 * TeXShop - TeX editor for Mac OS
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// The name in Blocks.txt of the Unicode block of a code point, such as "Latin-1 Supplement",
/// or nil outside every block. The block comes from ICU.
NSString *_Nullable TSUnicodeBlockName(UInt32 codePoint);

/// The name of a block (as TSUnicodeBlockName gives it) in the language of the interface, as the Character Viewer
/// of macOS names it (its table UnicodeBlocks_Title.loctable, read once), or the name itself where the table, the
/// language or the block is missing.
NSString *TSLocalizedUnicodeBlockName(NSString *blockName);

/// The key under which the Character Viewer's table holds a block name: letters and digits in lower case, with its
/// abbreviations spelled out ("CJK Unified Ideographs Ext. J" and "CJK Unified Ideographs Extension J" have one key).
NSString *TSUnicodeBlockKey(NSString *name);

/// The names of a language in a table of the Character Viewer's format ({language: {block name: name}}), by key;
/// empty for a missing or unreadable file or language. pt is pt_BR, pt-PT pt_PT, Base and en English.
NSDictionary<NSString *, NSString *> *TSUnicodeBlockTranslations(NSString *path, NSString *language);

/// For tests: the table and the language to read instead of the Character Viewer's and the interface's (nil for those).
void TSUseUnicodeBlockTable(NSString *_Nullable path, NSString *_Nullable language);

NS_ASSUME_NONNULL_END
