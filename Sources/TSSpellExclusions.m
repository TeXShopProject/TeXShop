/*
 * TeXShop - TeX editor for Mac OS
 * Copyright (C) 2026 Ralph Martin and Yusuke Terada
 * SPDX-License-Identifier: GPL-2.0-or-later
 * TeX-aware spelling implementation by Ralph Martin.
 *
 * Reads the spelling-exclusion rules from a file and masks TeX source text
 * accordingly. See TSSpellExclusions.h and Resources/TeXShop/SpellCheck/
 * SpellingExclusions.txt.
 *
 * This file is part of the TeX-aware spell checking added to TeXShop. It is
 * distributed under the same GNU General Public License as TeXShop.
 */

#import "TSSpellExclusions.h"

#ifndef TSSPELL_STANDALONE_TEST
#import "globals.h"
#endif

#pragma mark - TSSpellMask

@implementation TSSpellLanguageSegment
- (instancetype)initWithRange:(NSRange)range language:(NSString *)language
{
    if ((self = [super init])) { _range = range; _language = [language copy]; }
    return self;
}
@end

@interface TSSpellMask ()
- (instancetype)initWithMasked:(NSString *)masked
                        origin:(NSUInteger *)origin   // takes ownership (malloc)
                      excluded:(NSIndexSet *)excluded
                       accents:(NSIndexSet *)accents
                      language:(uint8_t *)language    // takes ownership (malloc); nil if none
                 languageNames:(NSArray<NSString *> *)languageNames // index 1... into `language`
                originalLength:(NSUInteger)originalLength;
@end

@implementation TSSpellMask {
    NSUInteger *_origin;
    NSUInteger _maskedLength;
    NSIndexSet *_excluded;
    NSIndexSet *_accents;
    uint8_t *_language;                 // per original character: 0 = document language, k = names[k-1]
    NSArray<NSString *> *_languageNames;
    NSArray<TSSpellLanguageSegment *> *_segments;
}

- (instancetype)initWithMasked:(NSString *)masked
                        origin:(NSUInteger *)origin
                      excluded:(NSIndexSet *)excluded
                       accents:(NSIndexSet *)accents
                      language:(uint8_t *)language
                 languageNames:(NSArray<NSString *> *)languageNames
                originalLength:(NSUInteger)originalLength
{
    if ((self = [super init])) {
        _masked = [masked copy];
        _maskedLength = [masked length];
        _origin = origin;
        _excluded = excluded;
        _accents = accents;
        _language = language;
        _languageNames = languageNames;
        _hasLanguages = language != NULL;
        _originalLength = originalLength;
    }
    return self;
}

- (void)dealloc
{
    free(_origin);
    free(_language);
}

- (NSString *)languageForOriginalIndex:(NSUInteger)index
{
    if (!_language || index >= _originalLength) return nil;
    uint8_t k = _language[index];
    return k ? _languageNames[k - 1] : nil;
}

- (NSArray<TSSpellLanguageSegment *> *)languageSegments
{
    if (!_language) return nil;
    if (_segments) return _segments;
    NSMutableArray *segments = [NSMutableArray array];
    NSUInteger start = 0;
    uint8_t current = _maskedLength ? _language[_origin[0]] : 0;
    for (NSUInteger k = 1; k <= _maskedLength; k++) {
        uint8_t here = (k < _maskedLength) ? _language[_origin[k]] : 0;
        if (k == _maskedLength || here != current) {
            NSString *name = current ? _languageNames[current - 1] : nil;
            [segments addObject:[[TSSpellLanguageSegment alloc] initWithRange:NSMakeRange(start, k - start) language:name]];
            start = k;
            current = here;
        }
    }
    _segments = segments;
    return _segments;
}

- (NSUInteger)originalIndexForMaskedIndex:(NSUInteger)i
{
    if (_maskedLength == 0) return 0;
    if (i >= _maskedLength) return _originalLength;
    return _origin[i];
}

- (NSUInteger)maskedIndexForOriginalIndex:(NSUInteger)index
{
    NSUInteger lo = 0, hi = _maskedLength;   // first i with _origin[i] >= index
    while (lo < hi) {
        NSUInteger mid = lo + (hi - lo) / 2;
        if (_origin[mid] < index) lo = mid + 1; else hi = mid;
    }
    return lo;
}

- (NSRange)originalRangeForMaskedRange:(NSRange)range
{
    if (range.length == 0 || NSMaxRange(range) > _maskedLength)
        return NSMakeRange([self originalIndexForMaskedIndex:range.location], 0);
    NSUInteger first = _origin[range.location];
    NSUInteger last = _origin[NSMaxRange(range) - 1] + 1;
    return NSMakeRange(first, last - first);
}

- (BOOL)rangeTouchesExclusion:(NSRange)range
{
    if (range.length == 0) return NO;
    return [_excluded intersectsIndexesInRange:range];
}

- (BOOL)rangeIsNextToAccent:(NSRange)range
{
    if (range.length == 0) return NO;
    NSUInteger start = range.location > 0 ? range.location - 1 : 0;
    return [_accents intersectsIndexesInRange:NSMakeRange(start, NSMaxRange(range) + 1 - start)];
}

@end

#pragma mark - Rules

@interface TSSpellRegexRule : NSObject
@property (nonatomic, strong) NSRegularExpression *regex;
@property (nonatomic) NSInteger count;
@end
@implementation TSSpellRegexRule
@end

@interface TSSpellDelimiter : NSObject
@property (nonatomic, copy) NSString *open;
@property (nonatomic, copy) NSString *close;   // nil: ends at the paragraph end
@property (nonatomic) unichar *openChars;      // C copies, for matching without messaging
@property (nonatomic) NSUInteger openLength;
@property (nonatomic) unichar *closeChars;
@property (nonatomic) NSUInteger closeLength;
@end
@implementation TSSpellDelimiter
- (void)prepare
{
    _openLength = [_open length];
    _openChars = malloc((_openLength + 1) * sizeof(unichar));
    [_open getCharacters:_openChars range:NSMakeRange(0, _openLength)];
    _closeLength = [_close length];
    _closeChars = malloc((_closeLength + 1) * sizeof(unichar));
    if (_closeLength) [_close getCharacters:_closeChars range:NSMakeRange(0, _closeLength)];
}
- (void)dealloc { free(_openChars); free(_closeChars); }
@end

