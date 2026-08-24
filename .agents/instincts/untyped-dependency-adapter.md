---
id: untyped-dependency-adapter
trigger: 'when a dependency returns `any`, an untyped AST, a loose JSON document, or a parser result the type checker cannot describe'
confidence: 0.9
domain: architecture
source: local-repo-analysis
---

# A weakly typed dependency needs an adapter and a shape test

A parser that returns `any` gives the type checker nothing to compare. A major
version bump then moves the runtime shape, and the build still passes. Type
checking, linting and bundling all succeed, and the feature returns empty rows.

The compiler cannot see this break, so a test must.

## Put the loose access in one narrow module

Extract every field read on the untyped value into one adapter file. Keep the
`any` inside it. Export named types outward, so the rest of the application
depends on your shape and not on the library's.

```ts
export interface ParsedField { name: string; type: string; pk: boolean }
export interface ParsedTable { name: string; fields: ParsedField[] }
export interface Parsed { tables: ParsedTable[] }

export function parse(text: string): { data?: Parsed; error?: string } {
  try {
    const doc = Vendor.parse(text);
    const tables = doc.schemas[0].tables.map((t: any) => ({
      name: t.name,
      fields: t.fields.map((f: any) => ({
        name: f.name,
        type: f.type?.type_name ?? "",
        pk: !!f.pk,
      })),
    }));
    return { data: { tables } };
  } catch (e: any) {
    return { error: String(e?.message ?? "invalid input") };
  }
}
```

Read every optional field defensively. `f.type?.type_name ?? ""` survives a
renamed node; `f.type.type_name` throws.

## Assert the real shape, with a real input

One test parses a small real document and asserts the values, not the types:
names in order, each mapped field, each flag, both ends of a relation. A snapshot
is weaker, because a reviewer accepts a changed snapshot without reading it.

Add the empty input case and the invalid input case. An adapter should return the
parser's message instead of throwing, so a bad document shows an error and does
not remove the screen.

## Take the major bump only when the test proves it

Upgrade the dependency, run the shape test, and read the result. Record in the
change that a test verified the bump. "It compiles" is not evidence for a
dependency the compiler cannot check.

## The same rule covers other blind boundaries

Any value the type system cannot describe needs the same treatment: an untyped
SDK response, a document from a schemaless store, an environment payload, a
plugin loaded at runtime. Validate or map it once, at the edge.
