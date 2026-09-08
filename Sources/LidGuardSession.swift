import Foundation

/// Serialized by the client's heartbeat queue. Transport failures never grant a
/// new session: retries can only renew the existing token before helper expiry.
final class LidGuardSession {
    enum Request: Equatable { case status, renew(String), change(Bool) }
    typealias Send = (Request, @escaping (Data?) -> Void) -> Void
    let send: Send
    let schedule: (Double, @escaping () -> Void) -> Void
    let invalidate: () -> Void
    let publish: (LidGuardStatus?, Bool) -> Void
    let activity: (Bool) -> Void
    let now: () -> Double
    private var token: String?
    private var renewUntil: Double = 0
    private var pending = false
    private var changing = false
    private var generation = UUID()
    private var lastStatus: LidGuardStatus?

    init(send: @escaping Send, schedule: @escaping (Double, @escaping () -> Void) -> Void,
         invalidate: @escaping () -> Void, publish: @escaping (LidGuardStatus?, Bool) -> Void,
         activity: @escaping (Bool) -> Void, now: @escaping () -> Double = { LidGuardClock.now }) {
        self.send = send; self.schedule = schedule; self.invalidate = invalidate
        self.publish = publish; self.activity = activity; self.now = now
    }
    private func decode(_ data: Data?) -> LidGuardReply? {
        guard let data, data.count <= 4096,
              let reply = try? JSONDecoder().decode(LidGuardReply.self, from: data),
              reply.status.fresh else { return nil }
        return reply
    }
    private func retain(_ reply: LidGuardReply) {
        lastStatus = reply.status
        if !reply.status.armed || reply.status.error != nil { token = nil }
        activity(token != nil)
        publish(lastStatus, changing)
    }
    func refresh() {
        guard !pending, !changing else { return }
        if token != nil && now() >= renewUntil {
            token = nil; lastStatus = nil; activity(false); publish(nil, false)
        }
        pending = true; generation = UUID(); let request = generation
        let expectedToken = token
        let sentAt = now()
        let finish: (Data?) -> Void = { [weak self] data in
            guard let self, self.pending, self.generation == request else { return }
            self.pending = false
            // Consume every result once, including errors; a late callback must
            // not invalidate a recovered connection or undo a newer user action.
            self.generation = UUID(); let retry = self.generation
            if let reply = self.decode(data) {
                if let expectedToken, reply.status.armed, reply.token != expectedToken {
                    self.token = nil
                    self.lastStatus = nil
                    self.activity(false); self.publish(nil, false)
                } else {
                    if expectedToken != nil { self.renewUntil = sentAt + 5 }
                    self.retain(reply)
                }
            } else {
                self.invalidate()
                self.lastStatus = nil; self.publish(nil, false)
                // Keep the token, but never call setEnabled as recovery. The
                // helper's original five-second lease remains authoritative.
                self.schedule(0.25) { [weak self] in
                    guard let self, self.generation == retry else { return }
                    self.refresh()
                }
            }
        }
        send(expectedToken.map(Request.renew) ?? .status, finish)
        schedule(2) { finish(nil) }
    }
    func change(_ enabled: Bool, completion: @escaping (Result<Void, Error>) -> Void) {
        guard !changing else {
            completion(.failure(AppError(message: "A lid change is already in progress."))); return
        }
        changing = true; pending = false; generation = UUID(); let request = generation
        let sentAt = now()
        token = nil; activity(true); publish(lastStatus, true)
        let finish: (Data?) -> Void = { [weak self] data in
            guard let self, self.changing, self.generation == request else { return }
            self.generation = UUID(); self.changing = false
            let reply = self.decode(data)
            if let reply, reply.status.error == nil, reply.status.armed == enabled,
               !enabled || reply.token.flatMap(UUID.init(uuidString:)) != nil {
                self.token = enabled ? reply.token : nil
                self.renewUntil = sentAt + 5
                self.retain(reply); completion(.success(()))
            } else {
                self.token = nil; self.invalidate()
                self.lastStatus = reply?.status
                self.activity(false); self.publish(self.lastStatus, false)
                completion(.failure(AppError(message: reply?.status.error ?? "The lid helper did not confirm the change. Review lid protection and retry with the lid open or external power connected.")))
            }
        }
        send(.change(enabled), finish)
        schedule(3) { finish(nil) }
    }
}
