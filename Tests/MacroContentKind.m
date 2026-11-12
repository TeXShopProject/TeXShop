// SPDX-License-Identifier: GPL-2.0-or-later
// Table test for TSMacroContentKindForString(). The earlier inline predicate of
// -[TSMacroMenuController doMacro:] is kept below as the reference: every input
// must be classified as it was, except those on which it raised, which are now
// ordinary (not direct) AppleScript.
#import <Foundation/Foundation.h>
#import "TSMacroContentKind.h"

static int failures = 0;
static NSString *KindName(NSInteger kind)
{
	switch (kind) {
		case TSMacroContentKindTeX: return @"TeX";
		case TSMacroContentKindAppleScript: return @"AppleScript";
		case TSMacroContentKindAppleScriptDirect: return @"Direct";
		default: return @"Exception";
	}
}
static NSString *Shown(NSString *s)
{
	if (s == nil) return @"(nil)";
	NSMutableString *r = [NSMutableString string];
	for (NSUInteger i = 0; i < [s length]; i++) {
		unichar c = [s characterAtIndex:i];
		if (c == '\n') [r appendString:@"\\n"];
		else if (c == '\r') [r appendString:@"\\r"];
		else if (c == '\t') [r appendString:@"\\t"];
		else if (c < 0x20 || c > 0x7e) [r appendFormat:@"\\u%04X", c];
		else [r appendFormat:@"%C", c];
	}
	return [NSString stringWithFormat:@"\"%@\" (%lu)", r, (unsigned long)[s length]];
}

// The predicate as it was in doMacro: and validateMenuItem: before the shared function.
static const NSInteger OldException = -1;
static NSInteger OldKind(NSString *macroString)
{
	if ([macroString length] <14 ||
		(![[[macroString substringToIndex: 13] lowercaseString] isEqualToString:@"--applescript"]
		 && ![[[macroString substringToIndex: 14] lowercaseString] isEqualToString:@"-- applescript"]))
		return TSMacroContentKindTeX;
	@try {
		if (([macroString length] >= 20) &&
			( ([[[macroString substringToIndex: 20] lowercaseString] isEqualToString:@"--applescript direct"]) ||
			  ([[[macroString substringToIndex: 21] lowercaseString] isEqualToString:@"-- applescript direct"])))
			return TSMacroContentKindAppleScriptDirect;
	} @catch (NSException *e) {
		if (![[e name] isEqualToString:NSRangeException]) @throw;
		return OldException;
	}
	return TSMacroContentKindAppleScript;
}

static NSInteger NewKind(NSString *s)
{
	@try { return TSMacroContentKindForString(s); }
	@catch (NSException *e) { return OldException; }
}

static NSUInteger tableRaised = 0;
static void Expect(NSString *s, NSInteger expected)
{
	NSInteger got = NewKind(s), old = OldKind(s);
	if (old == OldException) {
		tableRaised++;
		if (expected != TSMacroContentKindAppleScript) { failures++; fprintf(stderr, "FAIL table %s used to raise; only AppleScript is allowed\n", Shown(s).UTF8String); }
	} else if (old != expected) {
		failures++;
		fprintf(stderr, "FAIL table %s: the earlier predicate gave %s, the table says %s\n", Shown(s).UTF8String, KindName(old).UTF8String, KindName(expected).UTF8String);
	}
	if (got != expected) {
		failures++;
		fprintf(stderr, "FAIL table %s: expected %s, got %s\n", Shown(s).UTF8String, KindName(expected).UTF8String, KindName(got).UTF8String);
	}
}

