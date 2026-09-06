package app.storyarc.core.model

/**
 * Case-insensitive natural order over a name: runs of digits compare as numbers,
 * everything else compares case-insensitively.
 *
 * Written by hand rather than using a collator because collation is locale-sensitive,
 * and neither the order of pages inside an archive nor the order of files inside a
 * folder may depend on the reader's language.
 *
 * Here rather than in `:core:format`, where it was written, because two callers need it
 * and they sit in different modules: `PageOrdering` orders the entries of an archive,
 * and [LibraryIndex] falls back to it when a series carries no order of its own.
 * `:core:format` depends on this module, so this is the one place both can see. A second
 * copy would be a rule that drifts.
 */
object NaturalOrder {

    /**
     * @return negative when [lhs] sorts first, positive when [rhs] does, 0 when equal.
     *
     * An `Int` rather than a predicate because that is what a Kotlin `Comparator` takes.
     * iOS's `NaturalOrder.precedes` returns a `Bool` for the same reason on its side, and
     * the two answer the same question.
     */
    fun compare(lhs: String, rhs: String): Int {
        var left = 0
        var right = 0

        while (left < lhs.length && right < rhs.length) {
            val leftIsDigit = lhs[left].isDigit()
            val rightIsDigit = rhs[right].isDigit()

            if (leftIsDigit && rightIsDigit) {
                val leftEnd = runEnd(lhs, left)
                val rightEnd = runEnd(rhs, right)
                // Compared digit-by-digit rather than parsed into an integer:
                // parsing caps at the platform's word size, and Android's Long
                // and iOS's UInt64 do not have the same ceiling. A page number is
                // never that long, but a latent divergence between the two
                // implementations is exactly what this layer must not have.
                val leftDigits = lhs.substring(left, leftEnd).trimStart('0')
                val rightDigits = rhs.substring(right, rightEnd).trimStart('0')
                if (leftDigits.length != rightDigits.length) {
                    return leftDigits.length.compareTo(rightDigits.length)
                }
                if (leftDigits != rightDigits) return leftDigits.compareTo(rightDigits)
                // Same value. Fewer leading zeros sorts first, so the order is total.
                val leftRun = leftEnd - left
                val rightRun = rightEnd - right
                if (leftRun != rightRun) return leftRun.compareTo(rightRun)
                left = leftEnd
                right = rightEnd
                continue
            }

            // A digit sorts before a letter, so `p1` precedes `pa`.
            if (leftIsDigit != rightIsDigit) return if (leftIsDigit) -1 else 1

            val leftChar = lhs[left].lowercaseChar()
            val rightChar = rhs[right].lowercaseChar()
            if (leftChar != rightChar) return leftChar.compareTo(rightChar)
            left++
            right++
        }

        return (lhs.length - left).compareTo(rhs.length - right)
    }

    private fun runEnd(text: String, from: Int): Int {
        var index = from
        while (index < text.length && text[index].isDigit()) index++
        return index
    }
}
