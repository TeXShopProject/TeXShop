//
//  GlobalData.h
//  TeXShop
//
//  Created by Richard Koch on 3/20/14.
//
//

#import <Foundation/Foundation.h>

@interface GlobalData : NSObject

@property (retain) NSDictionary		*g_autocompletionDictionary;
@property (retain) NSArray			*g_autocompletionKeys;  // added by Terada
// The input characters whose key binding is also applied to pasted text
// (autocompletionPaste.plist).
@property (retain) NSArray			*g_autocompletionPasteKeys;
@property (retain) NSString         *g_defaultLanguage;
@property (retain) NSString         *CommandCompletionPath;
@property (retain) NSString         *tempAppleScriptPath;

+ (GlobalData *)sharedGlobalData;

// The key bindings applied to pasted text: the rows marked for pasting whose
// output can be used as it is.
- (NSDictionary<NSString *, NSString *> *)pasteKeyBindings;

@end

// YES when an output string has #SEL#, #INS#, #PASTE# or a mark, which only
// make sense where the output is typed.
BOOL TSKeyBindingOutputHasPlaceholder(NSString *output);
// The text with each input character of bindings replaced by its output.
NSString *TSApplyKeyBindings(NSString *text, NSDictionary<NSString *, NSString *> *bindings);
