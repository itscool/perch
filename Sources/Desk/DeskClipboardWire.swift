import Foundation
import CryptoKit
import Compression

/// How a copy crosses the desk.
///
/// The channel is the desk's own TLS 1.3 connection with pinned peer identities.
/// There is deliberately no second encryption layer inside it: the only way in
/// is that pinned, mutually authenticated channel between Macs that were paired
/// by hand, so per-chunk keys would add failure modes without answering any
/// threat the channel leaves open. What this layer adds is integrity of the
/// reassembly and a packet shape that says nothing about the copy:
///
/// - A manifest describes the content (transfer, copy, lengths, chunk count,
///   compression, SHA-256 of the content) and every chunk is bound to it. Both
///   are authenticated with HMAC-SHA256 under a fresh random key that the asking
///   Mac sends inside the pinned channel, so a chunk from another transfer, at
///   another index or in another order is refused, and the content digest is
///   checked once everything has arrived.
/// - Compression before encryption leaks length (the CRIME family). The rule:
///   compress only above a threshold, and always pad to a size bucket.
/// - One envelope for every kind of copy. Control messages are exactly 1 KB and
///   every chunk exactly 64 KB, whatever it carries; the kind of copy is inside
///   the padded content, never in a header.
/// - Exactly one format is negotiated per peer, and anything else is refused.
enum DeskClipboardWire {
    /// The tag that routes a desk application message here. A Perch without
    /// clipboard support routes an unknown tag nowhere and ignores it; see
    /// `DeskClipboard.send` for why nothing but a hello is ever sent to it.
    static let prefix = Data("Perch clipboard v1\0".utf8)
    /// Formats this build speaks, newest last. One is chosen per peer.
    static let formats: [UInt8] = [1]
    /// The envelope layout. The hello keeps this layout forever, so two Macs
    /// can always find out what they have in common.
    static let layout: UInt8 = 1
    static let controlSize = 1024
    static let chunkEnvelopeSize = 64 * 1024
    static let sizes = [controlSize, chunkEnvelopeSize]
    /// Content bytes per chunk. Every chunk envelope is padded to 64 KB anyway.
    static let chunkSize = 60 * 1024
    /// Content smaller than this is never compressed.
    static let compressionThreshold = 32 * 1024
    /// Padded content never goes below this, so all small copies look alike.
    static let minimumBucket = 4 * 1024

    enum Failure: Error, Equatable {
        case malformed(String)
        /// A message in a format other than the one negotiated with that Mac.
        case format
    }

    /// Above this, buckets are finer, so a large file is padded by at most a
    /// sixteenth rather than a quarter.
    static let fineBuckets = 64 * 1024 * 1024

    /// The padded length for content of `length` bytes: four steps per doubling
    /// (1, 1.25, 1.5 and 1.75 times a power of two), never below 4 KB, and
    /// sixteen steps per doubling above 64 MB. Every length inside a bucket
    /// produces exactly the same bytes on the wire.
    static func bucket(_ length: Int) -> Int {
        guard length > minimumBucket else { return minimumBucket }
        var base = minimumBucket
        while base <= length / 2 { base *= 2 }
        let steps = base >= fineBuckets ? 16 : 4
        for step in steps...(2 * steps) where base / steps * step >= length { return base / steps * step }
        return base * 2
    }

    // MARK: Envelope

    static func encode(_ message: DeskClipboardMessage, format: UInt8) throws -> Data {
        var w = Writer()
        w.u8(layout)
        if case .hello = message { w.u8(0) } else { w.u8(format) }
        message.write(into: &w)
        guard let size = sizes.first(where: { $0 >= w.data.count }) else { throw Failure.malformed("message too large") }
        return w.data + Data(count: size - w.data.count)
    }

