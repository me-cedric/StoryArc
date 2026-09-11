## MODIFIED Requirements

### Requirement: Kavita connection

The app SHALL connect to a Kavita server using its base URL and a user API key,
and SHALL manage session tokens without exposing them to the user.

The app SHALL NOT ask a server for its version, and SHALL NOT refuse a server for
the version it reports. No Kavita states its version to a reader's API key, so a
version floor cannot be checked and would refuse nobody. The app SHALL instead
read a route the server does not know as the signal that the server is too old
for that request, SHALL say so at the screen that made the request, and SHALL
read no other failure as an old server.

#### Scenario: Adding a server
- **WHEN** a user enters a Kavita base URL and API key
- **THEN** the app authenticates, confirms the account name the server returns, and saves the source
- **AND** it asks the server nothing else, so a server that answers only the token route is added

#### Scenario: Pasting a full OPDS URL
- **WHEN** a user pastes a Kavita OPDS URL that embeds the API key
- **THEN** the app extracts the base URL and key and configures a native Kavita source rather than a generic OPDS source

#### Scenario: Session token expires
- **WHEN** a request fails because the session token has expired
- **THEN** the app re-authenticates with the stored API key and retries the request once, without the user seeing an error

#### Scenario: API key revoked
- **WHEN** re-authentication fails because the API key is no longer valid
- **THEN** the source is marked `unauthorized` with an explanation and an action to enter a new key
