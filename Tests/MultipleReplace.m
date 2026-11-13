// SPDX-License-Identifier: GPL-2.0-or-later
// Multiple replacement: the library of sets, applying a set, the rule table, the window and the Find menu's items,
// the window's layout in every language and its images. Built by Tests/run-multiple-replace.py; nothing is shown and
// the defaults stay in memory.
#import "TestAppKitIsolation.h"
#import "TSAdvancedFindController+MultipleReplace.h"
#import "TSMultipleReplaceMenu.h"
#import "TSAdvancedFindTextView.h"
#import "TSAdvancedFindHighlights.h"
#import "TSMultipleReplaceWindowController.h"
#import "TSAdvancedFindHighlights.h"
#import "TSAdvancedFindOptionsForm.h"

static int failures;

static void Check(BOOL ok, NSString *name)
{
    if (!ok) {
        printf("FAIL %s\n", name.UTF8String);
        failures++;
    }
}

static TSAdvancedFindController *MakeController(NSUInteger *beeps)
{
    TSAdvancedFindSettings *settings = [[TSAdvancedFindSettings alloc] initWithDefaults:[TSMemoryDefaults new] findPasteboard:[NSPasteboard pasteboardWithUniqueName]];
    TSAdvancedFindController *controller = [[TSAdvancedFindController alloc] initWithSettings:settings];
    controller.beepHandler = ^{ if (beeps) (*beeps)++; };
    controller.lineEndingHandler = ^NSString *(NSTextView *view) { return @"\n"; };
    return controller;
}

static TSRegexReplacementRule *Rule(NSString *find, NSString *replace, BOOL regex, BOOL enabled)
{
    return [[TSRegexReplacementRule alloc] initWithFindString:find replaceString:replace usesRegularExpression:regex ignoresCase:NO enabled:enabled note:nil];
}

static TSRegexMultipleReplace *Set(NSArray<TSRegexReplacementRule *> *rules)
{
    return [[TSRegexMultipleReplace alloc] initWithRules:rules textualOptions:TSRegexMultipleReplace.defaultTextualOptions
                                regularExpressionOptions:TSRegexMultipleReplace.defaultRegularExpressionOptions replacementSyntax:TSRegexReplacementSyntaxICU];
}

static NSURL *TemporaryLibraryDirectory(void)
{
    NSURL *directory = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString] isDirectory:YES];
    return [directory URLByAppendingPathComponent:@"MultipleReplace" isDirectory:YES];
}

static NSTextView *MakeView(NSString *text)
{
    NSTextView *view = [[NSTextView alloc] initWithFrame:NSMakeRect(0, 0, 300, 80)];
    view.allowsUndo = YES;
    view.richText = NO;
    NSWindow *window = [[NSWindow alloc] initWithContentRect:view.frame styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:YES];
    window.contentView = view;
    [window makeFirstResponder:view];
    view.string = text;
    return view;
}

/// One user action is one undo group, as in the application.
static TSRegexMultipleReplaceResult *Apply(TSAdvancedFindController *controller, TSRegexMultipleReplace *set, NSTextView *view, BOOL inSelection)
{
    NSUndoManager *undo = view.undoManager;
    undo.groupsByEvent = NO;
    [undo beginUndoGrouping];
    TSRegexMultipleReplaceResult *result = [controller applyMultipleReplace:set inTextView:view inSelection:inSelection];
    [undo endUndoGrouping];
    return result;
}