    /// `format` is the one negotiated with the sender, nil before a hello.
    static func decode(_ envelope: Data, format: UInt8?) throws -> DeskClipboardMessage {
        let bytes = Data(envelope)
        guard sizes.contains(bytes.count) else { throw Failure.malformed("envelope size") }
        var r = Reader(bytes)
        guard try r.u8() == layout else { throw Failure.malformed("envelope layout") }
        let headerFormat = try r.u8()
        let message = try DeskClipboardMessage.read(from: &r)
        if case .hello = message { guard headerFormat == 0 else { throw Failure.malformed("hello format") } }
        else { guard let format, headerFormat == format else { throw Failure.format } }
        // Canonical padding: all zero, and in the smallest envelope that fits.
        guard r.remaining.allSatisfy({ $0 == 0 }) else { throw Failure.malformed("padding not empty") }
        guard sizes.first(where: { $0 >= r.consumed }) == bytes.count else { throw Failure.malformed("envelope not minimal") }
        return message
    }

    // MARK: Compression, bounded both ways

    static func compress(_ input: Data) -> Data? {
        guard input.count >= compressionThreshold else { return nil }
        var output = Data(count: input.count)
        let written = output.withUnsafeMutableBytes { dst in
            input.withUnsafeBytes { src in
                compression_encode_buffer(dst.bindMemory(to: UInt8.self).baseAddress!, input.count,
                                          src.bindMemory(to: UInt8.self).baseAddress!, input.count, nil, COMPRESSION_LZFSE)
            }
        }
        guard written > 0, written < input.count else { return nil }
        output.count = written
        return output
    }

    /// Decompress into exactly `length` bytes. The output buffer is the declared
    /// length plus one byte, so content that would expand past what the manifest
    /// promised (a decompression bomb) is detected without ever being expanded.
    static func decompress(_ input: Data, exactly length: Int) -> Data? {
        guard length > 0, !input.isEmpty else { return nil }
        var output = Data(count: length + 1)
        let written = output.withUnsafeMutableBytes { dst in
            input.withUnsafeBytes { src in
                compression_decode_buffer(dst.bindMemory(to: UInt8.self).baseAddress!, length + 1,
                                          src.bindMemory(to: UInt8.self).baseAddress!, input.count, nil, COMPRESSION_LZFSE)
            }
        }
        guard written == length else { return nil }
        output.count = length
        return output
    }

    // MARK: Sealing and reassembly

    /// Content ready to send: its manifest and the padded bytes it describes.
    struct Parcel {
        let manifest: DeskClipboardManifest
        let stream: Data
        let format: UInt8
        func chunk(_ index: UInt32, key: SymmetricKey) -> DeskClipboardMessage {
            let start = Int(index) * chunkSize
            let piece = stream.subdata(in: start..<min(stream.count, start + chunkSize))
            return .chunk(transfer: manifest.transfer, index: index, data: piece,
                          mac: chunkMAC(format: format, transfer: manifest.transfer, index: index, count: manifest.chunkCount, data: piece, key: key))
        }
    }

    static func seal(_ payload: Data, transfer: UUID, copy: UUID, key: SymmetricKey, format: UInt8) -> Parcel {
        let compressed = compress(payload)
        let encoded = compressed ?? payload
        let padded = bucket(encoded.count)
        let stream = encoded + Data(count: padded - encoded.count)
        var manifest = DeskClipboardManifest(transfer: transfer, copy: copy, payloadLength: UInt64(payload.count),
                                             encodedLength: UInt64(encoded.count), paddedLength: UInt64(padded),
                                             chunkCount: UInt32((padded + chunkSize - 1) / chunkSize), compressed: compressed != nil,
                                             digest: Data(SHA256.hash(data: payload)), mac: Data())
        manifest.mac = manifestMAC(manifest, format: format, key: key)
        return Parcel(manifest: manifest, stream: stream, format: format)
    }

    /// The manifest for the stream of a copy's files: their bytes one after
    /// another, as they are on disk, never compressed, padded to their bucket.
    /// Its digest is the SHA-256 of the list the receiving Mac already checked,
    /// binding the stream to exactly that list; each file's own SHA-256 follows
    /// it in a `fileDigests` message.
    static func treeManifest(transfer: UUID, copy: UUID, total: UInt64, list: Data, key: SymmetricKey, format: UInt8) -> DeskClipboardManifest {
        let padded = UInt64(bucket(Int(clamping: total)))
        var manifest = DeskClipboardManifest(transfer: transfer, copy: copy, payloadLength: total, encodedLength: total, paddedLength: padded,
                                             chunkCount: UInt32((padded + UInt64(chunkSize) - 1) / UInt64(chunkSize)), compressed: false,
                                             digest: Data(SHA256.hash(data: list)), mac: Data())
        manifest.mac = manifestMAC(manifest, format: format, key: key)
        return manifest
    }

