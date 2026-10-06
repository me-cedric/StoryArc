package app.storyarc.core.model

import kotlinx.serialization.Serializable

/**
 * [AppSettings] as the document spells it.
 *
 * A shape of its own rather than [AppSettings] itself, for two reasons. An enum case is a
 * `String` here so that the conversion is visible and testable — serialising the domain type
 * would make the document's wire a side effect of a Kotlin enum name, and a rename would
 * change every file this app has ever written with nothing to catch it. And the document
 * carries the union of what the two platforms hold, which is not what either one holds.
 *
 * [turnPagesWithVolumeButtons] is the live example: iOS has no such setting, so a document it
 * writes does not carry the field and one it reads drops it. `library-portability` /
 * *A field this version does not know* allows exactly that — "the field is ignored and the
 * rest is imported, and a re-export does not have to carry it back".
 *
 * That clause is why the field is nullable rather than defaulted. A default answers the
 * absent field with `false`, which is not ignoring it — it is turning the setting off. An
 * Android reader who turns pages with the volume buttons, exports from their iPhone and
 * imports here would find the buttons dead, and nothing would have gone wrong loudly enough
 * to look at. Null means "the document says nothing", and [settings] keeps what the device
 * already holds.
 */
@Serializable
data class DocumentSettings(
    val appearance: String = AppearanceMode.SYSTEM.name.toWireCase(),
    val language: String? = null,
    val turnPagesWithVolumeButtons: Boolean? = null,
    val turnPagesByTappingTheEdges: Boolean = true,
    val linkReadingThemeToAppearance: Boolean = false,
    val lightReadingTheme: String = ThemePreset.PAPER.name.toWireCase(),
    val darkReadingTheme: String = ThemePreset.QUIET.name.toWireCase(),
    val downloadOverWifiOnly: Boolean = false,
    val maximumDownloadBytes: Long? = null,
    val removeDownloadsAfterFinishing: Boolean = false,
) {
    constructor(settings: AppSettings) : this(
        appearance = settings.appearance.name.toWireCase(),
        language = settings.language,
        turnPagesWithVolumeButtons = settings.turnPagesWithVolumeButtons,
        turnPagesByTappingTheEdges = settings.turnPagesByTappingTheEdges,
        linkReadingThemeToAppearance = settings.linkReadingThemeToAppearance,
        lightReadingTheme = settings.lightReadingTheme.name.toWireCase(),
        darkReadingTheme = settings.darkReadingTheme.name.toWireCase(),
        downloadOverWifiOnly = settings.downloadOverWifiOnly,
        maximumDownloadBytes = settings.maximumDownloadBytes,
        removeDownloadsAfterFinishing = settings.removeDownloadsAfterFinishing,
    )

    /**
     * The settings this names, with a value this build does not know left at its default.
     *
     * A setting is a preference, and losing one is worth far less than refusing the whole
     * import — the same trade every store in this app already makes on unreadable data.
     */
    fun settings(onDevice: AppSettings = AppSettings()): AppSettings = AppSettings(
        appearance = wireEnum(appearance, AppearanceMode.SYSTEM),
        language = language,
        // A field the writing platform cannot express keeps this device's own answer.
        turnPagesWithVolumeButtons =
            turnPagesWithVolumeButtons ?: onDevice.turnPagesWithVolumeButtons,
        turnPagesByTappingTheEdges = turnPagesByTappingTheEdges,
        linkReadingThemeToAppearance = linkReadingThemeToAppearance,
        lightReadingTheme = wireEnum(lightReadingTheme, ThemePreset.PAPER),
        darkReadingTheme = wireEnum(darkReadingTheme, ThemePreset.QUIET),
        downloadOverWifiOnly = downloadOverWifiOnly,
        maximumDownloadBytes = maximumDownloadBytes,
        removeDownloadsAfterFinishing = removeDownloadsAfterFinishing,
    )
}

/**
 * [ReadingTheme] as the document spells it: the preset, the axes moved off it, and the
 * reader's own colours when they chose some.
 */
