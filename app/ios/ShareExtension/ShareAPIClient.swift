import Foundation

struct ShareRoom: Decodable {
  let id: Int
  let name: String
  let status: String?
}

struct ShareFolder: Decodable {
  let id: Int
  let name: String
}

enum ShareAPIError: Error {
  case invalidResponse
  case httpStatus(Int)
  case emptyResponse
}

final class ShareAPIClient {
  private let baseURL: URL
  private let session: URLSession

  init(baseURL: URL, session: URLSession = .shared) {
    self.baseURL = baseURL
    self.session = session
  }

  func fetchRooms(
    token: String,
    completion: @escaping (Result<[ShareRoom], Error>) -> Void
  ) {
    request(path: "/rooms", token: token) { result in
      switch result {
      case .success(let data):
        do {
          completion(.success(try JSONDecoder().decode([ShareRoom].self, from: data)))
        } catch {
          completion(.failure(error))
        }
      case .failure(let error):
        completion(.failure(error))
      }
    }
  }

  func fetchFolders(
    roomID: Int,
    token: String,
    completion: @escaping (Result<[ShareFolder], Error>) -> Void
  ) {
    request(path: "/rooms/\(roomID)/archive/folders", token: token) { result in
      switch result {
      case .success(let data):
        do {
          completion(.success(try JSONDecoder().decode([ShareFolder].self, from: data)))
        } catch {
          completion(.failure(error))
        }
      case .failure(let error):
        completion(.failure(error))
      }
    }
  }

  /// 공유 시트 안에서 새 아카이브 폴더를 만든다(QA).
  /// 서버 응답(id/name/itemCount/thumbnail)에서 ShareFolder(id/name)만 디코딩한다.
  func createFolder(
    roomID: Int,
    name: String,
    token: String,
    completion: @escaping (Result<ShareFolder, Error>) -> Void
  ) {
    guard let body = try? JSONSerialization.data(withJSONObject: ["name": name]) else {
      completion(.failure(ShareAPIError.invalidResponse))
      return
    }
    request(
      path: "/rooms/\(roomID)/archive/folders",
      method: "POST",
      token: token,
      body: body
    ) { result in
      switch result {
      case .success(let data):
        do {
          completion(.success(try JSONDecoder().decode(ShareFolder.self, from: data)))
        } catch {
          completion(.failure(error))
        }
      case .failure(let error):
        completion(.failure(error))
      }
    }
  }

  func registerItem(
    roomID: Int,
    folderID: Int,
    title: String,
    content: ShareContent,
    token: String,
    completion: @escaping (Result<Void, Error>) -> Void
  ) {
    var payload: [String: String] = ["title": title]
    if content.isURL {
      payload["url"] = content.value
    } else {
      payload["text"] = content.value
    }

    guard let body = try? JSONSerialization.data(withJSONObject: payload) else {
      completion(.failure(ShareAPIError.invalidResponse))
      return
    }

    request(
      path: "/rooms/\(roomID)/archive/folders/\(folderID)/items/pending",
      method: "POST",
      token: token,
      body: body
    ) { result in
      completion(result.map { _ in () })
    }
  }

  private func request(
    path: String,
    method: String = "GET",
    token: String,
    body: Data? = nil,
    completion: @escaping (Result<Data, Error>) -> Void
  ) {
    let base = baseURL.absoluteString.hasSuffix("/")
      ? String(baseURL.absoluteString.dropLast())
      : baseURL.absoluteString
    guard let url = URL(string: base + path) else {
      completion(.failure(ShareAPIError.invalidResponse))
      return
    }

    var request = URLRequest(url: url, timeoutInterval: 5)
    request.httpMethod = method
    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    if body != nil {
      request.httpBody = body
      request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    }

    session.dataTask(with: request) { data, response, error in
      if let error {
        completion(.failure(error))
        return
      }
      guard let response = response as? HTTPURLResponse else {
        completion(.failure(ShareAPIError.invalidResponse))
        return
      }
      guard (200...299).contains(response.statusCode) else {
        completion(.failure(ShareAPIError.httpStatus(response.statusCode)))
        return
      }
      completion(.success(data ?? Data()))
    }.resume()
  }
}
