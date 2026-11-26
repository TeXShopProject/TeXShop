//
//  CustomModalWindowViewController.m
//  CustomModalWindow
//
//  Based on Nick Kuh, 16/01/2015.
//

#import <AppKit/AppKit.h>
#import "TSDocument.h"
#import "TSEncodingSupport.h"
#import "CustomModalWindowController.h"


@interface CustomModalWindowController ()

@end

@implementation CustomModalWindowController


- (IBAction)didTapCancelButton:(id)sender {
    [myDocument initializeTempEncoding];
 //   theCode = [myDocument temporaryEncoding];
 //    NSLog(@"The current temporary encoding is %ld", theCode);
   [self.window.sheetParent endSheet:self.window returnCode:NSModalResponseCancel];
}

- (IBAction)didTapDoneButton:(id)sender {
    
    [myDocument activateTempEncoding];
    [self.window.sheetParent endSheet:self.window returnCode:NSModalResponseOK];
}

- (IBAction) itemChosen:(id)sender
{
    
    [myDocument chooseTempEncoding:sender];
    
}

// Create the contents of the encoding menu on the fly & select the active encoding
- (void)initializeEncodingMatrix: (TSDocument *)theDocument;
{
    NSStringEncoding currentEncoding;

    myDocument = theDocument;
    
    
//    NSLog(@"Initializing");
    
    
    
    currentEncoding = [myDocument currentDocumentEncoding];
    
//  NSLog(@"The current encoding is %ld", currentEncoding);
    
    currentEncoding = [[TSEncodingSupport sharedInstance] defaultEncoding];
    [myDocument initializeTempEncoding];
    
//    NSLog(@"The current encoding is %ld", currentEncoding);

    [self.theEncodings removeAllItems];
    [[TSEncodingSupport sharedInstance] addEncodingsToMenu:self.theEncodings.menu withTarget:0 action:0];
    [self.theEncodings selectItemWithTag: currentEncoding];
    [self fitWindowToContents];
}

// The sheet takes the size its contents need in the current language. The warning is two lines
// in Korean and Chinese and four in German and Dutch, so one size in the nib is too big or too small.
- (void)fitWindowToContents
{
    NSView *contents = self.window.contentView;
    [contents layoutSubtreeIfNeeded];
    NSSize size = contents.fittingSize;
    self.window.contentMinSize = size;
    [self.window setContentSize:size];
}


@end
