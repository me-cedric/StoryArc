import XCTest

/// Fixtures the wave 5 frame walks share: two answering catalogues and nothing else.
enum Wave5 {

    /// Attic and Loft only, so no third source raises a "has not been read yet" toast.
    static var twoCatalogues: String {
        """
        {"sources":[
        {"id":"11111111-1111-4111-8111-111111111111","displayName":"\(MockCatalogues.attic)",\
        "kind":"opdsCatalog","lastSuccessfulSync":null,"credentialReference":null,\
        "locator":"http://127.0.0.1:\(MockCatalogues.firstPort)/opds/all"},
        {"id":"22222222-2222-4222-8222-222222222222","displayName":"\(MockCatalogues.loft)",\
        "kind":"opdsCatalog","lastSuccessfulSync":null,"credentialReference":null,\
        "locator":"http://127.0.0.1:\(MockCatalogues.secondPort)/opds/all"}
        ],"tombstones":[]}
        """
    }
}
