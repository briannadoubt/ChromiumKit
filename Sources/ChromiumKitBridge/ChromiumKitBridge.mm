#import "ChromiumKitBridge.h"
#import "AppKitShim.h"

#import <objc/runtime.h>

#include "include/cef_app.h"
#include "include/cef_application_mac.h"
#include "include/cef_browser.h"
#include "include/cef_browser_process_handler.h"
#include "include/cef_command_line.h"
#include "include/cef_devtools_message_observer.h"
#include "include/cef_frame.h"
#include "include/cef_life_span_handler.h"
#include "include/cef_load_handler.h"
#include "include/cef_permission_handler.h"
#include "include/cef_request.h"
#include "include/cef_request_context.h"
#include "include/cef_request_handler.h"
#include "include/cef_resource_handler.h"
#include "include/cef_scheme.h"
#include "include/cef_values.h"

NSErrorDomain const CKChromiumKitBridgeErrorDomain = @"ChromiumKitBridgeErrorDomain";

namespace chromiumkit {

constexpr NSInteger kCKErrorRuntimeNotInitialized = 1;
constexpr NSInteger kCKErrorMissingHelper = 2;
constexpr NSInteger kCKErrorBrowserUnavailable = 3;
constexpr NSInteger kCKErrorJavaScriptFailure = 4;

NSString* ToNSString(const CefString& value) {
  return value.empty() ? nil : [NSString stringWithUTF8String:value.ToString().c_str()];
}

NSURL* ToNSURL(const CefString& value) {
  NSString* string = ToNSString(value);
  return string.length > 0 ? [NSURL URLWithString:string] : nil;
}

std::string ToStdString(NSString* string) {
  return string ? std::string(string.UTF8String) : std::string();
}

NSError* MakeError(NSInteger code, NSString* message) {
  return [NSError errorWithDomain:CKChromiumKitBridgeErrorDomain
                             code:code
                         userInfo:@{NSLocalizedDescriptionKey: message ?: @"Unknown ChromiumKit bridge error."}];
}

void DebugLog(NSString* message) {
#if DEBUG
  fprintf(stderr, "[ChromiumKitBridge] %s\n", message.UTF8String ?: "");
  fflush(stderr);
#endif
}

void SetCefString(cef_string_t& target, NSString* value) {
  CefString target_string(&target);
  target_string = ToStdString(value);
}

CefRefPtr<CefRequest> CreateRequest(NSURLRequest* request) {
  auto cef_request = CefRequest::Create();
  cef_request->SetURL(ToStdString(request.URL.absoluteString));
  cef_request->SetMethod(ToStdString(request.HTTPMethod ?: @"GET"));

  __block CefRequest::HeaderMap headers;
  [request.allHTTPHeaderFields enumerateKeysAndObjectsUsingBlock:^(NSString* key, NSString* value, BOOL*) {
    headers.insert(std::make_pair(ToStdString(key), ToStdString(value)));
  }];
  cef_request->SetHeaderMap(headers);

  NSData* body = request.HTTPBody;
  if (body.length > 0) {
    auto post_data = CefPostData::Create();
    auto element = CefPostDataElement::Create();
    element->SetToBytes(body.length, body.bytes);
    post_data->AddElement(element);
    cef_request->SetPostData(post_data);
  }

  return cef_request;
}

class MessagePumpScheduler {
 public:
  void Schedule(int64_t delay_ms) {
    dispatch_async(dispatch_get_main_queue(), ^{
      if (!initialized_) {
        return;
      }

      ensureTimer();
      if (delay_ms <= 0) {
        CefDoMessageLoopWork();
      }
    });
  }

  void MarkInitialized(bool initialized) {
    initialized_ = initialized;

    dispatch_async(dispatch_get_main_queue(), ^{
      if (!initialized_) {
        if (timer_) {
          dispatch_source_cancel(timer_);
          timer_ = nil;
        }
        return;
      }

      ensureTimer();
    });
  }

 private:
  void ensureTimer() {
    if (timer_ != nil) {
      return;
    }

    // CEF's external pump can otherwise go idle too aggressively in a SwiftUI-hosted
    // AppKit app, which leaves utility and renderer processes without a browser-process
    // connection. A lightweight repeating tick keeps the browser-process UI thread alive.
    timer_ = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
    dispatch_source_set_timer(
        timer_,
        dispatch_time(DISPATCH_TIME_NOW, 0),
        10 * NSEC_PER_MSEC,
        1 * NSEC_PER_MSEC);
    dispatch_source_set_event_handler(timer_, ^{
      if (initialized_) {
        CefDoMessageLoopWork();
      }
    });
    dispatch_resume(timer_);
  }

  __block dispatch_source_t timer_ = nil;
  bool initialized_ = false;
};

struct RuntimeState {
  bool initialized = false;
  CefRefPtr<CefApp> app;
  MessagePumpScheduler scheduler;
  std::vector<std::string> custom_schemes;
  std::vector<std::string> additional_arguments;
};

RuntimeState& SharedRuntimeState() {
  static RuntimeState state;
  return state;
}

std::vector<std::string> SchemesFromCSV(const std::string& joined) {
  std::vector<std::string> schemes;
  std::stringstream stream(joined);
  std::string scheme;
  while (std::getline(stream, scheme, ',')) {
    if (!scheme.empty()) {
      schemes.push_back(scheme);
    }
  }
  return schemes;
}

class RuntimeApp final : public CefApp, public CefBrowserProcessHandler {
 public:
  RuntimeApp(std::vector<std::string> custom_schemes,
             std::vector<std::string> additional_arguments)
      : custom_schemes_(std::move(custom_schemes)),
        additional_arguments_(std::move(additional_arguments)) {}

  void OnRegisterCustomSchemes(CefRawPtr<CefSchemeRegistrar> registrar) override {
    for (const auto& scheme : custom_schemes_) {
      registrar->AddCustomScheme(
          scheme,
          CEF_SCHEME_OPTION_STANDARD |
              CEF_SCHEME_OPTION_SECURE |
              CEF_SCHEME_OPTION_CORS_ENABLED |
              CEF_SCHEME_OPTION_FETCH_ENABLED);
    }
  }

  void OnBeforeCommandLineProcessing(
      const CefString& process_type,
      CefRefPtr<CefCommandLine> command_line) override {
    for (const auto& argument : additional_arguments_) {
      if (argument.rfind("--", 0) == 0) {
        command_line->AppendSwitch(argument.substr(2));
      }
    }
  }

