#!/usr/bin/env python3
# Text split off a comment line by a line break must lose the comment color.
# The test compiles the range computation of -[TSDocument fixColor::] with a
# small colorizer that, like colorizeText:range:, first clears the color of
# whole lines and then colors comments again. The edits are made through a
# real NSLayoutManager, whose temporary attributes move with the text.
from pathlib import Path
import shutil
import subprocess
import tempfile

root = Path(__file__).resolve().parent.parent
source = (root / 'Sources/Editor/TSDocument-Syntax.m').read_text()
method = source.index('- (void)fixColor: (NSUInteger)from : (NSUInteger)to')
start = source.index('\tif (from >= length)', method)
end = source.index('\tcolorRange.location = from;', start)
block = source[start:end]

program = r'''
#import <Cocoa/Cocoa.h>

static NSRange FixColorRange(NSUInteger from, NSUInteger to, NSUInteger length) {
BLOCK
    return NSMakeRange(from, to - from);
}

static NSDictionary *comment;

// Mirrors colorizeText:range: for comments: whole lines are reset, then
// everything from the first % to the end of its line is colored. Unlike the
// real parser, this ignores escaped percent signs, which these texts lack.
static void Colorize(NSLayoutManager *manager, NSRange range) {
    NSString *text = manager.textStorage.string;
    NSUInteger lineStart, lineEnd;
    [text getLineStart:&lineStart end:&lineEnd contentsEnd:NULL forRange:range];
    [manager removeTemporaryAttribute:NSForegroundColorAttributeName
                    forCharacterRange:NSMakeRange(lineStart, lineEnd - lineStart)];
    NSUInteger location = lineStart;
    while (location < lineEnd) {
        NSUInteger start, end, contentsEnd;
        [text getLineStart:&start end:&end contentsEnd:&contentsEnd forRange:NSMakeRange(location, 0)];
        NSRange percent = [text rangeOfString:@"%" options:0 range:NSMakeRange(start, contentsEnd - start)];
        if (percent.location != NSNotFound)
            [manager addTemporaryAttributes:comment
                          forCharacterRange:NSMakeRange(percent.location, contentsEnd - percent.location)];
        location = end;
    }
}

// Applies an edit the way the editor does: the change is recorded in
// textView:shouldChangeTextInRange:replacementString:, then fixColor:: runs.
static void Edit(NSLayoutManager *manager, NSRange range, NSString *replacement) {
    NSUInteger colorStart = range.location;
    NSUInteger colorEnd = colorStart + replacement.length;
    [manager.textStorage replaceCharactersInRange:range withString:replacement];
    NSUInteger length = manager.textStorage.length;
    if (length == 0)
        return;
    Colorize(manager, FixColorRange(colorStart, colorEnd, length));
}

static BOOL IsComment(NSLayoutManager *manager, NSString *word) {
    NSRange range = [manager.textStorage.string rangeOfString:word options:NSBackwardsSearch];
    NSDictionary *attributes = [manager temporaryAttributesAtCharacterIndex:range.location effectiveRange:NULL];
    return attributes[NSForegroundColorAttributeName] != nil;
}

static int failures;
static void Expect(BOOL condition, const char *message) {
    if (!condition) {
        fprintf(stderr, "FAIL: %s\n", message);
        failures++;
    }
}

// A layout manager does not retain its text storage, so keep each one alive.
static NSMutableArray *storages;

static NSLayoutManager *Manager(NSString *text) {
    NSTextStorage *storage = [[NSTextStorage alloc] initWithString:text];
    [storages addObject:storage];
    NSLayoutManager *manager = [NSLayoutManager new];
    [storage addLayoutManager:manager];
    NSTextContainer *container = [[NSTextContainer alloc] initWithSize:NSMakeSize(400, 1e7)];
    [manager addTextContainer:container];
    Colorize(manager, NSMakeRange(0, storage.length));
    return manager;
}

int main(void) {
    @autoreleasepool {
        comment = @{NSForegroundColorAttributeName: NSColor.redColor};
        storages = [NSMutableArray array];

        // The report: "% one two", two empty lines, then return between the words.
        NSLayoutManager *manager = Manager(@"% one two\n\n");
        Expect(IsComment(manager, @"two"), "two starts as comment text");
        NSUInteger split = [manager.textStorage.string rangeOfString:@" two"].location;
        Edit(manager, NSMakeRange(split, 0), @"\n");
        Expect(!IsComment(manager, @"two"), "two is not a comment after one return");
        Expect(IsComment(manager, @"one"), "one stays a comment");
        Edit(manager, NSMakeRange(split, 0), @"\n");
        Expect(!IsComment(manager, @"two"), "two is not a comment after a second return");

        // Pasting text that ends with a line break inside a comment.
        manager = Manager(@"% alpha beta\n");
        split = [manager.textStorage.string rangeOfString:@"beta"].location;
        Edit(manager, NSMakeRange(split, 0), @"gamma\n");
        Expect(!IsComment(manager, @"beta"), "beta is not a comment after a paste ending in a line break");
        Expect(IsComment(manager, @"gamma"), "gamma pasted inside the comment is a comment");

        // Joining the lines again makes the text a comment again.
        manager = Manager(@"% one\ntwo\n");
        Expect(!IsComment(manager, @"two"), "two starts as ordinary text");
        Edit(manager, NSMakeRange(5, 1), @"");
        Expect(IsComment(manager, @"two"), "two becomes a comment when the line break is deleted");

        // A line break at the very end of the text.
        manager = Manager(@"% one");
        Edit(manager, NSMakeRange(5, 0), @"\n");
        Expect(IsComment(manager, @"one"), "one stays a comment after a final line break");

        // Typing at the end of the text, and an edit past its end, stay within it.
        NSRange range = FixColorRange(3, 3, 3);
        Expect(NSMaxRange(range) <= 3, "edit at the end stays within the text");
        range = FixColorRange(7, 9, 5);
        Expect(NSMaxRange(range) <= 5 && range.location <= 4, "an edit past the end is clipped");

        if (failures)
            return 1;
        puts("PASS: comment color after line breaks (10 checks)");
    }
    return 0;
}
'''.replace('BLOCK', block)

temporary = Path(tempfile.mkdtemp(prefix='texshop-comment-color.'))
try:
    (temporary / 'test.m').write_text(program)
    subprocess.run(['xcrun', 'clang', '-fobjc-arc', '-framework', 'Cocoa',
                    str(temporary / 'test.m'), '-o', str(temporary / 'test')], check=True)
    subprocess.run([str(temporary / 'test')], check=True)
finally:
    shutil.rmtree(temporary)
