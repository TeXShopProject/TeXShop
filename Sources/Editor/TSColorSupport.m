//
//  TSColorSupport.m
//  
//
//  Created by Richard Koch on 7/26/2018.
//  Copyright 2018 University of Oregon. All rights reserved.
//

#import "globals.h"
#import "TSLibraryRepair.h"
#import "TSColorSupport.h"
#import "TSThemeFileStore.h"

@implementation TSColorSupport

// Pointer to the TSColorSupport singleton
static id sharedColorSupport = nil;



+ (id)sharedInstance
{
    if (sharedColorSupport == nil) {
        sharedColorSupport = [[TSColorSupport alloc] init];
    }
    return sharedColorSupport;
}

// A user might remove ALL color styles from Library/TeXShop/Colors
// The routine below checks whether LiteTheme.plist and DarkTheme.plist exist in this directory
// If not, it restores them with default files
- (void)checkAndRestoreDefaults;
{
    NSString *reserveLitePath, *reserveDarkPath;
    
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSString *newColorPath = [ColorPath stringByExpandingTildeInPath];
    NSString* liteColorPath = [[newColorPath stringByAppendingString:@"/"] stringByAppendingString: @"LiteTheme.plist"];
    NSString* darkColorPath = [[newColorPath stringByAppendingString:@"/"] stringByAppendingString: @"DarkTheme.plist"];
    
    // Missing, each is restored from the copy inside TeXShop (damaged ones are repaired at launch, TSLibraryRepairAll).
    reserveLitePath = [[NSBundle mainBundle] pathForResource:@"LiteTheme" ofType:@"plist" inDirectory:@"Themes"];
    reserveDarkPath = [[NSBundle mainBundle] pathForResource:@"DarkTheme" ofType:@"plist" inDirectory:@"Themes"];
    TSLibraryRestoreMissingFile(liteColorPath, reserveLitePath, TSLibraryThemeCheck());
    TSLibraryRestoreMissingFile(darkColorPath, reserveDarkPath, TSLibraryThemeCheck());
    (void)fileManager;
}

// Colors of the bundled themes that a later version changed, because text could not be read in them or on them.
// The themes in ~/Library/TeXShop/Themes are copies made when that folder was created, so each copy is given the new
// color where it still has the color that TeXShop gave it. A color the user chose, a renamed copy and a theme of the
// user's own stay as they are. Each change belongs to an update; the last update done is kept in the settings.
typedef struct {
    NSInteger update;
    __unsafe_unretained NSString *theme;
    __unsafe_unretained NSString *key;
    double from[3];
    double to[3];
} TSBundledThemeColorChange;