  CefRefPtr<CefBrowserProcessHandler> GetBrowserProcessHandler() override {
    return this;
  }

  void OnBeforeChildProcessLaunch(
      CefRefPtr<CefCommandLine> command_line) override {
    DebugLog([NSString stringWithFormat:@"OnBeforeChildProcessLaunch command=%@",
              chromiumkit::ToNSString(command_line->GetCommandLineString()) ?: @"<nil>"]);
    if (!custom_schemes_.empty()) {
      std::string joined;
      for (size_t index = 0; index < custom_schemes_.size(); ++index) {
        if (index > 0) {
          joined += ",";
        }
        joined += custom_schemes_[index];
      }
      command_line->AppendSwitchWithValue("chromiumkit-custom-schemes", joined);
    }
  }

  void OnScheduleMessagePumpWork(int64_t delay_ms) override {
    SharedRuntimeState().scheduler.Schedule(delay_ms);
  }

  IMPLEMENT_REFCOUNTING(RuntimeApp);

 private:
  std::vector<std::string> custom_schemes_;
  std::vector<std::string> additional_arguments_;
};

class SchemeHandler final : public CefResourceHandler {
 public:
  explicit SchemeHandler(id<CKURLSchemeHandling> handler) : handler_(handler) {}

  bool Open(CefRefPtr<CefRequest> request,
            bool& handle_request,
            CefRefPtr<CefCallback> callback) override {
    handle_request = true;

    @autoreleasepool {
      NSURL* url = [NSURL URLWithString:ToNSString(request->GetURL())];
      NSString* method = ToNSString(request->GetMethod()) ?: @"GET";
      NSMutableURLRequest* ns_request = [NSMutableURLRequest requestWithURL:url ?: [NSURL URLWithString:@"about:blank"]];
      ns_request.HTTPMethod = method;

      CefRequest::HeaderMap header_map;
      request->GetHeaderMap(header_map);
      for (const auto& entry : header_map) {
        [ns_request setValue:ToNSString(entry.second) forHTTPHeaderField:ToNSString(entry.first)];
      }

      NSError* error = nil;
      CKURLSchemeResponse* response = [handler_ responseForRequest:ns_request error:&error];
      if (!response) {
        NSString* text = error.localizedDescription ?: @"Scheme handler returned no response.";
        data_ = [text dataUsingEncoding:NSUTF8StringEncoding];
        mime_type_ = @"text/plain";
        status_code_ = error ? 500 : 404;
        headers_ = @{};
        return true;
      }

      data_ = response.body;
      mime_type_ = response.mimeType;
      status_code_ = response.statusCode;
      headers_ = response.headers;
      return true;
    }
  }

  void GetResponseHeaders(CefRefPtr<CefResponse> response,
                          int64_t& response_length,
                          CefString& redirectUrl) override {
    response->SetStatus(static_cast<int>(status_code_));
    response->SetMimeType(ToStdString(mime_type_));
    __block CefResponse::HeaderMap header_map;
    [headers_ enumerateKeysAndObjectsUsingBlock:^(NSString* key, NSString* value, BOOL*) {
      header_map.insert(std::make_pair(ToStdString(key), ToStdString(value)));
    }];
    response->SetHeaderMap(header_map);
    response_length = data_.length;
  }

  bool Read(void* data_out,
            int bytes_to_read,
            int& bytes_read,
            CefRefPtr<CefResourceReadCallback> callback) override {
    bytes_read = 0;
    if (offset_ >= data_.length) {
      return false;
    }

    const NSUInteger remaining = data_.length - offset_;
    const NSUInteger amount = MIN(static_cast<NSUInteger>(bytes_to_read), remaining);
    memcpy(data_out, static_cast<const uint8_t*>(data_.bytes) + offset_, amount);
    offset_ += amount;
    bytes_read = static_cast<int>(amount);
    return true;
  }

  void Cancel() override {}

  IMPLEMENT_REFCOUNTING(SchemeHandler);

 private:
  __strong id<CKURLSchemeHandling> handler_;
  NSData* data_ = [NSData data];
  NSDictionary<NSString*, NSString*>* headers_ = @{};
  NSString* mime_type_ = @"text/plain";
  NSInteger status_code_ = 200;
  NSUInteger offset_ = 0;
};

class SchemeHandlerFactory final : public CefSchemeHandlerFactory {
 public:
  explicit SchemeHandlerFactory(id<CKURLSchemeHandling> handler) : handler_(handler) {}

  CefRefPtr<CefResourceHandler> Create(CefRefPtr<CefBrowser> browser,
                                       CefRefPtr<CefFrame> frame,
                                       const CefString& scheme_name,
                                       CefRefPtr<CefRequest> request) override {
    return new SchemeHandler(handler_);
  }

  IMPLEMENT_REFCOUNTING(SchemeHandlerFactory);

 private:
  __strong id<CKURLSchemeHandling> handler_;
};

}  // namespace chromiumkit

@interface CKNavigationAction ()
- (instancetype)initWithURL:(nullable NSURL *)url
                userGesture:(BOOL)userGesture
                   redirect:(BOOL)redirect
             opensNewWindow:(BOOL)opensNewWindow;
@end

@implementation CKNavigationAction
- (instancetype)initWithURL:(NSURL *)url
                userGesture:(BOOL)userGesture
                   redirect:(BOOL)redirect
             opensNewWindow:(BOOL)opensNewWindow {
  if ((self = [super init])) {
    _url = [url copy];
    _userGesture = userGesture;
    _redirect = redirect;
    _opensNewWindow = opensNewWindow;
  }
  return self;
}
@end

@interface CKPermissionRequest ()
- (instancetype)initWithOrigin:(nullable NSString *)origin kinds:(CKPermissionKinds)kinds;
@end

@implementation CKPermissionRequest
- (instancetype)initWithOrigin:(NSString *)origin kinds:(CKPermissionKinds)kinds {
  if ((self = [super init])) {
    _origin = [origin copy];
    _kinds = kinds;
  }
  return self;
}
@end

