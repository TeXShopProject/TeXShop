"""Extract the production encoding menu population, without unrelated document I/O."""
import re

def encoding_menu_fixture(root):
    source = (root/'Sources/App/TSEncodingSupport.m').read_text(encoding='latin1')
    def method(signature):
        start = source.index(signature)
        return source[start:source.index('\n}', start)+2]
    table = source[source.index('typedef struct {'):source.index('static TSEncoding _availableTexworksEncodings')]
    # Initialization data is read from production, not copied into the test.
    names = re.search(r'myArray = (\[NSMutableArray arrayWithObjects:.*?\]);', source, re.S)[1]
    return '#define ARRAYSIZE(a) (sizeof(a)/sizeof((a)[0]))\n'+table+"""
@interface EncodingMenuFixture : NSObject
@property (strong) NSArray *availableEncodingsNames;
- (void)addEncodingsToMenu:(NSMenu *)menu withTarget:(id)target action:(SEL)action;
@end
@implementation EncodingMenuFixture
- (instancetype)init {
 self=[super init]; if(!self)return nil;
 self.availableEncodingsNames = """+names+""";
 for(NSUInteger i=0;i<ARRAYSIZE(_availableEncodings);i++) _availableEncodings[i].nsEnc=CFStringConvertEncodingToNSStringEncoding(_availableEncodings[i].cfEnc);
 return self;
}
"""+method('- (NSString *)localizedNameForKey:')+'\n'+method('- (void)addEncodingsToMenu:')+'\n@end\n'
