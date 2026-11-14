#!/usr/bin/env python3
"""Exercise production Experiment document methods without AppKit windows or jobs.

The real methods write an isolated temporary TeX file; a console double records
its bytes and launch parameters. Normal-job pipes and windows are sentinels.
Use --mutation to prove the historical regressions are rejected.
"""
from pathlib import Path
import argparse
import os
import subprocess
import tempfile
from source_tree import source_file

MUTATIONS = {
    'inactive-pdf': ('typesetFile', 'if (!document) return;',
                     'if (!document || !document->scrapWindow.isVisible) return;'),
    'scrap-kill-normal': ('typesetFile', '    env = [self environmentWithNewPath: additionalPath];',
                          '    [self killRunningTasks];\n    env = [self environmentWithNewPath: additionalPath];'),
    'scrap-steal-inputpipe': ('typesetFile', '    env = [self environmentWithNewPath: additionalPath];',
                            '    self.inputPipe = [NSPipe pipe]; self.outputPipe = [NSPipe pipe]; self.readHandle = [self.outputPipe fileHandleForReading];\n    env = [self environmentWithNewPath: additionalPath];'),
    'scrap-close-normal-console': ('windowWillClose', '        [self closeExperiment];',
                                  '        [outputWindow close];\n        [self closeExperiment];'),
    'doc-close-no-experiment': ('close', '    [self closeExperiment];\n', ''),
    'scrap-no-clone': ('typesetScrap', '    [TSExperimentJob cloneItemsOfDirectory:', '    if (0) [TSExperimentJob cloneItemsOfDirectory:'),
    'scrap-aux-not-read': ('typesetScrap', '    newSource = [theHeader stringByAppendingFormat:@"\\n%@\\\\begin{document}\\n", readAux];',
                           '    newSource = [theHeader stringByAppendingFormat:@"\\n%@\\\\begin{document}\\n", @""];'),
    'scrap-aux-catcode': ('typesetScrap', '\\\\begingroup\\\\makeatletter\\\\csname @input\\\\endcsname{%@}\\\\endgroup',
                          '\\\\csname @input\\\\endcsname{%@}'),
    'scrap-header-underflow': ('typesetScrap', 'theHeader = [theSource substringToIndex:beginDoc.location];',
                              'theHeader = [theSource substringToIndex:[theSource lineRangeForRange:NSMakeRange(0, beginDoc.location - 1)].length];'),
    'scrap-script-self': ('typesetScrap', 'self.scrapScript = theDocument->whichScript;',
                         'self.scrapScript = whichScript;'),
    'pdf-top-before-show': ('typesetFile', '        [document->scrapPDFWindow makeKeyAndOrderFront:nil];\n        [document->scrapPDFKitView didShowOutputWindow];',
                            '        [document->scrapPDFKitView didShowOutputWindow];\n        [document->scrapPDFWindow makeKeyAndOrderFront:nil];'),
    'pdf-top-missing': ('typesetFile', '        [document->scrapPDFKitView didShowOutputWindow];\n', ''),
    # plain TeX, MetaPost and ConTeXt cannot typeset an Experiment, also when named by a
    # "% !TEX program" line; an engine of ~/Library/TeXShop/Engines keeps its name.
    'engine-plain-tex-runs': ('engine', '        return nil;   // plain TeX, MetaPost, or no engine', '        return @"pdflatex";'),
    'engine-context-runs': ('engine', '    return TSExperimentRejectsEngine(engine) ? nil : engine;', '    return engine;'),
    'engine-pdftex-runs': ('engine', '@"tex", @"pdftex", ', '@"tex", '),
    'engine-name-lowercased': ('engine', '        engine = menuTitles[menuEngine - 1];', '        engine = menuTitles[menuEngine - 1].lowercaseString;'),
}
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('root', nargs='?', type=Path, default=Path(__file__).resolve().parents[1])
parser.add_argument('--mutation', choices=MUTATIONS)
args = parser.parse_args()