    static let manifestDomain = Data("Perch clipboard manifest v1\0".utf8)
    static let chunkDomain = Data("Perch clipboard chunk v1\0".utf8)
    static let fileDigestDomain = Data("Perch clipboard file digests v1\0".utf8)
    /// File digests in one message: 24 fill a 1 KB control envelope comfortably.
    static let digestsPerMessage = 24

    static func fileDigestMAC(format: UInt8, transfer: UUID, first: UInt32, digests: [Data], key: SymmetricKey) -> Data {
        var w = Writer()
        w.fixed(fileDigestDomain); w.u8(format); w.uuid(transfer); w.u32(first); w.u8(UInt8(clamping: digests.count)); digests.forEach { w.fixed($0) }
        return Data(HMAC<SHA256>.authenticationCode(for: w.data, using: key))
    }

    static func manifestMAC(_ m: DeskClipboardManifest, format: UInt8, key: SymmetricKey) -> Data {
        var w = Writer()
        w.fixed(manifestDomain); w.u8(format); m.writeFields(into: &w)
        return Data(HMAC<SHA256>.authenticationCode(for: w.data, using: key))
    }

    static func chunkMAC(format: UInt8, transfer: UUID, index: UInt32, count: UInt32, data: Data, key: SymmetricKey) -> Data {
        var mac = HMAC<SHA256>(key: key)
        var w = Writer()
        w.fixed(chunkDomain); w.u8(format); w.uuid(transfer); w.u32(index); w.u32(count); w.u32(UInt32(data.count))
        mac.update(data: w.data)
        mac.update(data: data)
        return Data(mac.finalize())
    }

    /// Compares two 32-byte codes in constant time: every byte is examined
    /// whatever the first difference, so timing says nothing about a code.
    static func validMAC(_ expected: Data, _ received: Data) -> Bool {
        guard expected.count == 32, received.count == 32 else { return false }
        var difference: UInt8 = 0
        for (a, b) in zip(expected, received) { difference |= a ^ b }
        return difference == 0
    }

    // MARK: Binary fields

    struct Writer {
        private(set) var data = Data()
        mutating func u8(_ v: UInt8) { data.append(v) }
        mutating func u32(_ v: UInt32) { data.append(contentsOf: [UInt8(v >> 24 & 255), UInt8(v >> 16 & 255), UInt8(v >> 8 & 255), UInt8(v & 255)]) }
        mutating func u64(_ v: UInt64) { u32(UInt32(v >> 32)); u32(UInt32(v & 0xFFFF_FFFF)) }
        mutating func uuid(_ v: UUID) { withUnsafeBytes(of: v.uuid) { data.append(contentsOf: $0) } }
        mutating func fixed(_ v: Data) { data.append(v) }
        mutating func bytes(_ v: Data) { u32(UInt32(v.count)); data.append(v) }
    }
    struct Reader {
        private let data: Data
        private var offset = 0
        init(_ data: Data) { self.data = Data(data) }
        var consumed: Int { offset }
        var remaining: Data { data.subdata(in: offset..<data.count) }
        var atEnd: Bool { offset == data.count }
        mutating func u8() throws -> UInt8 {
            guard offset < data.count else { throw Failure.malformed("truncated") }
            defer { offset += 1 }
            return data[offset]
        }
        mutating func u32() throws -> UInt32 {
            guard data.count - offset >= 4 else { throw Failure.malformed("truncated") }
            defer { offset += 4 }
            return (UInt32(data[offset]) << 24) | (UInt32(data[offset + 1]) << 16) | (UInt32(data[offset + 2]) << 8) | UInt32(data[offset + 3])
        }
        mutating func u64() throws -> UInt64 { (UInt64(try u32()) << 32) | UInt64(try u32()) }
        mutating func fixed(_ count: Int) throws -> Data {
            guard count >= 0, data.count - offset >= count else { throw Failure.malformed("truncated") }
            defer { offset += count }
            return data.subdata(in: offset..<offset + count)
        }
        mutating func uuid() throws -> UUID {
            let raw = try fixed(16)
            return raw.withUnsafeBytes { UUID(uuid: $0.loadUnaligned(as: uuid_t.self)) }
        }
        mutating func bytes(max: Int) throws -> Data {
            let count = Int(try u32())
            guard count <= max else { throw Failure.malformed("field too long") }
            return try fixed(count)
        }
    }
}

