public import Foundation

/// The image search a reader is handed off to when no provider can answer.
///
/// `cover-art` asks for "an image search for that publication's title" opened in the system
/// browser. This type builds the address and stops there: the browser performs the search,
/// the reader saves the picture with the browser's own menu, and the app learns of it only
/// when they pick it. `design.md` records why at length — App Store guideline 5.2.3, and the
/// fact that StoryArc's only web view denies all network egress, so a second one that exists
/// to load a search engine would be the opposite rule on the same app.
public enum CoverWebSearch {
    /// DuckDuckGo, because the hand-off must not itself be a tracking event.
    ///
    /// The app has no analytics and no account, and sending a reader's publication titles
    /// to an engine that builds a profile against their signed-in identity would undo that
    /// at the one moment the app chooses the address. DuckDuckGo needs no account, keeps no
    /// profile, and has an image vertical this query reaches directly.
    private static let engine = "https://duckduckgo.com/"

    /// The word appended to the title, so the results are covers rather than the work.
    ///
    /// English only, and deliberately so: the picture a reader wants is the published
    /// artwork, which is indexed under the publisher's own language far more often than
    /// under the reader's. A localised word would narrow the results that matter.
    private static let subject = "cover"

    /// The address the system browser opens for this publication.
    ///
    /// Nil when the title is empty or is only whitespace. A search for nothing returns an
    /// engine's front page, and handing a reader that is worse than not offering the action.
    public static func url(title: String, author: String? = nil) -> URL? {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let author = author?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let terms = [trimmed, author, subject].filter { !$0.isEmpty }.joined(separator: " ")
        var components = URLComponents(string: engine)
        components?.queryItems = [
            URLQueryItem(name: "q", value: terms),
            // The engine's own image vertical. Two parameters, because one of them selects
            // the tab and the other selects the result set, and the engine needs both.
            URLQueryItem(name: "iax", value: "images"),
            URLQueryItem(name: "ia", value: "images"),
        ]
        return components?.plusEscapedURL
    }
}
