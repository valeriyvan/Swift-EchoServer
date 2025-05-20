import NIO

private final class EchoHandler: ChannelInboundHandler {
    public typealias InboundIn = ByteBuffer
    public typealias OutboundOut = ByteBuffer

    // Keep tracks of the number of message received in a single session
    // (an EchoHandler is created per client connection).
    private var count: Int = 0

    // Invoked on client connection
    public func channelRegistered(context: ChannelHandlerContext) {
        print("channel registered:", context.remoteAddress ?? "unknown")
    }

    // Invoked on client disconnect
    public func channelUnregistered(context: ChannelHandlerContext) {
        print("we have processed \(count) messages")
    }

    // Invoked when data are received from the client
    public func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        context.write(data, promise: nil)
        count = count + 1
    }

    // Invoked when channelRead as processed all the read event in the current read operation
    public func channelReadComplete(context: ChannelHandlerContext) {
        context.flush()
    }

    // Invoked when an error occurs
    public func errorCaught(context: ChannelHandlerContext, error: Error) {
        print("error: ", error)
        context.close(promise: nil)
    }
}

// Create a multi thread event loop to use all the system core for the processing
let group = MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount)

// Set up the server using a Bootstrap
let bootstrap = ServerBootstrap(group: group)
        // Define backlog and enable SO_REUSEADDR options at the server level
        .serverChannelOption(ChannelOptions.backlog, value: 256)
        .serverChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)

        // Handler Pipeline: handlers that are processing events from accepted Channels
        // To demonstrate that we can have several reusable handlers we start with a Swift-NIO default
        // handler that limits the speed at which we read from the client if we cannot keep up with the
        // processing through EchoHandler.
        // This is to protect the server from overload.
        .childChannelInitializer { channel in
            channel.pipeline.addHandler(BackPressureHandler()).flatMap { 
                channel.pipeline.addHandler(EchoHandler())
            }
        }

        // Enable common socket options at the channel level (TCP_NODELAY and SO_REUSEADDR).
        // These options are applied to accepted Channels
        .childChannelOption(ChannelOptions.socketOption(.tcp_nodelay), value: 1)
        .childChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
        // Message grouping
        .childChannelOption(ChannelOptions.maxMessagesPerRead, value: 16)
        // Let Swift-NIO adjust the buffer size, based on actual traffic.
        .childChannelOption(ChannelOptions.recvAllocator, value: AdaptiveRecvByteBufferAllocator())
defer {
    try! group.syncShutdownGracefully()
}

// Bind the port and run the server
let channel = try bootstrap.bind(host: "::1", port: 9999).wait()

print("Server started and listening on \(channel.localAddress!)")

// Clean-up (never called, as we do not have a code to decide when to stop
// the server). We assume we will be killing it with Ctrl-C.
try channel.closeFuture.wait()

print("Server terminated")

