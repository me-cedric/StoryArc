package app.storyarc.core.catalogue

import java.io.ByteArrayInputStream
import java.security.cert.CertificateException
import java.security.cert.CertificateFactory
import java.security.cert.X509Certificate
import java.util.concurrent.atomic.AtomicReference
import javax.net.ssl.X509TrustManager
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * The certificate decision a reader meets when they add a catalogue.
 *
 * `opds-catalog`, "Self-signed certificate": a catalogue presenting a certificate the system
 * does not trust is refused "by default", the app "explains why", and it "offers to pin that
 * specific certificate after showing its fingerprint". Three promises, and each one is a case
 * below.
 *
 * The platform trust manager is a stub, not the real one. The decision under test is what
 * [OpdsTrust.PinAwareTrustManager] does *with* the platform's answer, and a stub is the only
 * way to give it both answers without a live server and a private key in the repository. The
 * certificate is real: the fingerprint is computed over real DER, so the hexadecimal a reader
 * compares against their server is the value asserted here.
 *
 * iOS's `OpdsTrustTests` asserts the same fingerprint over the same certificate, and the same
 * pin rules. What it cannot assert is named there.
 */
class OpdsTrustTest {

    /**
     * A self-signed certificate, `CN=storyarc-test.invalid`, generated once for this test.
     *
     * The public half only. There is no private key here and no server to start: the tests
     * need a certificate to describe, not a handshake to complete.
     */
    private val certificate: X509Certificate = pem(
        """
        -----BEGIN CERTIFICATE-----
        MIICvDCCAaQCCQCFu1YvS2eBAzANBgkqhkiG9w0BAQsFADAgMR4wHAYDVQQDDBVz
        dG9yeWFyYy10ZXN0LmludmFsaWQwHhcNMjYwOTA2MTUxNjQzWhcNNDYwOTAxMTUx
        NjQzWjAgMR4wHAYDVQQDDBVzdG9yeWFyYy10ZXN0LmludmFsaWQwggEiMA0GCSqG
        SIb3DQEBAQUAA4IBDwAwggEKAoIBAQCzbuveCoU6GRNNt5B6it0HDmfJcNjHvt3Z
        DyxvvadztCwEKPDb1eSflgr+lv0fPiPUXrq9XnmftjwOLjPsKxxYMgaeSBoSraB5
        7sz3xrYekXV6C5STeGHbFdgB47Bikds0sq34Ac+a9V8SW6D59DWx3CA+SLc5QFmM
        vU0gkswL0W8U1p/5sYirQNF3v2mFb/xjRKGGIkaB6dfH9XXewJdKIl8x4PkYlYES
        CXo/fkroHj2p0eTxrTf9CTCV0glqmdMJb98dFZ40jWQ2ALQGzBfLHl14lIMZDFHU
        ZDDinnEHeTrYwM7l0uo976AFWXkVsIUwXWfciYrnvKWnIfBexklLAgMBAAEwDQYJ
        KoZIhvcNAQELBQADggEBAJhDPhlht0JpnoprzeXIN8PqK2KlF6z6Ij8LQ+oAHBok
        3pjfzzhbk3IdQCU2YypXRuOSGtCoemCmf4ch83YUOyw5G4UxqV0ZDntNjEoq15uX
        Tw+mcpTuSVUfr+RutjLV71gLsHMX1SVffcMbF7YsUaUXS4oyGuXoRacibLGnMNm/
        PDiBzXAz1h69RmHytSB4Ws9Y93ofZpLeEP2KsFj8LRWLIiCXXWvloa2DnIUtWlB3
        47U3aVWUjIwaDa8Mup58ulyLR6lXipLlUSc9oepxWeoSDT46At3sWVzHjW1oxUd1
        ZDo1duNUATwIjAtwJuYlDK+BG/rO0X0JPc/0d5BAGLM=
        -----END CERTIFICATE-----
        """,
    )

    /** What `openssl x509 -fingerprint -sha256` prints for that certificate. */
    private val fingerprint =
        "6B:D2:93:82:01:BB:37:FD:A2:61:8F:77:EB:99:1F:3F:F1:DE:9B:31:A6:C2:48:A1:77:15:22:25:7B:48:2B:56"

    private val host = "books.example"

    private val chain = arrayOf(certificate)

    // -- The fingerprint the reader is asked to compare ---------------------------------

    @Test
    fun theFingerprintIsTheSha256OfTheCertificate() {
        assertEquals(fingerprint, certificate.described(host).fingerprint)
    }

    @Test
    fun theRefusalNamesTheHostAndTheCertificate() {
        val described = certificate.described(host)
        assertEquals(host, described.host)
        assertTrue(described.subject.contains("storyarc-test.invalid"))
        assertEquals(certificate.notAfter, described.notValidAfter)
    }

    // -- The decision -------------------------------------------------------------------

