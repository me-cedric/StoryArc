//! Source health and refresh (`sources`, mirrored from StoryArcKit's `SourceRegistry` states
//! and `SourceDiagnosis`).
//!
//! A source is connected, connecting, unreachable since a moment, or refused its credential.
//! Unreachable is grey and never red (AGENTS.md, non-negotiable 3); only a refused credential
//! needs the reader, and then its one action comes first. A refresh that finishes records the
//! moment; one that fails keeps the moment of the last one that did.

use serde::{Deserialize, Serialize};

use crate::domain::Timestamp;
use crate::sources::kavita::KavitaError;
use crate::sources::opds::OpdsError;
use crate::sources::smb::SmbError;

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", tag = "state")]
pub enum ConnectionState {
    Connected,
    Connecting,
    /// Grey: the library stays browsable from the metadata cache.
    Unreachable {
        since: Timestamp,
    },
    /// The credential was refused; the reason is a case name, not a sentence.
    Unauthorized {
        reason: String,
    },
}

impl ConnectionState {
    pub fn needs_user_action(&self) -> bool {
        matches!(self, Self::Unauthorized { .. })
    }
}

/// How a refresh failed, sorted from any source's error.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum RefreshFailure {
    Unreachable,
    Unauthorized(String),
}

impl From<&OpdsError> for RefreshFailure {
    fn from(error: &OpdsError) -> Self {
        match error {
            OpdsError::Unauthorized(_) => Self::Unauthorized("credentialRefused".into()),
            OpdsError::Untrusted(_) => Self::Unauthorized("certificateUntrusted".into()),
            _ => Self::Unreachable,
        }
    }
}

impl From<&KavitaError> for RefreshFailure {
    fn from(error: &KavitaError) -> Self {
        match error {
            KavitaError::KeyRejected => Self::Unauthorized("keyRejected".into()),
            _ => Self::Unreachable,
        }
    }
}

impl From<&SmbError> for RefreshFailure {
    fn from(error: &SmbError) -> Self {
        match error {
            SmbError::AuthenticationRejected => Self::Unauthorized("credentialRefused".into()),
            _ => Self::Unreachable,
        }
    }
}

/// One source's health, as stored beside its record.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct SourceHealth {
    pub state: ConnectionState,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub last_successful_sync: Option<Timestamp>,
    /// When the source first stopped answering, kept through the retries in between.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub away_since: Option<Timestamp>,
}

impl Default for SourceHealth {
    fn default() -> Self {
        Self {
            state: ConnectionState::Connecting,
            last_successful_sync: None,
            away_since: None,
        }
    }
}

impl SourceHealth {
    pub fn refreshing(&self) -> Self {
        Self {
            state: ConnectionState::Connecting,
            ..self.clone()
        }
    }

    /// *A refresh that finished*: connected, and the moment written down.
    pub fn refreshed(&self, now: Timestamp) -> Self {
        Self {
            state: ConnectionState::Connected,
            last_successful_sync: Some(now),
            away_since: None,
        }
    }

    /// A failed refresh. An unreachable source keeps the moment it first went away, so the
    /// grey line can say since when.
    pub fn failed(&self, failure: &RefreshFailure, now: Timestamp) -> Self {
        match failure {
            RefreshFailure::Unauthorized(reason) => Self {
                state: ConnectionState::Unauthorized {
                    reason: reason.clone(),
                },
                away_since: None,
                ..self.clone()
            },
            RefreshFailure::Unreachable => {
                let since = self.away_since.unwrap_or(now);
                Self {
                    state: ConnectionState::Unreachable { since },
                    away_since: Some(since),
                    ..self.clone()
                }
            }
        }
    }

    /// The source's actions, in the order the diagnosis lists them.
    pub fn actions(&self, has_downloads: bool, removable: bool) -> Vec<SourceAction> {
        let mut actions = Vec::new();
        if self.state.needs_user_action() {
            actions.push(SourceAction::Reconnect);
        }
        actions.extend([
            SourceAction::TestConnection,
            SourceAction::Refresh,
            SourceAction::ClearCache,
        ]);
        if has_downloads {
            actions.push(SourceAction::RemoveDownloads);
        }
        if removable {
            actions.push(SourceAction::Remove);
        }
        actions
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum SourceAction {
    Reconnect,
    TestConnection,
    Refresh,
    ClearCache,
    RemoveDownloads,
    Remove,
}

impl SourceAction {
    /// Whether the action asks for a confirmation: it removes something the reader keeps.
    pub fn is_destructive(self) -> bool {
        matches!(self, Self::RemoveDownloads | Self::Remove)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_refresh_records_its_moment_and_a_failure_keeps_it() {
        let health = SourceHealth::default().refreshed(Timestamp(10));
        let away = health.failed(&RefreshFailure::Unreachable, Timestamp(20));
        assert_eq!(
            away.state,
            ConnectionState::Unreachable {
                since: Timestamp(20)
            }
        );
        assert_eq!(away.last_successful_sync, Some(Timestamp(10)));
        let still = away
            .refreshing()
            .failed(&RefreshFailure::Unreachable, Timestamp(30));
        assert_eq!(
            still.state,
            ConnectionState::Unreachable {
                since: Timestamp(20)
            }
        );
        assert_eq!(
            still.refreshed(Timestamp(40)).state,
            ConnectionState::Connected
        );
    }

    #[test]
    fn a_refused_credential_puts_reconnect_first_and_only_then() {
        let refused = SourceHealth::default().failed(
            &RefreshFailure::from(&KavitaError::KeyRejected),
            Timestamp(1),
        );
        assert_eq!(
            refused.actions(true, true),
            [
                SourceAction::Reconnect,
                SourceAction::TestConnection,
                SourceAction::Refresh,
                SourceAction::ClearCache,
                SourceAction::RemoveDownloads,
                SourceAction::Remove,
            ]
        );
        let away = SourceHealth::default().failed(
            &RefreshFailure::from(&OpdsError::Unreachable("x".into())),
            Timestamp(1),
        );
        assert_eq!(
            away.actions(false, false),
            [
                SourceAction::TestConnection,
                SourceAction::Refresh,
                SourceAction::ClearCache
            ]
        );
        assert_eq!(
            RefreshFailure::from(&SmbError::AuthenticationRejected),
            RefreshFailure::Unauthorized("credentialRefused".into())
        );
    }
}