// Everything parsed from one reading of the rules file. Immutable once built.
@interface TSSpellRules : NSObject
@property BOOL comments, commandNames, accents, lineBreakOptions, envOptions, autoMacros, languageNames;
@property (strong) NSMutableArray<TSSpellDelimiter *> *delimiters;
@property (strong) NSMutableSet<NSString *> *skipBody;
@property (strong) NSMutableDictionary<NSString *, NSNumber *> *envArgs;
@property (strong) NSMutableDictionary<NSString *, NSNumber *> *skipArgs;
@property (strong) NSMutableDictionary<NSString *, NSString *> *patterns; // command -> e.g. "[](){}"
@property (strong) NSMutableArray<TSSpellRegexRule *> *regexRules;
@property (strong) NSMutableSet<NSString *> *checkArgs;
@property (strong) NSMutableSet<NSString *> *definitions;
@property (strong) NSMutableSet<NSString *> *verbs;
@property (strong) NSMutableDictionary<NSString *, NSString *> *languageMap;   // babel/polyglossia name -> language code
@property (strong) NSMutableSet<NSString *> *languageCommands, *languageSwitches, *languageEnvs;
@property (copy) NSString *problems;
@end
@implementation TSSpellRules
- (instancetype)init
{
    if ((self = [super init])) {
        _delimiters = [NSMutableArray array];
        _skipBody = [NSMutableSet set];
        _envArgs = [NSMutableDictionary dictionary];
        _skipArgs = [NSMutableDictionary dictionary];
        _patterns = [NSMutableDictionary dictionary];
        _regexRules = [NSMutableArray array];
        _checkArgs = [NSMutableSet set];
        _definitions = [NSMutableSet set];
        _verbs = [NSMutableSet set];
        _languageMap = [NSMutableDictionary dictionary];
        _languageCommands = [NSMutableSet set];
        _languageSwitches = [NSMutableSet set];
        _languageEnvs = [NSMutableSet set];
    }
    return self;
}
@end

static BOOL ParseBool(NSString *s, BOOL *out)
{
    NSString *l = [s lowercaseString];
    if ([@[@"yes", @"true", @"on", @"1"] containsObject:l]) { *out = YES; return YES; }
    if ([@[@"no", @"false", @"off", @"0"] containsObject:l]) { *out = NO; return YES; }
    return NO;
}

static TSSpellRules *ParseRules(NSString *text)
{
    TSSpellRules *rules = [[TSSpellRules alloc] init];
    NSMutableString *problems = [NSMutableString string];
    NSUInteger lineNo = 0;

    for (NSString *rawLine in [text componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]]) {
        lineNo++;
        NSString *line = rawLine;
        NSRange hash = [line rangeOfString:@"#"];
        if (hash.location != NSNotFound) line = [line substringToIndex:hash.location];
        NSMutableArray<NSString *> *tok = [NSMutableArray array];
        for (NSString *t in [line componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceCharacterSet]])
            if ([t length]) [tok addObject:t];
        if ([tok count] == 0) continue;

        NSString *directive = tok[0];
        NSArray<NSString *> *args = [tok subarrayWithRange:NSMakeRange(1, [tok count] - 1)];
        BOOL b;

#define PROBLEM(...) [problems appendFormat:@"line %lu: %@\n", (unsigned long)lineNo, [NSString stringWithFormat:__VA_ARGS__]]

        if ([directive isEqualToString:@"comments"] || [directive isEqualToString:@"command-names"]
            || [directive isEqualToString:@"accents"] || [directive isEqualToString:@"line-break-options"]
            || [directive isEqualToString:@"env-options"] || [directive isEqualToString:@"auto-macros"]
            || [directive isEqualToString:@"language-names"]) {
            if ([args count] != 1 || !ParseBool(args[0], &b)) { PROBLEM(@"%@ needs yes or no", directive); continue; }
            if ([directive isEqualToString:@"comments"]) rules.comments = b;
            else if ([directive isEqualToString:@"command-names"]) rules.commandNames = b;
            else if ([directive isEqualToString:@"accents"]) rules.accents = b;
            else if ([directive isEqualToString:@"line-break-options"]) rules.lineBreakOptions = b;
            else if ([directive isEqualToString:@"auto-macros"]) rules.autoMacros = b;
            else if ([directive isEqualToString:@"language-names"]) rules.languageNames = b;
            else rules.envOptions = b;
        }
        else if ([directive isEqualToString:@"delimited"]) {
            if ([args count] < 1 || [args count] > 2) { PROBLEM(@"delimited needs OPEN and optionally CLOSE"); continue; }
            TSSpellDelimiter *d = [[TSSpellDelimiter alloc] init];
            d.open = args[0];
            d.close = [args count] > 1 ? args[1] : nil;
            [rules.delimiters addObject:d];
        }
        else if ([directive isEqualToString:@"skip-body"]) {
            [rules.skipBody addObjectsFromArray:args];
        }
        else if ([directive isEqualToString:@"skip-env-args"] || [directive isEqualToString:@"skip-args"]
                 || [directive isEqualToString:@"skip-args-matching"]) {
            NSInteger n = [args count] ? [args[0] integerValue] : -1;
            BOOL numeric = [args count] && [args[0] rangeOfCharacterFromSet:[[NSCharacterSet decimalDigitCharacterSet] invertedSet]].location == NSNotFound;
            if (!numeric || [args count] < 2) { PROBLEM(@"%@ needs a number and at least one name", directive); continue; }
            if ([directive isEqualToString:@"skip-env-args"]) {
                for (NSUInteger i = 1; i < [args count]; i++) rules.envArgs[args[i]] = @(n);
            } else if ([directive isEqualToString:@"skip-args"]) {
                for (NSUInteger i = 1; i < [args count]; i++) rules.skipArgs[args[i]] = @(n);
            } else {
                NSError *err = nil;
                NSString *pattern = [NSString stringWithFormat:@"^(?:%@)$", [[args subarrayWithRange:NSMakeRange(1, [args count] - 1)] componentsJoinedByString:@" "]];
                NSRegularExpression *re = [NSRegularExpression regularExpressionWithPattern:pattern options:0 error:&err];
                if (!re) { PROBLEM(@"bad regular expression: %@", [err localizedDescription]); continue; }
                TSSpellRegexRule *r = [[TSSpellRegexRule alloc] init];
                r.regex = re;
                r.count = n;
                [rules.regexRules addObject:r];
            }
        }
        else if ([directive isEqualToString:@"skip-pattern"]) {
            // skip-pattern PATTERN COMMAND...   where PATTERN is made of {} [] and ()
            NSString *pattern = [args count] ? args[0] : @"";
            BOOL valid = [pattern length] > 0 && [pattern length] % 2 == 0;
            for (NSUInteger k = 0; valid && k < [pattern length]; k += 2) {
                NSString *pair = [pattern substringWithRange:NSMakeRange(k, 2)];
                if (![@[@"{}", @"[]", @"()"] containsObject:pair]) valid = NO;
            }
            if (!valid || [args count] < 2) { PROBLEM(@"skip-pattern needs a pattern made of {} [] and (), and at least one command"); continue; }
            for (NSUInteger i = 1; i < [args count]; i++) rules.patterns[args[i]] = pattern;
        }
        else if ([directive isEqualToString:@"check-args"]) {
            [rules.checkArgs addObjectsFromArray:args];
        }
        else if ([directive isEqualToString:@"skip-definition"]) {
            [rules.definitions addObjectsFromArray:args];
        }
        else if ([directive isEqualToString:@"skip-verb"]) {
            [rules.verbs addObjectsFromArray:args];
        }
        else if ([directive isEqualToString:@"language-map"]) {
            if ([args count] != 2) { PROBLEM(@"language-map needs a language name and a language code"); continue; }
            rules.languageMap[args[0]] = [args[1] stringByReplacingOccurrencesOfString:@"-" withString:@"_"];
        }
        else if ([directive isEqualToString:@"language-command"]) {
            [rules.languageCommands addObjectsFromArray:args];
        }
        else if ([directive isEqualToString:@"language-switch"]) {
            [rules.languageSwitches addObjectsFromArray:args];
        }
        else if ([directive isEqualToString:@"language-env"]) {
            [rules.languageEnvs addObjectsFromArray:args];
        }
        else {
            PROBLEM(@"unknown directive '%@'", directive);
        }
