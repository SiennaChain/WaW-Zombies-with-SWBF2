// wawbf_launcher: the one thing a player runs.
//
// It finds both games through Steam, checks that they are the builds the mod
// was made for, puts the mod's files into them if it was given any (a folder
// "files" beside it: that is what a release is), starts Battlefront II with
// no window showing, waits until its bridge says the player's character is
// standing in the arena, and then starts World at War straight into the map
// with that map's build of the mod. With one map installed there is nothing
// to pick and it does all that at once; with more, it is a list of them.
//
// There is no going through World at War's own menus, before or after: its
// bridge closes the game if it ever comes to the main menu ([waw]
// quit_at_menu), so a different map means closing the game and running this
// again. When World at War has gone, Battlefront II is closed too.
//
// It is also what makes the mod do anything at all. Both bridges are loaded
// by their games every time those start, and do nothing unless they find the
// object this holds for as long as it runs (common/session.h). Started from
// Steam, either game is the game it always was.
//
// The list works from the keyboard (up, down, Enter, Esc) and from a
// controller (d-pad, A, B).
//
// It is also where the video settings are that World at War only offers at
// its main menu (fullscreen, the video mode, anti-aliasing and so on): the
// Settings button, which while a game is still on its way calls that off
// first. They are kept, with everything else that can be changed, in
// wawbf_launcher.ini beside the exe; see
// tools/launcher/wawbf_launcher.ini.example.
//
//   wawbf_launcher /settings     only the settings window: nothing is started
//   wawbf_launcher /uninstall    takes the mod's files back out of both games
//                                (/quiet as well: without saying so in a box)
#include <windows.h>

#include <shellapi.h>
#include <tlhelp32.h>

#include <algorithm>
#include <atomic>
#include <cstring>
#include <set>
#include <string>
#include <thread>
#include <vector>

#include "config.h"
#include "log.h"
#include "pad.h"
#include "session.h"
#include "wawbf_protocol.h"

using namespace wawbf;

namespace {

// The maps, in the order the game brought them out. The mod World at War is
// started with is "swbf2_" and the map's name: waw/mod/build.ps1 -Map builds
// and installs one for each, because each map has its own copy of the game's
// zombie scripts and a mod replaces a script for every map at once.
struct Map {
  const wchar_t* title;
  const wchar_t* name;
};
const Map kMaps[] = {
    {L"Nacht der Untoten", L"nazi_zombie_prototype"},
    {L"Verr\u00FCckt", L"nazi_zombie_asylum"},  // (written so: the file has no letters outside ASCII for a compiler to misread)
    {L"Shi No Numa", L"nazi_zombie_sumpf"},
    {L"Der Riese", L"nazi_zombie_factory"},
};
const int kMapCount = static_cast<int>(sizeof(kMaps) / sizeof(kMaps[0]));

const wchar_t* const kTitle = L"Zombies with Battlefront II";
const wchar_t* const kWawApp = L"10090";  // Steam's numbers for the two games
const wchar_t* const kBfApp = L"6060";
// Where Steam puts each, in whichever of its libraries: the folder with the exe.
const wchar_t* const kWawFolder = L"steamapps\\common\\Call of Duty World at War";
const wchar_t* const kBfFolder = L"steamapps\\common\\Star Wars Battlefront II Classic\\GameData";

// What was put where, written into each place files were installed to, one
// path a line; and what is added to the name of a file of somebody else's
// that was in the way (another mod's d3d9.dll), which uninstalling puts back.
const wchar_t* const kManifest = L"wawbf_installed.txt";
const wchar_t* const kSetAside = L".before-wawbf";

const UINT kSay = WM_APP + 1;     // lParam: a new std::wstring for the line at the bottom
const UINT kFailed = WM_APP + 2;  // the same, and the buttons come back
const UINT kStarted = WM_APP + 3; // World at War is on its way: the window goes
const UINT kOver = WM_APP + 4;    // World at War has gone: so does this
const UINT kBegin = WM_APP + 5;   // wParam: the map to start without being asked
const UINT kStopped = WM_APP + 6; // the start was called off (Settings was pressed): the buttons come back
const int kFirstButton = 100;
const int kSettingsButton = 200;
// The settings window's own: a box to tick, five lists, and two buttons.
const int kFullscreenBox = 300, kModeList = 301, kRefreshList = 302, kSmoothList = 303, kSyncList = 304, kDetailList = 305, kSave = 306, kLeave = 307;
const UINT_PTR kPadTimer = 1;

struct Settings {
  std::wstring map;         // the map to start at once; empty: the only one installed, or ask
  bool fullscreen = true;
  int width = 0, height = 0;  // World at War's picture; 0: the desktop's (a window: 1280 x 720)
  int refresh = 0;          // how often a second the screen is redrawn, fullscreen; 0: as World at War has it
  int smoothing = 0;        // anti-aliasing: 1 none, 2 or 4 samples; 0: as World at War has it
  int sync = -1;            // wait for the screen before each frame: 0 no, 1 yes; -1: as World at War has it
  bool wawVideo = true;     // tell World at War fullscreen, width and height
  int bfHeight = 1080;      // the most lines Battlefront II's picture is drawn with
  std::wstring bfArgs;      // more for Battlefront II's command line
  std::wstring wawArgs;     // more for World at War's, before the map
  bool cheats = false;      // +devmap in place of +map
  bool closeBf = true;      // close Battlefront II when World at War has gone
  int bfWaitSeconds = 120;  // how long Battlefront II is given to have a character in the arena
  std::wstring wawFolder, bfFolder;  // where the games are; empty: ask Steam
};

HWND g_window = nullptr;
HWND g_buttons[kMapCount] = {};
HWND g_status = nullptr;
HWND g_settingsWindow = nullptr;  // while it is open
bool g_have[kMapCount] = {};
int g_atOnce = -1;      // the map that is started without being asked, if there is one
Settings g_settings;
std::wstring g_beside;  // the folder this exe is in, with its backslash
std::atomic<bool> g_busy{false};
std::atomic<bool> g_callOff{false};  // Settings was pressed while a game was on its way
bool g_onlySettings = false;         // started with /settings: the settings window and nothing else
int g_dpi = 96;
HFONT g_big = nullptr, g_plain = nullptr;

// Sizes are for a screen at 96 dots an inch and grow with it.
int Px(int at96) { return MulDiv(at96, g_dpi, 96); }

std::wstring Wide(const std::string& text) {
  if (text.empty()) return {};
  std::wstring wide(MultiByteToWideChar(CP_UTF8, 0, text.data(), static_cast<int>(text.size()), nullptr, 0), L'\0');
  MultiByteToWideChar(CP_UTF8, 0, text.data(), static_cast<int>(text.size()), &wide[0], static_cast<int>(wide.size()));
  return wide;
}

std::string Narrow(const std::wstring& text) {
  if (text.empty()) return {};
  std::string narrow(WideCharToMultiByte(CP_UTF8, 0, text.data(), static_cast<int>(text.size()), nullptr, 0, nullptr, nullptr), '\0');
  WideCharToMultiByte(CP_UTF8, 0, text.data(), static_cast<int>(text.size()), &narrow[0], static_cast<int>(narrow.size()), nullptr, nullptr);
  return narrow;
}

std::wstring Folder(const wchar_t* variable) {
  wchar_t buffer[MAX_PATH] = {};
  const DWORD length = GetEnvironmentVariableW(variable, buffer, MAX_PATH);
  return length && length < MAX_PATH ? std::wstring(buffer) : std::wstring();
}

bool Exists(const std::wstring& path) { return GetFileAttributesW(path.c_str()) != INVALID_FILE_ATTRIBUTES; }

std::wstring ModOf(const Map& map) { return std::wstring(L"swbf2_") + map.name; }

// Where World at War keeps a player's mods and its own odds and ends.
std::wstring WawData() { return Folder(L"LOCALAPPDATA") + L"\\Activision\\CoDWaW"; }

DWORD Running(const wchar_t* exe) {
  const HANDLE snapshot = CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);
  if (snapshot == INVALID_HANDLE_VALUE) return 0;
  PROCESSENTRY32W entry{};
  entry.dwSize = sizeof(entry);
  DWORD found = 0;
  for (BOOL more = Process32FirstW(snapshot, &entry); more && !found; more = Process32NextW(snapshot, &entry)) {
    if (lstrcmpiW(entry.szExeFile, exe) == 0) found = entry.th32ProcessID;
  }
  CloseHandle(snapshot);
  return found;
}

