#import <Cocoa/Cocoa.h>
@interface SessionChecker : NSObject
@property NSView *accessoryView;
@property NSPanel *spellingPanel;
@property (copy) void (^panelUpdate)(void);
@property NSArray *guesses;
@property NSString *guessedWord;
+ (instancetype)sharedSpellChecker;
- (NSString *)language;
- (NSArray *)availableLanguages;
- (NSArray *)guessesForWordRange:(NSRange)range inString:(NSString *)string language:(NSString *)language inSpellDocumentWithTag:(NSInteger)tag;
- (void)updateSpellingPanelWithMisspelledWord:(NSString *)word;
- (NSRange)checkSpellingOfString:(NSString *)s startingAt:(NSInteger)start language:(NSString *)language wrap:(BOOL)wrap inSpellDocumentWithTag:(NSInteger)tag wordCount:(NSInteger *)count;
- (BOOL)hasLearnedWord:(NSString *)word;
- (void)unlearnWord:(NSString *)word;
@end
