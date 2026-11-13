// SPDX-License-Identifier: GPL-2.0-or-later
// The roles of syntax coloring, shared by every grammar: the source and the Experiment source (TeX and XML),
// the macro editor (TeX or AppleScript with placeholders) and the find and replace fields (regular expressions
// and replacement templates). A scanner gives each token a role; a color scheme turns a role into the
// attributes that are shown.
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, TSSyntaxRole) {
    /// No color: a range that only carries flags, such as text left out of spell checking.
    TSSyntaxRoleNone = -1,
    // TeX
    TSSyntaxRoleCommand = 0,
    TSSyntaxRoleComment,
    TSSyntaxRoleMarker,                 // $ &
    TSSyntaxRoleBracketParen,
    TSSyntaxRoleBracketCurly,
    TSSyntaxRoleBracketSquare,
    TSSyntaxRoleIndex,                  // the argument of \index
    TSSyntaxRoleFootnote,               // the argument of \footnote and \cite
    TSSyntaxRoleFullwidthSymbol,        // fullwidth letters, digits and symbols, easily mistaken for ASCII
    TSSyntaxRoleExplVariable,           // \l_name, \g_name, \c_name
    TSSyntaxRoleExplFunction,           // \module_name:args
    TSSyntaxRoleExplIntenseVariable,    // \l__name
    TSSyntaxRoleExplIntenseFunction,    // \__module_name:args
    TSSyntaxRoleExplMessage,            // \msg_...
    TSSyntaxRoleExplKey,                // the key before .tl_set:N and the like
    TSSyntaxRoleExplKeyArgument,        // .tl_set:N
    // XML
    TSSyntaxRoleXMLComment,
    TSSyntaxRoleXMLTag,
    TSSyntaxRoleXMLSpecial,             // the name of an entity
    TSSyntaxRoleXMLParameter,
    TSSyntaxRoleXMLValue,
    // AppleScript and macros
    TSSyntaxRoleString,
    TSSyntaxRoleKeyword,
    TSSyntaxRoleNumber,
    TSSyntaxRoleRawEvent,               // «event ...»
    TSSyntaxRolePlaceholder,            // #SEL#, #FILEPATH# and the like
    TSSyntaxRoleMark,                   // • and •‹...›
    // Regular expressions and replacement templates
    TSSyntaxRoleRegexCharacterClass,    // [a-z] \d \w \p{L} .
    TSSyntaxRoleRegexBackreference,     // \1 \k<name> in a pattern; $1 \1 \g<name> in a replacement
    TSSyntaxRoleRegexQuantifier,        // * + ? {2,3} and their lazy or possessive forms
    TSSyntaxRoleRegexAnchor,            // ^ $ \b \A \z
    TSSyntaxRoleRegexSymbol,            // ( (?: (?<name> ) |
    TSSyntaxRoleRegexEscape,            // \t \n \x{41} \.
    TSSyntaxRoleRegexIncompatible,      // valid, but read differently by Onigmo (OgreKit)
    TSSyntaxRoleInvalid,
} NS_SWIFT_NAME(SyntaxRole);

NS_ASSUME_NONNULL_END
