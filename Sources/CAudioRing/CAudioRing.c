#include "CAudioRing.h"
#include <stdatomic.h>
#include <stdlib.h>

typedef struct { float value; double time; } Sample;
struct SWAudioRing {
    Sample *samples;
    size_t capacity;
    _Atomic size_t head;
    _Atomic size_t tail;
    _Atomic uint64_t dropped;
    _Atomic size_t lastBlock;
};

SWAudioRing *SWAudioRingCreate(size_t capacity) {
    if (capacity == 0) return NULL;
    SWAudioRing *ring = calloc(1, sizeof(*ring));
    if (!ring) return NULL;
    ring->samples = calloc(capacity, sizeof(Sample));
    if (!ring->samples) { free(ring); return NULL; }
    ring->capacity = capacity;
    atomic_init(&ring->head, 0); atomic_init(&ring->tail, 0);
    atomic_init(&ring->dropped, 0); atomic_init(&ring->lastBlock, 0);
    return ring;
}
void SWAudioRingDestroy(SWAudioRing *ring) {
    if (ring) { free(ring->samples); free(ring); }
}
void SWAudioRingWrite(SWAudioRing *ring, const float *input, size_t count, size_t stride,
                      double startTime, double sampleRate) {
    atomic_store_explicit(&ring->lastBlock, count, memory_order_relaxed);
    const size_t head = atomic_load_explicit(&ring->head, memory_order_relaxed);
    const size_t tail = atomic_load_explicit(&ring->tail, memory_order_acquire);
    if (count > ring->capacity - (head - tail)) {
        atomic_fetch_add_explicit(&ring->dropped, count, memory_order_relaxed);
        return;
    }
    for (size_t i = 0; i < count; i++) {
        ring->samples[(head + i) % ring->capacity] = (Sample){input[i * stride], startTime + (double)(i + 1) / sampleRate};
    }
    atomic_store_explicit(&ring->head, head + count, memory_order_release);
}
size_t SWAudioRingRead(SWAudioRing *ring, float *output, size_t maximum, double *endTime) {
    const size_t tail = atomic_load_explicit(&ring->tail, memory_order_relaxed);
    const size_t head = atomic_load_explicit(&ring->head, memory_order_acquire);
    const size_t count = head - tail < maximum ? head - tail : maximum;
    for (size_t i = 0; i < count; i++) { output[i] = ring->samples[(tail + i) % ring->capacity].value; }
    if (count > 0) { *endTime = ring->samples[(tail + count - 1) % ring->capacity].time; }
    atomic_store_explicit(&ring->tail, tail + count, memory_order_release);
    return count;
}
size_t SWAudioRingAvailable(SWAudioRing *ring) {
    const size_t tail = atomic_load_explicit(&ring->tail, memory_order_relaxed);
    return atomic_load_explicit(&ring->head, memory_order_acquire) - tail;
}
uint64_t SWAudioRingDropped(SWAudioRing *ring) { return atomic_load_explicit(&ring->dropped, memory_order_relaxed); }
size_t SWAudioRingLastBlockSize(SWAudioRing *ring) { return atomic_load_explicit(&ring->lastBlock, memory_order_relaxed); }
