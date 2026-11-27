//
//  GeckoRuntime.swift
//  Reynard
//
//  Created by Minh Ton on 1/2/26.
//

import Foundation
import UIKit

public protocol GeckoScreenOrientationDelegate: AnyObject {
    func lockScreenOrientation(
        to requestedOrientations: UIInterfaceOrientationMask,
        completion: @escaping (GeckoOrientationLockResult) -> Void
    )
    func unlockScreenOrientation()
}

public final class GeckoScreenOrientationController {
    public weak var delegate: GeckoScreenOrientationDelegate?
}

class GeckoRuntimeImpl: NSObject, SwiftGeckoViewRuntime {
    func runtimeDispatcher() -> any SwiftEventDispatcher {
        return GeckoEventDispatcherWrapper.runtimeInstance
    }
    
    func dispatcher(byName name: UnsafePointer<CChar>) -> any SwiftEventDispatcher {
        return GeckoEventDispatcherWrapper.lookup(byName: String(cString: name))
    }
    
    @objc(childProcessDidStartWithPID:processType:)
    func childProcessDidStart(withPID pid: Int32, processType: String) {
        // Update jetsam limit for the child process
        updateJetsamControl(pid)
        
        NotificationCenter.default.post(
            name: Notification.Name("GeckoRuntime.ChildProcessDidStart"),
            object: nil,
            userInfo: [
                "pid": NSNumber(value: pid),
                "processType": processType
            ]
        )
    }
    
    func lockScreenOrientation(
        _ orientationMask: UInt,
        completion: @escaping (GeckoOrientationLockResult) -> Void
    ) {
        let requestedOrientations = UIInterfaceOrientationMask(rawValue: orientationMask)
        DispatchQueue.main.async {
            guard let delegate = GeckoRuntime.orientationController.delegate else {
                completion(.notSupported)
                return
            }
            delegate.lockScreenOrientation(
                to: requestedOrientations,
                completion: completion
            )
        }
    }
    
    func unlockScreenOrientation() {
        DispatchQueue.main.async {
            GeckoRuntime.orientationController.delegate?.unlockScreenOrientation()
        }
    }
}

public class GeckoRuntime {
    static let runtime = GeckoRuntimeImpl()
    public static let orientationController = GeckoScreenOrientationController()
    
    public static var version: String {
        return GeckoRuntimeBridge.version()
    }
    
    public static func setLocale(acceptLanguages: String) {
        GeckoEventDispatcherWrapper.runtimeInstance.dispatch(
            type: "GeckoView:SetLocale",
            message: [
                "acceptLanguages": acceptLanguages
            ]
        )
    }
    
    public static func setDefaultPrefs(_ preferences: [String: Any]) {
        GeckoEventDispatcherWrapper.runtimeInstance.dispatch(
            type: "GeckoView:SetDefaultPrefs",
            message: preferences
        )
    }
    
    /// Imports a PKCS#12 (.p12 / .pfx) client certificate with its private key
    /// into the profile's certificate database (Edge engine patch). Returns the
    /// nsIX509CertDB result code: 0 success, 6 wrong password, 7 unreadable file.
    public static func importClientCertificate(path: String, password: String) async throws -> Int {
        let response = try await GeckoEventDispatcherWrapper.runtimeInstance.query(
            type: "GeckoView:Edge:ImportClientCertificate",
            message: ["path": path, "password": password]
        )
        if let number = response as? NSNumber {
            return number.intValue
        }
        return (response as? Int) ?? 1
    }
    
    /// The user's own (imported) client certificates: dbKey, name,
    /// organization, issuer, serialNumber, notAfter (ms since 1970).
    public static func listClientCertificates() async throws -> [[String: Any]] {
        let response = try await GeckoEventDispatcherWrapper.runtimeInstance.query(
            type: "GeckoView:Edge:ListClientCertificates"
        )
        return (response as? [Any])?.compactMap { $0 as? [String: Any] } ?? []
    }
    
    /// Deletes a client certificate (and its private key) by its dbKey.
    public static func deleteClientCertificate(dbKey: String) async throws -> Bool {
        let response = try await GeckoEventDispatcherWrapper.runtimeInstance.query(
            type: "GeckoView:Edge:DeleteClientCertificate",
            message: ["dbKey": dbKey]
        )
        return (response as? Bool) ?? ((response as? NSNumber)?.boolValue ?? false)
    }
    
    public static func dispatchEvent(type: String, message: [String: Any?]? = nil) {
        GeckoEventDispatcherWrapper.runtimeInstance.dispatch(
            type: type,
            message: message
        )
    }
    
    public static func main(
        argc: Int32,
        argv: UnsafeMutablePointer<UnsafeMutablePointer<Int8>?>
    ) {
        MainProcessInit(argc, argv, runtime)
    }
    
    public static func childMain(
        xpcConnection: xpc_connection_t,
        process: GeckoProcessExtension
    ) {
        ChildProcessInit(xpcConnection, process, runtime)
    }
}