struct DeskClipboardManifest: Equatable {
    var transfer: UUID
    var copy: UUID
    /// The content's length before compression. Lengths are 64-bit so that
    /// files above 4 GB use the same manifest.
    var payloadLength: UInt64
    /// After compression, before padding.
    var encodedLength: UInt64
    /// What crosses the wire: always a size bucket.
    var paddedLength: UInt64
    var chunkCount: UInt32
    var compressed: Bool
    /// SHA-256 of the content itself.
    var digest: Data
    var mac: Data
    func writeFields(into w: inout DeskClipboardWire.Writer) {
        w.uuid(transfer); w.uuid(copy); w.u64(payloadLength); w.u64(encodedLength); w.u64(paddedLength)
        w.u32(chunkCount); w.u8(compressed ? 1 : 0); w.fixed(digest)
    }
}

enum DeskClipboardMessage: Equatable {
    /// The formats this Mac speaks. The only message ever sent to a Mac that
    /// has not answered with one of its own.
    case hello(formats: [UInt8], reply: Bool)
    /// "Something that can be brought over was just copied on this Mac." Sent
    /// once per copy, by the Mac it was copied on only, never by a Mac that
    /// received it, and never for a copy that cannot be brought over (Scott:
    /// those are invisible on copy). Its age in milliseconds is measured on the
    /// sender's own clock, so the Macs' clocks never need to agree. `what` is
    /// its kind, count and size bucket, never its contents or names. Inside
    /// the padded 1 KB envelope, so it changes nothing an observer sees.
    case copied(copy: UUID, age: UInt32, what: DeskClipboardDescriptor)
    /// "Bring over the newest copy": sent to the Mac typing goes to by the Mac
    /// whose keyboard pressed ⌃⌥⌘V.
    case bringOver
    /// "What is your newest copy?" Asked only when ⌃⌥⌘V is pressed.
    case ask(query: UUID)
    /// The answer: this Mac's newest copy, how long ago it was made, and what
    /// it is or why it cannot be brought over. The only way an unshareable
    /// copy's existence ever leaves its Mac.
    case newest(query: UUID, copy: UUID?, age: UInt32, answer: DeskClipboardAnswer)
    case fetch(transfer: UUID, copy: UUID, key: Data)
    /// The contents of a copy's files, as one stream in the order its list
    /// names them, asked for once the list is in and has been checked.
    case treeFetch(transfer: UUID, copy: UUID, key: Data)
    case manifest(DeskClipboardManifest)
    case chunk(transfer: UUID, index: UInt32, data: Data, mac: Data)
    /// The SHA-256 of consecutive files of a stream, from `first`, sent just
    /// after the chunk holding the last byte of the last of them, authenticated
    /// for that transfer and those files. Up to `DeskClipboardWire.digestsPerMessage`
    /// in one message, so a folder of thousands of small or empty files sends
    /// hundreds of these, not thousands.
    case fileDigests(transfer: UUID, first: UInt32, digests: [Data], mac: Data)
    /// Everything below `next` has arrived; up to a window beyond it may follow.
    case ack(transfer: UUID, next: UInt32)
    case refuse(transfer: UUID, refusal: DeskClipboardRefusal)
    case cancel(transfer: UUID, reason: DeskClipboardReason)

