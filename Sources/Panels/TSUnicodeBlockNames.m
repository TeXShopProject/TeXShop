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

#import "TSUnicodeBlockNames.h"
#import <unicode/uchar.h>

// The names of Blocks.txt of the Unicode Character Database (Unicode 17.0), the English names of the blocks,
// written by Scripts/update-unicode-block-names.py. ICU names a block by its property value alias
// ("Latin_1_Supplement"), which matches one of these when spaces, hyphens, underscores and case are ignored.
static NSArray<NSString *> *BlockNames(void)
{
    return @[
    // BEGIN block names
    @"Adlam",
    @"Aegean Numbers",
    @"Ahom",
    @"Alchemical Symbols",
    @"Alphabetic Presentation Forms",
    @"Anatolian Hieroglyphs",
    @"Ancient Greek Musical Notation",
    @"Ancient Greek Numbers",
    @"Ancient Symbols",
    @"Arabic",
    @"Arabic Extended-A",
    @"Arabic Extended-B",
    @"Arabic Extended-C",
    @"Arabic Mathematical Alphabetic Symbols",
    @"Arabic Presentation Forms-A",
    @"Arabic Presentation Forms-B",
    @"Arabic Supplement",
    @"Armenian",
    @"Arrows",
    @"Avestan",
    @"Balinese",
    @"Bamum",
    @"Bamum Supplement",
    @"Basic Latin",
    @"Bassa Vah",
    @"Batak",
    @"Bengali",
    @"Beria Erfe",
    @"Bhaiksuki",
    @"Block Elements",
    @"Bopomofo",
    @"Bopomofo Extended",
    @"Box Drawing",
    @"Brahmi",
    @"Braille Patterns",
    @"Buginese",
    @"Buhid",
    @"Byzantine Musical Symbols",
    @"Carian",
    @"Caucasian Albanian",
    @"Chakma",
    @"Cham",
    @"Cherokee",
    @"Cherokee Supplement",
    @"Chess Symbols",
    @"Chorasmian",
    @"CJK Compatibility",
    @"CJK Compatibility Forms",
    @"CJK Compatibility Ideographs",
    @"CJK Compatibility Ideographs Supplement",
    @"CJK Radicals Supplement",
    @"CJK Strokes",
    @"CJK Symbols and Punctuation",
    @"CJK Unified Ideographs",
    @"CJK Unified Ideographs Extension A",
    @"CJK Unified Ideographs Extension B",
    @"CJK Unified Ideographs Extension C",
    @"CJK Unified Ideographs Extension D",
    @"CJK Unified Ideographs Extension E",
    @"CJK Unified Ideographs Extension F",
    @"CJK Unified Ideographs Extension G",
    @"CJK Unified Ideographs Extension H",
    @"CJK Unified Ideographs Extension I",
    @"CJK Unified Ideographs Extension J",
    @"Combining Diacritical Marks",
    @"Combining Diacritical Marks Extended",
    @"Combining Diacritical Marks for Symbols",
    @"Combining Diacritical Marks Supplement",
    @"Combining Half Marks",
    @"Common Indic Number Forms",
    @"Control Pictures",
    @"Coptic",
    @"Coptic Epact Numbers",
    @"Counting Rod Numerals",
    @"Cuneiform",
    @"Cuneiform Numbers and Punctuation",
    @"Currency Symbols",
    @"Cypriot Syllabary",
    @"Cypro-Minoan",
    @"Cyrillic",
    @"Cyrillic Extended-A",
    @"Cyrillic Extended-B",
    @"Cyrillic Extended-C",
    @"Cyrillic Extended-D",
    @"Cyrillic Supplement",
    @"Deseret",
    @"Devanagari",
    @"Devanagari Extended",
    @"Devanagari Extended-A",
    @"Dingbats",
    @"Dives Akuru",
    @"Dogra",
    @"Domino Tiles",
    @"Duployan",
    @"Early Dynastic Cuneiform",
    @"Egyptian Hieroglyph Format Controls",
    @"Egyptian Hieroglyphs",
    @"Egyptian Hieroglyphs Extended-A",
    @"Elbasan",
    @"Elymaic",
    @"Emoticons",
    @"Enclosed Alphanumeric Supplement",
    @"Enclosed Alphanumerics",
    @"Enclosed CJK Letters and Months",
    @"Enclosed Ideographic Supplement",
    @"Ethiopic",
    @"Ethiopic Extended",
    @"Ethiopic Extended-A",
    @"Ethiopic Extended-B",
    @"Ethiopic Supplement",
    @"Garay",
    @"General Punctuation",
    @"Geometric Shapes",
    @"Geometric Shapes Extended",
    @"Georgian",
    @"Georgian Extended",
    @"Georgian Supplement",
    @"Glagolitic",
    @"Glagolitic Supplement",
    @"Gothic",
    @"Grantha",
    @"Greek and Coptic",
    @"Greek Extended",
    @"Gujarati",
    @"Gunjala Gondi",
    @"Gurmukhi",
    @"Gurung Khema",
    @"Halfwidth and Fullwidth Forms",
    @"Hangul Compatibility Jamo",
    @"Hangul Jamo",
    @"Hangul Jamo Extended-A",
    @"Hangul Jamo Extended-B",
    @"Hangul Syllables",
    @"Hanifi Rohingya",
    @"Hanunoo",
    @"Hatran",
    @"Hebrew",
    @"High Private Use Surrogates",
    @"High Surrogates",
    @"Hiragana",
    @"Ideographic Description Characters",
    @"Ideographic Symbols and Punctuation",
    @"Imperial Aramaic",
    @"Indic Siyaq Numbers",
    @"Inscriptional Pahlavi",
    @"Inscriptional Parthian",
    @"IPA Extensions",
    @"Javanese",
    @"Kaithi",
    @"Kaktovik Numerals",
    @"Kana Extended-A",
    @"Kana Extended-B",
    @"Kana Supplement",
    @"Kanbun",
    @"Kangxi Radicals",
    @"Kannada",
    @"Katakana",
    @"Katakana Phonetic Extensions",
    @"Kawi",
    @"Kayah Li",
    @"Kharoshthi",
    @"Khitan Small Script",
    @"Khmer",
    @"Khmer Symbols",
    @"Khojki",
    @"Khudawadi",
    @"Kirat Rai",
    @"Lao",
    @"Latin Extended Additional",
    @"Latin Extended-A",
    @"Latin Extended-B",
    @"Latin Extended-C",
    @"Latin Extended-D",
    @"Latin Extended-E",
    @"Latin Extended-F",
    @"Latin Extended-G",
    @"Latin-1 Supplement",
    @"Lepcha",
    @"Letterlike Symbols",
    @"Limbu",
    @"Linear A",
    @"Linear B Ideograms",
    @"Linear B Syllabary",
    @"Lisu",
    @"Lisu Supplement",
    @"Low Surrogates",
    @"Lycian",
    @"Lydian",
    @"Mahajani",
    @"Mahjong Tiles",
    @"Makasar",
    @"Malayalam",
    @"Mandaic",
    @"Manichaean",
    @"Marchen",
    @"Masaram Gondi",
    @"Mathematical Alphanumeric Symbols",
    @"Mathematical Operators",
    @"Mayan Numerals",
    @"Medefaidrin",
    @"Meetei Mayek",
    @"Meetei Mayek Extensions",
    @"Mende Kikakui",
    @"Meroitic Cursive",
    @"Meroitic Hieroglyphs",
    @"Miao",
    @"Miscellaneous Mathematical Symbols-A",
    @"Miscellaneous Mathematical Symbols-B",
    @"Miscellaneous Symbols",
    @"Miscellaneous Symbols and Arrows",
    @"Miscellaneous Symbols and Pictographs",
    @"Miscellaneous Symbols Supplement",
    @"Miscellaneous Technical",
    @"Modi",
    @"Modifier Tone Letters",
    @"Mongolian",
    @"Mongolian Supplement",
    @"Mro",
    @"Multani",
    @"Musical Symbols",
    @"Myanmar",
    @"Myanmar Extended-A",
    @"Myanmar Extended-B",
    @"Myanmar Extended-C",
    @"Nabataean",
    @"Nag Mundari",
    @"Nandinagari",
    @"New Tai Lue",
    @"Newa",
    @"NKo",
    @"Number Forms",
    @"Nushu",
    @"Nyiakeng Puachue Hmong",
    @"Ogham",
    @"Ol Chiki",
    @"Ol Onal",
    @"Old Hungarian",
    @"Old Italic",
    @"Old North Arabian",
    @"Old Permic",
    @"Old Persian",
    @"Old Sogdian",
    @"Old South Arabian",
    @"Old Turkic",
    @"Old Uyghur",
    @"Optical Character Recognition",
    @"Oriya",
    @"Ornamental Dingbats",
    @"Osage",
    @"Osmanya",
    @"Ottoman Siyaq Numbers",
    @"Pahawh Hmong",
    @"Palmyrene",
    @"Pau Cin Hau",
    @"Phags-pa",
    @"Phaistos Disc",
    @"Phoenician",
    @"Phonetic Extensions",
    @"Phonetic Extensions Supplement",
    @"Playing Cards",
    @"Private Use Area",
    @"Psalter Pahlavi",
    @"Rejang",
    @"Rumi Numeral Symbols",
    @"Runic",
    @"Samaritan",
    @"Saurashtra",
    @"Sharada",
    @"Sharada Supplement",
    @"Shavian",
    @"Shorthand Format Controls",
    @"Siddham",
    @"Sidetic",
    @"Sinhala",
    @"Sinhala Archaic Numbers",
    @"Small Form Variants",
    @"Small Kana Extension",
    @"Sogdian",
    @"Sora Sompeng",
    @"Soyombo",
    @"Spacing Modifier Letters",
    @"Specials",
    @"Sundanese",
    @"Sundanese Supplement",
    @"Sunuwar",
    @"Superscripts and Subscripts",
    @"Supplemental Arrows-A",
    @"Supplemental Arrows-B",
    @"Supplemental Arrows-C",
    @"Supplemental Mathematical Operators",
    @"Supplemental Punctuation",
    @"Supplemental Symbols and Pictographs",
    @"Supplementary Private Use Area-A",
    @"Supplementary Private Use Area-B",
    @"Sutton SignWriting",
    @"Syloti Nagri",
    @"Symbols and Pictographs Extended-A",
    @"Symbols for Legacy Computing",
    @"Symbols for Legacy Computing Supplement",
    @"Syriac",
    @"Syriac Supplement",
    @"Tagalog",
    @"Tagbanwa",
    @"Tags",
    @"Tai Le",
    @"Tai Tham",
    @"Tai Viet",
    @"Tai Xuan Jing Symbols",
    @"Tai Yo",
    @"Takri",
    @"Tamil",
    @"Tamil Supplement",
    @"Tangsa",
    @"Tangut",
    @"Tangut Components",
    @"Tangut Components Supplement",
    @"Tangut Supplement",
    @"Telugu",
    @"Thaana",
    @"Thai",
    @"Tibetan",
    @"Tifinagh",
    @"Tirhuta",
    @"Todhri",
    @"Tolong Siki",
    @"Toto",
    @"Transport and Map Symbols",
    @"Tulu-Tigalari",
    @"Ugaritic",
    @"Unified Canadian Aboriginal Syllabics",
    @"Unified Canadian Aboriginal Syllabics Extended",
    @"Unified Canadian Aboriginal Syllabics Extended-A",
    @"Vai",
    @"Variation Selectors",
    @"Variation Selectors Supplement",
    @"Vedic Extensions",
    @"Vertical Forms",
    @"Vithkuqi",
    @"Wancho",
    @"Warang Citi",
    @"Yezidi",
    @"Yi Radicals",
    @"Yi Syllables",
    @"Yijing Hexagram Symbols",
    @"Zanabazar Square",
    @"Znamenny Musical Notation",
    // END block names
    ];
}

