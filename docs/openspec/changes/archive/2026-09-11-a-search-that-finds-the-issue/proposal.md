# A search that finds the issue

**Platforms: both.** A search of a Kavita source answers with series and with
almost no issues. This change adds the issues, and it adds them on the device,
because the server cannot find them.

## Why

A reader searched their own Kavita for "lantern". They got fifteen series and no
issues. Every issue of every one of those fifteen series is a file the server
holds, and the reader wanted the files.

### Kavita cannot answer this, and the reason is in its own source

`API/Data/Repositories/SeriesRepository.cs` at tag v0.8.7 matches a chapter on
`EF.Functions.Like(c.TitleName, ...)`, on `c.ISBN` and on `c.Range`. A chapter
row carries no series name. So "lantern" matches no chapter of
"Green Lantern (2005)", and a bigger query changes nothing.

The same response carries a `Files` group, which looks like the answer and is
not. The server fills it for an administrator only, and `MangaFileDto` carries
no `seriesId` and no `chapterId`, so a file the server named cannot be opened.

### The app already holds the issues

`KavitaContributor` walks a source and makes one `Publication` per chapter. Each
one carries the series name the server gave it, the chapter's own display title,
and the chapter's remote id. A series hit from the server carries the numeric
series id. Joining the two on the series name yields the issue rows, with no
further request and no new naming rule.

## What changes

- `kavita-server` → *Server-side search* → *Searching a Kavita source* gains two
  clauses. The first says the issues of a matched series are listed. The second
  says the join reads what the library holds, so a series the app has not read
  from that source contributes none.
- Both apps gain one pure function, `KavitaIssues.joined`, in the module that
  already holds `KavitaFind`.
- Both finders pass the source's publications to that function and show the
  result. No new view, no new heading, no new string.

## Non-goals

- **Asking the server per series.** Fifteen series hits would be fifteen more
  requests, and the app already holds the answer.
- **Opening the issue directly.** A tapped issue opens its series, as a tapped
  chapter from the server does today. Opening the file needs a chapter the join
  does not hold.
- **Listing an issue whose own title matches while its series does not.** Such a
  hit carries no series id, so it draws dim and opens nothing.
- **Reading more of the server.** The join covers the slice the library holds.
  Widening that slice belongs to `library-browsing`.