    func write(into w: inout DeskClipboardWire.Writer) {
        switch self {
        case .hello(let formats, let reply):
            w.u8(1); w.u8(UInt8(min(formats.count, 16))); formats.prefix(16).forEach { w.u8($0) }; w.u8(reply ? 1 : 0)
        case .fetch(let transfer, let copy, let key): w.u8(5); w.uuid(transfer); w.uuid(copy); w.fixed(key)
        case .manifest(let m): w.u8(6); m.writeFields(into: &w); w.fixed(m.mac)
        case .chunk(let transfer, let index, let data, let mac): w.u8(7); w.uuid(transfer); w.u32(index); w.bytes(data); w.fixed(mac)
        case .ack(let transfer, let next): w.u8(8); w.uuid(transfer); w.u32(next)
        case .refuse(let transfer, let refusal): w.u8(9); w.uuid(transfer); refusal.write(into: &w)
        case .cancel(let transfer, let reason): w.u8(10); w.uuid(transfer); w.u8(reason.rawValue)
        case .copied(let copy, let age, let what): w.u8(12); w.uuid(copy); w.u32(age); what.write(into: &w)
        case .bringOver: w.u8(13)
        case .ask(let query): w.u8(14); w.uuid(query)
        case .newest(let query, let copy, let age, let answer):
            w.u8(15); w.uuid(query); w.u8(copy == nil ? 0 : 1); w.uuid(copy ?? UUID(uuid: (0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0))); w.u32(age)
            answer.write(into: &w)
        case .treeFetch(let transfer, let copy, let key): w.u8(16); w.uuid(transfer); w.uuid(copy); w.fixed(key)
        case .fileDigests(let transfer, let first, let digests, let mac):
            w.u8(17); w.uuid(transfer); w.u32(first); w.u8(UInt8(clamping: digests.count)); digests.forEach { w.fixed($0) }; w.fixed(mac)
        }
    }

    /// The tags of a transfer's chunks and acknowledgements, whose pace the
    /// window already sets (`DeskClipboard.budget(of:)`).
    static let flowTags: Set<UInt8> = [7, 8]

    static func read(from r: inout DeskClipboardWire.Reader) throws -> Self {
        func flag() throws -> Bool {
            let value = try r.u8()
            guard value <= 1 else { throw DeskClipboardWire.Failure.malformed("flag") }
            return value == 1
        }
        switch try r.u8() {
        case 1:
            let count = Int(try r.u8())
            guard (1...16).contains(count) else { throw DeskClipboardWire.Failure.malformed("hello formats") }
            let formats = try (0..<count).map { _ in try r.u8() }
            return .hello(formats: formats, reply: try flag())
        case 5: return .fetch(transfer: try r.uuid(), copy: try r.uuid(), key: try r.fixed(32))
        case 6:
            let manifest = DeskClipboardManifest(transfer: try r.uuid(), copy: try r.uuid(), payloadLength: try r.u64(),
                                                 encodedLength: try r.u64(), paddedLength: try r.u64(), chunkCount: try r.u32(),
                                                 compressed: try flag(), digest: try r.fixed(32), mac: try r.fixed(32))
            return .manifest(manifest)
        case 7: return .chunk(transfer: try r.uuid(), index: try r.u32(), data: try r.bytes(max: DeskClipboardWire.chunkSize), mac: try r.fixed(32))
        case 8: return .ack(transfer: try r.uuid(), next: try r.u32())
        case 9: return .refuse(transfer: try r.uuid(), refusal: try DeskClipboardRefusal.read(from: &r))
        case 10: return .cancel(transfer: try r.uuid(), reason: try DeskClipboardRefusal.reason(from: &r))
        case 12: return .copied(copy: try r.uuid(), age: try r.u32(), what: try DeskClipboardDescriptor.read(from: &r))
        case 13: return .bringOver
        case 14: return .ask(query: try r.uuid())
        case 15:
            let query = try r.uuid(), known = try flag(), copy = try r.uuid(), age = try r.u32()
            let answer = try DeskClipboardAnswer.read(from: &r)
            guard known || answer == .nothing else { throw DeskClipboardWire.Failure.malformed("answer without a copy") }
            return .newest(query: query, copy: known ? copy : nil, age: age, answer: answer)
        case 16: return .treeFetch(transfer: try r.uuid(), copy: try r.uuid(), key: try r.fixed(32))
        case 17:
            let transfer = try r.uuid(), first = try r.u32(), count = Int(try r.u8())
            guard (1...DeskClipboardWire.digestsPerMessage).contains(count) else { throw DeskClipboardWire.Failure.malformed("digest count") }
            return .fileDigests(transfer: transfer, first: first, digests: try (0..<count).map { _ in try r.fixed(32) }, mac: try r.fixed(32))
        default: throw DeskClipboardWire.Failure.malformed("unknown message")
        }
    }
}

