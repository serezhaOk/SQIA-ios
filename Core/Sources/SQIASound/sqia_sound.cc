// The synth: eight Plaits voices, an envelope each, a pan each, summed into
// the Rings reverb.
//
// Everything is worked out a Plaits block (12 samples, 0.25 ms) at a time,
// which is the rate Plaits itself reads its knobs at. Gains are ramped across
// the block so nothing steps audibly.

#include "sqia_sound.h"

#include <algorithm>
#include <atomic>
#include <cmath>
#include <cstring>
#include <new>
#include <vector>

#include "plaits/dsp/voice.h"
#include "rings/dsp/fx/reverb.h"

struct SQIASampleSet {
  struct Sample {
    std::vector<float> left;
    std::vector<float> right;  // empty for mono
    double rate = 48000;
    int frames() const { return static_cast<int>(left.size()); }
  };
  struct Zone {
    int sample;
    int low;
    int high;
    float root;
  };

  std::vector<Sample> samples;
  std::vector<Zone> zones;
  // For each MIDI note, the zones it may play — worked out once, off the
  // audio thread, so a note costs a lookup.
  std::vector<int> choices[128];

  void Build() {
    for (int note = 0; note < 128; ++note) {
      std::vector<int>& c = choices[note];
      c.clear();
      for (int z = 0; z < static_cast<int>(zones.size()); ++z) {
        if (note >= zones[z].low && note <= zones[z].high) c.push_back(z);
      }
      if (!c.empty() || zones.empty()) continue;
      // Outside every zone: the nearest one stretches to cover it.
      int best = 0;
      int best_distance = 1 << 30;
      for (int z = 0; z < static_cast<int>(zones.size()); ++z) {
        const int d = note < zones[z].low ? zones[z].low - note : note - zones[z].high;
        if (d < best_distance) {
          best_distance = d;
          best = z;
        }
      }
      c.push_back(best);
    }
  }
};

namespace {

constexpr int kBlock = static_cast<int>(plaits::kBlockSize);
constexpr float kRate = static_cast<float>(SQIA_SAMPLE_RATE);
constexpr float kBlockTime = kBlock / kRate;

// Plaits works out pitch against its hardware's real clock, 47872.34 Hz, not
// the nominal 48 kHz. Played at an honest 48 kHz everything would come out
// 4.6 cents sharp, so the difference goes back in here.
const float kTuningCorrection =
    -12.0f * std::log2(plaits::kSampleRate / plaits::kCorrectedSampleRate);

constexpr float kPi = 3.14159265358979f;
constexpr float kSqrt2 = 1.41421356237310f;

// Below this a voice counts as silent. Plaits rounds with a +1 LSB offset, so
// true silence reads as 1/32768 — the threshold sits well above that.
constexpr float kSilence = 2e-4f;

const SQIAParamInfo kParams[SQIA_PARAM_COUNT] = {
    // key, name, min, max, default, unit, log, integer, spreadable
    {"engine", "Engine", 0, SQIA_ENGINE_COUNT - 1, 8, SQIA_UNIT_CHOICE, false, true, false},
    {"harmonics", "Harmonics", 0, 1, 0.5f, SQIA_UNIT_NONE, false, false, true},
    {"timbre", "Timbre", 0, 1, 0.5f, SQIA_UNIT_NONE, false, false, true},
    {"morph", "Morph", 0, 1, 0.5f, SQIA_UNIT_NONE, false, false, true},
    {"env_to_pitch", "Env → Pitch", -1, 1, 0, SQIA_UNIT_BIPOLAR, false, false, true},
    {"env_to_timbre", "Env → Timbre", -1, 1, 0, SQIA_UNIT_BIPOLAR, false, false, true},
    {"env_to_morph", "Env → Morph", -1, 1, 0, SQIA_UNIT_BIPOLAR, false, false, true},
    {"lpg_decay", "Decay", 0, 1, 0.5f, SQIA_UNIT_NONE, false, false, true},
    {"lpg_colour", "Colour", 0, 1, 0.5f, SQIA_UNIT_NONE, false, false, true},
    {"amp_mode", "Amp", 0, 2, SQIA_AMP_LPG, SQIA_UNIT_CHOICE, false, true, false},
    {"attack", "Attack", 0.001f, 8, 0.003f, SQIA_UNIT_SECONDS, true, false, true},
    {"decay", "Decay", 0.01f, 8, 0.6f, SQIA_UNIT_SECONDS, true, false, true},
    {"sustain", "Sustain", 0, 1, 0.7f, SQIA_UNIT_NONE, false, false, true},
    {"release", "Release", 0.01f, 10, 0.4f, SQIA_UNIT_SECONDS, true, false, true},
    {"velocity", "Velocity", 0, 1, 0.6f, SQIA_UNIT_NONE, false, false, false},
    {"aux_mix", "Aux", 0, 1, 0, SQIA_UNIT_NONE, false, false, true},
    {"transpose", "Transpose", -24, 24, 0, SQIA_UNIT_SEMITONES, false, true, false},
    {"fine", "Fine", -50, 50, 0, SQIA_UNIT_CENTS, false, false, true},
    {"pan", "Pan", -1, 1, 0, SQIA_UNIT_BIPOLAR, false, false, true},
    {"level", "Level", -36, 0, -8, SQIA_UNIT_DECIBELS, false, false, true},
    {"polyphony", "Voices", 1, SQIA_MAX_VOICES, SQIA_MAX_VOICES, SQIA_UNIT_COUNT, false, true, false},
    {"reverb_mix", "Mix", 0, 1, 0.2f, SQIA_UNIT_NONE, false, false, false},
    {"reverb_time", "Time", 0, 1, 0.5f, SQIA_UNIT_NONE, false, false, false},
    {"reverb_tone", "Tone", 0, 1, 0.5f, SQIA_UNIT_NONE, false, false, false},
    {"source", "Source", 0, 1, SQIA_SOURCE_PLAITS, SQIA_UNIT_CHOICE, false, true, false},
    {"sample_start", "Start", 0, 0.95f, 0, SQIA_UNIT_NONE, false, false, true},
    {"cutoff", "Cutoff", 40, 20000, 20000, SQIA_UNIT_HERTZ, true, false, true},
    {"resonance", "Resonance", 0, 1, 0, SQIA_UNIT_NONE, false, false, true},
    {"key_track", "Key track", 0, 1, 1, SQIA_UNIT_NONE, false, false, false},
};

// In the order Plaits registers them in voice.cc.
const char* const kEngineKeys[SQIA_ENGINE_COUNT] = {
    "va_vcf", "phase_distortion", "six_op_a", "six_op_b",
    "six_op_c", "wave_terrain", "string_machine", "chiptune",
    "virtual_analog", "waveshaping", "fm", "grain_formant",
    "additive", "wavetable", "chords", "speech",
    "swarm", "noise", "particle", "string",
    "modal", "bass_drum", "snare_drum", "hi_hat",
};

inline float Clamp(float x, float lo, float hi) { return std::min(std::max(x, lo), hi); }

// Transparent up to −1 dB, then bends smoothly into ±1.
inline float SoftCeiling(float x) {
  const float knee = 0.9f;
  const float a = std::fabs(x);
  if (a <= knee) return x;
  const float y = knee + (1.0f - knee) * std::tanh((a - knee) / (1.0f - knee));
  return x < 0 ? -y : y;
}

struct Event {
  enum Type : uint8_t { kNoteOn, kNoteOff, kAllOff, kPanic };
  Type type;
  uint8_t note;
  float velocity;
  /// A note-on that releases itself after this long; zero to wait for
  /// its note-off.
  float seconds;
};

// Single producer, single consumer.
class EventQueue {
 public:
  bool Push(const Event& e) {
    const uint32_t head = head_.load(std::memory_order_relaxed);
    const uint32_t next = (head + 1) & kMask;
    if (next == tail_.load(std::memory_order_acquire)) return false;
    events_[head] = e;
    head_.store(next, std::memory_order_release);
    return true;
  }

