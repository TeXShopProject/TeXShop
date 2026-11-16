// SPDX-License-Identifier: GPL-2.0-or-later
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// The byte order mark a source starts with.
typedef NS_ENUM(NSInteger, TSTeXRootByteOrderMark) {
    TSTeXRootByteOrderMarkNone = 0,
    TSTeXRootByteOrderMarkUTF8,
    TSTeXRootByteOrderMarkUTF16BigEndian,
    TSTeXRootByteOrderMarkUTF16LittleEndian,
} NS_SWIFT_NAME(TeXRootByteOrderMark);

/// Why a file is listed but cannot be replaced in ("search only").
typedef NS_ENUM(NSInteger, TSTeXRootSearchOnlyReason) {
    TSTeXRootSearchOnlyReasonNone = 0,
    /// The bytes do not read strictly in the file's encoding; the text shown was read leniently.
    TSTeXRootSearchOnlyReasonUndecodable,
    /// The text, written back in the file's encoding, would not give the very same bytes.
    TSTeXRootSearchOnlyReasonRoundTrip,
    /// The file has more than one name (a hard link); writing it would split the names.
    TSTeXRootSearchOnlyReasonHardLink,
    /// The file cannot be written: read only, locked, or no permission.
    TSTeXRootSearchOnlyReasonNotWritable,
} NS_SWIFT_NAME(TeXRootSearchOnlyReason);

/// Why an item under the folder could not be looked at.
typedef NS_ENUM(NSInteger, TSTeXRootUnreadableReason) {
    /// A folder that could not be entered.
    TSTeXRootUnreadableReasonFolder = 1,
    /// A file that could not be read (or downloaded).
    TSTeXRootUnreadableReasonFile,
} NS_SWIFT_NAME(TeXRootUnreadableReason);

/// The result of reading one source as TeXShop opens it.
NS_SWIFT_NAME(TeXRootSourceReading)
@interface TSTeXRootSourceReading : NSObject
@property (nonatomic, readonly) NSStringEncoding encoding;
@property (nonatomic, readonly) TSTeXRootByteOrderMark byteOrderMark;
/// The text as the editor shows it; read leniently (as Latin 9, as opening does) when `decodedStrictly` is NO.
@property (nonatomic, readonly, copy) NSString *text;
@property (nonatomic, readonly) BOOL decodedStrictly;
/// The text, written back, gives exactly the bytes it was read from.
@property (nonatomic, readonly) BOOL roundTrips;
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;
@end

/// How sources are read and written: TeXShop's choice of encoding and its editing and saving conversions
/// (backslash and yen sign, tilde and overline) are given from outside, so that this class needs Foundation only.
NS_SWIFT_NAME(TeXRootSourceCodec)
@interface TSTeXRootSourceCodec : NSObject
- (instancetype)initWithEncodingForData:(NSStringEncoding (^)(NSData *data, NSURL *url))encodingForData
                         textForEditing:(NSString * (^)(NSString *text, NSStringEncoding encoding))textForEditing
                          textForSaving:(NSString * (^)(NSString *text, NSStringEncoding encoding))textForSaving NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;

+ (TSTeXRootByteOrderMark)byteOrderMarkOfData:(NSData *)data;
/// Reads `data`, the contents of `url`: the encoding opening would choose, strict decoding (lenient as Latin 9 when
/// that fails, as opening does), the editing conversion, and the round-trip check.
- (TSTeXRootSourceReading *)readData:(NSData *)data url:(NSURL *)url;
/// The same; without `verifies`, the round trip is not made and `roundTrips` is NO (to decide whether a file belongs).
- (TSTeXRootSourceReading *)readData:(NSData *)data url:(NSURL *)url verifyingRoundTrip:(BOOL)verifies;
/// The bytes for `text` as TeXShop saves it, with no lossy conversion: the saving conversion, then the byte order mark
/// again for UTF-8 and UTF-16. Nil when a character cannot be written in the encoding.
- (nullable NSData *)dataForText:(NSString *)text encoding:(NSStringEncoding)encoding
                   byteOrderMark:(TSTeXRootByteOrderMark)byteOrderMark;
@end

/// One file of a project: the root, or a .tex file under the root's folder whose root is the same file.
NS_SWIFT_NAME(TeXRootProjectFile)
@interface TSTeXRootProjectFile : NSObject
@property (nonatomic, readonly, copy) NSURL *url;
/// The path below the root's folder, as shown in the tree ("chapters/chapter1.tex").
@property (nonatomic, readonly, copy) NSString *relativePath;
@property (nonatomic, readonly) BOOL isRoot;
/// The file's identity for this session (NSURLFileResourceIdentifierKey); never stored.
@property (nonatomic, readonly) id<NSObject, NSCopying> identifier;
/// The text was given by an open document, not read from the disk.
@property (nonatomic, readonly) BOOL isOpen;
@property (nonatomic, readonly, copy) NSString *text;
/// For a file read from the disk: how it was read and the bytes it was read from.
@property (nonatomic, readonly, nullable) TSTeXRootSourceReading *reading;
@property (nonatomic, readonly, copy, nullable) NSData *sha256;
@property (nonatomic, readonly) unsigned long long size;
@property (nonatomic, readonly, copy, nullable) NSDate *modificationDate;
@property (nonatomic, readonly) TSTeXRootSearchOnlyReason searchOnlyReason;
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;
@end