static const TSBundledThemeColorChange TSBundledThemeColorChanges[] = {
    // 6.00: the content of braces, the active line and the text found by SyncTeX are painted behind the text, which
    // must stay readable on them; brackets, markers, index entries, XML and the commands of Manteuffel are made
    // readable on the background of their themes.
    {1, @"DarkTheme", @"EditorHighlightContent", {0.4756349325, 0.4756467342, 0.4756404161}, {0.270588, 0.25098, 0.176471}},
    {1, @"DarkTheme", @"EntryColor", {0.6386525630950928, 0.1230164617300034, 0.1503929197788239}, {0.258824, 0.258824, 0.258824}},
    {1, @"DarkTheme", @"XMLSpecial", {0.0, 0.3, 1.0}, {0.431373, 0.607843, 1.0}},
    {1, @"Dracula", @"EditorHighlightContent", {0.4756349325, 0.4756467342, 0.4756404161}, {0.25098, 0.243137, 0.172549}},
    {1, @"Dracula", @"EditorReverseSync", {0.9872317910194397, 0.2329826056957245, 0.2662559449672699}, {0.478431, 0.14902, 0.2}},
    {1, @"Dracula", @"EntryColor", {1.0, 0.0, 0.0630970448255539}, {0.180392, 0.188235, 0.243137}},
    {1, @"Dracula", @"SyntaxMarkerCurly", {0.0, 0.0, 0.0}, {0.9725490196078431, 0.9725490196078431, 0.9490196078431372}},
    {1, @"Dracula", @"SyntaxMarkerParen", {0.0, 0.0, 0.0}, {0.9725490196078431, 0.9725490196078431, 0.9490196078431372}},
    {1, @"Dracula", @"SyntaxMarkerSquare", {0.0, 0.0, 0.0}, {0.9725490196078431, 0.9725490196078431, 0.9490196078431372}},
    {1, @"Dracula", @"XMLSpecial", {0.0, 0.3, 1.0}, {0.431373, 0.607843, 1.0}},
    {1, @"GLG-Lite", @"EditorReverseSync", {0.2000000029802322, 0.6000000238418579, 0.9900000095367432}, {0.74902, 0.866667, 0.988235}},
    {1, @"GLG-Lite", @"SyntaxIndex", {1.0, 1.0, 0.0}, {0.541176, 0.427451, 0.0}},
    {1, @"GLG-Lite", @"XMLParameter", {0.0, 1.0, 0.0}, {0.0, 0.541176, 0.0}},
    {1, @"GLG-Lite", @"XMLValue", {0.6, 0.6, 0.2}, {0.478431, 0.478431, 0.121569}},
    {1, @"LiteTheme", @"EditorHighlightContent", {0.8946298956871033, 0.241200892533709, 0.2138740761137153}, {1.0, 0.956863, 0.768627}},
    {1, @"LiteTheme", @"SyntaxIndex", {1.0, 0.9932006001472473, 0.0}, {0.541176, 0.427451, 0.0}},
    {1, @"LiteTheme", @"XMLParameter", {0.0, 1.0, 0.0}, {0.0, 0.541176, 0.0}},
    {1, @"LiteTheme", @"XMLValue", {0.6, 0.6, 0.2}, {0.478431, 0.478431, 0.121569}},
    {1, @"Manteuffel", @"SyntaxCommand", {0.08235294371843338, 0.7098039388656616, 0.9137254953384399}, {0.043137, 0.52549, 0.701961}},
    {1, @"Manteuffel", @"SyntaxIndex", {1.0, 1.0, 0.0}, {0.541176, 0.427451, 0.0}},
    {1, @"Manteuffel", @"XMLParameter", {0.0, 1.0, 0.0}, {0.0, 0.541176, 0.0}},
    {1, @"Manteuffel", @"XMLValue", {0.6, 0.6, 0.2}, {0.478431, 0.478431, 0.121569}},
    {1, @"PreTeXt-Dark", @"EditorHighlightContent", {0.4756349325, 0.4756467342, 0.4756404161}, {0.239216, 0.227451, 0.156863}},
    {1, @"PreTeXt-Dark", @"EntryColor", {1.0, 0.0, 0.0}, {0.188235, 0.192157, 0.164706}},
    {1, @"PreTeXt-Dark", @"XMLSpecial", {0.0, 0.3, 1.0}, {0.431373, 0.607843, 1.0}},
    {1, @"SolarizedDark", @"EditorHighlightContent", {1.0, 1.0, 0.0}, {0.2, 0.188235, 0.039216}},
    {1, @"SolarizedDark", @"EditorReverseSync", {1.0, 1.0, 0.0}, {0.352941, 0.121569, 0.105882}},
    {1, @"SolarizedDark", @"EntryColor", {1.0, 0.0, 0.07932668179273605}, {0.027451, 0.211765, 0.258824}},
    {1, @"SolarizedDark", @"XMLSpecial", {0.0, 0.3, 1.0}, {0.431373, 0.607843, 1.0}},
    {1, @"SolarizedLite", @"SyntaxMarker", {0.1650000065565109, 0.6299999952316284, 0.5960000157356262}, {0.8299999833106995, 0.2099999934434891, 0.5099999904632568}},
    {1, @"SolarizedLite", @"XMLParameter", {0.0, 1.0, 0.0}, {0.0, 0.541176, 0.0}},
    {1, @"SolarizedLite", @"XMLValue", {0.6, 0.6, 0.2}, {0.478431, 0.478431, 0.121569}},
    {1, @"TransparentTheme", @"EditorHighlightContent", {0.9816838723753915, 0.3395324724758731, 0.1522207877986456}, {1.0, 0.956863, 0.768627}},
    {1, @"TransparentTheme", @"SyntaxIndex", {1.0, 1.0, 0.0}, {0.541176, 0.427451, 0.0}},
    {1, @"TransparentTheme", @"SyntaxMarker", {1.0, 0.9703128892638841, 0.2354147580939638}, {0.5, 0.4, 0.0}},
    {1, @"TransparentTheme", @"XMLParameter", {0.0, 1.0, 0.0}, {0.0, 0.541176, 0.0}},
    {1, @"TransparentTheme", @"XMLValue", {0.6, 0.6, 0.2}, {0.478431, 0.478431, 0.121569}},
    // 6.00: every color drawn as text (the text, syntax, expl3 and XML colors, the console and the log) and the
    // matching braces are readable on the background of their themes, and the text found by SyncTeX in Dracula and
    // PreTeXt-Dark on its color; the background of copied images is white.
    {2, @"DarkTheme", @"ImageBackground", {0.0, 0.0, 0.0}, {1.0, 1.0, 1.0}},
    {2, @"DarkTheme", @"SyntaxComment", {0.4214648995014463, 0.4841349735731593, 0.4887142229806348}, {0.596078, 0.764706, 0.47451}},
    {2, @"DarkTheme", @"XMLComment", {0.5, 0.5, 0.5}, {0.615686, 0.615686, 0.615686}},
    {2, @"DarkTheme", @"XMLTag", {1.0, 0.0, 0.2}, {1.0, 0.423529, 0.541176}},
    {2, @"DarkTheme", @"XMLValue", {0.6, 0.6, 0.2}, {0.635294, 0.635294, 0.211765}},
    {2, @"DarkTheme", @"explFunction", {0.5738074183, 0.5655357838, 0.0}, {0.647059, 0.635294, 0.0}},
    {2, @"DarkTheme", @"explVariable", {0.3612271356295268, 0.5538832545280457, 0.1470971305796211}, {0.443137, 0.682353, 0.180392}},
    {2, @"DarkTheme", @"explmsg", {0.2445922347363184, 0.5628632708533178, 0.5655312538146973}, {0.294118, 0.67451, 0.678431}},
    {2, @"DarkTheme", @"explmykey", {0.5337947981286083, 0.2416767935226142, 0.9631578326225281}, {0.709804, 0.529412, 0.976471}},
    {2, @"DarkTheme", @"explmykeyArgument", {0.7865745425224304, 0.3276950635431077, 0.3814485680324715}, {0.85098, 0.529412, 0.564706}},
    {2, @"Dracula", @"EditorReverseSync", {0.478431, 0.14902, 0.2}, {0.439216, 0.137255, 0.184314}},
    {2, @"Dracula", @"ImageBackground", {0.0, 0.0, 0.0}, {1.0, 1.0, 1.0}},
    {2, @"Dracula", @"SyntaxComment", {0.3119781017303467, 0.3640799522399902, 0.5760171413421631}, {0.639216, 0.682353, 0.858824}},
    {2, @"Dracula", @"XMLComment", {0.5, 0.5, 0.5}, {0.533333, 0.533333, 0.533333}},
    {2, @"Dracula", @"XMLTag", {1.0, 0.0, 0.2}, {1.0, 0.211765, 0.368627}},
    {2, @"GLG-Lite", @"EditorHighlightBraces", {1.0, 0.0, 1.0}, {0.752941, 0.0, 0.752941}},
    {2, @"GLG-Lite", @"SyntaxCommand", {0.1294117718935013, 0.4627451002597809, 0.7803921699523926}, {0.121569, 0.439216, 0.741176}},
    {2, @"GLG-Lite", @"SyntaxIndex", {0.541176, 0.427451, 0.0}, {0.533333, 0.419608, 0.0}},
    {2, @"GLG-Lite", @"SyntaxMarker", {0.8627451062202454, 0.196078434586525, 0.1843137294054031}, {0.835294, 0.152941, 0.141176}},
    {2, @"GLG-Lite", @"XMLComment", {0.5, 0.5, 0.5}, {0.431373, 0.431373, 0.431373}},
    {2, @"GLG-Lite", @"XMLParameter", {0.0, 0.541176, 0.0}, {0.0, 0.505882, 0.0}},
    {2, @"GLG-Lite", @"XMLTag", {1.0, 0.0, 0.2}, {0.870588, 0.0, 0.172549}},
    {2, @"GLG-Lite", @"XMLValue", {0.478431, 0.478431, 0.121569}, {0.447059, 0.447059, 0.113725}},
    {2, @"GLG-Lite", @"explFunction", {0.4235, 0.4431, 0.7686}, {0.376471, 0.396078, 0.74902}},
    {2, @"GLG-Lite", @"explIntenseFunction", {0.8275, 0.2118, 0.5098}, {0.792157, 0.172549, 0.47451}},
    {2, @"GLG-Lite", @"explVariable", {0.5216, 0.6, 0.0}, {0.4, 0.462745, 0.0}},
    {2, @"GLG-Lite", @"explmsg", {0.1647, 0.6314, 0.5961}, {0.12549, 0.478431, 0.454902}},
    {2, @"GLG-Lite", @"explmykey", {0.7961, 0.2941, 0.0863}, {0.752941, 0.278431, 0.082353}},
    {2, @"GLG-Lite", @"explmykeyArgument", {0.7098, 0.5373, 0.0}, {0.545098, 0.411765, 0.0}},
    {2, @"LiteTheme", @"ImageBackground", {0.0, 0.0, 0.0}, {1.0, 1.0, 1.0}},
    {2, @"LiteTheme", @"SyntaxComment", {1.0, 0.0, 0.0}, {0.921569, 0.0, 0.0}},
    {2, @"LiteTheme", @"XMLComment", {0.5, 0.5, 0.5}, {0.458824, 0.458824, 0.458824}},
    {2, @"LiteTheme", @"XMLTag", {1.0, 0.0, 0.2}, {0.913725, 0.0, 0.184314}},
    {2, @"LiteTheme", @"explVariable", {0.3084011078, 0.5618229508, 0.0}, {0.282353, 0.513725, 0.0}},
    {2, @"LiteTheme", @"explmsg", {0.0, 0.5690457821, 0.5746168494}, {0.0, 0.509804, 0.513725}},
    {2, @"LiteTheme", @"explmykeyArgument", {0.8478753566741943, 0.2924012940011032, 0.36077542561165}, {0.835294, 0.231373, 0.305882}},
    {2, @"Manteuffel", @"EditorHighlightBraces", {1.0, 0.0, 1.0}, {0.752941, 0.0, 0.752941}},
    {2, @"Manteuffel", @"EditorInsertionPoint", {0.08235294371843338, 0.7098039388656616, 0.9137254953384399}, {0.054902, 0.466667, 0.603922}},
    {2, @"Manteuffel", @"FootnoteColor", {0.1077135801315308, 0.6468018293380737, 0.8915331959724426}, {0.07451, 0.466667, 0.639216}},
    {2, @"Manteuffel", @"SyntaxCommand", {0.043137, 0.52549, 0.701961}, {0.039216, 0.466667, 0.623529}},
    {2, @"Manteuffel", @"SyntaxComment", {0.7529411911964417, 0.7411764860153198, 0.729411780834198}, {0.243137, 0.490196, 0.243137}},
    {2, @"Manteuffel", @"XMLComment", {0.5, 0.5, 0.5}, {0.435294, 0.435294, 0.435294}},
    {2, @"Manteuffel", @"XMLParameter", {0.0, 0.541176, 0.0}, {0.0, 0.509804, 0.0}},
    {2, @"Manteuffel", @"XMLTag", {1.0, 0.0, 0.2}, {0.878431, 0.0, 0.176471}},
    {2, @"Manteuffel", @"XMLValue", {0.478431, 0.478431, 0.121569}, {0.45098, 0.45098, 0.113725}},
    {2, @"Manteuffel", @"explFunction", {0.2471, 0.4549, 0.7216}, {0.239216, 0.443137, 0.701961}},
    {2, @"Manteuffel", @"explIntenseFunction", {0.6039, 0.3569, 0.7098}, {0.588235, 0.329412, 0.698039}},
    {2, @"Manteuffel", @"explIntenseVariable", {0.5412, 0.5412, 0.5412}, {0.435294, 0.435294, 0.435294}},
    {2, @"Manteuffel", @"explVariable", {0.3608, 0.6039, 0.2353}, {0.290196, 0.486275, 0.188235}},
    {2, @"Manteuffel", @"explmsg", {0.1647, 0.6157, 0.5608}, {0.129412, 0.486275, 0.443137}},
    {2, @"Manteuffel", @"explmykey", {0.8157, 0.5176, 0.1098}, {0.611765, 0.388235, 0.082353}},
    {2, @"Manteuffel", @"explmykeyArgument", {0.7608, 0.3216, 0.2902}, {0.745098, 0.286275, 0.25098}},
    {2, @"PreTeXt-Dark", @"EditorReverseSync", {0.5807225108, 0.066734083, 0.0}, {0.486275, 0.054902, 0.0}},
    {2, @"PreTeXt-Dark", @"ImageBackground", {0.0, 0.0, 0.0}, {1.0, 1.0, 1.0}},
    {2, @"PreTeXt-Dark", @"SyntaxComment", {0.4214648995014463, 0.4841349735731593, 0.4887142229806348}, {0.662745, 0.713725, 0.721569}},
    {2, @"PreTeXt-Dark", @"XMLComment", {0.5, 0.5, 0.5}, {0.529412, 0.529412, 0.529412}},
    {2, @"PreTeXt-Dark", @"XMLTag", {1.0, 0.0, 0.3689290583133698}, {1.0, 0.156863, 0.466667}},
    {2, @"PreTeXt-Dark", @"explmykeyArgument", {0.9765, 0.149, 0.4471}, {0.976471, 0.207843, 0.486275}},
    {2, @"SolarizedDark", @"FootnoteColor", {0.8104339838027954, 0.1117527186870575, 0.1393231600522995}, {0.917647, 0.392157, 0.415686}},
    {2, @"SolarizedDark", @"SyntaxCommand", {0.8600000143051147, 0.1959999948740005, 0.1840000003576279}, {0.894118, 0.403922, 0.396078}},
    {2, @"SolarizedDark", @"SyntaxComment", {0.5992382592506159, 0.1415595600346804, 0.849357360208095}, {0.611765, 0.8, 0.239216}},
    {2, @"SolarizedDark", @"SyntaxIndex", {0.8299999833106995, 0.2099999934434891, 0.5099999904632568}, {0.870588, 0.4, 0.627451}},
    {2, @"SolarizedDark", @"XMLComment", {0.5, 0.5, 0.5}, {0.560784, 0.560784, 0.560784}},
    {2, @"SolarizedDark", @"XMLTag", {1.0, 0.0, 0.2}, {1.0, 0.290196, 0.431373}},
    {2, @"SolarizedDark", @"explFunction", {0.149, 0.5451, 0.8235}, {0.2, 0.584314, 0.854902}},
    {2, @"SolarizedDark", @"explIntenseFunction", {0.4235, 0.4431, 0.7686}, {0.521569, 0.537255, 0.807843}},
    {2, @"SolarizedDark", @"explmykey", {0.7961, 0.2941, 0.0863}, {0.913725, 0.403922, 0.192157}},
    {2, @"SolarizedLite", @"EditorHighlightBraces", {1.0, 0.0, 1.0}, {0.752941, 0.0, 0.752941}},
    {2, @"SolarizedLite", @"EditorText", {0.4000000059604645, 0.4799999892711639, 0.5099999904632568}, {0.372549, 0.447059, 0.478431}},
    {2, @"SolarizedLite", @"LogText", {0.4000000059604645, 0.4799999892711639, 0.5099999904632568}, {0.372549, 0.447059, 0.478431}},
    {2, @"SolarizedLite", @"SyntaxCommand", {0.8600000143051147, 0.1959999948740005, 0.1840000003576279}, {0.839216, 0.156863, 0.145098}},
    {2, @"SolarizedLite", @"SyntaxComment", {0.5799999833106995, 0.6299999952316284, 0.6299999952316284}, {0.376471, 0.396078, 0.74902}},
    {2, @"SolarizedLite", @"SyntaxIndex", {0.8299999833106995, 0.2099999934434891, 0.5099999904632568}, {0.796078, 0.172549, 0.47451}},
    {2, @"SolarizedLite", @"SyntaxMarker", {0.8299999833106995, 0.2099999934434891, 0.5099999904632568}, {0.796078, 0.172549, 0.47451}},
    {2, @"SolarizedLite", @"XMLComment", {0.5, 0.5, 0.5}, {0.435294, 0.435294, 0.435294}},
    {2, @"SolarizedLite", @"XMLParameter", {0.0, 0.541176, 0.0}, {0.0, 0.509804, 0.0}},
    {2, @"SolarizedLite", @"XMLTag", {1.0, 0.0, 0.2}, {0.87451, 0.0, 0.176471}},
    {2, @"SolarizedLite", @"XMLValue", {0.478431, 0.478431, 0.121569}, {0.447059, 0.447059, 0.113725}},
    {2, @"SolarizedLite", @"explFunction", {0.149, 0.5451, 0.8235}, {0.12549, 0.454902, 0.686275}},
    {2, @"SolarizedLite", @"explIntenseFunction", {0.4235, 0.4431, 0.7686}, {0.376471, 0.396078, 0.74902}},
    {2, @"SolarizedLite", @"explVariable", {0.5216, 0.6, 0.0}, {0.4, 0.462745, 0.0}},
    {2, @"SolarizedLite", @"explmsg", {0.1647, 0.6314, 0.5961}, {0.12549, 0.478431, 0.454902}},
    {2, @"SolarizedLite", @"explmykey", {0.7961, 0.2941, 0.0863}, {0.756863, 0.278431, 0.082353}},
    {2, @"SolarizedLite", @"explmykeyArgument", {0.7098, 0.5373, 0.0}, {0.545098, 0.411765, 0.0}},
    {2, @"TransparentTheme", @"ConsoleText", {0.03342935759671994, 0.490464023518719, 1.0}, {0.0, 0.423529, 0.898039}},
    {2, @"TransparentTheme", @"EditorText", {0.659283788071066, 0.3899459829154598, 0.519830080548534}, {0.619608, 0.345098, 0.478431}},
    {2, @"TransparentTheme", @"FootnoteColor", {0.2264918088912964, 0.5419937968254089, 0.9477165937423706}, {0.058824, 0.411765, 0.870588}},
    {2, @"TransparentTheme", @"ImageBackground", {0.0, 0.0, 0.0}, {1.0, 1.0, 1.0}},
    {2, @"TransparentTheme", @"SyntaxCommand", {0.2747414999891776, 0.6231743567483239, 0.9596965909004211}, {0.043137, 0.431373, 0.807843}},
    {2, @"TransparentTheme", @"SyntaxComment", {0.9175150990486145, 0.4509730964372159, 0.05484317457009981}, {0.760784, 0.254902, 0.047059}},
    {2, @"TransparentTheme", @"XMLComment", {0.5, 0.5, 0.5}, {0.431373, 0.431373, 0.431373}},
    {2, @"TransparentTheme", @"XMLParameter", {0.0, 0.541176, 0.0}, {0.0, 0.505882, 0.0}},
    {2, @"TransparentTheme", @"XMLTag", {1.0, 0.0, 0.2}, {0.87451, 0.0, 0.176471}},
    {2, @"TransparentTheme", @"XMLValue", {0.478431, 0.478431, 0.121569}, {0.447059, 0.447059, 0.113725}},
    {2, @"TransparentTheme", @"explIntenseFunction", {0.7059, 0.2824, 0.6078}, {0.690196, 0.27451, 0.592157}},
    {2, @"TransparentTheme", @"explIntenseVariable", {0.4588, 0.4588, 0.4588}, {0.431373, 0.431373, 0.431373}},
    {2, @"TransparentTheme", @"explVariable", {0.1804, 0.5451, 0.3412}, {0.160784, 0.490196, 0.305882}},
    {2, @"TransparentTheme", @"explmsg", {0.0, 0.5137, 0.5608}, {0.0, 0.482353, 0.52549}},
};

