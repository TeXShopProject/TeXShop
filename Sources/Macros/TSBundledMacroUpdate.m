#import "TSBundledMacroUpdate.h"

static NSString * const TSCurrentHomePage = @"https://texshop.app/";

// The addresses that earlier versions bundled in place of the current one.
static NSArray<NSString *> *TSFormerHomePages(void)
{
    return @[@"https://pages.uoregon.edu/koch/texshop/texshop.html",
             @"http://pages.uoregon.edu/koch/texshop/texshop.html",
             @"http://www.uoregon.edu/~koch/texshop/texshop.html"];
}

// The changes from the text of Set Root File… (Root up to 6.00 RC 2) to its earlier text: the relative
// path of the root file was found by Perl, with the paths put in a Perl string, so that a path with " $ @ or '
// in it broke the macro; it is now found by the AppleScript handler relative_root_path at the end.
static NSArray<NSArray<NSString *> *> *TSRootFileChanges(void)
{
    return @[
        @[(@"\t-- The path of the Root document relative to the folder of this document\n"
             "\tset Root_rel_path to my relative_root_path(Root_abs_path, TeX_path)\n"),
          (@"\t-- Use perl to convert the absolute path to the Root document \n"
             "\t-- to a relative path to it.\n"
             "\tset command to \"perl -e 'use File::Spec; \"\n"
             "\tset command to command & \"$rel_path = File::Spec->abs2rel\"\n"
             "\tset command to command & \"( \\\"\" & Root_abs_path & \"\\\",\"\n"
             "\tset command to command & \"\\\"\" & TeX_path & \"\\\" ) ; \"\n"
             "\tset command to command & \"print $rel_path'\"\n"
             "\ttell me to set Root_rel_path to do shell script command\n")],
        @[(@"\tend try\n"
             "\t\n"
             "\t-- Get the absolute path"),
          (@"\tend try\n"
             "\t\n"
             "\tset TeX_path to do shell script \"dirname \" & quoted form of TeX_path\n"
             "\t\n"
             "\t-- Get the absolute path")],
        @[(@"end tell\n"
             "\n"
             "-- The path of the file target_path relative to the folder of the file document_path, as earlier\n"
             "-- versions gave it with File::Spec->abs2rel of Perl: \"..\" for each folder to go up, then the rest.\n"
             "-- Names are compared character for character, so a path may have any character in it.\n"
             "on relative_root_path(target_path, document_path)\n"
             "\tset saved_delimiters to AppleScript's text item delimiters\n"
             "\tset AppleScript's text item delimiters to \"/\"\n"
             "\tset target_names to {}\n"
             "\trepeat with a_name in text items of target_path\n"
             "\t\tif contents of a_name is not in {\"\", \".\"} then set end of target_names to contents of a_name\n"
             "\tend repeat\n"
             "\tset base_names to {}\n"
             "\trepeat with a_name in text items of document_path\n"
             "\t\tif contents of a_name is not in {\"\", \".\"} then set end of base_names to contents of a_name\n"
             "\tend repeat\n"
             "\t-- The folder of the document: its path without the name of the document.\n"
             "\tif (count of base_names) > 0 then set base_names to reverse of rest of reverse of base_names\n"
             "\tset common to 0\n"
             "\trepeat while common < (count of target_names) and common < (count of base_names)\n"
             "\t\tif id of (item (common + 1) of target_names) is not id of (item (common + 1) of base_names) then exit repeat\n"
             "\t\tset common to common + 1\n"
             "\tend repeat\n"
             "\tset relative_names to {}\n"
             "\trepeat (count of base_names) - common times\n"
             "\t\tset end of relative_names to \"..\"\n"
             "\tend repeat\n"
             "\trepeat with i from common + 1 to count of target_names\n"
             "\t\tset end of relative_names to item i of target_names\n"
             "\tend repeat\n"
             "\tif relative_names is {} then\n"
             "\t\tset relative_path to \".\"\n"
             "\telse\n"
             "\t\tset relative_path to relative_names as text\n"
             "\tend if\n"
             "\tset AppleScript's text item delimiters to saved_delimiters\n"
             "\treturn relative_path\n"
             "end relative_root_path"),
          (@"end tell")],
    ];
}