@implementation CKURLSchemeResponse
- (instancetype)initWithBody:(NSData *)body
                    mimeType:(NSString *)mimeType
                  statusCode:(NSInteger)statusCode
                     headers:(NSDictionary<NSString *,NSString *> *)headers {
  if ((self = [super init])) {
    _body = [body copy];
    _mimeType = [mimeType copy];
    _statusCode = statusCode;
    _headers = [headers copy];
  }
  return self;
}
@end

@implementation CKRuntimeConfiguration
- (instancetype)init {
  if ((self = [super init])) {
    _additionalArguments = @[];
    _knownCustomSchemes = @[];
  }
  return self;
}
@end

@implementation CKWebPageConfiguration
- (instancetype)init {
  if ((self = [super init])) {
    _urlSchemeHandlers = @{};
  }
  return self;
}
@end

@interface CKChromiumHostView : NSView
@property (nonatomic, weak) CKWebViewHostController *controller;
@end

@interface CKWebViewHostController ()
- (void)hostViewBecameReady;
- (void)attachBrowserViewIfNeeded;
- (void)didUpdateTitle:(nullable NSString *)title;
- (void)didUpdateURLString:(nullable NSString *)urlString;
- (void)didUpdateLoadingState:(BOOL)isLoading canGoBack:(BOOL)canGoBack canGoForward:(BOOL)canGoForward;
- (void)didUpdateEstimatedProgress:(double)progress;
- (NSInteger)beginNavigationForURLString:(nullable NSString *)urlString redirect:(BOOL)isRedirect;
- (void)didCommitNavigationWithID:(NSInteger)identifier urlString:(nullable NSString *)urlString;
- (void)didFinishNavigationWithID:(NSInteger)identifier urlString:(nullable NSString *)urlString httpStatusCode:(NSInteger)httpStatusCode;
- (void)didFailNavigationWithID:(NSInteger)identifier urlString:(nullable NSString *)urlString provisional:(BOOL)provisional code:(NSInteger)code description:(NSString *)description;
- (void)didEncounterRuntimeError:(NSError *)error;
- (CKNavigationDecision)decisionForURLString:(nullable NSString *)urlString userGesture:(BOOL)userGesture redirect:(BOOL)redirect opensNewWindow:(BOOL)opensNewWindow;
- (CKPermissionDecision)permissionDecisionForOrigin:(nullable NSString *)origin kinds:(CKPermissionKinds)kinds;
- (void)completeJavaScriptWithMessageID:(NSInteger)messageID success:(BOOL)success payload:(nullable NSString *)payload;
@end

namespace chromiumkit {

class DevToolsObserver final : public CefDevToolsMessageObserver {
 public:
  explicit DevToolsObserver(CKWebViewHostController* controller) : controller_(controller) {}

  void OnDevToolsMethodResult(CefRefPtr<CefBrowser> browser,
                              int message_id,
                              bool success,
                              const void* result,
                              size_t result_size) override {
    NSString* payload = nil;
    if (result && result_size > 0) {
      payload = [[NSString alloc] initWithBytes:result
                                         length:result_size
                                       encoding:NSUTF8StringEncoding];
    }

    dispatch_async(dispatch_get_main_queue(), ^{
      [controller_ completeJavaScriptWithMessageID:message_id success:success payload:payload];
    });
  }

  IMPLEMENT_REFCOUNTING(DevToolsObserver);

