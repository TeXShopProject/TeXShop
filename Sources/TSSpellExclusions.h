/*
 * TeXShop - TeX editor for Mac OS
 *
 * Which parts of a TeX source file the spell checker must ignore is not built
 * into TeXShop; it is read from ~/Library/TeXShop/SpellCheck/SpellingExclusions.txt
 * (a default copy lives in the application bundle). See that file for the
 * directives it understands.
 *
 * This file is part of the TeX-aware spell checking added to TeXShop. It is
 * distributed under the same GNU General Public License as TeXShop.
 */

#import <Foundation/Foundation.h>

/*" A stretch of the masked text, in one language. `language` is the code
    written in the rules file (for example "de" or "pt_BR"), or nil for the text
    that is in the document's own language. "*/
@interface TSSpellLanguageSegment : NSObject
@property (nonatomic, readonly) NSRange range;      // in the masked text
@property (nonatomic, readonly, copy) NSString *language;
@end

/*" The result of masking a TeX source text. "*/
@interface TSSpellMask : NSObject

/*" The text to hand to the spell checker: the original text with every
    excluded character replaced by a space (newlines are kept), and with
    accent commands such as \"u replaced by the letter they stand for. "*/
@property (nonatomic, readonly) NSString *masked;

/*" The index in the original text that character i of `masked` came from. "*/
- (NSUInteger)originalIndexForMaskedIndex:(NSUInteger)i;

/*" The smallest masked index whose original index is >= `index` (the length
    of `masked` if there is none). "*/
- (NSUInteger)maskedIndexForOriginalIndex:(NSUInteger)index;

/*" The range in the original text covered by a range of `masked`. "*/
- (NSRange)originalRangeForMaskedRange:(NSRange)range;

/*" YES if any character of `range` (original text) is excluded from spell
    checking. "*/
- (BOOL)rangeTouchesExclusion:(NSRange)range;

/*" YES if `range` (original text) touches, or is right next to, an accent
    command such as \"u, \'e or \ss. The system sees a word like M\"unchen as
    the two fragments "M" and "unchen", so a fragment next to an accent command
    is not a reliable misspelling. "*/
- (BOOL)rangeIsNextToAccent:(NSRange)range;

/*" YES if some of the text was marked as being in another language (by
    \foreignlanguage, \selectlanguage, an otherlanguage environment, ...). "*/
@property (nonatomic, readonly) BOOL hasLanguages;

/*" The language code (as written in the rules file) of the character at `index`
    in the original text, or nil if it is in the document's own language. "*/
- (NSString *)languageForOriginalIndex:(NSUInteger)index;

/*" Consecutive stretches that cover the whole masked text, each with its
    language code (nil for the document's own language). nil if the text has no
    other language in it. "*/
- (NSArray<TSSpellLanguageSegment *> *)languageSegments;

/*" Length of the original text this mask was made from. "*/
@property (nonatomic, readonly) NSUInteger originalLength;

@end


@interface TSSpellExclusions : NSObject

/*" The shared instance, reading the user's rules file. The file is read again
    whenever it has changed on disk. "*/
+ (TSSpellExclusions *)sharedExclusions;

/*" Path of the user's rules file. "*/
+ (NSString *)userRulesPath;

/*" Path of the default rules file inside the application bundle, or nil. "*/
+ (NSString *)bundledRulesPath;

/*" Create ~/Library/TeXShop/SpellCheck and copy the bundled default rules file
    there if the user has none. "*/
+ (void)installDefaultRulesIfNeeded;

- (instancetype)initWithRulesFile:(NSString *)path;
- (instancetype)initWithRulesText:(NSString *)text;

/*" Re-read the rules file if it changed. Returns YES if it was re-read. "*/
- (BOOL)reloadIfChanged;

/*" Problems found while reading the rules (unknown directives, bad regular
    expressions), one per line; nil if there were none. "*/
@property (nonatomic, readonly) NSString *problems;

/*" Mask `text` according to the rules. "*/
- (TSSpellMask *)maskForText:(NSString *)text;

/*" Command names from `skip-args` and `skip-args-matching` rules without a
    regular expression, and the `check-args` exceptions. TeXShop's syntax
    colouring uses these for its parameter highlighting. "*/
- (NSArray<NSString *> *)commandsWithExcludedArguments;
- (NSArray<NSString *> *)commandsWithCheckedArguments;

@end