// Gives the colors of the updates after the given one to a copy of a bundled theme, where it still has the old color.
static BOOL TSApplyBundledThemeColorChanges(NSMutableDictionary *colors, NSString *theme, NSInteger update)
{
    const size_t count = sizeof(TSBundledThemeColorChanges) / sizeof(TSBundledThemeColorChanges[0]);
    BOOL changed = NO;
    for (size_t i = 0; i < count; i++) {
        const TSBundledThemeColorChange *change = &TSBundledThemeColorChanges[i];
        if (change->update <= update || ![change->theme isEqualToString:theme])
            continue;
        NSMutableArray *color = colors[change->key];
        if (![color isKindOfClass:NSMutableArray.class] || color.count < 3)
            continue;
        BOOL unchanged = YES;
        for (NSUInteger c = 0; c < 3; c++)
            unchanged = unchanged && [color[c] isKindOfClass:NSNumber.class] && fabs([color[c] doubleValue] - change->from[c]) < 0.0005;
        if (!unchanged)
            continue;
        // The opacity, if any, stays.
        for (NSUInteger c = 0; c < 3; c++)
            color[c] = @(change->to[c]);
        changed = YES;
    }
    return changed;
}

// Updates one theme file; NO if it exists but could not be read or written. Another TeXShop may save the theme at the
// same time: the file is coordinated with the theme saves of this version, and it is replaced only if it still holds
// what was read; otherwise it is read again, so that a color saved meanwhile is kept.
static BOOL TSUpdateBundledThemeFile(NSURL *url, NSString *theme, NSInteger update)
{
    __block BOOL done = NO;
    NSError *coordinationError = nil;
    NSFileCoordinator *coordinator = [[NSFileCoordinator alloc] initWithFilePresenter:nil];
    [coordinator coordinateWritingItemAtURL:url options:NSFileCoordinatorWritingForMerging error:&coordinationError byAccessor:^(NSURL *fileURL) {
        for (NSUInteger attempt = 0; attempt < 5; attempt++) {
            NSData *data = [NSData dataWithContentsOfURL:fileURL];
            NSMutableDictionary *colors = data ? [NSPropertyListSerialization propertyListWithData:data options:NSPropertyListMutableContainers format:NULL error:NULL] : nil;
            if (![colors isKindOfClass:NSMutableDictionary.class])
                return;
            if (!TSApplyBundledThemeColorChanges(colors, theme, update)) {
                done = YES;
                return;
            }
            NSData *updated = [NSPropertyListSerialization dataWithPropertyList:colors format:NSPropertyListXMLFormat_v1_0 options:0 error:NULL];
            if (updated == nil)
                return;
            if (![[NSData dataWithContentsOfURL:fileURL] isEqualToData:data])
                continue;
            done = [updated writeToURL:fileURL options:NSDataWritingAtomic error:NULL];
            return;
        }
    }];
    return done;
}