int main(void)
{
	@autoreleasepool {
		const NSInteger T = TSMacroContentKindTeX, A = TSMacroContentKindAppleScript, D = TSMacroContentKindAppleScriptDirect;
		NSUInteger tableCount = 0;
#define E(s, k) do { Expect((s), (k)); tableCount++; } while (0)
		// Missing contents and short strings.
		E(nil, T); E(@"", T); E(@"\\section{}", T);
		// Length 12-22 around "--applescript" (13) and "--applescript direct" (20).
		E(@"--applescrip", T);                 // 12
		E(@"--applescript", T);                // 13: shorter than 14, so TeX as before
		E(@"--applescript\n", A);              // 14
		E(@"--applescript ", A);               // 14
		E(@"--applescriptX", A);               // 14: only the first 13 characters count
		E(@"--applescript d", A);              // 15
		E(@"--applescript dire", A);           // 18
		E(@"--applescript direc", A);          // 19
		E(@"--applescript direct", D);         // 20
		E(@"--applescript direct\n", D);       // 21
		E(@"--applescript directx", D);        // 21: prefix match, as before
		E(@"--applescript direct\ntell", D);   // 25
		E(@"--applescript directo", D);        // 21
		E(@"--applescriptdirect\n", A);        // 20: used to raise NSRangeException
		E(@"--applescript abcdef", A);         // 20: used to raise NSRangeException
		E(@"--applescript  direct", A);        // 21: two spaces
		E(@"--applescript\tdirect", A);        // 20: tab; used to raise NSRangeException
		E(@"--applescript\ndirect", A);        // 20: line break; used to raise NSRangeException
		// Length 12-22 around "-- applescript" (14) and "-- applescript direct" (21).
		E(@"-- applescri", T);                 // 12
		E(@"-- applescrip", T);                // 13
		E(@"-- applescript", A);               // 14
		E(@"-- applescript\n", A);             // 15
		E(@"-- applescript\r\n", A);           // 16
		E(@"-- applescript dir", A);           // 18
		E(@"-- applescript dire", A);          // 19
		E(@"-- applescript direc", A);         // 20: used to raise NSRangeException
		E(@"-- applescript\nabcde", A);        // 20: used to raise NSRangeException
		E(@"-- applescriptdirect", A);         // 20: used to raise NSRangeException
		E(@"-- APPLESCRIPT DIREC", A);         // 20: used to raise NSRangeException
		E(@"-- applescript direct", D);        // 21
		E(@"-- applescript direct\n", D);      // 22
		E(@"-- applescript directs", D);       // 22
		E(@"-- applescript  direct", A);       // 22: two spaces
		E(@"--  applescript direct", T);       // 22: two spaces after the dashes
		// Case.
		E(@"--AppleScript", T);                // 13
		E(@"--AppleScript\n", A);
		E(@"--APPLESCRIPT DIRECT", D);
		E(@"-- AppleScript Direct\nbeep", D);
		E(@"-- APPLESCRIPT\nbeep", A);
		E(@"-- ApPlEsCrIpT dIrEcT", D);
		// Leading white space, line breaks and other characters before the header.
		E(@" --applescript direct", T);
		E(@" -- applescript direct", T);
		E(@"\t-- applescript", T);
		E(@"\n-- applescript direct", T);
		E(@"\r\n--applescript direct", T);
		E(@"\uFEFF-- applescript direct", T);  // byte order mark
		E(@"%-- applescript direct", T);
		E(@"- applescript direct", T);
		E(@"\u2014 applescript direct", T);    // em dash
		E(@"--appIescript direct", T);         // capital i instead of l
		E(@"-- applescript\u00A0direct", A);   // no-break space before direct
		// Line endings right after the header.
		E(@"--applescript\r\ntell application \"Finder\"", A);
		E(@"--applescript direct\r\nbeep", D);
		E(@"-- applescript direct\rbeep", D);
		E(@"-- applescript\u2028direct", A);
#undef E

		// Every truncation (length 0-26) of a set of seeds in three cases must match
		// the earlier predicate, except where that raised.
		NSArray *seeds = @[@"--applescript direct\nbeep\n", @"-- applescript direct\nbeep\n",
						   @"--applescript\ndirect\nbeep\n", @"-- applescript\ndirect\nbeep\n",
						   @"-- applescript direc\nbeep\n", @"-- applescriptdirect\nbeep\n",
						   @"-- applescript  direct beep", @" -- applescript direct beep",
						   @"--applescriptdirect\nbeep\n", @"\\documentclass{article}\n",
						   @"-- applescript\r\ndirect\r\nbeep", @"--applescript direct\r\nbeep"];
		NSMutableOrderedSet *inputs = [NSMutableOrderedSet orderedSet];
		for (NSString *seed in seeds)
			for (NSString *variant in @[seed, [seed uppercaseString], [seed capitalizedString]])
				for (NSUInteger n = 0; n <= MIN((NSUInteger)26, [variant length]); n++)
					[inputs addObject:[variant substringToIndex:n]];
		NSUInteger same = 0, raised = 0;
		for (NSString *s in inputs) {
			NSInteger old = OldKind(s), now = NewKind(s);
			if (old == OldException) {
				raised++;
				// Any AppleScript header of exactly 20 characters other than "--applescript direct".
				BOOL boundary = [s length] == 20;
				if (!boundary) { failures++; fprintf(stderr, "FAIL the earlier predicate raised on an unexpected input %s\n", Shown(s).UTF8String); }
				if (now != TSMacroContentKindAppleScript) { failures++; fprintf(stderr, "FAIL %s used to raise and must now be AppleScript, got %s\n", Shown(s).UTF8String, KindName(now).UTF8String); }
			} else if (old != now) {
				failures++;
				fprintf(stderr, "FAIL %s changed from %s to %s\n", Shown(s).UTF8String, KindName(old).UTF8String, KindName(now).UTF8String);
			} else
				same++;
		}
		if (raised == 0) { failures++; fprintf(stderr, "FAIL no input reached the earlier exception\n"); }

		// The bundled macros keep their kinds.
		NSUInteger bundled = 0, bundledApple = 0, bundledDirect = 0;
		NSArray *args = [[NSProcessInfo processInfo] arguments];
		for (NSUInteger i = 1; i < [args count]; i++) {
			NSMutableArray *stack = [NSMutableArray arrayWithObject:[NSDictionary dictionaryWithContentsOfFile:args[i]] ?: @{}];
			while ([stack count]) {
				NSDictionary *item = [stack lastObject]; [stack removeLastObject];
				for (NSDictionary *child in item[@"submenu"]) [stack addObject:child];
				NSString *content = item[@"content"];
				if (![content isKindOfClass:[NSString class]]) continue;
				bundled++;
				NSInteger old = OldKind(content), now = NewKind(content);
				if (now == A) bundledApple++;
				if (now == D) bundledDirect++;
				if (old != now) { failures++; fprintf(stderr, "FAIL bundled macro %s: %s -> %s\n", [item[@"name"] UTF8String], KindName(old).UTF8String, KindName(now).UTF8String); }
			}
		}
		if ([args count] > 1 && bundled == 0) { failures++; fprintf(stderr, "FAIL no bundled macros were read\n"); }

		if (failures) { fprintf(stderr, "FAIL %d failure(s)\n", failures); return 1; }
		printf("PASS %lu table rows (%lu used to raise); %lu truncations unchanged, %lu former exceptions now AppleScript; %lu bundled macros unchanged (%lu AppleScript, %lu direct)\n",
			   (unsigned long)tableCount, (unsigned long)tableRaised, (unsigned long)same, (unsigned long)raised, (unsigned long)bundled, (unsigned long)bundledApple, (unsigned long)bundledDirect);
	}
	return 0;
}
