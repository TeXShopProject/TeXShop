// SPDX-License-Identifier: GPL-2.0-or-later
//
//  TSTeXOptions.h
//
//  TeX options in typesetting commands, written as the engines' own usage messages write them:
//  one hyphen for pdfTeX, XeTeX, e-pTeX, e-upTeX and the other web2c engines (-file-line-error,
//  -synctex=1, -shell-escape), two for LuaTeX (--file-line-error). Every engine accepts both.
//

#import <Foundation/Foundation.h>

// Whether the command runs LuaTeX (luatex, lualatex, luahbtex, …), whose usage writes two hyphens.
static inline BOOL TSTeXCommandRunsLuaTeX(NSString *command)
{
    NSString *trimmed = [command stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    NSString *program = [[trimmed componentsSeparatedByCharactersInSet:NSCharacterSet.whitespaceCharacterSet].firstObject lastPathComponent];
    return [program.lowercaseString hasPrefix:@"lua"];
}

// The hyphens of a TeX option for the engine of the command: "--" for LuaTeX, "-" otherwise.
static inline NSString *TSTeXOptionDashes(NSString *command)
{
    return TSTeXCommandRunsLuaTeX(command) ? @"--" : @"-";
}

// -shell-escape or --shell-escape as a whole argument, also inside a latexmk q/…/ (not -no-shell-escape).
static inline NSRegularExpression *TSShellEscapeExpression(void)
{
    static NSRegularExpression *expression;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        expression = [NSRegularExpression regularExpressionWithPattern:@"(?<![^\\s\"'/])--?shell-escape(?![^\\s\"'/])" options:0 error:NULL];
    });
    return expression;
}

static inline BOOL TSTeXCommandHasShellEscape(NSString *command)
{
    return command.length && [TSShellEscapeExpression() firstMatchInString:command options:0 range:NSMakeRange(0, command.length)] != nil;
}

// The command without its -shell-escape or --shell-escape arguments.
static inline NSString *TSTeXCommandWithoutShellEscape(NSString *command)
{
    if (command.length == 0)
        return command;
    return [TSShellEscapeExpression() stringByReplacingMatchesInString:command options:0 range:NSMakeRange(0, command.length) withTemplate:@""];
}

// The command with the TeX options that both spellings name written with one hyphen, to compare
// commands that differ only in that (the profiles of earlier versions wrote --file-line-error).
static inline NSString *TSTeXCommandWithOneHyphenOptions(NSString *command)
{
    static NSRegularExpression *expression;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        expression = [NSRegularExpression regularExpressionWithPattern:@"(?<![^\\s\"'/=])--((?:no-)?(?:file-line-error|shell-escape|synctex=|interaction=))" options:0 error:NULL];
    });
    if (command.length == 0)
        return command;
    return [expression stringByReplacingMatchesInString:command options:0 range:NSMakeRange(0, command.length) withTemplate:@"-$1"];
}