static void TestLibrary(NSURL *directory)
{
    TSMultipleReplaceLibrary *library = [[TSMultipleReplaceLibrary alloc] initWithDirectory:directory];
    library.usesTrash = NO;
    Check(library.setNames.count == 0 && ![NSFileManager.defaultManager fileExistsAtPath:directory.path], @"no folder and no set at first; nothing is written");
    Check([TSMultipleReplaceLibrary.fileExtension isEqualToString:@"json"], @"sets are CotEditor replacement definitions in .json files");
    // A set reads back the same: rules, both kinds of options and the replacement syntax.
    TSRegexReplacementRule *noted = [[TSRegexReplacementRule alloc] initWithFindString:@"(\\w+)\t¥" replaceString:@"\\1\n" usesRegularExpression:YES
                                                                             ignoresCase:YES enabled:NO note:@"メモ"];
    TSRegexMultipleReplace *full = [[TSRegexMultipleReplace alloc] initWithRules:@[noted, Rule(@"a", @"b", NO, YES)]
        textualOptions:TSRegexMultipleReplace.defaultTextualOptions | TSRegexFindWholeWord
        regularExpressionOptions:TSRegexMultipleReplace.defaultRegularExpressionOptions | TSRegexFindDotMatchesLineSeparators
        replacementSyntax:TSRegexReplacementSyntaxOgreKit];
    Check([library saveSet:full named:@"Round trip" error:NULL], @"save a set");
    TSRegexMultipleReplace *loaded = [library setNamed:@"Round trip" error:NULL];
    Check([loaded.rules isEqualToArray:full.rules] && loaded.textualOptions == full.textualOptions
          && loaded.regularExpressionOptions == full.regularExpressionOptions && loaded.replacementSyntax == TSRegexReplacementSyntaxOgreKit,
          @"a saved set reads back the same: rules, options and replacement syntax");
    Check([[NSFileManager.defaultManager contentsOfDirectoryAtPath:directory.path error:NULL] isEqualToArray:@[@"Round trip.json"]], @"one file per set, named after the set");
    Check([library removeSetNamed:@"Round trip" error:NULL] && library.setNames.count == 0, @"remove a set");
    // A broken file in the folder: listed, but reading it gives an error instead of a set.
    [@"{ not json" writeToURL:[directory URLByAppendingPathComponent:@"Broken.json"] atomically:YES encoding:NSUTF8StringEncoding error:NULL];
    [full.JSONData writeToURL:[directory URLByAppendingPathComponent:@"CotEditor.cotrpl"] atomically:YES];
    [@"ignored" writeToURL:[directory URLByAppendingPathComponent:@"notes.txt"] atomically:YES encoding:NSUTF8StringEncoding error:NULL];
    NSError *brokenError = nil;
    Check([library.setNames isEqualToArray:@[@"Broken"]] && ![library setNamed:@"Broken" error:&brokenError] && brokenError, @"a broken set is listed and reports an error; other files, a .cotrpl among them, are not sets of the folder");
    [NSFileManager.defaultManager removeItemAtURL:[directory URLByAppendingPathComponent:@"CotEditor.cotrpl"] error:NULL];
    [library removeSetNamed:@"Broken" error:NULL];

    TSRegexMultipleReplace *set = Set(@[Rule(@"a", @"b", NO, YES)]);
    Check([library saveSet:set named:@"X" error:NULL] && [[library availableNameForName:@"X"] isEqualToString:@"X 2"]
          && [[library availableNameForName:@"x"] isEqualToString:@"x 2"], @"a taken name gets a number");
    [library saveSet:set named:@"Y" error:NULL];
    NSError *error = nil;
    Check(![library renameSetNamed:@"X" to:@"Y" error:&error] && [error.domain isEqualToString:TSRegexFindErrorDomain] && [library setNamed:@"X" error:NULL],
          @"renaming onto another set is refused with our own message, and both are kept");
    Check([library renameSetNamed:@"X" to:@"x" error:NULL] && [library.setNames containsObject:@"x"] && ![library.setNames containsObject:@"X"], @"a change of case is a rename");
    for (NSString *bad in @[@"", @".hidden", @"a/b", @"a:b", @" lead", @"trail "])
        Check(![TSMultipleReplaceLibrary isValidName:bad], [@"not a name: " stringByAppendingString:bad]);
    for (NSString *bad in @[@"a/b", @".hidden", @" lead", @"trail "]) {
        NSError *badError = nil;
        Check(![library saveSet:set named:bad error:&badError] && badError, [@"a set is not saved under a bad name: " stringByAppendingString:bad]);
    }
    Check(![NSFileManager.defaultManager fileExistsAtPath:[directory URLByAppendingPathComponent:@".hidden.cotrpl"].path], @"no file for a bad name");

    NSURL *tsv = [directory.URLByDeletingLastPathComponent URLByAppendingPathComponent:@"pairs.txt"];
    [@"alpha\tα\nbeta\tβ\nno tab\n" writeToURL:tsv atomically:YES encoding:NSUTF8StringEncoding error:NULL];
    NSString *imported = [library importFileAtURL:tsv error:NULL];
    Check([imported isEqualToString:@"pairs"] && [library setNamed:@"pairs" error:NULL].rules.count == 2, @"import tab-separated text");
    NSURL *exported = [directory.URLByDeletingLastPathComponent URLByAppendingPathComponent:@"pairs.cotrpl"];
    Check([library exportSetNamed:@"pairs" toURL:exported error:NULL], @"export a set");
    NSString *again = [library importFileAtURL:exported error:NULL];
    Check([again isEqualToString:@"pairs 2"] && [[library setNamed:@"pairs 2" error:NULL].rules isEqualToArray:[library setNamed:@"pairs" error:NULL].rules], @"import an exported definition under a new name");
    // CotEditor's .cotrpl and a .json are read as definitions; a file whose name cannot be a set's gets a fallback name.
    NSURL *cotrpl = [directory.URLByDeletingLastPathComponent URLByAppendingPathComponent:@"From CotEditor.cotrpl"];
    [full.JSONData writeToURL:cotrpl atomically:YES];
    Check([[library importFileAtURL:cotrpl error:NULL] isEqualToString:@"From CotEditor"]
          && [[library setNamed:@"From CotEditor" error:NULL].rules isEqualToArray:full.rules], @"import CotEditor's .cotrpl as a definition");
    NSURL *badName = [directory.URLByDeletingLastPathComponent URLByAppendingPathComponent:@" lead.json"];
    [full.JSONData writeToURL:badName atomically:YES];
    NSString *fallback = TSAdvancedFindLocalized(@"MultipleReplace.Imported", @"Imported");
    Check(![fallback isEqualToString:@"MultipleReplace.Imported"] && [[library importFileAtURL:badName error:NULL] isEqualToString:fallback]
          && [[library importFileAtURL:badName error:NULL] isEqualToString:[fallback stringByAppendingString:@" 2"]],
          @"a file whose name cannot be a set's is imported under the localized fallback name, then with a number");
    NSURL *broken = [directory.URLByDeletingLastPathComponent URLByAppendingPathComponent:@"broken.cotrpl"];
    [@"{\"replacements\": 3}" writeToURL:broken atomically:YES encoding:NSUTF8StringEncoding error:NULL];
    error = nil;
    Check(![library importFileAtURL:broken error:&error] && error, @"a broken definition is refused with an error");
}

