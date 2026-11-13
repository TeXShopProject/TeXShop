// SPDX-License-Identifier: GPL-2.0-or-later
#import "TSSyntaxHighlighter.h"

// More than the number of roles; looked up once per role while a range is colored.
enum { TSSyntaxRoleCacheSize = 64 };

@implementation TSSyntaxHighlighter

- (instancetype)initWithTextView:(NSTextView *)textView scanner:(id<TSSyntaxScanner>)scanner scheme:(TSSyntaxColorScheme *)scheme
{
    if ((self = [super init])) {
        _textView = textView;
        _scanner = scanner;
        _scheme = scheme;
    }
    return self;
}

- (void)applyTokensInRange:(NSRange)range
{
    NSTextView *textView = self.textView;
    NSLayoutManager *layoutManager = textView.layoutManager;
    if (!textView || !layoutManager)
        return;
    TSSyntaxColorScheme *scheme = self.scheme;
    __unsafe_unretained NSDictionary<NSAttributedStringKey, id> *roles[TSSyntaxRoleCacheSize] = {nil};
    __unsafe_unretained NSDictionary<NSAttributedStringKey, id> **cache = roles;
    [self.scanner enumerateTokensInString:textView.string range:range usingBlock:^(NSRange token, TSSyntaxRole role, TSSyntaxTokenFlags flags) {
        if (role != TSSyntaxRoleNone) {
            NSDictionary<NSAttributedStringKey, id> *attributes;
            if (role >= 0 && role < TSSyntaxRoleCacheSize) {
                if (!cache[role])
                    cache[role] = [scheme attributesForRole:role];
                attributes = cache[role];
            } else
                attributes = [scheme attributesForRole:role];
            if (attributes.count)
                [layoutManager addTemporaryAttributes:attributes forCharacterRange:token];
        }
        if (flags & TSSyntaxTokenFlagsNoSpellCheck)
            [textView setSpellingState:0 range:token];
    }];
}

@end
