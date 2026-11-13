"""The production Experiment console controller, as the checks compile it: its
source, and the stubs it needs (encoding filters copied from their source,
theme colors and preferences)."""
from pathlib import Path


def cut(text, start, end):
    a = text.index(start)
    return text[a:text.index(end, a)]


def controller_source(root):
    return (Path(root) / 'Sources/Typesetting/TSExperimentConsoleController.m').read_text().replace('#import "TSEncodingSupport.h"', '').replace('#import "globals.h"', '')


def prefix(root):
    enc = (Path(root) / 'Sources/App/TSEncodingSupport.m').read_text(encoding='latin1')
    helpers = cut(enc, '// UTF-8 in which each byte that does not start or continue a valid character is replaced', '// The byte order mark that starts data')
    japanese = cut(enc, '// Japanese encodings read the byte 0x5C', '- (BOOL)ptexUtfOutputCheck:')
    filters = enc[enc.index('// replace backslashes by yens'):].rstrip() + '\n'
    return PREFIX.replace('HELPERS', helpers).replace('JAPANESE', japanese).replace('FILTERS', filters)


PREFIX = r'''
#import <Cocoa/Cocoa.h>
#import "TestAppKitIsolation.h"
#import "TSExperimentJob.h"
#import "TSColorSupport.h"
#import "TSEncodingSupport.h"
typedef enum { kNoFilterMode = 0, kMacJapaneseFilterMode = 1, kOtherJapaneseFilterMode = 2 } TSFilterMode;
static TSFilterMode g_shouldFilter = kNoFilterMode;
static NSString *yenString = @"\u00a5";
@implementation TSEncodingSupport
+ (instancetype)sharedInstance { static TSEncodingSupport *s; if (!s) s = [self new]; return s; }
HELPERS
JAPANESE
@end
FILTERS
static NSDictionary *liteColors;
static NSDictionary *darkColors;
@implementation TSColorSupport
+ (id)sharedInstance { static id s; if (!s) s = [self new]; return s; }
- (NSColor *)opaqueColorForKey:(NSString *)key fromDictionary:(NSDictionary *)theme isWindowDark:(BOOL)dark
{ return theme[key] ?: (dark ? NSColor.blackColor : NSColor.whiteColor); }
@end
static BOOL behind;
@interface TestDefaults : NSObject
- (BOOL)boolForKey:(NSString *)key;
- (NSString *)stringForKey:(NSString *)key;
- (float)floatForKey:(NSString *)key;
@end
@implementation TestDefaults
- (NSString *)stringForKey:(NSString *)key { return @"Menlo"; }
- (float)floatForKey:(NSString *)key { return 15; }
- (BOOL)boolForKey:(NSString *)key { return [key isEqualToString:@"ConsoleBehavior"] ? behind : YES; }
@end
#define SUD ((TestDefaults *)[TestDefaults new])
#define SourceColorChangedNotification @"SourceColorChanged"
#define ConsoleFontNameKey @"ConsoleFontName"
#define ConsoleFontSizeKey @"ConsoleFontSize"
#define ConsoleFontChangedNotification @"ConsoleFontChanged"
#define ConsoleBehaviorKey @"ConsoleBehavior"
#define BringPdfFrontOnTypesetKey @"BringPdfFront"
'''
