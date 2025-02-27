//===----------------------------------------------------------------------===//
//
// This source file is part of the Soto for AWS open source project
//
// Copyright (c) 2017-2023 the Soto project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of Soto project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import NIOCore

/// An AsyncSequence that returns fixed size ByteBuffers from an AsyncSequence of ByteBuffers
public struct FixedSizeByteBufferAsyncSequence<Base: AsyncSequence>: AsyncSequence where Base.Element == ByteBuffer {
    public typealias Element = ByteBuffer

    public let byteBufferSequence: Base
    public let chunkSize: Int

    public struct AsyncIterator: AsyncIteratorProtocol {
        var iterator: Base.AsyncIterator
        let chunkSize: Int
        var currentByteBuffer: ByteBuffer?

        @usableFromInline
        init(sequence: FixedSizeByteBufferAsyncSequence) {
            self.iterator = sequence.byteBufferSequence.makeAsyncIterator()
            self.chunkSize = sequence.chunkSize
        }

        public mutating func next() async throws -> ByteBuffer? {
            // get current bytebuffer or first buffer from source sequence
            var byteBuffer: ByteBuffer
            if let currentByteBuffer = self.currentByteBuffer {
                byteBuffer = currentByteBuffer
            } else {
                if let firstByteBuffer = try await iterator.next() {
                    byteBuffer = firstByteBuffer
                } else {
                    return nil
                }
            }
            byteBuffer.reserveCapacity(self.chunkSize)

            // while current byte buffer does not contain enough bytes read from source sequence
            while byteBuffer.readableBytes < self.chunkSize {
                if var nextByteBuffer = try await iterator.next() {
                    // if next byte buffer has enough bytes to create a chunk
                    if var slice = nextByteBuffer.readSlice(length: self.chunkSize - byteBuffer.readableBytes) {
                        byteBuffer.writeBuffer(&slice)
                        self.currentByteBuffer = nextByteBuffer
                        return byteBuffer
                    } else {
                        byteBuffer.writeBuffer(&nextByteBuffer)
                    }
                } else {
                    // no more byte buffers are available from the source sequence so return what is left
                    self.currentByteBuffer = nil
                    // don't return a ByteBuffer if it is empty
                    if byteBuffer.readableBytes > 0 {
                        return byteBuffer
                    } else {
                        return nil
                    }
                }
            }
            let chunkByteBuffer = byteBuffer.readSlice(length: self.chunkSize)
            self.currentByteBuffer = byteBuffer
            return chunkByteBuffer
        }
    }

    /// Make async iterator
    public __consuming func makeAsyncIterator() -> AsyncIterator {
        AsyncIterator(sequence: self)
    }
}

extension FixedSizeByteBufferAsyncSequence: Sendable where Base: Sendable {}

extension AsyncSequence where Element == ByteBuffer {
    /// Return an AsyncSequence that returns ByteBuffers of a fixed size
    /// - Parameter chunkSize: Size of each chunk
    public func fixedSizeSequence(chunkSize: Int) -> FixedSizeByteBufferAsyncSequence<Self> {
        .init(byteBufferSequence: self, chunkSize: chunkSize)
    }
}
