package app.storyarc.core.model

/**
 * What this build does to the traffic between the app and a network share.
 *
 * `network-share`'s *Encrypted transport* requires the source detail screen to state
 * whether the connection is encrypted. That sentence must follow a value. Before this file
 * the screen drew one fixed string, so it made a claim about a reader's security that no
 * code had measured.
 *
 * The value belongs to the client, not to one share, because neither SMB client encrypts:
 *
 * - Android uses jcifs-ng 2.1.10. Its `Configuration` documents
 *   `jcifs.smb.client.encryptionEnabled` as an option that only indicates "support during
 *   protocol negotiation, SMB encryption is not implemented yet". No source file in that
 *   release writes an SMB 3 transform header, and `SmbSessionImpl` throws
 *   `SmbUnsupportedOperationException` when a server demands encryption.
 * - iOS uses SMBClient 0.3.1. `Session` offers the dialects SMB 2.0.2 and SMB 2.1 only.
 *   SMB 3 is where transport encryption starts, so that client never reaches the question.
 *
 * Give either client encryption and change this value with it. The screen reads the value;
 * it does not repeat the answer. `SmbClient.connect()` reports the same value, so the
 * add-share sheet and the detail screen cannot disagree.
 */
object ShareTransport {
    /** True when the app encrypts what it reads from a network share. */
    const val IS_ENCRYPTED: Boolean = false
}