static NSString *const TSCharacterViewerBlockTable = @"/System/Library/Input Methods/CharacterPalette.app/Contents/Resources/UnicodeBlocks_Title.loctable";

static NSString *LooseName(NSString *name)
{
    NSMutableString *loose = [NSMutableString string];
    [name enumerateSubstringsInRange:NSMakeRange(0, name.length) options:NSStringEnumerationByComposedCharacterSequences
                          usingBlock:^(NSString *part, NSRange range, NSRange enclosing, BOOL *stop) {
        if (![part isEqualToString:@" "] && ![part isEqualToString:@"_"] && ![part isEqualToString:@"-"])
            [loose appendString:part.lowercaseString];
    }];
    return loose;
}

NSString *TSUnicodeBlockName(UInt32 codePoint)
{
    static NSDictionary<NSString *, NSString *> *names;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSMutableDictionary *byLooseName = [NSMutableDictionary dictionary];
        for (NSString *name in BlockNames())
            byLooseName[LooseName(name)] = name;
        names = byLooseName;
    });
    if (codePoint > 0x10FFFF)
        return nil;
    UBlockCode block = ublock_getCode((UChar32)codePoint);
    if (block == UBLOCK_NO_BLOCK || block == UBLOCK_INVALID_CODE)
        return nil;
    const char *alias = u_getPropertyValueName(UCHAR_BLOCK, block, U_LONG_PROPERTY_NAME);
    if (alias == NULL)
        return nil;
    NSString *icuName = @(alias);
    // A block newer than the list keeps ICU's name, with spaces.
    return names[LooseName(icuName)] ?: [icuName stringByReplacingOccurrencesOfString:@"_" withString:@" "];
}

