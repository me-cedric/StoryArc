import Foundation
import Network

public class Connection {
  let host: String
  var onDisconnected: (Error) -> Void
  /// StoryArc: opens an SMB 3 transform. The session sets it once its keys exist.
  var unseal: ((Data) throws -> Data)?

  private let connection: NWConnection
  private var buffer = Data()

  private let semaphore = Semaphore(value: 1)

  public var state: NWConnection.State {
    connection.state
  }

  public init(host: String) {
    self.host = host
    let endpoint = NWEndpoint.hostPort(
      host: NWEndpoint.Host(host),
      port: NWEndpoint.Port(integerLiteral: 445)
    )
    connection = NWConnection(to: endpoint, using: .tcp)
    onDisconnected = { _ in }
  }

  public init(host: String, port: Int) {
    self.host = host
    let endpoint = NWEndpoint.hostPort(
      host: NWEndpoint.Host(host),
      port: NWEndpoint.Port(rawValue: UInt16(port))!
    )
    connection = NWConnection(to: endpoint, using: .tcp)
    onDisconnected = { _ in }
  }

  public func connect() async throws {
    return try await withCheckedThrowingContinuation { (continuation) in
      connection.stateUpdateHandler = { (state) in
        switch state {
        case .setup, .preparing:
          break
        case .waiting(let error):
          continuation.resume(throwing: error)
          self.connection.stateUpdateHandler = nil
        case .ready:
          continuation.resume()
          self.connection.stateUpdateHandler = stateUpdateHandler
        case .failed(let error):
          continuation.resume(throwing: error)
          self.connection.stateUpdateHandler = nil
        case .cancelled:
          continuation.resume(throwing: ConnectionError.cancelled)
          self.connection.stateUpdateHandler = nil
        @unknown default:
          break
        }
      }

      connection.start(queue: .global(qos: .userInitiated))
    }

    @Sendable
    func stateUpdateHandler(_ state: NWConnection.State) {
      switch state {
      case .waiting(let error), .failed(let error):
        onDisconnected(error)
      case .setup, .preparing, .ready, .cancelled:
        break
      @unknown default:
        break
      }
    }
  }

  public func disconnect() {
    connection.cancel()
  }

  public func send(_ data: Data) async throws -> Data {
    await semaphore.wait()
    defer { Task { await semaphore.signal() } }

    switch connection.state {
    case .setup:
      try await connect()
    case .waiting(let error), .failed(let error):
      onDisconnected(error)
      throw error
    case .preparing, .ready:
      break
    case .cancelled:
      throw ConnectionError.cancelled
    @unknown default:
      throw ConnectionError.unknown
    }

    let transportPacket = DirectTCPPacket(smb2Message: data)
    let content = transportPacket.encoded()

    return try await withCheckedThrowingContinuation { (continuation) in
      connection.send(content: content, completion: .contentProcessed() { (error) in
        if let error {
          continuation.resume(throwing: error)
          return
        }

        self.receive() { (result) in
          switch result {
          case .success(let data):
            continuation.resume(returning: data)
          case .failure(let error):
            continuation.resume(throwing: error)
          }
        }
      })
    }
  }

  // StoryArc: the receive path reads one transport frame at a time, so that an SMB 3
  // transform (an encrypted message) is opened before its header is read. The rules are
  // upstream's: an interim STATUS_PENDING reply is replaced by the final reply that follows
  // it, and any other failure status ends the exchange with an ErrorResponse.
  private func receive(completion: @escaping (Result<Data, Error>) -> Void) {
    receiveMessage { (result) in
      switch result {
      case .success(let data):
        self.settle(data, from: 0, completion: completion)
      case .failure(let error):
        completion(.failure(error))
      }
    }
  }

  /// Walks a reply, compounded or not, from `offset`, and waits out an interim reply.
  private func settle(_ data: Data, from start: Int, completion: @escaping (Result<Data, Error>) -> Void) {
    var offset = start
    while true {
      guard data.count >= offset + 64 else {
        completion(.failure(ConnectionError.noData))
        return
      }
      let reader = ByteReader(data)
      reader.seek(to: offset)
      let header: Header = reader.read()

      switch NTStatus(header.status) {
      case .success, .moreProcessingRequired, .noMoreFiles, .endOfFile:
        break
      case .pending:
        // The final reply to this element arrives in a frame of its own, and it takes the
        // interim reply's place in the chain.
        receiveMessage { (result) in
          switch result {
          case .success(let next):
            self.settle(Data(data.prefix(offset)) + next, from: offset, completion: completion)
          case .failure(let error):
            completion(.failure(error))
          }
        }
        return
      default:
        completion(.failure(ErrorResponse(data: Data(data.dropFirst(offset)))))
        return
      }

      guard header.nextCommand > 0 else { break }
      offset += Int(header.nextCommand)
    }
    completion(.success(data))
  }

  /// One transport frame's SMB message, opened when it is an SMB 3 transform.
  private func receiveMessage(completion: @escaping (Result<Data, Error>) -> Void) {
    receive(upTo: 4) { (result) in
      if case .failure(let error) = result {
        completion(.failure(error))
        return
      }
      let prefix = [UInt8](self.buffer.prefix(4))
      let length = Int(prefix[1]) << 16 | Int(prefix[2]) << 8 | Int(prefix[3])

      self.receive(upTo: 4 + length) { (result) in
        if case .failure(let error) = result {
          completion(.failure(error))
          return
        }
        let message = Data(self.buffer.dropFirst(4).prefix(length))
        self.buffer = Data(self.buffer.dropFirst(4 + length))
        do {
          completion(.success(try self.open(message)))
        } catch {
          completion(.failure(error))
        }
      }
    }
  }

  /// Opens an SMB 3 transform with the session's key, and passes anything else through.
  private func open(_ message: Data) throws -> Data {
    guard SMB3Transform.isTransform(message) else { return message }
    guard let unseal else { throw SMB3Error.decryptionFailed }
    return try unseal(message)
  }

  private func receive(upTo byteCount: Int, completion: @escaping (Result<(), Error>) -> Void) {
    let minimumIncompleteLength = 0
    let maximumLength = 65536

    if self.buffer.count < byteCount {
      self.connection.receive(minimumIncompleteLength: minimumIncompleteLength, maximumLength: maximumLength) { (data, _, isComplete, error) in
        if let error = error {
          completion(.failure(error))
          return
        }

        guard let data else {
          if isComplete {
            completion(.failure(ConnectionError.disconnected))
          } else {
            completion(.failure(ConnectionError.noData))
          }
          return
        }

        self.buffer.append(data)
        self.receive(upTo: byteCount, completion: completion)
      }
      return
    }

    completion(.success(()))
  }
}

public enum ConnectionError: Error {
  case noData
  case disconnected
  case cancelled
  case unknown
}