 private:
  __weak CKWebViewHostController* controller_;
};

class BrowserClient final : public CefClient,
                            public CefDisplayHandler,
                            public CefLoadHandler,
                            public CefRequestHandler,
                            public CefLifeSpanHandler,
                            public CefPermissionHandler {
 public:
  explicit BrowserClient(CKWebViewHostController* controller) : controller_(controller) {}

  CefRefPtr<CefDisplayHandler> GetDisplayHandler() override { return this; }
  CefRefPtr<CefLoadHandler> GetLoadHandler() override { return this; }
  CefRefPtr<CefRequestHandler> GetRequestHandler() override { return this; }
  CefRefPtr<CefLifeSpanHandler> GetLifeSpanHandler() override { return this; }
  CefRefPtr<CefPermissionHandler> GetPermissionHandler() override { return this; }

  bool OnProcessMessageReceived(CefRefPtr<CefBrowser> browser,
                                CefRefPtr<CefFrame> frame,
                                CefProcessId source_process,
                                CefRefPtr<CefProcessMessage> message) override {
    return false;
  }

  void OnAddressChange(CefRefPtr<CefBrowser> browser,
                       CefRefPtr<CefFrame> frame,
                       const CefString& url) override {
    if (!frame->IsMain()) {
      return;
    }

    NSString* url_string = ToNSString(url);
    DebugLog([NSString stringWithFormat:@"OnAddressChange url=%@",
              url_string ?: @"<nil>"]);

    dispatch_async(dispatch_get_main_queue(), ^{
      [controller_ didUpdateURLString:url_string];
    });
  }

  void OnTitleChange(CefRefPtr<CefBrowser> browser, const CefString& title) override {
    NSString* title_string = ToNSString(title);
    dispatch_async(dispatch_get_main_queue(), ^{
      [controller_ didUpdateTitle:title_string];
    });
  }

  void OnLoadingProgressChange(CefRefPtr<CefBrowser> browser, double progress) override {
    DebugLog([NSString stringWithFormat:@"OnLoadingProgressChange progress=%.3f", progress]);
    dispatch_async(dispatch_get_main_queue(), ^{
      [controller_ didUpdateEstimatedProgress:progress];
    });
  }

  void OnLoadingStateChange(CefRefPtr<CefBrowser> browser,
                            bool isLoading,
                            bool canGoBack,
                            bool canGoForward) override {
    DebugLog([NSString stringWithFormat:@"OnLoadingStateChange isLoading=%d canGoBack=%d canGoForward=%d",
              isLoading,
              canGoBack,
              canGoForward]);
    dispatch_async(dispatch_get_main_queue(), ^{
      [controller_ didUpdateLoadingState:isLoading canGoBack:canGoBack canGoForward:canGoForward];
    });
  }

  bool OnBeforeBrowse(CefRefPtr<CefBrowser> browser,
                      CefRefPtr<CefFrame> frame,
                      CefRefPtr<CefRequest> request,
                      bool user_gesture,
                      bool is_redirect) override {
    if (!frame->IsMain()) {
      return false;
    }

    NSString* url = ToNSString(request->GetURL());
    DebugLog([NSString stringWithFormat:@"OnBeforeBrowse url=%@ userGesture=%d redirect=%d",
              url ?: @"<nil>",
              user_gesture,
              is_redirect]);
    __block CKNavigationDecision decision = CKNavigationDecisionAllow;
    auto work = ^{
      decision = [controller_ decisionForURLString:url
                                       userGesture:user_gesture
                                          redirect:is_redirect
                                    opensNewWindow:NO];
      [controller_ beginNavigationForURLString:url redirect:is_redirect];
    };
    if ([NSThread isMainThread]) {
      work();
    } else {
      dispatch_sync(dispatch_get_main_queue(), work);
    }

    if (decision == CKNavigationDecisionOpenExternally) {
      NSURL* externalURL = url.length > 0 ? [NSURL URLWithString:url] : nil;
      if (externalURL) {
        [[NSWorkspace sharedWorkspace] openURL:externalURL];
      }
      return true;
    }

    return decision == CKNavigationDecisionCancel;
  }

  bool OnOpenURLFromTab(CefRefPtr<CefBrowser> browser,
                        CefRefPtr<CefFrame> frame,
                        const CefString& target_url,
                        WindowOpenDisposition target_disposition,
                        bool user_gesture) override {
    NSString* url = ToNSString(target_url);
    __block CKNavigationDecision decision = CKNavigationDecisionOpenExternally;
    auto work = ^{
      decision = [controller_ decisionForURLString:url
                                       userGesture:user_gesture
                                          redirect:NO
                                    opensNewWindow:YES];
    };
    if ([NSThread isMainThread]) {
      work();
    } else {
      dispatch_sync(dispatch_get_main_queue(), work);
    }

    if (decision == CKNavigationDecisionOpenExternally || decision == CKNavigationDecisionAllow) {
      NSURL* externalURL = url.length > 0 ? [NSURL URLWithString:url] : nil;
      if (externalURL) {
        [[NSWorkspace sharedWorkspace] openURL:externalURL];
      }
    }

    return true;
  }

  bool OnBeforePopup(CefRefPtr<CefBrowser> browser,
                     CefRefPtr<CefFrame> frame,
                     int popup_id,
                     const CefString& target_url,
                     const CefString& target_frame_name,
                     WindowOpenDisposition target_disposition,
                     bool user_gesture,
                     const CefPopupFeatures& popupFeatures,
                     CefWindowInfo& windowInfo,
                     CefRefPtr<CefClient>& client,
                     CefBrowserSettings& settings,
                     CefRefPtr<CefDictionaryValue>& extra_info,
                     bool* no_javascript_access) override {
    NSString* url = ToNSString(target_url);
    __block CKNavigationDecision decision = CKNavigationDecisionOpenExternally;
    auto work = ^{
      decision = [controller_ decisionForURLString:url
                                       userGesture:user_gesture
                                          redirect:NO
                                    opensNewWindow:YES];
    };
    if ([NSThread isMainThread]) {
      work();
    } else {
      dispatch_sync(dispatch_get_main_queue(), work);
    }

    if (decision != CKNavigationDecisionCancel) {
      NSURL* externalURL = url.length > 0 ? [NSURL URLWithString:url] : nil;
      if (externalURL) {
        [[NSWorkspace sharedWorkspace] openURL:externalURL];
      }
    }

    return true;
  }

  void OnAfterCreated(CefRefPtr<CefBrowser> browser) override {
    browser_ = browser;
    DebugLog([NSString stringWithFormat:@"OnAfterCreated browser=%d runtimeStyle=%d",
              browser->GetIdentifier(),
              browser->GetHost()->GetRuntimeStyle()]);
    dispatch_async(dispatch_get_main_queue(), ^{
      [controller_ attachBrowserViewIfNeeded];
      [controller_ hostViewBecameReady];
    });
  }

  void OnBeforeClose(CefRefPtr<CefBrowser> browser) override {
    browser_ = nullptr;
  }

  void OnLoadStart(CefRefPtr<CefBrowser> browser,
                   CefRefPtr<CefFrame> frame,
                   TransitionType transition_type) override {
    if (!frame->IsMain()) {
      return;
    }

    NSString* url_string = ToNSString(frame->GetURL());
    DebugLog([NSString stringWithFormat:@"OnLoadStart url=%@",
              url_string ?: @"<nil>"]);

    dispatch_async(dispatch_get_main_queue(), ^{
      [controller_ didCommitNavigationWithID:current_navigation_identifier_
                                   urlString:url_string];
    });
  }

  void OnLoadEnd(CefRefPtr<CefBrowser> browser,
                 CefRefPtr<CefFrame> frame,
                 int httpStatusCode) override {
    if (!frame->IsMain()) {
      return;
    }

    NSString* url_string = ToNSString(frame->GetURL());
    DebugLog([NSString stringWithFormat:@"OnLoadEnd url=%@ status=%d",
              url_string ?: @"<nil>",
              httpStatusCode]);

    dispatch_async(dispatch_get_main_queue(), ^{
      [controller_ didFinishNavigationWithID:current_navigation_identifier_
                                   urlString:url_string
                              httpStatusCode:httpStatusCode];
    });
  }

  void OnLoadError(CefRefPtr<CefBrowser> browser,
                   CefRefPtr<CefFrame> frame,
                   ErrorCode errorCode,
                   const CefString& errorText,
                   const CefString& failedUrl) override {
    if (!frame->IsMain()) {
      return;
    }

    NSString* failed_url_string = ToNSString(failedUrl);
    NSString* error_description = ToNSString(errorText) ?: @"Navigation failed";
    DebugLog([NSString stringWithFormat:@"OnLoadError url=%@ code=%d error=%@",
              failed_url_string ?: @"<nil>",
              static_cast<int>(errorCode),
              error_description]);

    const BOOL provisional = !has_committed_navigation_;
    dispatch_async(dispatch_get_main_queue(), ^{
      [controller_ didFailNavigationWithID:current_navigation_identifier_
                                 urlString:failed_url_string
                               provisional:provisional
                                      code:errorCode
                               description:error_description];
    });
  }

  bool OnRequestMediaAccessPermission(
      CefRefPtr<CefBrowser> browser,
      CefRefPtr<CefFrame> frame,
      const CefString& requesting_origin,
      uint32_t requested_permissions,
      CefRefPtr<CefMediaAccessCallback> callback) override {
    __block CKPermissionDecision decision = CKPermissionDecisionDefault;
    auto work = ^{
      decision = [controller_ permissionDecisionForOrigin:ToNSString(requesting_origin)
                                                    kinds:static_cast<CKPermissionKinds>(requested_permissions)];
    };
    if ([NSThread isMainThread]) {
      work();
    } else {
      dispatch_sync(dispatch_get_main_queue(), work);
    }

    switch (decision) {
      case CKPermissionDecisionAllow:
        callback->Continue(requested_permissions);
        return true;
      case CKPermissionDecisionDeny:
        callback->Cancel();
        return true;
      case CKPermissionDecisionDefault:
        return false;
    }
  }

  bool OnShowPermissionPrompt(
      CefRefPtr<CefBrowser> browser,
      uint64_t prompt_id,
      const CefString& requesting_origin,
      uint32_t requested_permissions,
      CefRefPtr<CefPermissionPromptCallback> callback) override {
    __block CKPermissionDecision decision = CKPermissionDecisionDefault;
    auto work = ^{
      decision = [controller_ permissionDecisionForOrigin:ToNSString(requesting_origin)
                                                    kinds:static_cast<CKPermissionKinds>(requested_permissions)];
    };
    if ([NSThread isMainThread]) {
      work();
    } else {
      dispatch_sync(dispatch_get_main_queue(), work);
    }

    switch (decision) {
      case CKPermissionDecisionAllow:
        callback->Continue(CEF_PERMISSION_RESULT_ACCEPT);
        return true;
      case CKPermissionDecisionDeny:
        callback->Continue(CEF_PERMISSION_RESULT_DENY);
        return true;
      case CKPermissionDecisionDefault:
        return false;
    }
  }

  void SetCurrentNavigationIdentifier(NSInteger identifier, bool redirect) {
    current_navigation_identifier_ = static_cast<int>(identifier);
    if (!redirect) {
      has_committed_navigation_ = false;
    }
  }

  void MarkCommitted() { has_committed_navigation_ = true; }

  void SetBrowser(CefRefPtr<CefBrowser> browser) { browser_ = browser; }

  CefRefPtr<CefBrowser> browser() const { return browser_; }

  IMPLEMENT_REFCOUNTING(BrowserClient);

 private:
  __weak CKWebViewHostController* controller_;
  CefRefPtr<CefBrowser> browser_;
  int current_navigation_identifier_ = 0;
  bool has_committed_navigation_ = false;
};

}  // namespace chromiumkit

