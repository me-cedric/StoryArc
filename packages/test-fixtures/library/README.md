# Library documents

Two exports of the same library, one written by each platform's encoder.

`library-portability` task 1.2 asks for a test that "writes on one platform's encoder and
reads on the other's decoder". These files are what makes that a gate rather than a claim:

| File | Pinned by | Read by |
| --- | --- | --- |
| `written-by-ios.json` | iOS `LibraryDocumentTests` | Android `LibraryDocumentBoundaryTest` |
| `written-by-android.json` | Android `LibraryDocumentTest` | iOS `LibraryDocumentBoundaryTests` |

The library both describe is built in `LibraryDocumentFixture`, which exists on both
platforms and holds the same values. Change it on one side and both suites fail, which is
the intent: neither platform can privately redefine what the document says.

**Regenerating.** There is no generator script. Each file is what its platform's encoder
produces, so the way to update one is to change the encoder or the fixture, watch that
platform's pinning test fail, and take the value it reports.

The two files are *not* byte-identical and are not meant to be. `JSONEncoder` sorts keys and
indents by two spaces; `kotlinx.serialization` keeps declaration order and indents by four.
What has to match is the data, and that is what the cross-reading tests assert.

**The secrets in them are deliberate and fake.** `LibraryDocumentFixture` gives its network
share a password inside its address and its Kavita server an API key inside its query string,
because `library-portability` task 2.2 asks for a test that neither reaches the bytes. Grep
either file for `hunter2` and the answer has to be nothing.
