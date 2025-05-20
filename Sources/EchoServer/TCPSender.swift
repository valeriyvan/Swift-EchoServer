import Foundation
import NIO

fileprivate final class SendHandler: ChannelInboundHandler {
    typealias InboundIn = ByteBuffer
    typealias OutboundOut = ByteBuffer
    
    private let packets: [ByteBuffer]
    private var index = 0
    
    init(packets: [ByteBuffer]) {
        self.packets = packets
    }
    
    // This is called when a client connects to the server
    func channelActive(context: ChannelHandlerContext) {
        print("Client connected: \(context.remoteAddress?.description ?? "unknown")")
        // Start sending packets to the client
        sendNext(context: context)
    }
    
    private func sendNext(context: ChannelHandlerContext) {
        guard index < packets.count else {
            print("All packets sent to client. Closing connection.")
            context.close(promise: nil)
            return
        }
        
        // Send packet with a delay between each one
        context.eventLoop.scheduleTask(in: .milliseconds(500)) { [self] in
            print("Sending packet \(index + 1)/\(packets.count)")
            context.writeAndFlush(self.wrapOutboundOut(packets[index])).whenComplete { result in
                switch result {
                case .success:
                    self.index += 1
                    self.sendNext(context: context)
                case .failure(let error):
                    print("Failed to send packet: \(error)")
                    context.close(promise: nil)
                }
            }
        }
    }
    
    // Handle any received data (client responses)
    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        var buffer = unwrapInboundIn(data)
        if let response = buffer.readString(length: buffer.readableBytes) {
            print("Received from client: \(response)")
        }
    }
    
    func channelInactive(context: ChannelHandlerContext) {
        print("Client disconnected")
        // Reset index for the next client
        index = 0
    }
    
    func errorCaught(context: ChannelHandlerContext, error: Error) {
        print("Error: \(error)")
        context.close(promise: nil)
    }
}

struct TCPSender {
    private let channel: Channel
    private let group: MultiThreadedEventLoopGroup
    
    init(host: String, port: Int, packetsToSend: [ByteBuffer]) throws {
        group = MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount)
        
        // Initialize server bootstrap
        let bootstrap = ServerBootstrap(group: group)
            // Set server socket options
            .serverChannelOption(ChannelOptions.backlog, value: 256)
            .serverChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
            
            // Configure handler for each client connection
            .childChannelInitializer { channel in
                channel.pipeline.addHandler(SendHandler(packets: packetsToSend))
            }
            
            // Configure child socket options
            .childChannelOption(ChannelOptions.socketOption(.tcp_nodelay), value: 1)
            .childChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
            .childChannelOption(ChannelOptions.maxMessagesPerRead, value: 16)
            .childChannelOption(ChannelOptions.recvAllocator, value: AdaptiveRecvByteBufferAllocator())
        
        // Bind to host/port and start listening
        print("Binding to \(host):\(port)...")
        channel = try bootstrap.bind(host: host, port: port).wait()
        print("Server started and listening on \(channel.localAddress!)")
        print("Ready to accept connections. Connect with a TCP client to receive packets.")
    }
    
    func waitForClose() throws {
        // Wait until server is shutdown (usually by ctrl+c)
        try channel.closeFuture.wait()
        try group.syncShutdownGracefully()
    }
}