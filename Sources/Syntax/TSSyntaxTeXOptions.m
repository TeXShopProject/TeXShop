// SPDX-License-Identifier: GPL-2.0-or-later
#import "TSSyntaxTeXOptions.h"

@interface TSSyntaxTeXOptions ()
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

@implementation TSSyntaxTeXOptions

- (instancetype)init
{
    if ((self = [super init])) {
        _texCharacter = '\\';
        _commandsWithCheckedParameters = @[];
        _commandsWithUncheckedParameters = @[];
    }
    return self;
}

// The lists keep copies of the commands too, so that a mutable string passed in cannot change them afterwards.
- (void)setCommandsWithCheckedParameters:(NSArray<NSString *> *)commands
{
    _commandsWithCheckedParameters = [[NSArray alloc] initWithArray:commands copyItems:YES];
}

- (void)setCommandsWithUncheckedParameters:(NSArray<NSString *> *)commands
{
    _commandsWithUncheckedParameters = [[NSArray alloc] initWithArray:commands copyItems:YES];
}

- (void)copyValuesTo:(TSSyntaxTeXOptions *)copy
{
    copy.texCharacter = self.texCharacter;
    copy.colorsExpl3 = self.colorsExpl3;
    copy.makesAtLetter = self.makesAtLetter;
    copy.colorsIndex = self.colorsIndex;
    copy.colorsFootnote = self.colorsFootnote;
    copy.marksFullwidthSymbols = self.marksFullwidthSymbols;
    copy.isXML = self.isXML;
    copy.excludesCommandsFromSpelling = self.excludesCommandsFromSpelling;
    copy.excludesCommentsFromSpelling = self.excludesCommentsFromSpelling;
    copy.excludesParametersFromSpelling = self.excludesParametersFromSpelling;
    copy.excludesParametersOfUnlistedCommands = self.excludesParametersOfUnlistedCommands;
    copy.commandsWithCheckedParameters = self.commandsWithCheckedParameters;
    copy.commandsWithUncheckedParameters = self.commandsWithUncheckedParameters;
}

- (id)copyWithZone:(nullable NSZone *)zone
{
    if ([self isMemberOfClass:[TSSyntaxTeXOptions class]])
        return self;
    TSSyntaxTeXOptions *copy = [TSSyntaxTeXOptions new];
    [self copyValuesTo:copy];
    return copy;
}

- (id)mutableCopyWithZone:(nullable NSZone *)zone
{
    TSMutableSyntaxTeXOptions *copy = [TSMutableSyntaxTeXOptions new];
    [self copyValuesTo:copy];
    return copy;
}

@end

@implementation TSMutableSyntaxTeXOptions
@dynamic texCharacter, colorsExpl3, makesAtLetter, colorsIndex, colorsFootnote, marksFullwidthSymbols, isXML,
    excludesCommandsFromSpelling, excludesCommentsFromSpelling, excludesParametersFromSpelling,
    excludesParametersOfUnlistedCommands, commandsWithCheckedParameters, commandsWithUncheckedParameters;
@end