static void TestApplying(void)
{
    NSUInteger beeps = 0;
    TSAdvancedFindController *controller = MakeController(&beeps);

    NSString *text = @"Header line\n{\\bf 太字}、{\\it 斜体}。\nFooter";
    NSTextView *view = MakeView(text);
    NSColor *foreign = NSColor.systemPinkColor;
    [view.layoutManager addTemporaryAttribute:NSBackgroundColorAttributeName value:foreign forCharacterRange:NSMakeRange(0, 6)];
    [view.layoutManager addTemporaryAttribute:NSBackgroundColorAttributeName value:foreign forCharacterRange:NSMakeRange(text.length - 6, 6)];
    TSRegexMultipleReplace *set = Set(@[
        Rule(@"\\{\\\\bf\\s+([^}]*)\\}", @"\\\\textbf{$1}", YES, YES),
        Rule(@"\\{\\\\it\\s+([^}]*)\\}", @"\\\\textit{$1}", YES, YES),
        Rule(@"、", @"，", NO, YES),
        Rule(@"(", @"x", YES, YES),       // invalid: skipped
        Rule(@"。", @"．", NO, NO),       // disabled
    ]);
    TSRegexMultipleReplaceResult *result = Apply(controller, set, view, NO);
    Check([view.string isEqualToString:@"Header line\n\\textbf{太字}，\\textit{斜体}。\nFooter"], [@"rules run in order: " stringByAppendingString:view.string]);
    Check([result.counts isEqualToArray:@[@1, @1, @1, @0, @0]] && result.errors.count == 1 && result.errors[@3], @"counts per rule; the invalid rule is reported");
    Check([view.layoutManager temporaryAttribute:NSBackgroundColorAttributeName atCharacterIndex:0 effectiveRange:NULL] == foreign
          && [view.layoutManager temporaryAttribute:NSBackgroundColorAttributeName atCharacterIndex:view.string.length - 1 effectiveRange:NULL] == foreign,
          @"only the changed part is replaced: the text around it keeps its attributes");
    [view.undoManager undo];
    Check([view.string isEqualToString:text], @"one undo restores the text");

    view.string = @"a、b、c、d";
    view.selectedRanges = @[[NSValue valueWithRange:NSMakeRange(2, 3)]];
    result = Apply(controller, Set(@[Rule(@"、", @"，，", NO, YES)]), view, YES);
    Check([view.string isEqualToString:@"a、b，，c、d"] && NSEqualRanges(view.selectedRange, NSMakeRange(2, 4)), @"in selection, the selection follows the replacement");
    beeps = 0;
    result = Apply(controller, Set(@[Rule(@"z", @"y", NO, YES)]), view, NO);
    Check(result.totalCount == 0 && beeps == 1, @"nothing to replace beeps");

    view.string = @"x1 y2 x3";
    NSUInteger count = [controller highlightMultipleReplace:Set(@[Rule(@"x\\d", @"", YES, YES), Rule(@"y", @"", NO, YES)]) inTextView:view inSelection:NO];
    NSArray<NSValue *> *ranges = [TSAdvancedFindHighlights existingHighlightsForTextStorage:view.textStorage].ranges;
    Check(count == 3 && ranges.count == 3 && ranges[1].rangeValue.location == 3, @"highlight the matches of every rule, sorted");

    NSDictionary<NSNumber *, NSError *> *problems = TSMultipleReplaceProblems(Set(@[Rule(@"", @"a", NO, YES), Rule(@"[", @"", YES, YES), Rule(@"[", @"", NO, YES), Rule(@"(", @"", YES, NO)]));
    Check(problems.count == 2 && problems[@0] && problems[@1], @"an empty find string and an invalid pattern are problems; plain text and disabled rules are not");
    view.editable = NO;
    beeps = 0;
    Check([controller applyMultipleReplace:Set(@[Rule(@"x", @"y", NO, YES)]) inTextView:view inSelection:NO] == nil && beeps == 1
          && [view.string isEqualToString:@"x1 y2 x3"], @"a read-only text view takes no multiple replacement");
}

