// Local native frontend adapter for PPSSPP 1.20.4. GPL-2.0-or-later.
// Included by NativeApp.cpp; every command is dispatched on its normal frame thread.
#pragma once
#include <algorithm>
#include <atomic>
#include <cmath>
#include <fstream>
#include <iomanip>
#include <mutex>
#include <sstream>
#include <mach/mach.h>
#include "Core/Core.h"
#include "Core/Config.h"
#include "Core/KeyMap.h"
#include "Core/System.h"
#include "Core/ELF/ParamSFO.h"
#include "Core/HLE/sceCtrl.h"
#include "Core/HW/Display.h"
#include "Core/MIPS/JitCommon/JitCommon.h"
#include "Core/SaveState.h"
#include "Core/Screenshot.h"
#include "Common/System/Request.h"
#include "Common/File/FileUtil.h"
#include "Common/TimeUtil.h"
#include "UI/KoalaMetrics.h"

namespace KoalaNative {
static std::string root;
static std::string logRoot;
static std::string lastCommand;
static std::atomic<bool> saving{false}, exitRequested{false}, resumeRequested{false};
static std::mutex outputLock;
static double nextPoll = 0, nextSample = 0, nextAutoSave = 0, buttonUntil = 0, analogUntil = 0;
static uint32_t heldButtons = 0;
static bool initialized = false;

static std::string Quote(const std::string &s) {
  std::ostringstream out;
  out << '"';
  for (unsigned char c : s) {
    if (c == '"' || c == '\\') out << '\\' << c;
    else if (c < 32) out << "\\u" << std::hex << std::setw(4) << std::setfill('0') << int(c) << std::dec;
    else out << c;
  }
  out << '"';
  return out.str();
}
static void AtomicWrite(const std::string &name, const std::string &value) {
  std::lock_guard<std::mutex> lock(outputLock);
  const auto target = root + "/" + name;
  { std::ofstream f(target + ".tmp"); f << value << '\n'; }
  std::rename((target + ".tmp").c_str(), target.c_str());
}
static void Ack(const std::string &id, bool ok, const std::string &message) {
  AtomicWrite("ack.json", "{\"id\":" + Quote(id) + ",\"ok\":" + (ok ? "true" : "false") + ",\"message\":" + Quote(message) + "}");
}
static void PublishMappings() {
  std::ostringstream out;
  KeyMap::LockMappings();
  out << "{\"generation\":" << KeyMap::g_controllerMapGeneration << ",\"actions\":[";
  size_t count = 0; const auto *keys = KeyMap::GetMappableKeys(&count);
  for (size_t i = 0; i < count; ++i) {
    if (i) out << ',';
    std::vector<KeyMap::MultiInputMapping> bindings;
    KeyMap::InputMappingsFromPspButtonNoLock(keys[i].key, &bindings, false);
    out << "{\"name\":" << Quote(keys[i].name) << ",\"bindings\":[";
    for (size_t b = 0; b < bindings.size(); ++b) {
      if (b) out << ',';
      out << '['; bool first = true;
      for (auto &input : bindings[b].mappings) {
        if (!first) out << ','; first = false;
        out << "{\"device\":" << (int)input.deviceId << ",\"code\":" << input.keyCode << '}';
      }
      out << ']';
    }
    out << "]}";
  }
  out << "]}";
  KeyMap::UnlockMappings();
  AtomicWrite("mappings.json", out.str());
}
static bool SlotExists(std::string_view prefix, int slot) {
  // HasSaveInSlot uses PPSSPP's menu cache, which can predate an async save.
  return File::Exists(SaveState::GenerateSaveSlotPath(prefix, slot, "ppst"));
}
static void Save(const std::string &id, int slot, bool quit = false) {
  if (!PSP_IsInited() || saving.exchange(true)) {
    if (!id.empty()) Ack(id, false, "游戏尚未就绪或正在存档");
    return;
  }
  SaveState::SaveSlot(SaveState::GetGamePrefix(g_paramSFO), slot,
    [id, quit](SaveState::Status status, std::string_view message) {
      saving = false;
      const bool ok = status != SaveState::Status::FAILURE;
      if (!id.empty()) Ack(id, ok, ok ? "存档已保存" : std::string(message));
      if (quit && ok) exitRequested = true;
    });
}
static void Tick() {
  if (!initialized) {
    initialized = true;
    if (const char *path = getenv("KOALA_CONTROL_DIR")) root = path;
    logRoot = root;
    if (const char *path = getenv("KOALA_LOG_DIR")) logRoot = path;
    if (!root.empty()) File::CreateFullPath(Path(root));
    if (!logRoot.empty()) File::CreateFullPath(Path(logRoot));
  }
  if (root.empty()) return;
  const double now = time_now_d();
  if (exitRequested.exchange(false)) System_ExitApp();
  if (resumeRequested.exchange(false)) Core_Resume();
  if (heldButtons && now >= buttonUntil) { __CtrlUpdateButtons(0, heldButtons); heldButtons = 0; }
  if (analogUntil && now >= analogUntil) { __CtrlSetAnalogXY(0, 0, 0); analogUntil = 0; }
  if (now >= nextPoll) {
    nextPoll = now + 0.025;
    std::ifstream file(root + "/command.txt");
    std::string id, op;
    file >> id >> op;
    if (!id.empty() && id != lastCommand) {
      lastCommand = id;
      const bool ready = PSP_IsInited();
      if (op == "quit") {
        if (ready) { if (Core_IsStepping()) Core_Resume(); Save(id, 0, true); }
        else { Ack(id, true, "已停止"); System_ExitApp(); }
      } else if (!ready) {
        Ack(id, false, "游戏尚未就绪");
      } else if (op == "ping") {
        Ack(id, true, "控制通道正常");
      } else if (op == "mapping-ui") {
        if (GetUIState() != UISTATE_INGAME) Ack(id, false, "请先退出游戏内菜单，再打开按键设置");
        else { System_PostUIMessage(UIMessage::SHOW_CONTROL_MAPPING); Ack(id, true, "按键设置已在游戏窗口打开"); }
      } else if (op == "test-binding" && getenv("KOALA_BACKGROUND_TEST")) {
        // Hidden-test seam uses the same KeyMap mutation API as ControlMappingScreen.
        std::string name, mapping; file >> name >> mapping;
        size_t count = 0; const auto *keys = KeyMap::GetMappableKeys(&count); bool found = false;
        for (size_t i = 0; i < count; ++i) if (name == keys[i].name) {
          if (mapping == "clear") { std::vector<KeyMap::MultiInputMapping> old;
            KeyMap::InputMappingsFromPspButton(keys[i].key, &old, false);
            for (size_t j = old.size(); j > 0; --j) KeyMap::DeleteNthMapping(keys[i].key, (int)j - 1);
          } else KeyMap::SetInputMapping(keys[i].key, KeyMap::MultiInputMapping::FromConfigString(mapping), true);
          found = true; break;
        }
        Ack(id, found, found ? "测试映射已改变（未写入配置文件）" : "未知按键");
      } else if (op == "bind-shoulders") {
        // SDL v1.20.4 reports LB/RB as b6/b5, while the stock map binds b7/b8.
        // Add aliases for pad 0; keep keyboard and custom bindings intact.
        KeyMap::SetInputMapping(CTRL_LTRIGGER, KeyMap::MultiInputMapping(InputMapping(DEVICE_ID_PAD_0, NKCODE_BUTTON_6)), false);
        KeyMap::SetInputMapping(CTRL_RTRIGGER, KeyMap::MultiInputMapping(InputMapping(DEVICE_ID_PAD_0, NKCODE_BUTTON_5)), false);
        const bool saved = g_Config.Save("Koala SDL shoulder aliases");
        Ack(id, saved, saved ? "已为首个手柄添加 L/R 肩键映射，原有按键保留" : "映射已应用，但配置保存失败");
      } else if (op == "settings") {
        int muted, volume, hud;
        if (!(file >> muted >> volume >> hud) || muted < 0 || muted > 1 || volume < 0 || volume > 100 || hud < 0 || hud > 2) {
          Ack(id, false, "设置参数无效");
        } else {
          g_Config.bEnableSound = !muted;
          g_Config.iGameVolume = volume;
          g_Config.iShowStatusFlags = hud == 0 ? 0 : hud == 1 ? 6 : 22;
          Ack(id, true, "音量、静音与 HUD 已应用；其余设置下次启动生效");
        }
        nextSample = 0;
      } else if (op == "save") {
        int slot = 1; file >> slot; Save(id, std::clamp(slot, 0, 1));
      } else if (op == "load") {
        int slot = 1; file >> slot;
        const auto prefix = SaveState::GetGamePrefix(g_paramSFO);
        slot = std::clamp(slot, 0, 1);
        if (saving.load() || !SlotExists(prefix, slot)) Ack(id, false, "此位置没有存档或正在保存");
        else SaveState::LoadSlot(prefix, slot, [id](SaveState::Status s, std::string_view message) {
          if (s != SaveState::Status::FAILURE) resumeRequested = true;
          Ack(id, s != SaveState::Status::FAILURE, s == SaveState::Status::FAILURE ? std::string(message) : "存档已读取");
        });
      } else if (op == "pause") {
        if (Core_IsStepping()) Core_Resume(); else Core_Break(BreakReason::UIPause);
        Ack(id, true, "播放状态已切换");
      } else if (op == "resume") {
        Core_Resume(); Ack(id, true, "继续游戏");
      } else if (op == "mute") {
        g_Config.bEnableSound = !g_Config.bEnableSound; nextSample = 0; Ack(id, true, g_Config.bEnableSound ? "声音已开启" : "已静音");
      } else if (op == "fullscreen") {
        g_Config.bFullScreen = !g_Config.bFullScreen; System_ApplyFullscreenState(); Ack(id, true, "全屏已切换");
      } else if (op == "press") {
        uint32_t bits = 0; int ms = 100; file >> bits >> ms;
        if (heldButtons) __CtrlUpdateButtons(0, heldButtons);
        heldButtons = bits & CTRL_MASK_USER;
        __CtrlUpdateButtons(heldButtons, 0);
        buttonUntil = now + std::clamp(ms, 16, 10000) / 1000.0;
        Ack(id, true, "按键已按下");
      } else if (op == "analog") {
        float x = 0, y = 0; int ms = 100; file >> x >> y >> ms;
        __CtrlSetAnalogXY(0, std::clamp(x, -1.0f, 1.0f), std::clamp(y, -1.0f, 1.0f));
        analogUntil = now + std::clamp(ms, 16, 10000) / 1000.0;
        Ack(id, true, "摇杆已移动");
      } else if (op == "screenshot") {
        std::string name; file >> name;
        if (name.empty() || name.find_first_not_of("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_.") != std::string::npos || name.front() == '.') Ack(id, false, "截图文件名无效");
        else ScheduleScreenshot(Path(logRoot + "/" + name), ScreenshotFormat::PNG, ScreenshotType::Output, 0, [id](ScreenshotResult r) {
          Ack(id, r == ScreenshotResult::Success, r == ScreenshotResult::Success ? "截图已保存" : "截图失败");
        });
      } else Ack(id, false, "未知操作");
    }
  }
  if (PSP_IsInited() && GetUIState() == UISTATE_INGAME && !Core_IsStepping()) {
    if (nextAutoSave == 0) nextAutoSave = now + 30;
    if (now >= nextAutoSave) { nextAutoSave = now + 30; Save("", 0); }
  }
  if (now < nextSample) return;
  nextSample = now + 1;
  PublishMappings();
  float vps = 0, fps = 0, actual = 0;
  const bool ready = PSP_IsInited();
  const bool playing = ready && GetUIState() == UISTATE_INGAME && !Core_IsStepping();
  if (playing) __DisplayGetFPS(&vps, &fps, &actual);
  if (!std::isfinite(vps)) vps = 0;
  if (!std::isfinite(fps)) fps = 0;
  if (!std::isfinite(actual)) actual = 0;
  mach_task_basic_info_data_t info{};
  mach_msg_type_number_t count = MACH_TASK_BASIC_INFO_COUNT;
  task_info(mach_task_self(), MACH_TASK_BASIC_INFO, (task_info_t)&info, &count);
  const auto timing = playing ? KoalaMetrics::FrameTiming() : KoalaMetrics::Timing{};
  const auto prefix = ready ? SaveState::GetGamePrefix(g_paramSFO) : "";
  const bool autoExists = ready && SlotExists(prefix, 0);
  const bool manualExists = ready && SlotExists(prefix, 1);
  std::ostringstream out;
  out << std::fixed << std::setprecision(3)
      << "{\"time\":" << now << ",\"ready\":" << (ready ? "true" : "false")
      << ",\"playing\":" << (playing ? "true" : "false")
      << ",\"vps\":" << vps << ",\"game_fps\":" << actual << ",\"target_game_fps\":" << fps
      << ",\"speed_percent\":" << (vps / 59.94 * 100.0)
      << ",\"vblanks\":" << (ready ? __DisplayGetNumVblanks() : 0)
      << ",\"flips\":" << (ready ? __DisplayGetFlipCount() : 0)
      << ",\"frame_ms_mean\":" << timing.mean << ",\"frame_ms_p95\":" << timing.p95 << ",\"frame_samples\":" << timing.samples
      << ",\"volume\":" << g_Config.iGameVolume << ",\"audio_buffer\":" << g_Config.iSDLAudioBufferSize
      << ",\"hud\":" << (g_Config.iShowStatusFlags == 0 ? 0 : (g_Config.iShowStatusFlags & 16) ? 2 : 1)
      << ",\"vsync\":" << (g_Config.bVSync ? "true" : "false")
      << ",\"texture_filter\":" << g_Config.iTexFiltering << ",\"anisotropy\":" << g_Config.iAnisotropyLevel
      << ",\"rss_bytes\":" << info.resident_size
      << ",\"jit_active\":" << (MIPSComp::jit ? "true" : "false")
      << ",\"cpu_core\":" << g_Config.iCpuCore << ",\"gpu_backend\":" << (int)GetGPUBackend()
      << ",\"render_scale\":" << g_Config.iInternalResolution << ",\"frameskip\":" << g_Config.iFrameSkip
      << ",\"muted\":" << (g_Config.bEnableSound ? "false" : "true")
      << ",\"saving\":" << (saving.load() ? "true" : "false")
      << ",\"title\":" << Quote(ready ? g_paramSFO.GetValueString("TITLE") : "")
      << ",\"disc_id\":" << Quote(ready ? g_paramSFO.GetDiscID() : "")
      << ",\"gpu\":" << Quote(GetGPUBackendDevice())
      << ",\"auto_exists\":" << (autoExists ? "true" : "false")
      << ",\"manual_exists\":" << (manualExists ? "true" : "false")
      << ",\"auto_path\":" << Quote(autoExists ? SaveState::GenerateSaveSlotPath(prefix, 0, "ppst").ToString() : "") << "}";
  AtomicWrite("status.json", out.str());
  std::ofstream(logRoot + "/performance.jsonl", std::ios::app) << out.str() << '\n';
}
}  // namespace KoalaNative
