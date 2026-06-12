import Foundation
import LyraVoiceCore

/// Транскрибация через OpenAI API (whisper-1, gpt-4o-transcribe, gpt-4o-mini-transcribe).
/// Требует API-ключ и интернет; аудио уходит на сервера OpenAI.
enum CloudTranscriptionService {
    static func transcribe(
        audioURL: URL,
        apiKey: String,
        model: OpenAITranscriptionModel,
        language: String
    ) throws -> String {
        guard !apiKey.isEmpty else {
            throw CloudTranscriptionError.missingAPIKey
        }

        let audioData: Data
        do {
            audioData = try Data(contentsOf: audioURL)
        } catch {
            throw CloudTranscriptionError.audioReadFailed(error.localizedDescription)
        }

        let boundary = "LyraVoiceCloud\(UUID().uuidString.replacingOccurrences(of: "-", with: ""))"
        var body = Data()

        func crlf() { body.append("\r\n".data(using: .utf8)!) }
        func str(_ s: String) { body.append(s.data(using: .utf8)!) }
        func field(_ name: String, _ value: String) {
            str("--\(boundary)\r\n")
            str("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n")
            str(value)
            crlf()
        }

        str("--\(boundary)\r\n")
        str("Content-Disposition: form-data; name=\"file\"; filename=\"audio.wav\"\r\n")
        str("Content-Type: audio/wav\r\n\r\n")
        body.append(audioData)
        crlf()

        field("model", model.rawValue)
        field("response_format", "json")
        // Передаём язык только если задан явно (не auto — OpenAI не понимает "auto").
        if language != "auto", language.count == 2 || language.count == 5 {
            field("language", language)
        }
        str("--\(boundary)--\r\n")

        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/audio/transcriptions")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        request.timeoutInterval = 60

        let semaphore = DispatchSemaphore(value: 0)
        let box = ResultBox<String>()

        URLSession.shared.dataTask(with: request) { data, response, error in
            defer { semaphore.signal() }
            if let error {
                box.error = CloudTranscriptionError.requestFailed(error.localizedDescription)
                return
            }
            if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                let body = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
                box.error = CloudTranscriptionError.httpError(http.statusCode, body)
                return
            }
            guard let data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let text = json["text"] as? String else {
                box.error = CloudTranscriptionError.invalidResponse
                return
            }
            box.value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        }.resume()

        semaphore.wait()

        if let error = box.error { throw error }
        return box.value ?? ""
    }
}

enum CloudTranscriptionError: Error, LocalizedError {
    case missingAPIKey
    case audioReadFailed(String)
    case requestFailed(String)
    case httpError(Int, String)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "Нет API-ключа OpenAI. Добавьте ключ в разделе «Модель»."
        case .audioReadFailed(let m):
            return "Ошибка чтения аудио: \(m)"
        case .requestFailed(let m):
            return "Сеть: \(m)"
        case .httpError(let code, let body):
            let hint = body.contains("invalid_api_key") ? " (неверный ключ)" : ""
            return "OpenAI HTTP \(code)\(hint)"
        case .invalidResponse:
            return "Неожиданный ответ OpenAI API"
        }
    }
}

private final class ResultBox<T>: @unchecked Sendable {
    var value: T?
    var error: Error?
}
