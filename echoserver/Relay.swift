//
//  Created by Jericho Hasselbush on 5/6/24.
//

import Foundation
import Network

class Relay {
    let listener: NWListener
    let queue = DispatchQueue(label: "swifr.relay")
    init() throws {
        let parameters = NWParameters(tls: nil, tcp: .init())
        let websocketOptions = NWProtocolWebSocket.Options()
        parameters.defaultProtocolStack.applicationProtocols.insert(websocketOptions, at: 0)

        let port = NWEndpoint.Port(integerLiteral: 8080)
        listener = try NWListener(using: parameters, on: port)

        listener.stateUpdateHandler = { _ in }

        listener.newConnectionHandler = { newConnection in
            newConnection.start(queue: .main)

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
        }
    }

    func receive(with connection: NWConnection) {
        connection.receiveMessage {[weak self] content, context, complete, error in
            guard let self = self else { return }
            if let content = content {
                let metaData = NWProtocolWebSocket.Metadata(opcode: .text)
                let context = NWConnection.ContentContext(identifier: "text", metadata: [metaData])
                if String(data: content, encoding: .utf8) == "EVENT_REQUEST" {
                    let eventData = self.basicEvent.data(using: .utf8)!
                    send(eventData, to: connection, in: context)
                } else {
                    send(content, to: connection, in: context)
                }
            }
            if !complete {
                receive(with: connection)
            }
        }
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

    let basicEvent: String = "[\"EVENT\",\"sub1\",{\"id\":\"id1\",\"pubkey\":\"pubkey1\",\"created_at\":-62135769600.0,\"kind\":1,\"tags\":[[\"e\",\"event1\",\"event2\"],[\"p\",\"pub1\",\"pub2\"]],\"content\":\"content1\",\"sig\":\"sig1\"}]"

}
