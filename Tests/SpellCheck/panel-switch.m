// Probe delayed panel updates after switching to another document.
#import <Cocoa/Cocoa.h>
#import "TSSpellExclusions.h"
#import "TSSpellSupport.h"
static NSTextField *Field(NSView *v) {
 if([v isKindOfClass:NSTextField.class] && [(NSTextField *)v isEditable]) return (NSTextField *)v;
 for(NSView *s in v.subviews) {NSTextField *f=Field(s);if(f)return f;}return nil;
}
int main(void) {@autoreleasepool {
 [NSApplication sharedApplication];
 NSTextView *a=[[NSTextView alloc] initWithFrame:NSMakeRect(0,0,300,200)],*b=[[NSTextView alloc] initWithFrame:NSMakeRect(0,0,300,200)];
 a.string=@"zzqqa word";b.string=@"zzqqb word";
 TSSpellExclusions *e=[TSSpellExclusions sharedExclusions];
 [TSSpellSupport showSpellingPanelForTextView:a mask:[e maskForText:a.string] hidePanel:^{}];
 [TSSpellSupport findNextMisspellingInTextView:b mask:[e maskForText:b.string]];
 NSTextField *field=Field(NSSpellChecker.sharedSpellChecker.spellingPanel.contentView);
 printf("B selected=%s panel before wait=%s\n",[b.string substringWithRange:b.selectedRange].UTF8String,field.stringValue.UTF8String);
 NSDate *until=[NSDate dateWithTimeIntervalSinceNow:.8];while(until.timeIntervalSinceNow>0)[[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.01]];
 printf("B selected=%s panel after wait=%s\n",[b.string substringWithRange:b.selectedRange].UTF8String,field.stringValue.UTF8String);
}return 0;}