NS_SWIFT_NAME(TeXRootUnreadableItem)
@interface TSTeXRootUnreadableItem : NSObject
@property (nonatomic, readonly, copy) NSURL *url;
@property (nonatomic, readonly, copy) NSString *relativePath;
@property (nonatomic, readonly) TSTeXRootUnreadableReason reason;
@property (nonatomic, readonly, nullable) NSError *error;
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;
@end

NS_SWIFT_NAME(TeXRootProject)
@interface TSTeXRootProject : NSObject
@property (nonatomic, readonly, copy) NSURL *rootURL;
@property (nonatomic, readonly, copy) NSURL *folderURL;
/// The root; nil when it could not be read (it is then among `unreadableItems`, and the files that name it are still
/// collected, so that they can be searched).
@property (nonatomic, readonly, nullable) TSTeXRootProjectFile *rootFile;
/// The root first (when it could be read), then the other files in the order of their relative paths (as the Finder
/// sorts names).
@property (nonatomic, readonly, copy) NSArray<TSTeXRootProjectFile *> *files;
@property (nonatomic, readonly, copy) NSArray<TSTeXRootUnreadableItem *> *unreadableItems;
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;
@end

/// What is wrong with the root a document names (the entry point refuses to open the window then).
typedef NS_ENUM(NSInteger, TSTeXRootProblem) {
    TSTeXRootProblemNone = 0,
    TSTeXRootProblemMissing,
    TSTeXRootProblemNotRegularFile,
    TSTeXRootProblemNotTeXFile,
} NS_SWIFT_NAME(TeXRootProblem);

/// Why -collect gave nothing.
typedef NS_ENUM(NSInteger, TSTeXRootCollectionFailure) {
    TSTeXRootCollectionFailureNone = 0,
    TSTeXRootCollectionFailureCancelled,
    /// The root does not exist, is not a regular file or is not a .tex file (see `rootProblem`).
    TSTeXRootCollectionFailureRootProblem,
    /// The file system gave no identity for the root, so no file could be compared with it.
    TSTeXRootCollectionFailureRootIdentity,
} NS_SWIFT_NAME(TeXRootCollectionFailure);

/// Collects the files of a project: the root R and every .tex file in R's folder and below whose root, found as
/// TeXShop finds it (TSRootFileResolver), is the same file as R. Foundation only; meant to run off the main thread.
NS_SWIFT_NAME(TeXRootProjectCollector)
@interface TSTeXRootProjectCollector : NSObject

/// The root must exist, be a regular file and have the lowercase extension "tex".
+ (TSTeXRootProblem)problemWithRootURL:(NSURL *)rootURL;
/// A .tex file in the sense of this feature: a regular file, not a symbolic link, whose extension is exactly "tex".
+ (BOOL)isCandidateName:(NSString *)name;
/// SHA-256 of all of `data`, however long.
+ (NSData *)sha256OfData:(NSData *)data;
/// The same, given to CommonCrypto in pieces of at most `pieceLength` bytes (the real pieces are 1 GiB; a test uses
/// small ones to check that the pieces add up to the whole).
+ (NSData *)sha256OfData:(NSData *)data pieceLength:(NSUInteger)pieceLength;

- (instancetype)initWithRootURL:(NSURL *)rootURL codec:(TSTeXRootSourceCodec *)codec
              allowsSourceDoc:(BOOL)allowsSourceDoc jobNameToken:(NSString *)jobNameToken NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;

/// The texts of the open documents, by file identifier, taken on the main thread before collecting.
@property (nonatomic, copy) NSDictionary<id<NSCopying>, NSString *> *openDocumentTexts;
/// Called on the collecting thread after each piece of a file is read while deciding whether it belongs (for tests,
/// which cancel there to check that reading stops).
@property (nonatomic, copy, nullable) void (^pieceReadHandler)(void);
/// Called now and then from the collecting thread: folders and files looked at, and the folder being read.
@property (nonatomic, copy, nullable) void (^progressHandler)(NSUInteger folders, NSUInteger files, NSString *currentFolder);

/// Walks the folder. Nil when cancelled (the partial result is dropped) or when the root cannot be used; `failure`
/// tells which. Items that cannot be read are listed in the result, the root included.
- (nullable TSTeXRootProject *)collect;
@property (nonatomic, readonly) TSTeXRootCollectionFailure failure;
@property (nonatomic, readonly) TSTeXRootProblem rootProblem;
/// Safe from any thread; also stops waiting for a file being downloaded.
- (void)cancel;
@property (atomic, readonly, getter=isCancelled) BOOL cancelled;

@end

NS_ASSUME_NONNULL_END
