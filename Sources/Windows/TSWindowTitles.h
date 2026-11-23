//
//  TSWindowTitles.h
//  TeXShop
//
//  The titles of the Preview window and the console follow Show Full Path, as the title
//  of the source window does: the full path while it is on, the file name while it is off.
//

#import <Foundation/Foundation.h>

// The Preview window shows the PDF at path.
static inline NSString *TSPreviewWindowTitle(NSString *path, BOOL showFullPath)
{
    return showFullPath ? path : path.lastPathComponent;
}

// The console shows the typesetting of the file at path (any extension is left out).
static inline NSString *TSConsoleWindowTitle(NSString *path, BOOL showFullPath)
{
    NSString *name = showFullPath ? path : path.lastPathComponent;
    return [name.stringByDeletingPathExtension stringByAppendingString: @" console"];
}