@implementation CKChromiumHostView
- (BOOL)isFlipped {
  return YES;
}

- (void)viewDidMoveToWindow {
  [super viewDidMoveToWindow];
  [self.controller hostViewBecameReady];
}

- (void)layout {
  [super layout];
  [self.controller hostViewBecameReady];
}
@end

@implementation CKRuntime
+ (BOOL)ensureInitializedWithConfiguration:(CKRuntimeConfiguration *)configuration error:(NSError *__autoreleasing  _Nullable * _Nullable)error {
  auto& state = chromiumkit::SharedRuntimeState();
  if (state.initialized) {
    return YES;
  }

  CKInstallApplicationShim();

  if (configuration.helperExecutableURL == nil) {
    if (error) {
      *error = chromiumkit::MakeError(chromiumkit::kCKErrorMissingHelper, @"Missing helper executable path. Run `chromiumkit new-host` and embed the helper app into your macOS target.");
    }
    return NO;
  }

  if (![[NSFileManager defaultManager] isExecutableFileAtPath:configuration.helperExecutableURL.path]) {
    if (error) {
      *error = chromiumkit::MakeError(chromiumkit::kCKErrorMissingHelper, [NSString stringWithFormat:@"Helper executable is not present or not executable at %@.", configuration.helperExecutableURL.path]);
    }
    return NO;
  }

  if (configuration.cacheDirectoryURL) {
    [[NSFileManager defaultManager] createDirectoryAtURL:configuration.cacheDirectoryURL withIntermediateDirectories:YES attributes:nil error:nil];
  }

  state.custom_schemes.clear();
  for (NSString* scheme in configuration.knownCustomSchemes) {
    state.custom_schemes.push_back(chromiumkit::ToStdString(scheme.lowercaseString));
  }

  state.additional_arguments.clear();
  for (NSString* argument in configuration.additionalArguments) {
    state.additional_arguments.push_back(chromiumkit::ToStdString(argument));
  }

  CefSettings settings;
  settings.no_sandbox = true;
  settings.external_message_pump = true;
  settings.command_line_args_disabled = false;

  NSBundle *mainBundle = NSBundle.mainBundle;
  NSURL *frameworkURL = [mainBundle.privateFrameworksURL URLByAppendingPathComponent:@"Chromium Embedded Framework.framework"
                                                                        isDirectory:YES];
  NSURL *frameworkResourcesURL = [frameworkURL URLByAppendingPathComponent:@"Resources" isDirectory:YES];
  NSURL *frameworkLocalesURL = [frameworkResourcesURL URLByAppendingPathComponent:@"locales" isDirectory:YES];

  chromiumkit::SetCefString(settings.browser_subprocess_path, configuration.helperExecutableURL.path);
  chromiumkit::SetCefString(settings.main_bundle_path, mainBundle.bundleURL.path);
  chromiumkit::SetCefString(settings.framework_dir_path, frameworkURL.path);
  chromiumkit::SetCefString(settings.resources_dir_path, frameworkResourcesURL.path);
  chromiumkit::SetCefString(settings.locales_dir_path, frameworkLocalesURL.path);
  if (configuration.cacheDirectoryURL) {
    chromiumkit::SetCefString(settings.root_cache_path, configuration.cacheDirectoryURL.path);
    chromiumkit::SetCefString(settings.cache_path, configuration.cacheDirectoryURL.path);
  }
  if (configuration.logDirectoryURL) {
    NSURL* logFile = [configuration.logDirectoryURL URLByAppendingPathComponent:@"chromiumkit.log"];
    [[NSFileManager defaultManager] createDirectoryAtURL:configuration.logDirectoryURL withIntermediateDirectories:YES attributes:nil error:nil];
    chromiumkit::SetCefString(settings.log_file, logFile.path);
  }

  NSArray<NSString*>* arguments = NSProcessInfo.processInfo.arguments;
  std::vector<std::string> argv_storage;
  argv_storage.reserve(arguments.count);
  for (NSString* argument in arguments) {
    argv_storage.push_back(chromiumkit::ToStdString(argument));
  }

  std::vector<char*> argv;
  argv.reserve(argv_storage.size());
  for (auto& argument : argv_storage) {
    argv.push_back(argument.data());
  }

  CefMainArgs main_args(static_cast<int>(argv.size()), argv.data());
  state.app = new chromiumkit::RuntimeApp(state.custom_schemes, state.additional_arguments);

  if (!CefInitialize(main_args, settings, state.app.get(), nullptr)) {
    if (error) {
      *error = chromiumkit::MakeError(chromiumkit::kCKErrorRuntimeNotInitialized, @"CEF failed to initialize in the browser process.");
    }
    return NO;
  }

  state.initialized = true;
  state.scheduler.MarkInitialized(true);
  return YES;
}

