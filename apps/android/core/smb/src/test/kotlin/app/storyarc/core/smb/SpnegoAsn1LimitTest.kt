package app.storyarc.core.smb

import org.bouncycastle.asn1.ASN1InputStream
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * The SMB server chooses the bytes of the SPNEGO token, and BouncyCastle parses them.
 *
 * `jcifs.spnego.NegTokenInit` hands the server's token straight to `ASN1InputStream`, so
 * every object identifier in it is attacker-chosen. BouncyCastle 1.76 — the version
 * jcifs-ng 2.1.10 declares — puts no ceiling on how long one identifier's contents may
 * be, which is CVE-2025-8885: a single oversized arc makes the parser allocate without
 * bound, and the app is killed for memory pressure every time the reader touches that
 * share. 1.78 added the ceiling; the app pins 1.84 by constraint in `build.gradle.kts`,
 * because nothing here calls BouncyCastle directly and a constraint says that.
 *
 * The test is on the behaviour rather than on a version string: what matters is that an
 * identifier no real protocol would send is refused before anything is allocated for it.
 * Against 1.76 this parses happily and the test fails.
 */
class SpnegoAsn1LimitTest {
    @Test
    fun `an object identifier longer than any real one is refused rather than allocated`() {
        val thrown = runCatching { ASN1InputStream(oversizedObjectIdentifier()).use { it.readObject() } }
            .exceptionOrNull()

        assertTrue(
            "an ${CONTENTS_LENGTH}-byte object identifier was accepted: " +
                "BouncyCastle is older than 1.78 and CVE-2025-8885 applies (${thrown ?: "no error"})",
            thrown != null,
        )
        assertTrue(
            "refused, but not for its length: $thrown",
            thrown?.message?.contains("OID contents length limit") == true,
        )
    }

    /**
     * A DER OBJECT IDENTIFIER carrying one arc spread over thousands of continuation
     * bytes. Well-formed — the point is the size, not a malformed encoding, because a
     * malformed one would be rejected by both versions and prove nothing.
     */
    private fun oversizedObjectIdentifier(): ByteArray {
        val der = ByteArray(4 + CONTENTS_LENGTH)
        der[0] = 0x06 // OBJECT IDENTIFIER
        der[1] = 0x82.toByte() // long-form length, two bytes follow
        der[2] = (CONTENTS_LENGTH shr 8).toByte()
        der[3] = (CONTENTS_LENGTH and 0xff).toByte()
        der[4] = 0x2a // the first two arcs, 1.2
        for (i in 5 until der.size - 1) der[i] = 0x81.toByte() // more of the same arc
        der[der.size - 1] = 0x01 // and its last byte
        return der
    }

    private companion object {
        /** Twice the 4096-byte ceiling 1.78 introduced, so the margin is not the question. */
        const val CONTENTS_LENGTH = 8192
    }
}