#undef PROBLEM
    }

    // Longer openers first, so that $$ is tried before $.
    [rules.delimiters sortWithOptions:NSSortStable usingComparator:^NSComparisonResult(TSSpellDelimiter *a, TSSpellDelimiter *b) {
        if ([a.open length] > [b.open length]) return NSOrderedAscending;
        if ([a.open length] < [b.open length]) return NSOrderedDescending;
        return NSOrderedSame;
    }];
    for (TSSpellDelimiter *d in rules.delimiters) [d prepare];
    rules.problems = [problems length] ? problems : nil;
    return rules;
}

#pragma mark - Masking

static inline BOOL IsLetter(unichar c)   { return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z'); }
static inline BOOL IsNewline(unichar c)  { return c == '\n' || c == '\r'; }

static BOOL HasPrefixAt(const unichar *src, NSUInteger n, NSUInteger i, NSString *s)
{
    NSUInteger len = [s length];
    if (i + len > n) return NO;
    for (NSUInteger k = 0; k < len; k++)
        if (src[i + k] != [s characterAtIndex:k]) return NO;
    return YES;
}

static BOOL MatchesAt(const unichar *src, NSUInteger n, NSUInteger i, const unichar *pat, NSUInteger len)
{
    if (i + len > n) return NO;
    for (NSUInteger k = 0; k < len; k++)
        if (src[i + k] != pat[k]) return NO;
    return YES;
}

// Index just past the group opening at src[i], or NSNotFound.
static NSUInteger BalancedEnd(const unichar *src, NSUInteger n, NSUInteger i, unichar open, unichar close)
{
    NSInteger depth = 0;
    while (i < n) {
        unichar c = src[i];
        if (c == '\\') { i += 2; continue; }
        if (c == open) depth++;
        else if (c == close) { depth--; if (depth == 0) return i + 1; }
        i++;
    }
    return NSNotFound;
}

// YES if src[i] is a newline that ends a paragraph (only blanks, then another
// newline or the end of the text, follow it).
static BOOL IsParagraphBreakAt(const unichar *src, NSUInteger n, NSUInteger i)
{
    if (!IsNewline(src[i])) return NO;
    NSUInteger j = i + 1;
    if (src[i] == '\r' && j < n && src[j] == '\n') j++;
    while (j < n && (src[j] == ' ' || src[j] == '\t')) j++;
    return j >= n || IsNewline(src[j]);
}

static unichar ComposeAccent(unichar accentChar, unichar letter)
{
    unichar combining = 0;
    switch (accentChar) {
        case '`': combining = 0x0300; break;
        case '\'': combining = 0x0301; break;
        case '^': combining = 0x0302; break;
        case '"': combining = 0x0308; break;
        case '~': combining = 0x0303; break;
        case '=': combining = 0x0304; break;
        case '.': combining = 0x0307; break;
        default: return letter;
    }
    NSString *s = [NSString stringWithFormat:@"%C%C", letter, combining];
    NSString *p = [s precomposedStringWithCanonicalMapping];
    return [p length] == 1 ? [p characterAtIndex:0] : letter;
}

static unichar LetterCommand(NSString *name)
{
    static NSDictionary<NSString *, NSString *> *table;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        table = @{@"ss": @"ß", @"ae": @"æ", @"AE": @"Æ", @"oe": @"œ",
                  @"OE": @"Œ", @"o": @"ø", @"O": @"Ø", @"aa": @"å",
                  @"AA": @"Å", @"l": @"ł", @"L": @"Ł", @"i": @"i", @"j": @"j"};
    });
    NSString *s = table[name];
    return s ? [s characterAtIndex:0] : 0;
}

// A macro defined in the text (\newcommand, \def, \NewDocumentCommand ...) some of
// whose arguments are only passed on to things that are not prose.
@interface TSSpellMacro : NSObject
@property (copy) NSString *kinds;      // one letter per argument: m mandatory, o optional [..], s star
@property NSUInteger skip;             // bit k set: argument k+1 is not prose
@end
@implementation TSSpellMacro
@end

// Working state for one masking pass.
typedef struct {
    const unichar *src;        // the original text
    unichar *out;              // masked characters, same indexing as src
    uint8_t *deleted;          // 1: character removed from the masked text
    uint8_t *excluded;         // 1: character is not to be spell checked
    uint8_t *accent;           // 1: character belongs to an accent command (\"u, \ss, ...)
    uint8_t *language;         // 0: document language, k: languageNames[k-1]
    NSUInteger n;
    __unsafe_unretained NSMutableDictionary<NSString *, NSNumber *> *argCountCache; // command name -> args to skip (-1: none)
    __unsafe_unretained NSMutableArray<NSString *> *languageNames;
    __unsafe_unretained NSDictionary<NSString *, TSSpellMacro *> *macros;      // macros defined in the text
    __unsafe_unretained NSSet<NSString *> *skipBodyEnvs;                        // environments defined in the text
} MaskState;

static void Blank(MaskState *m, NSUInteger i, NSUInteger j)
{
    if (j > m->n) j = m->n;
    for (NSUInteger k = i; k < j; k++) {
        if (IsNewline(m->src[k])) continue;
        m->out[k] = ' ';
        m->excluded[k] = 1;
    }
}

static void Delete(MaskState *m, NSUInteger i)
{
    m->deleted[i] = 1;
    m->excluded[i] = 1;
}

// Blank the [..] groups and up to `mandatory` {..} groups starting at pos;
// returns the position after them.
static NSUInteger SkipArgs(MaskState *m, NSUInteger pos, NSInteger mandatory)
{
    NSInteger remaining = mandatory;
    for (;;) {
        if (mandatory > 0 && remaining == 0) break;
        NSUInteger j = pos;
        while (j < m->n && (m->src[j] == ' ' || m->src[j] == '\t')) j++;
        NSUInteger end;
        if (j < m->n && m->src[j] == '[') {
            end = BalancedEnd(m->src, m->n, j, '[', ']');
        } else if (j < m->n && m->src[j] == '{' && remaining > 0) {
            end = BalancedEnd(m->src, m->n, j, '{', '}');
            if (end != NSNotFound) remaining--;
        } else {
            break;
        }
        if (end == NSNotFound) break;
        Blank(m, pos, end);
        pos = end;
    }
    return pos;
}

static NSUInteger SkipOptional(MaskState *m, NSUInteger pos)
{
    if (pos < m->n && m->src[pos] == '[') {
        NSUInteger end = BalancedEnd(m->src, m->n, pos, '[', ']');
        if (end != NSNotFound) { Blank(m, pos, end); return end; }
    }
    return pos;
}

