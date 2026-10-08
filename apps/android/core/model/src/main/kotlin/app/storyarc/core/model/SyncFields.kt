package app.storyarc.core.model

/**
 * The settings, field by field, as a sync merges them.
 *
 * `library-sync` task 3.5. The names are the document's own keys, so the moments the document
 * carries line up with the fields they date. The sync place is not here and never travels: a
 * device that carried it would make every other device write where the first one does.
 */
object SettingsStamps {

    val fields: List<SyncField<DocumentSettings>> = listOf(
        SyncField("appearance", { it.appearance }) { a, b -> a.copy(appearance = b.appearance) },
        SyncField("language", { it.language }) { a, b -> a.copy(language = b.language) },
        // iOS has no such setting and writes nothing here, so a null keeps this device's own.
        SyncField("turnPagesWithVolumeButtons", { it.turnPagesWithVolumeButtons }) { a, b ->
            b.turnPagesWithVolumeButtons?.let { a.copy(turnPagesWithVolumeButtons = it) } ?: a
        },
        SyncField("turnPagesByTappingTheEdges", { it.turnPagesByTappingTheEdges }) { a, b ->
            a.copy(turnPagesByTappingTheEdges = b.turnPagesByTappingTheEdges)
        },
        SyncField("linkReadingThemeToAppearance", { it.linkReadingThemeToAppearance }) { a, b ->
            a.copy(linkReadingThemeToAppearance = b.linkReadingThemeToAppearance)
        },
        SyncField("lightReadingTheme", { it.lightReadingTheme }) { a, b ->
            a.copy(lightReadingTheme = b.lightReadingTheme)
        },
        SyncField("darkReadingTheme", { it.darkReadingTheme }) { a, b ->
            a.copy(darkReadingTheme = b.darkReadingTheme)
        },
        SyncField("downloadOverWifiOnly", { it.downloadOverWifiOnly }) { a, b ->
            a.copy(downloadOverWifiOnly = b.downloadOverWifiOnly)
        },
        SyncField("maximumDownloadBytes", { it.maximumDownloadBytes }) { a, b ->
            a.copy(maximumDownloadBytes = b.maximumDownloadBytes)
        },
        SyncField("removeDownloadsAfterFinishing", { it.removeDownloadsAfterFinishing }) { a, b ->
            a.copy(removeDownloadsAfterFinishing = b.removeDownloadsAfterFinishing)
        },
    )

    /** Each field's value, by name: what a store compares to find what the reader changed. */
    fun values(settings: AppSettings): Map<String, Any?> {
        val document = DocumentSettings(settings)
        return fields.associate { it.name to it.read(document) }
    }

    /** This device's settings merged with the document's, newer field wins. */
    fun merging(
        local: AppSettings,
        localStamps: Map<String, Long>,
        remote: DocumentSettings,
        device: String,
    ): StampedValue<AppSettings> {
        val merged = ChangeStamps.merging(
            fields, DocumentSettings(), DocumentSettings(local), localStamps,
            remote, remote.changed, device,
        )
        return StampedValue(merged.value.settings(local), merged.changedAt)
    }
}

/**
 * The reading themes, field by field, as a sync merges them.
 *
 * A field's moment is filed under `scope/shelf|field`: the entry the document already names
 * (an entry with no shelf is a scope's default), then the field. The custom colour slot is one
 * more field, [CUSTOM_PALETTE].
 */
object ThemeStamps {

    const val CUSTOM_PALETTE = "customPalette"

    private fun <V> values(name: String, read: (DocumentThemeValues) -> V, copy: (DocumentThemeValues, V) -> DocumentThemeValues) =
        SyncField<DocumentShelfSettings>("values.$name", { read(it.values) }) { a, b ->
            a.copy(values = copy(a.values, read(b.values)))
        }

