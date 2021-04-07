//
//  HttpRequest.swift
//  Squid
//
//  Created by Oliver Borchert on 9/17/19.
//

import Foundation
import Combine

internal struct HttpRequest {

    // MARK: Properties
    let urlRequest: URLRequest
    private let body: HttpBody?

    // MARK: Initialization
    init?(url: UrlConvertible) {
        guard let url = url.url else {
            return nil
        }
        self.urlRequest = URLRequest(url: url)
        self.body = nil
    }

    private init(_ request: URLRequest, _ body: HttpBody?) {
        self.urlRequest = request
        self.body = body
    }

    // MARK: Instance Methods
    func with(scheme: String) -> HttpRequest {
        var request = self.urlRequest
        request.url = request.url
            .map { scheme + "://" + $0.absoluteString.components(separatedBy: "://").last! }
            .flatMap(URL.init(string:))
        return HttpRequest(request, self.body)
    }

    func with(method: HttpMethod) -> HttpRequest {
        var request = self.urlRequest
        method.add(to: &request)
        return HttpRequest(request, self.body)
    }

    func with(route: HttpRoute) -> HttpRequest {
        var request = self.urlRequest
        route.add(to: &request)
        return HttpRequest(request, self.body)
    }

    func with(query: HttpQuery) throws -> HttpRequest {
        var request = self.urlRequest
        try query.add(to: &request)
        return HttpRequest(request, self.body)
    }

    func with(header: HttpHeader) -> HttpRequest {
        var request = self.urlRequest
        header.add(to: &request)
        return HttpRequest(request, self.body)
    }

    func with(body: HttpBody) throws -> HttpRequest {
        var request = self.urlRequest
        try body.add(to: &request)
        return HttpRequest(request, body)
    }

    func process(with execute: (URLRequest) -> URLRequest) -> HttpRequest {
        let newRequest = execute(self.urlRequest)
        return HttpRequest(newRequest, self.body)
    }
}

/// :nodoc:
extension HttpRequest: CustomStringConvertible {

    var description: String {
        let excludeHeader = Squid.Logger.shared.excludeHeader
        let headerString = excludeHeader ? "<excluded>" : (
            self
                .urlRequest
                .allHTTPHeaderFields?
                .httpHeaderDescription?
                .indent(spaces: 12, skipLines: 1) ?? "<none>"
        )

        let excludeBody = Squid.Logger.shared.excludeBody
        let bodyString = excludeBody ? "<excluded>" : (
            self
                .body?
                .description
                .indent(spaces: 12, skipLines: 1) ?? "<none>"
        )

        return """
        - Method:   \(self.urlRequest.httpMethod ?? "<none>")
        - Url:      \(self.urlRequest.url?.absoluteString ?? "<none>")
        - Headers:  \(headerString)
        - Body:     \(bodyString)
        """
    }
}

// MARK: Extension
extension HttpRequest {

    internal static func publisher<R, S>(
        for request: R, service: S
    ) -> AnyPublisher<HttpRequest, Squid.Error> where R: Request, S: HttpService {
        return service.asyncHeader
            .mapError(Squid.Error.ensure(_:))
            .flatMap { header -> Future<HttpRequest, Squid.Error> in
                return .init { promise in
                    // 1) Determine destination url
                    let url = request.url ?? service.apiUrl

                    // 2) Initialize request with destination URL
                    guard var httpRequest = HttpRequest(url: url) else {
                        promise(.failure(.invalidUrl))
                        return
                    }

                    // 3) Modify request to carry all required data
                    do {
                        let secure = request.usesSecureProtocol ?? service.usesSecureProtocol
                        httpRequest = try httpRequest
                            .with(scheme: secure ? "https" : "http")
                            .with(method: request.method)
                            .with(route: request.routes)
                            .with(query: request.query)
                            .with(header: service.header + header + request.header)
                            .with(body: request.body)
                            .process(with: request.prepare(_:))
                    } catch {
                        promise(.failure(.ensure(error)))
                    }

                    // 4) Validate request
                    if let error = request.validate() {
                        promise(.failure(error))
                    }

                    promise(.success(httpRequest))
                }
            }.eraseToAnyPublisher()
    }

    internal static func streamPublisher<R, S>(
        for request: R, service: S
    ) -> AnyPublisher<HttpRequest, Squid.Error> where R: StreamRequest, S: HttpService {
        return service.asyncHeader
            .mapError(Squid.Error.ensure(_:))
            .flatMap { header -> Future<HttpRequest, Squid.Error> in
                return .init { promise in
                    // 1) Determine destination url
                    let url = request.url ?? service.apiUrl

                    // 2) Initialize request with destination URL
                    guard var httpRequest = HttpRequest(url: url) else {
                        promise(.failure(.invalidUrl))
                        return
                    }

                    // 3) Modify request to carry all required data
                    do {
                        let secure = request.usesSecureProtocol ?? service.usesSecureProtocol
                        httpRequest = try httpRequest
                            .with(scheme: secure ? "wss" : "ws")
                            .with(method: .get)
                            .with(route: request.routes)
                            .with(query: request.query)
                            .with(header: service.header + header + request.header)
                    } catch {
                        promise(.failure(.ensure(error)))
                    }

                    promise(.success(httpRequest))
                }
            }.eraseToAnyPublisher()
    }
}
