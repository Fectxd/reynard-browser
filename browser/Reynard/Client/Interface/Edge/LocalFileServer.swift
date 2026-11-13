//
//  LocalFileServer.swift
//  Reynard
//
//  Created by Edge UI instrumentation.
//
//  Gecko's content processes cannot read files outside their own sandbox, so
//  a file:// URL for a document picked in Files (or copied into the app) fails
//  to load. Instead of copying files into the app, the app process keeps the
//  security-scoped grant for the picked file and serves it to Gecko over a
//  loopback-only HTTP listener (127.0.0.1, random port, random token per file).
//  Nothing is stored, so the app does not grow.
//

import Foundation
import Network
import UniformTypeIdentifiers

final class LocalFileServer {
    static let shared = LocalFileServer()

    private let queue = DispatchQueue(label: "Reynard.LocalFileServer")
    private var listener: NWListener?
    private var port: UInt16?
    private var pendingStarts: [(UInt16?) -> Void] = []
    /// token -> security-scoped file URL (access stays open while registered).
    private var files: [String: URL] = [:]

    /// Registers a picked file and returns its loopback URL via `completion`
    /// (on the main queue), or nil if the server could not start.
    func publish(_ fileURL: URL, completion: @escaping (URL?) -> Void) {
        // Keep the grant for the rest of the session so reloads still work.
        _ = fileURL.startAccessingSecurityScopedResource()
        queue.async {
            let token = UUID().uuidString.lowercased()
            self.files[token] = fileURL
            self.startIfNeeded { port in
                let url = port.flatMap { port -> URL? in
                    var components = URLComponents()
                    components.scheme = "http"
                    components.host = "127.0.0.1"
                    components.port = Int(port)
                    components.path = "/\(token)/\(fileURL.lastPathComponent)"
                    return components.url
                }
                DispatchQueue.main.async {
                    completion(url)
                }
            }
        }
    }

    // MARK: - Listener

    private func startIfNeeded(_ completion: @escaping (UInt16?) -> Void) {
        if let port {
            completion(port)
            return
        }
        pendingStarts.append(completion)
        guard listener == nil else {
            return
        }

        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = NWEndpoint.hostPort(host: "127.0.0.1", port: .any)
        parameters.acceptLocalOnly = true
        guard let listener = try? NWListener(using: parameters) else {
            finishStart(nil)
            return
        }
        self.listener = listener
        listener.newConnectionHandler = { [weak self] connection in
            self?.handle(connection)
        }
        listener.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                self.port = listener.port?.rawValue
                self.finishStart(self.port)
            case .failed, .cancelled:
                self.listener = nil
                self.port = nil
                self.finishStart(nil)
            default:
                break
            }
        }
        listener.start(queue: queue)
    }

    private func finishStart(_ port: UInt16?) {
        let completions = pendingStarts
        pendingStarts = []
        completions.forEach { $0(port) }
    }

    // MARK: - HTTP

    private func handle(_ connection: NWConnection) {
        connection.start(queue: queue)
        receiveRequest(on: connection, buffer: Data())
    }

    private func receiveRequest(on connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16 * 1024) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            var buffer = buffer
            if let data {
                buffer.append(data)
            }
            if let headerEnd = buffer.range(of: Data("\r\n\r\n".utf8)) {
                let header = String(decoding: buffer[..<headerEnd.lowerBound], as: UTF8.self)
                self.respond(to: header, on: connection)
            } else if error != nil || isComplete || buffer.count > 64 * 1024 {
                connection.cancel()
            } else {
                self.receiveRequest(on: connection, buffer: buffer)
            }
        }
    }

    private func respond(to header: String, on connection: NWConnection) {
        let requestLine = header.components(separatedBy: "\r\n").first ?? ""
        let parts = requestLine.split(separator: " ")
        guard parts.count >= 2, parts[0] == "GET" || parts[0] == "HEAD" else {
            sendStatus(405, "Method Not Allowed", on: connection)
            return
        }
        let isHead = parts[0] == "HEAD"
        let path = String(parts[1]).split(separator: "?").first.map(String.init) ?? ""
        let token = path.split(separator: "/").first.map(String.init) ?? ""
        guard let fileURL = files[token],
              let handle = try? FileHandle(forReadingFrom: fileURL) else {
            sendStatus(404, "Not Found", on: connection)
            return
        }

        let size = (try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize).flatMap { $0 } ?? 0
        let head = [
            "HTTP/1.1 200 OK",
            "Content-Type: \(Self.mimeType(for: fileURL))",
            "Content-Length: \(size)",
            "Cache-Control: no-store",
            "Connection: close",
            "", "",
        ].joined(separator: "\r\n")
        connection.send(content: Data(head.utf8), completion: .contentProcessed { [weak self] error in
            guard error == nil, !isHead else {
                try? handle.close()
                connection.cancel()
                return
            }
            self?.streamBody(handle, on: connection)
        })
    }

    private func streamBody(_ handle: FileHandle, on connection: NWConnection) {
        let chunk = handle.readData(ofLength: 256 * 1024)
        guard !chunk.isEmpty else {
            try? handle.close()
            connection.send(content: nil, isComplete: true, completion: .contentProcessed { _ in
                connection.cancel()
            })
            return
        }
        connection.send(content: chunk, completion: .contentProcessed { [weak self] error in
            guard error == nil else {
                try? handle.close()
                connection.cancel()
                return
            }
            self?.streamBody(handle, on: connection)
        })
    }

    private func sendStatus(_ code: Int, _ reason: String, on connection: NWConnection) {
        let response = "HTTP/1.1 \(code) \(reason)\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
        connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    private static func mimeType(for url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "pdf":
            return "application/pdf"
        case "htm", "html":
            return "text/html"
        case "xhtml", "xht":
            return "application/xhtml+xml"
        default:
            if #available(iOS 14.0, *),
               let type = UTType(filenameExtension: url.pathExtension),
               let mime = type.preferredMIMEType {
                return mime
            }
            return "application/octet-stream"
        }
    }
}
