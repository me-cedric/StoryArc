//! Case-insensitive natural order over a name: runs of digits compare as numbers,
//! everything else compares case-insensitively. Mirrored from `NaturalOrder.swift`.
//!
//! Written by hand rather than through a locale-aware collation because that is
//! locale-sensitive, and neither the order of pages inside an archive nor the order of
//! files inside a folder may depend on the reader's language.

use std::cmp::Ordering;

pub struct NaturalOrder;

impl NaturalOrder {
    /// Whether `lhs` sorts before `rhs`. The predicate the Swift reader exposes; `compare`
    /// is the three-way form `sort_by` wants, and the two answer the same question.
    pub fn precedes(lhs: &str, rhs: &str) -> bool {
        Self::compare(lhs, rhs) == Ordering::Less
    }

    pub fn compare(lhs: &str, rhs: &str) -> Ordering {
        let left: Vec<char> = lhs.chars().collect();
        let right: Vec<char> = rhs.chars().collect();
        let (mut l, mut r) = (0, 0);

        while l < left.len() && r < right.len() {
            let left_is_digit = Self::is_digit(left[l]);
            let right_is_digit = Self::is_digit(right[r]);

            if left_is_digit && right_is_digit {
                let left_run = Self::digit_run(&left[l..]);
                let right_run = Self::digit_run(&right[r..]);
                // Compared digit-by-digit rather than parsed into an integer: parsing caps
                // at the platform's word size, and the three platforms do not share a
                // ceiling. A page number is never that long, but a latent divergence
                // between implementations is exactly what this layer must not have.
                let left_digits = Self::without_leading_zeros(left_run);
                let right_digits = Self::without_leading_zeros(right_run);
                if left_digits.len() != right_digits.len() {
                    return left_digits.len().cmp(&right_digits.len());
                }
                if left_digits != right_digits {
                    return left_digits.cmp(right_digits);
                }
                // Same value. Fewer leading zeros sorts first, so the order is total.
                if left_run.len() != right_run.len() {
                    return left_run.len().cmp(&right_run.len());
                }
                l += left_run.len();
                r += right_run.len();
                continue;
            }

            if left_is_digit != right_is_digit {
                // A digit sorts before a letter, so `p1` precedes `pa`.
                return if left_is_digit {
                    Ordering::Less
                } else {
                    Ordering::Greater
                };
            }

            let left_lower = Self::lowered(left[l]);
            let right_lower = Self::lowered(right[r]);
            if left_lower != right_lower {
                return left_lower.cmp(&right_lower);
            }
            l += 1;
            r += 1;
        }

        (left.len() - l).cmp(&(right.len() - r))
    }

    /// Whether a character is one of the ten digits.
    ///
    /// The ten, spelled out, rather than `char::is_numeric`, which answers `true` for the
    /// whole Unicode number category — a superscript two included. Swift and Kotlin spell
    /// the same range, so the three file the same folder in the same order.
    fn is_digit(character: char) -> bool {
        character.is_ascii_digit()
    }

    fn digit_run(chars: &[char]) -> &[char] {
        let end = chars
            .iter()
            .position(|&c| !Self::is_digit(c))
            .unwrap_or(chars.len());
        &chars[..end]
    }

    fn without_leading_zeros(run: &[char]) -> &[char] {
        let start = run.iter().position(|&c| c != '0').unwrap_or(run.len());
        &run[start..]
    }

    /// The first scalar of the lower-cased form: the whole of it for every character a
    /// file name carries, and a stable choice for the few that lower-case to two.
    fn lowered(character: char) -> char {
        character.to_lowercase().next().unwrap_or(character)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn sorted(names: &[&str]) -> Vec<String> {
        let mut out: Vec<String> = names.iter().map(|&s| s.to_owned()).collect();
        out.sort_by(|a, b| NaturalOrder::compare(a, b));
        out
    }

    #[test]
    fn page10_sorts_after_page9_not_after_page1() {
        assert_eq!(
            sorted(&[
                "page1.png",
                "page10.png",
                "page2.png",
                "page9.png",
                "page11.png"
            ]),
            [
                "page1.png",
                "page2.png",
                "page9.png",
                "page10.png",
                "page11.png"
            ]
        );
    }

    #[test]
    fn leading_zeros_do_not_change_the_value_but_keep_the_order_total() {
        assert_eq!(
            sorted(&["p007.png", "p7.png", "p8.png"]),
            ["p7.png", "p007.png", "p8.png"]
        );
    }

    #[test]
    fn a_digit_sorts_before_a_letter() {
        assert!(NaturalOrder::precedes("p1.png", "pa.png"));
        assert!(!NaturalOrder::precedes("pa.png", "p1.png"));
    }

    #[test]
    fn ordering_is_case_insensitive() {
        assert_eq!(
            sorted(&["B.png", "a.png", "C.png"]),
            ["a.png", "B.png", "C.png"]
        );
    }

    #[test]
    fn a_digit_run_longer_than_any_integer_type_still_orders_correctly() {
        let long = format!("p{}.png", "9".repeat(40));
        let longer = format!("p1{}.png", "0".repeat(40));
        assert_eq!(sorted(&[&longer, &long]), [long.clone(), longer.clone()]);
        assert_eq!(
            sorted(&["p99999999999.png", "p2.png"]),
            ["p2.png", "p99999999999.png"]
        );
    }

    #[test]
    fn a_prefix_sorts_before_what_extends_it() {
        assert!(NaturalOrder::precedes("ch1", "ch1/p1.png"));
        assert_eq!(NaturalOrder::compare("same", "same"), Ordering::Equal);
    }
}