/// A Mac's newest copy, as it answers ⌃⌥⌘V.
enum DeskClipboardAnswer: Equatable {
    /// Nothing was copied there since Perch started.
    case nothing
    case shareable(DeskClipboardDescriptor)
    case unshareable(DeskClipboardRefusal)
    /// A copy that came from another Mac: never brought over from here.
    case received

    func write(into w: inout DeskClipboardWire.Writer) {
        switch self {
        case .nothing: w.u8(0)
        case .shareable(let what): w.u8(1); what.write(into: &w)
        case .unshareable(let refusal): w.u8(2); refusal.write(into: &w)
        case .received: w.u8(3)
        }
    }
    static func read(from r: inout DeskClipboardWire.Reader) throws -> Self {
        switch try r.u8() {
        case 0: return .nothing
        case 1: return .shareable(try DeskClipboardDescriptor.read(from: &r))
        case 2: return .unshareable(try DeskClipboardRefusal.read(from: &r))
        case 3: return .received
        default: throw DeskClipboardWire.Failure.malformed("answer")
        }
    }
}

extension DeskClipboardDescriptor {
    func write(into w: inout DeskClipboardWire.Writer) {
        w.u8(kind.rawValue); w.u32(UInt32(clamping: count)); w.u8(small ? 1 : 0); w.u8(size)
    }
    static func read(from r: inout DeskClipboardWire.Reader) throws -> Self {
        guard let kind = Kind(rawValue: try r.u8()) else { throw DeskClipboardWire.Failure.malformed("unknown kind") }
        let count = Int(try r.u32()), small = try r.u8(), size = try r.u8()
        guard (1...100_000).contains(count), small <= 1, small == 0 || kind == .text, Int(size) <= DeskClipboardPolicy.sizeBuckets.count else {
            throw DeskClipboardWire.Failure.malformed("description")
        }
        return .init(kind: kind, count: count, small: small == 1, size: size)
    }
}

extension DeskClipboardRefusal {
    func write(into w: inout DeskClipboardWire.Writer) {
        w.u8(reason.rawValue)
        w.u8(amount == nil ? 0 : 1); w.u64(amount ?? 0)
        w.u8(limit == nil ? 0 : 1); w.u64(limit ?? 0)
    }
    static func reason(from r: inout DeskClipboardWire.Reader) throws -> DeskClipboardReason {
        guard let value = DeskClipboardReason(rawValue: try r.u8()) else { throw DeskClipboardWire.Failure.malformed("unknown reason") }
        return value
    }
    static func read(from r: inout DeskClipboardWire.Reader) throws -> Self {
        let why = try reason(from: &r)
        func optional() throws -> UInt64? {
            let known = try r.u8(), value = try r.u64()
            guard known <= 1, known == 1 || value == 0 else { throw DeskClipboardWire.Failure.malformed("amount") }
            return known == 1 ? value : nil
        }
        let amount = try optional(), limit = try optional()
        return .init(why, amount: amount, limit: limit)
    }
}