// Bundled macros reworded since earlier versions: the current name, the changes from each
// earlier text to the current one (current text, earlier text), and the earlier name when the
// macro was renamed too. "TeX Live" is written with the space, and the ConTeXt macro that
// opened the teTeX page of Gerben Wierda opens the TeX Live home page. Program no longer offers
// metafont and context, which typesetting does not know without an engine file of that name, and
// Encoding offers DOSKorean, as the encoding menus do. Up to 6.00 beta 8, the macros that run the
// scripts in ~/Library/TeXShop/bin passed file names to the shell unquoted, and the line ending
// macros ran flip through tcsh. Set Root File… no longer runs Perl (above).
// All of these but View TeX Live file were renamed too (below).
static NSArray<NSDictionary *> *TSRewordedMacros(void)
{
    NSMutableArray<NSDictionary *> *macros = [@[
        @{@"name": @"Set Typesetting Program…",
          @"changes": @[@[@"\"personallatex\", \"metapost\"} & engines", @"\"personallatex\", \"metapost\", \"metafont\", \"context\"} & engines"]]},
        @{@"name": @"Set Encoding…",
          @"changes": @[@[@"\"MacKorean\", \"DOSKorean\", \"UTF-8 Unicode\"", @"\"MacKorean\", \"UTF-8 Unicode\""]]},
        @{@"name": @"View TeX Live file",
          @"changes": @[@[@"-- OPEN TeX Live FILE", @"-- OPEN TeXLive FILE"],
                        @[@"a file in the TeX Live tree, for", @"a file in the TeXLive tree, for"],
                        @[@"any files in the TeX Live tree with", @"any files in the teTeX tree with"]]},
        @{@"name": @"TeX Live home page", @"formerName": @"teTeX/TeXLive home page",
          @"changes": @[@[@"open location \"https://tug.org/texlive/\"", @"open location \"http://www.rna.nl/tex.html\""]]},
        @{@"name": @"Set Root File…", @"changes": TSRootFileChanges()},
    ] mutableCopy];
    NSArray *unquoted = @[@[@" & quoted form of baseName", @" & baseName"], @[@" & quoted form of texName", @" & texName"]];
    for (NSString *name in @[@"Run BibTeX, Then pdfLaTeX Twice", @"Run pdfLaTeX, BibTeX, Then pdfLaTeX Twice",
                             @"Run MetaPost, Then pdfLaTeX", @"Run pdfLaTeX, MetaPost, Then pdfLaTeX",
                             @"Make HTML with TeX4ht", @"Make HTML with TeX4ht, Remaking Images", @"Run LaTeX, dvips and ps2pdf",
                             @"Run pdfLaTeX with Shell Escape", @"Run pdfLaTeX, MakeIndex, MetaPost, Then pdfLaTeX"])
        [macros addObject:@{@"name": name, @"changes": unquoted}];
    NSDictionary<NSString *, NSString *> *flipOptions = @{@"Save Copy with Classic Mac Line Endings": @"m",
                                                          @"Save Copy with Unix Line Endings": @"u",
                                                          @"Save Copy with Windows Line Endings": @"d"};
    for (NSString *name in flipOptions) {
        NSString *flip = [NSString stringWithFormat:@"~/Library/TeXShop/bin/flip -%@ ", flipOptions[name]];
        [macros addObject:@{@"name": name, @"changes": @[
            @[@"set shellScript to  \"cd \" & dirName & \" && \"", @"set shellScript to  \"cd \" & dirName & \";\""],
            @[@"set shellScript to shellScript & \"cp \" & quoted form of (\"./\" & texName) & \" \" & quoted form of (\"./\" & backupTexName) & \" && \"",
              @"set shellScript to shellScript & \"cp  \" & texName &\" \" & backupTexName &\";\""],
            @[[NSString stringWithFormat:@"\"%@\" & quoted form of (\"./\" & backupTexName)", flip],
              [NSString stringWithFormat:@"\"/bin/tcsh -c '%@ \" & backupTexName & \"'\"", flip]]]}];
    }
    return macros;
}

// Bundled macros renamed in 6.00 so that the name says what the macro does, by current name: the
// name earlier versions gave them. Their texts are those of earlier versions, or those reworded
// above. A copy that still has the bundled text and the earlier name takes the current name; its
// key stays.
static NSDictionary<NSString *, NSString *> *TSRenamedMacros(void)
{
    return @{
        @"Set Typesetting Program…": @"Program",
        @"Set Encoding…": @"Encoding",
        @"Set Root File…": @"Root",
        @"Page Number Correction": @"Numbering",
        @"PreTeXt Tag Comment": @"PreText Personal Mark",
        @"Root File Line": @"Root (Short Version)",
        @"Insert Font Set…": @"GetFontSet",
        @"Save Font Set": @"SaveFontSet",
        @"Test Font Set Sizes": @"TestFontSet",
        @"Align Table Columns": @"Tabularize",
        @"Align Table Columns with Spaces": @"Tabularize +space",
        @"Show Source and PDF in Finder": @"Show files",
        @"Save Copy with Classic Mac Line Endings": @"Convert to MAC",
        @"Save Copy with Unix Line Endings": @"Convert to Unix",
        @"Save Copy with Windows Line Endings": @"Convert to Windows",
        @"Run LaTeX, BibTeX, Then LaTeX Twice": @"Bibliography",
        @"Run BibTeX, Then pdfLaTeX Twice": @"bibtexc",
        @"Run pdfLaTeX, BibTeX, Then pdfLaTeX Twice": @"bibtexcpl",
        @"Run MetaPost, Then pdfLaTeX": @"mpostc",
        @"Run pdfLaTeX, MetaPost, Then pdfLaTeX": @"mpostcpl",
        @"Make HTML with TeX4ht": @"htlatexc",
        @"Make HTML with TeX4ht, Remaking Images": @"htlatexr",
        @"Run LaTeX, dvips and ps2pdf": @"altpdflatexc",
        @"Run pdfLaTeX with Shell Escape": @"pdflatexc",
        @"Extract Pages from PDF…": @"pdfselectc",
        @"Open PDF": @"openpdf",
        @"Run pdfLaTeX, MakeIndex, MetaPost, Then pdfLaTeX": @"latex-makeindex-mpost",
        @"figure": @"regular",
    };
}