std::string ReadAll(const std::wstring& path) {
  std::string text;
  const HANDLE file = CreateFileW(path.c_str(), GENERIC_READ, FILE_SHARE_READ | FILE_SHARE_WRITE, nullptr, OPEN_EXISTING, 0, nullptr);
  if (file == INVALID_HANDLE_VALUE) return text;
  char buffer[4096];
  DWORD got = 0;
  while (ReadFile(file, buffer, sizeof(buffer), &got, nullptr) && got) text.append(buffer, got);
  CloseHandle(file);
  return text;
}

std::wstring IniPath() { return g_beside + L"wawbf_launcher.ini"; }

void LoadSettings() {
  const Config config(IniPath());
  Settings s;
  s.map = Wide(config.GetString("launcher", "map", ""));
  s.fullscreen = config.GetInt("launcher", "fullscreen", 1) != 0;
  s.width = config.GetInt("launcher", "width", 0);
  s.height = config.GetInt("launcher", "height", 0);
  s.refresh = config.GetInt("launcher", "refresh", 0);
  s.smoothing = config.GetInt("launcher", "antialiasing", 0);
  s.sync = config.GetInt("launcher", "sync_every_frame", -1);
  s.wawVideo = config.GetInt("launcher", "waw_video", 1) != 0;
  s.bfHeight = std::max(240, config.GetInt("launcher", "swbf2_height", 1080));
  s.bfArgs = Wide(config.GetString("launcher", "swbf2_args", ""));
  s.wawArgs = Wide(config.GetString("launcher", "waw_args", ""));
  s.cheats = config.GetInt("launcher", "cheats", 0) != 0;
  s.closeBf = config.GetInt("launcher", "close_swbf2", 1) != 0;
  s.bfWaitSeconds = config.GetInt("launcher", "swbf2_wait_s", 120);
  s.wawFolder = Wide(config.GetString("launcher", "waw_folder", ""));
  s.bfFolder = Wide(config.GetString("launcher", "swbf2_folder", ""));
  g_settings = s;
}

// --- finding the games -------------------------------------------------------

std::wstring SteamValue(const wchar_t* name) {
  wchar_t path[MAX_PATH] = {};
  DWORD size = sizeof(path);
  if (RegGetValueW(HKEY_CURRENT_USER, L"Software\\Valve\\Steam", name, RRF_RT_REG_SZ, nullptr, path, &size) != ERROR_SUCCESS) return {};
  std::wstring value(path);
  std::replace(value.begin(), value.end(), L'/', L'\\');
  return value;
}

// Steam's own folder and every other library it has been given: the lines
//   "path"    "E:\\SteamLibrary"
// of its list of them.
std::vector<std::wstring> SteamLibraries() {
  std::vector<std::wstring> libraries;
  const std::wstring steam = SteamValue(L"SteamPath");
  if (steam.empty()) return libraries;
  libraries.push_back(steam);
  const std::string list = ReadAll(steam + L"\\steamapps\\libraryfolders.vdf");
  for (size_t at = 0; (at = list.find("\"path\"", at)) != std::string::npos;) {
    at += 6;
    const size_t open = list.find('"', at), end = list.find('\n', at);
    if (open == std::string::npos || (end != std::string::npos && open > end)) continue;
    std::string path;
    for (size_t i = open + 1; i < list.size() && list[i] != '"'; ++i) {
      if (list[i] == '\\' && i + 1 < list.size()) ++i;  // written "\\" for each one
      path += list[i];
    }
    if (!path.empty()) libraries.push_back(Wide(path));
  }
  return libraries;
}

// The folder a game's exe is in: the one wawbf_launcher.ini names, or the one
// under whichever Steam library has it. Empty if there is none.
std::wstring GameFolder(const std::wstring& named, const wchar_t* under, const wchar_t* exe) {
  if (!named.empty()) return Exists(named + L"\\" + exe) ? named : std::wstring();
  for (const std::wstring& library : SteamLibraries()) {
    const std::wstring folder = library + L"\\" + under;
    if (Exists(folder + L"\\" + exe)) return folder;
  }
  return {};
}

// --- putting the mod's files in, and taking them out ------------------------

void List(const std::wstring& root, const std::wstring& under, std::vector<std::wstring>* files) {
  WIN32_FIND_DATAW found{};
  const HANDLE search = FindFirstFileW((root + L"\\" + under + L"*").c_str(), &found);
  if (search == INVALID_HANDLE_VALUE) return;
  do {
    const std::wstring name = found.cFileName;
    if (name == L"." || name == L"..") continue;
    if (found.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) {
      List(root, under + name + L"\\", files);
    } else {
      files->push_back(under + name);
    }
  } while (FindNextFileW(search, &found));
  FindClose(search);
}

std::set<std::wstring> Manifest(const std::wstring& root) {
  std::set<std::wstring> lines;
  const std::wstring text = Wide(ReadAll(root + L"\\" + kManifest));
  for (size_t at = 0; at < text.size();) {
    size_t end = text.find(L'\n', at);
    if (end == std::wstring::npos) end = text.size();
    std::wstring line = text.substr(at, end - at);
    while (!line.empty() && (line.back() == L'\r' || line.back() == L' ')) line.pop_back();
    if (!line.empty()) lines.insert(line);
    at = end + 1;
  }
  return lines;
}

bool Same(const std::wstring& a, const std::wstring& b) {
  WIN32_FILE_ATTRIBUTE_DATA one{}, other{};
  return GetFileAttributesExW(a.c_str(), GetFileExInfoStandard, &one) && GetFileAttributesExW(b.c_str(), GetFileExInfoStandard, &other) &&
         one.nFileSizeLow == other.nFileSizeLow && one.nFileSizeHigh == other.nFileSizeHigh &&
         CompareFileTime(&one.ftLastWriteTime, &other.ftLastWriteTime) == 0;
}

