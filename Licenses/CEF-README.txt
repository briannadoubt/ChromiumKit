Chromium Embedded Framework (CEF) Minimal Binary Distribution for MacOS
-------------------------------------------------------------------------------

Date:             April 15, 2026

CEF Version:      146.0.11+g3a0fcf1+chromium-146.0.7680.179
CEF URL:          https://github.com/chromiumembedded/cef.git
                  @3a0fcf1e1b6249b50c96ac77c429bfefade09d96

Chromium Version: 146.0.7680.179
Chromium URL:     https://chromium.googlesource.com/chromium/src.git
                  @347d8fd10aba5b885fb19ba5ea809b39b94afd0b

This distribution contains the minimal components necessary to build and
distribute an application using CEF on the MacOS platform. Please see
the LICENSING section of this document for licensing terms and conditions.


CONTENTS
--------

bazel       Contains Bazel configuration files shared by all targets.

cmake       Contains CMake configuration files shared by all targets.

include     Contains all required CEF header files.

libcef_dll  Contains the source code for the libcef_dll_wrapper static library
            that all applications using the CEF C++ API must link against.

Release     Contains the "Chromium Embedded Framework.framework" and other
            components required to run the release version of CEF-based
            applications.


USAGE
-----

Building using CMake:
  CMake can be used to generate project files in many different formats. See
  usage instructions at the top of the CMakeLists.txt file.

Building using Bazel:
  Bazel can be used to build CEF-based applications. CEF support for Bazel is
  considered experimental. For current development status see
  https://github.com/chromiumembedded/cef/issues/3757.

Please visit the CEF Website for additional usage information.

https://github.com/chromiumembedded/cef/


REDISTRIBUTION
--------------

This binary distribution contains the below components. Components listed under
the "required" section must be redistributed with all applications using CEF.
Components listed under the "optional" section may be excluded if the related
features will not be used.

Applications using CEF on MacOS must follow a specific app bundle structure.
Replace "cefclient" in the below example with your application name.

cefclient.app
└── Contents
    ├── Frameworks
    │   ├── Chromium Embedded Framework.framework
    │   │   ├── Chromium Embedded Framework <= main application library
    │   │   ├── Libraries
    │   │   │   ├── libEGL.dylib <= ANGLE support libraries
    │   │   │   ├── libGLESv2.dylib <=^
    │   │   │   ├── libvk_swiftshader.dylib <= SwANGLE support libraries
    │   │   │   └── vk_swiftshader_icd.json <=^
    │   │   └── Resources
    │   │       ├── chrome_100_percent.pak <= non-localized resources and strings
    │   │       ├── chrome_200_percent.pak <=^
    │   │       ├── resources.pak          <=^
    │   │       ├── gpu_shader_cache.bin <= ANGLE-Metal shader cache
    │   │       ├── icudtl.dat <= unicode support
    │   │       ├── v8_context_snapshot.[x86_64|arm64].bin <= V8 initial snapshot
    │   │       ├── en.lproj/, ... <= locale-specific resources and strings
    │   │       └── Info.plist
    │   ├── cefclient Helper.app
    │   │   └── Contents
    │   │       ├── Info.plist
    │   │       ├── MacOS
    │   │       │   └── cefclient Helper <= helper executable
    │   │       └── Pkginfo
    │   └── Info.plist
    ├── MacOS
    │   └── cefclient <= cefclient application executable
    ├── Pkginfo
    └── Resources
        └── binding.html, ... <= cefclient application resources

The "Chromium Embedded Framework.framework" is an unversioned framework that
contains CEF binaries and resources. Executables (cefclient, cefclient Helper,
etc) must load this framework dynamically at runtime instead of linking it
directly. See the documentation in include/wrapper/cef_library_loader.h for
more information.

Newer Xcode versions (specifically Xcode 26) require a versioned framework
directory structure using relative symlinks as follows:

  Chromium Embedded Framework.framework
  ├── Chromium Embedded Framework -> Versions/A/Chromium Embedded Framework
  ├── Libraries -> Versions/A/Libraries
  ├── Resources -> Versions/A/Resources
  └── Versions
     ├── A  (actual framework contents)
     │   ├── Chromium Embedded Framework
     │   ├── Libraries
     │   └── Resources
     └── Current -> A

This structure can be created while constructing the final app bundle as
demonstrated by the supplied CMake and Bazel configurations.

The "cefclient Helper" app is used for executing separate processes (renderer,
plugin, etc) with different characteristics. It needs to have a separate app
bundle and Info.plist file so that, among other things, it doesn't show dock
icons.

Required components:

The following components are required. CEF will not function without them.

* CEF core library.
  * Chromium Embedded Framework.framework/Chromium Embedded Framework

* Unicode support data.
  * Chromium Embedded Framework.framework/Resources/icudtl.dat

* V8 snapshot data.
  * Chromium Embedded Framework.framework/Resources/v8_context_snapshot.bin

Optional components:

The following components are optional. If they are missing CEF will continue to
run but any related functionality may become broken or disabled.

* Localized resources.
  Locale file loading can be disabled completely using
  CefSettings.pack_loading_disabled.

  * Chromium Embedded Framework.framework/Resources/*.lproj/
    Directory containing localized resources used by CEF, Chromium and Blink. A
    .pak file is loaded from this directory based on the CefSettings.locale
    value. Only configured locales need to be distributed. If no locale is
    configured the default locale of "en" will be used. Without these files
    arbitrary Web components may display incorrectly.

* Other resources.
  Pack file loading can be disabled completely using
  CefSettings.pack_loading_disabled.

  * Chromium Embedded Framework.framework/Resources/chrome_100_percent.pak
  * Chromium Embedded Framework.framework/Resources/chrome_200_percent.pak
  * Chromium Embedded Framework.framework/Resources/resources.pak
    These files contain non-localized resources used by CEF, Chromium and Blink.
    Without these files arbitrary Web components may display incorrectly.

* ANGLE support.
  * Chromium Embedded Framework.framework/Libraries/libEGL.dylib
  * Chromium Embedded Framework.framework/Libraries/libGLESv2.dylib
  * Chromium Embedded Framework.framework/Resources/gpu_shader_cache.bin
  Support for rendering of HTML5 content like 2D canvas, 3D CSS and WebGL.
  Without these files the aforementioned capabilities may fail.

* SwANGLE support.
  * Chromium Embedded Framework.framework/Libraries/libvk_swiftshader.dylib
  * Chromium Embedded Framework.framework/Libraries/vk_swiftshader_icd.json
  Support for software rendering of HTML5 content like 2D canvas, 3D CSS and
  WebGL using SwiftShader's Vulkan library as ANGLE's Vulkan backend. Without
  these files the aforementioned capabilities may fail when GPU acceleration is
  disabled or unavailable.


LICENSING
---------

The CEF project is BSD licensed. Please read the LICENSE.txt file included with
this binary distribution for licensing terms and conditions. Other software
included in this distribution is provided under other licenses. Please see the
CREDITS.html file or visit "about:credits" in a CEF-based application for
complete Chromium and third-party licensing information.
