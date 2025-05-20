import NIO

// Create sample data to send
let allocator = ByteBufferAllocator()
let packetsToSend = (0..<5).map { allocator.buffer(string: "Hello from server, message \($0)\n") }

do {
    // Create the TCP Sender that will wait for incoming connections and send packets
    print("Starting TCP Sender...")
    let sender = try TCPSender(host: "::1", port: 9999, packetsToSend: packetsToSend)
    
    // Wait for connections and handle them until program is terminated
    try sender.waitForClose()
    print("TCP Sender terminated")
} catch {
    print("Error: \(error)")
}