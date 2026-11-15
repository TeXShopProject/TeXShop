// SPDX-License-Identifier: GPL-2.0-or-later
/*
 * TSStatusBarCounting.h
 *
 * The numbers of the status bar under the source: lines, characters and words of the
 * whole text and of the selection, and where the insertion point is.
 *
 * A character is what the reader sees as one character (a grapheme cluster): a letter
 * with combining marks, an emoji joined with ZWJ, a character with a variation selector
 * and CR LF each count as one. Words are those of the system's word boundaries for the
 * current language, as the Cocoa text system sees them (and CotEditor counts them), with two
 * differences: a "word" of variation selectors, combining marks or other invisible characters
 * alone (the selector of 葛󠄀) belongs to the word before it and is not counted, and an emoji
 * outside the words (😀, 🇯🇵, ❤️, a ZWJ sequence) is a word of its own. TeX commands are
 * counted as they are written. Lines end with LF, CR, CR LF, NEL, LINE SEPARATOR or PARAGRAPH SEPARATOR;
 * an empty last line is not counted. The location and the column count characters from
 * the start of the text and of the line, from 0; the line counts from 1.
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Returns YES when the count should stop because a newer one is wanted. Called now and then from the loops.
typedef BOOL (^TSStatusBarCancel)(void);

/// The number of characters in `range` of `string`. A cluster that starts before the range counts once, from where the range starts.
NSUInteger TSStatusBarCharacterCount(NSString *string, NSRange range, TSStatusBarCancel _Nullable cancel);
/// The number of words in `range` of `string`.
NSUInteger TSStatusBarWordCount(NSString *string, NSRange range, TSStatusBarCancel _Nullable cancel);
/// The number of lines of the whole text, without an empty last line: 0 for an empty text.
NSUInteger TSStatusBarLineCount(NSString *string, TSStatusBarCancel _Nullable cancel);
/// The line (from 1) of the UTF-16 location `location`. A location between CR and LF belongs to the line of the CR.
NSUInteger TSStatusBarLineNumber(NSString *string, NSUInteger location);
/// The number of lines that hold characters of the non-empty ranges, each line counted once.
NSUInteger TSStatusBarSelectedLineCount(NSString *string, NSArray<NSValue *> *ranges);
/// The column (from 0) of the UTF-16 location `location`: the characters between the start of its line and it.
NSUInteger TSStatusBarColumn(NSString *string, NSUInteger location);

/// All the numbers of the status bar. NSNotFound stands for a number not counted yet.
typedef struct {
    NSUInteger lines, characters, words;
    NSUInteger selectedLines, selectedCharacters, selectedWords;
    NSUInteger location, line, column;
} TSStatusBarCounts;

/// Counts with nothing counted yet.
TSStatusBarCounts TSStatusBarCountsUnknown(void);
/// Fills in the numbers of the whole text (`content`) and of the selection (`selection`). `ranges` are the selected
/// ranges of a text view, the first one holding the insertion point. Returns NO when `cancel` stopped it.
BOOL TSStatusBarCount(NSString *string, NSArray<NSValue *> *ranges, BOOL content, BOOL selection,
                      TSStatusBarCounts *counts, TSStatusBarCancel _Nullable cancel);

NS_ASSUME_NONNULL_END