static void TestRuleTable(void)
{
    TSMultipleReplaceRuleTable *table = [TSMultipleReplaceRuleTable new];
    __block TSRegexMultipleReplace *changed = nil;
    table.setChangedHandler = ^(TSRegexMultipleReplace *set) { changed = set; };
    table.set = Set(@[Rule(@"a", @"1", NO, YES), Rule(@"b", @"2", NO, YES), Rule(@"c", @"3", NO, YES), Rule(@"d", @"4", NO, YES)]);
    Check(table.tableView.numberOfRows == 4, @"one row per rule");
    [table moveRulesAtIndexes:[NSIndexSet indexSetWithIndex:3] toRow:0];
    Check([[changed.rules valueForKey:@"findString"] isEqualToArray:@[@"d", @"a", @"b", @"c"]], @"drag the last rule to the top");
    NSMutableIndexSet *two = [NSMutableIndexSet indexSetWithIndex:0];
    [two addIndex:2];
    [table moveRulesAtIndexes:two toRow:4];
    Check([[changed.rules valueForKey:@"findString"] isEqualToArray:@[@"a", @"c", @"d", @"b"]], @"drag two rules to the end");
    [table moveRulesAtIndexes:[NSIndexSet indexSetWithIndex:0] toRow:2];
    Check([[changed.rules valueForKey:@"findString"] isEqualToArray:@[@"c", @"a", @"d", @"b"]], @"drag the first rule below the second");
    [table moveRulesAtIndexes:[NSIndexSet indexSetWithIndex:1] toRow:0];
    [table.tableView selectRowIndexes:[NSIndexSet indexSetWithIndex:1] byExtendingSelection:NO];
    [table removeSelectedRules];
    Check([[changed.rules valueForKey:@"findString"] isEqualToArray:@[@"a", @"d", @"b"]], @"remove the selected rule");
    [table.tableView selectRowIndexes:[NSIndexSet indexSetWithIndex:0] byExtendingSelection:NO];
    [table addRule];
    Check(changed.rules.count == 4 && changed.rules[1].findString.length == 0, @"a new rule goes after the selection");
    [table replaceRuleAtIndex:0 withRule:Rule(@"a", @"1", YES, NO)];
    Check(changed.rules[0].usesRegularExpression && !changed.rules[0].enabled, @"editing a rule keeps the rest");
    table.counts = @[@2, @0, @1, @0];
    TSRegexMultipleReplace *before = changed;
    table.set = before;
    Check(table.counts == nil, @"a changed set clears the counts of the last run");
    // Before anything is applied, a rule that cannot be used shows ⚠︎ with the reason in the count column.
    table.set = Set(@[Rule(@"ok", @"", NO, YES), Rule(@"(", @"", YES, YES), Rule(@"", @"x", NO, YES), Rule(@"(", @"", YES, NO)]);
    NSTableColumn *countColumn = [table.tableView tableColumnWithIdentifier:@"count"];
    NSMutableArray<NSString *> *marks = [NSMutableArray array];
    for (NSInteger row = 0; row < 4; row++) {
        NSTextField *cell = (NSTextField *)[table tableView:table.tableView viewForTableColumn:countColumn row:row];
        [marks addObject:[cell.stringValue isEqualToString:@"⚠︎"] && cell.toolTip.length > 0 ? @"!" : @"-"];
    }
    Check([marks isEqualToArray:@[@"-", @"!", @"!", @"-"]], [@"⚠︎ on the invalid and the empty rule only: " stringByAppendingString:[marks componentsJoinedByString:@""]]);
    table.set = before;
    // The cells are plain unless a styler colors them (the place for the coloring of the fields).
    NSTableColumn *findColumn = [table.tableView tableColumnWithIdentifier:@"find"];
    NSTextField *plain = (NSTextField *)[table tableView:table.tableView viewForTableColumn:findColumn row:0];
    Check([plain.attributedStringValue attribute:NSForegroundColorAttributeName atIndex:0 effectiveRange:NULL] != NSColor.systemPinkColor, @"plain cells");
    table.fieldStyler = ^NSAttributedString *(NSString *string, TSRegexReplacementRule *rule, TSMultipleReplaceRuleField field, TSRegexFindOptions options, NSDictionary *attributes) {
        NSMutableDictionary *pink = [attributes mutableCopy];
        pink[NSForegroundColorAttributeName] = NSColor.systemPinkColor;
        return field == TSMultipleReplaceRuleFieldFind ? [[NSAttributedString alloc] initWithString:string attributes:pink] : nil;
    };
    NSTextField *styled = (NSTextField *)[table tableView:table.tableView viewForTableColumn:findColumn row:0];
    NSTextField *replacement = (NSTextField *)[table tableView:table.tableView viewForTableColumn:[table.tableView tableColumnWithIdentifier:@"replace"] row:0];
    Check([styled.attributedStringValue attribute:NSForegroundColorAttributeName atIndex:0 effectiveRange:NULL] == NSColor.systemPinkColor
          && [replacement.stringValue isEqualToString:changed.rules[0].replaceString], @"the styler colors a field; a nil result leaves it plain");
}

static void TestOptionsForm(void)
{
    // A set's rules choose their own kind, so both sections stay changeable whatever the panel would do.
    TSAdvancedFindOptionsForm *form = [[TSAdvancedFindOptionsForm alloc] initWithStyle:TSAdvancedFindOptionsFormStyleSet textualOptions:0
                                                                regularExpressionOptions:TSRegexFindRegularExpression replacementSyntax:TSRegexReplacementSyntaxOgreKit];
    form.usesRegularExpression = YES;
    NSUInteger text = 0, unescapes = 0;
    for (NSView *v in form.view.arrangedSubviews)
        if ([v isKindOfClass:[NSButton class]] && ((NSButton *)v).enabled) {
            text += [v.identifier isEqualToString:@"text"];
            unescapes += [v.identifier isEqualToString:@"unescapes"];
        }
    Check(text == 5, @"a set's text options can always be changed");
    Check(unescapes == 0, @"unescaping belongs to the ICU syntax only");
    TSAdvancedFindOptionsForm *panel = [[TSAdvancedFindOptionsForm alloc] initWithStyle:TSAdvancedFindOptionsFormStylePanel textualOptions:0
                                                                 regularExpressionOptions:TSRegexFindRegularExpression replacementSyntax:TSRegexReplacementSyntaxICU];
    text = 0;
    for (NSView *v in panel.view.arrangedSubviews)
        text += [v isKindOfClass:[NSButton class]] && ((NSButton *)v).enabled && [v.identifier isEqualToString:@"text"];
    Check(text == 0, @"in the panel, text options wait while regular expressions are on");
}

