// Added by Terada: exercise the bundled importer without changing Spotlight's index.
#import <Foundation/Foundation.h>
#import <CoreServices/CoreServices.h>
#import <dlfcn.h>
int main(int argc, const char **argv) {
    @autoreleasepool {
        if (argc != 2) return 2;
        void *library = dlopen(argv[1], RTLD_NOW);
        if (!library) { fprintf(stderr, "%s\n", dlerror()); return 3; }
        Boolean (*import)(void *, CFMutableDictionaryRef, CFStringRef, CFStringRef) = dlsym(library, "GetMetadataForFile");
        if (!import) return 4;
        NSString *folder = [NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
        [NSFileManager.defaultManager createDirectoryAtPath:folder withIntermediateDirectories:YES attributes:nil error:NULL];
        NSString *path = [folder stringByAppendingPathComponent:@"sample.tex"];
        NSString *text = @"% Test\n\\title{Spotlight Test}\n\\author{Alice \\and Bob}\n\\begin{document}\n日本語の本文 café\n\\end{document}\n";
        BOOL passed = YES;
        for (NSNumber *encoding in @[@(NSUTF8StringEncoding), @(NSUTF16StringEncoding), @(NSMacOSRomanStringEncoding)]) {
            NSString *content = encoding.unsignedIntegerValue == NSMacOSRomanStringEncoding ? [text stringByReplacingOccurrencesOfString:@"日本語の本文" withString:@"Body"] : text;
            [[content dataUsingEncoding:encoding.unsignedIntegerValue] writeToFile:path atomically:YES];
            NSMutableDictionary *attributes = [NSMutableDictionary dictionary];
            passed &= import(NULL, (__bridge CFMutableDictionaryRef)attributes, CFSTR("org.tug.tex"), (__bridge CFStringRef)path);
            passed &= [attributes[(__bridge NSString *)kMDItemTextContent] isEqual:content];
            passed &= [attributes[(__bridge NSString *)kMDItemTitle] isEqual:@"Spotlight Test"];
            passed &= [attributes[(__bridge NSString *)kMDItemAuthors] isEqual:@[@"Alice", @"Bob"]];
        }
        [NSFileManager.defaultManager removeItemAtPath:folder error:NULL];
        NSMutableDictionary *attributes = [NSMutableDictionary dictionary];
        passed &= !import(NULL, (__bridge CFMutableDictionaryRef)attributes, CFSTR("org.tug.tex"), (__bridge CFStringRef)path);
        puts(passed ? "PASS: UTF-8, UTF-16, MacRoman metadata and missing-file handling" : "FAIL: metadata mismatch");
        return passed ? 0 : 1;
    }
}
