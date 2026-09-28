## ADDED Requirements

### Requirement: Local network permission

On Android, the app SHALL declare the local-network permission and SHALL
request it at the moment it is first needed, rather than at first launch.

#### Scenario: Requesting at first need
- **WHEN** a user opens SMB discovery, or the app makes its first connection to an SMB share, an OPDS catalogue or a Kavita server on the local network
- **THEN** the app requests the local-network permission at that moment, with a rationale naming what it is for
- **AND** a user who already granted it is not asked again

#### Scenario: Permission denied
- **WHEN** the local-network permission is denied
- **THEN** SMB discovery is hidden and manual entry still works, per [`network-share`](../network-share/spec.md) "Discovery"
- **AND** the app states once, in the surface that asked, how to grant the permission in system settings
- **AND** a connection attempt to a share, a catalogue or a Kavita server that the missing permission blocks fails with its own sentence naming the missing permission, distinct from a host-unreachable failure