static void TestWindow(NSURL *directory)
{
    TSMultipleReplaceLibrary *library = [[TSMultipleReplaceLibrary alloc] initWithDirectory:directory];
    library.usesTrash = NO;
    [library saveSet:Set(@[Rule(@"cat", @"dog", NO, YES), Rule(@"(", @"", YES, YES)]) named:@"A" error:NULL];
    [library saveSet:Set(@[Rule(@"dog", @"bird", NO, YES)]) named:@"B" error:NULL];
    TSAdvancedFindController *controller = MakeController(NULL);
    TSMultipleReplaceWindowController *window = [[TSMultipleReplaceWindowController alloc] initWithFindController:controller library:library];
    Check([window.selectedSetName isEqualToString:@"A"] && window.ruleTable.set.rules.count == 2, @"the first set is shown");
    NSTextView *view = MakeView(@"cat cat");
    view.undoManager.groupsByEvent = NO;
    [view.undoManager beginUndoGrouping]; // one group for the window's runs; they are not undone here
    Check([window replaceAllInTextView:view] && [view.string isEqualToString:@"dog dog"], @"replace all runs the shown set");
    Check([window.ruleTable.counts isEqualToArray:@[@2, @0]], @"the table shows the counts");
    Check([window.statusField.stringValue containsString:@"2"], @"the status reports the result");
    [window selectSetNamed:@"B"];
    [window highlightInTextView:view];
    Check([TSAdvancedFindHighlights existingHighlightsForTextStorage:view.textStorage].ranges.count == 2, @"highlight runs the shown set");
    window.inSelection = YES;
    view.selectedRange = NSMakeRange(0, 3);
    [window replaceAllInTextView:view];
    Check([view.string isEqualToString:@"bird dog"], @"in selection");
    [view.undoManager endUndoGrouping];
    [window.ruleTable replaceRuleAtIndex:0 withRule:Rule(@"dog", @"fish", NO, YES)];
    Check([[library setNamed:@"B" error:NULL].rules.firstObject.replaceString isEqualToString:@"fish"], @"an edit is saved at once");

    NSView *options = [window makeOptionsView];
    NSUInteger text = 0, regex = 0;
    NSMutableArray<NSView *> *pending = [options.subviews mutableCopy];
    while (pending.count) {
        NSView *v = pending.lastObject;
        [pending removeLastObject];
        [pending addObjectsFromArray:v.subviews];
        if ([v isKindOfClass:[NSButton class]] && ((NSButton *)v).enabled)
            text += [v.identifier isEqualToString:@"text"], regex += [v.identifier isEqualToString:@"regex"];
    }
    Check(text == 5 && regex == 7, @"a set can change both kinds of options: its rules choose");
    NSButton *wholeWord = nil;
    pending = [options.subviews mutableCopy];
    while (pending.count && !wholeWord) {
        NSView *v = pending.lastObject;
        [pending removeLastObject];
        [pending addObjectsFromArray:v.subviews];
        if ([v isKindOfClass:[NSButton class]] && v.tag == (NSInteger)TSRegexFindWholeWord)
            wholeWord = (NSButton *)v;
    }
    [wholeWord performClick:nil];
    Check(([library setNamed:@"B" error:NULL].textualOptions & TSRegexFindWholeWord) != 0, @"an option of the set is saved");
    // Read-only target: Replace All is gray, Highlight is not.
    TSAdvancedFindController.testTargetTextView = view;
    view.editable = NO;
    [window updateButtons];
    NSButton *replaceButton = nil, *highlightButton = nil;
    NSMutableArray<NSView *> *all = [window.window.contentView.subviews mutableCopy];
    while (all.count) {
        NSView *v = all.lastObject;
        [all removeLastObject];
        [all addObjectsFromArray:v.subviews];
        if ([v isKindOfClass:[NSButton class]] && ((NSButton *)v).action == @selector(replaceAll:)) replaceButton = (NSButton *)v;
        if ([v isKindOfClass:[NSButton class]] && ((NSButton *)v).action == @selector(highlight:)) highlightButton = (NSButton *)v;
    }
    Check(replaceButton && !replaceButton.enabled && highlightButton.enabled, @"Replace All is gray for a read-only text view");
    view.editable = YES;
    [window updateButtons];
    Check(replaceButton.enabled, @"and not for an editable one");
    TSAdvancedFindController.testTargetTextView = nil;
    // A broken set: the error is shown, the table is empty, nothing is overwritten.
    NSURL *brokenURL = [directory URLByAppendingPathComponent:@"C broken.json"];
    [@"{\"replacements\": 3}" writeToURL:brokenURL atomically:YES encoding:NSUTF8StringEncoding error:NULL];
    [window reloadSets];
    [window selectSetNamed:@"C broken"];
    Check(window.ruleTable.set == nil && window.statusField.stringValue.length > 0
          && [[NSString stringWithContentsOfURL:brokenURL encoding:NSUTF8StringEncoding error:NULL] isEqualToString:@"{\"replacements\": 3}"],
          @"a broken set shows its error and is left as it is");
    Check(!window.window.isVisible, @"the window is never shown");
}

/// An empty folder: no set, an empty table, and nothing to apply.
static void TestEmptyWindow(void)
{
    NSURL *directory = TemporaryLibraryDirectory();
    TSMultipleReplaceLibrary *library = [[TSMultipleReplaceLibrary alloc] initWithDirectory:directory];
    NSUInteger beeps = 0;
    TSMultipleReplaceWindowController *window = [[TSMultipleReplaceWindowController alloc] initWithFindController:MakeController(&beeps) library:library];
    NSTextView *view = MakeView(@"text");
    Check(window.selectedSetName == nil && window.ruleTable.set == nil && window.ruleTable.tableView.numberOfRows == 0 && window.statusField.stringValue.length == 0,
          @"an empty folder shows no set, no rule and no message");
    Check(![window replaceAllInTextView:view] && ![window highlightInTextView:view] && beeps == 2 && [view.string isEqualToString:@"text"],
          @"with no set, Replace All and Highlight beep and change nothing");
    Check(![NSFileManager.defaultManager fileExistsAtPath:directory.path], @"nothing is written into an empty folder");
    [window addSet:nil];
    Check(window.selectedSetName.length > 0 && library.setNames.count == 1 && window.ruleTable.tableView.numberOfRows == 1, @"a new set has one empty rule and is saved");
    [NSFileManager.defaultManager removeItemAtURL:directory.URLByDeletingLastPathComponent error:NULL];
}

