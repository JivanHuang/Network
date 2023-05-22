import Combine
import Foundation

public enum HTTPMethod: String {
    case get = "GET"
    case post = "POST"
}

public enum NetworkError: Error {
    case badURL
    case badStatus(statusCode: Int, data: Data?)
    case unknown
    case parse(error: Error)
    case data(error: Error)
}

public protocol RequestType {
    var baseURL: URL { get }
    var path: String { get }
    var parameters: Encodable? { get }
    var method: HTTPMethod { get }
}

@available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 6.0, *)
public protocol APIClientProtocol {
    func request<T: Decodable>(_ endpoint: RequestType) -> AnyPublisher<T, Error>
}

@available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 6.0, *)
public class APIClient: APIClientProtocol {
    private let session: URLSession
    private let jsonDecoder: JSONDecoder

    public init(session: URLSession = .shared, jsonDecoder: JSONDecoder = JSONDecoder()) {
        self.session = session
        self.jsonDecoder = jsonDecoder
    }

    public func request<T: Decodable>(_ endpoint: RequestType) -> AnyPublisher<T, Error> {
        guard var urlComponents = URLComponents(url: endpoint.baseURL, resolvingAgainstBaseURL: true) else {
            return Fail(error: NetworkError.badURL).eraseToAnyPublisher()
        }
        urlComponents.path = endpoint.path
        if endpoint.method == .get {
            urlComponents.queryItems = endpoint.parameters?.asDictionary?.map { key, value in
                URLQueryItem(name: key, value: "\(value)")
            }
        }

        guard let url = urlComponents.url else {
            return Fail(error: NetworkError.badURL).eraseToAnyPublisher()
        }

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = endpoint.method.rawValue
        if let parameters = endpoint.parameters, endpoint.method == .post {
            do {
                let data = try JSONEncoder().encode(parameters)
                urlRequest.httpBody = data
            } catch {
                return Fail(error: NetworkError.data(error: error)).eraseToAnyPublisher()
            }
        }

        return session.dataTaskPublisher(for: urlRequest)
            .tryMap { data, response in
                guard let httpResponse = response as? HTTPURLResponse else {
                    throw NetworkError.badStatus(statusCode: 500, data: data)
                }
                guard 200 ... 299 ~= httpResponse.statusCode else {
                    let code = Int(httpResponse.statusCode)
                    throw NetworkError.badStatus(statusCode: code, data: data)
                }
                return data
            }
            .decode(type: T.self, decoder: jsonDecoder)
            .mapError { error in
                switch error {
                case is URLError:
                    return NetworkError.badURL
                case is Swift.DecodingError:
                    return NetworkError.parse(error: error)
                default:
                    return NetworkError.unknown
                }
            }
            .eraseToAnyPublisher()
    }
}
private extension URLComponents {
    mutating func withPath(_ path: String) {
        self.path = path
    }

    mutating func withQueryItems(_ parameters: Encodable?) {
        queryItems = parameters?.asDictionary?.map { key, value in
            URLQueryItem(name: key, value: "\(value)")
        }
    }
}

private extension Encodable {
    var asDictionary: [String: Any]? {
        guard let data = try? JSONEncoder().encode(self) else { return nil }
        guard let dictionary = try? JSONSerialization.jsonObject(with: data, options: .allowFragments) as? [String: Any] else { return nil }
        return dictionary
    }
}
