// SQIASound — the synth core shared by SQIA Lab and SQIA itself.
//
// A plain C interface over C++, so Swift reaches it without C++ interop and a
// JNI shim on Android can wrap it the same way later. The voice is the Plaits
// macro-oscillator (MIT), eight of them for polyphony, into the Rings reverb.
//
// Threading: one thread renders (the audio callback), one other thread sends
// notes and parameters. Parameters are atomics and can be written from
// anywhere; notes go through a single-producer queue, so they must all come
// from the same thread — the app funnels MIDI onto the main thread for this.
//
// The engine runs at 48 kHz, which is what Plaits is written for. Created
// for another output rate, it resamples on the way out.

#ifndef SQIA_SOUND_H_
#define SQIA_SOUND_H_

#include <stdbool.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#define SQIA_SAMPLE_RATE 48000
#define SQIA_MAX_VOICES 8
#define SQIA_ENGINE_COUNT 24

/// Every parameter a preset can hold. The numbers are indices into the
/// engine's table and may be reordered; the keys returned by
/// `sqia_param_info` are what presets store, and those never change.
typedef enum {
  SQIA_PARAM_ENGINE = 0,
  SQIA_PARAM_HARMONICS,
  SQIA_PARAM_TIMBRE,
  SQIA_PARAM_MORPH,
  SQIA_PARAM_ENV_TO_PITCH,
  SQIA_PARAM_ENV_TO_TIMBRE,
  SQIA_PARAM_ENV_TO_MORPH,
  SQIA_PARAM_LPG_DECAY,
  SQIA_PARAM_LPG_COLOUR,
  SQIA_PARAM_AMP_MODE,
  SQIA_PARAM_ATTACK,
  SQIA_PARAM_DECAY,
  SQIA_PARAM_SUSTAIN,
  SQIA_PARAM_RELEASE,
  SQIA_PARAM_VELOCITY,
  SQIA_PARAM_AUX_MIX,
  SQIA_PARAM_TRANSPOSE,
  SQIA_PARAM_FINE,
  SQIA_PARAM_PAN,
  SQIA_PARAM_LEVEL,
  SQIA_PARAM_POLYPHONY,
  SQIA_PARAM_REVERB_MIX,
  SQIA_PARAM_REVERB_TIME,
  SQIA_PARAM_REVERB_TONE,
  /// Plaits, or the loaded samples.
  SQIA_PARAM_SOURCE,
  // Samples only.
  SQIA_PARAM_SAMPLE_START,
  SQIA_PARAM_CUTOFF,
  SQIA_PARAM_RESONANCE,
  SQIA_PARAM_KEY_TRACK,
  SQIA_PARAM_COUNT
} SQIAParam;

typedef enum {
  SQIA_SOURCE_PLAITS = 0,
  SQIA_SOURCE_SAMPLES = 1,
} SQIASource;

/// How the amplitude is shaped.
typedef enum {
  /// The ADSR drives a clean VCA after the voice.
  SQIA_AMP_ADSR = 0,
  /// The ADSR drives Plaits' low-pass gate, so the tone closes as it fades.
  /// With samples, the envelope sweeps the filter the same way.
  SQIA_AMP_LPG = 1,
  /// No ADSR: the gate pings the low-pass gate, LPG DECAY sets the length.
  /// Samples simply play to their end.
  SQIA_AMP_PING = 2,
} SQIAAmpMode;

typedef enum {
  SQIA_UNIT_NONE = 0,   // 0…1, shown as a percentage
  SQIA_UNIT_BIPOLAR,    // −1…1, shown as a signed percentage
  SQIA_UNIT_SECONDS,
  SQIA_UNIT_DECIBELS,
  SQIA_UNIT_SEMITONES,
  SQIA_UNIT_CENTS,
  SQIA_UNIT_COUNT,      // a whole number of things
  SQIA_UNIT_CHOICE,     // an index into a list the host names
  SQIA_UNIT_HERTZ,
} SQIAUnit;

typedef struct {
  /// Stable storage key, e.g. "harmonics".
  const char* key;
  const char* name;
  float min;
  float max;
  float default_value;
  SQIAUnit unit;
  /// Knob travel is logarithmic in value (times).
  bool logarithmic;
  /// Snaps to whole numbers.
  bool integer;
  /// Can be re-rolled per note within a spread.
  bool spreadable;
} SQIAParamInfo;

typedef struct SQIASynth SQIASynth;

/// Recordings and the notes they answer, for SQIA_SOURCE_SAMPLES. Built on
/// any thread, then handed to a synth, which owns it from then on.
typedef struct SQIASampleSet SQIASampleSet;

