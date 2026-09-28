extension ReaderModel {
    /// Each decoded page's own width-over-height ratio, for ``PagePlaceholder``.
    var decodedRatios: [Int: Double] {
        decoded.compactMapValues { image in
            image.height > 0 ? Double(image.width) / Double(image.height) : nil
        }
    }
}
