import Foundation
import WebKit

final class LocalResources: NSObject, WKURLSchemeHandler {
    let directory: URL

    init(directory: URL) { self.directory = directory.standardizedFileURL }

    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        guard let url = urlSchemeTask.request.url, url.host == "app", urlSchemeTask.request.httpMethod == "GET" else {
            urlSchemeTask.didFailWithError(URLError(.unsupportedURL))
            return
        }
        let file = directory.appendingPathComponent(url.path).standardizedFileURL
        guard file.path.hasPrefix(directory.path + "/"), let data = try? Data(contentsOf: file) else {
            urlSchemeTask.didFailWithError(URLError(.fileDoesNotExist))
            return
        }
        let types = ["html": "text/html", "js": "text/javascript", "mjs": "text/javascript",
                     "css": "text/css", "woff2": "font/woff2", "svg": "image/svg+xml", "png": "image/png"]
        let response = URLResponse(url: url, mimeType: types[file.pathExtension] ?? "application/octet-stream",
                                   expectedContentLength: data.count, textEncodingName: ["html", "js", "mjs", "css", "svg"].contains(file.pathExtension) ? "utf-8" : nil)
        urlSchemeTask.didReceive(response)
        urlSchemeTask.didReceive(data)
        urlSchemeTask.didFinish()
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {}
}
