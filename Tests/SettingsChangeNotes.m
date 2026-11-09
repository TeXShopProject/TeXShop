// SPDX-License-Identifier: GPL-2.0-or-later
#import "TestAppKitIsolation.h"
#import "TSSettingsChangeNote.h"
#import "TSPrefPaneLayout.h"
#import "TSSettingsSearch.h"
static NSUInteger announcements;
static NSDictionary *lastAnnouncement;
void TSProbeAnnouncement(id element, NSAccessibilityNotificationName notification, NSDictionary *userInfo) {
    if ([notification isEqual:NSAccessibilityAnnouncementRequestedNotification]) { announcements++; lastAnnouncement=userInfo; }
}
static void Check(BOOL value, NSString *message) { if (!value) { fprintf(stderr,"FAIL: %s\n",message.UTF8String); exit(1); } }
static NSView *Find(NSView *view, NSString *identifier) {
    if ([view.identifier isEqual:identifier]) return view;
    for (NSView *child in view.subviews) { NSView *found=Find(child,identifier); if(found)return found; } return nil;
}
static TSSettingsChangeNote *Note(NSDictionary *panes, NSString *category, NSString *row) { return (id)Find(Find([panes[category] view],row),@"settings.change-note"); }
static void Set(TSSettingsChangeNotes *notes, TSMemoryDefaults *defaults, NSString *key, id value) {
    id previous=[notes currentValueForKey:key]; [defaults setObject:value forKey:key]; [notes recordUserChangeForKey:key previousValue:previous];
}
int main(int argc, char **argv) { @autoreleasepool {
    TSInstallAppKitIsolation(); [NSApplication sharedApplication];
    TSMemoryDefaults *defaults=[TSMemoryDefaults new];
    NSDictionary *initial=@{@"TeXAwareSpellChecking":@YES,@"PdfMagnification":@1,@"Encoding":@"UTF-8",@"AutoSaveEnabled":@NO,@"FindMethod":@1};
    [defaults registerDefaults:initial];
    TSSettingsRememberLaunchValue(@"AutoSaveEnabled",@NO); TSSettingsRememberLaunchValue(@"AutoSaveEnabled",@YES);
    TSSettingsRememberLaunchValue(@"FindMethod",@1); TSSettingsRememberLaunchValue(@"FindMethod",@2);
    Check([TSSettingsLaunchValues()[@"AutoSaveEnabled"] isEqual:@NO] && [TSSettingsLaunchValues()[@"FindMethod"] isEqual:@1], @"Launch baseline is captured only once");
    NSBundle *strings=argc>1?[NSBundle bundleWithPath:[NSString stringWithUTF8String:argv[1]]]:NSBundle.mainBundle;
    Check(strings!=nil,@"Localized strings bundle exists");
    TSSettingsChangeNotes *notes=[[TSSettingsChangeNotes alloc] initWithDefaults:defaults launchValues:TSSettingsLaunchValues() bundle:strings];
    __block BOOL pdf=NO, source=NO; notes.hasPDFWindow=^BOOL{return pdf;}; notes.hasSourceWindow=^BOOL{return source;};
    NSDictionary *rows=@{@"spelling":@[@"row.catalog.spelling.1.0"],@"preview":@[@"row.catalog.preview.0.2"],@"documents":@[@"row.catalog.documents.0.0",@"row.catalog.documents.1.0"],@"editor":@[@"row.catalog.editor.7.0"]};
    NSMutableDictionary *panes=[NSMutableDictionary dictionary];
    for(NSString *category in rows){
        NSViewController *pane=[NSViewController new]; NSStackView *stack=[NSStackView new]; stack.orientation=NSUserInterfaceLayoutOrientationVertical;stack.alignment=NSLayoutAttributeLeading;stack.spacing=12;
        pane.view=stack; panes[category]=pane;
        for(NSString *identifier in rows[category]){
            NSStackView *row=[NSStackView new];row.identifier=identifier;row.orientation=NSUserInterfaceLayoutOrientationHorizontal;row.spacing=12;
            NSStackView *label=[NSStackView new];label.identifier=@"label.catalog-stack";label.orientation=NSUserInterfaceLayoutOrientationVertical;label.alignment=NSLayoutAttributeLeading;label.spacing=2;
            NSTextField *name=[NSTextField labelWithString:[category isEqual:@"preview"]?@"New PDF zoom":@"LaTeX-aware spelling"];
            [label addArrangedSubview:name];[name.widthAnchor constraintEqualToAnchor:label.widthAnchor].active=YES;
            [row addArrangedSubview:label];[row addArrangedSubview:[NSSwitch new]];
            [row.widthAnchor constraintEqualToConstant:500].active=YES;[row.heightAnchor constraintGreaterThanOrEqualToConstant:38].active=YES;[stack addArrangedSubview:row];
        }
    }
    [notes attachToPanes:panes];[notes beginSession];
    TSSettingsChangeNote *spell=Note(panes,@"spelling",@"row.catalog.spelling.1.0"), *zoom=Note(panes,@"preview",@"row.catalog.preview.0.2"), *encoding=Note(panes,@"documents",@"row.catalog.documents.0.0"),*autosave=Note(panes,@"documents",@"row.catalog.documents.1.0"),*find=Note(panes,@"editor",@"row.catalog.editor.7.0");
    NSArray<TSSettingsChangeNote *> *all=@[spell,zoom,encoding,autosave,find];
    for(TSSettingsChangeNote *note in all) Check(note.hidden,@"Opening settings creates no warning");
    Set(notes,defaults,@"TeXAwareSpellChecking",@NO);Check(!spell.hidden,@"Spell toggle shows note");
    Check(announcements==1 && [lastAnnouncement[NSAccessibilityAnnouncementKey] isEqual:spell.accessibilityLabel] && [lastAnnouncement[NSAccessibilityPriorityKey] integerValue]==NSAccessibilityPriorityMedium,@"Showing a note requests a medium-priority VoiceOver announcement");
    Set(notes,defaults,@"TeXAwareSpellChecking",@YES);Check(spell.hidden,@"Returning to session value clears spell note");
    Set(notes,defaults,@"PdfMagnification",@1.25);Check(zoom.hidden,@"No preview means no zoom note");
    pdf=YES;Set(notes,defaults,@"PdfMagnification",@1.25);Check(zoom.hidden,@"Committing the same zoom does not show a note");
    Set(notes,defaults,@"PdfMagnification",@1.5);Check(!zoom.hidden,@"Open preview and changed zoom show note");
    Set(notes,defaults,@"PdfMagnification",@1);Check(zoom.hidden,@"Restoring zoom clears note");
    Set(notes,defaults,@"Encoding",@"ISO Latin 1");Check(encoding.hidden,@"No source window means no encoding note");
    source=YES;Set(notes,defaults,@"Encoding",@"MacOSRoman");Check(!encoding.hidden,@"Open source and changed encoding show note");
    Set(notes,defaults,@"Encoding",@"UTF-8");Check(encoding.hidden,@"Restoring encoding clears note");
    Set(notes,defaults,@"TeXAwareSpellChecking",@NO);[notes leaveCategory];Check(spell.hidden,@"Category transition clears transient note");
    Set(notes,defaults,@"TeXAwareSpellChecking",@YES);Set(notes,defaults,@"TeXAwareSpellChecking",@NO);[notes endSession];
    for(TSSettingsChangeNote *note in all)Check(note.hidden,@"Closing hides all notes");
    [notes beginSession];Check(spell.hidden,@"Reopening captures a new transient baseline");
    Set(notes,defaults,@"TeXAwareSpellChecking",@YES);Check(!spell.hidden,@"New session has its own opening value");
    [notes valuesReplaced];Check(spell.hidden,@"Profile/reset clears transient notes");
    [defaults setDouble:2 forKey:@"PdfMagnification"];[defaults setObject:@"MacOSRoman" forKey:@"Encoding"];[notes valuesReplaced];
    Check(zoom.hidden && encoding.hidden,@"Profile/reset does not create transient notes");
    Set(notes,defaults,@"FindMethod",@0);Check(find.hidden,@"Panel and bar changes take effect without restart");
    Set(notes,defaults,@"FindMethod",@1);Check(find.hidden,@"Returning from panel to bar needs no restart");
    Set(notes,defaults,@"AutoSaveEnabled",@YES);Set(notes,defaults,@"FindMethod",@2);
    Check(!autosave.hidden&&!find.hidden,@"Changed startup settings show restart notes");
    [notes leaveCategory];Check(!autosave.hidden&&!find.hidden,@"Restart notes survive category transitions");
    [notes endSession];[notes beginSession];Check(!autosave.hidden&&!find.hidden,@"Restart notes survive reopening");
    Set(notes,defaults,@"AutoSaveEnabled",@NO);Set(notes,defaults,@"FindMethod",@1);Check(autosave.hidden&&find.hidden,@"Restoring launch values clears restart notes");
    [defaults setBool:YES forKey:@"AutoSaveEnabled"];[defaults setInteger:2 forKey:@"FindMethod"];[notes valuesReplaced];Check(!autosave.hidden&&!find.hidden,@"Profile differences also need restart notes");
    TSSettingsChangeNotes *ogre=[[TSSettingsChangeNotes alloc]initWithDefaults:defaults launchValues:@{@"FindMethod":@2,@"AutoSaveEnabled":@NO} bundle:strings];
    [defaults setInteger:2 forKey:@"FindMethod"];[ogre beginSession];
    TSSettingsChangeNote *ogreNote=[[[[ogre valueForKey:@"categories"]objectForKey:@"editor"]firstObject]valueForKey:@"view"];
    Check(ogreNote.hidden,@"OgreKit startup value itself needs no warning");
    Set(ogre,defaults,@"FindMethod",@0);Check(!ogreNote.hidden,@"Leaving OgreKit for the standard panel needs restart");
    Set(ogre,defaults,@"FindMethod",@1);Check(!ogreNote.hidden,@"Leaving OgreKit for the find bar needs restart");
    Set(ogre,defaults,@"FindMethod",@2);Check(ogreNote.hidden,@"Returning to startup OgreKit clears its warning");
    // A real resource index must not include transient note keys.
    if(argc>1){ NSBundle *bundle=[NSBundle bundleWithPath:[NSString stringWithUTF8String:argv[1]]];TSSettingsSearch *index=[[TSSettingsSearch alloc]initWithBundle:bundle categoryOrder:rows.allKeys commandNames:@[]];
        Check([index resultsForQuery:[bundle localizedStringForKey:@"catalog.spelling.1.0.title" value:nil table:@"SettingsCategories"]].count>0,@"Real localized search resources are loaded");
        for(TSSettingsChangeNote *note in all)Check([index resultsForQuery:note.accessibilityLabel].count==0,@"Warnings are excluded from search"); }
    for(TSSettingsChangeNote *note in all){NSTextField *label=(id)note.arrangedSubviews.lastObject;NSImageView *icon=(id)note.arrangedSubviews.firstObject;
        Check(icon.image!=nil,@"Warning symbol exists on the runtime OS");
        Check([label.textColor isEqual:NSColor.labelColor]&&icon.contentTintColor==nil && [icon.identifier isEqual:@"settings.warning-symbol.multicolor"],@"Warning uses label text and an untinted multicolor symbol");
        Check(label.font.pointSize==NSFont.smallSystemFontSize && note.arrangedSubviews.count==2,@"Small label and warning symbol, without extra frame"); }
    puts("PASS: transient and restart note conditions, value restoration, lifecycle, profile, search exclusion and appearance");
}return 0;}
