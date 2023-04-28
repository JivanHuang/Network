
import Combine
import Foundation

public enum HTTPMethod: String {
    case get = "GET"
    case post = "POST"
}

@available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 6.0, *)
public protocol RequestType {
    associatedtype ResponseObject: Codable

    var method: HTTPMethod { get }
    var baseURL: String { get }
    var path: String { get }
    var headers: [String: String] { get }
    var parameters: [String: Any]? { get }
    var decoder: JSONDecoder { get }
    func request() -> AnyPublisher<ResponseObject, Error>
}

@available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 6.0, *)
public class Network<T: Codable>: RequestType {
    public typealias ResponseObject = T

    public var method: HTTPMethod
    public var baseURL: String
    public var path: String
    public var headers: [String: String]
    public var parameters: [String: Any]?
    public var session: URLSession
    public var decoder: JSONDecoder

    public init(method: HTTPMethod, baseURL: String, path: String, headers: [String: String] = [:], parameters: [String: Any]?, session: URLSession = .shared, decoder: JSONDecoder = JSONDecoder()) {
        self.method = method
        self.baseURL = baseURL
        self.path = path
        self.headers = headers
        self.parameters = parameters
        self.session = session
        self.decoder = decoder
    }

    public func request() -> AnyPublisher<T, Error> {
        guard let url = URL(string: baseURL + path) else {
            return Fail(error: URLError(.badURL))
                .mapError { $0 as Error }
                .eraseToAnyPublisher()
        }

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = method.rawValue
        headers.forEach { key, value in
            urlRequest.addValue(value, forHTTPHeaderField: key)
        }
        if let params = parameters {
            switch method {
            case .get:
                urlRequest.setQueryParameters(params)
            case .post:
                let data = try? JSONSerialization.data(withJSONObject: params)
                urlRequest.httpBody = data
            }
        }
        return session.dataTaskPublisher(for: urlRequest)
            .mapError { $0 as Error }
            .flatMap { data, response -> AnyPublisher<T, Error> in
                guard let httpResponse = response as? HTTPURLResponse, 200 ..< 300 ~= httpResponse.statusCode else {
                    return Fail(error: URLError(.badServerResponse))
                        .mapError { $0 as Error }
                        .eraseToAnyPublisher()
                }
                return Just(data)
                    .decode(type: T.self, decoder: JSONDecoder())
                    .mapError { $0 as Error }
                    .eraseToAnyPublisher()
            }
            .eraseToAnyPublisher()
    }
}

private extension URLRequest {
    mutating func setQueryParameters(_ parameters: [String: Any]) {
        guard let url = url else { return }
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.queryItems = parameters.map { key, value in
            URLQueryItem(name: key, value: "\(value)")
        }
        self.url = components?.url
    }
}
