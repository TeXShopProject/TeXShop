#!/usr/bin/env python3
"""Exercise the production Cancel ordering, before unrelated theme/UI restoration."""
from pathlib import Path
import os,sys
root=Path(__file__).resolve().parents[1]
s=(root/'Sources/TSPreferences.m').read_text()
a=s.index('- (IBAction)cancelButtonPressed:sender');a=s.index('{',a)+1
b=s.index('[[[NSApp mainMenu]',a)
prefix=s[a:b]
if os.environ.get('DOCK_MUTATE_CANCEL'):
    line='[[TSDockIconController sharedController] cancelEditing];'
    prefix=prefix.replace(line,'');prefix=line+'\n'+prefix
out='''
@interface DockPreferencesProbe : NSObject {
    NSUndoManager *_undoManager;
}
- (void)setDockStyle:(NSString *)style;
- (void)beginReset;
- (void)cancelButtonPressed:(id)sender;
@end
@implementation DockPreferencesProbe
- (instancetype)init { if((self=[super init])) { _undoManager=[NSUndoManager new]; _undoManager.groupsByEvent=NO; } return self; }
- (void)cancelForColor {}
- (void)cancelEnginePathDiscovery {}
- (void)setDockStyle:(NSString *)style {
    NSString *previous=[NSUserDefaults.standardUserDefaults stringForKey:TSDockIconKey];
    [[_undoManager prepareWithInvocationTarget:self] setDockStyle:previous];
    if(style) [NSUserDefaults.standardUserDefaults setObject:style forKey:TSDockIconKey];
    else [NSUserDefaults.standardUserDefaults removeObjectForKey:TSDockIconKey];
}
- (void)beginReset { [_undoManager beginUndoGrouping]; [self setDockStyle:nil]; }
- (void)cancelButtonPressed:(id)sender {
'''+prefix+'''
}
@end
static void CheckPreferenceCancel(void) {
    TSDockIconController *shared=[TSDockIconController sharedController];
    [NSUserDefaults.standardUserDefaults setObject:@"round" forKey:TSDockIconKey];
    [shared beginEditing];
    DockPreferencesProbe *preferences=[DockPreferencesProbe new];
    [preferences beginReset];
    [preferences cancelButtonPressed:nil];
    Require([[shared valueForKey:@"selection"] isEqual:@"round"] && NSApp.dockTile.contentView != nil,
            @"Production Cancel restores defaults before restoring Dock preview");
}
'''
Path(sys.argv[1]).write_text(out)