  bool Pop(Event* e) {
    const uint32_t tail = tail_.load(std::memory_order_relaxed);
    if (tail == head_.load(std::memory_order_acquire)) return false;
    *e = events_[tail];
    tail_.store((tail + 1) & kMask, std::memory_order_release);
    return true;
  }

 private:
  static constexpr uint32_t kSize = 512;
  static constexpr uint32_t kMask = kSize - 1;
  Event events_[kSize];
  std::atomic<uint32_t> head_{0};
  std::atomic<uint32_t> tail_{0};
};

class Rng {
 public:
  explicit Rng(uint32_t seed) : state_(seed ? seed : 1) {}
  // Uniform in [-1, 1].
  float Bipolar() {
    state_ ^= state_ << 13;
    state_ ^= state_ >> 17;
    state_ ^= state_ << 5;
    return static_cast<float>(state_) / 2147483648.0f - 1.0f;
  }

 private:
  uint32_t state_;
};

// A parameter as one note hears it: the knob, moved by that note's roll
// within the spread. The spread is a fraction of the knob's travel, so a log
// knob wanders by a ratio and a linear one by a distance.
inline float Rolled(int param, float value, float spread, float roll) {
  const SQIAParamInfo& info = kParams[param];
  if (spread <= 0.0f || roll == 0.0f) return value;
  float v;
  if (info.logarithmic) {
    v = value * std::pow(info.max / info.min, roll * spread);
  } else {
    v = value + roll * spread * (info.max - info.min);
  }
  return Clamp(v, info.min, info.max);
}

struct Voice {
  enum Stage { kIdle, kAttack, kDecay, kSustain, kRelease };

  plaits::Voice plaits;
  alignas(16) char ram[16384];
  stmlib::BufferAllocator allocator;
  plaits::Voice::Frame frames[plaits::kMaxBlockSize];

  bool active = false;
  bool gate = false;
  int note = 0;
  float velocity = 0;
  uint64_t started = 0;
  float roll[SQIA_PARAM_COUNT] = {};

  Stage stage = kIdle;
  float env = 0;
  // Blocks the trigger is held low for, so a retriggered voice sees an edge.
  int trigger_low = 0;
  int silent_samples = 0;

  // The gain actually applied at the end of the last block, per side; the
  // next block ramps from here.
  float gain_l = 0;
  float gain_r = 0;

  // A stolen voice fades out for a couple of milliseconds before taking its
  // new note, instead of jumping mid-cycle.
  int fade_blocks = 0;
  bool has_pending = false;
  int pending_note = 0;
  float pending_velocity = 0;
  // The pending note's key came up before it could start: play it anyway,
  // and release it as soon as its attack is through.
  bool pending_released = false;
  bool release_after_attack = false;

  // Playing a sample: which zone, where in it, and the filter's memory.
  int zone = -1;
  double position = 0;
  bool sample_ended = false;
  float svf_l[2] = {};
  float svf_r[2] = {};

  void Init() {
    allocator.Init(ram, sizeof(ram));
    plaits.Init(&allocator);
  }
};

}  // namespace

struct SQIASynth {
  static constexpr int kFadeBlocks = 8;  // 2 ms

  std::atomic<float> params[SQIA_PARAM_COUNT];
  std::atomic<float> spreads[SQIA_PARAM_COUNT];
  EventQueue events;

