// Just enough atomics for one lock-free queue.
//
// Swift's own Synchronization.Atomic needs iOS 18, and SQIA targets iOS 17;
// swift-atomics would do but this is the whole of what the audio queue needs,
// so it stays a dependency-free target. Acquire/release is exactly the
// pairing a single-producer, single-consumer ring buffer calls for: the
// consumer's acquire load of the write index orders it after the producer's
// release store, so the slot's contents are visible once the index is.

#ifndef CSQIA_ATOMICS_H
#define CSQIA_ATOMICS_H

#include <stdatomic.h>
#include <stdint.h>

typedef struct {
    _Atomic uint64_t value;
} SQIAAtomicUInt64;

static inline void SQIAAtomicInit(SQIAAtomicUInt64 *slot, uint64_t value) {
    atomic_init(&slot->value, value);
}

/// Reads a value another thread may be writing; no ordering implied.
static inline uint64_t SQIAAtomicLoadRelaxed(SQIAAtomicUInt64 *slot) {
    return atomic_load_explicit(&slot->value, memory_order_relaxed);
}

/// Reads a value and orders everything the writer did before its release
/// store after this load.
static inline uint64_t SQIAAtomicLoadAcquire(SQIAAtomicUInt64 *slot) {
    return atomic_load_explicit(&slot->value, memory_order_acquire);
}

/// Publishes a value, and with it every write made before this call.
static inline void SQIAAtomicStoreRelease(SQIAAtomicUInt64 *slot, uint64_t value) {
    atomic_store_explicit(&slot->value, value, memory_order_release);
}

#endif /* CSQIA_ATOMICS_H */
