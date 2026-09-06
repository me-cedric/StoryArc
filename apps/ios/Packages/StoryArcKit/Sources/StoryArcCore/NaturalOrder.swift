/// Case-insensitive natural order over a name: runs of digits compare as numbers,
/// everything else compares case-insensitively.
///
/// Written by hand rather than using `localizedStandardCompare` because that is
/// locale-sensitive, and neither the order of pages inside an archive nor the order
/// of files inside a folder may depend on the reader's language.
///
/// Here rather than in `Formats`, where it was written, because two callers need it
/// and they sit in different targets: ``PageOrdering`` orders the entries of an
/// archive, and ``LibraryIndex`` falls back to it when a series carries no order of
/// its own. `Formats` depends on this target, so this is the one place both can see.
/// A second copy would be a rule that drifts.
public enum NaturalOrder {

    /// Whether `lhs` sorts before `rhs`.
    ///
    /// A predicate rather than a three-way comparison because that is what Swift's
    /// `sorted(by:)` takes. Android's `NaturalOrder.compare` returns an `Int` for the
    /// same reason on its side, and the two answer the same question.
    public static func precedes(_ lhs: String, _ rhs: String) -> Bool {
        var left = Substring(lhs)
        var right = Substring(rhs)

        while let leftChar = left.first, let rightChar = right.first {
            let leftIsDigit = isDigit(leftChar)
            let rightIsDigit = isDigit(rightChar)

            if leftIsDigit && rightIsDigit {
                let leftRun = left.prefix(while: isDigit)
                let rightRun = right.prefix(while: isDigit)
                // Compared digit-by-digit rather than parsed into an integer:
                // parsing caps at the platform's word size, and iOS's UInt64 and
                // Android's Long do not have the same ceiling. A page number is
                // never that long, but a latent divergence between the two
                // implementations is exactly what this layer must not have.
                let leftDigits = leftRun.drop(while: { $0 == "0" })
                let rightDigits = rightRun.drop(while: { $0 == "0" })
                if leftDigits.count != rightDigits.count {
                    return leftDigits.count < rightDigits.count
                }
                if leftDigits != rightDigits {
                    return leftDigits.lexicographicallyPrecedes(rightDigits)
                }
                // Same value. Fewer leading zeros sorts first, so the order is total.
                if leftRun.count != rightRun.count { return leftRun.count < rightRun.count }
                left = left.dropFirst(leftRun.count)
                right = right.dropFirst(rightRun.count)
                continue
            }

            if leftIsDigit != rightIsDigit {
                // A digit sorts before a letter, so `p1` precedes `pa`.
                return leftIsDigit
            }

            let leftLower = Character(leftChar.lowercased())
            let rightLower = Character(rightChar.lowercased())
            if leftLower != rightLower { return leftLower < rightLower }
            left = left.dropFirst()
            right = right.dropFirst()
        }

        return left.count < right.count
    }

    /// Whether a character is one of the ten digits.
    ///
    /// The ten, spelled out, rather than `Character.isNumber`, which answers `true` for the
    /// whole Unicode number category — a superscript two included. Kotlin's `Char.isDigit`
    /// answers `true` for decimal digits only, so the two rules would file the same folder
    /// in different orders. This range is the rule both platforms can spell.
    private static func isDigit(_ character: Character) -> Bool {
        ("0"..."9").contains(character)
    }
}