  Voice voices[SQIA_MAX_VOICES];
  uint64_t clock = 0;
  Rng rng{0x5eed1e55u};

  rings::Reverb reverb;
  uint16_t reverb_ram[32768];

  float block_l[kBlock];
  float block_r[kBlock];
  int block_position = kBlock;

  std::atomic<int> active_voices{0};
  std::atomic<float> peak{0};

  // ---------------------------------------------------------- sequencer --
  //
  // SQIA's pattern, played on the audio thread so the steps land on the
  // sample rather than whenever the main thread gets round to it. Written
  // from anywhere, cell by cell.

  static constexpr int kSteps = SQIA_SEQ_STEPS;
  static constexpr int kRows = SQIA_SEQ_ROWS;

  std::atomic<float> cells[kSteps * kRows];
  std::atomic<int> row_notes[kRows];
  std::atomic<float> bpm{120};
  std::atomic<float> length{0.5f};
  std::atomic<bool> playing{false};
  std::atomic<int> position{-1};

  bool was_playing = false;
  int step = -1;
  double samples_to_step = 0;

  struct PendingOff {
    int note;
    double samples;
  };
  PendingOff offs[kSteps * kRows];
  int off_count = 0;

  // Plaits runs at 48 kHz whatever the device does. At any other output
  // rate the stream is resampled on the way out (4-point Hermite), which
  // costs two samples of latency and keeps every pitch true.
  double output_rate = kRate;
  double resample_step = 1.0;
  double resample_phase = 0.0;
  float history_l[4] = {};
  float history_r[4] = {};

  // Blocks in a row with nothing sounding and nothing coming out. Past a
  // few seconds the reverb tail is gone and the block is skipped outright,
  // so a sound nobody is playing costs nothing.
  static constexpr int kIdleBlocks = static_cast<int>(3 * kRate / kBlock);
  int idle_blocks = kIdleBlocks;

  // Samples. The set in use belongs to the audio thread; a new one arrives
  // through `incoming`, and the one it replaces is parked in `retired` for
  // the host thread to free, so nothing is ever freed on the audio thread.
  SQIASampleSet* samples = nullptr;
  std::atomic<SQIASampleSet*> incoming{nullptr};
  static constexpr int kRetiredSlots = 8;
  std::atomic<SQIASampleSet*> retired[kRetiredSlots] = {};

  // Host thread only.
  void SweepRetired() {
    for (auto& slot : retired) delete slot.exchange(nullptr);
  }

  ~SQIASynth() {
    SweepRetired();
    delete incoming.exchange(nullptr);
    delete samples;
  }

  // Audio thread.
  void PickUpSamples() {
    SQIASampleSet* next = incoming.exchange(nullptr, std::memory_order_acquire);
    if (!next) return;
    for (Voice& v : voices) {
      if (v.zone >= 0) {
        v.active = false;
        v.zone = -1;
      }
    }
    // A set with no zones is how the host says "no samples".
    if (next->zones.empty()) {
      DeleteLater(next);
      next = nullptr;
    }
    if (samples) DeleteLater(samples);
    samples = next;
  }

  void DeleteLater(SQIASampleSet* set) {
    for (auto& slot : retired) {
      SQIASampleSet* expected = nullptr;
      if (slot.compare_exchange_strong(expected, set, std::memory_order_release)) return;
    }
    // Every slot full means the host has swapped eight sets without once
    // coming back; leaking one is better than freeing on this thread.
  }

  explicit SQIASynth(double rate) {
    if (rate > 0 && std::fabs(rate - kRate) > 0.5) {
      output_rate = rate;
      resample_step = kRate / rate;
    }
    for (int i = 0; i < SQIA_PARAM_COUNT; ++i) {
      params[i].store(kParams[i].default_value, std::memory_order_relaxed);
      spreads[i].store(0.0f, std::memory_order_relaxed);
    }
    for (Voice& v : voices) v.Init();
    for (auto& c : cells) c.store(0.0f, std::memory_order_relaxed);
    for (int r = 0; r < kRows; ++r) row_notes[r].store(48 + r, std::memory_order_relaxed);
    std::memset(reverb_ram, 0, sizeof(reverb_ram));
    reverb.Init(reverb_ram);
  }

  // ------------------------------------------------------------ events --

  void Start(Voice& v, int note, float velocity) {
    const bool retrigger = v.active;
    v.active = true;
    v.gate = true;
    v.note = note;
    v.velocity = velocity;
    v.started = ++clock;
    v.stage = Voice::kAttack;
    if (!retrigger) {
      v.env = 0;
      v.gain_l = v.gain_r = 0;
    }
    v.trigger_low = 1;
    v.silent_samples = 0;
    v.fade_blocks = 0;
    v.has_pending = false;
    v.pending_released = false;
    v.release_after_attack = false;
    for (float& r : v.roll) r = rng.Bipolar();

    v.zone = -1;
    v.sample_ended = false;
    if (static_cast<int>(Load(SQIA_PARAM_SOURCE)) == SQIA_SOURCE_SAMPLES && samples) {
      const std::vector<int>& c = samples->choices[std::min(std::max(note, 0), 127)];
      if (!c.empty()) {
        const int pick = static_cast<int>((rng.Bipolar() + 1) * 0.5f * c.size());
        v.zone = c[std::min(pick, static_cast<int>(c.size()) - 1)];
        const auto& sample = samples->samples[samples->zones[v.zone].sample];
        const float start = Rolled(
            SQIA_PARAM_SAMPLE_START, Load(SQIA_PARAM_SAMPLE_START),
            Spread(SQIA_PARAM_SAMPLE_START), v.roll[SQIA_PARAM_SAMPLE_START]);
        v.position = start * sample.frames();
        if (!retrigger) {
          v.svf_l[0] = v.svf_l[1] = v.svf_r[0] = v.svf_r[1] = 0;
        }
      } else {
        v.sample_ended = true;
      }
    }
  }

