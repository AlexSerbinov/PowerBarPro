import Foundation

/// Structured LLM response about a process.
struct ProcessDescription: Codable {
    let description: String
    let isSystem: Bool
    let safeToClose: Bool

    /// Formatted tooltip text.
    func tooltip(processName: String) -> String {
        let typeTag = isSystem ? "[SYSTEM]" : "[APP]"
        let safeTag = safeToClose ? "Safe to close" : "Do NOT close"
        return "\(typeTag) \(processName)\n\(description)\n\(safeTag)"
    }
}

/// Calls Groq API to get description of macOS processes.
/// Caches results per (processName, language) to disk.
/// Pre-fetches descriptions when process list updates.
final class ProcessDescriptionService {

    /// LLM API configuration, loaded from (in priority order):
    /// 1. `OPENROUTER_API_KEY` environment variable
    /// 2. `openRouterAPIKey` in UserDefaults
    /// 3. `config.json` in ~/Library/Application Support/PowerBarPro/
    /// Without a key the service works in cached-only mode (no network calls).
    private let apiKey: String?
    private let apiURL: String
    private let model: String

    // Cache: "processName:lang" → ProcessDescription
    private var cache: [String: ProcessDescription] = [:]
    private let cacheFileURL: URL
    private let lock = NSLock()

    // Track in-flight requests to avoid duplicates
    private var inFlight: Set<String> = []

    private struct FileConfig: Codable {
        let openRouterAPIKey: String?
        let model: String?
        let apiURL: String?
    }

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support")
        let dir = appSupport.appendingPathComponent("PowerBarPro")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.cacheFileURL = dir.appendingPathComponent("process_descriptions_v2.json")

        let fileConfig = (try? Data(contentsOf: dir.appendingPathComponent("config.json")))
            .flatMap { try? JSONDecoder().decode(FileConfig.self, from: $0) }

        let envKey = ProcessInfo.processInfo.environment["OPENROUTER_API_KEY"]
        let defaultsKey = UserDefaults.standard.string(forKey: "openRouterAPIKey")
        let resolvedKey = [envKey, defaultsKey, fileConfig?.openRouterAPIKey]
            .compactMap { $0 }
            .first { !$0.isEmpty }

        self.apiKey = resolvedKey
        self.apiURL = fileConfig?.apiURL ?? "https://openrouter.ai/api/v1/chat/completions"
        self.model = fileConfig?.model ?? "openai/gpt-4.1-mini"

        loadCache()
    }

    // MARK: - Public API

    /// Get cached description (nil if not yet fetched).
    func getCached(processName: String, language: String) -> ProcessDescription? {
        lock.lock()
        defer { lock.unlock() }
        return cache["\(processName):\(language)"]
    }

    /// Pre-fetch descriptions for a list of process names.
    /// Fetches only those not already cached. Non-blocking.
    func prefetch(processNames: [String], language: String) {
        guard apiKey != nil else { return }  // cached-only mode
        for name in processNames {
            let key = "\(name):\(language)"

            lock.lock()
            let hasCached = cache[key] != nil
            let isInFlight = inFlight.contains(key)
            if !hasCached && !isInFlight {
                inFlight.insert(key)
            }
            lock.unlock()

            if hasCached || isInFlight { continue }

            DispatchQueue.global(qos: .utility).async { [weak self] in
                self?.fetchFromAPI(processName: name, language: language) { desc in
                    guard let self = self else { return }
                    self.lock.lock()
                    self.cache[key] = desc
                    self.inFlight.remove(key)
                    self.lock.unlock()
                    self.saveCache()
                }
            }
        }
    }

    /// Get description with async callback. Returns cached immediately if available.
    func getDescription(processName: String, language: String, completion: @escaping (ProcessDescription) -> Void) {
        if let cached = getCached(processName: processName, language: language) {
            DispatchQueue.main.async { completion(cached) }
            return
        }

        guard apiKey != nil else { return }  // cached-only mode: no fetch, keep basic tooltip

        DispatchQueue.global(qos: .utility).async { [weak self] in
            self?.fetchFromAPI(processName: processName, language: language) { desc in
                guard let self = self else { return }
                let key = "\(processName):\(language)"
                self.lock.lock()
                self.cache[key] = desc
                self.lock.unlock()
                self.saveCache()
                DispatchQueue.main.async { completion(desc) }
            }
        }
    }

    // MARK: - API Call

    private func fetchFromAPI(processName: String, language: String, completion: @escaping (ProcessDescription) -> Void) {
        guard let apiKey = apiKey else {
            // No API key configured — cached-only mode
            completion(ProcessDescription(description: "Unknown process", isSystem: false, safeToClose: true))
            return
        }
        let langInstr = language == "ua"
            ? "Відповідай українською мовою. Поле description — українською."
            : "Reply in English."

        let prompt = """
        macOS process: "\(processName)". \(langInstr)
        Return JSON: {"description": "one sentence what this process does", "is_system": true/false, "safe_to_close": true/false}
        """

        let body: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "user", "content": prompt]
            ],
            "max_tokens": 500,
            "temperature": 0.2,
            "response_format": ["type": "json_object"]  // Structured JSON output
        ]

        guard let url = URL(string: apiURL),
              let jsonData = try? JSONSerialization.data(withJSONObject: body) else {
            completion(ProcessDescription(description: "Unknown process", isSystem: false, safeToClose: true))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = jsonData
        request.timeoutInterval = 15

        URLSession.shared.dataTask(with: request) { data, _, _ in
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let choices = json["choices"] as? [[String: Any]],
                  let message = choices.first?["message"] as? [String: Any],
                  let content = message["content"] as? String,
                  !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                completion(ProcessDescription(description: "Unknown process", isSystem: false, safeToClose: true))
                return
            }

            // Parse structured JSON response
            let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
            if let jsonData = trimmed.data(using: .utf8),
               let parsed = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] {
                let desc = parsed["description"] as? String ?? "Unknown process"
                let isSys = parsed["is_system"] as? Bool ?? false
                let safe = parsed["safe_to_close"] as? Bool ?? true
                completion(ProcessDescription(description: desc, isSystem: isSys, safeToClose: safe))
            } else {
                // Fallback for non-JSON response
                completion(ProcessDescription(description: trimmed.prefix(120) + "...", isSystem: false, safeToClose: true))
            }
        }.resume()
    }

    // MARK: - Persistence

    private func loadCache() {
        guard let data = try? Data(contentsOf: cacheFileURL),
              let dict = try? JSONDecoder().decode([String: ProcessDescription].self, from: data) else { return }
        cache = dict
    }

    private func saveCache() {
        lock.lock()
        let snapshot = cache
        lock.unlock()
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        try? data.write(to: cacheFileURL)
    }
}