// Blank the groups that follow a command according to a pattern such as "[](){}":
// each [..] or (..) in the pattern is skipped if it is there, and each {..} must
// be there (the pattern stops at the first {..} that is missing). Returns the
// position after the last group skipped.
static NSUInteger SkipPattern(MaskState *m, NSUInteger pos, NSString *pattern)
{
    for (NSUInteger k = 0; k + 1 < [pattern length]; k += 2) {
        unichar open = [pattern characterAtIndex:k], close = [pattern characterAtIndex:k + 1];
        NSUInteger j = pos;
        while (j < m->n && (m->src[j] == ' ' || m->src[j] == '\t')) j++;
        NSUInteger end = NSNotFound;
        if (j < m->n && m->src[j] == open) end = BalancedEnd(m->src, m->n, j, open, close);
        if (end == NSNotFound) {
            if (open == '{') break;      // a required argument is missing: stop
            continue;                    // an optional group is absent: try the next
        }
        Blank(m, pos, end);
        pos = end;
    }
    return pos;
}

// Skip blanks, and one line break that is not a paragraph break, as TeX does
// between a command and its arguments.
static NSUInteger SkipBlanks(const unichar *src, NSUInteger n, NSUInteger p)
{
    while (p < n && (src[p] == ' ' || src[p] == '\t')) p++;
    if (p < n && IsNewline(src[p]) && !IsParagraphBreakAt(src, n, p)) {
        if (src[p] == '\r' && p + 1 < n && src[p + 1] == '\n') p++;
        p++;
        while (p < n && (src[p] == ' ' || src[p] == '\t')) p++;
    }
    return p;
}

// Blank the arguments of a macro defined in the text, as far as its definition
// shows that they are not prose (skip bit set). The other arguments are left
// for the normal scan; this returns nothing because the scan continues just
// after the macro's name and passes over the blanked groups quickly.
static void ApplyMacro(MaskState *m, NSUInteger pos, TSSpellMacro *macro)
{
    NSString *kinds = macro.kinds;
    for (NSUInteger k = 0; k < [kinds length]; k++) {
        unichar kind = [kinds characterAtIndex:k];
        BOOL skip = (macro.skip >> k) & 1;
        NSUInteger p = SkipBlanks(m->src, m->n, pos);
        if (kind == 's') {
            if (p < m->n && m->src[p] == '*') { if (skip) Blank(m, p, p + 1); pos = p + 1; }
            continue;
        }
        unichar open = (kind == 'o') ? '[' : '{', close = (kind == 'o') ? ']' : '}';
        if (p >= m->n || m->src[p] != open) {
            if (kind == 'o') continue;      // an optional argument that is not there
            return;                         // a missing argument: stop
        }
        NSUInteger end = BalancedEnd(m->src, m->n, p, open, close);
        if (end == NSNotFound) return;
        if (skip) Blank(m, p, end);
        pos = end;
    }
}

// Mark src[from..to) as being in the language that rules.languageMap gives for
// `name` (a babel or polyglossia language name).
static void SetLanguage(MaskState *m, TSSpellRules *rules, NSString *name, NSUInteger from, NSUInteger to)
{
    // A language that is not in the map ("und") is one nothing can be checked in.
    NSString *code = rules.languageMap[[name stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]]] ?: @"und";
    NSUInteger index = [m->languageNames indexOfObject:code];
    if (index == NSNotFound) {
        if ([m->languageNames count] >= 255) return;
        [m->languageNames addObject:code];
        index = [m->languageNames count] - 1;
    }
    if (to > m->n) to = m->n;
    for (NSUInteger k = from; k < to; k++) m->language[k] = (uint8_t)(index + 1);
}

// The end of the group or environment that contains position `from`: the first
// } or \end{..} that has no opening in between, or the end of the text. A later
// language switch in the same group or environment ends it too, since that switch
// takes over from there (this also keeps a long run of top-level switches linear).
static NSUInteger ScopeEnd(MaskState *m, TSSpellRules *rules, NSUInteger from)
{
    const unichar *src = m->src;
    NSUInteger n = m->n, j = from;
    NSInteger braces = 0, envs = 0;
    while (j < n) {
        unichar c = src[j];
        if (c == '%') { while (j < n && !IsNewline(src[j])) j++; continue; }
        if (c == '\\') {
            if (HasPrefixAt(src, n, j, @"\\begin{")) envs++;
            else if (HasPrefixAt(src, n, j, @"\\end{")) { if (envs == 0) return j; envs--; }
            else if (braces == 0 && envs == 0 && j + 1 < n && IsLetter(src[j + 1])) {
                NSUInteger e = j + 1;
                while (e < n && IsLetter(src[e])) e++;
                if ([rules.languageSwitches containsObject:[NSString stringWithCharacters:src + j + 1 length:e - j - 1]])
                    return j;
                j = e;
                continue;
            }
            j += 2;
            continue;
        }
        if (c == '{') braces++;
        else if (c == '}') { if (braces == 0) return j; braces--; }
        j++;
    }
    return n;
}

// Blank any [..] groups at pos; returns the position after them.
static NSUInteger BlankOptionals(MaskState *m, NSUInteger pos)
{
    for (;;) {
        NSUInteger p = SkipBlanks(m->src, m->n, pos);
        if (p >= m->n || m->src[p] != '[') return pos;
        NSUInteger end = BalancedEnd(m->src, m->n, p, '[', ']');
        if (end == NSNotFound) return pos;
        Blank(m, p, end);
        pos = end;
    }
}

// The commands that mark text as being in another language:
//   \foreignlanguage[options]{language}{text}     (language-command)
//   \selectlanguage{language}                      (language-switch): to the end of the group or environment
//   \textgerman[options]{text}                     (language-names yes): \text followed by a language name
// Returns the position to continue from, or NSNotFound if `name` is none of these.
// The text itself is left for the normal scan, which also finds its markup.
static NSUInteger HandleLanguageCommand(MaskState *m, TSSpellRules *rules, NSString *name, NSUInteger pos)
{
    int kind;
    NSString *fixed = nil;
    if ([rules.languageCommands containsObject:name]) kind = 1;
    else if ([rules.languageSwitches containsObject:name]) kind = 2;
    else if (rules.languageNames && [name length] > 4 && [name hasPrefix:@"text"]
             && rules.languageMap[[name substringFromIndex:4]]) { kind = 3; fixed = [name substringFromIndex:4]; }
    else return NSNotFound;

    const unichar *src = m->src;
    NSUInteger n = m->n;
    NSUInteger p = BlankOptionals(m, pos);
    NSString *language = fixed;
    if (kind != 3) {
        NSUInteger q = SkipBlanks(src, n, p);
        if (q >= n || src[q] != '{') return p;
        NSUInteger end = BalancedEnd(src, n, q, '{', '}');
        if (end == NSNotFound) return p;
        language = [NSString stringWithCharacters:src + q + 1 length:end - q - 2];
        Blank(m, q, end);
        p = end;
    }
    if (kind == 2) {
        SetLanguage(m, rules, language, p, ScopeEnd(m, rules, p));
        return p;
    }
    NSUInteger q = SkipBlanks(src, n, p);
    if (q < n && src[q] == '{') {
        NSUInteger end = BalancedEnd(src, n, q, '{', '}');
        if (end != NSNotFound) SetLanguage(m, rules, language, q + 1, end - 1);
    }
    return p;
}