+ (void)shutdown {
  auto& state = chromiumkit::SharedRuntimeState();
  if (!state.initialized) {
    return;
  }
  CefShutdown();
  state.initialized = false;
  state.scheduler.MarkInitialized(false);
  state.app = nullptr;
}
@end

@implementation CKWebViewHostController {
  CKChromiumHostView *_hostView;
  CKWebPageConfiguration *_configuration;
  CefRefPtr<chromiumkit::BrowserClient> _client;
  CefRefPtr<CefRequestContext> _requestContext;
  CefRefPtr<chromiumkit::DevToolsObserver> _devToolsObserver;
  CefRefPtr<CefRegistration> _devToolsRegistration;
  NSURLRequest *_pendingRequest;
  NSString *_pendingHTML;
  NSURL *_pendingHTMLBaseURL;
  NSData *_pendingData;
  NSString *_pendingMimeType;
  NSString *_pendingCharacterEncoding;
  NSURL *_pendingDataBaseURL;
  BOOL _browserCreating;
  NSInteger _nextNavigationIdentifier;
  NSMutableDictionary<NSNumber *, id> *_pendingJavaScriptCompletions;
}

- (NSString *)htmlDataURLFromHTML:(NSString *)html baseURL:(NSURL *)baseURL {
  NSString *composed = html ?: @"";
  if (baseURL.absoluteString.length > 0) {
    NSRange headRange = [composed rangeOfString:@"<head>" options:NSCaseInsensitiveSearch];
    NSString *baseTag = [NSString stringWithFormat:@"<base href=\"%@\">", baseURL.absoluteString];
    if (headRange.location != NSNotFound) {
      composed = [composed stringByReplacingCharactersInRange:NSMakeRange(NSMaxRange(headRange), 0) withString:baseTag];
    } else {
      composed = [NSString stringWithFormat:@"<head>%@</head>%@", baseTag, composed];
    }
  }

  NSData *data = [composed dataUsingEncoding:NSUTF8StringEncoding] ?: [NSData data];
  NSString *base64 = [data base64EncodedStringWithOptions:0];
  return [NSString stringWithFormat:@"data:text/html;charset=utf-8;base64,%@", base64];
}

- (NSString *)dataURLFromData:(NSData *)data
                     mimeType:(NSString *)mimeType
            characterEncoding:(NSString *)characterEncoding
                      baseURL:(NSURL *)baseURL {
  if ([mimeType caseInsensitiveCompare:@"text/html"] == NSOrderedSame &&
      [characterEncoding caseInsensitiveCompare:@"utf-8"] == NSOrderedSame) {
    NSString *html = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    if (html) {
      return [self htmlDataURLFromHTML:html baseURL:baseURL];
    }
  }

  NSString *base64 = [data base64EncodedStringWithOptions:0];
  return [NSString stringWithFormat:@"data:%@;charset=%@;base64,%@",
                                    mimeType ?: @"application/octet-stream",
                                    characterEncoding ?: @"utf-8",
                                    base64];
}

- (BOOL)canRepresentRequestAsSimpleNavigation:(NSURLRequest *)request {
  if (request.URL.absoluteString.length == 0) {
    return NO;
  }

  NSString *method = request.HTTPMethod ?: @"GET";
  if ([method caseInsensitiveCompare:@"GET"] != NSOrderedSame) {
    return NO;
  }

  if (request.HTTPBody.length > 0 || request.HTTPBodyStream != nil) {
    return NO;
  }

  return request.allHTTPHeaderFields.count == 0;
}

- (NSString *)consumeInitialNavigationURLIfPossible {
  if (_pendingRequest && [self canRepresentRequestAsSimpleNavigation:_pendingRequest]) {
    NSString *urlString = _pendingRequest.URL.absoluteString;
    _pendingRequest = nil;
    return urlString;
  }

  if (_pendingHTML) {
    NSString *dataURL = [self htmlDataURLFromHTML:_pendingHTML baseURL:_pendingHTMLBaseURL];
    _pendingHTML = nil;
    _pendingHTMLBaseURL = nil;
    return dataURL;
  }

  if (_pendingData) {
    NSString *dataURL = [self dataURLFromData:_pendingData
                                     mimeType:_pendingMimeType
                            characterEncoding:_pendingCharacterEncoding
                                      baseURL:_pendingDataBaseURL];
    _pendingData = nil;
    _pendingMimeType = nil;
    _pendingCharacterEncoding = nil;
    _pendingDataBaseURL = nil;
    return dataURL;
  }

  return @"about:blank";
}

- (instancetype)initWithConfiguration:(CKWebPageConfiguration *)configuration {
  if ((self = [super init])) {
    _configuration = configuration;
    _hostView = [[CKChromiumHostView alloc] initWithFrame:NSZeroRect];
    _hostView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    _hostView.controller = self;
    _pendingJavaScriptCompletions = [[NSMutableDictionary alloc] init];
    _nextNavigationIdentifier = 1;
  }
  return self;
}

- (NSView *)view {
  return _hostView;
}

- (BOOL)load:(NSURLRequest *)request error:(NSError *__autoreleasing  _Nullable * _Nullable)error {
  _pendingRequest = [request copy];
  _pendingHTML = nil;
  _pendingData = nil;
  [self hostViewBecameReady];
  return YES;
}

- (BOOL)loadHTMLString:(NSString *)html baseURL:(NSURL *)baseURL error:(NSError *__autoreleasing  _Nullable * _Nullable)error {
  _pendingHTML = [html copy];
  _pendingHTMLBaseURL = [baseURL copy];
  _pendingRequest = nil;
  _pendingData = nil;
  [self hostViewBecameReady];
  return YES;
}

