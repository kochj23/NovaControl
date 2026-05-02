// NovaControl — AI Service Reader (Local LLM Summarization)
// Written by Jordan Koch
// Provides meeting summarization and email summarization via Ollama,
// replacing the need to keep OneOnOne running for Nova's AI features.

import Foundation

actor AIServiceReader {
    static let shared = AIServiceReader()

    private let ollamaEndpoint = "http://127.0.0.1:11434"
    private let defaultModel = "nova:latest"
    private let fallbackModel = "qwen3-coder:30b"
    private let maxTokens = 1024
    private let temperature = 0.7

    // MARK: - Meeting Summarization

    func generateMeetingSummary(meetingId: String) async -> (Int, [String: Any]) {
        let meetings = await OneOnOneReader.shared.fetchMeetings()
        guard let uuid = UUID(uuidString: meetingId) else {
            return (400, ["error": "Invalid meeting ID"])
        }
        guard let meeting = meetings.first(where: { $0.id == uuid }) else {
            return (404, ["error": "Meeting not found", "meetingId": meetingId])
        }
        guard !meeting.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return (422, ["error": "Meeting has no notes to summarize", "meetingId": meetingId])
        }

        let attendees = meeting.attendeeNames.joined(separator: ", ")
        let prompt = """
            You are a helpful assistant that summarizes meeting notes concisely.

            Meeting attendees: \(attendees.isEmpty ? "Not specified" : attendees)

            Meeting notes:
            \(meeting.notes)

            Please provide a brief summary (2-3 paragraphs) of the key points discussed, decisions made, and action items identified.
            """

        let result = await callOllama(prompt: prompt)
        switch result {
        case .success(let summary):
            return (200, [
                "summary": summary,
                "meetingId": meetingId,
                "meetingTitle": meeting.title,
                "model": defaultModel
            ])
        case .failure(let error):
            return (500, ["error": "AI generation failed: \(error.localizedDescription)", "meetingId": meetingId])
        }
    }

    // MARK: - Email/Text Summarization

    func summarize(content: String, context: String?) async -> (Int, [String: Any]) {
        guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return (400, ["error": "Content is empty"])
        }

        var prompt = "You are summarizing an email for Jordan Koch's AI assistant Nova.\n\n"
        if let context = context, !context.isEmpty {
            prompt += "Context: \(context)\n\n"
        }
        prompt += """
            Email:
            \(content)

            Provide a concise summary (2-3 sentences) covering: who sent it, what they are communicating, and any action required from Jordan.
            """

        let result = await callOllama(prompt: prompt)
        switch result {
        case .success(let summary):
            return (200, ["summary": summary, "model": defaultModel])
        case .failure(let error):
            return (500, ["error": "AI generation failed: \(error.localizedDescription)"])
        }
    }

    // MARK: - Action Item Extraction

    func extractActionItems(notes: String) async -> (Int, [String: Any]) {
        guard !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return (400, ["error": "Notes are empty"])
        }

        let prompt = """
            Extract action items from the following meeting notes. Return each action item on its own line, prefixed with "- ".
            Include the assignee if mentioned.

            Notes:
            \(notes)

            Action items:
            """

        let result = await callOllama(prompt: prompt)
        switch result {
        case .success(let text):
            let items = text.components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { $0.hasPrefix("-") || $0.hasPrefix("•") }
                .map { String($0.dropFirst(2)) }
            return (200, ["actionItems": items, "count": items.count, "model": defaultModel])
        case .failure(let error):
            return (500, ["error": "AI generation failed: \(error.localizedDescription)"])
        }
    }

    // MARK: - Ollama API

    private func callOllama(prompt: String) async -> Result<String, Error> {
        guard let url = URL(string: "\(ollamaEndpoint)/api/generate") else {
            return .failure(AIError.invalidURL)
        }

        let body: [String: Any] = [
            "model": defaultModel,
            "prompt": prompt,
            "stream": false,
            "options": [
                "num_predict": maxTokens,
                "temperature": temperature
            ]
        ]

        guard let bodyData = try? JSONSerialization.data(withJSONObject: body) else {
            return .failure(AIError.serializationError)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = bodyData
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 120

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                return .failure(AIError.invalidResponse)
            }

            if http.statusCode == 200 {
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let text = json["response"] as? String, !text.isEmpty {
                    return .success(text.trimmingCharacters(in: .whitespacesAndNewlines))
                }
                return .failure(AIError.emptyResponse)
            }

            // Model not found — try fallback
            if http.statusCode == 404 {
                return await callOllamaFallback(prompt: prompt)
            }

            return .failure(AIError.httpError(http.statusCode))
        } catch {
            return .failure(error)
        }
    }

    private func callOllamaFallback(prompt: String) async -> Result<String, Error> {
        guard let url = URL(string: "\(ollamaEndpoint)/api/generate") else {
            return .failure(AIError.invalidURL)
        }

        let body: [String: Any] = [
            "model": fallbackModel,
            "prompt": prompt,
            "stream": false,
            "options": [
                "num_predict": maxTokens,
                "temperature": temperature
            ]
        ]

        guard let bodyData = try? JSONSerialization.data(withJSONObject: body) else {
            return .failure(AIError.serializationError)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = bodyData
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 120

        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let text = json["response"] as? String, !text.isEmpty {
                return .success(text.trimmingCharacters(in: .whitespacesAndNewlines))
            }
            return .failure(AIError.emptyResponse)
        } catch {
            return .failure(error)
        }
    }

    // MARK: - Error Types

    enum AIError: LocalizedError {
        case invalidURL
        case serializationError
        case invalidResponse
        case emptyResponse
        case httpError(Int)

        var errorDescription: String? {
            switch self {
            case .invalidURL: return "Invalid Ollama URL"
            case .serializationError: return "Failed to serialize request"
            case .invalidResponse: return "Invalid HTTP response"
            case .emptyResponse: return "Model returned empty response"
            case .httpError(let code): return "Ollama returned HTTP \(code)"
            }
        }
    }
}