void MakeFoldersFor(const std::wstring& file) {
  for (size_t at = file.find(L'\\', 3); at != std::wstring::npos; at = file.find(L'\\', at + 1)) {
    CreateDirectoryW(file.substr(0, at).c_str(), nullptr);
  }
}

// Everything under `from` goes to the same place under `to`. A file already
// there that this did not put there, in `to` itself, is somebody else's (a
// d3d9.dll of another mod's, most likely): it is set aside under another
// name, once, and uninstalling brings it back. Empty if all went well,
// otherwise what did not.
std::wstring Install(const std::wstring& from, const std::wstring& to) {
  std::vector<std::wstring> files;
  List(from, L"", &files);
  if (files.empty()) return {};
  std::set<std::wstring> ours = Manifest(to);
  int copied = 0;
  for (const std::wstring& file : files) {
    const std::wstring source = from + L"\\" + file, target = to + L"\\" + file;
    MakeFoldersFor(target);
    const bool known = ours.count(file) != 0;
    if (!known && file.find(L'\\') == std::wstring::npos && Exists(target) && !Exists(target + kSetAside)) {
      MoveFileW(target.c_str(), (target + kSetAside).c_str());
      log::Info("install: %s was there already and is now %s%s", Narrow(target).c_str(), Narrow(file).c_str(), Narrow(kSetAside).c_str());
    }
    if (!Same(source, target)) {
      if (!CopyFileW(source.c_str(), target.c_str(), FALSE)) {
        return L"Could not write " + target + L" (error " + std::to_wstring(GetLastError()) + L"). Is the game running, or the folder read-only?";
      }
      ++copied;
    }
    ours.insert(file);
  }
  std::string list;
  for (const std::wstring& line : ours) list += Narrow(line) + "\r\n";
  const HANDLE manifest = CreateFileW((to + L"\\" + kManifest).c_str(), GENERIC_WRITE, 0, nullptr, CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
  if (manifest != INVALID_HANDLE_VALUE) {
    DWORD wrote = 0;
    WriteFile(manifest, list.data(), static_cast<DWORD>(list.size()), &wrote, nullptr);
    CloseHandle(manifest);
  }
  log::Info("install: %d of %d files written to %s", copied, static_cast<int>(files.size()), Narrow(to).c_str());
  return {};
}

// Takes out of `to` everything Install put there, puts back whatever was set
// aside, and removes the folders that leaves empty. How many files went.
int Uninstall(const std::wstring& to, const std::vector<std::wstring>& also) {
  std::set<std::wstring> ours = Manifest(to);
  if (ours.empty()) return 0;
  for (const std::wstring& more : also) ours.insert(more);  // what the bridges themselves leave: logs and the like
  int gone = 0;
  for (const std::wstring& file : ours) {
    const std::wstring target = to + L"\\" + file;
    if (DeleteFileW(target.c_str())) ++gone;
    if (Exists(target + kSetAside)) MoveFileW((target + kSetAside).c_str(), target.c_str());
    for (size_t at = target.rfind(L'\\'); at != std::wstring::npos && at > to.size(); at = target.rfind(L'\\', at - 1)) {
      if (!RemoveDirectoryW(target.substr(0, at).c_str())) break;  // not empty: and so nor is anything above it
    }
  }
  DeleteFileW((to + L"\\" + kManifest).c_str());
  return gone;
}

// --- one game of it ----------------------------------------------------------

bool Start(const std::wstring& steam, const std::wstring& arguments) {
  log::Info("steam %s", Narrow(arguments).c_str());
  return reinterpret_cast<INT_PTR>(ShellExecuteW(nullptr, L"open", steam.c_str(), arguments.c_str(), nullptr, SW_SHOWNORMAL)) > 32;
}

void Say(UINT message, const std::wstring& text) {
  log::Info("%s", Narrow(text).c_str());
  PostMessageW(g_window, message, 0, reinterpret_cast<LPARAM>(new std::wstring(text)));
}

// Battlefront II's bridge is alive and says which character is in play: the
// mission has loaded and the player has been put into the arena. `why` is
// what to tell the player if this is asked for the last time.
bool BfReady(std::wstring* why) {
  *why = L"Battlefront II did not start, or started without the mod. Run this again; if it happens every time, start Battlefront II once from "
         L"Steam to see that it runs.";
  const HANDLE handle = OpenFileMappingW(FILE_MAP_READ, FALSE, kMappingName);
  if (!handle) return false;
  bool ready = false;
  if (const auto* block = static_cast<const SharedBlock*>(MapViewOfFile(handle, FILE_MAP_READ, 0, 0, kMappingSize))) {
    const PeerInfo& bf = block->header.peers[kSideBf];
    BfPlayerState state{};
    if (block->header.magic.load() != kMagic || block->header.version != kVersion) {
      *why = L"The mod's files in the two games are of a different version from this launcher. Install the ones that came with it.";
    } else if (!HeartbeatAlive(bf.heartbeatMs.load(), bf.beats.load(), GetTickCount())) {
      // (the first words stand)
    } else if (!block->bf.read(state) || state.kit == 0) {
      *why = L"Battlefront II is running but did not get as far as its arena. Start it once from Steam: it may be waiting at a question "
             L"(a first profile to make, say) that it cannot show while it is hidden.";
    } else {
      ready = true;
    }
    UnmapViewOfFile(block);
  }
  CloseHandle(handle);
  return ready;
}

// (Its window may never have been shown: [swbf2] hidden. So not only windows
// that are showing; but only ones with a name, which leaves out the unseen
// ones Windows makes for a program's own housekeeping.)
BOOL CALLBACK CloseIfOf(HWND window, LPARAM pid) {
  DWORD owner = 0;
  GetWindowThreadProcessId(window, &owner);
  if (owner == static_cast<DWORD>(pid) && !GetWindow(window, GW_OWNER) && GetWindowTextLengthW(window) > 0) PostMessageW(window, WM_CLOSE, 0, 0);
  return TRUE;
}

void CloseBf(int patience = 60) {
  const DWORD bf = Running(session::kBf.exe);
  if (!bf) return;
  EnumWindows(CloseIfOf, static_cast<LPARAM>(bf));
  for (int waited = 0; waited < patience && Running(session::kBf.exe); ++waited) Sleep(250);
  if (Running(session::kBf.exe) != bf) return;
  // Asked and still there after `patience` quarters of a second (a quarter of
  // a minute, unless told less): it has no window to be seen or closed by
  // hand, so it is not left behind.
  if (const HANDLE process = OpenProcess(PROCESS_TERMINATE, FALSE, bf)) {
    TerminateProcess(process, 0);
    CloseHandle(process);
    log::Info("Battlefront II did not close when asked and was stopped");
  }
}

// The player's own name, back in World at War's settings.
//
// While they play, the player is called after their character (World at
// War's scoreboard shows it), and the game writes any change of name into the
// player's settings as it happens. Its bridge puts the name back when the
// game is quit from its menu; a game that ends any other way would leave the
// player called Darth Vader for good. So the bridge keeps the name they had
// in a file for as long as they go by another, and if the game has gone and
// that file is still there, the name in it goes back into the settings here.
void GiveNameBack(const std::wstring& wawDir) {
  const std::wstring kept = wawDir + L"\\wawbf_name.txt";
  std::string own = ReadAll(kept);
  own.erase(std::remove_if(own.begin(), own.end(), [](unsigned char c) { return c < 32 || c == '"' || c == ';' || c == '\\'; }), own.end());
  if (own.empty() || Running(session::kWaw.exe)) return;
  std::string profile = ReadAll(WawData() + L"\\players\\profiles\\active.txt");
  while (!profile.empty() && static_cast<unsigned char>(profile.back()) <= 32) profile.pop_back();
  std::wstring folder(MultiByteToWideChar(CP_ACP, 0, profile.data(), static_cast<int>(profile.size()), nullptr, 0), L'\0');
  if (!folder.empty()) MultiByteToWideChar(CP_ACP, 0, profile.data(), static_cast<int>(profile.size()), &folder[0], static_cast<int>(folder.size()));
  const std::wstring config = WawData() + L"\\players\\profiles\\" + folder + L"\\config.cfg";
  std::string text = ReadAll(config);
  const char* const line = "seta name \"";
  size_t at = text.find(line);
  while (at != std::string::npos && at != 0 && text[at - 1] != '\n') at = text.find(line, at + 1);
  const size_t open = at == std::string::npos ? at : at + std::strlen(line);
  const size_t close = open == std::string::npos ? open : text.find('"', open);
  if (close != std::string::npos && text.compare(open, close - open, own) != 0) {
    const std::string was = text.substr(open, close - open);
    text.replace(open, close - open, own);
    const HANDLE file = CreateFileW(config.c_str(), GENERIC_WRITE, 0, nullptr, CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
    if (file != INVALID_HANDLE_VALUE) {
      DWORD wrote = 0;
      WriteFile(file, text.data(), static_cast<DWORD>(text.size()), &wrote, nullptr);
      CloseHandle(file);
      log::Info("name: World at War was left calling the player %s; its settings say %s again", was.c_str(), own.c_str());
    }
  }
  DeleteFileW(kept.c_str());
}

// Battlefront II's picture: the shape of World at War's, no more lines than
// asked for, and no bigger than the two bridges can pass between them.
void BfPicture(int wawWidth, int wawHeight, int mostLines, int* width, int* height) {
  int lines = std::min({wawHeight, mostLines, static_cast<int>(kFrameMaxHeight)});
  int across = static_cast<int>(static_cast<double>(lines) * wawWidth / wawHeight + 0.5);
  if (across > static_cast<int>(kFrameMaxWidth)) {
    across = static_cast<int>(kFrameMaxWidth);
    lines = static_cast<int>(static_cast<double>(across) * wawHeight / wawWidth + 0.5);
  }
  *width = across & ~1;
  *height = lines & ~1;
}

// Everything from the pick to World at War having gone again. Its own thread:
// most of it is waiting.
void Play(int which) {
  const Map& map = kMaps[which];
  const Settings s = g_settings;
  const std::wstring steam = SteamValue(L"SteamExe");
  if (steam.empty()) return Say(kFailed, L"Steam was not found on this PC. Both games have to be the Steam ones.");

  const std::wstring wawDir = GameFolder(s.wawFolder, kWawFolder, session::kWaw.exe);
  const std::wstring bfDir = GameFolder(s.bfFolder, kBfFolder, session::kBf.exe);
  if (wawDir.empty()) return Say(kFailed, L"Call of Duty: World at War was not found in Steam. Install it there (or name its folder in wawbf_launcher.ini: waw_folder).");
  if (bfDir.empty()) return Say(kFailed, L"Star Wars Battlefront II (the 2005 one, \"Classic\" on Steam) was not found in Steam. Install it there (or name its GameData folder in wawbf_launcher.ini: swbf2_folder).");
  log::Info("World at War: %s", Narrow(wawDir).c_str());
  log::Info("Battlefront II: %s", Narrow(bfDir).c_str());

  session::ExeId id;
  if (!session::OfFile(wawDir + L"\\" + session::kWaw.exe, &id) || id != session::kWaw.id) {
    log::Info("CoDWaW.exe is 0x%08X, 0x%08X", id.stamp, id.imageSize);
    return Say(kFailed, L"This copy of World at War is not the version the mod was made for (the current one on Steam), so nothing was started. Let Steam update it or check its files.");
  }
  if (!session::OfFile(bfDir + L"\\" + session::kBf.exe, &id) || id != session::kBf.id) {
    log::Info("BattlefrontII.exe is 0x%08X, 0x%08X", id.stamp, id.imageSize);
    return Say(kFailed, L"This copy of Battlefront II is not the version the mod was made for (the current one on Steam), so nothing was started. Let Steam update it or check its files.");
  }
  if (Running(session::kWaw.exe)) return Say(kFailed, L"World at War is already running. Close it first.");
  GiveNameBack(wawDir);  // from a game that ended with nobody here to do it

  // Both games ask a first-time player something before anything else, and
  // Battlefront II would be asking it with no window.
  WIN32_FIND_DATAW found{};
  const HANDLE profile = FindFirstFileW((bfDir + L"\\SaveGames\\*.profile").c_str(), &found);
  if (profile == INVALID_HANDLE_VALUE) {
    return Say(kFailed, L"Battlefront II has no player profile yet. Start it once from Steam, make a profile, quit, and run this again.");
  }
  FindClose(profile);
  if (!Exists(WawData() + L"\\players\\profiles\\active.txt")) {
    return Say(kFailed, L"World at War has not been played on this PC yet. Start it once from Steam (single player), make a profile, quit, and run this again.");
  }

  const bool bfWasRunning = Running(session::kBf.exe) != 0;
  const std::wstring files = g_beside + L"files";
  if (Exists(files)) {
    Say(kSay, L"Putting the mod's files into both games...");
    std::wstring wrong = Install(files + L"\\waw", wawDir);
    if (wrong.empty() && !bfWasRunning) wrong = Install(files + L"\\swbf2", bfDir);
    if (wrong.empty()) wrong = Install(files + L"\\mods", WawData() + L"\\mods");
    if (!wrong.empty()) return Say(kFailed, wrong);
  }
  if (!Exists(WawData() + L"\\mods\\" + ModOf(map) + L"\\mod.ff")) return Say(kFailed, std::wstring(L"The mod's files for ") + map.title + L" are not installed.");
  if (!Exists(wawDir + L"\\d3d9.dll") || !Exists(bfDir + L"\\d3d9.dll")) {
    return Say(kFailed, L"The mod's d3d9.dll is missing from one of the games. Unpack the whole download again and run the launcher from there.");
  }

  // The pictures. World at War's is the screen's unless told otherwise, and
  // Battlefront II's is the same shape.
  int width = s.width, height = s.height;
  if (width <= 0 || height <= 0) {
    width = s.fullscreen ? GetSystemMetrics(SM_CXSCREEN) : 1280;
    height = s.fullscreen ? GetSystemMetrics(SM_CYSCREEN) : 720;
  }
  int bfWidth = 0, bfHeight = 0;
  BfPicture(width, height, s.bfHeight, &bfWidth, &bfHeight);

  if (!bfWasRunning) {
    Say(kSay, L"Starting Battlefront II...");
    std::wstring arguments = std::wstring(L"-applaunch ") + kBfApp + L" /win /nointro /resolution " + std::to_wstring(bfWidth) + L" " + std::to_wstring(bfHeight);
    if (!s.bfArgs.empty()) arguments += L" " + s.bfArgs;
    if (!Start(steam, arguments)) return Say(kFailed, L"Steam would not start Battlefront II.");
  }
  Say(kSay, L"Battlefront II is loading (it has no window: that is as it should be)...");
  // Settings pressed meanwhile: the start is called off. Battlefront II is
  // closed again if it was started for this (waited for first, if Steam has
  // not got as far as starting it: it has no window to be found by later).
  // (And with Battlefront II gone, so is the file its bridge made to have its
  // add-on go straight into the arena. The bridge takes it away itself the
  // next time the game is started by anything else; this is for a bridge
  // that is no longer there to.)
  const auto bfGone = [&](int patience) {
    CloseBf(patience);
    if (!Running(session::kBf.exe)) DeleteFileW((bfDir + L"\\addon\\WAW\\wawbf_start.txt").c_str());
  };
  const auto calledOff = [&] {
    if (!g_callOff.load()) return false;
    if (!bfWasRunning) {
      for (int waited = 0; waited < 40 && !Running(session::kBf.exe); ++waited) Sleep(250);
      bfGone(4);  // still loading, most likely, and deaf to being asked: not long is waited
    }
    log::Info("the start was called off");
    PostMessageW(g_window, kStopped, 0, 0);
    return true;
  };
  std::wstring why;
  for (int waited = 0; !BfReady(&why); ++waited) {
    if (calledOff()) return;
    // One that was running already and is not ours is not going to become so.
    if (bfWasRunning && waited >= 20) return Say(kFailed, L"Battlefront II was already running, and not started from here. Close it and run this again.");
    if (waited >= s.bfWaitSeconds * 4) {
      bfGone(60);
      return Say(kFailed, why);
    }
    Sleep(250);
  }
  if (calledOff()) return;

  // A World at War that did not end properly asks, the next time, whether to
  // start in safe mode, in a box that has to be clicked. What makes it ask is
  // a file it leaves while it runs; with no World at War running, that file
  // is left over, and goes.
  DeleteFileW((WawData() + L"\\__CoDWaW").c_str());

  Say(kSay, std::wstring(L"Starting World at War: ") + map.title + L"...");
  std::wstring arguments = std::wstring(L"-applaunch ") + kWawApp + L" +set fs_game mods/" + ModOf(map) +
                           L" +set com_introPlayed 1 +set com_startupIntroPlayed 1";  // or its opening films play over the map, and then its main menu
  // What World at War only lets a player change at its main menu, which is
  // never seen here: so it is told on the way in. (It remembers all of it, as
  // it would anything set in its own options.)
  if (s.wawVideo) {
    arguments += std::wstring(L" +set r_fullscreen ") + (s.fullscreen ? L"1" : L"0") + L" +set r_mode " + std::to_wstring(width) + L"x" + std::to_wstring(height);
  }
  if (s.refresh > 0) arguments += L" +set r_displayRefresh \"" + std::to_wstring(s.refresh) + L" Hz\"";
  if (s.smoothing == 1 || s.smoothing == 2 || s.smoothing == 4) arguments += L" +set r_aasamples " + std::to_wstring(s.smoothing);
  if (s.sync == 0 || s.sync == 1) arguments += L" +set r_vsync " + std::to_wstring(s.sync);
  if (!s.wawArgs.empty()) arguments += L" " + s.wawArgs;
  arguments += std::wstring(s.cheats ? L" +devmap " : L" +map ") + map.name;
  if (!Start(steam, arguments)) return Say(kFailed, L"Steam would not start World at War.");

  // World at War has to come up in front: started behind another window with
  // the whole screen asked for, it never gets the screen, and stops answering
  // (seen: it was started while its player was typing somewhere else). Any
  // program is let take the front from here, which is as much as Windows
  // allows this one to arrange, and it only counts while this is itself the
  // window in front; then, for its first seconds, the game's window is asked
  // forward whenever it is found behind.
  AllowSetForegroundWindow(ASFW_ANY);
  for (int waited = 0; !Running(session::kWaw.exe); ++waited) {
    if (waited >= 120 * 4) {
      if (s.closeBf) bfGone(60);
      return Say(kFailed, L"World at War did not start.");
    }
    Sleep(250);
  }
  for (int waited = 0; waited < 32; ++waited) {
    const DWORD waw = Running(session::kWaw.exe);
    if (!waw) break;
    HWND found = nullptr;
    struct Look {
      DWORD pid;
      HWND* found;
    } look = {waw, &found};
    EnumWindows(
        [](HWND window, LPARAM arg) -> BOOL {
          const auto* look = reinterpret_cast<const Look*>(arg);
          DWORD owner = 0;
          GetWindowThreadProcessId(window, &owner);
          if (owner != look->pid || !IsWindowVisible(window) || GetWindow(window, GW_OWNER)) return TRUE;
          *look->found = window;
          return FALSE;
        },
        reinterpret_cast<LPARAM>(&look));
    if (found && GetForegroundWindow() != found) SetForegroundWindow(found);
    Sleep(250);
  }
  PostMessageW(g_window, kStarted, 0, 0);

  // Steam starts the game, which may start itself again: gone means gone for
  // a few seconds together.
  for (int gone = 0; gone < 16;) {
    Sleep(250);
    gone = Running(session::kWaw.exe) ? 0 : gone + 1;
  }
  log::Info("World at War has gone");
  GiveNameBack(wawDir);
  if (s.closeBf) bfGone(60);
  PostMessageW(g_window, kOver, 0, 0);
}

void Pick(int which) {
  if (which < 0 || which >= kMapCount || !g_have[which] || g_busy.exchange(true)) return;
  g_callOff.store(false);
  for (HWND button : g_buttons) {
    if (button) EnableWindow(button, FALSE);
  }
  std::thread(Play, which).detach();
}

// --- the settings ------------------------------------------------------------
//
// World at War has two Graphics screens. The one at its main menu has every
// setting on it. The one a player reaches from a map (Esc, Options) is a
// different screen under the same name, on which the video mode, the refresh
// rate, the aspect ratio, anti-aliasing and "sync every frame" are words and
// not controls: those can only be changed at the main menu, and the main
// menu's screen is not even loaded while a map is. With this launcher there
// is no main menu, so they are set here instead, and World at War is told
// them as it starts. Everything else is in its own Options as it always was.

struct Mode {
  int width, height;
};
std::vector<Mode> g_modes;  // the sizes the screen can show, largest first
std::vector<int> g_rates;   // and how many times a second it can show them

void ListModes() {
  g_modes.clear();
  g_rates.clear();
  DEVMODEW mode{};
  mode.dmSize = sizeof(mode);
  for (DWORD i = 0; EnumDisplaySettingsW(nullptr, i, &mode); ++i) {
    if (mode.dmBitsPerPel < 32 || mode.dmPelsWidth < 800 || mode.dmPelsHeight < 600) continue;
    const int width = static_cast<int>(mode.dmPelsWidth), height = static_cast<int>(mode.dmPelsHeight), rate = static_cast<int>(mode.dmDisplayFrequency);
    if (std::none_of(g_modes.begin(), g_modes.end(), [&](const Mode& m) { return m.width == width && m.height == height; })) g_modes.push_back({width, height});
    if (rate > 1 && std::find(g_rates.begin(), g_rates.end(), rate) == g_rates.end()) g_rates.push_back(rate);
  }
  std::sort(g_modes.begin(), g_modes.end(), [](const Mode& a, const Mode& b) { return a.width != b.width ? a.width > b.width : a.height > b.height; });
  std::sort(g_rates.begin(), g_rates.end());
}

HWND Made(HWND parent, const wchar_t* kind, const wchar_t* text, DWORD style, int id, int x, int y, int width, int height) {
  const HWND made = CreateWindowW(kind, text, WS_CHILD | WS_VISIBLE | style, Px(x), Px(y), Px(width), Px(height), parent,
                                  reinterpret_cast<HMENU>(static_cast<INT_PTR>(id)), GetModuleHandleW(nullptr), nullptr);
  SendMessageW(made, WM_SETFONT, reinterpret_cast<WPARAM>(g_plain), TRUE);
  return made;
}

// A list to pick one thing from; each thing has a number, which is what is kept.
HWND List(HWND parent, const wchar_t* label, int id, int row) {
  Made(parent, L"STATIC", label, SS_RIGHT, 0, 16, 24 + row * 40, 168, 22);
  return Made(parent, L"COMBOBOX", L"", CBS_DROPDOWNLIST | WS_VSCROLL | WS_TABSTOP, id, 196, 20 + row * 40, 248, 320);
}
void Offer(HWND list, const std::wstring& text, int number, int chosen) {
  const LRESULT at = SendMessageW(list, CB_ADDSTRING, 0, reinterpret_cast<LPARAM>(text.c_str()));
  SendMessageW(list, CB_SETITEMDATA, at, number);
  if (number == chosen || SendMessageW(list, CB_GETCURSEL, 0, 0) == CB_ERR) SendMessageW(list, CB_SETCURSEL, at, 0);
}
int Picked(HWND window, int id) {
  const HWND list = GetDlgItem(window, id);
  return static_cast<int>(SendMessageW(list, CB_GETITEMDATA, SendMessageW(list, CB_GETCURSEL, 0, 0), 0));
}

void Keep(const wchar_t* key, int value) { WritePrivateProfileStringW(L"launcher", key, std::to_wstring(value).c_str(), IniPath().c_str()); }

void SaveSettings(HWND window) {
  const int mode = Picked(window, kModeList);  // 0: the screen's own; otherwise one more than its place in g_modes
  const bool sized = mode > 0 && mode <= static_cast<int>(g_modes.size());
  Keep(L"fullscreen", IsDlgButtonChecked(window, kFullscreenBox) == BST_CHECKED ? 1 : 0);
  Keep(L"width", sized ? g_modes[mode - 1].width : 0);
  Keep(L"height", sized ? g_modes[mode - 1].height : 0);
  Keep(L"waw_video", 1);
  Keep(L"refresh", Picked(window, kRefreshList));
  Keep(L"antialiasing", Picked(window, kSmoothList));
  Keep(L"sync_every_frame", Picked(window, kSyncList));
  Keep(L"swbf2_height", Picked(window, kDetailList));
  LoadSettings();
  log::Info("settings saved: fullscreen %d, %d x %d, refresh %d, anti-aliasing %d, sync %d, Battlefront II %d lines", g_settings.fullscreen ? 1 : 0,
            g_settings.width, g_settings.height, g_settings.refresh, g_settings.smoothing, g_settings.sync, g_settings.bfHeight);
}

LRESULT CALLBACK SettingsProc(HWND window, UINT message, WPARAM wParam, LPARAM lParam) {
  static bool play = false;
  switch (message) {
    case WM_COMMAND:
      if (HIWORD(wParam) != BN_CLICKED) break;
      if (LOWORD(wParam) == kSave) {
        SaveSettings(window);
        play = true;
        DestroyWindow(window);
        return 0;
      }
      if (LOWORD(wParam) == kLeave) {
        DestroyWindow(window);
        return 0;
      }
      break;
    case WM_CLOSE:
      DestroyWindow(window);
      return 0;
    case WM_DESTROY:
      g_settingsWindow = nullptr;
      EnableWindow(g_window, TRUE);
      SetForegroundWindow(g_window);
      // Saved, and nothing to choose between: straight in, as before.
      if (play && g_atOnce >= 0) PostMessageW(g_window, kBegin, static_cast<WPARAM>(g_atOnce), 0);
      play = false;
      // "/settings": that was all. (Asked to close, not destroyed from here:
      // it owns this window, which is still on its way out.)
      if (g_onlySettings) PostMessageW(g_window, WM_CLOSE, 0, 0);
      return 0;
  }
  return DefWindowProcW(window, message, wParam, lParam);
}

void OpenSettings() {
  if (g_settingsWindow) return;
  ListModes();
  const Settings& s = g_settings;
  const int width = 460, height = 24 + 6 * 40 + 96 + 56;
  RECT frame = {0, 0, Px(width), Px(height)}, owner{};
  const DWORD style = WS_POPUP | WS_CAPTION | WS_SYSMENU;
  AdjustWindowRect(&frame, style, FALSE);
  GetWindowRect(g_window, &owner);
  g_settingsWindow = CreateWindowW(L"wawbf_settings", L"Settings", style, owner.left + Px(24), owner.top + Px(24), frame.right - frame.left,
                                   frame.bottom - frame.top, g_window, nullptr, GetModuleHandleW(nullptr), nullptr);
  if (!g_settingsWindow) return;
  const HWND w = g_settingsWindow;

  Made(w, L"BUTTON", L"Fullscreen", BS_AUTOCHECKBOX | WS_TABSTOP, kFullscreenBox, 196, 20, 248, 24);
  CheckDlgButton(w, kFullscreenBox, s.fullscreen ? BST_CHECKED : BST_UNCHECKED);

  HWND list = List(w, L"Resolution", kModeList, 1);
  int chosen = 0;
  for (size_t i = 0; i < g_modes.size(); ++i) {
    if (g_modes[i].width == s.width && g_modes[i].height == s.height) chosen = static_cast<int>(i) + 1;
  }
  Offer(list, L"The screen's own (" + std::to_wstring(GetSystemMetrics(SM_CXSCREEN)) + L" x " + std::to_wstring(GetSystemMetrics(SM_CYSCREEN)) + L")", 0, chosen);
  for (size_t i = 0; i < g_modes.size(); ++i) {
    Offer(list, std::to_wstring(g_modes[i].width) + L" x " + std::to_wstring(g_modes[i].height), static_cast<int>(i) + 1, chosen);
  }

  const wchar_t* const own = L"As World at War has it";
  list = List(w, L"Refresh rate", kRefreshList, 2);
  Offer(list, own, 0, s.refresh);
  for (const int rate : g_rates) Offer(list, std::to_wstring(rate) + L" Hz", rate, s.refresh);

  list = List(w, L"Anti-aliasing", kSmoothList, 3);
  Offer(list, own, 0, s.smoothing);
  Offer(list, L"Off", 1, s.smoothing);
  Offer(list, L"2x", 2, s.smoothing);
  Offer(list, L"4x", 4, s.smoothing);

  list = List(w, L"Sync every frame", kSyncList, 4);
  Offer(list, own, -1, s.sync);
  Offer(list, L"No", 0, s.sync);
  Offer(list, L"Yes", 1, s.sync);

  list = List(w, L"Your character's picture", kDetailList, 5);
  const int lines[] = {1080, 900, 720, 540};
  const wchar_t* const called[] = {L"Sharpest (1080 lines)", L"Sharp (900 lines)", L"Fast (720 lines)", L"Fastest (540 lines)"};
  bool listed = false;
  for (int i = 0; i < 4; ++i) {
    Offer(list, called[i], lines[i], s.bfHeight);
    listed = listed || lines[i] == s.bfHeight;
  }
  if (!listed) Offer(list, std::to_wstring(s.bfHeight) + L" lines", s.bfHeight, s.bfHeight);

  Made(w, L"STATIC",
       L"These are the settings World at War only lets you change at its main menu, which this skips. Everything else (brightness, shadows, "
       L"textures, sound, controls) is in its own Options while you play: Esc.",
       SS_LEFT, 0, 24, 24 + 6 * 40, width - 48, 90);
  SetFocus(Made(w, L"BUTTON", g_atOnce >= 0 ? L"Save and play" : L"Save", BS_DEFPUSHBUTTON | WS_TABSTOP, kSave, width - 24 - 110 - 12 - 150, height - 48, 150, 32));
  Made(w, L"BUTTON", L"Cancel", BS_PUSHBUTTON | WS_TABSTOP, kLeave, width - 24 - 110, height - 48, 110, 32);

  EnableWindow(g_window, FALSE);
  ShowWindow(w, SW_SHOW);
}

// The button the keyboard is on, moved by `step` to the next map there is.
void Move(int step) {
  int at = -1;
  const HWND focus = GetFocus();
  for (int i = 0; i < kMapCount; ++i) {
    if (g_buttons[i] && g_buttons[i] == focus) at = i;
  }
  for (int tried = 0; tried < kMapCount; ++tried) {
    at = (at + step + kMapCount) % kMapCount;
    if (g_have[at]) {
      SetFocus(g_buttons[at]);
      return;
    }
  }
}

LRESULT CALLBACK WindowProc(HWND window, UINT message, WPARAM wParam, LPARAM lParam) {
  switch (message) {
    case WM_COMMAND:
      if (HIWORD(wParam) != BN_CLICKED) return 0;
      if (LOWORD(wParam) != kSettingsButton) {
        Pick(LOWORD(wParam) - kFirstButton);
      } else if (g_busy.load()) {
        // A game is on its way: it is called off first (Play sees this, closes
        // Battlefront II again and says kStopped), and the settings open then.
        g_callOff.store(true);
        EnableWindow(GetDlgItem(window, kSettingsButton), FALSE);
        SetWindowTextW(g_status, L"Stopping, to open the settings...");
      } else {
        OpenSettings();
      }
      return 0;
    case kBegin:
      Pick(static_cast<int>(wParam));
      return 0;
    case kStopped:
      g_busy.store(false);
      g_callOff.store(false);
      for (int i = 0; i < kMapCount; ++i) {
        if (g_buttons[i]) EnableWindow(g_buttons[i], g_have[i]);
      }
      EnableWindow(GetDlgItem(window, kSettingsButton), TRUE);
      SetWindowTextW(g_status, L"");
      OpenSettings();
      return 0;
    case WM_TIMER: {
      // A controller: the d-pad moves, A plays, B leaves. Each on the press.
      static uint32_t held = ~0u;
      const uint32_t now = GetForegroundWindow() == window ? pad::Buttons() : 0;
      const uint32_t pressed = now & ~held;
      held = now;
      if (g_busy.load()) return 0;
      if (pressed & pad::kUp) Move(-1);
      if (pressed & pad::kDown) Move(1);
      if (pressed & 0x1000) {  // A
        for (int i = 0; i < kMapCount; ++i) {
          if (g_buttons[i] && g_buttons[i] == GetFocus()) Pick(i);
        }
      }
      if (pressed & 0x2000) DestroyWindow(window);  // B
      return 0;
    }
    case kSay:
    case kFailed: {
      auto* text = reinterpret_cast<std::wstring*>(lParam);
      SetWindowTextW(g_status, text->c_str());
      delete text;
      if (message == kFailed) {
        g_busy.store(false);
        g_callOff.store(false);
        for (int i = 0; i < kMapCount; ++i) {
          if (g_buttons[i]) EnableWindow(g_buttons[i], g_have[i]);
        }
        EnableWindow(GetDlgItem(window, kSettingsButton), TRUE);
        ShowWindow(window, SW_SHOW);
        Move(1);
      }
      return 0;
    }
    case kStarted:
      ShowWindow(window, SW_HIDE);
      return 0;
    case kOver:
      DestroyWindow(window);
      return 0;
    case WM_CLOSE:
      // With a game on its way the window only hides: someone has to be here
      // to close Battlefront II afterwards, and to go on holding what tells
      // the two games they were started from here.
      if (g_busy.load()) {
        ShowWindow(window, SW_HIDE);
        return 0;
      }
      break;
    case WM_DESTROY:
      PostQuitMessage(0);
      return 0;
  }
  return DefWindowProcW(window, message, wParam, lParam);
}

// wawbf_launcher /uninstall [/quiet]
int TakeOut(bool quiet) {
  if (Running(session::kWaw.exe) || Running(session::kBf.exe)) {
    if (!quiet) MessageBoxW(nullptr, L"Close World at War and Battlefront II first.", kTitle, MB_OK | MB_ICONINFORMATION);
    return 1;
  }
  const std::wstring wawDir = GameFolder(g_settings.wawFolder, kWawFolder, session::kWaw.exe);
  const std::wstring bfDir = GameFolder(g_settings.bfFolder, kBfFolder, session::kBf.exe);
  int gone = 0;
  if (!wawDir.empty()) {
    GiveNameBack(wawDir);
    gone += Uninstall(wawDir, {L"wawbf_waw.log", L"wawbf_name.txt"});
  }
  if (!bfDir.empty()) gone += Uninstall(bfDir, {L"wawbf_swbf2.log", L"addon\\WAW\\wawbf_start.txt"});
  gone += Uninstall(WawData() + L"\\mods", {});
  log::Info("uninstall: %d files removed", gone);
  const std::wstring said = gone ? L"The mod's files have been taken out of both games (" + std::to_wstring(gone) + L" files). This folder can be deleted."
                                 : std::wstring(L"There was nothing of the mod's installed in either game.");
  if (!quiet) MessageBoxW(nullptr, said.c_str(), kTitle, MB_OK | MB_ICONINFORMATION);
  return 0;
}

}  // namespace

int WINAPI wWinMain(HINSTANCE instance, HINSTANCE, PWSTR commandLine, int show) {
  // Told the screen's real size: it is what World at War is asked to fill.
  SetProcessDPIAware();
  wchar_t self[MAX_PATH] = {};
  GetModuleFileNameW(nullptr, self, MAX_PATH);
  g_beside = self;
  g_beside.erase(g_beside.find_last_of(L"\\/") + 1);
  log::Init(g_beside + L"wawbf_launcher.log");

  LoadSettings();

  if (commandLine && wcsstr(commandLine, L"/uninstall")) return TakeOut(wcsstr(commandLine, L"/quiet") != nullptr);

  g_onlySettings = commandLine && wcsstr(commandLine, L"/settings");

  // Held from here to the end: what tells the two games' bridges that they
  // were started from here. And there is only one of it, so only one of this.
  // (Not for the settings by themselves: nothing is started from those.)
  const HANDLE session = g_onlySettings ? nullptr : session::Hold();
  if (!session && !g_onlySettings) {
    if (const HWND other = FindWindowW(L"wawbf_launcher", nullptr)) {
      ShowWindow(other, SW_SHOW);
      SetForegroundWindow(other);
    }
    return 0;
  }

  WNDCLASSW type{};
  type.lpfnWndProc = WindowProc;
  type.hInstance = instance;
  type.hCursor = LoadCursorW(nullptr, IDC_ARROW);
  type.hbrBackground = reinterpret_cast<HBRUSH>(COLOR_BTNFACE + 1);
  type.lpszClassName = L"wawbf_launcher";
  RegisterClassW(&type);
  WNDCLASSW settingsType = type;
  settingsType.lpfnWndProc = SettingsProc;
  settingsType.lpszClassName = L"wawbf_settings";
  RegisterClassW(&settingsType);

  // A map is one to offer if its mod is in World at War already, or is among
  // the files this was given to put there.
  int built = 0, only = -1, asked = -1;
  for (int i = 0; i < kMapCount; ++i) {
    g_have[i] = Exists(WawData() + L"\\mods\\" + ModOf(kMaps[i]) + L"\\mod.ff") || Exists(g_beside + L"files\\mods\\" + ModOf(kMaps[i]) + L"\\mod.ff");
    if (g_have[i]) {
      ++built;
      only = i;
      if (lstrcmpiW(g_settings.map.c_str(), kMaps[i].name) == 0) asked = i;
    }
  }

  const HDC screen = GetDC(nullptr);
  g_dpi = GetDeviceCaps(screen, LOGPIXELSY);
  ReleaseDC(nullptr, screen);

  // The maps (or the one), what is happening, and at the bottom the way into
  // the settings.
  const int width = Px(460), row = Px(56), top = Px(70), words = Px(96), bottom = Px(52);
  RECT frame = {0, 0, width, top + std::max(built, 1) * row + words + bottom};
  const DWORD style = WS_OVERLAPPED | WS_CAPTION | WS_SYSMENU | WS_MINIMIZEBOX;
  AdjustWindowRect(&frame, style, FALSE);
  g_window = CreateWindowW(type.lpszClassName, kTitle, style, CW_USEDEFAULT, CW_USEDEFAULT, frame.right - frame.left, frame.bottom - frame.top,
                           nullptr, nullptr, instance, nullptr);
  if (!g_window) return 1;

  g_big = CreateFontW(-Px(22), 0, 0, 0, FW_SEMIBOLD, 0, 0, 0, DEFAULT_CHARSET, 0, 0, CLEARTYPE_QUALITY, 0, L"Segoe UI");
  g_plain = CreateFontW(-Px(15), 0, 0, 0, FW_NORMAL, 0, 0, 0, DEFAULT_CHARSET, 0, 0, CLEARTYPE_QUALITY, 0, L"Segoe UI");
  const HWND heading = CreateWindowW(L"STATIC", built > 1 ? L"Which map?" : kTitle, WS_CHILD | WS_VISIBLE | SS_CENTER, 0, Px(22), width, Px(32), g_window,
                                     nullptr, instance, nullptr);
  SendMessageW(heading, WM_SETFONT, reinterpret_cast<WPARAM>(g_big), TRUE);

  int line = 0;
  for (int i = 0; i < kMapCount; ++i) {
    if (!g_have[i]) continue;
    g_buttons[i] = CreateWindowW(L"BUTTON", kMaps[i].title, WS_CHILD | WS_VISIBLE | WS_TABSTOP | BS_PUSHBUTTON, Px(40), top + line * row, width - Px(80),
                                 row - Px(10), g_window, reinterpret_cast<HMENU>(static_cast<INT_PTR>(kFirstButton + i)), instance, nullptr);
    SendMessageW(g_buttons[i], WM_SETFONT, reinterpret_cast<WPARAM>(g_big), TRUE);
    ++line;
  }
  const int below = top + std::max(built, 1) * row;
  g_status = CreateWindowW(L"STATIC", built ? L"" : L"No map's files are here: neither installed in World at War nor in a \"files\" folder beside this.",
                           WS_CHILD | WS_VISIBLE | SS_CENTER, Px(16), below + Px(4), width - Px(32), words - Px(8), g_window, nullptr, instance, nullptr);
  SendMessageW(g_status, WM_SETFONT, reinterpret_cast<WPARAM>(g_plain), TRUE);
  const HWND settings = CreateWindowW(L"BUTTON", L"Settings", WS_CHILD | WS_VISIBLE | WS_TABSTOP | BS_PUSHBUTTON, width - Px(16) - Px(110), below + words + Px(8),
                                      Px(110), Px(30), g_window, reinterpret_cast<HMENU>(static_cast<INT_PTR>(kSettingsButton)), instance, nullptr);
  SendMessageW(settings, WM_SETFONT, reinterpret_cast<WPARAM>(g_plain), TRUE);

  if (g_onlySettings) {
    // The main window is made and never shown: the settings belong to it.
    OpenSettings();
    if (!g_settingsWindow) return 1;
  } else {
    ShowWindow(g_window, show);
    Move(1);
    SetTimer(g_window, kPadTimer, 60, nullptr);
    // Nothing to choose between: straight in. (Settings, pressed while it
    // loads, calls that off and opens them.)
    if (asked < 0 && built == 1) asked = only;
    g_atOnce = asked;
    if (asked >= 0) PostMessageW(g_window, kBegin, static_cast<WPARAM>(asked), 0);
  }

  MSG message;
  while (GetMessageW(&message, nullptr, 0, 0) > 0) {
    if (g_settingsWindow) {
      if (message.message == WM_KEYDOWN && message.wParam == VK_ESCAPE) { DestroyWindow(g_settingsWindow); continue; }
      if (IsDialogMessageW(g_settingsWindow, &message)) continue;
    } else if (message.message == WM_KEYDOWN && !g_busy.load()) {
      if (message.wParam == VK_UP) { Move(-1); continue; }
      if (message.wParam == VK_DOWN) { Move(1); continue; }
      if (message.wParam == VK_ESCAPE) { DestroyWindow(g_window); continue; }
    }
    if (IsDialogMessageW(g_window, &message)) continue;
    TranslateMessage(&message);
    DispatchMessageW(&message);
  }
  if (session) CloseHandle(session);
  return 0;
}
