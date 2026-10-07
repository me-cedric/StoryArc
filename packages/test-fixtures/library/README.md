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

## The sealed-secrets vector

`sealed-secrets.json` holds one block of sealed secrets, `library-portability` task 5.2. It
has the passphrase, the two plaintexts, and the `secrets` object a document would carry.

| Read by | What it asserts |
| --- | --- |
| iOS `LibrarySecretSealerTests` | Opens it, and seals the same inputs to the same bytes |
| Android `LibrarySecretSealerTest` | Opens it, and seals the same inputs to the same bytes |

**It was sealed once, by neither app.** Python's `cryptography` package and `hashlib.pbkdf2_hmac`
made it: PBKDF2-HMAC-SHA256 at 600,000 iterations over the NFC passphrase, a salt of the bytes
`00` to `0f`, then AES-256-GCM with a nonce of twelve bytes counting up from `20` for the first
source and from `30` for the second. A vector made by one of the two apps would only prove that
app agrees with itself. Do not regenerate it to make a failing test pass: a failure here means
one platform stopped agreeing with the other, and that is the defect.

The passphrase and both plaintexts contain characters outside ASCII on purpose, because the two
platforms must agree on the UTF-8 bytes they derive a key from and encrypt. The two plaintexts
are fake.