@Serializable
data class DocumentReadingTheme(
    val preset: String = ThemePreset.PAPER.name.toWireCase(),
    /**
     * Sorted, because this is a set on both platforms and a set has no order — so two
     * exports of one library would otherwise differ in a way a diff reports and a reader
     * cannot explain.
     */
    val deviations: List<String> = emptyList(),
    val custom: ReaderPalette? = null,
) {
    constructor(theme: ReadingTheme) : this(
        preset = theme.preset.name.toWireCase(),
        deviations = theme.deviations.map { it.name.toWireCase() }.sorted(),
        custom = theme.custom,
    )

    fun theme(): ReadingTheme = ReadingTheme(
        preset = wireEnum(preset, ThemePreset.PAPER),
        deviations = deviations.mapNotNull { wireEnumOrNull<ThemeAxis>(it) }.toSet(),
        custom = custom,
    )
}

/**
 * [ThemeValues] as the document spells it.
 *
 * [fontSizePercent] is a number and says its unit. iOS backs its `FontSizeStep` with the
 * percentage itself and this platform backs it with a name, so neither platform's own
 * spelling is one the other can read; the percentage is the value both of them actually mean.
 */
@Serializable
data class DocumentThemeValues(
    val typeface: String = ReaderTypeface.PUBLISHER.name.toWireCase(),
    val fontSizePercent: Int = FontSizeStep.NORMAL.percent,
    val isBold: Boolean = false,
    val isHyphenated: Boolean = false,
    val lineHeight: Double = 1.4,
    val letterSpacing: Double = 0.0,
    val wordSpacing: Double = 0.0,
    val paragraphSpacing: Double = 0.5,
    val pageMargins: Double = 1.0,
    val textAlignment: String = ReaderTextAlignment.PUBLISHER.name.toWireCase(),
) {
    constructor(values: ThemeValues) : this(
        typeface = values.typeface.name.toWireCase(),
        fontSizePercent = values.fontSize.percent,
        isBold = values.isBold,
        isHyphenated = values.isHyphenated,
        lineHeight = values.lineHeight,
        letterSpacing = values.letterSpacing,
        wordSpacing = values.wordSpacing,
        paragraphSpacing = values.paragraphSpacing,
        pageMargins = values.pageMargins,
        textAlignment = values.textAlignment.name.toWireCase(),
    )

    fun values(): ThemeValues = ThemeValues(
        typeface = wireEnum(typeface, ReaderTypeface.PUBLISHER),
        fontSize = FontSizeStep.entries.firstOrNull { it.percent == fontSizePercent }
            ?: FontSizeStep.NORMAL,
        isBold = isBold,
        isHyphenated = isHyphenated,
        lineHeight = lineHeight,
        letterSpacing = letterSpacing,
        wordSpacing = wordSpacing,
        paragraphSpacing = paragraphSpacing,
        pageMargins = pageMargins,
        textAlignment = wireEnum(textAlignment, ReaderTextAlignment.PUBLISHER),
    )
}

/** [ShelfSettings] as the document spells it: everything one shelf is read with. */
@Serializable
data class DocumentShelfSettings(
    val theme: DocumentReadingTheme = DocumentReadingTheme(),
    val values: DocumentThemeValues = DocumentThemeValues(),
    val transition: String = PageTransition.SLIDE.name.toWireCase(),
    val scrollAxis: String? = null,
    val readingDirection: String? = null,
    val adjustments: ImageAdjustments = ImageAdjustments(),
    val offsetsSpreads: Boolean = false,
    val showsPageSeparator: Boolean = false,
    val fit: String = PageFit.SCREEN.name.toWireCase(),
) {
    constructor(settings: ShelfSettings) : this(
        theme = DocumentReadingTheme(settings.theme),
        values = DocumentThemeValues(settings.values),
        transition = settings.transition.name.toWireCase(),
        scrollAxis = settings.scrollAxis?.name?.toWireCase(),
        readingDirection = settings.readingDirection?.name?.toWireCase(),
        adjustments = settings.adjustments,
        offsetsSpreads = settings.offsetsSpreads,
        showsPageSeparator = settings.showsPageSeparator,
        fit = settings.fit.name.toWireCase(),
    )

    fun settings(): ShelfSettings = ShelfSettings(
        theme = theme.theme(),
        values = values.values(),
        transition = wireEnum(transition, PageTransition.SLIDE),
        scrollAxis = wireEnumOrNull<ScrollAxis>(scrollAxis),
        readingDirection = wireEnumOrNull<ReadingDirection>(readingDirection),
        adjustments = adjustments,
        offsetsSpreads = offsetsSpreads,
        showsPageSeparator = showsPageSeparator,
        fit = wireEnum(fit, PageFit.SCREEN),
    )
}
