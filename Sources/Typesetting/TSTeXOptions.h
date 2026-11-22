// SPDX-License-Identifier: GPL-2.0-or-later
//
//  TSTeXOptions.h
//
//  TeX options in typesetting commands, written as the engines' own usage messages write them:
//  one hyphen for pdfTeX, XeTeX, e-pTeX, e-upTeX and the other web2c engines (-file-line-error,
//  -synctex=1, -shell-escape), two for LuaTeX (--file-line-error). Every engine accepts both.
//

#import <Foundation/Foundation.h>

// The program the command runs: its first word, past env and its options and NAME=value settings.
static inline NSString *TSTeXCommandProgram(NSString *command)
{
    NSArray<NSString *> *words = [[command stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet]
                                  componentsSeparatedByCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
    BOOL afterEnv = NO;
    for (NSString *word in words) {
        if (word.length == 0) continue;
        NSString *name = word.lastPathComponent;
        if (!afterEnv && [name isEqualToString:@"env"]) { afterEnv = YES; continue; }
        if (afterEnv && ([word hasPrefix:@"-"] || [word containsString:@"="])) continue;
        return name;
    }
    return @"";
}

// Whether the command runs LuaTeX (luatex, lualatex, luahbtex, …), whose usage writes two hyphens.
static inline BOOL TSTeXCommandRunsLuaTeX(NSString *command)
{
    return [TSTeXCommandProgram(command).lowercaseString hasPrefix:@"lua"];
}

// The hyphens of a TeX option for the engine of the command: "--" for LuaTeX, "-" otherwise.
static inline NSString *TSTeXOptionDashes(NSString *command)
{
    return TSTeXCommandRunsLuaTeX(command) ? @"--" : @"-";
}

// -shell-escape or --shell-escape as a whole argument: after a blank or at the start, alone or in quotes, and up
// to a blank, the end, or the slash that closes a latexmk q/…/ (not -no-shell-escape, not part of a path or name).
static inline NSRegularExpression *TSShellEscapeExpression(void)
{
    static NSRegularExpression *expression;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        expression = [NSRegularExpression regularExpressionWithPattern:@"(?:(?<=^)|(?<=\\s)|(?<=q/))([\"']?)--?shell-escape\\1(?=\\s|$|/(?:[\\s\"']|$))" options:0 error:NULL];
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
// commands that differ only in that (the profiles of earlier versions wrote --file-line-error). Only
// whole arguments change: -file-line-error, -shell-escape (and their -no- forms), -synctex=N and
// -interaction=mode, after a blank, a quote or a latexmk q/ and up to a blank, a quote, the end or
// the slash that closes the q/…/; other names, values and paths stay as they are.
static inline NSString *TSTeXCommandWithOneHyphenOptions(NSString *command)
{
    static NSRegularExpression *expression;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        expression = [NSRegularExpression regularExpressionWithPattern:
            @"(?:(?<=^)|(?<=[\\s\"'])|(?<=q/))--((?:no-)?(?:file-line-error|shell-escape)|synctex=-?\\d+|interaction=[a-z]+)(?=[\\s\"']|$|/(?:[\\s\"']|$))"
            options:0 error:NULL];
    });
    if (command.length == 0)
        return command;
    return [expression stringByReplacingMatchesInString:command options:0 range:NSMakeRange(0, command.length) withTemplate:@"-$1"];
}