/// The Find submenu as OgreKit makes it at launch when the find method is OgreKit: its own items, without
/// performFindPanelAction: and without Jump to Selection. The items join it at the end, once.
static void TestOgreKitMenu(void)
{
    NSMenu *main = [[NSMenu alloc] initWithTitle:@"Main"];
    NSMenuItem *editItem = [main addItemWithTitle:@"Edit" action:NULL keyEquivalent:@""];
    NSMenu *edit = [[NSMenu alloc] initWithTitle:@"Edit"];
    editItem.submenu = edit;
    [edit addItemWithTitle:@"Copy" action:@selector(copy:) keyEquivalent:@"c"];
    NSMenuItem *findItem = [edit addItemWithTitle:@"Find" action:NULL keyEquivalent:@""];
    NSMenu *find = [[NSMenu alloc] initWithTitle:@"Find"];
    findItem.submenu = find;
    [find addItemWithTitle:@"Find…" action:NSSelectorFromString(@"showFindPanel:") keyEquivalent:@"f"];
    [find addItemWithTitle:@"Find Next" action:NSSelectorFromString(@"findNext:") keyEquivalent:@"g"];
    [find addItemWithTitle:@"Use Selection for Find" action:NSSelectorFromString(@"useSelectionForFind:") keyEquivalent:@"e"];
    NSURL *directory = TemporaryLibraryDirectory();
    [TSMultipleReplaceMenu installInMainMenu:main directory:directory];
    [TSMultipleReplaceMenu installInMainMenu:main directory:directory];
    Check(find.numberOfItems == 6 && [find itemAtIndex:3].separatorItem && [find itemAtIndex:4].action == @selector(showMultipleReplace:)
          && [find itemAtIndex:5].submenu && [[find itemAtIndex:0].title isEqualToString:@"Find…"] && edit.numberOfItems == 2,
          @"OgreKit's Find submenu gets the items at its end, once, and keeps its own");
}

/// The Find submenu's items, in a menu like TeXShop's.
static void TestMenu(void)
{
    NSMenu *main = [[NSMenu alloc] initWithTitle:@"Main"];
    NSMenuItem *editItem = [main addItemWithTitle:@"Edit" action:NULL keyEquivalent:@""];
    NSMenu *edit = [[NSMenu alloc] initWithTitle:@"Edit"];
    editItem.submenu = edit;
    NSMenuItem *findItem = [edit addItemWithTitle:@"Find" action:NULL keyEquivalent:@""];
    NSMenu *find = [[NSMenu alloc] initWithTitle:@"Find"];
    findItem.submenu = find;
    [find addItemWithTitle:@"Find…" action:@selector(performFindPanelAction:) keyEquivalent:@"f"].tag = NSFindPanelActionShowFindPanel;
    [find addItemWithTitle:@"Find Next" action:@selector(performFindPanelAction:) keyEquivalent:@"g"].tag = NSFindPanelActionNext;
    [find addItemWithTitle:@"Jump to Selection" action:@selector(centerSelectionInVisibleArea:) keyEquivalent:@"j"];
    [find addItemWithTitle:@"Marks" action:NULL keyEquivalent:@""];
    NSURL *directory = TemporaryLibraryDirectory();
    [TSMultipleReplaceMenu installInMainMenu:main directory:directory];
    [TSMultipleReplaceMenu installInMainMenu:main directory:directory];
    Check(find.numberOfItems == 7, @"three items added once, even when installed twice");
    NSMenuItem *show = [find itemAtIndex:4], *sets = [find itemAtIndex:5];
    Check([find itemAtIndex:3].separatorItem && show.action == @selector(showMultipleReplace:) && [show.identifier isEqualToString:@"TSShortcut.showMultipleReplace:.0"]
          && show.keyEquivalent.length == 0 && sets.submenu && [[find itemAtIndex:6].title isEqualToString:@"Marks"],
          @"after Jump to Selection: a separator, Edit Multiple Replace… (a shortcut command without a key) and the sets");
    TSMultipleReplaceMenu *menu = TSMultipleReplaceMenu.sharedMenu;
    Check(menu && ![menu validateMenuItem:sets], @"no set: the submenu is gray");
    menu.findController.beepHandler = ^{};
    [menu.library saveSet:Set(@[Rule(@"cat", @"dog", NO, YES)]) named:@"Pets" error:NULL];
    [menu.library saveSet:Set(@[Rule(@"a", @"b", NO, YES)]) named:@"Letters" error:NULL];
    [menu menuNeedsUpdate:(NSMenu *_Nonnull)sets.submenu];
    Check([menu validateMenuItem:sets] && sets.submenu.numberOfItems == 2 && [[sets.submenu itemAtIndex:0].title isEqualToString:@"Letters"],
          @"the submenu lists the sets in order");
    NSTextView *view = MakeView(@"cat and cat");
    TSAdvancedFindController.testTargetTextView = view;
    NSMenuItem *pets = [sets.submenu itemAtIndex:1];
    Check([menu validateMenuItem:pets], @"a set can be applied to an editable text view");
    [menu applySet:pets];
    Check([view.string isEqualToString:@"dog and dog"], @"choosing a set applies it to the whole text");
    [view.undoManager undo];
    Check([view.string isEqualToString:@"cat and cat"], @"in one undo step");
    view.editable = NO;
    Check(![menu validateMenuItem:pets], @"not to a read-only one");
    TSAdvancedFindController.testTargetTextView = nil;
    [menu showMultipleReplace:nil];
    Check(!menu.windowController.window.isVisible && [menu.windowController.selectedSetName isEqualToString:@"Letters"], @"the window opens on the first set (never shown here)");
    [NSFileManager.defaultManager removeItemAtURL:directory.URLByDeletingLastPathComponent error:NULL];
}

