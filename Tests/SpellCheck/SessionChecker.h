#import <Cocoa/Cocoa.h>
@interface SessionChecker : NSObject
@property NSView *accessoryView;
+ (instancetype)sharedSpellChecker;
- (NSString *)language;
- (NSArray *)availableLanguages;
- (void)updateSpellingPanelWithMisspelledWord:(NSString *)word;
- (NSRange)checkSpellingOfString:(NSString *)s startingAt:(NSInteger)start language:(NSString *)language wrap:(BOOL)wrap inSpellDocumentWithTag:(NSInteger)tag wordCount:(NSInteger *)count;
- (BOOL)hasLearnedWord:(NSString *)word;
- (void)unlearnWord:(NSString *)word;
@end
