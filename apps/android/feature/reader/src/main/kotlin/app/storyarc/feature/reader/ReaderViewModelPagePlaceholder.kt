package app.storyarc.feature.reader

/** Each decoded page's own width-over-height ratio, for [PagePlaceholder]. */
internal fun ReaderViewModel.decodedRatios(): Map<Int, Float> =
    decoded.mapNotNull { (index, bitmap) ->
        if (bitmap.height > 0) index to bitmap.width.toFloat() / bitmap.height else null
    }.toMap()