// The key of the Character Viewer's table for a block: its name with the abbreviations of the table spelled out
// ("CJK Unified Ideographs Ext. J", "Arabic Math Alphabetic Symbols", "CJK Compatibility Ideographs Supp.",
// "Ideographic Desc. Characters"), and only letters and digits, in lower case ("N'Ko" is "nko").
NSString *TSUnicodeBlockKey(NSString *name)
{
    NSString *spelled = name.lowercaseString;
    for (NSArray<NSString *> *pair in @[@[@"\\bext\\.", @"extension"], @[@"\\bsupp\\.", @"supplement"], @[@"\\bdesc\\.", @"description"], @[@"\\bmath\\b", @"mathematical"]])
        spelled = [spelled stringByReplacingOccurrencesOfString:pair[0] withString:pair[1] options:NSRegularExpressionSearch range:NSMakeRange(0, spelled.length)];
    NSMutableString *key = [NSMutableString string];
    for (NSUInteger i = 0; i < spelled.length; i++) {
        unichar c = [spelled characterAtIndex:i];
        if ((c >= 'a' && c <= 'z') || (c >= '0' && c <= '9'))
            [key appendFormat:@"%C", c];
    }
    return key;
}

// The language of the Character Viewer's table for a language of the interface: pt is Brazilian Portuguese.
static NSString *TableLanguage(NSString *language)
{
    NSDictionary<NSString *, NSString *> *languages = @{@"Base": @"en", @"en": @"en", @"pt": @"pt_BR", @"pt-BR": @"pt_BR", @"pt_BR": @"pt_BR",
                                                       @"pt-PT": @"pt_PT", @"pt_PT": @"pt_PT", @"zh_CN": @"zh_CN", @"zh-Hans": @"zh_CN", @"zh-CN": @"zh_CN"};
    return languages[language] ?: [language stringByReplacingOccurrencesOfString:@"-" withString:@"_"];
}

