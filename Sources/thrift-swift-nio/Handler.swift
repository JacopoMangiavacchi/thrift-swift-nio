//
//  Handler.swift
//  SwiftNIOTest
//
//  Created by Jacopo Mangiavacchi on 3/1/18.
//

import Foundation
import NIO
import NIOHTTP1
import Thrift

public class Handler: ChannelInboundHandler {
    private enum FileIOMethod {
        case sendfile
        case nonblockingFileIO
    }
    public typealias InboundIn = HTTPServerRequestPart
    public typealias OutboundOut = HTTPServerResponsePart
    
    private var requestUri: String?
    private var keepAlive = false
    
    private let fileIO: NonBlockingFileIO
    private let processor: Processor
    
    private let inProtocolType: TProtocol.Type
    private let outProtocolType: TProtocol.Type
    
    public init(fileIO: NonBlockingFileIO, processor: Processor, inProtocolType: TProtocol.Type, outProtocolType: TProtocol.Type) {
        self.fileIO = fileIO
        self.processor = processor
        self.inProtocolType = inProtocolType
        self.outProtocolType = outProtocolType
    }
    
    public func channelRead(ctx: ChannelHandlerContext, data: NIOAny) {
        let reqPart = self.unwrapInboundIn(data)
        
        switch reqPart {
        case .head(let request):
            keepAlive = request.isKeepAlive
            
            //TODO: Get InProtocol && OutProtocol
            let itrans = TMemoryBufferTransport()
            // if let bytes = request.postBodyBytes {
            //     let data = Data(bytes: bytes)
            //     itrans.reset(readBuffer: data)
            // }

            var bodyOutputBuffer = [UInt8]()
            let sem = DispatchSemaphore(value: 0)

            let otrans = TMemoryBufferTransport(flushHandler: { trans, buff in
                bodyOutputBuffer = buff.withUnsafeBytes {
                    Array<UInt8>(UnsafeBufferPointer(start: $0, count: buff.count))
                }

                sem.signal()
            })

            let inproto = inProtocolType.init(on: itrans)
            let outproto = outProtocolType.init(on: otrans)

            do {
                try processor.process(on: inproto, outProtocol: outproto)
                try otrans.flush()

                sem.wait()

                var buffer = ctx.channel.allocator.buffer(capacity: bodyOutputBuffer.count)
                buffer.write(bytes: bodyOutputBuffer)

                var responseHead = HTTPResponseHead(version: request.version, status: HTTPResponseStatus.ok)
                responseHead.headers.add(name: "content-type", value: "application/x-thrift")
                responseHead.headers.add(name: "content-length", value: String(bodyOutputBuffer.count))

                let response = HTTPServerResponsePart.head(responseHead)
                ctx.write(self.wrapOutboundOut(response), promise: nil)
                
                let content = HTTPServerResponsePart.body(.byteBuffer(buffer.slice()))
                ctx.write(self.wrapOutboundOut(content), promise: nil)
            } catch {
                var buffer = ctx.channel.allocator.buffer(capacity: 5)
                buffer.write(staticString: "error")

                var responseHead = HTTPResponseHead(version: request.version, status: HTTPResponseStatus.ok)
                responseHead.headers.add(name: "content-length", value: String(buffer.readableBytes))

                let response = HTTPServerResponsePart.head(responseHead)
                ctx.write(self.wrapOutboundOut(response), promise: nil)
                
                let content = HTTPServerResponsePart.body(.byteBuffer(buffer.slice()))
                ctx.write(self.wrapOutboundOut(content), promise: nil)
            }
        case .body:
            break
        case .end:
            if keepAlive {
                ctx.write(self.wrapOutboundOut(HTTPServerResponsePart.end(nil)), promise: nil)
            } else {
                ctx.write(self.wrapOutboundOut(HTTPServerResponsePart.end(nil))).whenComplete {
                    ctx.close(promise: nil)
                }
            }
        }
    }
    
    public func channelReadComplete(ctx: ChannelHandlerContext) {
        ctx.flush()
    }
}