/// Reassembles one transfer, refusing anything that does not follow its
/// manifest exactly. Chunks must arrive in order, once each, authenticated for
/// this transfer and index; the content digest is checked at the end. A class,
/// so a chunk is appended in place rather than copying everything so far.
final class DeskClipboardAssembly {
    enum Failure: Error, Equatable {
        case manifest(String)
        case chunk(String)
        case content(String)
        /// Whole and intact, but more than this Mac accepts.
        case declined(DeskClipboardReason)
        var detail: String {
            switch self {
            case .manifest(let d), .chunk(let d), .content(let d): return d
            case .declined(let reason): return reason.text
            }
        }
    }
    let manifest: DeskClipboardManifest
    let format: UInt8
    /// A file is written to disk as it arrives rather than kept here.
    let streaming: Bool
    private let key: SymmetricKey
    private(set) var next: UInt32 = 0
    private var stream = Data()
    var complete: Bool { next == manifest.chunkCount }
    var fraction: Double { manifest.chunkCount == 0 ? 1 : Double(next) / Double(manifest.chunkCount) }

    init(_ manifest: DeskClipboardManifest, transfer: UUID, copy: UUID, key: SymmetricKey, format: UInt8, maximumPayload: Int, streaming: Bool = false) throws {
        guard manifest.transfer == transfer else { throw Failure.manifest("belongs to another transfer") }
        guard manifest.copy == copy else { throw Failure.manifest("describes a different copy") }
        guard DeskClipboardWire.validMAC(DeskClipboardWire.manifestMAC(manifest, format: format, key: key), manifest.mac) else {
            throw Failure.manifest("authentication failed")
        }
        // Checked as 64-bit numbers before any becomes an Int, so a hostile
        // length can neither trap nor wrap.
        // A file may be empty; a copy never is. A file is never compressed.
        guard manifest.payloadLength > 0 || streaming, manifest.payloadLength <= UInt64(maximumPayload) else { throw Failure.manifest("declares a size Perch does not accept") }
        guard !streaming || !manifest.compressed else { throw Failure.manifest("compresses a file") }
        guard manifest.compressed ? (manifest.encodedLength < manifest.payloadLength) : (manifest.encodedLength == manifest.payloadLength),
              manifest.paddedLength <= 2 * manifest.payloadLength + UInt64(DeskClipboardWire.minimumBucket) else { throw Failure.manifest("lengths disagree") }
        let payload = Int(manifest.payloadLength), encoded = Int(manifest.encodedLength), padded = Int(manifest.paddedLength)
        guard !manifest.compressed || payload >= DeskClipboardWire.compressionThreshold else { throw Failure.manifest("compressed below the threshold") }
        guard padded == DeskClipboardWire.bucket(encoded) else { throw Failure.manifest("not padded to its size bucket") }
        guard Int(manifest.chunkCount) == (padded + DeskClipboardWire.chunkSize - 1) / DeskClipboardWire.chunkSize else { throw Failure.manifest("chunk count disagrees with its length") }
        self.manifest = manifest; self.key = key; self.format = format; self.streaming = streaming
        if !streaming { stream.reserveCapacity(padded) }
    }

    /// Verify one chunk and return the part of it that is content, not padding.
    @discardableResult
    func accept(transfer: UUID, index: UInt32, data: Data, mac: Data) throws -> Data {
        guard transfer == manifest.transfer else { throw Failure.chunk("belongs to another transfer") }
        guard index >= next else { throw Failure.chunk("chunk \(index) arrived again") }
        guard index == next else { throw Failure.chunk("chunk \(index) arrived before chunk \(next)") }
        let expected = index + 1 == manifest.chunkCount ? Int(manifest.paddedLength) - Int(index) * DeskClipboardWire.chunkSize : DeskClipboardWire.chunkSize
        guard index < manifest.chunkCount, data.count == expected else { throw Failure.chunk("chunk \(index) has the wrong length") }
        guard DeskClipboardWire.validMAC(DeskClipboardWire.chunkMAC(format: format, transfer: transfer, index: index, count: manifest.chunkCount, data: data, key: key), mac) else {
            throw Failure.chunk("chunk \(index) failed authentication")
        }
        let start = UInt64(index) * UInt64(DeskClipboardWire.chunkSize)
        let content = Int(min(UInt64(data.count), manifest.encodedLength > start ? manifest.encodedLength - start : 0))
        if streaming {
            // Padding is checked here, since nothing is kept to check later.
            guard data[data.startIndex + content..<data.endIndex].allSatisfy({ $0 == 0 }) else { throw Failure.chunk("chunk \(index) padding not empty") }
        } else { stream.append(data) }
        next += 1
        return data.prefix(content)
    }

