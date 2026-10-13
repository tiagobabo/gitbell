import Foundation

// Just enough of CircleCI's API to approve a job that's on hold.
struct CircleCIClient {
    let token: String
    private let base = URL(string: "https://circleci.com/api/v2")!

    private struct ErrorBody: Decodable { let message: String }

    private struct Jobs: Decodable {
        struct Job: Decodable {
            let name: String
            let type: String
            let status: String
            let approvalRequestId: String?
        }
        let items: [Job]
    }

    // The token's owner, which also tells us the token works.
    func me() async throws -> String {
        struct Me: Decodable { let login: String }
        let me: Me = try await send(base.appending(path: "me"))
        return me.login
    }

    // Approves the held job called `job` in a workflow. Returns false if there was nothing on hold by that name,
    // for instance because someone already approved it.
    func approve(job: String, workflow: String) async throws -> Bool {
        let jobs: Jobs = try await send(base.appending(path: "workflow/\(workflow)/job"))
        guard let held = jobs.items.first(where: { $0.type == "approval" && $0.status == "on_hold" && $0.name == job }),
              let request = held.approvalRequestId else { return false }
        let _: [String: String] = try await send(base.appending(path: "workflow/\(workflow)/approve/\(request)"), method: "POST")
        return true
    }

    private func send<T: Decodable>(_ url: URL, method: String = "GET") async throws -> T {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue(token, forHTTPHeaderField: "Circle-Token")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            let message = (try? JSONDecoder().decode(ErrorBody.self, from: data))?.message ?? "CircleCI returned \(status)"
            throw APIError(status: status, message: status == 401 ? "CircleCI rejected the token in Settings." : message)
        }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(T.self, from: data)
    }
}