  void NoteOn(int note, float velocity) {
    const int polyphony = static_cast<int>(Load(SQIA_PARAM_POLYPHONY));

    // The same key again restarts its own voice.
    for (int i = 0; i < polyphony; ++i) {
      Voice& v = voices[i];
      if (v.active && v.gate && v.note == note && !v.has_pending) {
        Start(v, note, velocity);
        return;
      }
    }

    Voice* free_voice = nullptr;
    Voice* oldest_released = nullptr;
    Voice* oldest = nullptr;
    for (int i = 0; i < polyphony; ++i) {
      Voice& v = voices[i];
      if (!v.active) {
        free_voice = &v;
        break;
      }
      if (!v.gate && (!oldest_released || v.started < oldest_released->started)) {
        oldest_released = &v;
      }
      if (!oldest || v.started < oldest->started) oldest = &v;
    }

    if (free_voice) {
      Start(*free_voice, note, velocity);
      return;
    }
    Voice& victim = oldest_released ? *oldest_released : *oldest;
    victim.has_pending = true;
    victim.pending_note = note;
    victim.pending_velocity = velocity;
    victim.pending_released = false;
    victim.fade_blocks = kFadeBlocks;
    victim.gate = false;
    victim.started = ++clock;
  }

  void NoteOff(int note) {
    for (Voice& v : voices) {
      if (v.has_pending && v.pending_note == note) {
        v.pending_released = true;
        continue;
      }
      if (v.active && v.gate && v.note == note) {
        v.gate = false;
        if (v.stage != Voice::kIdle) v.stage = Voice::kRelease;
      }
    }
  }

  void AllOff() {
    for (Voice& v : voices) {
      if (v.has_pending) v.pending_released = true;
      if (v.gate) {
        v.gate = false;
        v.stage = Voice::kRelease;
      }
    }
  }

  void Panic() {
    for (Voice& v : voices) {
      v.active = false;
      v.gate = false;
      v.has_pending = false;
      v.stage = Voice::kIdle;
      v.env = 0;
      v.gain_l = v.gain_r = 0;
    }
    reverb.Clear();
  }

  // ---------------------------------------------------------- rendering --

  float Load(int p) const { return params[p].load(std::memory_order_relaxed); }
  float Spread(int p) const { return spreads[p].load(std::memory_order_relaxed); }

  void Render(float* left, float* right, int frames) {
    if (resample_step != 1.0) {
      RenderResampled(left, right, frames);
      return;
    }
    float peak_here = 0.0f;
    while (frames > 0) {
      if (block_position >= kBlock) {
        RenderBlock();
        block_position = 0;
      }
      const int n = std::min(frames, kBlock - block_position);
      for (int i = 0; i < n; ++i) {
        const float l = block_l[block_position + i];
        const float r = block_r[block_position + i];
        left[i] = l;
        right[i] = r;
        peak_here = std::max(peak_here, std::max(std::fabs(l), std::fabs(r)));
      }
      left += n;
      right += n;
      frames -= n;
      block_position += n;
    }
    float previous = peak.load(std::memory_order_relaxed);
    while (peak_here > previous &&
           !peak.compare_exchange_weak(previous, peak_here, std::memory_order_relaxed)) {
    }
  }

  void RenderResampled(float* left, float* right, int frames) {
    float peak_here = 0.0f;
    for (int i = 0; i < frames; ++i) {
      while (resample_phase >= 1.0) {
        resample_phase -= 1.0;
        if (block_position >= kBlock) {
          RenderBlock();
          block_position = 0;
        }
        for (int k = 0; k < 3; ++k) {
          history_l[k] = history_l[k + 1];
          history_r[k] = history_r[k + 1];
        }
        history_l[3] = block_l[block_position];
        history_r[3] = block_r[block_position];
        ++block_position;
      }
      const float t = static_cast<float>(resample_phase);
      left[i] = Hermite(history_l, t);
      right[i] = Hermite(history_r, t);
      peak_here = std::max(peak_here, std::max(std::fabs(left[i]), std::fabs(right[i])));
      resample_phase += resample_step;
    }
    float previous = peak.load(std::memory_order_relaxed);
    while (peak_here > previous &&
           !peak.compare_exchange_weak(previous, peak_here, std::memory_order_relaxed)) {
    }
  }

  // Between x[1] and x[2], t of the way.
  static float Hermite(const float* x, float t) {
    const float c0 = x[1];
    const float c1 = 0.5f * (x[2] - x[0]);
    const float c2 = x[0] - 2.5f * x[1] + 2.0f * x[2] - 0.5f * x[3];
    const float c3 = 0.5f * (x[3] - x[0]) + 1.5f * (x[1] - x[2]);
    return ((c3 * t + c2) * t + c1) * t + c0;
  }

  // Releases `note` after `samples`, replacing any release it already had
  // pending — a note restarted before its old release must not be cut short
  // by it.
  void HoldFor(int note, double samples) {
    for (int i = 0; i < off_count;) {
      if (offs[i].note == note) {
        offs[i] = offs[--off_count];
      } else {
        ++i;
      }
    }
    if (off_count < kSteps * kRows) offs[off_count++] = {note, samples};
  }