// Index just past \end{env} (or \end{env*}) at or after pos; n if there is none.
static NSUInteger EnvironmentEnd(MaskState *m, NSUInteger pos, NSString *env)
{
    NSUInteger n = m->n;
    for (NSUInteger i = pos; i < n; i++) {
        if (m->src[i] != '\\' || !HasPrefixAt(m->src, n, i, @"\\end")) continue;
        NSUInteger j = i + 4;
        while (j < n && (m->src[j] == ' ' || m->src[j] == '\t' || IsNewline(m->src[j]))) j++;
        if (j >= n || m->src[j] != '{') continue;
        NSUInteger k = j + 1;
        while (k < n && m->src[k] != '}') k++;
        if (k >= n) continue;
        NSString *name = [NSString stringWithCharacters:m->src + j + 1 length:k - j - 1];
        name = [name stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        if ([name hasSuffix:@"*"]) name = [name substringToIndex:[name length] - 1];
        if ([name isEqualToString:env]) return k + 1;
    }
    return n;
}

// Handle a delimited span starting at i if one of the rules' openers is there.
// Returns the position to continue from, or NSNotFound if none matched.
static NSUInteger HandleDelimited(MaskState *m, TSSpellRules *rules, NSUInteger i)
{
    for (TSSpellDelimiter *d in rules.delimiters) {
        if (!MatchesAt(m->src, m->n, i, d.openChars, d.openLength)) continue;
        // Look for the closer, giving up at the end of the paragraph (TeX
        // does not allow a blank line inside maths): an unterminated opener
        // then excludes the rest of its paragraph only.
        NSUInteger j = i + d.openLength;
        NSUInteger end = NSNotFound;
        while (j < m->n) {
            if (d.closeLength && MatchesAt(m->src, m->n, j, d.closeChars, d.closeLength)) { end = j + d.closeLength; break; }
            if (IsParagraphBreakAt(m->src, m->n, j)) { end = j; break; }
            if (m->src[j] == '\\') j += 2; else j++;
        }
        if (end == NSNotFound) end = m->n;
        Blank(m, i, end);
        return end;
    }
    return NSNotFound;
}

static NSUInteger HandleBackslash(MaskState *m, TSSpellRules *rules, NSUInteger i)
{
    const unichar *src = m->src;
    NSUInteger n = m->n;

    // \begin{env} and \end{env}
    BOOL isBegin = HasPrefixAt(src, n, i, @"\\begin");
    BOOL isEnd = !isBegin && HasPrefixAt(src, n, i, @"\\end");
    if (isBegin || isEnd) {
        NSUInteger j = i + (isBegin ? 6 : 4);
        while (j < n && (src[j] == ' ' || src[j] == '\t' || IsNewline(src[j]))) j++;
        if (j < n && src[j] == '{') {
            NSUInteger k = j + 1;
            while (k < n && src[k] != '}') k++;
            if (k < n) {
                NSString *env = [[NSString stringWithCharacters:src + j + 1 length:k - j - 1]
                                 stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
                if ([env hasSuffix:@"*"]) env = [env substringToIndex:[env length] - 1];
                NSUInteger pos = k + 1;
                Blank(m, i, pos);
                if (isEnd) return pos;
                if ([rules.skipBody containsObject:env] || [m->skipBodyEnvs containsObject:env]) {
                    NSUInteger stop = EnvironmentEnd(m, pos, env);
                    Blank(m, pos, stop);
                    return stop;
                }
                if ([rules.languageEnvs containsObject:env]) {
                    // \begin{otherlanguage}[options]{language}
                    NSUInteger p = BlankOptionals(m, pos);
                    NSUInteger q = SkipBlanks(src, n, p);
                    if (q < n && src[q] == '{') {
                        NSUInteger end = BalancedEnd(src, n, q, '{', '}');
                        if (end != NSNotFound) {
                            NSString *language = [NSString stringWithCharacters:src + q + 1 length:end - q - 2];
                            Blank(m, q, end);
                            SetLanguage(m, rules, language, end, EnvironmentEnd(m, end, env));
                            return end;
                        }
                    }
                    return p;
                }
                if (rules.languageNames && rules.languageMap[env])      // \begin{german}
                    SetLanguage(m, rules, env, pos, EnvironmentEnd(m, pos, env));
                if (rules.envOptions) pos = SkipOptional(m, pos);
                NSNumber *count = rules.envArgs[env];
                if (count) pos = SkipArgs(m, pos, [count integerValue]);
                return pos;
            }
        }
    }

    // \name
    if (i + 1 < n && (IsLetter(src[i + 1]) || src[i + 1] == '@')) {
        NSUInteger e = i + 1;
        while (e < n && (IsLetter(src[e]) || src[e] == '@')) e++;
        NSString *name = [NSString stringWithCharacters:src + i + 1 length:e - i - 1];
        NSUInteger pos = (e < n && src[e] == '*') ? e + 1 : e;

        if ([rules.verbs containsObject:name]) {
            NSUInteger end = pos;
            if (pos < n && !IsNewline(src[pos])) {
                end = pos + 1;
                while (end < n && src[end] != src[pos] && !IsNewline(src[end])) end++;
                if (end < n && src[end] == src[pos]) end++;
            }
            Blank(m, i, end);
            return end;
        }
        if (rules.accents) {
            unichar letter = LetterCommand(name);
            if (letter) {
                for (NSUInteger k = i + 1; k < pos; k++) Delete(m, k);
                for (NSUInteger k = i; k < pos; k++) m->accent[k] = 1;
                m->out[i] = letter;
                return pos;
            }
        }
        if (rules.commandNames) Blank(m, i, pos);

        NSUInteger afterLanguage = HandleLanguageCommand(m, rules, name, pos);
        if (afterLanguage != NSNotFound) return afterLanguage;

        if ([rules.definitions containsObject:name]) {
            NSUInteger j = pos;
            while (j < n && src[j] != '{' && !IsNewline(src[j])) j++;
            NSUInteger end = j;
            if (j < n && src[j] == '{') {
                NSUInteger b = BalancedEnd(src, n, j, '{', '}');
                if (b != NSNotFound) end = b;
            }
            Blank(m, pos, end);
            return end;
        }
        if ([rules.checkArgs containsObject:name]) return pos;
        NSString *pattern = rules.patterns[name];
        if (pattern) return SkipPattern(m, pos, pattern);
        // How many arguments does this command skip? Looked up once per name.
        NSNumber *cached = m->argCountCache[name];
        if (!cached) {
            NSInteger found = -1;
            NSNumber *count = rules.skipArgs[name];
            if (count) {
                found = [count integerValue];
            } else {
                for (TSSpellRegexRule *r in rules.regexRules) {
                    if ([r.regex firstMatchInString:name options:0 range:NSMakeRange(0, [name length])]) {
                        found = r.count;
                        break;
                    }
                }
            }
            cached = @(found);
            m->argCountCache[name] = cached;
        }
        if ([cached integerValue] >= 0) return SkipArgs(m, pos, [cached integerValue]);
        TSSpellMacro *macro = m->macros[name];
        if (macro) ApplyMacro(m, pos, macro);
        return pos;
    }

    if (i + 1 >= n) return i + 1;
    unichar next = src[i + 1];

    if (next == '\\') {
        Blank(m, i, i + 2);
        return rules.lineBreakOptions ? SkipOptional(m, i + 2) : i + 2;
    }
    if (rules.accents && next > 0 && next < 128 && strchr("`'^\".~=", (int)next) != NULL) {
        NSUInteger j = i + 2;
        BOOL brace = j < n && src[j] == '{';
        NSUInteger k = brace ? j + 1 : j;
        if (k < n && IsLetter(src[k])) {
            unichar composed = ComposeAccent(next, src[k]);
            Delete(m, i);
            Delete(m, i + 1);
            m->accent[i] = m->accent[i + 1] = m->accent[k] = 1;
            if (brace) {
                Delete(m, j);
                m->accent[j] = 1;
                if (k + 1 < n && src[k + 1] == '}') { Delete(m, k + 1); m->accent[k + 1] = 1; }
            }
            m->out[k] = composed;
            return k + 1;
        }
    }
    // \% \$ \& \_ \{ \} \, ... : a control symbol, never prose.
    Blank(m, i, i + 2);
    return i + 2;
}

// The scan itself: fills in m->out, deleted, excluded, accent and language.
static void RunMask(MaskState *m, TSSpellRules *rules)
{
    const unichar *src = m->src;
    NSUInteger n = m->n;

    // Which characters can start a delimited span (no messaging in the loop).
    BOOL startsDelimiter[128] = {0};
    BOOL anyDelimiter = NO;
    for (TSSpellDelimiter *d in rules.delimiters) {
        if (d.openLength && d.openChars[0] < 128) { startsDelimiter[d.openChars[0]] = YES; anyDelimiter = YES; }
        else if (d.openLength) { anyDelimiter = YES; }
    }
    BOOL comments = rules.comments;

    NSUInteger i = 0;
    while (i < n) {
        unichar c = src[i];
        if (m->excluded[i] && !IsNewline(c)) { i++; continue; }     // already blanked (by a macro's arguments)
        if (c == '%' && comments) {
            NSUInteger j = i;
            while (j < n && !IsNewline(src[j])) j++;
            Blank(m, i, j);
            i = j;
            continue;
        }
        if (anyDelimiter && (c >= 128 || startsDelimiter[c])) {
            NSUInteger next = HandleDelimited(m, rules, i);
            if (next != NSNotFound) { i = next; continue; }
        }
        if (c == '\\') i = HandleBackslash(m, rules, i);
        else i++;
    }
}

#pragma mark - Macros defined in the text

// Which characters of `text` the rules exclude (1 = excluded), for analysing the
// body of a macro definition.
static NSData *ExcludedFlags(TSSpellRules *rules, NSDictionary<NSString *, TSSpellMacro *> *macros,
                             NSSet<NSString *> *envs, NSString *text)
{
    NSUInteger n = [text length];
    unichar *src = malloc((n + 1) * sizeof(unichar));
    unichar *out = malloc((n + 1) * sizeof(unichar));
    uint8_t *deleted = calloc(n + 1, 1), *excluded = calloc(n + 1, 1), *accent = calloc(n + 1, 1), *language = calloc(n + 1, 1);
    [text getCharacters:src range:NSMakeRange(0, n)];
    memcpy(out, src, n * sizeof(unichar));
    NSMutableDictionary<NSString *, NSNumber *> *cache = [NSMutableDictionary dictionary];
    NSMutableArray<NSString *> *names = [NSMutableArray array];
    MaskState m = { src, out, deleted, excluded, accent, language, n, cache, names, macros, envs };
    RunMask(&m, rules);
    NSData *flags = [NSData dataWithBytes:excluded length:n];
    free(src); free(out); free(deleted); free(excluded); free(accent); free(language);
    return flags;
}

static NSString *const kProbe = @"qzjxq";

// Decide, from the body of a definition, which arguments are not prose: those
// that occur only where the rules exclude the text (the argument of \label or
// \ref, inside maths, in the argument of another such macro, ...). The body is
// run through the masking itself with the argument replaced by a probe word.
static void RegisterMacro(TSSpellRules *rules, NSMutableDictionary<NSString *, TSSpellMacro *> *macros,
                          NSSet<NSString *> *envs, NSString *name, NSString *kinds, NSString *body)
{
    if ([kinds length] == 0 || [kinds length] > 9) return;
    NSUInteger skip = 0;
    for (NSUInteger k = 0; k < [kinds length]; k++) {
        if ([kinds characterAtIndex:k] == 's') continue;
        unichar target = (unichar)('1' + k);
        NSMutableString *probe = [NSMutableString string];
        for (NSUInteger j = 0; j < [body length]; j++) {
            unichar c = [body characterAtIndex:j];
            if (c == '#' && j + 1 < [body length]) {
                unichar d = [body characterAtIndex:j + 1];
                if (d >= '1' && d <= '9') {
                    [probe appendString:(d == target) ? kProbe : @"x"];
                    j++;
                    continue;
                }
                if (d == '#') { [probe appendString:@"##"]; j++; continue; }
            }
            [probe appendFormat:@"%C", c];
        }
        NSData *flags = nil;
        BOOL found = NO, allExcluded = YES;
        NSRange from = NSMakeRange(0, [probe length]);
        for (;;) {
            NSRange r = [probe rangeOfString:kProbe options:0 range:from];
            if (r.location == NSNotFound) break;
            if (!flags) flags = ExcludedFlags(rules, macros, envs, probe);
            found = YES;
            if (((const uint8_t *)flags.bytes)[r.location] == 0) { allExcluded = NO; break; }
            from = NSMakeRange(NSMaxRange(r), [probe length] - NSMaxRange(r));
        }
        if (found && allExcluded) skip |= (NSUInteger)1 << k;
    }
    if (skip == 0) return;
    TSSpellMacro *macro = [[TSSpellMacro alloc] init];
    macro.kinds = kinds;
    macro.skip = skip;
    macros[name] = macro;
}

// "\foo" or "{\foo}" at p (after blanks): the name; moves p past it.
static NSString *ReadMacroName(const unichar *src, NSUInteger n, NSUInteger *p)
{
    NSUInteger q = SkipBlanks(src, n, *p);
    BOOL brace = NO;
    if (q < n && src[q] == '{') { brace = YES; q = SkipBlanks(src, n, q + 1); }
    if (q >= n || src[q] != '\\') return nil;
    NSUInteger e = q + 1;
    while (e < n && (IsLetter(src[e]) || src[e] == '@')) e++;
    if (e == q + 1) return nil;
    NSString *name = [NSString stringWithCharacters:src + q + 1 length:e - q - 1];
    if (brace) {
        e = SkipBlanks(src, n, e);
        if (e >= n || src[e] != '}') return nil;
        e++;
    }
    *p = e;
    return name;
}

// The {..} group at p (after blanks): its content; moves p past it.
static NSString *ReadGroup(const unichar *src, NSUInteger n, NSUInteger *p)
{
    NSUInteger q = SkipBlanks(src, n, *p);
    if (q >= n || src[q] != '{') return nil;
    NSUInteger end = BalancedEnd(src, n, q, '{', '}');
    if (end == NSNotFound) return nil;
    *p = end;
    return [NSString stringWithCharacters:src + q + 1 length:end - q - 2];
}

// The environments a \newenvironment's opening code begins with the body of
// (\newenvironment{eqn}{\begin{align}}{\end{align}}): the new environment is then
// not prose either.
static void RegisterEnvironment(TSSpellRules *rules, NSMutableSet<NSString *> *envs, NSString *name, NSString *begin)
{
    NSRange from = NSMakeRange(0, [begin length]);
    for (;;) {
        NSRange r = [begin rangeOfString:@"\\begin{" options:0 range:from];
        if (r.location == NSNotFound) return;
        NSUInteger start = NSMaxRange(r);
        NSRange close = [begin rangeOfString:@"}" options:0 range:NSMakeRange(start, [begin length] - start)];
        if (close.location == NSNotFound) return;
        NSString *inner = [begin substringWithRange:NSMakeRange(start, close.location - start)];
        if ([inner hasSuffix:@"*"]) inner = [inner substringToIndex:[inner length] - 1];
        if ([rules.skipBody containsObject:inner] || [envs containsObject:inner]) { [envs addObject:name]; return; }
        from = NSMakeRange(close.location, [begin length] - close.location);
    }
}

// Read the definitions of macros and environments in the text, so that the
// arguments of the macros that only pass them on to non-prose can be skipped.
static void ScanDefinitions(TSSpellRules *rules, const unichar *src, NSUInteger n,
                            NSMutableDictionary<NSString *, TSSpellMacro *> *macros, NSMutableSet<NSString *> *envs)
{
    static NSSet<NSString *> *commandDefiners, *documentDefiners, *defDefiners, *envDefiners, *documentEnvDefiners;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        commandDefiners = [NSSet setWithObjects:@"newcommand", @"renewcommand", @"providecommand", @"DeclareRobustCommand", nil];
        documentDefiners = [NSSet setWithObjects:@"NewDocumentCommand", @"RenewDocumentCommand", @"ProvideDocumentCommand",
                            @"DeclareDocumentCommand", nil];
        defDefiners = [NSSet setWithObjects:@"def", @"gdef", @"edef", @"xdef", nil];
        envDefiners = [NSSet setWithObjects:@"newenvironment", @"renewenvironment", nil];
        documentEnvDefiners = [NSSet setWithObjects:@"NewDocumentEnvironment", @"RenewDocumentEnvironment",
                               @"ProvideDocumentEnvironment", @"DeclareDocumentEnvironment", nil];
    });
    NSUInteger i = 0;
    while (i < n) {
        unichar c = src[i];
        if (c == '%') { while (i < n && !IsNewline(src[i])) i++; continue; }
        if (c != '\\') { i++; continue; }
        if (i + 1 >= n || !IsLetter(src[i + 1])) { i += 2; continue; }
        NSUInteger e = i + 1;
        while (e < n && IsLetter(src[e])) e++;
        NSString *word = [NSString stringWithCharacters:src + i + 1 length:e - i - 1];
        NSUInteger p = (e < n && src[e] == '*') ? e + 1 : e;
        i = p;
        BOOL isCommand = [commandDefiners containsObject:word], isDocument = [documentDefiners containsObject:word];
        BOOL isDef = [defDefiners containsObject:word];
        BOOL isEnv = [envDefiners containsObject:word], isDocumentEnv = [documentEnvDefiners containsObject:word];
        if (!(isCommand || isDocument || isDef || isEnv || isDocumentEnv)) continue;

        if (isEnv || isDocumentEnv) {
            // {name}[n][default]{begin}{end}   or   {name}{spec}{begin}{end}
            NSString *envName = ReadGroup(src, n, &p);
            if (!envName) continue;
            if (isEnv) {
                NSUInteger q = SkipBlanks(src, n, p);
                while (q < n && src[q] == '[') {
                    NSUInteger end = BalancedEnd(src, n, q, '[', ']');
                    if (end == NSNotFound) break;
                    p = end;
                    q = SkipBlanks(src, n, p);
                }
            } else {
                if (!ReadGroup(src, n, &p)) continue;
            }
            NSString *begin = ReadGroup(src, n, &p);
            if (!begin) continue;
            RegisterEnvironment(rules, envs, [envName stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]], begin);
            i = p;
            continue;
        }

        NSString *name = ReadMacroName(src, n, &p);
        if (!name) continue;
        NSMutableString *kinds = [NSMutableString string];
        BOOL supported = YES;
        if (isCommand) {
            NSUInteger q = SkipBlanks(src, n, p);
            NSInteger count = 0;
            BOOL hasDefault = NO;
            if (q < n && src[q] == '[') {
                NSUInteger end = BalancedEnd(src, n, q, '[', ']');
                if (end == NSNotFound) continue;
                count = [[NSString stringWithCharacters:src + q + 1 length:end - q - 2] integerValue];
                p = end;
                q = SkipBlanks(src, n, p);
                if (q < n && src[q] == '[') {
                    end = BalancedEnd(src, n, q, '[', ']');
                    if (end == NSNotFound) continue;
                    hasDefault = YES;
                    p = end;
                }
            }
            if (count < 0 || count > 9) continue;
            for (NSInteger k = 0; k < count; k++) [kinds appendString:(k == 0 && hasDefault) ? @"o" : @"m"];
        } else if (isDocument) {
            NSString *spec = ReadGroup(src, n, &p);
            if (!spec) continue;
            for (NSUInteger k = 0; k < [spec length] && supported; k++) {
                unichar t = [spec characterAtIndex:k];
                if (t == ' ' || t == '\t' || t == '\n' || t == '+' || t == '!') continue;
                if (t == 'm') [kinds appendString:@"m"];
                else if (t == 'o') [kinds appendString:@"o"];
                else if (t == 's') [kinds appendString:@"s"];
                else if (t == 'O') {
                    [kinds appendString:@"o"];
                    while (k + 1 < [spec length] && [spec characterAtIndex:k + 1] == ' ') k++;
                    if (k + 1 < [spec length] && [spec characterAtIndex:k + 1] == '{') {      // the default value
                        NSInteger depth = 0;
                        for (k = k + 1; k < [spec length]; k++) {
                            unichar u = [spec characterAtIndex:k];
                            if (u == '{') depth++; else if (u == '}' && --depth == 0) break;
                        }
                    }
                } else supported = NO;
            }
        } else {
            // \def\name#1#2{...}: parameters must be plain #1 #2 ... for us to follow them.
            while (p + 1 < n && src[p] == '#' && src[p + 1] >= '1' && src[p + 1] <= '9') { [kinds appendString:@"m"]; p += 2; }
            if (p >= n || src[p] != '{') supported = NO;
        }
        if (!supported) continue;
        NSString *body = ReadGroup(src, n, &p);
        if (!body) continue;
        RegisterMacro(rules, macros, envs, name, kinds, body);
        i = p;
    }
}

