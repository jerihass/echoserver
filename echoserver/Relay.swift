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
            func receive() {
                newConnection.receiveMessage { content, context, complete, error in
                    if let content = content {
                        let metaData = NWProtocolWebSocket.Metadata(opcode: .text)
                        let context = NWConnection.ContentContext(identifier: "text", metadata: [metaData])
                        if String(data: content, encoding: .utf8) == "EVENT_REQUEST" {
                            let eventData = self.basicEvent.data(using: .utf8)!
                            newConnection
                                .send(content: eventData,
                                      contentContext: context,
                                      completion: .contentProcessed { error in
                                    if error == nil {
                                        receive()
                                    }
                                })
                        } else {
                            newConnection
                                .send(content: content,
                                      contentContext: context,
                                      completion: .contentProcessed { error in
                                    if error == nil {
                                        receive()
                                    }
                                })
                        }
                    }
                    if !complete {
                        receive()
                    }
                }
            }
        }
    }

    func start() {
        listener.start(queue: queue)
    }

    let basicEvent: String = "[\"EVENT\",\"sub1\",{\"id\":\"id1\",\"pubkey\":\"pubkey1\",\"created_at\":-62135769600.0,\"kind\":1,\"tags\":[[\"e\",\"event1\",\"event2\"],[\"p\",\"pub1\",\"pub2\"]],\"content\":\"content1\",\"sig\":\"sig1\"}]"

}
