#import <AppKit/AppKit.h>
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSErrorDomain const CKChromiumKitBridgeErrorDomain;

typedef NS_ENUM(NSInteger, CKNavigationDecision) {
    CKNavigationDecisionAllow = 0,
    CKNavigationDecisionCancel = 1,
    CKNavigationDecisionOpenExternally = 2,
};

typedef NS_ENUM(NSInteger, CKPermissionDecision) {
    CKPermissionDecisionDefault = 0,
    CKPermissionDecisionAllow = 1,
    CKPermissionDecisionDeny = 2,
};

typedef NS_OPTIONS(NSUInteger, CKPermissionKinds) {
    CKPermissionKindAudioCapture = 1 << 0,
    CKPermissionKindVideoCapture = 1 << 1,
    CKPermissionKindNotifications = 1 << 2,
    CKPermissionKindClipboard = 1 << 3,
};

@protocol CKNavigationDeciding;
@protocol CKPermissionDeciding;
@protocol CKURLSchemeHandling;
@protocol CKWebViewHostControllerDelegate;

@interface CKRuntimeConfiguration : NSObject
@property (nonatomic, copy, nullable) NSURL *cacheDirectoryURL;
@property (nonatomic, copy, nullable) NSURL *logDirectoryURL;
@property (nonatomic, copy, nullable) NSURL *helperExecutableURL;
@property (nonatomic, copy) NSArray<NSString *> *additionalArguments;
@property (nonatomic, copy) NSArray<NSString *> *knownCustomSchemes;
@end

@interface CKRuntime : NSObject
+ (BOOL)ensureInitializedWithConfiguration:(CKRuntimeConfiguration *)configuration error:(NSError * _Nullable * _Nullable)error NS_SWIFT_NAME(ensureInitialized(with:));
+ (void)shutdown;
@end

@interface CKNavigationAction : NSObject
@property (nonatomic, copy, readonly, nullable) NSURL *url;
@property (nonatomic, readonly, getter=isUserGesture) BOOL userGesture;
@property (nonatomic, readonly, getter=isRedirect) BOOL redirect;
@property (nonatomic, readonly, getter=opensNewWindow) BOOL opensNewWindow;
@end

@protocol CKNavigationDeciding <NSObject>
- (CKNavigationDecision)decidePolicyForAction:(CKNavigationAction *)action NS_SWIFT_NAME(decidePolicy(for:));
@end

@interface CKPermissionRequest : NSObject
@property (nonatomic, copy, readonly, nullable) NSString *origin;
@property (nonatomic, readonly) CKPermissionKinds kinds;
@end

@protocol CKPermissionDeciding <NSObject>
- (CKPermissionDecision)decidePermissionForRequest:(CKPermissionRequest *)request NS_SWIFT_NAME(decidePermission(for:));
@end

@interface CKURLSchemeResponse : NSObject
@property (nonatomic, copy, readonly) NSData *body;
@property (nonatomic, copy, readonly) NSString *mimeType;
@property (nonatomic, readonly) NSInteger statusCode;
@property (nonatomic, copy, readonly) NSDictionary<NSString *, NSString *> *headers;
- (instancetype)initWithBody:(NSData *)body
                    mimeType:(NSString *)mimeType
                  statusCode:(NSInteger)statusCode
                     headers:(NSDictionary<NSString *, NSString *> *)headers NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;
@end

@protocol CKURLSchemeHandling <NSObject>
- (nullable CKURLSchemeResponse *)responseForRequest:(NSURLRequest *)request error:(NSError * _Nullable * _Nullable)error NS_SWIFT_NAME(response(for:));
@end

@interface CKWebPageConfiguration : NSObject
@property (nonatomic, copy, nullable) NSURL *cacheDirectoryURL;
@property (nonatomic, weak, nullable) id<CKNavigationDeciding> navigationDecider;
@property (nonatomic, weak, nullable) id<CKPermissionDeciding> permissionDecider;
@property (nonatomic, copy) NSDictionary<NSString *, id<CKURLSchemeHandling>> *urlSchemeHandlers;
@end

@interface CKWebViewHostController : NSObject
@property (nonatomic, strong, readonly) NSView *view;
@property (nonatomic, weak, nullable) id<CKWebViewHostControllerDelegate> delegate;

- (instancetype)initWithConfiguration:(CKWebPageConfiguration *)configuration NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

- (BOOL)load:(NSURLRequest *)request error:(NSError * _Nullable * _Nullable)error;
- (BOOL)loadHTMLString:(NSString *)html baseURL:(nullable NSURL *)baseURL error:(NSError * _Nullable * _Nullable)error;
- (BOOL)loadData:(NSData *)data
        mimeType:(NSString *)mimeType
characterEncoding:(NSString *)characterEncoding
         baseURL:(nullable NSURL *)baseURL
           error:(NSError * _Nullable * _Nullable)error;
- (void)reload;
- (void)stopLoading;
- (void)goBack;
- (void)goForward;
- (void)evaluateJavaScript:(NSString *)javaScript completionHandler:(void (^)(NSString * _Nullable resultJSON, NSError * _Nullable error))completionHandler;
@end

@protocol CKWebViewHostControllerDelegate <NSObject>
- (void)webViewHostController:(CKWebViewHostController *)controller didUpdateTitle:(nullable NSString *)title;
- (void)webViewHostController:(CKWebViewHostController *)controller didUpdateURL:(nullable NSURL *)url;
- (void)webViewHostController:(CKWebViewHostController *)controller didUpdateLoadingState:(BOOL)isLoading canGoBack:(BOOL)canGoBack canGoForward:(BOOL)canGoForward;
- (void)webViewHostController:(CKWebViewHostController *)controller didUpdateEstimatedProgress:(double)progress;
- (void)webViewHostController:(CKWebViewHostController *)controller didStartNavigationWithID:(NSInteger)identifier url:(nullable NSURL *)url isRedirect:(BOOL)isRedirect;
- (void)webViewHostController:(CKWebViewHostController *)controller didCommitNavigationWithID:(NSInteger)identifier url:(nullable NSURL *)url;
- (void)webViewHostController:(CKWebViewHostController *)controller didFinishNavigationWithID:(NSInteger)identifier url:(nullable NSURL *)url httpStatusCode:(NSInteger)httpStatusCode;
- (void)webViewHostController:(CKWebViewHostController *)controller didFailNavigationWithID:(NSInteger)identifier url:(nullable NSURL *)url provisional:(BOOL)provisional code:(NSInteger)code description:(NSString *)description;
- (void)webViewHostController:(CKWebViewHostController *)controller didEncounterRuntimeError:(NSError *)error;
@end

NS_ASSUME_NONNULL_END