#pragma mark - TSSpellExclusions

@implementation TSSpellExclusions {
    NSString *_path;
    TSSpellRules *_rules;
    NSDate *_loadedModificationDate;
    NSNumber *_loadedSize;
    NSTimeInterval _lastCheck;
    NSUInteger _generation;
    NSString *_loadProblems;
}

+ (NSString *)userRulesPath
{
#ifdef TSSPELL_STANDALONE_TEST
    // Test builds (outside TeXShop) can point at another rules file.
    if (getenv("TSSPELL_RULES")) return [NSString stringWithUTF8String:getenv("TSSPELL_RULES")];
#endif
    return [[@"~/Library/TeXShop/SpellCheck/SpellingExclusions.txt" stringByExpandingTildeInPath] copy];
}

+ (NSString *)bundledRulesPath
{
    NSBundle *b = [NSBundle mainBundle];
    return [b pathForResource:@"SpellingExclusions" ofType:@"txt" inDirectory:@"TeXShop/SpellCheck"];
}

+ (void)installDefaultRulesIfNeeded
{
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *dest = [self userRulesPath];
    if ([fm fileExistsAtPath:dest]) return;
    NSString *source = [self bundledRulesPath];
    if (!source) return;
    [fm createDirectoryAtPath:[dest stringByDeletingLastPathComponent] withIntermediateDirectories:YES attributes:nil error:NULL];
    [fm copyItemAtPath:source toPath:dest error:NULL];
}

