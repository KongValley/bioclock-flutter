#pragma once

// Minimal CW2A fallback used only when MSVC C++ ATL headers are not installed
// on the local build machine (e.g. VS Build Tools without ATLMFC component).
#include <string>
#include <windows.h>

class CW2A {
 public:
  explicit CW2A(LPCWSTR wide, UINT code_page = CP_UTF8) {
    if (wide == nullptr) return;
    const int required =
        WideCharToMultiByte(code_page, 0, wide, -1, nullptr, 0, nullptr, nullptr);
    if (required > 1) {
      buf_.resize(static_cast<size_t>(required));
      WideCharToMultiByte(
          code_page, 0, wide, -1, buf_.data(), required, nullptr, nullptr);
      buf_.pop_back();
    }
  }

  operator const char*() const noexcept { return buf_.c_str(); }

 private:
  std::string buf_;
};