  void RenderBlock() {
    PickUpSamples();
    Event e;
    while (events.Pop(&e)) {
      switch (e.type) {
        case Event::kNoteOn:
          NoteOn(e.note, e.velocity);
          if (e.seconds > 0) {
            HoldFor(e.note, e.seconds * kRate);
          }
          break;
        case Event::kNoteOff: NoteOff(e.note); break;
        case Event::kAllOff: AllOff(); break;
        case Event::kPanic: Panic(); break;
      }
    }

    Sequence();

    bool any_active = false;
    for (const Voice& v : voices) any_active = any_active || v.active;
    if (!any_active && idle_blocks >= kIdleBlocks) {
      std::fill(block_l, block_l + kBlock, 0.0f);
      std::fill(block_r, block_r + kBlock, 0.0f);
      active_voices.store(0, std::memory_order_relaxed);
      return;
    }

    float p[SQIA_PARAM_COUNT];
    float s[SQIA_PARAM_COUNT];
    for (int i = 0; i < SQIA_PARAM_COUNT; ++i) {
      p[i] = Load(i);
      s[i] = Spread(i);
    }

    std::fill(block_l, block_l + kBlock, 0.0f);
    std::fill(block_r, block_r + kBlock, 0.0f);

    int sounding = 0;
    for (Voice& v : voices) {
      if (!v.active) continue;
      RenderVoice(v, p, s);
      if (v.active) ++sounding;
    }
    active_voices.store(sounding, std::memory_order_relaxed);

    reverb.set_amount(p[SQIA_PARAM_REVERB_MIX]);
    reverb.set_time(0.35f + 0.63f * p[SQIA_PARAM_REVERB_TIME]);
    reverb.set_lp(0.3f + 0.6f * p[SQIA_PARAM_REVERB_TONE]);
    reverb.set_diffusion(0.625f);
    reverb.set_input_gain(0.2f);
    reverb.Process(block_l, block_r, kBlock);

    float block_peak = 0.0f;
    for (int i = 0; i < kBlock; ++i) {
      block_peak = std::max(block_peak, std::fabs(block_l[i]) + std::fabs(block_r[i]));
    }
    idle_blocks = (sounding == 0 && block_peak < 1e-5f) ? idle_blocks + 1 : 0;

    for (int i = 0; i < kBlock; ++i) {
      block_l[i] = SoftCeiling(block_l[i]);
      block_r[i] = SoftCeiling(block_r[i]);
    }
  }

  void Sequence() {
    // Note-offs first, so a note ending on this block frees its voice for
    // one starting on it.
    for (int i = 0; i < off_count;) {
      offs[i].samples -= kBlock;
      if (offs[i].samples <= 0) {
        NoteOff(offs[i].note);
        offs[i] = offs[--off_count];
      } else {
        ++i;
      }
    }

    const bool play = playing.load(std::memory_order_relaxed);
    if (play != was_playing) {
      was_playing = play;
      if (play) {
        step = -1;
        samples_to_step = 0;
      } else {
        for (int i = 0; i < off_count; ++i) NoteOff(offs[i].note);
        off_count = 0;
        position.store(-1, std::memory_order_relaxed);
      }
    }
    if (!play) return;

    const double step_samples =
        kRate * 60.0 / Clamp(bpm.load(std::memory_order_relaxed), 20.0f, 400.0f) / 4.0;
    while (samples_to_step <= 0) {
      step = (step + 1) % kSteps;
      position.store(step, std::memory_order_relaxed);
      PlayStep(step, step_samples);
      samples_to_step += step_samples;
    }
    samples_to_step -= kBlock;
  }

  // SQIA's rule for a step: accents always sound, soft cells sound with a
  // chance that grows with their brightness, and every hit's velocity is
  // shimmered — so the pattern stays itself and no two passes are alike.
  void PlayStep(int step, double step_samples) {
    const double hold = step_samples * Clamp(length.load(std::memory_order_relaxed), 0.05f, 16.0f);
    for (int row = 0; row < kRows; ++row) {
      const float intensity = cells[step * kRows + row].load(std::memory_order_relaxed);
      if (intensity <= 0) continue;
      if (intensity < 1 && (rng.Bipolar() + 1) * 0.5f > 0.35f + 0.65f * intensity) continue;
      const float velocity = intensity * (0.72f + (rng.Bipolar() + 1) * 0.5f * 0.26f);
      const int note = row_notes[row].load(std::memory_order_relaxed);

      NoteOn(note, velocity);
      HoldFor(note, hold);
    }
  }

  void StepEnvelope(Voice& v, float attack, float decay, float sustain, float release) {
    // Decay and release are exponential and reach the target to within
    // −43 dB (a factor of 5 time constants) in the time asked for.
    switch (v.stage) {
      case Voice::kIdle:
        v.env = 0;
        break;
      case Voice::kAttack:
        v.env += kBlockTime / attack;
        if (v.env >= 1.0f) {
          v.env = 1.0f;
          v.stage = Voice::kDecay;
        }
        break;
      case Voice::kDecay:
        v.env = sustain + (v.env - sustain) * std::exp(-5.0f * kBlockTime / decay);
        if (std::fabs(v.env - sustain) < 1e-4f) v.stage = Voice::kSustain;
        break;
      case Voice::kSustain:
        v.env = sustain;
        break;
      case Voice::kRelease:
        v.env *= std::exp(-5.0f * kBlockTime / release);
        if (v.env < 1e-4f) {
          v.env = 0;
          v.stage = Voice::kIdle;
        }
        break;
    }
  }