    /// The content, once every chunk is in. Heavy work: run it off the main thread.
    func finish() throws -> Data {
        guard complete, stream.count == Int(manifest.paddedLength) else { throw Failure.content("chunks are missing") }
        let encoded = Int(manifest.encodedLength)
        guard stream[encoded...].allSatisfy({ $0 == 0 }) else { throw Failure.content("padding not empty") }
        let body = stream.prefix(encoded)
        let payload: Data
        if manifest.compressed {
            guard let expanded = DeskClipboardWire.decompress(Data(body), exactly: Int(manifest.payloadLength)) else { throw Failure.content("did not expand to its declared size") }
            payload = expanded
        } else { payload = Data(body) }
        guard DeskClipboardWire.validMAC(Data(SHA256.hash(data: payload)), manifest.digest) else { throw Failure.content("content digest does not match") }
        return payload
    }
}

/// What arrived, by the kind byte inside the padded content.
enum DeskClipboardPayload {
    case content(DeskClipboardContent)
    /// The list of a copy's files and folders, and its own encoding, which the
    /// stream of their contents is bound to.
    case files(DeskTreeList, encoded: Data)
    static func decode(_ payload: Data, limits: DeskClipboardLimits, fileLimits: DeskFileLimits) throws -> Self {
        switch payload.first {
        case DeskClipboardContent.kind: return .content(try DeskClipboardContent.decode(payload, limits: limits))
        case DeskTreeList.kind: return .files(try DeskTreeList.decode(payload, limits: fileLimits), encoded: payload)
        default: throw DeskClipboardWire.Failure.malformed("content kind")
        }
    }
}

/// A copy's representations, as they cross the wire inside the padded content.
struct DeskClipboardContent: Equatable {
    struct Representation: Equatable {
        let type: DeskClipboardType
        let data: Data
    }
    var items: [[Representation]]
    var byteCount: Int { items.reduce(0) { $0 + $1.reduce(0) { $0 + $1.data.count } } }

    /// Content kind 1: pasteboard data. The kind lives inside the content, so no
    /// header or packet size says what was copied.
    static let kind: UInt8 = 1

    func encoded() -> Data {
        var w = DeskClipboardWire.Writer()
        w.u8(Self.kind); w.u32(UInt32(items.count))
        for item in items {
            w.u8(UInt8(item.count))
            for representation in item { w.u8(representation.type.rawValue); w.bytes(representation.data) }
        }
        return w.data
    }

    static func decode(_ payload: Data, limits: DeskClipboardLimits) throws -> Self {
        typealias F = DeskClipboardWire.Failure
        var r = DeskClipboardWire.Reader(payload)
        guard try r.u8() == kind else { throw F.malformed("content kind") }
        let count = Int(try r.u32())
        guard (1...limits.items).contains(count) else { throw F.malformed("item count") }
        var items: [[Representation]] = [], total = 0
        for _ in 0..<count {
            let representations = Int(try r.u8())
            guard (1...DeskClipboardType.allCases.count).contains(representations) else { throw F.malformed("representation count") }
            var item: [Representation] = []
            for _ in 0..<representations {
                guard let type = DeskClipboardType(rawValue: try r.u8()) else { throw F.malformed("type outside the allowlist") }
                guard !item.contains(where: { $0.type == type || ($0.type.isImage && type.isImage) }) else { throw F.malformed("repeated representation") }
                let data = try r.bytes(max: limits.cap(type))
                total += data.count
                guard total <= limits.total else { throw F.malformed("content too large") }
                if type == .plainText { guard String(data: data, encoding: .utf8) != nil else { throw F.malformed("text is not UTF-8") } }
                item.append(.init(type: type, data: data))
            }
            items.append(item)
        }
        guard r.atEnd else { throw F.malformed("trailing content") }
        return Self(items: items)
    }
}
