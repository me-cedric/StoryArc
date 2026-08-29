package app.storyarc.core.model

import java.util.UUID
import kotlinx.serialization.KSerializer
import kotlinx.serialization.descriptors.PrimitiveKind
import kotlinx.serialization.descriptors.PrimitiveSerialDescriptor
import kotlinx.serialization.descriptors.SerialDescriptor
import kotlinx.serialization.encoding.Decoder
import kotlinx.serialization.encoding.Encoder

/**
 * A `UUID` as the string everything else in this app writes it as.
 *
 * `SourceStore` and `DownloadStore` both store an identifier as `id.toString()`, and a
 * cached publication carrying its source id has to agree with them — a registry entry and a
 * cached publication that disagree about how a source is spelled is a publication attributed
 * to nothing.
 *
 * iOS needs no counterpart: `UUID` is `Codable` in Foundation, and encodes as the same
 * string.
 */
object UuidSerializer : KSerializer<UUID> {
    override val descriptor: SerialDescriptor =
        PrimitiveSerialDescriptor("java.util.UUID", PrimitiveKind.STRING)

    override fun serialize(encoder: Encoder, value: UUID) = encoder.encodeString(value.toString())

    override fun deserialize(decoder: Decoder): UUID = UUID.fromString(decoder.decodeString())
}
