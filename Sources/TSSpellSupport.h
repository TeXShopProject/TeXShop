/*
 * TeXShop - TeX editor for Mac OS
 *
 * TeX-aware spell checking, working through the standard Spelling and Grammar
 * panel: the panel's Find Next (and Check Document Now, Command-;) finds the
 * next misspelled word in the text that is left once the markup described in
 * SpellingExclusions.txt has been masked out.
 *
 * This file is part of the TeX-aware spell checking added to TeXShop. It is
 * distributed under the same GNU General Public License as TeXShop.
 */

#import <Cocoa/Cocoa.h>

@class TSSpellMask;

@interface TSSpellSupport : NSObject

/*" Find the next misspelled word after the selection in `textView` (wrapping
    round to the top), ignoring everything `mask` excludes. The word is
    selected in the text view, scrolled to the vertical centre, and given to
    the Spelling and Grammar panel, which offers its suggestions, Change,
    Ignore and Learn as usual. Beeps if there is none. Returns the word found
    (as the panel was given it), or nil. "*/
+ (void)changeAll:(id)sender;
+ (NSString *)findNextMisspellingInTextView:(NSTextView *)textView mask:(TSSpellMask *)mask;

/*" Opening the Spelling and Grammar panel (Show Spelling and Grammar, Command-:)
    makes the system run its own search at once, which knows nothing about the
    exclusion rules. This runs `openPanel` (the text view's original
    showGuessPanel:), puts the selection back where it was, and does the
    TeX-aware search instead. "*/
+ (void)showSpellingPanelForTextView:(NSTextView *)textView mask:(TSSpellMask *)mask openPanel:(void (^)(void))openPanel;

/*" Menu actions (the target is the class). "*/
+ (void)forgetLearnedWords:(id)sender;
+ (void)editSpellingExclusions:(id)sender;
+ (void)showSpellCheckingHelp:(id)sender;
+ (NSString *)checkerLanguageForCode:(NSString *)code isDocumentLanguage:(BOOL *)isDocument;
+ (BOOL)rangeIsInOtherLanguage:(NSRange)range mask:(TSSpellMask *)mask;
+ (NSString *)helpPathInDirectory:(NSString *)directory forLanguages:(NSArray<NSString *> *)languages;

/*" The words in `text` that have been learned (Learn in the Spelling panel) for
    the spell checker's current language, sorted. macOS has no call that lists all
    learned words, so the words of the text are checked one by one with
    -hasLearnedWord:. "*/
+ (NSArray<NSString *> *)learnedWordsInText:(NSString *)text;

/*" The sheet behind Forget Learned Words…: lists the learned words that occur in
    the given document text and forgets the ones the user selects. "*/
+ (void)forgetLearnedWordsFoundInText:(NSString *)text;

/*" Make the spell checker forget these words for its current language. Returns
    how many had been learned. "*/
+ (NSUInteger)forgetWords:(NSArray<NSString *> *)words;

/*" Add "Forget Learned Words…" and "Edit Spelling Exclusions…" next to Check
    Spelling in the Edit > Spelling and Grammar menu, and "Spell Checking Help"
    to the Help menu (after "TeXShop Help"/"Getting Started", found by its
    action). "*/
+ (void)installMenuItems;

@end
