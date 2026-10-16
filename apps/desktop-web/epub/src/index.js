// The bundle's entry. Wave 1 pins the toolkit and nothing more: this file makes the whole
// of both packages reachable from the host as `StoryArcEpub.navigator` and
// `StoryArcEpub.shared`, so the digest in pin.json covers every byte the web views will
// run. The host-facing glue — locators, preference axes, footnote and link events, themes,
// search, highlights — is tasks 4.1 and 4.2 and lands beside this file under src/.
import * as navigator from '@readium/navigator'
import * as shared from '@readium/shared'

export { navigator, shared }