  void RenderVoice(Voice& v, const float* p, const float* s) {
    auto value = [&](int param) { return Rolled(param, p[param], s[param], v.roll[param]); };

    if (v.release_after_attack && v.trigger_low == 0 && v.stage != Voice::kAttack) {
      v.release_after_attack = false;
      v.gate = false;
      v.stage = Voice::kRelease;
    }

    const int mode = static_cast<int>(p[SQIA_PARAM_AMP_MODE]);
    StepEnvelope(v, value(SQIA_PARAM_ATTACK), value(SQIA_PARAM_DECAY),
                 value(SQIA_PARAM_SUSTAIN), value(SQIA_PARAM_RELEASE));

    const float sensitivity = p[SQIA_PARAM_VELOCITY];
    const float velocity = 1.0f - sensitivity * (1.0f - Clamp(v.velocity, 0.0f, 1.0f));

    float xl[kBlock];
    float xr[kBlock];
    const bool sampled = v.zone >= 0 || static_cast<int>(p[SQIA_PARAM_SOURCE]) == SQIA_SOURCE_SAMPLES;
    if (sampled) {
      RenderSample(v, p, value, mode, xl, xr);
    } else {
      RenderPlaits(v, p, value, mode, velocity, xl, xr);
    }

    // Where the gains should be by the end of this block.
    const float level = std::pow(10.0f, value(SQIA_PARAM_LEVEL) / 20.0f);
    float amp = level;
    if (mode == SQIA_AMP_ADSR) amp *= v.env;
    if (mode == SQIA_AMP_PING || sampled) amp *= velocity;
    if (sampled && mode == SQIA_AMP_LPG) amp *= v.env;
    if (v.fade_blocks > 0) {
      --v.fade_blocks;
      amp *= static_cast<float>(v.fade_blocks) / kFadeBlocks;
    }
    const float pan = value(SQIA_PARAM_PAN);
    const float angle = (pan + 1.0f) * 0.25f * kPi;
    const float target_l = amp * std::cos(angle) * kSqrt2;
    const float target_r = amp * std::sin(angle) * kSqrt2;

    const float step_l = (target_l - v.gain_l) / kBlock;
    const float step_r = (target_r - v.gain_r) / kBlock;
    float gl = v.gain_l;
    float gr = v.gain_r;
    float voice_peak = 0.0f;
    for (int i = 0; i < kBlock; ++i) {
      voice_peak = std::max(voice_peak, std::max(std::fabs(xl[i]), std::fabs(xr[i])));
      gl += step_l;
      gr += step_r;
      block_l[i] += xl[i] * gl;
      block_r[i] += xr[i] * gr;
    }
    v.gain_l = target_l;
    v.gain_r = target_r;

    // Stolen voice: once faded, it becomes the new note.
    if (v.has_pending && v.fade_blocks == 0) {
      const bool released = v.pending_released;
      v.active = false;
      Start(v, v.pending_note, v.pending_velocity);
      v.release_after_attack = released;
      return;
    }

    // Retire the voice once nothing more can come out of it.
    if (voice_peak * amp < kSilence) {
      v.silent_samples += kBlock;
    } else {
      v.silent_samples = 0;
    }
    if (sampled && v.sample_ended) {
      v.active = false;
      v.zone = -1;
      v.gain_l = v.gain_r = 0;
      return;
    }
    if (!v.gate && !v.has_pending) {
      bool done = false;
      switch (mode) {
        case SQIA_AMP_ADSR: done = v.stage == Voice::kIdle; break;
        case SQIA_AMP_LPG:
          done = v.stage == Voice::kIdle && (sampled || v.silent_samples >= 2400);
          break;
        default: done = !sampled && v.silent_samples >= 4800; break;
      }
      if (done) {
        v.active = false;
        v.zone = -1;
        v.gain_l = v.gain_r = 0;
      }
    }
  }

  template <typename Value>
  void RenderPlaits(Voice& v, const float* p, Value value, int mode, float velocity,
                    float* xl, float* xr) {
    plaits::Patch patch = {};
    patch.note = p[SQIA_PARAM_TRANSPOSE] + value(SQIA_PARAM_FINE) / 100.0f + kTuningCorrection;
    patch.harmonics = value(SQIA_PARAM_HARMONICS);
    patch.timbre = value(SQIA_PARAM_TIMBRE);
    patch.morph = value(SQIA_PARAM_MORPH);
    patch.frequency_modulation_amount = value(SQIA_PARAM_ENV_TO_PITCH);
    patch.timbre_modulation_amount = value(SQIA_PARAM_ENV_TO_TIMBRE);
    patch.morph_modulation_amount = value(SQIA_PARAM_ENV_TO_MORPH);
    patch.engine = static_cast<int>(p[SQIA_PARAM_ENGINE]);
    patch.decay = value(SQIA_PARAM_LPG_DECAY);
    patch.lpg_colour = value(SQIA_PARAM_LPG_COLOUR);

    plaits::Modulations mod = {};
    mod.note = static_cast<float>(v.note);
    mod.trigger = (v.gate && v.trigger_low == 0) ? 1.0f : 0.0f;
    mod.trigger_patched = true;
    if (v.trigger_low > 0) --v.trigger_low;
    switch (mode) {
      case SQIA_AMP_ADSR:
        // The gate stays wide open; the VCA below does the shaping. Velocity
        // still reaches the engine as accent and a touch of brightness.
        mod.level_patched = true;
        mod.level = velocity;
        break;
      case SQIA_AMP_LPG:
        mod.level_patched = true;
        mod.level = v.env * velocity;
        break;
      default:
        mod.level_patched = false;
        break;
    }

    v.plaits.Render(patch, mod, v.frames, kBlock);

    const float aux = value(SQIA_PARAM_AUX_MIX);
    for (int i = 0; i < kBlock; ++i) {
      const float out = v.frames[i].out / 32768.0f;
      const float aux_out = v.frames[i].aux / 32768.0f;
      xl[i] = xr[i] = out + (aux_out - out) * aux;
    }
  }

