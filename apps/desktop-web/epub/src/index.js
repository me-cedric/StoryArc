// The bundle's entry. The three desktop hosts embed dist/storyarc-epub.js and serve it on
// their own scheme (ADR-0018 D6), so the digest in pin.json covers every byte the web views
// run. `navigator` and `shared` are the whole toolkit, kept reachable for the host and the
// tests; `open` is the host-facing reader (reader.js) and the rest of src/ is its glue.
import * as navigator from '@readium/navigator'
import * as shared from '@readium/shared'
import { open } from './reader.js'
import { hostPost } from './transport.js'

export { navigator, shared, open, hostPost }
