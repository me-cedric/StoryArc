## MODIFIED Requirements

### Requirement: Discovery

The app SHALL offer to discover SMB hosts on the local network to reduce manual entry, where the platform permits it.

#### Scenario: Discovering hosts
- **WHEN** a user adds an SMB source
- **THEN** the app lists hosts advertising SMB on the local network, if the platform permits it, alongside a manual-entry field
- **AND** manual entry is always available and never gated behind discovery

#### Scenario: Local network permission denied
- **WHEN** the platform's local-network permission is denied
- **THEN** discovery is hidden, manual entry still works, and the app explains once how to enable discovery in system settings
