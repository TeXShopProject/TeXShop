// SPDX-License-Identifier: GPL-2.0-or-later
#import "TSTeXRootSearchEntry.h"
#import "TSDocument.h"
#import "TSEncodingSupport.h"
#import "TSRootFileResolver.h"
#import "TSSourceMagicComments.h"
#import "TSTeXRootProject.h"
#import "TSMultipleReplaceMenu.h"
#import "TSAdvancedFindTextView.h"
#import "TSRegexTextFind.h"
#import "globals.h"

#define TSLocalized TSAdvancedFindLocalized

static NSString *const TSFindItemIdentifier = @"TSShortcut.showTeXRootSearch:.0";
static TSTeXRootSearchEntry *TSSharedEntry;

/// An open document as the window sees it: its text, the file it shows, and whether it can be edited.
@interface TSTeXRootOpenDocument : NSObject
@property (nonatomic, weak) TSDocument *document;
@property (nonatomic, strong, nullable) id identifier;
@property (nonatomic, weak) NSTextStorage *storage;
@end

@implementation TSTeXRootOpenDocument
@end

@interface TSTeXRootSearchEntry ()
@property (nonatomic, readonly) TSAdvancedFindController *findController;
@property (nonatomic, readonly) TSMultipleReplaceLibrary *library;
@property (nonatomic, strong, nullable) TSTeXRootSearchWindowController *madeWindowController;
/// The open documents and the files they show, kept while the window is open; `signature` tells when they change.
@property (nonatomic, copy) NSArray<TSTeXRootOpenDocument *> *openDocuments;
@property (nonatomic, copy, nullable) NSArray *signature;
@property (nonatomic, copy, nullable) NSArray *editableSignature;
@end

@implementation TSTeXRootSearchEntry

+ (nullable TSTeXRootSearchEntry *)sharedEntry
{
    return TSSharedEntry;
}

+ (void)installInMainMenu:(NSMenu *)mainMenu findController:(TSAdvancedFindController *)findController library:(TSMultipleReplaceLibrary *)library
{
    if (!TSSharedEntry)
        TSSharedEntry = [[TSTeXRootSearchEntry alloc] initWithFindController:findController library:library];
    TSAdvancedFindController.texRootSearchTarget = TSSharedEntry;
    // The Find submenu: after "Multiple Replace" ▸ (or at the end), where a key can be given in Settings › Keyboard.
    NSMenu *findMenu = nil;
    NSMutableArray<NSMenu *> *menus = [NSMutableArray arrayWithObject:mainMenu];
    while (menus.count && !findMenu) {
        NSMenu *menu = menus.lastObject;
        [menus removeLastObject];
        for (NSMenuItem *item in menu.itemArray) {
            if ([item.identifier isEqualToString:TSFindItemIdentifier])
                return;
            if ([item.identifier isEqualToString:@"TSShortcut.showMultipleReplace:.0"] || item.action == @selector(centerSelectionInVisibleArea:))
                findMenu = menu;
            if (item.submenu)
                [menus addObject:(NSMenu *_Nonnull)item.submenu];
        }
    }
    if (!findMenu)
        return;
    NSInteger index = findMenu.numberOfItems;
    for (NSInteger i = 0; i < findMenu.numberOfItems; i++) {
        NSMenuItem *item = [findMenu itemAtIndex:i];
        if (item.action == @selector(applySet:) && item.submenu)
            index = i + 1;
    }
    NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:[TSTeXRootEntryRules titleForState:TSTeXRootEntryStateChild applying:NO]
                                                  action:@selector(showTeXRootSearch:) keyEquivalent:@""];
    item.identifier = TSFindItemIdentifier;
    item.target = TSSharedEntry;
    [findMenu insertItem:item atIndex:index];
}

- (instancetype)initWithFindController:(TSAdvancedFindController *)findController library:(TSMultipleReplaceLibrary *)library
{
    if (!(self = [super init]))
        return nil;
    _findController = findController;
    _library = library;
    _openDocuments = @[];
    return self;
}

