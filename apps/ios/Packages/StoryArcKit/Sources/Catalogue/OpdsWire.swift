internal import Foundation

/// The OPDS 2.0 wire shapes, named for what they are so nothing mistakes them for the model.
///
/// Top-level rather than nested inside the parser: half of these types need their own
/// `init(from:)`, because the standard lets `rel`, `author` and `belongsTo.series` each be
/// a string, an object, or an array of either. Nested five deep they were unreadable.
struct OpdsWireFeed: Decodable {
    let metadata: OpdsWireTitle?
    let links: [OpdsWireLink]?
    let navigation: [OpdsWireLink]?
    let publications: [OpdsWirePublication]?
    let groups: [OpdsWireGroup]?
    let facets: [OpdsWireFacet]?
}

struct OpdsWireTitle: Decodable {
    let title: String
}

struct OpdsWireGroup: Decodable {
    let navigation: [OpdsWireLink]?
    let publications: [OpdsWirePublication]?
}

struct OpdsWireFacet: Decodable {
    let metadata: OpdsWireTitle?
    let links: [OpdsWireLink]
}

struct OpdsWireLink: Decodable {
    let href: String
    let type: String?
    let title: String?
    let templated: Bool?
    let properties: OpdsWireProperties?

    /// One string or an array of them, which the standard permits.
    let rel: [String]?

    private enum CodingKeys: String, CodingKey {
        case href, type, title, templated, properties, rel
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        href = try container.decode(String.self, forKey: .href)
        type = try container.decodeIfPresent(String.self, forKey: .type)
        title = try container.decodeIfPresent(String.self, forKey: .title)
        templated = try container.decodeIfPresent(Bool.self, forKey: .templated)
        properties = try container.decodeIfPresent(OpdsWireProperties.self, forKey: .properties)
        if let one = try? container.decodeIfPresent(String.self, forKey: .rel) {
            rel = [one]
        } else {
            rel = try container.decodeIfPresent([String].self, forKey: .rel)
        }
    }
}

struct OpdsWireProperties: Decodable {
    let numberOfItems: Int?
}

struct OpdsWirePublication: Decodable {
    let metadata: OpdsWireMetadata
    let links: [OpdsWireLink]?
    let images: [OpdsWireImage]?
}

struct OpdsWireImage: Decodable {
    let href: String
    let width: Int?
}

struct OpdsWireMetadata: Decodable {
    let identifier: String?
    let title: String?
    let description: String?
    let modified: String?
    let author: OpdsWireContributors?
    let belongsTo: OpdsWireBelongsTo?
}

struct OpdsWireBelongsTo: Decodable {
    let series: OpdsWireSeries?
}

/// A series is a string, an object with a name and a position, or an array of either.
struct OpdsWireSeries: Decodable {
    let names: [String]
    let position: Double?

    private enum CodingKeys: String, CodingKey {
        case name, position
    }

    init(from decoder: any Decoder) throws {
        if let name = try? decoder.singleValueContainer().decode(String.self) {
            names = [name]
            position = nil
            return
        }
        if let one = try? decoder.container(keyedBy: CodingKeys.self) {
            names = [try one.decode(String.self, forKey: .name)]
            position = try one.decodeIfPresent(Double.self, forKey: .position)
            return
        }
        let read = try OpdsWireNamed.list(from: decoder)
        names = read.names
        position = read.position
    }
}

/// An author is a string, an object with a name, or an array of either.
struct OpdsWireContributors: Decodable {
    let names: [String]

    init(from decoder: any Decoder) throws {
        if let one = try? decoder.singleValueContainer().decode(String.self) {
            names = [one]
            return
        }
        if let object = try? decoder.singleValueContainer().decode(OpdsWireNamed.self) {
            names = [object.name]
            return
        }
        names = try OpdsWireNamed.list(from: decoder).names
    }
}

/// An object with a name, and the array reader both of the above share.
struct OpdsWireNamed: Decodable {
    let name: String
    let position: Double?

    /// Reads an array whose members are strings, named objects, or something else again.
    ///
    /// Something else again is skipped rather than thrown on. A feed with one malformed
    /// author is a feed with the other authors intact, and refusing the whole catalogue
    /// over it helps nobody.
    static func list(from decoder: any Decoder) throws -> (names: [String], position: Double?) {
        var list = try decoder.unkeyedContainer()
        var names: [String] = []
        var position: Double?
        while !list.isAtEnd {
            if let name = try? list.decode(String.self) {
                names.append(name)
            } else if let object = try? list.decode(OpdsWireNamed.self) {
                names.append(object.name)
                position = position ?? object.position
            } else {
                _ = try? list.decode(OpdsWireAnything.self)
            }
        }
        return (names, position)
    }
}

/// Consumes one member of an array without caring what it was.
struct OpdsWireAnything: Decodable {}
