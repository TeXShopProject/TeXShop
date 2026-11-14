// SPDX-License-Identifier: GPL-2.0-or-later
// The settings that change how TeX is split into tokens (layer 1). A value: the caller reads the preferences and
// the document's state, and the scanner only reads these.
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

NS_SWIFT_NAME(SyntaxTeXOptions)
@interface TSSyntaxTeXOptions : NSObject <NSCopying, NSMutableCopying>
/// The character that starts a command: a backslash, or a yen sign with Japanese encodings.
@property (nonatomic, readonly) unichar texCharacter;
/// expl3 names (\l_name, \module_name:args, keys) in their own colors; _ and : are letters of commands.
@property (nonatomic, readonly) BOOL colorsExpl3;
/// @ is a letter of commands, as after \makeatletter.
@property (nonatomic, readonly) BOOL makesAtLetter;
/// The arguments of \index and \footnote (and \cite) in their own colors.
@property (nonatomic, readonly) BOOL colorsIndex;
@property (nonatomic, readonly) BOOL colorsFootnote;
/// Fullwidth letters, digits and symbols are tokens.
@property (nonatomic, readonly) BOOL marksFullwidthSymbols;
/// The text is XML, such as PreTeXt: tags, entities and comments.
@property (nonatomic, readonly) BOOL isXML;
/// Commands, comments, or the first arguments of commands are left out of spell checking.
@property (nonatomic, readonly) BOOL excludesCommandsFromSpelling;
@property (nonatomic, readonly) BOOL excludesCommentsFromSpelling;
@property (nonatomic, readonly) BOOL excludesParametersFromSpelling;
/// With excludesParametersFromSpelling: YES leaves out the arguments of every command except those listed in
/// commandsWithCheckedParameters; NO only those listed in commandsWithUncheckedParameters.
@property (nonatomic, readonly) BOOL excludesParametersOfUnlistedCommands;
@property (nonatomic, readonly, copy) NSArray<NSString *> *commandsWithCheckedParameters;
@property (nonatomic, readonly, copy) NSArray<NSString *> *commandsWithUncheckedParameters;
@end

NS_SWIFT_NAME(MutableSyntaxTeXOptions)
@interface TSMutableSyntaxTeXOptions : TSSyntaxTeXOptions
@property (nonatomic, readwrite) unichar texCharacter;
@property (nonatomic, readwrite) BOOL colorsExpl3;
@property (nonatomic, readwrite) BOOL makesAtLetter;
@property (nonatomic, readwrite) BOOL colorsIndex;
@property (nonatomic, readwrite) BOOL colorsFootnote;
@property (nonatomic, readwrite) BOOL marksFullwidthSymbols;
@property (nonatomic, readwrite) BOOL isXML;
@property (nonatomic, readwrite) BOOL excludesCommandsFromSpelling;
@property (nonatomic, readwrite) BOOL excludesCommentsFromSpelling;
@property (nonatomic, readwrite) BOOL excludesParametersFromSpelling;
@property (nonatomic, readwrite) BOOL excludesParametersOfUnlistedCommands;
@property (nonatomic, readwrite, copy) NSArray<NSString *> *commandsWithCheckedParameters;
@property (nonatomic, readwrite, copy) NSArray<NSString *> *commandsWithUncheckedParameters;
@end

NS_ASSUME_NONNULL_END
