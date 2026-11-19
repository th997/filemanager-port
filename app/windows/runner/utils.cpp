#include "utils.h"

#include <flutter_windows.h>
#include <io.h>
#include <stdio.h>
#include <windows.h>

#include <iostream>
#include <string>
#include <cwchar>

namespace {

std::wstring ReadRegistryString(HKEY root, const wchar_t* subkey,
                                const wchar_t* value_name) {
  HKEY key = nullptr;
  if (::RegOpenKeyExW(root, subkey, 0, KEY_QUERY_VALUE, &key) !=
      ERROR_SUCCESS) {
    return std::wstring();
  }
  DWORD type = 0;
  DWORD byte_len = 0;
  std::wstring result;
  if (::RegQueryValueExW(key, value_name, nullptr, &type, nullptr,
                         &byte_len) == ERROR_SUCCESS &&
      (type == REG_SZ || type == REG_EXPAND_SZ) &&
      byte_len > sizeof(wchar_t)) {
    result.resize(byte_len / sizeof(wchar_t));
    if (::RegQueryValueExW(key, value_name, nullptr, &type,
                           reinterpret_cast<BYTE*>(result.data()),
                           &byte_len) != ERROR_SUCCESS) {
      result.clear();
    } else if (!result.empty() && result.back() == L'\0') {
      result.pop_back();
    }
  }
  ::RegCloseKey(key);
  return result;
}

void SetRegistryStringValue(HKEY root, const wchar_t* subkey,
                            const wchar_t* value_name, const wchar_t* data) {
  if (ReadRegistryString(root, subkey, value_name) == data) {
    return;
  }
  HKEY key = nullptr;
  if (::RegCreateKeyExW(root, subkey, 0, nullptr, REG_OPTION_NON_VOLATILE,
                        KEY_SET_VALUE, nullptr, &key, nullptr) == ERROR_SUCCESS) {
    const DWORD byte_len =
        static_cast<DWORD>((wcslen(data) + 1) * sizeof(wchar_t));
    ::RegSetValueExW(key, value_name, 0, REG_SZ,
                     reinterpret_cast<const BYTE*>(data), byte_len);
    ::RegCloseKey(key);
  }
}

// OpenWithProgids entries are documented as REG_NONE values.
void SetRegistryNoneValue(HKEY root, const wchar_t* subkey,
                          const wchar_t* value_name) {
  HKEY key = nullptr;
  if (::RegCreateKeyExW(root, subkey, 0, nullptr, REG_OPTION_NON_VOLATILE,
                        KEY_SET_VALUE, nullptr, &key, nullptr) == ERROR_SUCCESS) {
    ::RegSetValueExW(key, value_name, 0, REG_NONE, nullptr, 0);
    ::RegCloseKey(key);
  }
}

}  // namespace

void CreateAndAttachConsole() {
  if (::AllocConsole()) {
    FILE *unused;
    if (freopen_s(&unused, "CONOUT$", "w", stdout)) {
      _dup2(_fileno(stdout), 1);
    }
    if (freopen_s(&unused, "CONOUT$", "w", stderr)) {
      _dup2(_fileno(stderr), 2);
    }
    std::ios::sync_with_stdio();
    FlutterDesktopResyncOutputStreams();
  }
}

std::vector<std::string> GetCommandLineArguments() {
  // Convert the UTF-16 command line arguments to UTF-8 for the Engine to use.
  int argc;
  wchar_t** argv = ::CommandLineToArgvW(::GetCommandLineW(), &argc);
  if (argv == nullptr) {
    return std::vector<std::string>();
  }

  std::vector<std::string> command_line_arguments;

  // Skip the first argument as it's the binary name.
  for (int i = 1; i < argc; i++) {
    command_line_arguments.push_back(Utf8FromUtf16(argv[i]));
  }

  ::LocalFree(argv);

  return command_line_arguments;
}

std::string Utf8FromUtf16(const wchar_t* utf16_string) {
  if (utf16_string == nullptr) {
    return std::string();
  }
  // First, find the length of the string with a safe upper bound (CWE-126).
  // UNICODE_STRING_MAX_CHARS (32767) is the maximum length of a UNICODE_STRING.
  int input_length = static_cast<int>(wcsnlen(utf16_string, UNICODE_STRING_MAX_CHARS));
  // Now use that bounded length to determine the required buffer size.
  // When an explicit length is passed, WideCharToMultiByte does not include
  // the null terminator in its returned size.
  int target_length = ::WideCharToMultiByte(
      CP_UTF8, WC_ERR_INVALID_CHARS, utf16_string,
      input_length, nullptr, 0, nullptr, nullptr);
  std::string utf8_string;
  if (target_length == 0 || static_cast<size_t>(target_length) > utf8_string.max_size()) {
    return utf8_string;
  }
  utf8_string.resize(target_length);
  int converted_length = ::WideCharToMultiByte(
      CP_UTF8, WC_ERR_INVALID_CHARS, utf16_string,
      input_length, utf8_string.data(), target_length, nullptr, nullptr);
  if (converted_length == 0) {
    return std::string();
  }
  return utf8_string;
}