- (TSTeXRootSearchWindowController *)windowController
{
    if (!self.madeWindowController) {
        TSTeXRootSearchWindowController *controller = [[TSTeXRootSearchWindowController alloc] initWithFindController:self.findController library:self.library];
        __weak typeof(self) weakSelf = self;
        controller.showItemHandler = ^(TSTeXRootSearchFileResult *file, TSTeXRootSearchItem *item, BOOL front) { [weakSelf showItem:item inFile:file front:front]; };
        controller.openHelpHandler = ^{
            NSString *book = [NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleHelpBookName"];
            [NSHelpManager.sharedHelpManager openHelpAnchor:@"texroot_search" inBook:book];
        };
        controller.editSetHandler = ^(NSString *name) {
            TSMultipleReplaceWindowController *window = TSMultipleReplaceMenu.sharedMenu.windowController;
            [window reloadSets];
            [window selectSetNamed:name];
            [window showWindow:nil];
        };
        self.madeWindowController = controller;
        [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(applicationDidUpdate:) name:NSApplicationDidUpdateNotification object:nil];
        [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(projectTextDidChange:) name:NSTextStorageDidProcessEditingNotification object:nil];
    }
    return (TSTeXRootSearchWindowController *_Nonnull)self.madeWindowController;
}

#pragma mark States and titles

/// The document of the main window, which the panel and the Multiple Replace window act on.
- (nullable TSDocument *)targetDocument
{
    NSTextView *view = TSAdvancedFindController.targetTextView;
    NSWindow *window = view.window ?: NSApp.mainWindow;
    NSDocument *document = window ? [NSDocumentController.sharedDocumentController documentForWindow:(NSWindow *_Nonnull)window] : nil;
    return [document isKindOfClass:[TSDocument class]] ? (TSDocument *)document : nil;
}

/// The document's text as typesetting reads it for the root: on screen, or on the disk in the external editor mode.
- (nullable NSString *)textOfDocument:(TSDocument *)document
{
    if (!document.externalEditor)
        return [document.textStorage.string copy];
    NSData *data = document.fileURL ? [NSData dataWithContentsOfURL:(NSURL *_Nonnull)document.fileURL] : nil;
    return data ? [[self makeCodec] readData:(NSData *_Nonnull)data url:(NSURL *_Nonnull)document.fileURL verifyingRoundTrip:NO].text : nil;
}

- (TSTeXRootEntryState)stateOfDocument:(nullable TSDocument *)document rootURL:(NSURL *_Nullable *_Nullable)rootURL
{
    if (rootURL)
        *rootURL = nil;
    if (!document)
        return TSTeXRootEntryStateNoDocument;
    return [TSTeXRootEntryRules stateForDocumentURL:document.fileURL text:[self textOfDocument:document]
                                   allowingSourceDoc:[SUD boolForKey:UseOldHeadingCommandsKey]
                                        jobNameToken:[document filterBackslashes:@"\\jobname"] ?: @"\\jobname" rootURL:rootURL];
}

- (BOOL)validateMenuItem:(NSMenuItem *)item
{
    BOOL applying = item.action == @selector(applySetToTeXRootSources:);
    if (item.action != @selector(showTeXRootSearch:) && !applying)
        return YES;
    TSTeXRootEntryState state = [self stateOfDocument:[self targetDocument] rootURL:NULL];
    item.title = [TSTeXRootEntryRules titleForState:state applying:applying];
    if (state != TSTeXRootEntryStateChild && state != TSTeXRootEntryStateRoot)
        return NO;
    if (applying)
        return TSMultipleReplaceMenu.sharedMenu.windowController.selectedSetName != nil;
    return YES;
}

#pragma mark Opening

- (IBAction)showTeXRootSearch:(nullable id)sender
{
    [self openWithMode:TSTeXRootSearchModeFind setName:nil sender:sender];
}

- (IBAction)applySetToTeXRootSources:(nullable id)sender
{
    NSString *name = TSMultipleReplaceMenu.sharedMenu.windowController.selectedSetName;
    if (!name) {
        NSBeep();
        return;
    }
    [self openWithMode:TSTeXRootSearchModeMultipleReplace setName:name sender:sender];
}

- (void)openWithMode:(TSTeXRootSearchMode)mode setName:(nullable NSString *)name sender:(nullable id)sender
{
    TSDocument *document = [self targetDocument];
    NSURL *rootURL = nil;
    TSTeXRootEntryState state = [self stateOfDocument:document rootURL:&rootURL];
    if ((state != TSTeXRootEntryStateChild && state != TSTeXRootEntryStateRoot) || !rootURL) {
        NSBeep();
        return;
    }
    TSTeXRootProblem problem = [TSTeXRootProjectCollector problemWithRootURL:(NSURL *_Nonnull)rootURL];
    if (problem != TSTeXRootProblemNone) {
        NSAlert *alert = [NSAlert new];
        alert.alertStyle = NSAlertStyleWarning;
        alert.messageText = [TSTeXRootEntryRules messageForProblem:problem];
        alert.informativeText = rootURL.path ?: @"";
        NSWindow *window = NSApp.keyWindow ?: [document textWindow];
        if (window)
            [alert beginSheetModalForWindow:(NSWindow *_Nonnull)window completionHandler:nil];
        else
            [alert runModal];
        return;
    }
    TSTeXRootSearchWindowController *controller = self.windowController;
    controller.mentionsSourceDoc = [SUD boolForKey:UseOldHeadingCommandsKey];
    [self refreshOpenDocuments];
    [controller openForRootURL:(NSURL *_Nonnull)rootURL environment:[self makeEnvironment] mode:mode setName:name];
    [controller showWindow:sender];
}

#pragma mark What the window needs from TeXShop

/// Reading and writing files as TeXShop opens and saves them, with the settings of now.
- (TSTeXRootSourceCodec *)makeCodec
{
    TSEncodingSupport *support = [TSEncodingSupport sharedInstance];
    BOOL useOld = [SUD boolForKey:UseOldHeadingCommandsKey];
    BOOL detects = !([SUD objectForKey:EncodingAutoDetectionKey] && ![SUD boolForKey:EncodingAutoDetectionKey]);
    NSStringEncoding preferred = [support defaultEncoding];
    return [[TSTeXRootSourceCodec alloc] initWithEncodingForData:^NSStringEncoding(NSData *data, NSURL *url) {
        // As -[TSDocument dataEncoding:] and -encodingForUnmarkedData:URL: choose it for a file opened anew.
        NSString *name = [TSSourceMagicComments encodingNameInHeaderText:[TSSourceMagicComments headerTextOfData:data] allowingOldHeading:useOld];
        if (name)
            return [support stringEncodingForKey:(NSString *_Nonnull)name];
        return detects ? [support detectedEncodingForData:data fileURL:url preferredEncoding:preferred] : preferred;
    } textForEditing:^NSString *(NSString *text, NSStringEncoding encoding) {
        return [support textForEditing:text encoding:encoding];
    } textForSaving:^NSString *(NSString *text, NSStringEncoding encoding) {
        return [support textForSaving:text encoding:encoding];
    }];
}

+ (nullable id)identifierOfURL:(nullable NSURL *)url
{
    if (!url)
        return nil;
    id identifier = nil;
    [url.URLByResolvingSymlinksInPath getResourceValue:&identifier forKey:NSURLFileResourceIdentifierKey error:NULL];
    return identifier;
}

/// The open TeX documents with a file, not in the external editor mode (whose text is the file's).
- (void)refreshOpenDocuments
{
    NSMutableArray<TSTeXRootOpenDocument *> *open = [NSMutableArray array];
    NSMutableArray *signature = [NSMutableArray array], *editable = [NSMutableArray array];
    for (NSDocument *document in NSDocumentController.sharedDocumentController.documents) {
        if (![document isKindOfClass:[TSDocument class]] || !document.fileURL)
            continue;
        TSDocument *source = (TSDocument *)document;
        if (source.externalEditor || !source.textStorage)
            continue;
        TSTeXRootOpenDocument *entry = [TSTeXRootOpenDocument new];
        entry.document = source;
        entry.storage = source.textStorage;
        entry.identifier = [TSTeXRootSearchEntry identifierOfURL:source.fileURL];
        [open addObject:entry];
        [signature addObject:@[[NSValue valueWithNonretainedObject:source], (NSURL *_Nonnull)source.fileURL]];
        NSTextView *view = [source textView];
        [editable addObject:@(view.isEditable)];
    }
    self.openDocuments = open;
    self.signature = signature;
    self.editableSignature = editable;
}

- (NSArray<TSTeXRootOpenDocument *> *)openDocumentsWithIdentifier:(id)identifier
{
    NSMutableArray<TSTeXRootOpenDocument *> *found = [NSMutableArray array];
    for (TSTeXRootOpenDocument *open in self.openDocuments)
        if (open.document && [open.identifier isEqual:identifier])
            [found addObject:open];
    return found;
}

- (TSTeXRootSearchEnvironment *)makeEnvironment
{
    TSTeXRootSearchEnvironment *environment = [TSTeXRootSearchEnvironment new];
    TSTeXRootSourceCodec *codec = [self makeCodec];
    environment.codec = codec;
    __weak typeof(self) weakSelf = self;
    environment.collectorForRoot = ^TSTeXRootProjectCollector *(NSURL *rootURL) {
        TSTeXRootProjectCollector *collector = [[TSTeXRootProjectCollector alloc] initWithRootURL:rootURL codec:codec
                                                                                  allowsSourceDoc:[SUD boolForKey:UseOldHeadingCommandsKey]
                                                                                     jobNameToken:[weakSelf jobNameToken]];
        [weakSelf refreshOpenDocuments];
        NSMutableDictionary *texts = [NSMutableDictionary dictionary];
        for (TSTeXRootOpenDocument *open in weakSelf.openDocuments) {
            id identifier = open.identifier;
            if (identifier && !texts[identifier] && open.storage)
                texts[identifier] = [open.storage.string copy];
        }
        collector.openDocumentTexts = texts;
        return collector;
    };
    environment.sourcesForFiles = ^NSArray<TSTeXRootSearchSource *> *(NSArray<TSTeXRootProjectFile *> *files) {
        NSMutableArray<TSTeXRootSearchSource *> *sources = [NSMutableArray array];
        NSString *lineEnding = [SUD boolForKey:ConvertLFKey] ? @"\n" : nil;
        for (TSTeXRootProjectFile *file in files) {
            NSArray<TSTeXRootOpenDocument *> *open = [weakSelf openDocumentsWithIdentifier:file.identifier];
            TSTeXRootOpenDocument *first = open.firstObject;
            NSTextStorage *storage = first.storage;
            if (!first || !storage) {
                [sources addObject:[[TSTeXRootSearchSource alloc] initWithFile:file]];
                continue;
            }
            NSTextView *view = [first.document textView];
            TSTeXRootSearchOnlyReason reason = open.count > 1 ? TSTeXRootSearchOnlyReasonOpenTwice
                                             : !view.isEditable ? TSTeXRootSearchOnlyReasonNotEditable : TSTeXRootSearchOnlyReasonNone;
            [sources addObject:[[TSTeXRootSearchSource alloc] initWithFile:file openDocumentText:[storage.string copy] lineEnding:lineEnding searchOnlyReason:reason]];
        }
        return sources;
    };
    return environment;
}

- (NSString *)jobNameToken
{
    TSDocument *document = [self targetDocument] ?: self.openDocuments.firstObject.document;
    return document ? [document filterBackslashes:@"\\jobname"] : @"\\jobname";
}

#pragma mark Following the documents

/// Documents opened, closed or renamed: the files are collected again, since a closed document's file must be read
/// from the disk; a document that became read-only or editable: the files are searched again.
- (void)applicationDidUpdate:(NSNotification *)notification
{
    TSTeXRootSearchModel *model = self.madeWindowController.model;
    if (!model || !self.madeWindowController.window.isVisible)
        return;
    NSArray *oldSignature = self.signature, *oldEditable = self.editableSignature;
    [self refreshOpenDocuments];
    if (![oldSignature isEqual:self.signature]) {
        if (model.activity != TSTeXRootSearchActivityCollecting)
            [model collect];
    } else if (![oldEditable isEqual:self.editableSignature]) {
        [model documentsDidChange];
    }
}

/// An open document of the project was edited: only it is searched again (after the pause).
- (void)projectTextDidChange:(NSNotification *)notification
{
    NSTextStorage *storage = notification.object;
    TSTeXRootSearchModel *model = self.madeWindowController.model;
    if (!model.project || !(storage.editedMask & NSTextStorageEditedCharacters))
        return;
    for (TSTeXRootOpenDocument *open in self.openDocuments)
        if (open.storage == storage && open.identifier) {
            [model textDidChangeForFileWithIdentifier:(id _Nonnull)open.identifier];
            return;
        }
}

#pragma mark Showing an item

- (void)selectItem:(TSTeXRootSearchItem *)item inFile:(TSTeXRootSearchFileResult *)file document:(TSDocument *)document front:(BOOL)front
{
    NSTextView *view = [document textView];
    NSString *text = view.string;
    NSRange range = item.range;
    if (!file.source.isOpenDocument) {
        // The file was searched as it is on the disk; the document shows it with its line endings perhaps changed
        // (ConvertLF): the place is found again from the line and the column.
        NSString *source = file.source.text;
        NSUInteger sourceLineStart = 0;
        [source getLineStart:&sourceLineStart end:NULL contentsEnd:NULL forRange:NSMakeRange(item.range.location, 0)];
        NSUInteger column = item.range.location - sourceLineStart;
        NSString *matched = [source substringWithRange:item.range];
        NSUInteger start = 0, line = 1;
        while (line < item.lineNumber && start < text.length) {
            NSUInteger end = 0;
            [text getLineStart:NULL end:&end contentsEnd:NULL forRange:NSMakeRange(start, 0)];
            start = end;
            line++;
        }
        NSString *lineEnding = [SUD boolForKey:ConvertLFKey] ? @"\n" : nil;
        NSUInteger length = lineEnding ? TSRegexStringByReplacingLineEndings(matched, (NSString *_Nonnull)lineEnding).length : matched.length;
        range = NSMakeRange(start + column, length);
    }
    if (NSMaxRange(range) > text.length) {
        NSBeep();
        return;
    }
    view.selectedRange = range;
    [view scrollRangeToVisible:range];
    if (front) {
        [view.window makeKeyAndOrderFront:nil];
        [view.window makeFirstResponder:view];
    } else if (!view.window.isVisible) {
        [view.window orderFront:nil];
    }
    if (view.window.isVisible)
        [view showFindIndicatorForRange:range];
}

- (void)showItem:(TSTeXRootSearchItem *)item inFile:(TSTeXRootSearchFileResult *)file front:(BOOL)front
{
    for (TSTeXRootOpenDocument *open in [self openDocumentsWithIdentifier:file.source.file.identifier])
        if (open.document) {
            [self selectItem:item inFile:file document:(TSDocument *_Nonnull)open.document front:front];
            return;
        }
    __weak typeof(self) weakSelf = self;
    [NSDocumentController.sharedDocumentController openDocumentWithContentsOfURL:file.source.file.url display:YES
                                                               completionHandler:^(NSDocument *document, BOOL alreadyOpen, NSError *error) {
        if ([document isKindOfClass:[TSDocument class]])
            [weakSelf selectItem:item inFile:file document:(TSDocument *)document front:front];
    }];
}

@end
