#import <Cocoa/Cocoa.h>

#include <fstream>
#include <sstream>

#include "include/cef_app.h"
#include "include/cef_scheme.h"
#include "include/wrapper/cef_library_loader.h"

namespace {
void DebugLog(const std::string& message) {
  @autoreleasepool {
    NSArray<NSURL*>* directories = [[NSFileManager defaultManager]
        URLsForDirectory:NSApplicationSupportDirectory
               inDomains:NSUserDomainMask];
    NSURL* base_directory = directories.firstObject;
    if (!base_directory) {
      return;
    }

    NSURL* support_directory =
        [base_directory URLByAppendingPathComponent:@"ChromiumKitHost"
                                       isDirectory:YES];
    [[NSFileManager defaultManager] createDirectoryAtURL:support_directory
                             withIntermediateDirectories:YES
                                              attributes:nil
                                                   error:nil];
    NSURL* log_url = [support_directory URLByAppendingPathComponent:@"helper.log"];
    std::ofstream stream(log_url.path.UTF8String, std::ios::app);
    if (!stream.is_open()) {
      return;
    }

    stream << message << std::endl;
  }
}

class HelperApp final : public CefApp {
 public:
  void OnRegisterCustomSchemes(CefRawPtr<CefSchemeRegistrar> registrar) override {
    auto command_line = CefCommandLine::GetGlobalCommandLine();
    if (!command_line) {
      return;
    }

    const auto joined = command_line->GetSwitchValue("chromiumkit-custom-schemes");
    if (joined.empty()) {
      return;
    }

    std::stringstream stream(joined.ToString());
    std::string scheme;
    while (std::getline(stream, scheme, ',')) {
      if (!scheme.empty()) {
        registrar->AddCustomScheme(
            scheme,
            CEF_SCHEME_OPTION_STANDARD |
                CEF_SCHEME_OPTION_SECURE |
                CEF_SCHEME_OPTION_CORS_ENABLED |
                CEF_SCHEME_OPTION_FETCH_ENABLED);
      }
    }
  }

  IMPLEMENT_REFCOUNTING(HelperApp);
};
}  // namespace

int main(int argc, char* argv[]) {
  std::stringstream command_line_stream;
  for (int index = 0; index < argc; ++index) {
    if (index > 0) {
      command_line_stream << ' ';
    }
    command_line_stream << argv[index];
  }
  DebugLog("Helper main argv=" + command_line_stream.str());

  CefScopedLibraryLoader library_loader;
  if (!library_loader.LoadInHelper()) {
    DebugLog("LoadInHelper failed");
    return 1;
  }

  CefMainArgs main_args(argc, argv);
  CefRefPtr<HelperApp> app(new HelperApp);
  const int exit_code = CefExecuteProcess(main_args, app, nullptr);
  DebugLog("CefExecuteProcess exit_code=" + std::to_string(exit_code));
  return exit_code;
}
