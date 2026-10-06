public import Foundation

/// What Kavita's cover-upload route is sent.
///
/// `url` is Kavita's own field name for a picture that may arrive either as an address or
/// as base64, and this client always sends base64: an address would ask the server to fetch
/// a file from this device, which it cannot reach.
struct KavitaCoverUpload: Encodable {
    let id: Int
    let url: String
}

extension KavitaClient {
    /// The largest picture this client will send, in bytes of image.
    ///
    /// Eight megabytes, which `design.md` fixes. Base64 inflates a body by a third, so the
    /// request at this ceiling is about eleven megabytes — comfortably inside a default
    /// ASP.NET Core body limit, and far above any cover a reader actually has. The guard is
    /// here rather than at the screen because the screen is not the only caller a later
    /// change might add.
    public static let coverUploadCeiling = 8 * 1024 * 1024

    /// Writes a cover to a reading list the signed-in reader owns.
    ///
    /// **The one Kavita cover route a normal reader may use.** The other five — series,
    /// volume, chapter, collection and library — require the administrator role, so
    /// `cover-art` forbids offering them at all. ``CoverWriteBack/offer(for:)`` is what
    /// decides that, and this method is what it decides to call.
    ///
    /// **Not verified against a live server.** Task 5.3 of `cover-for-every-publication` is
    /// the owner step that does it, and the mock in `scripts/kavita-server.mjs` is where a
    /// correction gets recorded. The shape below is Kavita's documented `UploadFileDto`.
    public func uploadReadingListCover(_ listID: Int, image: Data) async throws {
        guard !image.isEmpty else { throw KavitaError.imageRejected }
        guard image.count <= Self.coverUploadCeiling else { throw KavitaError.imageTooLarge }
        guard let url = address.endpoint("Upload/reading-list") else {
            throw KavitaError.badAddress
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(
            KavitaCoverUpload(id: listID, url: image.base64EncodedString())
        )
        // Versioned, so an older Kavita without the route says so once and is not asked
        // again for the rest of the session.
        _ = try await sendVersioned(request, path: "Upload/reading-list")
    }
}