// Returns the last update done: every update after the given one, or the given one if a theme that is there could not
// be read or written, so that the update is tried again at the next launch.
- (NSInteger)updateBundledThemeColorsInDirectory: (NSURL *)directory after: (NSInteger)update
{
    const size_t count = sizeof(TSBundledThemeColorChanges) / sizeof(TSBundledThemeColorChanges[0]);
    NSInteger last = update;
    for (size_t i = 0; i < count; i++)
        last = MAX(last, TSBundledThemeColorChanges[i].update);
    if (last == update)
        return update;

    TSThemeFileStore *store = [[TSThemeFileStore alloc] initWithDirectory:directory];
    NSMutableOrderedSet<NSString *> *themes = [NSMutableOrderedSet orderedSet];
    for (size_t i = 0; i < count; i++)
        if (TSBundledThemeColorChanges[i].update > update)
            [themes addObject:TSBundledThemeColorChanges[i].theme];
    BOOL written = YES;
    for (NSString *theme in themes) {
        // A theme that is not there, or is reached through a symbolic link, is left alone.
        NSURL *url = [store URLForTitle:theme];
        if (url == nil || ![[NSFileManager defaultManager] fileExistsAtPath:url.path])
            continue;
        if (!TSUpdateBundledThemeFile(url, theme, update))
            written = NO;
    }
    return written ? last : update;
}