- (BOOL)loadData:(NSData *)data
        mimeType:(NSString *)mimeType
characterEncoding:(NSString *)characterEncoding
         baseURL:(NSURL *)baseURL
           error:(NSError *__autoreleasing  _Nullable * _Nullable)error {
  _pendingData = [data copy];
  _pendingMimeType = [mimeType copy];
  _pendingCharacterEncoding = [characterEncoding copy];
  _pendingDataBaseURL = [baseURL copy];
  _pendingRequest = nil;
  _pendingHTML = nil;
  [self hostViewBecameReady];
  return YES;
}

- (void)reload {
  if (_client && _client->browser()) {
    _client->browser()->Reload();
  }
}

- (void)stopLoading {
  if (_client && _client->browser()) {
    _client->browser()->StopLoad();
  }
}

- (void)goBack {
  if (_client && _client->browser() && _client->browser()->CanGoBack()) {
    _client->browser()->GoBack();
  }
}

- (void)goForward {
  if (_client && _client->browser() && _client->browser()->CanGoForward()) {
    _client->browser()->GoForward();
  }
}

- (void)evaluateJavaScript:(NSString *)javaScript completionHandler:(void (^)(NSString * _Nullable, NSError * _Nullable))completionHandler {
  if (!(_client && _client->browser())) {
    completionHandler(nil, chromiumkit::MakeError(chromiumkit::kCKErrorBrowserUnavailable, @"The browser is not attached to a window yet."));
    return;
  }

  if (!_devToolsObserver) {
    _devToolsObserver = new chromiumkit::DevToolsObserver(self);
    _devToolsRegistration = _client->browser()->GetHost()->AddDevToolsMessageObserver(_devToolsObserver);
  }

  NSString *wrappedExpression =
      [NSString stringWithFormat:
          @"(async () => { const __ck_value = await (async function(){ %@ })(); if (typeof __ck_value === 'undefined') { return JSON.stringify({ chromiumKitType: 'undefined' }); } return JSON.stringify({ chromiumKitType: 'value', value: __ck_value }); })()",
          javaScript ?: @""];

  auto params = CefDictionaryValue::Create();
  params->SetString("expression", chromiumkit::ToStdString(wrappedExpression));
  params->SetBool("awaitPromise", true);
  params->SetBool("returnByValue", true);

  const int messageID = _client->browser()->GetHost()->ExecuteDevToolsMethod(0, "Runtime.evaluate", params);
  _pendingJavaScriptCompletions[@(messageID)] = [completionHandler copy];
}

- (void)hostViewBecameReady {
  chromiumkit::DebugLog([NSString stringWithFormat:
      @"hostViewBecameReady window=%@ bounds=%@ creating=%d client=%d browser=%d pendingRequest=%@",
      _hostView.window,
      NSStringFromRect(_hostView.bounds),
      _browserCreating,
      _client ? 1 : 0,
      (_client && _client->browser()) ? 1 : 0,
      _pendingRequest.URL.absoluteString ?: @"<nil>"]);

  if (_browserCreating || _client || _hostView.window == nil) {
    [self applyPendingLoadIfNeeded];
    return;
  }

  NSError *runtimeError = nil;
  if (![CKRuntime ensureInitializedWithConfiguration:[CKRuntimeConfiguration new] error:&runtimeError]) {
    [self didEncounterRuntimeError:runtimeError];
    return;
  }

  _requestContext = nullptr;
  if (_configuration.cacheDirectoryURL || _configuration.urlSchemeHandlers.count > 0) {
    CefRequestContextSettings context_settings;
    if (_configuration.cacheDirectoryURL) {
      chromiumkit::SetCefString(context_settings.cache_path, _configuration.cacheDirectoryURL.path);
    }
    _requestContext = CefRequestContext::CreateContext(context_settings, nullptr);
    for (NSString *scheme in _configuration.urlSchemeHandlers) {
      id<CKURLSchemeHandling> handler = _configuration.urlSchemeHandlers[scheme];
      _requestContext->RegisterSchemeHandlerFactory(
          chromiumkit::ToStdString(scheme.lowercaseString),
          "",
          new chromiumkit::SchemeHandlerFactory(handler));
    }
  }

  _client = new chromiumkit::BrowserClient(self);
  _browserCreating = YES;

  CefWindowInfo window_info;
  window_info.SetAsChild(CAST_NSVIEW_TO_CEF_WINDOW_HANDLE(_hostView), CefRect(0, 0, NSWidth(_hostView.bounds), NSHeight(_hostView.bounds)));
  window_info.runtime_style = CEF_RUNTIME_STYLE_ALLOY;

  CefBrowserSettings settings;
  CefRefPtr<CefBrowser> browser = CefBrowserHost::CreateBrowserSync(
      window_info,
      _client,
      "about:blank",
      settings,
      nullptr,
      _requestContext);

  chromiumkit::DebugLog([NSString stringWithFormat:@"CreateBrowserSync browser=%@ initialURL=%@ pendingRequest=%@",
                         browser ? [NSString stringWithFormat:@"%d", browser->GetIdentifier()] : @"<nil>",
                         @"about:blank",
                         _pendingRequest.URL.absoluteString ?: @"<nil>"]);

  if (!browser) {
    _browserCreating = NO;
    [self didEncounterRuntimeError:chromiumkit::MakeError(
        chromiumkit::kCKErrorBrowserUnavailable,
        @"CEF refused to create the browser instance. Check bridge debug logs for host-view state.")];
    return;
  }

  _client->SetBrowser(browser);
  [self attachBrowserViewIfNeeded];
  [self applyPendingLoadIfNeeded];
}

- (void)attachBrowserViewIfNeeded {
  if (!(_client && _client->browser())) {
    return;
  }

  NSView *browserView = CAST_CEF_WINDOW_HANDLE_TO_NSVIEW(_client->browser()->GetHost()->GetWindowHandle());
  chromiumkit::DebugLog([NSString stringWithFormat:@"attachBrowserViewIfNeeded browserView=%@ hostBounds=%@",
                         browserView,
                         NSStringFromRect(_hostView.bounds)]);
  if (!browserView) {
    return;
  }

  browserView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
  browserView.frame = _hostView.bounds;
  if (browserView.superview != _hostView) {
    [_hostView addSubview:browserView];
  }
}