NSDictionary<NSString *, NSString *> *TSUnicodeBlockTranslations(NSString *path, NSString *language)
{
    NSData *data = [NSData dataWithContentsOfFile:path options:NSDataReadingMappedIfSafe error:NULL];
    id table = data ? [NSPropertyListSerialization propertyListWithData:data options:NSPropertyListImmutable format:NULL error:NULL] : nil;
    if (![table isKindOfClass:NSDictionary.class])
        return @{};
    id names = ((NSDictionary *)table)[TableLanguage(language)];
    if (![names isKindOfClass:NSDictionary.class])
        return @{};
    NSMutableDictionary<NSString *, NSString *> *translations = [NSMutableDictionary dictionary];
    [(NSDictionary *)names enumerateKeysAndObjectsUsingBlock:^(id key, id value, BOOL *stop) {
        if ([key isKindOfClass:NSString.class] && [value isKindOfClass:NSString.class] && [value length])
            translations[TSUnicodeBlockKey(key)] = value;
    }];
    return translations;
}

static NSDictionary<NSString *, NSString *> *CachedTranslations;
static NSString *TablePath, *TableLanguageOverride;

void TSUseUnicodeBlockTable(NSString *path, NSString *language)
{
    TablePath = [path copy];
    TableLanguageOverride = [language copy];
    CachedTranslations = nil;
}

NSString *TSLocalizedUnicodeBlockName(NSString *blockName)
{
    // Read once, in the language TeXShop shows its interface in.
    if (!CachedTranslations)
        CachedTranslations = TSUnicodeBlockTranslations(TablePath ?: TSCharacterViewerBlockTable,
                                                        TableLanguageOverride ?: NSBundle.mainBundle.preferredLocalizations.firstObject ?: @"en");
    return CachedTranslations[TSUnicodeBlockKey(blockName)] ?: blockName;
}
