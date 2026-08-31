import Foundation

/// Fixtures read by more than one suite in this target.
///
/// The OPDS 2.0 catalogue below is parsed by both `OpdsParsingTests` and
/// `OpdsAcquisitionSizeTests`, and `bothDialectsAgreeOnOneSize` only means anything while
/// the two suites read the *same* document. A copy per file would let them drift into
/// agreeing about different catalogues, which is the one thing that test exists to catch.
enum OpdsFixtures {
    static let base = URL(string: "https://library.example/opds/")!

    static let opds2 = """
    {
      "metadata": { "title": "Example Library" },
      "links": [
        { "rel": "self", "href": "/opds", "type": "application/opds+json" },
        { "rel": ["next"], "href": "/opds?page=2", "type": "application/opds+json" },
        { "rel": "search", "href": "/opds/search{?query}", "templated": true }
      ],
      "navigation": [
        { "title": "Unread", "href": "/opds/unread", "type": "application/opds+json",
          "properties": { "numberOfItems": 12 } }
      ],
      "groups": [
        {
          "metadata": { "title": "Recently added" },
          "links": [
            { "rel": "self", "href": "/opds/recent", "type": "application/opds+json" }
          ],
          "navigation": [
            { "title": "Series", "href": "/opds/series", "type": "application/opds+json" }
          ],
          "publications": [
            {
              "metadata": {
                "identifier": "urn:uuid:9", "title": "Grouped Title",
                "author": "Grace Hopper"
              },
              "links": [
                { "href": "/download/9.epub", "type": "application/epub+zip",
                  "rel": "http://opds-spec.org/acquisition" }
              ]
            }
          ]
        },
        {
          "publications": [
            {
              "metadata": { "identifier": "urn:uuid:10", "title": "Untitled Group Member" },
              "links": [
                { "href": "/download/10.epub", "type": "application/epub+zip" }
              ]
            }
          ]
        }
      ],
      "facets": [
        {
          "metadata": { "title": "Language" },
          "links": [
            { "title": "English", "href": "/opds?lang=en",
              "properties": { "numberOfItems": 40 } }
          ]
        }
      ],
      "publications": [
        {
          "metadata": {
            "title": "Harbour Lights 02",
            "author": [{ "name": "Ada Lovelace" }, "Alan Turing"],
            "belongsTo": { "series": { "name": "Harbour Lights", "position": 2 } },
            "modified": "2026-08-01T10:00:00Z",
            "description": "Second."
          },
          "images": [
            { "href": "/cover/2.jpg", "width": 1200 },
            { "href": "/thumb/2.jpg", "width": 200 }
          ],
          "links": [
            { "href": "/download/2.epub", "type": "application/epub+zip", "size": 5565 }
          ]
        }
      ]
    }
    """
}