- (void)applyPendingLoadIfNeeded {
  if (!(_client && _client->browser())) {
    return;
  }

  chromiumkit::DebugLog([NSString stringWithFormat:@"applyPendingLoadIfNeeded request=%@ html=%d data=%d",
                         _pendingRequest.URL.absoluteString ?: @"<nil>",
                         _pendingHTML != nil,
                         _pendingData != nil]);

  if (_pendingRequest) {
    if ([self canRepresentRequestAsSimpleNavigation:_pendingRequest]) {
      _client->browser()->GetMainFrame()->LoadURL(chromiumkit::ToStdString(_pendingRequest.URL.absoluteString));
    } else {
      _client->browser()->GetMainFrame()->LoadRequest(chromiumkit::CreateRequest(_pendingRequest));
    }
    _pendingRequest = nil;
  } else if (_pendingHTML) {
    NSString *dataURL = [self htmlDataURLFromHTML:_pendingHTML baseURL:_pendingHTMLBaseURL];
    _client->browser()->GetMainFrame()->LoadURL(chromiumkit::ToStdString(dataURL));
    _pendingHTML = nil;
    _pendingHTMLBaseURL = nil;
  } else if (_pendingData) {
    NSString *dataURL = [self dataURLFromData:_pendingData
                                     mimeType:_pendingMimeType
                            characterEncoding:_pendingCharacterEncoding
                                      baseURL:_pendingDataBaseURL];
    _client->browser()->GetMainFrame()->LoadURL(chromiumkit::ToStdString(dataURL));
    _pendingData = nil;
    _pendingMimeType = nil;
    _pendingCharacterEncoding = nil;
    _pendingDataBaseURL = nil;
  }
}

- (void)didUpdateTitle:(NSString *)title {
  [self.delegate webViewHostController:self didUpdateTitle:title];
}

- (void)didUpdateURLString:(NSString *)urlString {
  [self.delegate webViewHostController:self didUpdateURL:urlString.length > 0 ? [NSURL URLWithString:urlString] : nil];
}

- (void)didUpdateLoadingState:(BOOL)isLoading canGoBack:(BOOL)canGoBack canGoForward:(BOOL)canGoForward {
  [self.delegate webViewHostController:self didUpdateLoadingState:isLoading canGoBack:canGoBack canGoForward:canGoForward];
}

- (void)didUpdateEstimatedProgress:(double)progress {
  [self.delegate webViewHostController:self didUpdateEstimatedProgress:progress];
}

- (NSInteger)beginNavigationForURLString:(NSString *)urlString redirect:(BOOL)isRedirect {
  const NSInteger identifier = isRedirect ? MAX(1, _nextNavigationIdentifier - 1) : _nextNavigationIdentifier++;
  if (_client) {
    _client->SetCurrentNavigationIdentifier(identifier, isRedirect);
  }
  [self.delegate webViewHostController:self
               didStartNavigationWithID:identifier
                                     url:urlString.length > 0 ? [NSURL URLWithString:urlString] : nil
                               isRedirect:isRedirect];
  return identifier;
}

- (void)didCommitNavigationWithID:(NSInteger)identifier urlString:(NSString *)urlString {
  if (_client) {
    _client->MarkCommitted();
  }
  [self.delegate webViewHostController:self
             didCommitNavigationWithID:identifier
                                   url:urlString.length > 0 ? [NSURL URLWithString:urlString] : nil];
}

- (void)didFinishNavigationWithID:(NSInteger)identifier urlString:(NSString *)urlString httpStatusCode:(NSInteger)httpStatusCode {
  _browserCreating = NO;
  [self applyPendingLoadIfNeeded];
  [self.delegate webViewHostController:self
             didFinishNavigationWithID:identifier
                                   url:urlString.length > 0 ? [NSURL URLWithString:urlString] : nil
                        httpStatusCode:httpStatusCode];
}

- (void)didFailNavigationWithID:(NSInteger)identifier urlString:(NSString *)urlString provisional:(BOOL)provisional code:(NSInteger)code description:(NSString *)description {
  _browserCreating = NO;
  [self.delegate webViewHostController:self
              didFailNavigationWithID:identifier
                                   url:urlString.length > 0 ? [NSURL URLWithString:urlString] : nil
                           provisional:provisional
                                  code:code
                           description:description];
}

- (void)didEncounterRuntimeError:(NSError *)error {
  [self.delegate webViewHostController:self didEncounterRuntimeError:error];
}

- (CKNavigationDecision)decisionForURLString:(NSString *)urlString userGesture:(BOOL)userGesture redirect:(BOOL)redirect opensNewWindow:(BOOL)opensNewWindow {
  if (!_configuration.navigationDecider) {
    return opensNewWindow ? CKNavigationDecisionOpenExternally : CKNavigationDecisionAllow;
  }

  CKNavigationAction *action = [[CKNavigationAction alloc] initWithURL:urlString.length > 0 ? [NSURL URLWithString:urlString] : nil
                                                           userGesture:userGesture
                                                              redirect:redirect
                                                        opensNewWindow:opensNewWindow];
  return [_configuration.navigationDecider decidePolicyForAction:action];
}

- (CKPermissionDecision)permissionDecisionForOrigin:(NSString *)origin kinds:(CKPermissionKinds)kinds {
  if (!_configuration.permissionDecider) {
    return CKPermissionDecisionDefault;
  }

  CKPermissionRequest *request = [[CKPermissionRequest alloc] initWithOrigin:origin kinds:kinds];
  return [_configuration.permissionDecider decidePermissionForRequest:request];
}

- (void)completeJavaScriptWithMessageID:(NSInteger)messageID success:(BOOL)success payload:(NSString *)payload {
  void (^completion)(NSString *, NSError *) = _pendingJavaScriptCompletions[@(messageID)];
  if (!completion) {
    return;
  }

  [_pendingJavaScriptCompletions removeObjectForKey:@(messageID)];
  if (!success) {
    completion(nil, chromiumkit::MakeError(chromiumkit::kCKErrorJavaScriptFailure, payload ?: @"JavaScript evaluation failed."));
    return;
  }

  NSData *data = [payload dataUsingEncoding:NSUTF8StringEncoding];
  NSDictionary *root = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
  NSDictionary *result = root[@"result"];
  NSString *value = result[@"value"];
  completion(value, nil);
}

@end