bool sqia_param_info(int param, SQIAParamInfo* out);
/// Stable storage key of an engine, e.g. "virtual_analog"; NULL if out of range.
const char* sqia_engine_key(int engine);

/// At 48 kHz.
SQIASynth* sqia_synth_create(void);
/// Rendering at `output_rate`, resampled from 48 kHz when it differs.
SQIASynth* sqia_synth_create_at(double output_rate);
void sqia_synth_destroy(SQIASynth* synth);

/// Clamped to the parameter's range. Safe from any thread.
void sqia_synth_set_param(SQIASynth* synth, int param, float value);
float sqia_synth_get_param(const SQIASynth* synth, int param);

/// How far each note may wander from the knob, as a fraction of the knob's
/// full travel (0 = always the same, 0.5 = anywhere within half the range
/// either side). Rolled once per note. Safe from any thread.
void sqia_synth_set_spread(SQIASynth* synth, int param, float spread);
float sqia_synth_get_spread(const SQIASynth* synth, int param);

/// Note events, from one thread only.
void sqia_synth_note_on(SQIASynth* synth, int note, float velocity);
/// A note that releases itself after `seconds` — what a sequencer wants.
void sqia_synth_note_on_for(SQIASynth* synth, int note, float velocity, float seconds);
void sqia_synth_note_off(SQIASynth* synth, int note);
/// Releases every held note, letting the tails ring.
void sqia_synth_all_notes_off(SQIASynth* synth);
/// Silences everything at once, tails included.
void sqia_synth_panic(SQIASynth* synth);

/// Fills `frames` samples of each channel. Audio thread only; never
/// allocates or locks.
void sqia_synth_render(SQIASynth* synth, float* left, float* right, int frames);

// ------------------------------------------------------------ samples --

SQIASampleSet* sqia_samples_create(void);
/// Only for a set never handed to a synth.
void sqia_samples_destroy(SQIASampleSet* set);
/// Copies a recording in, at its own rate; `right` may be NULL for mono.
/// Returns its index for `sqia_samples_map`.
int sqia_samples_add(
    SQIASampleSet* set, const float* left, const float* right, int frames, double sample_rate);
/// A recording answers notes `low_note`…`high_note`, sounding its own pitch
/// at `root` (fractional, so a slightly sharp recording plays in tune).
/// Where zones overlap, each note picks one of them at random — two takes
/// of the same note become a round robin.
void sqia_samples_map(SQIASampleSet* set, int sample, int low_note, int high_note, float root);
typedef enum {
  /// Each recording answers the notes nearest its root and is repitched to
  /// them; recordings within half a semitone of each other take turns.
  SQIA_LAYOUT_PITCHED = 0,
  /// The recordings are spread across the twelve keys of every octave, in
  /// the order they were added, each at its own pitch.
  SQIA_LAYOUT_KIT = 1,
} SQIASampleLayout;

/// Maps every recording added so far, replacing any mapping made before.
/// `roots` holds one root per recording, in the order they were added; a
/// kit ignores it and may pass NULL.
void sqia_samples_lay_out(SQIASampleSet* set, SQIASampleLayout layout, const float* roots);
/// Swaps the synth's samples. Voices playing the old ones stop. The synth
/// frees sets it is done with; NULL just removes them.
void sqia_synth_set_samples(SQIASynth* synth, SQIASampleSet* set);

// ---------------------------------------------------------- sequencer --
//
// SQIA's pattern: 16 steps of sixteenths, 12 rows, each cell an intensity
// (0 empty, 1 accent, in between a soft cell that sounds only sometimes).
// Runs on the audio thread; everything here is safe from any thread.

#define SQIA_SEQ_STEPS 16
#define SQIA_SEQ_ROWS 12

void sqia_seq_set_cell(SQIASynth* synth, int step, int row, float intensity);
/// The MIDI note a row plays — the host maps rows onto its key and scale.
void sqia_seq_set_row_note(SQIASynth* synth, int row, int note);
void sqia_seq_set_tempo(SQIASynth* synth, float bpm);
/// How long each note is held, in steps.
void sqia_seq_set_length(SQIASynth* synth, float steps);
/// Starting always begins at step 0.
void sqia_seq_set_playing(SQIASynth* synth, bool playing);
/// The step that last sounded, or -1 when stopped.
int sqia_seq_position(const SQIASynth* synth);

/// For meters: voices currently sounding, and the output peak since the
/// last call (reading resets it).
int sqia_synth_active_voices(const SQIASynth* synth);
float sqia_synth_take_peak(SQIASynth* synth);

#ifdef __cplusplus
}
#endif

#endif  // SQIA_SOUND_H_