    val fields: List<SyncField<DocumentShelfSettings>> = listOf(
        SyncField("theme.preset", { it.theme.preset }) { a, b ->
            a.copy(theme = a.theme.copy(preset = b.theme.preset))
        },
        SyncField("theme.deviations", { it.theme.deviations }) { a, b ->
            a.copy(theme = a.theme.copy(deviations = b.theme.deviations))
        },
        SyncField("theme.custom", { it.theme.custom }) { a, b ->
            a.copy(theme = a.theme.copy(custom = b.theme.custom))
        },
        values("typeface", { it.typeface }) { v, x -> v.copy(typeface = x) },
        values("fontSizePercent", { it.fontSizePercent }) { v, x -> v.copy(fontSizePercent = x) },
        values("isBold", { it.isBold }) { v, x -> v.copy(isBold = x) },
        values("isHyphenated", { it.isHyphenated }) { v, x -> v.copy(isHyphenated = x) },
        values("lineHeight", { it.lineHeight }) { v, x -> v.copy(lineHeight = x) },
        values("letterSpacing", { it.letterSpacing }) { v, x -> v.copy(letterSpacing = x) },
        values("wordSpacing", { it.wordSpacing }) { v, x -> v.copy(wordSpacing = x) },
        values("paragraphSpacing", { it.paragraphSpacing }) { v, x -> v.copy(paragraphSpacing = x) },
        values("pageMargins", { it.pageMargins }) { v, x -> v.copy(pageMargins = x) },
        values("textAlignment", { it.textAlignment }) { v, x -> v.copy(textAlignment = x) },
        SyncField("transition", { it.transition }) { a, b -> a.copy(transition = b.transition) },
        SyncField("scrollAxis", { it.scrollAxis }) { a, b -> a.copy(scrollAxis = b.scrollAxis) },
        SyncField("readingDirection", { it.readingDirection }) { a, b ->
            a.copy(readingDirection = b.readingDirection)
        },
        SyncField("adjustments", { it.adjustments }) { a, b -> a.copy(adjustments = b.adjustments) },
        SyncField("offsetsSpreads", { it.offsetsSpreads }) { a, b ->
            a.copy(offsetsSpreads = b.offsetsSpreads)
        },
        SyncField("showsPageSeparator", { it.showsPageSeparator }) { a, b ->
            a.copy(showsPageSeparator = b.showsPageSeparator)
        },
        SyncField("fit", { it.fit }) { a, b -> a.copy(fit = b.fit) },
    )

    private val paletteField = SyncField<ReaderPalette?>(CUSTOM_PALETTE, { it }) { _, b -> b }

    private val defaults = DocumentShelfSettings(ShelfSettings()).let { settings ->
        fields.associate { it.name to it.read(settings) }
    }

    /** A field's value in an entry that is not there: the default setup's. */
    fun default(name: String): Any? = defaults[name.substringAfterLast('|')]

    /** The entry a field's moment is filed under. */
    fun entry(scope: String, shelf: String?): String = "$scope/${shelf.orEmpty()}"

    /** Each field's value, by its filed name: what a store compares to find what changed. */
    fun values(memory: ShelfMemory): Map<String, Any?> = buildMap {
        for (entry in memory.entries) {
            val document = DocumentShelfSettings(entry.settings)
            val name = entry(entry.scope.name.toWireCase(), entry.shelf)
            for (field in fields) put("$name|${field.name}", field.read(document))
        }
        put(CUSTOM_PALETTE, memory.customPalette)
    }

    /**
     * This device's themes merged with the document's, newer field wins.
     *
     * An entry only the document has arrives whole, unless this device removed it later: then
     * its fields are merged against the defaults the removal left.
     */
    fun merging(
        local: ShelfMemory,
        localStamps: Map<String, Long>,
        remote: DocumentThemes,
        device: String,
    ): StampedValue<ShelfMemory> {
        val mine = local.entries.associate {
            entry(it.scope.name.toWireCase(), it.shelf) to
                ShelfMemory.Entry(it.scope, it.shelf, it.settings)
        }
        val theirs = remote.entries.mapNotNull { arriving ->
            val scope = wireEnumOrNull<ThemeScope>(arriving.scope) ?: return@mapNotNull null
            entry(arriving.scope, arriving.shelf) to
                ShelfMemory.Entry(scope, arriving.shelf, arriving.settings.settings())
        }.toMap()
        val arrivingStamps = ChangeStamps.moments(remote.changed)

        var memory = ShelfMemory()
        val stamps = mutableMapOf<String, Long>()
        for (name in mine.keys + theirs.keys) {
            val held = mine[name]
            val arriving = theirs[name]
            val prefix = "$name|"
            val settings = when {
                arriving == null -> held!!.settings.also {
                    stamps.putAll(localStamps.filterKeys { it.startsWith(prefix) })
                }
                held == null && localStamps.keys.none { it.startsWith(prefix) } ->
                    arriving.settings.also {
                        stamps.putAll(arrivingStamps.filterKeys { it.startsWith(prefix) })
                    }
                else -> ChangeStamps.merging(
                    fields, DocumentShelfSettings(ShelfSettings()),
                    DocumentShelfSettings(held?.settings ?: ShelfSettings()), localStamps,
                    DocumentShelfSettings(arriving.settings), remote.changed, device,
                ) { "$prefix$it" }.also { stamps.putAll(it.changedAt) }.value.settings()
            }
            val shape = held ?: arriving!!
            memory = memory.recording(ShelfMemory.Entry(shape.scope, shape.shelf, settings))
        }
        val palette = ChangeStamps.merging(
            listOf(paletteField), null, local.customPalette, localStamps,
            remote.customPalette, remote.changed, device,
        )
        stamps.putAll(palette.changedAt)
        return StampedValue(memory.copy(customPalette = palette.value), stamps)
    }
}
