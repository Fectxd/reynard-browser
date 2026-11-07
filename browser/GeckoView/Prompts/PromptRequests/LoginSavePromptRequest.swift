//
//  LoginSavePromptRequest.swift
//  Reynard
//
//  Created by Edge UI instrumentation.
//
//  Gecko emits the `Autocomplete:Save:Login` prompt when a page submits a
//  login form and the engine's own password manager wants to offer to save it.
//  The payload carries the candidate login(s) the page submitted; the app
//  decides whether to keep them (and answers with the chosen login, or null to
//  decline).
//

import Foundation

public struct LoginSavePromptRequest {
    public struct Login {
        public let guid: String
        public let origin: String
        public let formActionOrigin: String?
        public let httpRealm: String?
        public let username: String
        public let password: String

        /// Parses a single login entry from Gecko's payload, accepting both the
        /// camelCase keys GeckoView uses and snake_case variants.
        init?(_ payload: [String: Any]) {
            guard let origin = PayloadValue.string(payload["origin"]), !origin.isEmpty else {
                return nil
            }

            self.guid = PayloadValue.string(payload["guid"]) ?? ""
            self.origin = origin
            self.formActionOrigin = PayloadValue.string(payload["formActionOrigin"])
                ?? PayloadValue.string(payload["form_action_origin"])
            self.httpRealm = PayloadValue.string(payload["httpRealm"])
                ?? PayloadValue.string(payload["http_realm"])
            self.username = PayloadValue.string(payload["username"]) ?? ""
            self.password = PayloadValue.string(payload["password"]) ?? ""
        }

        /// The login entry serialised back into the shape Gecko's prompt expects.
        var payload: [String: Any] {
            var payload: [String: Any] = [
                "origin": origin,
                "username": username,
                "password": password,
            ]

            if !guid.isEmpty {
                payload["guid"] = guid
            }
            if let formActionOrigin, !formActionOrigin.isEmpty {
                payload["formActionOrigin"] = formActionOrigin
            }
            if let httpRealm, !httpRealm.isEmpty {
                payload["httpRealm"] = httpRealm
            }

            return payload
        }
    }

    public let id: String
    public let logins: [Login]
}