def method(filename, signature):
    text = (source_file(args.root, filename)).read_text(errors='replace')
    start = text.index(signature)
    return text[start:text.index('\n}\n', start) + 3]


methods = {name: method('TSDocument-Scrap.m', sig) for name, sig in [
    ('typesetFile', '- (void)typesetFile:'), ('typesetScrap', '- (IBAction) typesetScrap:'),
    ('windowWillClose', '- (void)windowWillClose:'), ('closeExperiment', '- (void)closeExperiment'),
    ('getFilePath', '- (NSString *)getFilePath'), ('searchFile', '- (void)searchFile:')]}
methods['close'] = method('TSDocument.m', '- (void)close\n')
# The engine of an Experiment and the constants it uses, from the product sources
scrap = source_file(args.root, 'TSDocument-Scrap.m').read_text(errors='replace')
engine = scrap[scrap.index('// An experiment typesets a LaTeX document'):scrap.index('@implementation TSDocument (Scrap)')]
globals_h = source_file(args.root, 'globals.h').read_text(errors='replace')
document_h = source_file(args.root, 'TSDocument.h').read_text(errors='replace')
engine_start = globals_h.index('enum EngineCommand')
mode_end = document_h.index('} DefaultTypesetMode;') + len('} DefaultTypesetMode;')
constants = (globals_h[engine_start:globals_h.index('};', engine_start) + 2] + '\n'
             + document_h[document_h.rindex('typedef enum', 0, mode_end):mode_end] + '\n')
if args.mutation:
    name, old, new = MUTATIONS[args.mutation]
    if name == 'engine':
        assert engine.count(old) == 1, args.mutation
        engine = engine.replace(old, new, 1)
    else:
        assert methods[name].count(old) == 1, args.mutation
        methods[name] = methods[name].replace(old, new, 1)

