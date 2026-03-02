//
// Copyright 2026
//

import UIKit
import SignalServiceKit

/// Displays Bulletin HTML from the Directus JSON endpoint using a text view (no WebKit),
/// avoiding WebContent process and related simulator/system errors.
final class BulletinViewController: UIViewController {

    private let bulletinURL: URL
    private let textView: UITextView = {
        let v = UITextView()
        v.isEditable = false
        v.isSelectable = true
        v.dataDetectorTypes = [.link]
        v.textContainerInset = UIEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
        v.backgroundColor = .clear
        return v
    }()
    private let loadingIndicator = UIActivityIndicatorView(style: .large)

    init(bulletinURL: URL, title: String) {
        self.bulletinURL = bulletinURL
        super.init(nibName: nil, bundle: nil)
        self.title = title
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        loadingIndicator.hidesWhenStopped = true
        view.addSubview(loadingIndicator)
        view.addSubview(textView)
        textView.isHidden = true

        loadingIndicator.translatesAutoresizingMaskIntoConstraints = false
        textView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            loadingIndicator.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            loadingIndicator.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            textView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            textView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            textView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
            textView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor)
        ])

        loadingIndicator.startAnimating()
        fetchBulletin()
    }

    private func fetchBulletin() {
        var request = URLRequest(url: bulletinURL)
        let apiKey = DirectusConfig.apiKey
        if !apiKey.isEmpty {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }

        let task = URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                guard let self else { return }

                if let error {
                    self.loadingIndicator.stopAnimating()
                    self.presentError(message: error.localizedDescription)
                    return
                }

                guard let http = response as? HTTPURLResponse else {
                    self.loadingIndicator.stopAnimating()
                    self.presentError(message: "Unable to load bulletin (no HTTP response).")
                    return
                }

                // Handle non-2xx responses (e.g. 403 from Directus with an errors array).
                if !(200..<300).contains(http.statusCode) {
                    if
                        let data,
                        let directusError = try? JSONDecoder().decode(DirectusErrorResponse.self, from: data),
                        let firstError = directusError.errors.first
                    {
                        self.loadingIndicator.stopAnimating()
                        self.presentError(message: firstError.message)
                        return
                    } else {
                        self.loadingIndicator.stopAnimating()
                        self.presentError(message: "Unable to load bulletin (HTTP \(http.statusCode)).")
                        return
                    }
                }

                guard
                    let data,
                    let bulletin = try? JSONDecoder().decode(BulletinResponse.self, from: data)
                else {
                    self.loadingIndicator.stopAnimating()
                    self.presentError(message: "Unable to load bulletin.")
                    return
                }

                if !bulletin.data.subject.isEmpty {
                    self.title = bulletin.data.subject
                }

                self.loadingIndicator.stopAnimating()
                self.displayHTML(bulletin.data.body)
            }
        }

        task.resume()
    }

    private func displayHTML(_ html: String) {
        let wrapped = """
        <!DOCTYPE html><html><head><meta charset="UTF-8"><style>\
        body { font: -apple-system-body; color: \(cssColor(UIColor.label)); }\
        p { margin: 0 0 0.75em; } p:last-child { margin-bottom: 0; }\
        strong { font-weight: 600; } ul { margin: 0.5em 0; padding-left: 1.2em; }
        </style></head><body>\(html)</body></html>
        """
        guard let data = wrapped.data(using: .utf8) else {
            textView.text = html
            textView.isHidden = false
            return
        }
        let options: [NSAttributedString.DocumentReadingOptionKey: Any] = [
            .documentType: NSAttributedString.DocumentType.html,
            .characterEncoding: String.Encoding.utf8.rawValue
        ]
        if let attributed = try? NSMutableAttributedString(
            data: data,
            options: options,
            documentAttributes: nil
        ) {
            // Ensure readable font and dynamic type
            let fullRange = NSRange(location: 0, length: attributed.length)
            attributed.addAttribute(
                .font,
                value: UIFont.preferredFont(forTextStyle: .body),
                range: fullRange
            )
            attributed.addAttribute(
                .foregroundColor,
                value: UIColor.label,
                range: fullRange
            )
            textView.attributedText = attributed
        } else {
            textView.text = html
        }
        textView.isHidden = false
    }

    private func cssColor(_ color: UIColor) -> String {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.getRed(&r, green: &g, blue: &b, alpha: &a)
        return "rgba(\(Int(r * 255)),\(Int(g * 255)),\(Int(b * 255)),\(a))"
    }

    private func presentError(message: String) {
        let alert = UIAlertController(title: "Error", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
}

// MARK: - Decoding

private struct BulletinResponse: Decodable {
    struct BulletinData: Decodable {
        let subject: String
        let body: String
    }

    let data: BulletinData
}

// Directus error envelope for non-2xx responses.
private struct DirectusErrorResponse: Decodable {
    struct DirectusError: Decodable {
        let message: String
    }

    let errors: [DirectusError]
}
