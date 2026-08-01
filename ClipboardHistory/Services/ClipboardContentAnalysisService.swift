import Foundation
import Vision

actor ClipboardContentAnalysisService: ClipboardContentAnalyzing {
    func analyze(
        _ content: ClipboardContent,
        recognizesImageText: Bool
    ) async -> ClipboardContentAnalysis {
        switch content {
        case let .text(value, _, _, _, _, _):
            return ClipboardContentAnalysis(colorHex: ColorParser.hexColor(from: value))
        case let .images(pngData, _, _):
            guard let firstImage = pngData.first else { return .empty }
            return analyzeImage(firstImage, recognizesText: recognizesImageText)
        case .pdf, .files:
            return .empty
        }
    }

    private func analyzeImage(_ data: Data, recognizesText: Bool) -> ClipboardContentAnalysis {
        let barcodeRequest = VNDetectBarcodesRequest()
        barcodeRequest.symbologies = [.qr]
        var requests: [VNRequest] = [barcodeRequest]
        let textRequest: VNRecognizeTextRequest?
        if recognizesText {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            requests.append(request)
            textRequest = request
        } else {
            textRequest = nil
        }

        do {
            try VNImageRequestHandler(data: data).perform(requests)
            let lines = textRequest?.results?
                .compactMap { $0.topCandidates(1).first?.string }
                .filter { !$0.isEmpty } ?? []
            let qrCode = barcodeRequest.results?
                .compactMap(\.payloadStringValue)
                .first { !$0.isEmpty }
            return ClipboardContentAnalysis(
                extractedText: lines.isEmpty ? nil : lines.joined(separator: "\n"),
                qrCodeText: qrCode,
                colorHex: nil
            )
        } catch {
            AppLog.clipboard.error(
                "On-device image analysis failed; category=\(String(describing: type(of: error)), privacy: .public)"
            )
            return .empty
        }
    }
}