void RegisterWindowsOpenWithAssociations() {
  wchar_t exe_path[MAX_PATH] = {0};
  DWORD len = ::GetModuleFileNameW(nullptr, exe_path, MAX_PATH);
  if (len == 0 || len >= MAX_PATH) {
    return;
  }

  // Register once per executable path and schema version so upgrades apply new
  // shell entries while avoiding unnecessary registry writes on every launch.
  static const wchar_t* kProgIdPath = L"Software\\Classes\\FPFileManager.Document";
  static const wchar_t* kRegistrationVersion = L"2";
  if (ReadRegistryString(HKEY_CURRENT_USER, kProgIdPath,
                         L"RegisteredExecutable") == exe_path &&
      ReadRegistryString(HKEY_CURRENT_USER, kProgIdPath,
                         L"RegistrationVersion") == kRegistrationVersion) {
    return;
  }

  std::wstring open_cmd = L"\"";
  open_cmd += exe_path;
  open_cmd += L"\" \"%1\"";

  std::wstring bg_open_cmd = L"\"";
  bg_open_cmd += exe_path;
  bg_open_cmd += L"\" \"%V\"";

  std::wstring icon_spec = L"\"";
  icon_spec += exe_path;
  icon_spec += L"\",0";

  // 1. Register ProgID: HKCU\Software\Classes\FPFileManager.Document
  SetRegistryStringValue(HKEY_CURRENT_USER, kProgIdPath, nullptr,
                         L"FP File Manager Document");
  SetRegistryStringValue(
      HKEY_CURRENT_USER,
      L"Software\\Classes\\FPFileManager.Document\\DefaultIcon", nullptr,
      icon_spec.c_str());
  SetRegistryStringValue(
      HKEY_CURRENT_USER,
      L"Software\\Classes\\FPFileManager.Document\\shell\\open\\command",
      nullptr, open_cmd.c_str());

  // 2. Register Application entry: HKCU\Software\Classes\Applications\filemanager.exe
  SetRegistryStringValue(
      HKEY_CURRENT_USER,
      L"Software\\Classes\\Applications\\filemanager.exe",
      L"FriendlyAppName", L"FP File Manager");
  SetRegistryStringValue(
      HKEY_CURRENT_USER,
      L"Software\\Classes\\Applications\\filemanager.exe\\DefaultIcon",
      nullptr, icon_spec.c_str());
  SetRegistryStringValue(
      HKEY_CURRENT_USER,
      L"Software\\Classes\\Applications\\filemanager.exe\\shell\\open\\command",
      nullptr, open_cmd.c_str());

  // 3. Register SupportedTypes, OpenWithProgids, and Windows Default Apps Capabilities
  static const wchar_t* kSupportedExtensions[] = {
      L".zip", L".apk", L".apkm", L".apks", L".obb", L".cbz", L".jar", L".tar", L".tgz", L".gz", L".7z", L".epub", L".txt", L".md", L".markdown", L".json", L".jsonc", L".json5", L".geojson", L".topojson", L".map", L".lock", L".yaml", L".yml", L".xml", L".plist", L".svg", L".rs", L".dart", L".c", L".cpp", L".cc", L".h", L".hpp", L".py", L".js", L".mjs", L".jsx", L".ts", L".tsx", L".html", L".htm", L".xhtml", L".css", L".toml", L".sh", L".bash", L".zsh", L".log", L".ini", L".cfg", L".csv", L".java", L".kt", L".go", L".swift", L".sql", L".properties", L".diff", L".patch", L".conf", L".gradle", L".dockerfile", L".jpg", L".jpeg", L".png", L".gif", L".webp", L".bmp", L".heic", L".heif", L".mp4", L".mkv", L".avi", L".mov", L".webm", L".flv", L".3gp", L".m4v", L".wmv", L".rmvb", L".rm", L".vob", L".ogv", L".m2ts", L".mts", L".f4v", L".asf", L".divx", L".mpg", L".mpeg", L".mp3", L".flac", L".wav", L".ogg", L".m4a", L".aac", L".opus", L".wma", L".amr", L".ape", L".alac", L".aiff", L".mka", L".oga", L".wv", L".mid"
  };

  HKEY supported_types_key = nullptr;
  ::RegCreateKeyExW(
      HKEY_CURRENT_USER,
      L"Software\\Classes\\Applications\\filemanager.exe\\SupportedTypes",
      0, nullptr, REG_OPTION_NON_VOLATILE, KEY_SET_VALUE, nullptr,
      &supported_types_key, nullptr);

  static const wchar_t* kCapabilitiesPath = L"Software\\FPFileManager\\Capabilities";
  static const wchar_t* kCapabilitiesAssocPath =
      L"Software\\FPFileManager\\Capabilities\\FileAssociations";
  SetRegistryStringValue(HKEY_CURRENT_USER, kCapabilitiesPath,
                         L"ApplicationName", L"FP File Manager");
  SetRegistryStringValue(
      HKEY_CURRENT_USER, kCapabilitiesPath, L"ApplicationDescription",
      L"Browse local, remote, and archive files with FP File Manager");
  SetRegistryStringValue(HKEY_CURRENT_USER,
                         L"Software\\RegisteredApplications",
                         L"FPFileManager", kCapabilitiesPath);

  for (const wchar_t* ext : kSupportedExtensions) {
    if (supported_types_key != nullptr) {
      ::RegSetValueExW(supported_types_key, ext, 0, REG_SZ,
                       reinterpret_cast<const BYTE*>(L""), sizeof(wchar_t));
    }
    std::wstring ext_progids_key = L"Software\\Classes\\";
    ext_progids_key += ext;
    ext_progids_key += L"\\OpenWithProgids";
    SetRegistryNoneValue(HKEY_CURRENT_USER, ext_progids_key.c_str(),
                         L"FPFileManager.Document");
    SetRegistryStringValue(HKEY_CURRENT_USER, kCapabilitiesAssocPath, ext,
                           L"FPFileManager.Document");
  }

  if (supported_types_key != nullptr) {
    ::RegCloseKey(supported_types_key);
  }

  // Fallback wildcard "Open with" entry for arbitrary files
  SetRegistryNoneValue(HKEY_CURRENT_USER,
                       L"Software\\Classes\\*\\OpenWithProgids",
                       L"FPFileManager.Document");

  // 4. Register folder, folder background, and drive context menu entries
  SetRegistryStringValue(
      HKEY_CURRENT_USER,
      L"Software\\Classes\\Directory\\shell\\FPFileManager", nullptr,
      L"Open with FP File Manager");
  SetRegistryStringValue(
      HKEY_CURRENT_USER,
      L"Software\\Classes\\Directory\\shell\\FPFileManager", L"Icon",
      icon_spec.c_str());
  SetRegistryStringValue(
      HKEY_CURRENT_USER,
      L"Software\\Classes\\Directory\\shell\\FPFileManager\\command",
      nullptr, open_cmd.c_str());

  SetRegistryStringValue(
      HKEY_CURRENT_USER,
      L"Software\\Classes\\Directory\\Background\\shell\\FPFileManager",
      nullptr, L"Open with FP File Manager");
  SetRegistryStringValue(
      HKEY_CURRENT_USER,
      L"Software\\Classes\\Directory\\Background\\shell\\FPFileManager",
      L"Icon", icon_spec.c_str());
  SetRegistryStringValue(
      HKEY_CURRENT_USER,
      L"Software\\Classes\\Directory\\Background\\shell\\FPFileManager\\command",
      nullptr, bg_open_cmd.c_str());

  SetRegistryStringValue(
      HKEY_CURRENT_USER,
      L"Software\\Classes\\Drive\\shell\\FPFileManager", nullptr,
      L"Open with FP File Manager");
  SetRegistryStringValue(
      HKEY_CURRENT_USER,
      L"Software\\Classes\\Drive\\shell\\FPFileManager", L"Icon",
      icon_spec.c_str());
  SetRegistryStringValue(
      HKEY_CURRENT_USER,
      L"Software\\Classes\\Drive\\shell\\FPFileManager\\command",
      nullptr, open_cmd.c_str());

  // 5. Remember which executable and schema version the associations point at.
  SetRegistryStringValue(HKEY_CURRENT_USER, kProgIdPath,
                         L"RegisteredExecutable", exe_path);
  SetRegistryStringValue(HKEY_CURRENT_USER, kProgIdPath,
                         L"RegistrationVersion", kRegistrationVersion);
}