    @Test
    fun anUntrustedCertificateIsRefusedAndDescribed() {
        val refused = AtomicReference<UntrustedCertificate?>(null)
        assertThrows(CertificateException::class.java) {
            manager(CertificatePins(), refused).checkServerTrusted(chain, "RSA")
        }
        val seen = refused.get()
        assertNotNull(seen)
        assertEquals(host, seen?.host)
        assertEquals(fingerprint, seen?.fingerprint)
    }

    @Test
    fun aPinnedFingerprintIsAccepted() {
        val refused = AtomicReference<UntrustedCertificate?>(null)
        val pins = CertificatePins(mapOf(host to setOf(fingerprint)))
        manager(pins, refused).checkServerTrusted(chain, "RSA")
        // Nothing to ask the reader about: they already answered for this certificate.
        assertNull(refused.get())
    }

    @Test
    fun aPinBelongsToOneHost() {
        val refused = AtomicReference<UntrustedCertificate?>(null)
        val pins = CertificatePins(mapOf("other.example" to setOf(fingerprint)))
        assertThrows(CertificateException::class.java) {
            manager(pins, refused).checkServerTrusted(chain, "RSA")
        }
        assertEquals(fingerprint, refused.get()?.fingerprint)
    }

    @Test
    fun aPinBelongsToOneCertificate() {
        val refused = AtomicReference<UntrustedCertificate?>(null)
        val other = fingerprint.replaceFirst("6B", "6C")
        val pins = CertificatePins(mapOf(host to setOf(other)))
        assertThrows(CertificateException::class.java) {
            manager(pins, refused).checkServerTrusted(chain, "RSA")
        }
        assertEquals(fingerprint, refused.get()?.fingerprint)
    }

    @Test
    fun aServerThatOffersNoCertificateIsRefused() {
        val refused = AtomicReference<UntrustedCertificate?>(null)
        assertThrows(CertificateException::class.java) {
            manager(CertificatePins(), refused).checkServerTrusted(null, "RSA")
        }
        // Nothing was seen, so there is no fingerprint to offer and no question to ask.
        assertNull(refused.get())
    }

    /**
     * A pin is an exception the reader adds, not a restriction they impose.
     *
     * `opds-catalog` offers the pin only "WHEN a catalogue presents a certificate the system
     * does not trust", so a certificate the system *does* trust is accepted whether or not a
     * pin exists. Asserted rather than assumed, because the alternative reading -- a pinned
     * host refusing every other certificate -- is a different feature, and this test is what
     * says which one the app has.
     */
    @Test
    fun aSystemTrustedCertificateIsAcceptedWhateverIsPinned() {
        val refused = AtomicReference<UntrustedCertificate?>(null)
        val pins = CertificatePins(mapOf(host to setOf("00:11")))
        OpdsTrust.PinAwareTrustManager(Trusting(), pins, host, refused).checkServerTrusted(chain, "RSA")
        assertNull(refused.get())
    }

    // -- The record of what the reader accepted -------------------------------------------

    @Test
    fun nothingIsPinnedUntilAReaderPinsIt() {
        assertFalse(CertificatePins().accepts(fingerprint, host))
    }

    @Test
    fun pinningIsRememberedForThatHostAlone() {
        val pins = CertificatePins()
        pins.pin(fingerprint, host)
        assertTrue(pins.accepts(fingerprint, host))
        assertFalse(pins.accepts(fingerprint, "other.example"))
        assertEquals(mapOf(host to setOf(fingerprint)), pins.all)
    }

    @Test
    fun forgettingAHostDropsItsPinsAndNoOthers() {
        val pins = CertificatePins(
            mapOf(host to setOf(fingerprint), "other.example" to setOf(fingerprint)),
        )
        pins.forget(host)
        assertFalse(pins.accepts(fingerprint, host))
        assertTrue(pins.accepts(fingerprint, "other.example"))
    }

    // -- Fixtures --------------------------------------------------------------------------

    private fun manager(pins: CertificatePins, refused: AtomicReference<UntrustedCertificate?>) =
        OpdsTrust.PinAwareTrustManager(Refusing(), pins, host, refused)

    private fun pem(text: String): X509Certificate {
        val bytes = text.trimIndent().toByteArray()
        return CertificateFactory.getInstance("X.509")
            .generateCertificate(ByteArrayInputStream(bytes)) as X509Certificate
    }

    /** The platform, when it will not vouch for the chain -- a self-signed certificate. */
    private class Refusing : X509TrustManager {
        override fun checkServerTrusted(chain: Array<out X509Certificate>?, authType: String?): Unit =
            throw CertificateException("issuer is not trusted")

        override fun checkClientTrusted(chain: Array<out X509Certificate>?, authType: String?) = Unit

        override fun getAcceptedIssuers(): Array<X509Certificate> = emptyArray()
    }

    /** The platform, when the chain is ordinary and valid. */
    private class Trusting : X509TrustManager {
        override fun checkServerTrusted(chain: Array<out X509Certificate>?, authType: String?) = Unit

        override fun checkClientTrusted(chain: Array<out X509Certificate>?, authType: String?) = Unit

        override fun getAcceptedIssuers(): Array<X509Certificate> = emptyArray()
    }
}