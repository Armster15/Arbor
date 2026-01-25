import UIKit

public func isValidURL(_ string: String) -> Bool {
    let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
    let lowercased = trimmed.lowercased()

    if lowercased.hasPrefix("http://") || lowercased.hasPrefix("https://") {
        if let _ = URL(string: lowercased) {
            return true
        }
    }

    return false
}

public func formattedTime(_ seconds: Double) -> String {
    guard seconds.isFinite && !seconds.isNaN else { return "--:--" }
    let s = Int(seconds.rounded())
    let mins = s / 60
    let secs = s % 60
    return String(format: "%d:%02d", mins, secs)
}

public func sanitizeForFilename(_ string: String) -> String {
    // Remove or replace characters that are unsafe for filenames
    let unsafeCharacters = CharacterSet(charactersIn: "/\\:*?\"<>|")
    let sanitized = string.components(separatedBy: unsafeCharacters).joined(separator: "_")
    
    // Also replace newlines and trim whitespace
    let cleaned = sanitized
        .replacingOccurrences(of: "\n", with: " ")
        .replacingOccurrences(of: "\r", with: " ")
        .trimmingCharacters(in: .whitespacesAndNewlines)
    
    // Limit length to avoid extremely long filenames (max 100 chars per field)
    return String(cleaned.prefix(100))
}

public func formatArtists(_ artists: [String]) -> String {
    let cleaned = artists
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
    return cleaned.isEmpty ? "N/A" : cleaned.joined(separator: ", ")
}

extension UIImage {
    func croppedToSquare() -> UIImage {
        let sideLength = min(size.width, size.height)
        guard sideLength > 0 else { return self }
        let originX = (size.width - sideLength) * 0.5
        let originY = (size.height - sideLength) * 0.5
        let cropRect = CGRect(
            x: originX * scale,
            y: originY * scale,
            width: sideLength * scale,
            height: sideLength * scale
        )
        guard let cgImage = cgImage?.cropping(to: cropRect) else { return self }
        return UIImage(cgImage: cgImage, scale: scale, orientation: imageOrientation)
    }
}

// Saving images to photos library is at its core simply just UIImageWriteToSavedPhotosAlbum(uiImage, nil, nil, nil),
// but because of some historic Objective-C lore, we need a class for other functionality like error handling.
// https://www.hackingwithswift.com/books/ios-swiftui/how-to-save-images-to-the-users-photo-library
public class ImageSaver: NSObject {
    var onSuccess: (() -> Void)?
    var onError: ((Error) -> Void)?
    
    func save(_ image: UIImage) {
        UIImageWriteToSavedPhotosAlbum(image, self, #selector(saveCompleted), nil)
    }
    
    @objc func saveCompleted(_ image: UIImage, didFinishSavingWithError error: Error?, contextInfo: UnsafeRawPointer) {
        if let error = error {
            onError?(error)
        } else {
            onSuccess?()
        }
    }
}


// Imperatively show alerts like we can with JavaScript
public func showAlert(title: String, message: String, dismissButtonTitle: String = "OK") {
    DispatchQueue.main.async {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let rootVC = windowScene.windows.first?.rootViewController else { return }
        
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: dismissButtonTitle, style: .default))
        
        // Find the topmost presented view controller
        var topVC = rootVC
        while let presented = topVC.presentedViewController {
            topVC = presented
        }
        topVC.present(alert, animated: true)
    }
}
