// How a note gets from the transport to the speaker.
//
// The transport runs on a timer and decides what sounds when; the render
// thread turns that into samples and must never wait for anything. A
// single-producer, single-consumer ring buffer is the whole of what passes
// between them: the transport writes a slot then publishes the index, and the
// render thread reads the index then the slot.

import CSQIAAtomics

/// A wait-free queue between one writer and one reader.
///
/// Capacity is rounded up to a power of two so the wrap is a mask rather
/// than a division. A full queue drops the write and says so: an event lost
/// under that much pressure is one note, and blocking the transport — or
/// worse, the render thread — would cost far more.
public final class AudioEventQueue: @unchecked Sendable {
    private let mask: UInt64
    private let slots: UnsafeMutablePointer<AudioEvent>
    private let writeIndex: UnsafeMutablePointer<SQIAAtomicUInt64>
    private let readIndex: UnsafeMutablePointer<SQIAAtomicUInt64>

    public private(set) var capacity: Int

    public init(capacity requested: Int = 256) {
        var size = 1
        while size < max(2, requested) { size <<= 1 }
        capacity = size
        mask = UInt64(size - 1)

        slots = .allocate(capacity: size)
        slots.initialize(repeating: AudioEvent(kind: .silence, frame: 0), count: size)
        writeIndex = .allocate(capacity: 1)
        readIndex = .allocate(capacity: 1)
        SQIAAtomicInit(writeIndex, 0)
        SQIAAtomicInit(readIndex, 0)
    }

    deinit {
        slots.deinitialize(count: capacity)
        slots.deallocate()
        writeIndex.deallocate()
        readIndex.deallocate()
    }

    /// Producer side. Returns false when the queue is full.
    @discardableResult
    public func push(_ event: AudioEvent) -> Bool {
        let write = SQIAAtomicLoadRelaxed(writeIndex)
        let read = SQIAAtomicLoadAcquire(readIndex)
        if write &- read >= UInt64(capacity) { return false }

        slots[Int(write & mask)] = event
        // Publishes the slot's contents along with the index.
        SQIAAtomicStoreRelease(writeIndex, write &+ 1)
        return true
    }

    /// Consumer side — the render thread. Never allocates, never waits.
    public func pop() -> AudioEvent? {
        let read = SQIAAtomicLoadRelaxed(readIndex)
        let write = SQIAAtomicLoadAcquire(writeIndex)
        if read == write { return nil }

        let event = slots[Int(read & mask)]
        SQIAAtomicStoreRelease(readIndex, read &+ 1)
        return event
    }

    /// What the next `pop` would return, without consuming it. Lets the
    /// renderer look at an event's frame and leave it for a later block.
    public func peek() -> AudioEvent? {
        let read = SQIAAtomicLoadRelaxed(readIndex)
        let write = SQIAAtomicLoadAcquire(writeIndex)
        if read == write { return nil }
        return slots[Int(read & mask)]
    }

    public var isEmpty: Bool {
        SQIAAtomicLoadRelaxed(readIndex) == SQIAAtomicLoadAcquire(writeIndex)
    }

    public var count: Int {
        Int(SQIAAtomicLoadAcquire(writeIndex) &- SQIAAtomicLoadRelaxed(readIndex))
    }
}