program = r'''
#import <Foundation/Foundation.h>
static NSUInteger failures, checks, beeps;
static void Check(BOOL b, NSString *label) {
    checks++;
    if (!b) { failures++; fprintf(stderr, "FAIL: %s\n", label.UTF8String); }
}
static void NSBeep(void) { beeps++; }
@@CONSTANTS@@
@@ENGINE@@
@interface Node : NSObject
@property (copy) NSString *string, *title;
@property NSInteger indexOfSelectedItem;
@property (copy) NSArray<NSString *> *itemTitles;
@property BOOL isVisible, hidesOnDeactivate;
@property NSUInteger closes, shows, reloads, breaks, outputShows, shownBeforeOutput;
@property (strong) id document;
@property (copy) NSString *lastPath;
- (void)close;
- (id)toolbar;
- (void)turnVisibleOff:(BOOL)b;
- (void)breakConnections;
- (void)makeKeyAndOrderFront:(id)sender;
- (void)reShowWithPath:(NSString *)path;
- (void)didShowOutputWindow;
+ (id)sharedColorPanel;
+ (id)sharedFontPanel;
@end
static NSUInteger shownWindows;
@implementation Node
- (void)close { self.closes++; self.isVisible = NO; }
- (id)toolbar { return nil; }
- (void)turnVisibleOff:(BOOL)b { }
- (void)breakConnections { self.breaks++; }
- (void)makeKeyAndOrderFront:(id)sender { self.shows++; self.isVisible = YES; shownWindows++; }
- (void)reShowWithPath:(NSString *)path { self.reloads++; self.lastPath = path; }
- (void)didShowOutputWindow { self.outputShows++; self.shownBeforeOutput = shownWindows; }
+ (id)sharedColorPanel { return nil; }
+ (id)sharedFontPanel { return nil; }
@end
#define NSColorPanel Node
#define NSFontPanel Node
#define TSToolbar Node
@interface App : NSObject
@property (strong) Node *keyWindow;
+ (instancetype)shared;
@end
@implementation App
+ (instancetype)shared { static App *a; if (!a) a = [App new]; return a; }
@end
#define NSApp App.shared
@interface Defaults : NSObject
+ (instancetype)shared;
- (NSString *)stringForKey:(NSString *)key;
@end
@implementation Defaults
+ (instancetype)shared { static Defaults *d; if (!d) d = [Defaults new]; return d; }
- (NSString *)stringForKey:(NSString *)key { return [@"/engine/" stringByAppendingString:key]; }
@end
#define SUD Defaults.shared
static NSString *LatexScriptCommandKey = @"personal", *LatexCommandKey = @"pdf", *LatexGSCommandKey = @"dvi";
static NSString *EnginePath = @"/custom-engines";
static BOOL g_canRegisterCommandCompletion;
@interface Manager : NSObject
@property (copy) NSString *CommandCompletionPath;
+ (id)sharedInstance;
+ (instancetype)sharedGlobalData;
- (void)notifyActiveTextWindowClosed;
@end
@implementation Manager
+ (id)sharedInstance { return nil; }
+ (instancetype)sharedGlobalData { return nil; }
- (void)notifyActiveTextWindowClosed { }
@end
#define TSWindowManager Manager
#define GlobalData Manager
@interface TSEncodingSupport : NSObject
+ (instancetype)sharedInstance;
- (NSStringEncoding)stringEncodingForKey:(NSString *)key;
- (NSData *)dataForText:(NSString *)text encoding:(NSStringEncoding)encoding byteOrderMark:(NSInteger)mark;
@end
@implementation TSEncodingSupport
+ (instancetype)sharedInstance { static id e; if (!e) e = [self new]; return e; }
- (NSStringEncoding)stringEncodingForKey:(NSString *)key { return [key isEqualToString:@"UTF-8"] ? NSUTF8StringEncoding : NSISOLatin1StringEncoding; }
- (NSData *)dataForText:(NSString *)text encoding:(NSStringEncoding)encoding byteOrderMark:(NSInteger)mark {
    return [text dataUsingEncoding:encoding];
}
@end
enum { TSNoByteOrderMark };
@interface Console : NSObject
@property BOOL isWindowLoaded;
@property (strong) Node *window, *returnWindow;
@property NSUInteger starts, invalidations;
@property NSStringEncoding encoding;
@property (copy) NSString *executable, *source, *title;
@property (copy) NSArray *arguments;
@property (copy) NSDictionary *environment;
@property (strong) NSURL *directory;
@property (copy) void (^completion)(NSURL *);
- (void)invalidate;
- (void)startExecutable:(NSString *)exe arguments:(NSArray *)args environment:(NSDictionary *)env
              directory:(NSURL *)directory encoding:(NSStringEncoding)encoding title:(NSString *)title
             completion:(void (^)(NSURL *))completion;
@end
@implementation Console
- (void)invalidate { self.invalidations++; self.completion = nil; }
- (void)startExecutable:(NSString *)exe arguments:(NSArray *)args environment:(NSDictionary *)env
              directory:(NSURL *)directory encoding:(NSStringEncoding)encoding title:(NSString *)title
             completion:(void (^)(NSURL *))completion {
    self.starts++; self.executable = exe; self.arguments = args; self.environment = env;
    self.directory = directory; self.encoding = encoding; self.title = title; self.completion = completion;
    self.source = [[NSString alloc] initWithData:[NSData dataWithContentsOfURL:[directory URLByAppendingPathComponent:@"file.tex"]] encoding:encoding];
}
@end
#define TSExperimentConsoleController Console
// Records how the Experiment folder is prepared (#8); the work itself is tested elsewhere.
static NSURL *clonedSource, *clonedInto, *copiedAux, *copiedTo;
static NSArray *clonedExceptions;
static BOOL auxCopied;
@interface TSExperimentJob : NSObject
+ (NSUInteger)cloneItemsOfDirectory:(NSURL *)source intoDirectory:(NSURL *)directory exceptNames:(NSArray *)names;
+ (BOOL)copyAuxiliaryFile:(NSURL *)aux toURL:(NSURL *)destination;
@end
@implementation TSExperimentJob
+ (NSUInteger)cloneItemsOfDirectory:(NSURL *)source intoDirectory:(NSURL *)directory exceptNames:(NSArray *)names {
    clonedSource = source; clonedInto = directory; clonedExceptions = names; return 0;
}
+ (BOOL)copyAuxiliaryFile:(NSURL *)aux toURL:(NSURL *)destination { copiedAux = aux; copiedTo = destination; return auxCopied; }
@end
@interface BaseDocument : NSObject
@property NSUInteger baseCloses;
- (void)close;
@end
@implementation BaseDocument
- (void)close { self.baseCloses++; }
@end
@interface Document : BaseDocument {
@public
    Node *scrapWindow, *scrapPDFWindow, *scrapPDFKitView, *scrapTextView;
    Node *outputWindow, *outputText, *pdfWindow, *_htmlWindow, *annotationChoices;
    BOOL fileIsTex;
    NSInteger whichScript;
}
@property (strong) Document *rootDocument;
@property (strong) Console *experimentConsole;
@property (strong) Node *programButton, *textView, *myPDFKitView, *myPDFKitView2, *pdfKitWindow, *logWindow;
@property (strong) id inputPipe, outputPipe, readHandle, writeHandle;
@property (strong) NSTimer *tagTimer, *pdfRefreshTimer;
@property (strong) id pdfActivity;
@property BOOL useDVI, scrapDVI, annotationsExist;
@property (copy) NSString *scrapProgram, *scrapEncoding;
@property NSInteger scrapMenuEngine;
@property (copy) NSArray<NSString *> *scrapMenuTitles;
@property NSInteger scrapScript;
@property NSStringEncoding encoding, scrapEffectiveEncoding;
@property (strong) NSURL *fileURL;
@property NSUInteger cancellations, errors, watchCancellations, pdfStops, annotationSaves;
- (NSString *)getFilePath;
- (void)typesetFile:(NSURL *)url withAdditionalPath:(NSString *)path;
- (void)typesetScrap:(id)sender;
- (void)searchFile:(NSString *)source;
- (void)windowWillClose:(NSNotification *)notification;
- (void)closeExperiment;
- (Console *)ensureExperimentConsole;
- (NSDictionary *)environmentWithNewPath:(NSString *)path;
- (NSString *)separate:(NSString *)command into:(NSMutableArray *)args;
- (NSString *)absoluteEnginePath:(NSString *)path;
- (void)killRunningTasks;
- (void)presentError:(NSError *)error;
- (void)cancelWatchFile;
- (void)stopExternalPDFObservation;
- (void)callSaveAnnotations;
- (Node *)getStringWindow;
+ (void)applySpellingDefaultUnlessDocumentIsMain;
@end
#define TSDocument Document
#define NSDocument Document
static NSUInteger spellingDefaultsApplied;
@implementation Document
+ (void)applySpellingDefaultUnlessDocumentIsMain { spellingDefaultsApplied++; }
- (Console *)ensureExperimentConsole {
    if (!self.experimentConsole) self.experimentConsole = [Console new];
    return self.experimentConsole;
}
- (NSDictionary *)environmentWithNewPath:(NSString *)path { return @{@"TEXINPUTS":path}; }
- (NSString *)separate:(NSString *)command into:(NSMutableArray *)args { return command; }
- (NSString *)absoluteEnginePath:(NSString *)path { return path; }
- (void)killRunningTasks { self.cancellations++; }
- (void)presentError:(NSError *)error { self.errors++; }
- (void)cancelWatchFile { self.watchCancellations++; }
- (void)stopExternalPDFObservation { self.pdfStops++; }
- (void)callSaveAnnotations { self.annotationSaves++; }
- (Node *)getStringWindow { return nil; }
@@METHODS@@
@end
static Document *D(void) {
    Document *d = [Document new];
    d->scrapWindow = [Node new]; d->scrapWindow.title = @"Experiment sentinel";
    d->scrapWindow.isVisible = YES;
    d->scrapPDFWindow = [Node new]; d->scrapPDFKitView = [Node new];
    d->scrapTextView = [Node new]; d->scrapTextView.string = @"fragment";
    d->outputWindow = [Node new]; d->outputWindow.isVisible = YES; d->outputText = [Node new];
    d->outputText.string = @"normal running output"; d->outputWindow.title = @"normal console";
    d.inputPipe = [NSObject new]; d.outputPipe = [NSObject new];
    d.readHandle = [NSObject new]; d.writeHandle = [NSObject new];
    d.programButton = [Node new]; d.programButton.indexOfSelectedItem = 1;
    d.programButton.itemTitles = @[@"plain TeX", @"LaTeX", @"BibTeX", @"MakeIndex", @"MetaPost"];
    d.textView = [Node new]; d.textView.string = @"child preamble\\begin{document}child body";
    d.encoding = NSUTF8StringEncoding; d->whichScript = 100; d->fileIsTex = YES;
    d.fileURL = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:@"child.tex"]];
    return d;
}
static NSArray *NormalState(Document *d) {
    return @[d.inputPipe ?: NSNull.null, d.outputPipe ?: NSNull.null, d.readHandle ?: NSNull.null,
             d.writeHandle ?: NSNull.null, d->outputText, d->outputWindow];
}
static void CheckNormal(Document *d, NSArray *before) {
    NSArray *after = NormalState(d);
    for (NSUInteger i = 0; i < before.count; i++)
        Check(before[i] == after[i], @"Experiment preserves normal pipe/text/window ownership");
    Check(d.cancellations == 0, @"Experiment never stops normal typesetting");
    Check([d->outputText.string isEqualToString:@"normal running output"] && [d->outputWindow.title isEqualToString:@"normal console"], @"Experiment preserves normal console contents and title");
    Check(d->outputWindow.isVisible && d->outputWindow.closes == 0, @"Experiment leaves normal console visible");
}
static void RemoveOutput(Console *console) {
    if (console.directory) [[NSFileManager defaultManager] removeItemAtURL:console.directory error:NULL];
}
static void CheckSource(NSString *source, NSString *header, NSInteger rootScript,
                        NSStringEncoding rootEncoding, NSString *expectedExecutable) {
    Document *d = D(), *root = D(); d.rootDocument = root;
    root.fileURL = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:@"root/main.tex"]];
    root.textView.string = source; root->whichScript = rootScript;
    root.encoding = rootEncoding; root.useDVI = YES;
    NSArray *normal = NormalState(d);
    @try {
        [d typesetScrap:nil];
        Console *c = d.experimentConsole;
        Check(c.starts == 1 && d.errors == 0, @"one Experiment job starts");
        NSString *expected = [NSString stringWithFormat:@"%@\n\\begin{document}\nfragment\n\\end{document}\n", header];
        Check([c.source isEqualToString:expected], @"root preamble is extracted exactly, including first-column/inline/absent marker");
        Check(d.scrapScript == rootScript && d.scrapDVI, @"root engine mode and DVI setting are used");
        Check([c.executable isEqualToString:expectedExecutable], @"root engine determines executable");
        NSStringEncoding expectedEncoding = rootEncoding == NSUnicodeStringEncoding ? NSUTF8StringEncoding : rootEncoding;
        Check(d.scrapEffectiveEncoding == expectedEncoding && c.encoding == expectedEncoding, @"root encoding is used, UTF-16 is normalized to UTF-8");
        Check([c.environment[@"TEXINPUTS"] isEqualToString:root.fileURL.URLByDeletingLastPathComponent.path], @"root source directory supplies search path");
        Check([c.title isEqualToString:@"Experiment sentinel"], @"Experiment title passed to its console");
        Check([clonedSource.path isEqualToString:root.fileURL.URLByDeletingLastPathComponent.path] &&
              [clonedInto.path isEqualToString:c.directory.path] &&
              [clonedExceptions containsObject:@"file"] && [clonedExceptions containsObject:@"TeXShop-document.aux"],
              @"the root document's folder is cloned into the Experiment folder, except the Experiment's own names");
        Check([copiedAux.path isEqualToString:[root.fileURL.path.stringByDeletingPathExtension stringByAppendingPathExtension:@"aux"]] &&
              [copiedTo.path isEqualToString:[c.directory URLByAppendingPathComponent:@"TeXShop-document.aux"].path],
              @"the root document's .aux is copied under its own name, not as the Experiment's file.aux");
        CheckNormal(d, normal);
        // A hidden Experiment panel (e.g. application inactive) must still update.
        d->scrapWindow.isVisible = NO;
        NSURL *pdf = [c.directory URLByAppendingPathComponent:@"file.pdf"];
        [@"fixture" writeToURL:pdf atomically:YES encoding:NSUTF8StringEncoding error:NULL];
        c.completion(pdf);
        Check(d->scrapPDFKitView.reloads == 1, @"PDF completion loads while Experiment source is hidden");
        Check(d->scrapPDFWindow.shows == 1 && d->scrapPDFKitView.outputShows == 1 && d->scrapPDFKitView.shownBeforeOutput == shownWindows,
              @"PDF view is told after its window is shown, so a first output can show its top");
        RemoveOutput(c);
    } @catch (NSException *e) {
        Check(NO, [@"preamble extraction must not throw: " stringByAppendingString:e.name]);
        RemoveOutput(d.experimentConsole);
    }
}
// The engine of the source toolbar (its index in the menu: plain TeX, LaTeX, BibTeX, MakeIndex,
// MetaPost, then the engines of ~/Library/TeXShop/Engines) or of a "% !TEX program" line.
static NSString *ExperimentExecutable(NSInteger index, NSArray *titles, NSString *magic, NSInteger script, BOOL *refused) {
    Document *d = D();
    d.programButton.itemTitles = titles;
    d.programButton.indexOfSelectedItem = index;
    d->whichScript = script;
    d.textView.string = magic ? [magic stringByAppendingString:@"\n\\begin{document}x"] : @"\\begin{document}x";
    NSUInteger before = beeps;
    clonedInto = nil;
    [d typesetScrap:nil];
    Console *c = d.experimentConsole;
    *refused = c.starts == 0 && beeps == before + 1 && clonedInto != nil
        && ![[NSFileManager defaultManager] fileExistsAtPath:clonedInto.path];
    NSString *executable = c.starts == 1 && beeps == before ? c.executable : nil;
    RemoveOutput(c);
    return executable;
}
static NSArray *Engines(NSArray *users) {
    return [@[@"plain TeX", @"LaTeX", @"BibTeX", @"MakeIndex", @"MetaPost"] arrayByAddingObjectsFromArray:users];
}
static void CheckRefused(NSInteger index, NSArray *titles, NSString *magic, NSString *label) {
    BOOL refused = NO;
    ExperimentExecutable(index, titles, magic, 100, &refused);
    Check(refused, [label stringByAppendingString:@": no job starts, a beep, and the Experiment folder is removed"]);
}
static void CheckEngine(NSInteger index, NSArray *titles, NSString *magic, NSInteger script, NSString *expected, NSString *label) {
    BOOL refused = YES;
    NSString *executable = ExperimentExecutable(index, titles, magic, script, &refused);
    Check(!refused && [executable isEqualToString:expected],
          [NSString stringWithFormat:@"%@: expected %@, got %@", label, expected, executable]);
}
static void CheckEngines(void) {
    NSArray *users = Engines(@[@"ConTeXt", @"ConTeXt-TL", @"My Engine", @"XeLaTeX"]);
    CheckRefused(0, users, nil, @"plain TeX of the toolbar");
    CheckRefused(0, @[@"TeX (localized)", @"LaTeX", @"BibTeX", @"MakeIndex", @"MetaPost"], nil, @"plain TeX of the toolbar under another title");
    CheckRefused(4, users, nil, @"MetaPost of the toolbar");
    CheckRefused(5, users, nil, @"ConTeXt engine of the toolbar");
    CheckRefused(6, users, nil, @"ConTeXt-TL engine of the toolbar");
    CheckRefused(-1, users, nil, @"no engine selected in the toolbar");
    CheckEngine(1, users, nil, 100, @"/engine/pdf", @"LaTeX with pdfTeX");
    CheckEngine(1, users, nil, 101, @"/engine/dvi", @"LaTeX with TeX and DVI");
    CheckEngine(1, users, nil, 102, @"/engine/personal", @"LaTeX with a personal script");
    CheckEngine(2, users, nil, 101, @"/engine/pdf", @"BibTeX of the toolbar");
    CheckEngine(3, users, nil, 102, @"/engine/pdf", @"MakeIndex of the toolbar");
    CheckEngine(7, users, nil, 100, @"/custom-engines/My Engine.engine", @"engine with a space in its name");
    CheckEngine(8, users, nil, 100, @"/custom-engines/XeLaTeX.engine", @"engine keeps the case of its name");
    CheckEngine(5, Engines(@[@"LaTeX"]), nil, 100, @"/custom-engines/LaTeX.engine", @"an engine named LaTeX is that engine");
    for (NSString *program in @[@"plaintex", @"tex", @"pdftex", @"PdfTeX", @"personaltex", @"metapost", @"context", @"ConTeXt-TL"])
        CheckRefused(1, users, [@"% !TEX program = " stringByAppendingString:program],
                     [@"% !TEX program = " stringByAppendingString:program]);
    CheckEngine(0, users, @"% !TEX program = bibtex", 100, @"/engine/pdf", @"% !TEX program = bibtex");
    CheckEngine(0, users, @"%!TEX TS-program = makeindex", 101, @"/engine/pdf", @"%!TEX TS-program = makeindex");
    CheckEngine(0, users, @"% !TEX program = latex", 100, @"/engine/dvi", @"% !TEX program = latex");
    CheckEngine(0, users, @"% !TEX program = pdflatex", 101, @"/engine/pdf", @"% !TEX program = pdflatex");
    CheckEngine(0, users, @"% !TEX program = personallatex", 100, @"/engine/personal", @"% !TEX program = personallatex");
    CheckEngine(0, users, @"% !TEX program = xelatex", 100, @"/custom-engines/XeLaTeX.engine", @"% !TEX program names an engine of the toolbar");
    CheckEngine(0, users, @"% !TEX program = my engine", 100, @"/custom-engines/My Engine.engine", @"% !TEX program names an engine with a space");
    CheckEngine(4, users, @"% !TEX program = lualatex", 100, @"/custom-engines/lualatex.engine", @"% !TEX program names an engine not in the toolbar");
}
int main(void) { @autoreleasepool {
    CheckEngines();
    CheckSource(@"\\begin{document}body", @"", 101, NSISOLatin1StringEncoding, @"/engine/dvi");
    CheckSource(@"preamble\\begin{document}body", @"preamble", 102, NSUTF8StringEncoding, @"/engine/personal");
    CheckSource(@"preamble\n\\begin{document}body", @"preamble\n", 100, NSUnicodeStringEncoding, @"/engine/pdf");
    CheckSource(@"entire preamble", @"entire preamble", 101, NSUTF8StringEncoding, @"/engine/dvi");
    // With a copied .aux, every run reads it at its start with @ as a letter (#8).
    {
        auxCopied = YES;
        Document *d = D(), *root = D(); d.rootDocument = root;
        root.fileURL = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:@"root/main.tex"]];
        root.textView.string = @"pre\\begin{document}x"; root->whichScript = 100;
        [d typesetScrap:nil];
        Console *c = d.experimentConsole;
        NSString *expected = [NSString stringWithFormat:@"pre\n\\AtBeginDocument{\\begingroup\\makeatletter\\csname @input\\endcsname{%@/TeXShop-document.aux}\\endgroup}\\begin{document}\nfragment",
                              c.directory.path];
        Check([c.source hasPrefix:expected], @"the copy of the document's .aux is read with @ as a letter, on the line of \\begin{document}");
        Check([c.directory isEqual:[NSURL fileURLWithPath:c.directory.path isDirectory:YES]] && [c.arguments.lastObject isEqualToString:@"file.tex"],
              @"the Experiment still runs in its own folder");
        RemoveOutput(c);
        auxCopied = NO;
    }
    // Without a root document, own settings remain the fallback.
    Document *d = D(); NSArray *normal = NormalState(d); [d typesetScrap:nil];
    Check([d.experimentConsole.source hasPrefix:@"child preamble\n"], @"unrooted document uses its own preamble");
    Check([d.experimentConsole.executable isEqualToString:@"/engine/pdf"], @"unrooted document uses its own engine");
    CheckNormal(d, normal); RemoveOutput(d.experimentConsole);
    // Explicit TeX magic comments still take priority over root settings.
    d = D(); d.rootDocument = D(); d.rootDocument.encoding = NSISOLatin1StringEncoding;
    d.rootDocument.textView.string = @"% !TEX program = lualatex\n% !TEX encoding = UTF-8\n\\begin{document}";
    [d typesetScrap:nil];
    Check([d.experimentConsole.executable isEqualToString:@"/custom-engines/lualatex.engine"], @"magic engine directive takes priority");
    Check(d.experimentConsole.encoding == NSUTF8StringEncoding, @"magic encoding directive takes priority");
    RemoveOutput(d.experimentConsole);
    // Closing the Experiment source invalidates only its console/job and preview.
    d = D(); Console *c = [d ensureExperimentConsole]; normal = NormalState(d);
    [d windowWillClose:[NSNotification notificationWithName:@"close" object:d->outputWindow]];
    Check(c.invalidations == 0 && d.experimentConsole == c, @"unrelated window close does not invalidate Experiment");
    [d windowWillClose:[NSNotification notificationWithName:@"close" object:d->scrapWindow]];
    Check(c.invalidations == 1 && !d.experimentConsole, @"Experiment source close invalidates its job");
    Check(d->scrapPDFWindow.closes == 1 && !d->scrapPDFKitView.document, @"Experiment close clears its preview");
    CheckNormal(d, normal);
    // Full document close must invoke the same cancellation path.
    d = D(); c = [d ensureExperimentConsole]; spellingDefaultsApplied = 0; [d close];
    Check(c.invalidations == 1 && !d.experimentConsole, @"document close invalidates Experiment before teardown");
    Check(d.baseCloses == 1 && d.watchCancellations == 1 && d.pdfStops == 1, @"document close continues ordinary teardown");
    Check(spellingDefaultsApplied == 1, @"document close lets the spell checker return to the Settings choice");
    printf("%lu checks, %lu failures\n", (unsigned long)checks, (unsigned long)failures);
    return failures ? 1 : 0;
} }
'''.replace('@@METHODS@@', '\n'.join(methods.values())).replace('@@CONSTANTS@@', constants).replace('@@ENGINE@@', engine)
with tempfile.TemporaryDirectory(prefix='texshop-experiment-document-') as temporary:
    temporary = Path(temporary)
    source, executable = temporary / 'test.m', temporary / 'test'
    source.write_text(program)
    subprocess.run(['xcrun', 'clang', '-fobjc-arc', '-framework', 'Foundation', str(source), '-o', str(executable)], check=True)
    environment = os.environ.copy()
    environment['TMPDIR'] = str(temporary) + '/'
    environment['CFFIXED_USER_HOME'] = str(temporary / 'home')
    (temporary / 'home').mkdir()
    result = subprocess.run([str(executable)], capture_output=True, text=True, env=environment)
    if args.mutation:
        if result.returncode != 1 or 'FAIL:' not in result.stderr:
            raise SystemExit('Mutation did not fail through an assertion:\n' + result.stdout + result.stderr)
        print(f'PASS: detected mutation {args.mutation}')
    else:
        if result.returncode:
            raise SystemExit(result.stdout + result.stderr)
        print('PASS: production Experiment launch/close isolation, preamble, root settings, engines and inactive completion')
        print(result.stdout.strip())
