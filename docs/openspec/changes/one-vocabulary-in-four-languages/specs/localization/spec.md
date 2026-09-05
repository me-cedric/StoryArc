## MODIFIED Requirements

### Requirement: Supported languages

The app SHALL be fully localised in English, French, German and Spanish.

Completeness is not the same claim as key parity. A build can hold a translation
for every key it defines and still show a reader English, because a sentence that
was never made a key has no key to be missing. The requirement is about the
sentence, and the check that enforces it SHALL be about the sentence too.

#### Scenario: Following the system
- **WHEN** the app launches
- **THEN** it uses the first supported language in the device's preferred-language order, falling back to English

#### Scenario: Overriding in the app
- **WHEN** a user picks a language in settings
- **THEN** the whole interface switches immediately without a restart, and the choice persists
- **AND** a "System" option returns to following the device

#### Scenario: Completeness
- **WHEN** the app is built
- **THEN** the build fails if any supported language is missing a key that English defines
- **AND** no user-visible string is hardcoded in a source file

#### Scenario: A sentence that never became a key
- **WHEN** a sentence that a reader can be shown is written directly in a source file rather than in a translated catalogue
- **THEN** the build fails and names the file and line
- **AND** it fails whether the sentence is drawn as a label, spoken by a screen reader, or reached a screen by being carried in a value from another layer

#### Scenario: The check can fail
- **WHEN** a hardcoded reader-visible sentence is deliberately introduced
- **THEN** the check reports it by name, and reports nothing once it is removed, so a passing build distinguishes a clean codebase from a check that cannot fire

### Requirement: Content language

Publication metadata SHALL be presented in its own language, not translated.

Text that comes from a publication, a server or a file is content. Text the app
composes about that content is interface, and is translated even when it names
something that is not — the name of a format, of a library, or of a file.

#### Scenario: Publication titles
- **WHEN** a publication's title is in a language other than the interface language
- **THEN** it is displayed as-is and is never machine-translated

#### Scenario: Server-provided labels
- **WHEN** a server provides genre or tag names
- **THEN** they are displayed as the server provides them, and only StoryArc's own interface chrome is translated

#### Scenario: A sentence built around content
- **WHEN** the app states something about a file it will not open, naming the file and the reason
- **THEN** the file's name is shown as-is and every word the app supplies around it is in the reader's language
- **AND** this holds when the reason came from a layer that parsed the file rather than from the screen that shows it

## ADDED Requirements

### Requirement: A refusal speaks the reader's language

When the app declines to open or to index something, the sentence it shows SHALL
be in the reader's language.

A refusal is where the reader most needs to understand, and it is the text most
likely to be written far from any screen — in the layer that discovered the
problem. Naming the reason is already required elsewhere; this requirement says
that naming it in English only does not satisfy it.

#### Scenario: A file the app will not open
- **WHEN** a file is refused because its format is not read, because it is protected by its store's content protection, or because it is not recognised at all
- **THEN** the sentence naming that reason is shown in the reader's language

#### Scenario: A publication skipped during a scan
- **WHEN** a library scan skips a publication and states why
- **THEN** the reason is in the reader's language, both in the notice and in the list where each skipped publication sits beside its own reason
- **AND** a screen reader announces the same translated words the screen shows

#### Scenario: A failure with no sentence written for it
- **WHEN** something fails for a reason the app has no written sentence for
- **THEN** it shows a translated general refusal rather than text produced for a maintainer
- **AND** no internal diagnostic wording reaches the reader, in any language

#### Scenario: Reasons of different kinds in one list
- **WHEN** several publications are skipped in one scan for different reasons
- **THEN** every reason in the list is in the same language as the rest of the interface, with no mixture

### Requirement: One state, one name

A state the reader can be in SHALL be described with the same words wherever it
appears, and SHALL be described with the same words on both platforms.

Three phrasings of one state teach a reader that they are three states. The rule
binds within a platform — a chip, a settings row and a full screen describing one
condition use one wording — and across the two, because two apps that disagree
about what to call a thing are two products.

#### Scenario: One condition named in several places
- **WHEN** a source cannot be reached, and this is shown in more than one place in the interface
- **THEN** every place uses the same name for that condition

#### Scenario: The two platforms agree
- **WHEN** the same state is shown on iOS and on Android
- **THEN** both state it in the same words, allowing only for a difference the platform itself forces
- **AND** a difference the platform forces — the name of a system setting, of a device, or of a service the platform provides — is stated in each platform's own terms and is not treated as a divergence

#### Scenario: One sentence, assembled differently
- **WHEN** one platform composes a sentence from clauses and the other holds it whole
- **THEN** the reader is shown the same words on both, because how a sentence is assembled is not something a reader can see
- **AND** where the sentences genuinely differ in what they tell the reader — one naming a place the other leaves unnamed — the more informative one is the agreed wording

#### Scenario: A state that cannot be reached
- **WHEN** the app is offline and a state can only be described from what is already on the device
- **THEN** it is still named with the agreed wording, and the app does not substitute a vaguer sentence because it knows less

> [NEEDS CLARIFICATION: the destination holding everything readable offline is
> called *Downloads* on one platform and described as *on this device* on the
> other, and the two are different promises — a queue, or everything readable
> without a network. Direction §8.4 records this as an owner decision that was
> never taken. Which name is the agreed one? Until it is answered this
> requirement cannot be applied to that destination.]

### Requirement: Plain words where a reader browses

Interface text SHALL avoid technical vocabulary where a reader is browsing, and
SHALL keep it where a reader is connecting something up or being told why
something failed.

The two halves are one rule, not a preference for simplicity. A reader looking at
covers did not ask what protocol a library speaks. A reader typing an address
into a setup screen typed that acronym into their router an hour ago, and a
sentence that hides it from them makes their problem unfixable.

#### Scenario: Browsing
- **WHEN** text is shown on a surface a reader browses — the home surface, the library, the destination holding what is on the device, search, a publication's page, a shelf, or an empty state
- **THEN** it names things as a reader would, and does not name a protocol, a file format's acronym, a server product, or a unit of measurement that belongs to typesetting

#### Scenario: Setting a source up
- **WHEN** text is shown while a reader is adding or repairing a source
- **THEN** it may name the protocol, the product, the setting to change, or the address to type, because that is the vocabulary the task is conducted in

#### Scenario: A failure that must stay precise
- **WHEN** a failure can only be acted on by naming something technical — a codec, a certificate, a security setting on a network device, or a status a server returned
- **THEN** the message names it, in plain words first and the precise term after
- **AND** a browse-path sentence is never made vaguer than the reader needs to fix the problem, because vagueness here makes a problem unfixable

#### Scenario: A new sentence on a browse surface
- **WHEN** a sentence is added to a surface a reader browses
- **THEN** it is written to this rule at the time it is added, rather than left for a later pass