+ (TSSpellExclusions *)sharedExclusions
{
    static TSSpellExclusions *shared;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        [self installDefaultRulesIfNeeded];
        shared = [[TSSpellExclusions alloc] initWithRulesFile:[self userRulesPath]];
    });
    return shared;
}

- (instancetype)initWithRulesFile:(NSString *)path
{
    if ((self = [super init])) {
        _path = [path copy];
        [self load];
    }
    return self;
}

- (instancetype)initWithRulesText:(NSString *)text
{
    if ((self = [super init])) {
        _rules = ParseRules(text ?: @"");
    }
    return self;
}

- (NSString *)problems
{
    @synchronized (self) { return _loadProblems ?: _rules.problems; }
}

- (void)load
{
    NSError *error = nil;
    NSString *text = [NSString stringWithContentsOfFile:_path encoding:NSUTF8StringEncoding error:&error];
    NSDictionary *attrs = [[NSFileManager defaultManager] attributesOfItemAtPath:_path error:NULL];
    TSSpellRules *rules;
    if (text) {
        rules = ParseRules(text);
    } else {
        // No rules file: nothing is excluded (nothing is built in).
        rules = [[TSSpellRules alloc] init];
        rules.problems = [NSString stringWithFormat:@"Could not read %@\n", _path];
    }
    @synchronized (self) {
        _loadProblems = rules.problems;
        if (!_rules || !rules.problems.length) {
            _rules = rules;
            _generation++;
        }
        _loadedModificationDate = attrs[NSFileModificationDate];
        _loadedSize = attrs[NSFileSize];
    }

}

