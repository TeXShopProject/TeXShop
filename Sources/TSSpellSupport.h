/*
 * TeXShop - TeX editor for Mac OS
 * Copyright (C) 2026 Ralph Martin and Yusuke Terada
 * SPDX-License-Identifier: GPL-2.0-or-later
 * TeX-aware spelling implementation by Ralph Martin.
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
+ (void)preferencesDidChange;
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

/*" YES if the check while typing is not to mark a misspelling at `range`: the
    range touches text that `mask` excludes, is next to an accent command, or is
    in another language than the document's. "*/
+ (BOOL)mask:(TSSpellMask *)mask excludesSpellingInRange:(NSRange)range;
+ (NSString *)helpPathInDirectory:(NSString *)directory forLanguages:(NSArray<NSString *> *)languages;

/*" The words in `text` that have been learned (Learn in the Spelling panel) for
    the spell checker's current language, sorted. macOS has no call that lists all
    learned words, so the words of the text are checked one by one with
    -hasLearnedWord:. "*/
+ (NSArray<NSString *> *)learnedWordsInText:(NSString *)text;

/*" The same, without waiting: the words of `text` (of its masked form if
    `masked`) are found off the main thread and looked up with -hasLearnedWord:
    a batch at a time on the main thread, which goes on handling events in
    between. `completion` is called on the main thread. "*/
+ (void)findLearnedWordsInText:(NSString *)text masked:(BOOL)masked completion:(void (^)(NSArray<NSString *> *words))completion;

/*" The sheet behind Forget Learned Words…: lists the learned words that occur in
    the given document text (in its masked form if `masked`, which is what the
    TeX-aware spell checking checks) and forgets the ones the user selects. The
    sheet appears once the words have been looked up. "*/
+ (void)forgetLearnedWordsFoundInText:(NSString *)text;
+ (void)forgetLearnedWordsFoundInText:(NSString *)text masked:(BOOL)masked;

/*" Make the spell checker forget these words for its current language. Returns
    how many had been learned. "*/
+ (NSUInteger)forgetWords:(NSArray<NSString *> *)words;

/*" Add "Forget Learned Words…" and "Edit Spelling Exclusions…" next to Check
    Spelling in the Edit > Spelling and Grammar menu, and "Spell Checking Help"
    to the Help menu (after "TeXShop Help"/"Getting Started", found by its
    action). "*/
+ (void)installMenuItems;

@end


/*" The mask of the text in one text storage, shared by all the text views that
    show it (the panes of a split window), and made again only after the text or
    the rules have changed. "*/
@interface TSSpellMaskCache : NSObject

/*" The cache of `storage`, made on first use; nil if `storage` is nil. "*/
+ (TSSpellMaskCache *)cacheForTextStorage:(NSTextStorage *)storage;

/*" A text at least this long (default 200000 characters) is not masked again
    after each change: once editing has paused for `pauseDelay` seconds (default
    0.5), it is masked off the main thread. "*/
@property (class, nonatomic) NSUInteger deferredLength;
@property (class, nonatomic) NSTimeInterval pauseDelay;

/*" The mask of the text as it is now, for the check while typing; made now if
    needed. For a text of at least deferredLength characters that has changed
    since its mask was made, nil instead: the check then works as it does
    without TeX-aware spelling until the new mask is there, and `range` (where
    the check is about to mark a misspelling) has its mark removed at that point
    if the new mask excludes it. A location of NSNotFound records nothing. "*/
- (TSSpellMask *)maskForCheckingRange:(NSRange)range;

/*" A mask made now from the text as it is, which is kept as the current one. "*/
- (TSSpellMask *)freshMask;

/*" Forget the mask. "*/
- (void)invalidate;

@end