  // A recording, repitched to the note, through a resonant low-pass. In
  // LPG mode the envelope sweeps the cutoff as well as the level, the way a
  // vactrol closes.
  template <typename Value>
  void RenderSample(Voice& v, const float* p, Value value, int mode, float* xl, float* xr) {
    if (v.trigger_low > 0) --v.trigger_low;
    if (v.zone < 0 || !samples || v.sample_ended) {
      std::fill(xl, xl + kBlock, 0.0f);
      std::fill(xr, xr + kBlock, 0.0f);
      v.sample_ended = true;
      return;
    }
    const auto& zone = samples->zones[v.zone];
    const auto& sample = samples->samples[zone.sample];
    const float* left = sample.left.data();
    const float* right = sample.right.empty() ? left : sample.right.data();
    const int frames = sample.frames();

    const float semitones = (static_cast<float>(v.note) - zone.root) * p[SQIA_PARAM_KEY_TRACK] +
                            p[SQIA_PARAM_TRANSPOSE] + value(SQIA_PARAM_FINE) / 100.0f;
    const double increment = sample.rate / kRate * std::pow(2.0, semitones / 12.0);

    float cutoff = value(SQIA_PARAM_CUTOFF);
    if (mode == SQIA_AMP_LPG) cutoff = 40.0f * std::pow(cutoff / 40.0f, v.env);
    cutoff = Clamp(cutoff, 20.0f, 0.45f * kRate);
    const float g = std::tan(kPi * cutoff / kRate);
    const float k = 2.0f - 1.94f * value(SQIA_PARAM_RESONANCE);
    const float a1 = 1.0f / (1.0f + g * (g + k));
    const float a2 = g * a1;
    const float a3 = g * a2;

    auto at = [&](const float* x, int i) { return (i >= 0 && i < frames) ? x[i] : 0.0f; };
    auto filter = [&](float* ic, float in) {
      const float v3 = in - ic[1];
      const float v1 = a1 * ic[0] + a2 * v3;
      const float v2 = ic[1] + a2 * ic[0] + a3 * v3;
      ic[0] = 2.0f * v1 - ic[0];
      ic[1] = 2.0f * v2 - ic[1];
      return v2;
    };

    for (int i = 0; i < kBlock; ++i) {
      if (v.position >= frames) {
        v.sample_ended = true;
        xl[i] = filter(v.svf_l, 0.0f);
        xr[i] = filter(v.svf_r, 0.0f);
        continue;
      }
      const int n = static_cast<int>(v.position);
      const float t = static_cast<float>(v.position - n);
      const float hl[4] = {at(left, n - 1), at(left, n), at(left, n + 1), at(left, n + 2)};
      const float hr[4] = {at(right, n - 1), at(right, n), at(right, n + 1), at(right, n + 2)};
      xl[i] = filter(v.svf_l, Hermite(hl, t));
      xr[i] = filter(v.svf_r, Hermite(hr, t));
      v.position += increment;
    }
  }
};

// ------------------------------------------------------------------ C API --