// Maps each earlier bundled text to the current macro: its content, and its name and earlier
// name when it was renamed.
static void TSCollectBundledTexts(id node, NSMutableDictionary<NSString *, NSDictionary *> *earlier)
{
    if (![node isKindOfClass:[NSDictionary class]])
        return;
    NSString *content = node[@"content"];
    NSString *name = node[@"name"];
    NSString *current = [NSString stringWithFormat:@"open location \"%@\"", TSCurrentHomePage];
    if ([content isKindOfClass:[NSString class]] && [content containsString:current])
        for (NSString *former in TSFormerHomePages())
            earlier[[content stringByReplacingOccurrencesOfString:TSCurrentHomePage withString:former]] = @{@"content": content};
    NSString *formerName = [name isKindOfClass:[NSString class]] ? TSRenamedMacros()[name] : nil;
    // A renamed macro whose text is still the bundled one takes the current name.
    if ([content isKindOfClass:[NSString class]] && formerName)
        earlier[content] = @{@"content": content, @"name": name, @"formerName": formerName};
    if ([content isKindOfClass:[NSString class]] && [name isKindOfClass:[NSString class]])
        for (NSDictionary *macro in TSRewordedMacros()) {
            if (![name isEqualToString:macro[@"name"]])
                continue;
            NSString *former = content;
            for (NSArray<NSString *> *change in macro[@"changes"])
                former = [former stringByReplacingOccurrencesOfString:change[0] withString:change[1]];
            if ([former isEqualToString:content])
                continue;
            NSMutableDictionary *target = [@{@"content": content} mutableCopy];
            if (macro[@"formerName"] ?: formerName) {
                target[@"name"] = name;
                target[@"formerName"] = macro[@"formerName"] ?: formerName;
            }
            earlier[former] = target;
        }
    NSArray *submenu = node[@"submenu"];
    if ([submenu isKindOfClass:[NSArray class]])
        for (id child in submenu)
            TSCollectBundledTexts(child, earlier);
}

static NSUInteger TSReplaceEarlierTexts(id node, NSDictionary<NSString *, NSDictionary *> *earlier)
{
    if (![node isKindOfClass:[NSMutableDictionary class]])
        return 0;
    NSUInteger count = 0;
    NSString *content = node[@"content"];
    NSDictionary *target = [content isKindOfClass:[NSString class]] ? earlier[content] : nil;
    // A renamed macro is updated only under its earlier name; one the user renamed stays.
    if (target && (target[@"formerName"] == nil || [node[@"name"] isEqual:target[@"formerName"]])) {
        node[@"content"] = target[@"content"];
        if (target[@"name"])
            node[@"name"] = target[@"name"];
        count++;
    }
    NSArray *submenu = node[@"submenu"];
    if ([submenu isKindOfClass:[NSArray class]])
        for (id child in submenu)
            count += TSReplaceEarlierTexts(child, earlier);
    return count;
}

NSUInteger TSUpdateUnchangedBundledMacros(NSString *userPath, NSString *bundledPath)
{
    NSData *bundledData = [NSData dataWithContentsOfFile:bundledPath];
    id bundled = bundledData ? [NSPropertyListSerialization propertyListWithData:bundledData options:NSPropertyListImmutable format:NULL error:NULL] : nil;
    NSMutableDictionary<NSString *, NSDictionary *> *earlier = [NSMutableDictionary dictionary];
    TSCollectBundledTexts(bundled, earlier);
    if (earlier.count == 0)
        return 0;

    // Write through a symbolic link, so a Macros file kept elsewhere stays where it is.
    NSURL *file = [[NSURL fileURLWithPath:userPath] URLByResolvingSymlinksInPath];
    NSData *data = [NSData dataWithContentsOfURL:file];
    if (!data)
        return 0;
    NSPropertyListFormat format = NSPropertyListXMLFormat_v1_0;
    id macros = [NSPropertyListSerialization propertyListWithData:data options:NSPropertyListMutableContainersAndLeaves format:&format error:NULL];
    NSUInteger count = TSReplaceEarlierTexts(macros, earlier);
    if (count == 0)
        return 0;
    NSData *updated = [NSPropertyListSerialization dataWithPropertyList:macros format:format options:0 error:NULL];
    if (!updated || ![updated writeToURL:file atomically:YES])
        return 0;
    return count;
}