- (void)updateBundledThemeColors
{
    NSInteger update = [SUD integerForKey:BundledThemeColorsUpdateKey];
    NSURL *directory = [NSURL fileURLWithPath:[ColorPath stringByExpandingTildeInPath] isDirectory:YES];
    NSInteger done = [self updateBundledThemeColorsInDirectory:directory after:update];
    if (done != update)
        [SUD setInteger:done forKey:BundledThemeColorsUpdateKey];
}

// This routine sets the Lite and Dark color dictionaries. It also checks to make sure the default color plist exists.
// If not, it switches to LiteColors and/or DarkColors and changes the default values for these items.

- (void)initializeColors
{
    
    NSString *lite = [SUD stringForKey: DefaultLiteThemeKey];
    NSString *dark = [SUD stringForKey: DefaultDarkThemeKey];
    
    NSString *newColorPath = [ColorPath stringByExpandingTildeInPath];
    NSString* liteThemePath = [[[newColorPath stringByAppendingString:@"/"] stringByAppendingString: lite] stringByAppendingString: @".plist"];
    NSString* darkThemePath = [[[newColorPath stringByAppendingString:@"/"] stringByAppendingString: dark] stringByAppendingString: @".plist"];
    NSString* defaultLiteThemePath = [[newColorPath stringByAppendingString:@"/"] stringByAppendingString: @"LiteTheme.plist"];
    NSString* defaultDarkThemePath = [[newColorPath stringByAppendingString:@"/"] stringByAppendingString: @"DarkTheme.plist"];
    
    
    [self checkAndRestoreDefaults];
    // A missing theme that comes with TeXShop is restored like the two above.
    NSString *bundledLite = lite.length ? TSLibraryBundledPath([[@"Themes" stringByAppendingPathComponent:lite] stringByAppendingPathExtension:@"plist"]) : nil;
    NSString *bundledDark = dark.length ? TSLibraryBundledPath([[@"Themes" stringByAppendingPathComponent:dark] stringByAppendingPathExtension:@"plist"]) : nil;
    if (lite.length) TSLibraryRestoreMissingFile(liteThemePath, bundledLite, TSLibraryThemeCheck());
    if (dark.length) TSLibraryRestoreMissingFile(darkThemePath, bundledDark, TSLibraryThemeCheck());
    // One that cannot be restored now (the disk is full, the folder cannot be written) stays chosen: TeXShop's own
    // copy is read, and the next launch restores the file. A missing theme of the user's own gives way to Lite or Dark.
    NSFileManager *fileManager = [NSFileManager defaultManager];
    if (! [fileManager fileExistsAtPath: liteThemePath])
    {
        if (bundledLite != nil)
            liteThemePath = bundledLite;
        else {
            [SUD setObject: @"LiteTheme" forKey: DefaultLiteThemeKey];
            liteThemePath = defaultLiteThemePath;
        }
    }
    if (! [fileManager fileExistsAtPath: darkThemePath])
    {
        if (bundledDark != nil)
            darkThemePath = bundledDark;
        else {
            [SUD setObject: @"DarkTheme" forKey: DefaultDarkThemeKey];
            darkThemePath = defaultDarkThemePath;
        }
    }
    
    // A damaged theme is not read: the theme that comes with TeXShop is used until the next launch repairs it.
    NSString *reserveLite = [[NSBundle mainBundle] pathForResource:@"LiteTheme" ofType:@"plist" inDirectory:@"Themes"];
    NSString *reserveDark = [[NSBundle mainBundle] pathForResource:@"DarkTheme" ofType:@"plist" inDirectory:@"Themes"];
    if (!TSLibraryFileIsUsable(liteThemePath, reserveLite, TSLibraryThemeCheck()) && reserveLite) liteThemePath = reserveLite;
    if (!TSLibraryFileIsUsable(darkThemePath, reserveDark, TSLibraryThemeCheck()) && reserveDark) darkThemePath = reserveDark;
    liteColors = [NSDictionary dictionaryWithContentsOfFile:liteThemePath];
    darkColors = [NSDictionary dictionaryWithContentsOfFile:darkThemePath];
}

- (NSMutableDictionary *) dictionaryForColorFile: (NSString *) fileTitle
{
    
    NSString *newColorPath = [ColorPath stringByExpandingTildeInPath];
    NSString *colorFilePath = [[[newColorPath stringByAppendingString:@"/"] stringByAppendingString: fileTitle] stringByAppendingString: @".plist"];
    return [NSMutableDictionary dictionaryWithContentsOfFile:colorFilePath];
}


