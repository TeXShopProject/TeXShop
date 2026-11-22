#pragma once
// What the Matrix and LaTeX panels need from the application when a check loads them with their
// controllers: the factory defaults (LPanelOutlines; TS_FACTORY_DEFAULTS), atLeastMojave as
// TSAppDelegate sets it, and the pictures the panels name, which come from the application's asset catalog
// and are read here from Resources/Images.xcassets (TS_IMAGE_ASSETS). panel_environment in panel_sources.py
// sets both variables and an isolated home with ~/Library/TeXShop/LatexPanel and MatrixPanel.
#import <Cocoa/Cocoa.h>
#import <objc/runtime.h>
extern BOOL atLeastMojave;
static IMP TSOriginalImageNamed;
static NSImage *TSImageNamedFromAssets(id cls, SEL sel, NSString *name) {
    NSImage *image = ((NSImage *(*)(id, SEL, NSString *))TSOriginalImageNamed)(cls, sel, name);
    const char *assets = getenv("TS_IMAGE_ASSETS");
    if (image || !assets || !name.length) return image;
    NSString *set = [[@(assets) stringByAppendingPathComponent:name] stringByAppendingPathExtension:@"imageset"];
    NSDictionary *contents = [NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfFile:[set stringByAppendingPathComponent:@"Contents.json"]] ?: [NSData data] options:0 error:nil];
    for (NSDictionary *entry in contents[@"images"]) {
        if (!entry[@"filename"]) continue;
        NSImage *file = [[NSImage alloc] initWithContentsOfFile:[set stringByAppendingPathComponent:entry[@"filename"]]];
        NSImageRep *rep = file.representations.firstObject;
        if (!rep) continue;
        CGFloat scale = [entry[@"scale"] isEqual:@"2x"] ? 2 : [entry[@"scale"] isEqual:@"3x"] ? 3 : 1;
        file.size = NSMakeSize(rep.pixelsWide / scale, rep.pixelsHigh / scale);
        [file setName:name];
        return file;
    }
    return nil;
}
static void TSInstallPanelEnvironment(void) {
    atLeastMojave = YES;
    const char *factory = getenv("TS_FACTORY_DEFAULTS");
    if (factory) [NSUserDefaults.standardUserDefaults registerDefaults:[NSDictionary dictionaryWithContentsOfFile:@(factory)] ?: @{}];
    if (!TSOriginalImageNamed)
        TSOriginalImageNamed = method_setImplementation(class_getClassMethod(NSImage.class, @selector(imageNamed:)), (IMP)TSImageNamedFromAssets);
}
