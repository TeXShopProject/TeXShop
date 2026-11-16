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
/// The menus' states of documents in the external editor mode, read in the background, by file.
@property (nonatomic, strong) NSMutableDictionary<NSURL *, NSNumber *> *externalStates;
@property (nonatomic, strong) NSMutableSet<NSURL *> *pendingExternalStates;
/// Moves on with each choice of an item: only the last one opens the window.
@property (nonatomic) NSUInteger openRequest;
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
    _externalStates = [NSMutableDictionary dictionary];
    _pendingExternalStates = [NSMutableSet set];
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

/// What gives a document's text as typesetting reads it for the root: a copy of the text on screen, taken now on the
/// main thread, or for the external editor mode its file, read when the loader is called (on a background queue).
- (NSString *_Nullable (^)(void))textLoaderOfDocument:(TSDocument *)document
{
    if (!document.externalEditor) {
        NSString *text = [document.textStorage.string copy];
        return ^NSString *{ return text; };
    }
    NSURL *url = document.fileURL;
    TSTeXRootSourceCodec *codec = [self makeCodec];
    return ^NSString *{
        NSData *data = url ? [NSData dataWithContentsOfURL:(NSURL *_Nonnull)url] : nil;
        return data ? [codec readData:(NSData *_Nonnull)data url:(NSURL *_Nonnull)url verifyingRoundTrip:NO].text : nil;
    };
}

/// The menus' state of a document, without waiting for a disk: from the text on screen; for the external editor mode
/// from what was last read of its file (it is read again in the background, and the menu shows the new state the next
/// time it opens; meanwhile it reads as a child, which only names the item).
- (TSTeXRootEntryState)menuStateOfDocument:(nullable TSDocument *)document
{
    if (!document)
        return TSTeXRootEntryStateNoDocument;
    BOOL allows = [SUD boolForKey:UseOldHeadingCommandsKey];
    if (!document.externalEditor || !document.fileURL || ![document.fileURL.pathExtension isEqualToString:@"tex"])
        return [TSTeXRootEntryRules menuStateForDocumentURL:document.fileURL text:document.externalEditor ? nil : document.textStorage.string allowingSourceDoc:allows];
    NSURL *url = (NSURL *_Nonnull)document.fileURL;
    NSNumber *known = self.externalStates[url];
    if (![self.pendingExternalStates containsObject:url]) {
        [self.pendingExternalStates addObject:url];
        __weak typeof(self) weakSelf = self;
        [TSTeXRootEntryRules menuStateForDocumentURL:url textLoader:[self textLoaderOfDocument:document] allowingSourceDoc:allows
                                          completion:^(TSTeXRootEntryState state) {
            weakSelf.externalStates[url] = @(state);
            [weakSelf.pendingExternalStates removeObject:url];
        }];
    }
    return known ? (TSTeXRootEntryState)known.integerValue : TSTeXRootEntryStateChild;
}

- (BOOL)validateMenuItem:(NSMenuItem *)item
{
    BOOL applying = item.action == @selector(applySetToTeXRootSources:);
    if (item.action != @selector(showTeXRootSearch:) && !applying)
        return YES;
    TSTeXRootEntryState state = [self menuStateOfDocument:[self targetDocument]];
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

/// The root is found and checked on a background queue (the file system may be slow, or the file not yet downloaded);
/// then the window opens, or the warning is shown.
- (void)openWithMode:(TSTeXRootSearchMode)mode setName:(nullable NSString *)name sender:(nullable id)sender
{
    TSDocument *document = [self targetDocument];
    NSURL *documentURL = document.fileURL;
    if (!document || !documentURL || ![documentURL.pathExtension isEqualToString:@"tex"]) {
        NSBeep();
        return;
    }
    NSUInteger request = ++self.openRequest;
    __weak typeof(self) weakSelf = self;
    __weak TSDocument *weakDocument = document;
    [TSTeXRootEntryRules resolveRootForDocumentURL:(NSURL *_Nonnull)documentURL textLoader:[self textLoaderOfDocument:document]
                                 allowingSourceDoc:[SUD boolForKey:UseOldHeadingCommandsKey]
                                      jobNameToken:[document filterBackslashes:@"\\jobname"] ?: @"\\jobname"
                                        completion:^(TSTeXRootEntryState state, NSURL *rootURL, TSTeXRootProblem problem) {
        typeof(self) entry = weakSelf;
        if (!entry || entry.openRequest != request) // chosen again meanwhile
            return;
        if ((state != TSTeXRootEntryStateChild && state != TSTeXRootEntryStateRoot) || !rootURL) {
            NSBeep();
            return;
        }
        if (problem != TSTeXRootProblemNone) {
            NSAlert *alert = [NSAlert new];
            alert.alertStyle = NSAlertStyleWarning;
            alert.messageText = [TSTeXRootEntryRules messageForProblem:problem];
            alert.informativeText = rootURL.path ?: @"";
            NSWindow *window = NSApp.keyWindow ?: [weakDocument textWindow];
            if (window)
                [alert beginSheetModalForWindow:(NSWindow *_Nonnull)window completionHandler:nil];
            else
                [alert runModal];
            return;
        }
        TSTeXRootSearchWindowController *controller = entry.windowController;
        controller.mentionsSourceDoc = [SUD boolForKey:UseOldHeadingCommandsKey];
        [entry refreshOpenDocuments];
        [controller openForRootURL:(NSURL *_Nonnull)rootURL environment:[entry makeEnvironment] mode:mode setName:name];
        [controller showWindow:sender];
    }];
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

/// The open TeX documents with a file, not in the external editor mode, and their files: what tells whether the texts
/// taken from open documents still stand. Nothing is read from the disk.
- (NSArray *)currentSignature
{
    NSMutableArray *signature = [NSMutableArray array];
    for (NSDocument *document in NSDocumentController.sharedDocumentController.documents) {
        if (![document isKindOfClass:[TSDocument class]] || !document.fileURL)
            continue;
        TSDocument *source = (TSDocument *)document;
        if (source.externalEditor || !source.textStorage)
            continue;
        [signature addObject:@[[NSValue valueWithNonretainedObject:source], (NSURL *_Nonnull)source.fileURL]];
    }
    return signature;
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
    __weak typeof(self) weakEntry = self;
    environment.documentsSignature = ^id<NSObject> {
        return [weakEntry currentSignature] ?: @[];
    };
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
    if (![oldSignature isEqual:self.signature])
        [model openDocumentsDidChange]; // also while collecting: the model checks the signature again before listing
    else if (![oldEditable isEqual:self.editableSignature])
        [model documentsDidChange];
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