// Themes made before brackets had their own colors only define SyntaxMarker.
// A color is an array of red, green, blue and, mostly, opacity; anything else (in a theme file
// edited by hand or by another program) counts as a color the theme does not have.
- (NSArray *) colorArrayFromDictionary:(NSDictionary *)theDictionary andKey: (NSString *)theKey
{
    NSArray *(^color)(id) = ^NSArray *(id value) {
        if (![value isKindOfClass:NSArray.class] || [value count] < 3)
            return nil;
        for (id component in value)
            if (![component isKindOfClass:NSNumber.class])
                return nil;
        return value;
    };
    NSArray *theColorArray = color([theDictionary objectForKey: theKey]);
    if ((theColorArray == nil) &&
        ([theKey isEqualToString: @"SyntaxMarkerParen"] ||
         [theKey isEqualToString: @"SyntaxMarkerCurly"] ||
         [theKey isEqualToString: @"SyntaxMarkerSquare"]))
        theColorArray = color([theDictionary objectForKey: @"SyntaxMarker"]);
    return theColorArray;
}

- (NSColor *) colorFromDictionary:(NSDictionary *)theDictionary andKey: (NSString *)theKey
{
    NSArray *theColorArray = [self colorArrayFromDictionary: theDictionary andKey: theKey];
    if (theColorArray == nil)
        return nil;
    NSColor *theColor = [NSColor colorWithRed: [theColorArray[0] doubleValue]  green: [theColorArray[1] doubleValue]  blue: [theColorArray[2] doubleValue]  alpha:1.00];
    
    return theColor;
}


- (NSColor *) colorAndAlphaFromDictionary:(NSDictionary *)theDictionary andKey: (NSString *)theKey
{
    // Without the bracket colors' fallback of -colorArrayFromDictionary:andKey:.
    NSArray *theColorArray = [theDictionary objectForKey: theKey];
    if (theColorArray == nil || [self colorArrayFromDictionary: @{theKey: theColorArray} andKey: theKey] == nil)
        return nil;
    NSColor *theColor = [NSColor colorWithRed: [theColorArray[0] doubleValue]  green: [theColorArray[1] doubleValue]  blue: [theColorArray[2] doubleValue]  alpha: (theColorArray.count >= 4 ? [theColorArray[3] doubleValue] : 1.0)];
    
    return theColor;
}

// When colors are added later, dictionaries may not have them; the four calls below give default values until the user selects new
// colors for these keys and consequentlycolor adds entries to dictionaries

- (NSColor *)liteColorWithKey: (NSString *)theKey
{
    // A theme that has lost one of these colors (its file edited elsewhere) gets the color of the Lite
    // theme: text stays readable on its background. The theme file is not changed.
    NSArray *builtIn = @{
        @"EditorText": @[@0, @0, @0, @1],
        @"EditorBackground": @[@1, @1, @1, @1],
        @"EditorInsertionPoint": @[@0, @0, @0, @1],
        @"ConsoleText": @[@0, @0, @0, @1],
        @"ConsoleBackground": @[@0.996, @0.977, @0.918, @1],
        @"LogText": @[@0, @0, @0, @1],
        @"LogBackground": @[@1, @1, @1, @1],
        @"PreviewBackground": @[@1, @1, @1, @1],
        @"SyntaxComment": @[@0.922, @0, @0, @1],
        @"SyntaxCommand": @[@0, @0, @1, @1],
        @"SyntaxMarker": @[@0.02, @0.51, @0.13, @1],
        @"SyntaxIndex": @[@0.541, @0.427, @0, @1],
        @"EditorHighlightBraces": @[@0.962, @0.223, @0.219, @1],
        @"EditorHighlightContent": @[@1, @0.957, @0.769, @1],
        @"EditorInvisibleChar": @[@1, @0.013, @0.011, @1],
        @"EditorReverseSync": @[@1, @1, @0, @1],
        @"PreviewDirectSync": @[@1, @1, @0, @0.6],
        @"ImageForeground": @[@0, @0, @0, @1],
        @"ImageBackground": @[@1, @1, @1, @0]
    }[theKey];
    if (builtIn != nil)
        return [NSColor colorWithRed: [builtIn[0] doubleValue] green: [builtIn[1] doubleValue] blue: [builtIn[2] doubleValue] alpha: [builtIn[3] doubleValue]];
    if ([theKey isEqualToString: @"EditorFlash"])
        return [NSColor colorWithRed: 1 green: 0.95 blue: 1 alpha:1.00];
    else if ([theKey isEqualToString: @"FootnoteColor"]) //not actually used
        return [NSColor colorWithRed: 0.35  green: 0.35  blue: 0.35 alpha:1.00];
    else if ([theKey isEqualToString: @"EntryColor"])
        return [NSColor colorWithRed: 0.9  green: 0.99  blue: 0.99 alpha:1.00];

    else if ([theKey isEqualToString: @"XMLComment"])
            return [NSColor colorWithRed: 0.50  green: 0.50  blue: 0.50 alpha:1.00];
        else if ([theKey isEqualToString: @"XMLTag"])
            return [NSColor colorWithRed: 1.00  green: 0.00  blue: 0.20 alpha:1.00];
        else if ([theKey isEqualToString: @"XMLSpecial"])
            return [NSColor colorWithRed: 0.00  green: 0.30  blue: 1.00 alpha:1.00];
        else if ([theKey isEqualToString: @"XMLParameter"])
            return [NSColor colorWithRed: 0.00  green: 1.00  blue: 0.00 alpha:1.00];
        else if ([theKey isEqualToString: @"XMLValue"])
            return [NSColor colorWithRed: 0.60  green: 0.60  blue: 0.20 alpha:1.00];
    
    /*
    myColor1 = [NSColor colorWithRed: 1.0 green: 0.0 blue: 1.0 alpha: 1.00];
    self.explColorAttribute1 = [[NSDictionary alloc] initWithObjectsAndKeys:myColor1, NSForegroundColorAttributeName, nil];
    myColor2 = [NSColor colorWithRed: .2 green: 0.5 blue: 0.5 alpha: 1.00];
    self.explColorAttribute2 = [[NSDictionary alloc] initWithObjectsAndKeys:myColor2, NSForegroundColorAttributeName, nil];
    myColor3 = [NSColor colorWithRed: .5 green: 0.5 blue: .5 alpha: 1.00];
    self.explColorAttribute3 = [[NSDictionary alloc] initWithObjectsAndKeys:myColor3, NSForegroundColorAttributeName, nil];
    myColor4 = [NSColor colorWithRed: .8 green: 0.8 blue: 0.1 alpha: 1.00];
    self.explColorAttribute4 = [[NSDictionary alloc] initWithObjectsAndKeys:myColor4, NSForegroundColorAttributeName,nil];
    myColor5 = [NSColor colorWithRed: 1.0 green: 1.0 blue: 0.0 alpha: 1.00];
    self.explColorAttribute5 = [[NSDictionary alloc] initWithObjectsAndKeys:myColor5, NSForegroundColorAttributeName,nil];
    myColor6 = [NSColor colorWithRed: 0.0 green: 1.0 blue: 1.0 alpha: 1.00];
    self.explColorAttribute6 = [[NSDictionary alloc] initWithObjectsAndKeys:myColor6, NSForegroundColorAttributeName,nil];
    myColor7 = [NSColor colorWithRed: 0.7 green: 0.0 blue: 0.7 alpha: 1.00];
    self.explColorAttribute7 = [[NSDictionary alloc] initWithObjectsAndKeys:myColor7, NSForegroundColorAttributeName,nil];
    */
    
        else if ([theKey isEqualToString: @"explFunction"])
            return [NSColor colorWithRed: .00 green: 0.10 blue: 0.57 alpha: 1.00];
        else if ([theKey isEqualToString: @"explVariable"])
            return [NSColor colorWithRed: .31 green: 0.56 blue: .00 alpha: 1.00];
        else if ([theKey isEqualToString: @"explIntenseFunction"])
            return [NSColor colorWithRed: .58 green: 0.32 blue: 0.00 alpha: 1.00];
        else if ([theKey isEqualToString: @"explIntenseVariable"])
            return [NSColor colorWithRed: .37 green: 0.37 blue: .37 alpha: 1.00];
        else if ([theKey isEqualToString: @"explmykey"])
            return [NSColor colorWithRed: .58 green: .21 blue: 1.0 alpha: 1.00];
        else if ([theKey isEqualToString: @"explmykeyArgument"])
            return [NSColor colorWithRed: 0.85 green: 0.29 blue: 0.36 alpha: 1.00];
        else if ([theKey isEqualToString: @"explmsg"])
            return [NSColor colorWithRed: .00 green: .57 blue: .57 alpha: 1.00];
  
    
        else if ([theKey isEqualToString: @"SyntaxMarkerParen"])
            return [NSColor colorWithRed: .02 green: .51 blue: .13 alpha: 1.00];
        else if ([theKey isEqualToString: @"SyntaxMarkerCurly"])
            return [NSColor colorWithRed: .02 green: .51 blue: .13 alpha: 1.00];
        else if ([theKey isEqualToString: @"SyntaxMarkerSquare"])
            return [NSColor colorWithRed: .02 green: .51 blue: .13 alpha: 1.00];
    
    
    else
        return [NSColor colorWithRed: 1.00  green: 1.00 blue: 1.00 alpha:1.00];
}

