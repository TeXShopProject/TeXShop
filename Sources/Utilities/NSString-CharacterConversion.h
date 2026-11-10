/*
 * TeXShop - TeX editor for Mac OS
 * Copyright (C) 2000-2005 Richard Koch
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
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin St, Fifth Floor, Boston, MA  02110-1301  USA
 *
 */

#import <Foundation/Foundation.h>

// Conversions behind Edit > Character Type Conversion. They are aimed at
// Japanese LaTeX sources (pLaTeX/upLaTeX with the ajmacros package).
@interface NSString (TSCharacterConversion)

// JIS X 0208 外の文字 ⇄ \UTF / \CID
-(NSString*)stringByReplacingUnicodeCharactersWithUTF;
-(NSString*)stringByReplacingUTFWithUnicodeCharacters;

// あ ⇄ ア
-(NSString*)stringByReplacingHiraganaWithKatakana;
-(NSString*)stringByReplacingKatakanaWithHiragana;

// １ ⇄ 1
-(NSString*)stringByReplacingHalfwidthDigitsWithFullwidthDigits;
-(NSString*)stringByReplacingFullwidthDigitsWithHalfwidthDigits;

// Ａ ⇄ A, ａ ⇄ a
-(NSString*)stringByReplacingHalfwidthAlphabetsWithFullwidthAlphabets;
-(NSString*)stringByReplacingFullwidthAlphabetsWithHalfwidthAlphabets;

// Unicode文字 ⇄ ajmacros
-(NSString*)stringByReplacingUnicodeCharactersWithAjMacros;
-(NSString*)stringByReplacingAjMacrosWithUnicodeCharacters;

// ① ⇄ \ajMaru // 0..50
-(NSString*)stringByReplacingMaruSujiWithAjMaru;
-(NSString*)stringByReplacingAjMaruWithMaruSuji;

// ❶ ⇄ \ajKuroMaru // 0..20
-(NSString*)stringByReplacingKuroMaruSujiWithAjKuroMaru;
-(NSString*)stringByReplacingAjKuroMaruWithKuroMaruSuji;

// ⑴ ⇄ \ajKakko // 1..20
-(NSString*)stringByReplacingKakkoSujiWithAjKakko;
-(NSString*)stringByReplacingAjKakkoWithKakkoSuji;

// Ⓐ ⇄ \ajMaruAlph, ⓐ ⇄ \ajMarualph // 1..26
-(NSString*)stringByReplacingMaruAlphWithAjMaruAlph;
-(NSString*)stringByReplacingAjMaruAlphWithMaruAlph;

// 🄐 ⇄ \ajKakkoAlph, ⒜ ⇄ \ajKakkoalph // 1..26
-(NSString*)stringByReplacingKakkoAlphWithAjKakkoAlph;
-(NSString*)stringByReplacingAjKakkoAlphWithKakkoAlph;

// 🅐 ⇄ \ajKuroMaruAlph // 1..26
-(NSString*)stringByReplacingKuroMaruAlphWithAjKuroMaruAlph;
-(NSString*)stringByReplacingAjKuroMaruAlphWithKuroMaruAlph;

// 🄰 ⇄ \ajKakuAlph // 1..26
-(NSString*)stringByReplacingKakuAlphWithAjKakuAlph;
-(NSString*)stringByReplacingAjKakuAlphWithKakuAlph;

// 🅰 ⇄ \ajKuroKakuAlph // 1..26
-(NSString*)stringByReplacingKuroKakuAlphWithAjKuroKakuAlph;
-(NSString*)stringByReplacingAjKuroKakuAlphWithKuroKakuAlph;

// Ⅰ ⇄ \ajRoman, ⅰ ⇄ \ajroman // 1..12
-(NSString*)stringByReplacingRomanWithAjRoman;
-(NSString*)stringByReplacingAjRomanWithRoman;

// ⒈ ⇄ \ajPeriod // 1..9
-(NSString*)stringByReplacingPeriodWithAjPeriod;
-(NSString*)stringByReplacingAjPeriodWithPeriod;

// ㈪ ⇄ \ajKakkoYobi // 1..9
-(NSString*)stringByReplacingKakkoYobiWithAjKakkoYobi;
-(NSString*)stringByReplacingAjKakkoYobiWithKakkoYobi;

// ㊊ ⇄ \ajMaruYobi // 1..9
-(NSString*)stringByReplacingMaruYobiWithAjMaruYobi;
-(NSString*)stringByReplacingAjMaruYobiWithMaruYobi;

// ⓵ ⇄ \ajNijuMaru // 1..10
-(NSString*)stringByReplacingNijuMaruWithAjNijuMaru;
-(NSString*)stringByReplacingAjNijuMaruWithNijuMaru;

// ♳ ⇄ \ajRecycle // 0..11
-(NSString*)stringByReplacingRecycleWithAjRecycle;
-(NSString*)stringByReplacingAjRecycleWithRecycle;

// ㋐ ⇄ \ajMaruKata // 1..47
-(NSString*)stringByReplacingMaruKataWithAjMaruKata;
-(NSString*)stringByReplacingAjMaruKataWithMaruKata;

// ㈠ ⇄ \ajKakkoKansuji // 1..10
-(NSString*)stringByReplacingKakkoKansujiWithAjKakkoKansuji;
-(NSString*)stringByReplacingAjKakkoKansujiWithKakkoKansuji;

// ㊀ ⇄ \ajMaruKansuji // 1..10
-(NSString*)stringByReplacingMaruKansujiWithAjMaruKansuji;
-(NSString*)stringByReplacingAjMaruKansujiWithMaruKansuji;

// ㍿ ⇄ \ajLig{株式会社}
-(NSString*)stringByReplacingLigWithAjLig;
-(NSString*)stringByReplacingAjLigWithLig;

// Reading a file: \UTF{xxxx}, \UTFK, \UTFT and \UTFC (utf.sty) → Unicode文字.
// U+FF5E and U+FF0D become U+301C and U+2212, which Japanese encodings can save.
-(NSString*)stringByDecodingUTFCommandsForReading;

// 全角引用符 → 半角引用符
-(NSString*)stringByReplacingFullwidthQuotesWithHalfwidthQuotes;

@end
