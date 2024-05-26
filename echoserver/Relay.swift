//
//  Created by Jericho Hasselbush on 5/6/24.
//

import Foundation
import Network

class Relay {
    let listener: NWListener
    let queue = DispatchQueue(label: "swifr.relay")
    init() throws {
        let parameters = SecureWebSocket.parameters()
        let websocketOptions = NWProtocolWebSocket.Options(.version13)

        parameters.defaultProtocolStack.applicationProtocols.insert(websocketOptions, at: 0)

        let port = NWEndpoint.Port(integerLiteral: 4433)
        listener = try NWListener(using: parameters, on: port)

        listener.stateUpdateHandler = { _ in }

        listener.newConnectionHandler = { newConnection in

            newConnection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    receive()
                default:
                    break
                }
            }

            func sendData(_ data: Data, _ context: NWConnection.ContentContext) {
                self.send(data, to: newConnection, in: context)
            }
            
            func receive() {
                self.receive(with: newConnection)
            }

            newConnection.start(queue: .main)
        }
    }

    func receive(with connection: NWConnection) {
        connection.receiveMessage {[weak self] content, context, complete, error in
            guard let self = self else { return }
            if let content = content {
                let metaData = NWProtocolWebSocket.Metadata(opcode: .text)
                let context = NWConnection.ContentContext(identifier: "text", metadata: [metaData])
                switch String(data: content, encoding: .utf8) {
                case "EVENT_REQUEST":
                    send(nostrEvent(), to: connection, in: context)
                default:
                    send(content, to: connection, in: context)
                }
            }
            if !complete && error == nil {
                receive(with: connection)
            }
        }
    }

    func nostrEvent() -> Data {
         makeEventData(id: "eventID", pubkey: "pubkey", created_at: .now, kind: 1, tags: [], content: "The content", sig: "signature")
    }

    func send(_ data: Data, to connection: NWConnection, in context: NWConnection.ContentContext) {
        connection.send(content: data, contentContext: context, completion: .contentProcessed { error in
            if error == nil {
                self.receive(with: connection)
            }
        })
    }

    func start() {
        listener.start(queue: queue)
    }
}

private func makeEventData(id: String, pubkey: String, created_at: Date, kind: UInt16, tags: [[String]], content: String, sig: String) -> Data {
    let time = Int(created_at.timeIntervalSince1970)
    let tagString = tags.stringed

    let eventJSON = "[\"EVENT\",\"sub1\",{\"id\":\"\(id)\",\"pubkey\":\"\(pubkey)\",\"created_at\":\(time),\"kind\":\(kind),\"tags\":\(tagString),\"content\":\"\(content)\",\"sig\":\"\(sig)\"}]"

    return Data(eventJSON.utf8)
}

private extension Array where Element == [String] {
    var stringed: String {
        if let json = try? JSONEncoder().encode(self), let string = String(data: json, encoding: .utf8) {
            return string
        }
        return ""
    }
}

class SecureWebSocket {
    struct WSCreationError: Error {}

    static func parameters() -> NWParameters {
        let tlsOptions = NWProtocolTLS.Options()
        let tcpOptions = NWProtocolTCP.Options()
        let parameters = NWParameters(tls: tlsOptions, tcp: tcpOptions)
        let options = NWProtocolWebSocket.Options()
        parameters.defaultProtocolStack.applicationProtocols.insert(options, at: 0)

        if let secIdentity = getSecIdentity(),
           let identity = sec_identity_create(secIdentity) {
            sec_protocol_options_set_min_tls_protocol_version(
                tlsOptions.securityProtocolOptions, .TLSv13)
            sec_protocol_options_set_local_identity(
                tlsOptions.securityProtocolOptions, identity)
        }

        return parameters
    }

    static private func getSecIdentity() -> SecIdentity? {
        var identity: SecIdentity?
        let getquery = [kSecClass: kSecClassCertificate,
            kSecAttrLabel: "echoserver",
            kSecReturnRef: true] as NSDictionary


        var item: CFTypeRef?
        let status = SecItemCopyMatching(getquery as CFDictionary, &item)
        guard status == errSecSuccess else {
            return nil
        }
        let certificate = item as! SecCertificate

        let identityStatus = SecIdentityCreateWithCertificate(nil, certificate, &identity)
        guard identityStatus == errSecSuccess else {
            return nil
        }
        return identity
    }
}