- (NSColor *)darkColorWithKey: (NSString *)theKey
{
    // A theme that has lost one of these colors (its file edited elsewhere) gets the color of the Dark
    // theme: text stays readable on its background. The theme file is not changed.
    NSArray *builtIn = @{
        @"EditorText": @[@1, @1, @1, @1],
        @"EditorBackground": @[@0.203, @0.203, @0.203, @1],
        @"EditorInsertionPoint": @[@0.9, @0.894, @0.787, @1],
        @"ConsoleText": @[@0.883, @0.713, @0.491, @1],
        @"ConsoleBackground": @[@0.114, @0.172, @0.179, @1],
        @"LogText": @[@0, @0, @0, @1],
        @"LogBackground": @[@0.9, @0.889, @0.872, @1],
        @"PreviewBackground": @[@0.837, @0.837, @0.837, @1],
        @"SyntaxComment": @[@0.596, @0.765, @0.475, @1],
        @"SyntaxCommand": @[@0.42, @0.764, @0.83, @1],
        @"SyntaxMarker": @[@0.968, @0.578, @0.911, @1],
        @"SyntaxIndex": @[@1, @1, @0, @1],
        @"EditorHighlightBraces": @[@1, @0.643, @0.011, @1],
        @"EditorHighlightContent": @[@0.271, @0.251, @0.176, @1],
        @"EditorInvisibleChar": @[@0.5, @0.5, @0.5, @1],
        @"EditorReverseSync": @[@0.581, @0.067, @0, @1],
        @"PreviewDirectSync": @[@0.882, @0.714, @0.489, @0.6],
        @"ImageForeground": @[@0, @0, @0, @1],
        @"ImageBackground": @[@1, @1, @1, @0]
    }[theKey];
    if (builtIn != nil)
        return [NSColor colorWithRed: [builtIn[0] doubleValue] green: [builtIn[1] doubleValue] blue: [builtIn[2] doubleValue] alpha: [builtIn[3] doubleValue]];
    if ([theKey isEqualToString: @"EditorFlash"])
        return [NSColor colorWithRed: 0.00 green: 0.20  blue: 0.20 alpha:1.00];
    else if ([theKey isEqualToString: @"FootnoteColor"]) //not actually used
        return [NSColor colorWithRed: 0.75 green: 0.75 blue: 0.75 alpha:1.00];
    else if ([theKey isEqualToString: @"EntryColor"])
        return [NSColor colorWithRed: 0.1 green: 0.01 blue: 0.01 alpha:1.00];
    
    else if ([theKey isEqualToString: @"XMLComment"]) //not actually used
        return [NSColor colorWithRed: 0.50  green: 0.50  blue: 0.50 alpha:1.00];
    else if ([theKey isEqualToString: @"XMLTag"]) //not actually used
        return [NSColor colorWithRed: 1.00  green: 0.00  blue: 0.20 alpha:1.00];
    else if ([theKey isEqualToString: @"XMLSpecial"]) //not actually used
        return [NSColor colorWithRed: 0.00  green: 0.30  blue: 1.00 alpha:1.00];
    else if ([theKey isEqualToString: @"XMLParameter"]) //not actually used
        return [NSColor colorWithRed: 0.00  green: 1.00  blue: 0.00 alpha:1.00];
    else if ([theKey isEqualToString: @"XMLValue"]) //not actually used
        return [NSColor colorWithRed: 0.60  green: 0.60  blue: 0.20 alpha:1.00];
    
    else if ([theKey isEqualToString: @"explFunction"])
        return [NSColor colorWithRed: .57 green: 0.57 blue: 0.00 alpha: 1.00];
    else if ([theKey isEqualToString: @"explVariable"])
        return [NSColor colorWithRed: .31 green: 0.56 blue: .00 alpha: 1.00];
    else if ([theKey isEqualToString: @"explIntenseFunction"])
        return [NSColor colorWithRed: 1.00 green: 0.58 blue: 0.00 alpha: 1.00];
    else if ([theKey isEqualToString: @"explIntenseVariable"])
        return [NSColor colorWithRed: .66 green: 0.66 blue: .66 alpha: 1.00];
    else if ([theKey isEqualToString: @"explmykey"])
        return [NSColor colorWithRed: 0.709804 green: 0.529412 blue: 0.976471 alpha: 1.00];
    else if ([theKey isEqualToString: @"explmykeyArgument"])
        return [NSColor colorWithRed: 0.85098 green: 0.529412 blue: 0.564706 alpha: 1.00];
    else if ([theKey isEqualToString: @"explmsg"])
        return [NSColor colorWithRed: .00 green: .57 blue: .57 alpha: 1.00];
    
    
    else if ([theKey isEqualToString: @"SyntaxMarkerParen"])
        return [NSColor colorWithRed: 0.96766179800033569 green: 0.57783806324005127 blue: 0.9108852744102478 alpha: 1.00];
    else if ([theKey isEqualToString: @"SyntaxMarkerCurly"])
        return [NSColor colorWithRed: 0.96766179800033569 green: 0.57783806324005127 blue: 0.9108852744102478 alpha: 1.00];
    else if ([theKey isEqualToString: @"SyntaxMarkerSquare"])
        return [NSColor colorWithRed: 0.96766179800033569 green: 0.57783806324005127 blue: 0.9108852744102478 alpha: 1.00];
    
    else
        return [NSColor colorWithRed: 0.00  green: 0.00 blue: 0.00 alpha:1.00];
}


