//===----------------------------------------------------------------------===//
//
// This source file is part of the Soto for AWS open source project
//
// Copyright (c) 2017-2020 the Soto project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of Soto project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import AsyncHTTPClient
import Foundation
import Logging
import SotoCore
import XCTest

@propertyWrapper public struct EnvironmentVariable<Value: LosslessStringConvertible> {
    var defaultValue: Value
    var variableName: String

    public init(_ variableName: String, default: Value) {
        self.defaultValue = `default`
        self.variableName = variableName
    }

    public var wrappedValue: Value {
        guard let value = Environment[variableName] else { return self.defaultValue }
        return Value(value) ?? self.defaultValue
    }
}

public func createAWSClient(
    credentialProvider: CredentialProviderFactory = .default,
    retryPolicy: RetryPolicyFactory = .noRetry,
    middlewares: AWSMiddlewareProtocol = TestEnvironment.middlewares,
    options: AWSClient.Options = .init(),
    httpClient: AWSHTTPClient = HTTPClient.shared,
    logger: Logger = TestEnvironment.logger
) -> AWSClient {
    AWSClient(
        credentialProvider: credentialProvider,
        retryPolicy: retryPolicy,
        middleware: middlewares,
        options: options,
        httpClient: httpClient,
        logger: logger
    )
}

public func createServiceConfig(
    region: Region? = nil,
    partition: AWSPartition = .aws,
    amzTarget: String? = nil,
    service: String = "test",
    signingName: String? = nil,
    serviceProtocol: ServiceProtocol = .restjson,
    apiVersion: String = "01-01-2001",
    endpoint: String? = nil,
    serviceEndpoints: [String: String] = [:],
    partitionEndpoints: [AWSPartition: (endpoint: String, region: Region)] = [:],
    variantEndpoints: [EndpointVariantType: AWSServiceConfig.EndpointVariant] = [:],
    errorType: AWSErrorType.Type? = nil,
    xmlNamespace: String? = nil,
    middlewares: AWSMiddlewareProtocol? = nil,
    timeout: TimeAmount? = nil,
    options: AWSServiceConfig.Options = []
) -> AWSServiceConfig {
    AWSServiceConfig(
        region: region,
        partition: partition,
        amzTarget: amzTarget,
        serviceName: service,
        serviceIdentifier: service,
        signingName: signingName,
        serviceProtocol: serviceProtocol,
        apiVersion: apiVersion,
        endpoint: endpoint,
        serviceEndpoints: serviceEndpoints,
        partitionEndpoints: partitionEndpoints,
        variantEndpoints: variantEndpoints,
        errorType: errorType,
        xmlNamespace: xmlNamespace,
        middleware: middlewares,
        timeout: timeout,
        options: options
    )
}

// create a buffer of random values. Will always create the same given you supply the same z and w values
// Random number generator from https://www.codeproject.com/Articles/25172/Simple-Random-Number-Generation
public func createRandomBuffer(_ w: UInt, _ z: UInt, size: Int) -> [UInt8] {
    var z = z
    var w = w
    func getUInt8() -> UInt8 {
        z = 36969 * (z & 65535) + (z >> 16)
        w = 18000 * (w & 65535) + (w >> 16)
        return UInt8(((z << 16) + w) & 0xFF)
    }
    var data = [UInt8](repeating: 0, count: size)
    for i in 0..<size {
        data[i] = getUInt8()
    }
    return data
}

/// Provide various test environment variables
public enum TestEnvironment {
    /// current list of middleware
    public static var middlewares: AWSMiddlewareProtocol {
        (Environment["AWS_ENABLE_LOGGING"] == "true")
            ? AWSLoggingMiddleware(logger: TestEnvironment.logger, logLevel: .info)
            : AWSMiddleware { request, context, next in
                try await next(request, context)
            }
    }

    public static let logger: Logger = {
        if let loggingLevel = Environment["AWS_LOG_LEVEL"] {
            if let logLevel = Logger.Level(rawValue: loggingLevel.lowercased()) {
                var logger = Logger(label: "soto")
                logger.logLevel = logLevel
                return logger
            }
        }
        return AWSClient.loggingDisabled
    }()
}

/// Run closure and then run teardown closure once closure has either returned or throw an error
public func withTeardown<Value>(_ process: () async throws -> Value, teardown: () async -> Void) async throws -> Value {
    let result: Value
    do {
        result = try await process()
    } catch {
        await teardown()
        throw error
    }
    await teardown()
    return result
}
