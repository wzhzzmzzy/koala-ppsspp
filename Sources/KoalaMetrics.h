// Koala PSP: emulated VBlank interval statistics, not input-to-photon latency.
#pragma once
#include <algorithm>
#include <cmath>
#include <vector>
#include "Core/HW/Display.h"
namespace KoalaMetrics {
struct Timing { double mean = 0, p95 = 0; int samples = 0; };
inline Timing FrameTiming() {
  int valid = 0, pos = 0; float *sleep = nullptr;
  const float *history = __DisplayGetFrameTimes(&valid, &pos, &sleep);
  std::vector<double> recent;
  // Display.cpp has a 600-entry circular buffer. Skip the first sample after init,
  // whose origin precedes the first frame (and can include startup time).
  const int available = std::min(60, valid < 600 ? std::max(0, valid - 1) : valid);
  Timing result;
  for (int i = 0; i < available; ++i) {
    const double ms = history[(pos - 1 - i + 600) % 600] * 1000.0;
    if (std::isfinite(ms) && ms > 0) { recent.push_back(ms); result.mean += ms; }
  }
  result.samples = (int)recent.size();
  if (result.samples) {
    result.mean /= result.samples;
    std::sort(recent.begin(), recent.end());
    result.p95 = recent[(int)std::ceil(result.samples * 0.95) - 1];
  }
  return result;
}
}