- (NSColor *)liteColorAndAlphaWithKey: (NSString *)theKey
{
    return [self liteColorWithKey: theKey];
}

- (NSColor *)darkColorAndAlphaWithKey: (NSString *)theKey
{
      return [self darkColorWithKey: theKey];
}

// Resolves a color from any theme dictionary, falling back to the built-in default for the given mode.
- (NSColor *)colorForKey: (NSString *)theKey fromDictionary: (NSDictionary *)theDictionary isWindowDark: (BOOL)mode
{
    NSColor *theColor;
    
    NSArray *theColorArray = [self colorArrayFromDictionary: theDictionary andKey: theKey];
    if (theColorArray != nil)
        {
            theColor = [NSColor colorWithRed: [theColorArray[0] doubleValue]  green: [theColorArray[1] doubleValue]  blue: [theColorArray[2] doubleValue]  alpha: (theColorArray.count >= 4 ? [theColorArray[3] doubleValue] : 1.0)];
            return (theColor);
        }
    // The color drawn for it: the built-in one, readable with the other color of its pair.
    return [self opaqueColorForKey: theKey fromDictionary: theDictionary isWindowDark: mode];
}

// Themes store an opacity of 0 with some of these colors, for example the editor
// background of SolarizedDark, which -colorFromDictionary:andKey: ignores.
//
// A color the theme does not have is the built-in one of the mode, but text and the background
// it is drawn on are a pair: when the theme has only one of them (a theme of either kind can be
// used in a light or a dark window, and its file may have lost a color), the missing one is
// chosen so that the text reads on the background, contrast 4.5 or more: the built-in color of
// the mode, else that of the other mode, else white or black. The theme file is not changed.
// Text on: EditorText and EditorInsertionPoint on EditorBackground, ConsoleText on
// ConsoleBackground, LogText on LogBackground; EditorText on EntryColor (the active line).
- (NSColor *)opaqueColorForKey: (NSString *)theKey fromDictionary: (NSDictionary *)theDictionary isWindowDark: (BOOL)mode
{
    NSColor *theColor = [self colorFromDictionary: theDictionary andKey: theKey];
    if (theColor != nil)
        return theColor;
    NSColor *builtIn = mode ? [self darkColorWithKey: theKey] : [self liteColorWithKey: theKey];
    NSString *background = @{@"EditorText": @"EditorBackground", @"EditorInsertionPoint": @"EditorBackground",
                              @"ConsoleText": @"ConsoleBackground", @"LogText": @"LogBackground"}[theKey];
    NSString *text = @{@"EditorBackground": @"EditorText", @"EntryColor": @"EditorText",
                       @"ConsoleBackground": @"ConsoleText", @"LogBackground": @"LogText"}[theKey];
    // The other color of the pair: the background as it is drawn, or the theme's own text.
    NSColor *other = background ? [self opaqueColorForKey: background fromDictionary: theDictionary isWindowDark: mode]
        : text ? [self colorFromDictionary: theDictionary andKey: text] : nil;
    if (other == nil)
        return builtIn;
    // WCAG contrast of two colors.
    CGFloat (^luminance)(NSColor *) = ^CGFloat(NSColor *color) {
        NSColor *rgb = [color colorUsingColorSpace: NSColorSpace.sRGBColorSpace];
        CGFloat c[3] = {rgb.redComponent, rgb.greenComponent, rgb.blueComponent};
        for (int i = 0; i < 3; i++)
            c[i] = c[i] <= 0.03928 ? c[i] / 12.92 : pow((c[i] + 0.055) / 1.055, 2.4);
        return 0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2];
    };
    CGFloat otherLuminance = luminance(other);
    NSColor *best = nil;
    CGFloat bestContrast = 0;
    for (NSColor *candidate in @[builtIn, mode ? [self liteColorWithKey: theKey] : [self darkColorWithKey: theKey],
                                 [NSColor colorWithRed: 1 green: 1 blue: 1 alpha: 1], [NSColor colorWithRed: 0 green: 0 blue: 0 alpha: 1]]) {
        CGFloat l = luminance(candidate);
        CGFloat contrast = (MAX(l, otherLuminance) + 0.05) / (MIN(l, otherLuminance) + 0.05);
        if (contrast >= 4.5)
            return candidate;
        if (contrast > bestContrast) {
            best = candidate;
            bestContrast = contrast;
        }
    }
    return best;
}

- (NSColor *)colorForKey: (NSString *)theKey isWindowDark: (BOOL)mode
{
    NSDictionary *theDictionary;
    
    if (mode)
        theDictionary = darkColors;
     else
         theDictionary = liteColors;
    
    return [self colorForKey: theKey fromDictionary: theDictionary isWindowDark: mode];
}



- (void)changeColorValueInDictionary: (NSMutableDictionary *)theDictionary forKey: (NSString *)theKey fromColorWell: (id)theWell
{
    CGFloat aRed, aGreen, aBlue, anAlpha;
    NSNumber *redNumber, *greenNumber, *blueNumber, *alphaNumber;
    
    NSColor *theColor = [((NSColorWell *)theWell).color colorUsingColorSpace:NSColorSpace.genericRGBColorSpace];
    if (theColor == nil) return;
    [theColor getRed: &aRed green: &aGreen blue: &aBlue alpha: &anAlpha];
    redNumber = [NSNumber numberWithDouble: aRed];
    greenNumber = [NSNumber numberWithDouble: aGreen];
    blueNumber = [NSNumber numberWithDouble: aBlue];
    alphaNumber = [NSNumber numberWithDouble: anAlpha];
    NSArray *theArray = @[redNumber, greenNumber, blueNumber, alphaNumber];
    [theDictionary setObject: theArray forKey:theKey];
}

@end
