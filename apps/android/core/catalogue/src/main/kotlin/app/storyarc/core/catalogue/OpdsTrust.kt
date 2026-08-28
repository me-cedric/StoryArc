package app.storyarc.core.catalogue

import java.security.KeyStore
import java.security.cert.CertificateException
import java.security.cert.X509Certificate
import java.util.concurrent.atomic.AtomicReference
import javax.net.ssl.HttpsURLConnection
import javax.net.ssl.SSLContext
import javax.net.ssl.TrustManagerFactory
import javax.net.ssl.X509TrustManager

/**
 * Decides what to do with a server's certificate.
 *
 * The rule is: the system decides, and the reader can overrule it only for one certificate
 * they have seen. iOS's `OpdsTrustDelegate` applies the same rule through `URLSession`.
 */
internal object OpdsTrust {

    /**
     * Installs the rule on one connection, and returns where a refusal will be recorded.
     *
     * Per connection rather than process-wide. Setting the default `SSLContext` would apply
     * a reader's decision about one self-hosted server to every other request the app ever
     * makes, which is the opposite of what pinning one certificate means.
     */
    fun install(connection: HttpsURLConnection, pins: CertificatePins): AtomicReference<UntrustedCertificate?> {
        val refused = AtomicReference<UntrustedCertificate?>(null)
        val host = connection.url.host
        val manager = PinAwareTrustManager(platform(), pins, host, refused)
        val context = SSLContext.getInstance("TLS")
        context.init(null, arrayOf(manager), null)
        connection.sslSocketFactory = context.socketFactory
        return refused
    }

    /** The platform's own trust manager, which decides first and usually decides finally. */
    private fun platform(): X509TrustManager {
        val factory = TrustManagerFactory.getInstance(TrustManagerFactory.getDefaultAlgorithm())
        factory.init(null as KeyStore?)
        return factory.trustManagers.filterIsInstance<X509TrustManager>().first()
    }

    /**
     * The system first, then the reader's own pins, then a refusal that says what it saw.
     *
     * The system comes first on purpose. A certificate that evaluates is not the reader's
     * problem, and asking them about one would teach them to tap through the question that
     * matters.
     */
    private class PinAwareTrustManager(
        private val platform: X509TrustManager,
        private val pins: CertificatePins,
        private val host: String,
        private val refused: AtomicReference<UntrustedCertificate?>,
    ) : X509TrustManager {

        override fun checkServerTrusted(chain: Array<out X509Certificate>?, authType: String?) {
            val certificates = chain ?: throw CertificateException("no certificate offered")
            try {
                platform.checkServerTrusted(certificates, authType)
                return
            } catch (untrusted: CertificateException) {
                val leaf = certificates.first()
                val described = leaf.described(host)
                if (pins.accepts(described.fingerprint, host)) return
                // Refused, and described. `opds-catalog` requires the explanation before
                // the offer, so what the reader will be shown is captured here.
                refused.set(described)
                throw untrusted
            }
        }

        /**
         * Client certificates are not something StoryArc offers, so this is the platform's
         * answer unchanged rather than a permissive stub.
         */
        override fun checkClientTrusted(chain: Array<out X509Certificate>?, authType: String?) {
            platform.checkClientTrusted(chain, authType)
        }

        override fun getAcceptedIssuers(): Array<X509Certificate> = platform.acceptedIssuers
    }
}