- (NSUInteger)generation { return _generation; }

- (BOOL)reloadIfChanged
{
    NSTimeInterval now = NSProcessInfo.processInfo.systemUptime;
    if (now - _lastCheck < 1) return NO;
    _lastCheck = now;
    if (!_path) return NO;
    NSDictionary *attrs = [[NSFileManager defaultManager] attributesOfItemAtPath:_path error:NULL];
    NSDate *date = attrs[NSFileModificationDate];
    NSNumber *size = attrs[NSFileSize];
    BOOL same;
    @synchronized (self) {
        same = (date == _loadedModificationDate || [date isEqual:_loadedModificationDate])
            && (size == _loadedSize || [size isEqual:_loadedSize]);
    }
    if (same) return NO;
    [self load];
    return YES;
}

- (NSArray<NSString *> *)commandsWithExcludedArguments
{
    TSSpellRules *rules;
    @synchronized (self) { rules = _rules; }
    return [[rules.skipArgs allKeys] sortedArrayUsingSelector:@selector(compare:)];
}

- (NSArray<NSString *> *)commandsWithCheckedArguments
{
    TSSpellRules *rules;
    @synchronized (self) { rules = _rules; }
    return [[rules.checkArgs allObjects] sortedArrayUsingSelector:@selector(compare:)];
}

- (TSSpellMask *)maskForText:(NSString *)text
{
    TSSpellRules *rules;
    @synchronized (self) { rules = _rules; }

    NSUInteger n = [text length];
    unichar *src = malloc((n + 1) * sizeof(unichar));
    unichar *out = malloc((n + 1) * sizeof(unichar));
    uint8_t *deleted = calloc(n + 1, 1);
    uint8_t *excluded = calloc(n + 1, 1);
    uint8_t *accent = calloc(n + 1, 1);
    uint8_t *language = calloc(n + 1, 1);
    [text getCharacters:src range:NSMakeRange(0, n)];
    memcpy(out, src, n * sizeof(unichar));

    NSMutableDictionary<NSString *, NSNumber *> *argCountCache = [NSMutableDictionary dictionary];
    NSMutableArray<NSString *> *languageNames = [NSMutableArray array];
    NSMutableDictionary<NSString *, TSSpellMacro *> *macros = [NSMutableDictionary dictionary];
    NSMutableSet<NSString *> *envs = [NSMutableSet set];
    if (rules.autoMacros) ScanDefinitions(rules, src, n, macros, envs);
    MaskState m = { src, out, deleted, excluded, accent, language, n, argCountCache, languageNames, macros, envs };
    RunMask(&m, rules);

    NSUInteger keep = 0;
    for (NSUInteger k = 0; k < n; k++) if (!deleted[k]) keep++;
    unichar *maskedChars = malloc((keep + 1) * sizeof(unichar));
    NSUInteger *origin = malloc((keep + 1) * sizeof(NSUInteger));
    NSMutableIndexSet *excludedSet = [NSMutableIndexSet indexSet];
    NSMutableIndexSet *accentSet = [NSMutableIndexSet indexSet];
    for (NSUInteger k = 0; k < n; k++) if (accent[k]) [accentSet addIndex:k];
    NSUInteger w = 0, runStart = NSNotFound;
    for (NSUInteger k = 0; k <= n; k++) {
        BOOL ex = (k < n) && excluded[k];
        if (ex && runStart == NSNotFound) runStart = k;
        if (!ex && runStart != NSNotFound) {
            [excludedSet addIndexesInRange:NSMakeRange(runStart, k - runStart)];
            runStart = NSNotFound;
        }
        if (k == n) break;
        if (deleted[k]) continue;
        maskedChars[w] = out[k];
        origin[w] = k;
        w++;
    }
    NSString *masked = [NSString stringWithCharacters:maskedChars length:keep];
    free(maskedChars); free(src); free(out); free(deleted); free(excluded); free(accent);
    if ([languageNames count] == 0) { free(language); language = NULL; }
    return [[TSSpellMask alloc] initWithMasked:masked origin:origin excluded:excludedSet accents:accentSet
                                      language:language languageNames:languageNames originalLength:n];
}

@end
