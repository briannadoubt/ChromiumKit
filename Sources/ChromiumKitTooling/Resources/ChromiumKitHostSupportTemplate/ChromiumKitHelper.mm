#import <Cocoa/Cocoa.h>

#include <sstream>

#include "include/cef_app.h"
#include "include/cef_scheme.h"
#include "include/wrapper/cef_library_loader.h"

namespace {
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
  CefScopedLibraryLoader library_loader;
  if (!library_loader.LoadInHelper()) {
    return 1;
  }

  CefMainArgs main_args(argc, argv);
  CefRefPtr<HelperApp> app(new HelperApp);
  return CefExecuteProcess(main_args, app, nullptr);
}