/// Windows that are never shown do not draw buttons; each button's own cell is drawn at its measured frame
/// at its measured frame. Window glass and translucency are not reproduced.
static BOOL WritePNG(NSView *view, NSAppearance *appearance, NSString *path)
{
    __block BOOL written = NO;
    [appearance performAsCurrentDrawingAppearance:^{
        [view layoutSubtreeIfNeeded];
        [view displayIfNeeded];
        NSBitmapImageRep *raw = [view bitmapImageRepForCachingDisplayInRect:view.bounds];
        if (!raw)
            return;
        [view cacheDisplayInRect:view.bounds toBitmapImageRep:raw];
        NSImage *image = [[NSImage alloc] initWithSize:view.bounds.size];
        [image lockFocus];
        [NSColor.windowBackgroundColor setFill];
        NSRectFill(view.bounds);
        NSImage *cached = [[NSImage alloc] initWithSize:view.bounds.size];
        [cached addRepresentation:raw];
        [cached drawInRect:view.bounds fromRect:NSZeroRect operation:NSCompositingOperationSourceOver fraction:1];
        NSMutableArray<NSView *> *pending = [view.subviews mutableCopy];
        while (pending.count) {
            NSView *v = pending.lastObject;
            [pending removeLastObject];
            [pending addObjectsFromArray:v.subviews];
            if (!([v isKindOfClass:[NSButton class]] || [v isKindOfClass:[NSSegmentedControl class]]) || v.isHiddenOrHasHiddenAncestor)
                continue;
            NSRect frame = [v convertRect:v.bounds toView:view];
            [NSGraphicsContext saveGraphicsState];
            NSAffineTransform *transform = [NSAffineTransform transform];
            [transform translateXBy:frame.origin.x yBy:view.isFlipped ? NSHeight(view.bounds) - NSMaxY(frame) : frame.origin.y];
            if (v.isFlipped) {
                [transform translateXBy:0 yBy:frame.size.height];
                [transform scaleXBy:1 yBy:-1];
            }
            [transform concat];
            [[(NSControl *)v cell] drawWithFrame:v.bounds inView:v];
            [NSGraphicsContext restoreGraphicsState];
        }
        [image unlockFocus];
        NSBitmapImageRep *painted = [[NSBitmapImageRep alloc] initWithData:image.TIFFRepresentation];
        written = [[painted representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:path atomically:YES];
    }];
    return written;
}

/// A label shows all of its text: one line wide enough, or lines that wrap within its height.
static int CheckLabelFits(NSTextField *label, NSString *name)
{
    NSString *text = label.stringValue;
    if (text.length == 0)
        return 0;
    NSSize frame = label.frame.size;
    NSCell *cell = label.cell;
    BOOL wraps = !cell.usesSingleLineMode && (cell.lineBreakMode == NSLineBreakByWordWrapping || cell.lineBreakMode == NSLineBreakByCharWrapping);
    BOOL cut = wraps ? [cell cellSizeForBounds:NSMakeRect(0, 0, frame.width, CGFLOAT_MAX)].height > frame.height + 0.5
                     : cell.cellSize.width > frame.width + 0.5;
    if (cut)
        printf("FAIL %s: label cut: %s (%.0f wide, needs %.0f)\n", name.UTF8String, text.UTF8String, frame.width, cell.cellSize.width);
    return cut ? 1 : 0;
}

/// Every control inside the view, at least `rightInset` points from its right edge, with a title that fits.
static int CheckLayoutInset(NSView *root, NSString *name, CGFloat rightInset)
{
    int count = 0;
    NSMutableArray<NSView *> *pending = [root.subviews mutableCopy];
    while (pending.count) {
        NSView *v = pending.lastObject;
        [pending removeLastObject];
        if (![v isKindOfClass:[NSScrollView class]])
            [pending addObjectsFromArray:v.subviews];
        if (!([v isKindOfClass:[NSControl class]] || [v isKindOfClass:[NSScrollView class]]) || v.isHiddenOrHasHiddenAncestor)
            continue;
        NSRect frame = [v convertRect:v.bounds toView:root];
        NSString *title = [v isKindOfClass:[NSButton class]] ? [(NSButton *)v title]
                        : [v isKindOfClass:[NSTextField class]] ? [NSString stringWithFormat:@"%@ “%@”", NSStringFromClass(v.class), ((NSTextField *)v).stringValue]
                        : NSStringFromClass(v.class);
        if (rightInset > 0 && NSMaxX(frame) > NSMaxX(root.bounds) - rightInset) {
            printf("FAIL %s: no right inset: %s\n", name.UTF8String, title.UTF8String);
            count++;
        }
        if (!NSContainsRect(NSInsetRect(root.bounds, -0.5, -0.5), frame)) {
            printf("FAIL %s: outside: %s\n", name.UTF8String, title.UTF8String);
            count++;
        }
        if ([v isKindOfClass:[NSButton class]] && title.length > 0 && v.frame.size.width + 0.5 < v.fittingSize.width) {
            printf("FAIL %s: title cut: %s\n", name.UTF8String, title.UTF8String);
            count++;
        }
        if ([v isKindOfClass:[NSComboButton class]] && v.frame.size.width + 0.5 < v.fittingSize.width) {
            printf("FAIL %s: title cut: %s\n", name.UTF8String, [(NSComboButton *)v title].UTF8String);
            count++;
        }
        if ([v isKindOfClass:[NSTextField class]] && !((NSTextField *)v).isEditable)
            count += CheckLabelFits((NSTextField *)v, name);
    }
    return count;
}



/// The window and the options of a set in this language: layout, messages, and images on request.
static void TestLayout(NSString *_Nullable imageDirectory)
{
    NSString *language = NSBundle.mainBundle.preferredLocalizations.firstObject ?: @"en";
    NSURL *directory = TemporaryLibraryDirectory();
    TSMultipleReplaceLibrary *library = [[TSMultipleReplaceLibrary alloc] initWithDirectory:directory];
    library.usesTrash = NO;
    TSRegexReplacementRule *note = [[TSRegexReplacementRule alloc] initWithFindString:@"\\{\\\\bf\\s+([^}]*)\\}" replaceString:@"\\\\textbf{$1}"
                                                                usesRegularExpression:YES ignoresCase:NO enabled:YES note:TSAdvancedFindLocalized(@"MultipleReplace.Column.Note", @"Note")];
    [library saveSet:Set(@[note, Rule(@"、", @"，", NO, YES), Rule(@"[", @"", YES, YES), Rule(@"。", @"．", NO, NO)]) named:@"Typography" error:NULL];
    [library saveSet:Set(@[Rule(@"a", @"b", NO, YES)]) named:@"Letters" error:NULL];
    TSMultipleReplaceWindowController *window = [[TSMultipleReplaceWindowController alloc] initWithFindController:MakeController(NULL) library:library];
    [window selectSetNamed:@"Typography"];
    window.ruleTable.counts = @[@3, @12, @0, @0];
    NSView *content = window.window.contentView;
    NSView *options = [window makeOptionsView];
    [content layoutSubtreeIfNeeded];
    [options layoutSubtreeIfNeeded];
    [options setFrameSize:options.fittingSize];
    failures += CheckLayoutInset(content, [language stringByAppendingString:@" window"], 0);
    failures += CheckLayoutInset(options, [language stringByAppendingString:@" set options"], 16);
    // The smallest window, with the longest messages it shows
    NSRect old = window.window.frame;
    [window.window setContentSize:window.window.contentMinSize];
    [content layoutSubtreeIfNeeded];
    failures += CheckLayoutInset(content, [language stringByAppendingString:@" smallest window"], 0);
    NSArray<NSString *> *messages = @[
        [NSString stringWithFormat:TSAdvancedFindLocalized(@"MultipleReplace.Problem", @"Rule %lu is skipped: %@"), 12UL,
            [NSBundle.mainBundle localizedStringForKey:@"The find string is empty." value:@"The find string is empty." table:@"AdvancedFindEngine"]],
        [[NSString stringWithFormat:TSAdvancedFindLocalized(@"AdvancedFind.Replaced", @"%lu replaced"), 12345UL] stringByAppendingFormat:@" %@",
            [NSString stringWithFormat:TSAdvancedFindLocalized(@"MultipleReplace.SkippedRules", @"(rule %@ skipped; see ⚠︎)"), @"3, 7, 12"]],
        [NSString stringWithFormat:TSAdvancedFindLocalized(@"MultipleReplace.NameTaken", @"A set named “%@” already exists."), @"Typography"],
        [NSString stringWithFormat:TSAdvancedFindLocalized(@"MultipleReplace.BadName", @"“%@” cannot be the name of a set."), @"a/b"],
        [NSString stringWithFormat:TSAdvancedFindLocalized(@"MultipleReplace.NotText", @"“%@” is not UTF-8 text."), @"rules.txt"]];
    for (NSString *message in messages) {
        window.statusField.stringValue = message;
        [content layoutSubtreeIfNeeded];
        failures += CheckLabelFits(window.statusField, [language stringByAppendingString:@" window message"]);
    }
    window.statusField.stringValue = @"";
    [window.window setFrame:old display:NO];
    [content layoutSubtreeIfNeeded];
    // The table's headers are not cut
    for (NSTableColumn *column in window.ruleTable.tableView.tableColumns)
        Check(column.title.length == 0 || column.headerCell.cellSize.width <= column.width + 0.5, [NSString stringWithFormat:@"%@ header %@ fits", language, column.title]);
    if (imageDirectory) {
        [NSFileManager.defaultManager createDirectoryAtPath:(NSString *_Nonnull)imageDirectory withIntermediateDirectories:YES attributes:nil error:NULL];
        NSURL *emptyDirectory = TemporaryLibraryDirectory();
        TSMultipleReplaceWindowController *empty = [[TSMultipleReplaceWindowController alloc] initWithFindController:MakeController(NULL)
                                                                                                             library:[[TSMultipleReplaceLibrary alloc] initWithDirectory:emptyDirectory]];
        for (NSAppearanceName name in @[NSAppearanceNameAqua, NSAppearanceNameDarkAqua]) {
            NSAppearance *appearance = [NSAppearance appearanceNamed:name];
            NSString *tag = [name isEqualToString:NSAppearanceNameAqua] ? @"light" : @"dark";
            window.window.appearance = appearance;
            options.appearance = appearance;
            empty.window.appearance = appearance;
            NSString *base = [(NSString *_Nonnull)imageDirectory stringByAppendingPathComponent:[NSString stringWithFormat:@"%@-%@", language, tag]];
            Check(WritePNG(content, appearance, [base stringByAppendingString:@"-multiple-replace.png"])
                  && WritePNG(options, appearance, [base stringByAppendingString:@"-set-options.png"])
                  && WritePNG((NSView *_Nonnull)empty.window.contentView, appearance, [base stringByAppendingString:@"-multiple-replace-empty.png"]), @"images written");
        }
    }
    [NSFileManager.defaultManager removeItemAtURL:directory.URLByDeletingLastPathComponent error:NULL];
}

int main(int argc, const char *argv[])
{
    @autoreleasepool {
        TSInstallAppKitIsolation();
        [NSApplication sharedApplication];
        NSString *mode = argc > 1 ? @(argv[1]) : @"all";
        NSString *images = argc > 2 && argv[2][0] != '-' ? @(argv[2]) : nil; // not the -AppleLanguages that follows
        if ([mode isEqualToString:@"behavior"]) {
            NSURL *directory = TemporaryLibraryDirectory();
            TestLibrary(directory);
            [NSFileManager.defaultManager removeItemAtURL:directory.URLByDeletingLastPathComponent error:NULL];
            TestApplying();
            TestRuleTable();
            TestOptionsForm();
            NSURL *windowDirectory = TemporaryLibraryDirectory();
            TestWindow(windowDirectory);
            [NSFileManager.defaultManager removeItemAtURL:windowDirectory.URLByDeletingLastPathComponent error:NULL];
            TestEmptyWindow();
            TestOgreKitMenu();
            TestMenu();
        } else {
            TestLayout(images);
        }
        if (failures)
            return 1;
        printf("PASS %s (%s)\n", mode.UTF8String, (NSBundle.mainBundle.preferredLocalizations.firstObject ?: @"en").UTF8String);
    }
    return 0;
}