extern "C" {

bool sqia_param_info(int param, SQIAParamInfo* out) {
  if (param < 0 || param >= SQIA_PARAM_COUNT || !out) return false;
  *out = kParams[param];
  return true;
}

const char* sqia_engine_key(int engine) {
  if (engine < 0 || engine >= SQIA_ENGINE_COUNT) return nullptr;
  return kEngineKeys[engine];
}

SQIASynth* sqia_synth_create(void) { return sqia_synth_create_at(SQIA_SAMPLE_RATE); }

SQIASynth* sqia_synth_create_at(double output_rate) {
  return new (std::nothrow) SQIASynth(output_rate);
}

void sqia_synth_destroy(SQIASynth* synth) { delete synth; }

SQIASampleSet* sqia_samples_create(void) { return new (std::nothrow) SQIASampleSet(); }

void sqia_samples_destroy(SQIASampleSet* set) { delete set; }

int sqia_samples_add(
    SQIASampleSet* set, const float* left, const float* right, int frames, double sample_rate) {
  if (!set || !left || frames <= 0 || sample_rate <= 0) return -1;
  SQIASampleSet::Sample sample;
  sample.left.assign(left, left + frames);
  if (right) sample.right.assign(right, right + frames);
  sample.rate = sample_rate;
  set->samples.push_back(std::move(sample));
  return static_cast<int>(set->samples.size()) - 1;
}

void sqia_samples_map(SQIASampleSet* set, int sample, int low_note, int high_note, float root) {
  if (!set || sample < 0 || sample >= static_cast<int>(set->samples.size())) return;
  set->zones.push_back({sample, std::max(0, std::min(low_note, high_note)),
                        std::min(127, std::max(low_note, high_note)), root});
}

void sqia_samples_lay_out(SQIASampleSet* set, SQIASampleLayout layout, const float* roots) {
  if (!set) return;
  set->zones.clear();
  const int n = static_cast<int>(set->samples.size());
  if (n == 0) return;

  if (layout == SQIA_LAYOUT_KIT || !roots) {
    for (int octave = 0; octave <= 10; ++octave) {
      for (int i = 0; i < n; ++i) {
        const int low = octave * 12 + i * 12 / n;
        const int high = octave * 12 + std::max(i * 12 / n, (i + 1) * 12 / n - 1);
        if (low > 127) continue;
        set->zones.push_back({i, low, std::min(high, 127), static_cast<float>(low)});
      }
    }
    return;
  }

  std::vector<int> order(n);
  for (int i = 0; i < n; ++i) order[i] = i;
  std::sort(order.begin(), order.end(), [&](int a, int b) { return roots[a] < roots[b]; });

  // Group recordings of the same note, then split the keyboard halfway
  // between neighbouring groups.
  std::vector<std::vector<int>> groups;
  for (int i : order) {
    if (!groups.empty() && std::round(roots[i] - roots[groups.back().front()]) == 0) {
      groups.back().push_back(i);
    } else {
      groups.push_back({i});
    }
  }
  const int count = static_cast<int>(groups.size());
  for (int g = 0; g < count; ++g) {
    const float root = std::round(roots[groups[g].front()]);
    const float below = g > 0 ? std::round(roots[groups[g - 1].front()]) : -1000;
    const float above = g < count - 1 ? std::round(roots[groups[g + 1].front()]) : 1000;
    const int low = g == 0 ? 0 : static_cast<int>(std::floor((below + root) / 2)) + 1;
    const int high = g == count - 1 ? 127 : static_cast<int>(std::floor((root + above) / 2));
    for (int i : groups[g]) set->zones.push_back({i, low, high, roots[i]});
  }
}

void sqia_synth_set_samples(SQIASynth* synth, SQIASampleSet* set) {
  if (!synth) {
    delete set;
    return;
  }
  synth->SweepRetired();
  if (!set) set = new (std::nothrow) SQIASampleSet();  // an empty set clears
  if (!set) return;
  set->Build();
  // Replaces one the audio thread never picked up, which is then ours.
  delete synth->incoming.exchange(set, std::memory_order_release);
}

void sqia_synth_set_param(SQIASynth* synth, int param, float value) {
  if (!synth || param < 0 || param >= SQIA_PARAM_COUNT) return;
  const SQIAParamInfo& info = kParams[param];
  if (info.integer) value = std::round(value);
  synth->params[param].store(Clamp(value, info.min, info.max), std::memory_order_relaxed);
}

float sqia_synth_get_param(const SQIASynth* synth, int param) {
  if (!synth || param < 0 || param >= SQIA_PARAM_COUNT) return 0;
  return synth->Load(param);
}

void sqia_synth_set_spread(SQIASynth* synth, int param, float spread) {
  if (!synth || param < 0 || param >= SQIA_PARAM_COUNT) return;
  if (!kParams[param].spreadable) spread = 0;
  synth->spreads[param].store(Clamp(spread, 0.0f, 1.0f), std::memory_order_relaxed);
}

float sqia_synth_get_spread(const SQIASynth* synth, int param) {
  if (!synth || param < 0 || param >= SQIA_PARAM_COUNT) return 0;
  return synth->Spread(param);
}

void sqia_synth_note_on(SQIASynth* synth, int note, float velocity) {
  if (!synth || note < 0 || note > 127) return;
  synth->events.Push({Event::kNoteOn, static_cast<uint8_t>(note), Clamp(velocity, 0.0f, 1.0f), 0});
}

void sqia_synth_note_on_for(SQIASynth* synth, int note, float velocity, float seconds) {
  if (!synth || note < 0 || note > 127) return;
  synth->events.Push(
      {Event::kNoteOn, static_cast<uint8_t>(note), Clamp(velocity, 0.0f, 1.0f), std::max(seconds, 0.001f)});
}

void sqia_synth_note_off(SQIASynth* synth, int note) {
  if (!synth || note < 0 || note > 127) return;
  synth->events.Push({Event::kNoteOff, static_cast<uint8_t>(note), 0, 0});
}

void sqia_synth_all_notes_off(SQIASynth* synth) {
  if (synth) synth->events.Push({Event::kAllOff, 0, 0, 0});
}

void sqia_synth_panic(SQIASynth* synth) {
  if (synth) synth->events.Push({Event::kPanic, 0, 0, 0});
}

void sqia_synth_render(SQIASynth* synth, float* left, float* right, int frames) {
  if (!synth) {
    std::memset(left, 0, sizeof(float) * frames);
    std::memset(right, 0, sizeof(float) * frames);
    return;
  }
  synth->Render(left, right, frames);
}

void sqia_seq_set_cell(SQIASynth* synth, int step, int row, float intensity) {
  if (!synth || step < 0 || step >= SQIA_SEQ_STEPS || row < 0 || row >= SQIA_SEQ_ROWS) return;
  synth->cells[step * SQIA_SEQ_ROWS + row].store(Clamp(intensity, 0.0f, 1.0f), std::memory_order_relaxed);
}

void sqia_seq_set_row_note(SQIASynth* synth, int row, int note) {
  if (!synth || row < 0 || row >= SQIA_SEQ_ROWS) return;
  synth->row_notes[row].store(std::min(std::max(note, 0), 127), std::memory_order_relaxed);
}

void sqia_seq_set_tempo(SQIASynth* synth, float bpm) {
  if (synth) synth->bpm.store(bpm, std::memory_order_relaxed);
}

void sqia_seq_set_length(SQIASynth* synth, float steps) {
  if (synth) synth->length.store(steps, std::memory_order_relaxed);
}

void sqia_seq_set_playing(SQIASynth* synth, bool playing) {
  if (synth) synth->playing.store(playing, std::memory_order_relaxed);
}

int sqia_seq_position(const SQIASynth* synth) {
  return synth ? synth->position.load(std::memory_order_relaxed) : -1;
}

int sqia_synth_active_voices(const SQIASynth* synth) {
  return synth ? synth->active_voices.load(std::memory_order_relaxed) : 0;
}

float sqia_synth_take_peak(SQIASynth* synth) {
  return synth ? synth->peak.exchange(0.0f, std::memory_order_relaxed) : 0;
}

}  // extern "C"
