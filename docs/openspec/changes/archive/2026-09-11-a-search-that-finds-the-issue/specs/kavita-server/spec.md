## MODIFIED Requirements

### Requirement: Server-side search

The app SHALL use Kavita's search when searching within a Kavita source.

#### Scenario: Searching a Kavita source
- **WHEN** a user searches within a Kavita source
- **THEN** the query is sent to the server, returning matches across series, chapters, people, genres, and tags — not only titles cached locally
- **AND** the issues of every matched series are listed under chapters as well, joined on the device from the publications that source has already contributed to the library, because the server matches a chapter on the chapter's own title and never on the name of its series
- **AND** a series the app has not yet read from that source contributes no issues, because the join reads what the library holds and asks the server for nothing more

#### Scenario: Searching from the library, scoped to one server
- **WHEN** the library is narrowed to a Kavita source and the user searches
- **THEN** the local matches are shown, and one action offers to put the same query to that
  server, which answers with matches the local index cannot hold

#### Scenario: Searching while the server is unreachable
- **WHEN** the server is unreachable
- **THEN** the search falls back to the local cache and states that results are limited to cached content
- **AND** a result the device holds opens, rather than pointing at a series the server cannot serve
