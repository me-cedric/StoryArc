# Windows wave 3 conformance walk (task 3.24)

Status: a walk by a reader of the code, written without a .NET SDK and without Windows, on a
Mac. Nothing here has compiled or run on .NET. The `Desktop Windows` workflow is the first
compiler, the interop jobs on the Linux and macOS runners are the first run of the tests named
below, and a walk on a Windows 11 24H2 machine is the only proof of a screen. The JSON shapes the
C# reads were checked a different way: by calling the core's own library from Python and reading
what it wrote, against the mock servers of `scripts/`, so the records match the seam as built.

Each row names the code, the test that pins the pure part, and one of four states, as in the wave
2 walk:

- **tested**: a rule in `StoryArc.Interop` with a test in `StoryArc.Interop.Tests`, or a seam call
  exercised against `packages/test-fixtures`, a loopback server or a mock server. Passing awaits
  the first CI run.
- **wired, not proved**: the WinUI code calls the tested rule; proving it needs a Windows desktop.
- **not proved (needs Windows)**: the scenario is only visible on a Windows desktop, or needs a
  server this host cannot start (the Samba fixture needs Docker), and nothing here can stand in.
- **not started**: no code, with the reason. Each one is a gap in the core's seam or a task
  outside this lane; the last section lists them.

No scenario is marked passed. No capture has been made: every screen task also owes captures in
light and dark, at the default and the largest text size, which need a Windows desktop.

## The seam (task 3.21, the twenty-eight wave 3 exports)

| What | Where | Test | State |
| --- | --- | --- | --- |
| Status codes 8 and 9 have their names; every `STORYARC_ERROR_*` constant is named | `StoryArcStatus` | `NativeCoreSeamTests.Every_status_the_header_defines_has_its_name_here`, `NetworkSeamTests.Every_status_code_the_core_defines_has_a_name_here` | tested |
| The runtime, and the order handles are freed in | `CoreRuntime`, `CoreHandle.Retain` | `The_runtime_outlives_every_handle_made_from_it_whatever_order_they_are_disposed_in` | tested |
| The network state is one of three; an undescribed connection is not metered | `CoreRuntime.Connection` | `The_network_state_is_one_of_three_and_an_undescribed_connection_is_not_metered` | tested (the Windows provider, `NetworkCostType`, runs only on Windows: not proved) |
| The HTTP client and its pins; one client per transfer | `CoreHttp`, `PinBook` | `A_pin_goes_to_the_book_and_every_later_client_starts_with_it` | tested |
| An OPDS page, both dialects, a sign-in, a search | `CoreHttp.OpdsFeed` | `A_catalogue_page_crosses_as_a_record`, `The_catalogue_mock_serves_both_dialects_a_search_and_a_sign_in` (node) | tested |
| An untrusted certificate shows its fingerprint | `CertificateChallenge` | `A_certificate_the_system_does_not_trust_is_named_by_its_fingerprint_for_the_reader_to_pin` | tested; the pin sheet is wired, not proved |
| Kavita: connect, libraries, series, volumes, continue point, refused key | `CoreHttp.Kavita*` | `The_kavita_mock_signs_in_lists_libraries_series_and_volumes_and_refuses_a_bad_key` (node) | tested |
| SMB: unreachable and an address that is not one | `SmbShare.Connect` | `A_share_that_does_not_answer_is_unreachable_and_grey`, `An_address_that_is_not_a_share_is_refused` | tested |
| SMB: dialect, encryption, a folder listing, a wrong password | `SmbShare` | `The_samba_fixture_reports_its_dialect_and_encryption_and_lists_its_folders`, `A_wrong_password_is_named_apart_from_an_unreachable_host` | not proved: skip with a stated reason when no Samba answers (`pnpm smb` needs Docker) |
| A download lands verified, with progress on the calling thread | `CoreHttp.Fetch`, `[UnmanagedCallersOnly]` callback | `A_download_lands_verified_and_reports_its_progress_on_the_calling_thread` | tested |
| Bytes that are not a book are unreadable; a raised token keeps the partial file | `CoreHttp.Fetch` | `Bytes_that_are_not_a_publication_are_unreadable_and_a_raised_token_keeps_the_file_for_a_resume` | tested |
| A throwing progress handler never reaches the core | `OnProgress` | `A_progress_handler_that_throws_never_reaches_the_core` | tested |
| The three ways a transfer began | `CoreHttp.ResumptionOf` | `The_three_ways_a_transfer_began_are_read_from_the_cores_own_shape` | tested |
| The vault: save, load, delete | `CredentialVault` | `SourceCredentialsTests` | tested (Credential Manager itself runs only on Windows: not proved) |
| The queue rules | `DownloadQueues` | `DataSeamTests` (metered, unmetered, mid-download, offline, retry, verification) | tested |
| Shelves and the offline edit pull | `ShelfRules` | `DataSeamTests` | tested |
| A phone document imports, exports and syncs; an unplugged folder is unreachable; a newer format is refused | `LibraryDocuments` | `A_phone_document_imports_exports_and_syncs_...`, `A_document_from_a_newer_app_is_refused_naming_both_versions` | tested |
| Sealed credentials; a wrong passphrase opens nothing | `LibraryDocuments.SealCredentials` | `Credentials_travel_only_sealed_and_a_wrong_passphrase_opens_nothing` | tested |
| The diagnostic redacts; a folder weighs | `Diagnostics`, `StorageBytes` | `DataSeamTests` | tested |

## sources and desktop-experience, "Secrets in the system's own store" (tasks 3.21, 3.22)

| Scenario | Where | Evidence | State |
| --- | --- | --- | --- |
| Adding the first source | `SourcesPage.AddAsync`, `NetworkServices.AddSourceAsync`, `SourceProbe` | `SourceProbeTests`, `NetworkSourcesTests` | wired, not proved |
| Renaming, removing a source | `SourcesPage`, `NetworkServices.Rename/RemoveSource` (credential, shelves and edits go with it) | `NetworkSourcesTests.A_source_is_renamed_removed_and_never_renamed_to_nothing` | wired, not proved |
| Reordering sources | none | none | not started: the list keeps the order of adding; a drag handle is not built |
| Saving a password: the record holds only a reference | `NetworkSource` has no secret field | `A_source_added_keeps_no_credential_and_the_list_survives_a_save_and_a_restore` | tested |
| A sign-in typed inside an address is split out | `TypedAddress` | `A_sign_in_typed_into_an_address_is_split_out_so_the_record_never_holds_it` | tested |
| A secure store that is not running: say once, in grey, work for the session | `SourceCredentials`, the core's notice shown by the add sheet | `Without_a_secure_store_the_first_save_says_once_what_supplies_one` | tested on the hosts here (session-only); Credential Manager unavailable on a real PC: not proved |
| A secret the store refuses: name it, keep no copy, the source needs a sign-in | `CredentialOutcome.Refused`, `SourceMessages` | `The_limit_counts_bytes_not_characters_and_a_refused_longer_credential_keeps_no_older_copy` | tested; the refusal by Windows itself: not proved |
| The 2560-byte rule | `SourceCredentials.Fits` | `A_token_is_kept_up_to_2560_bytes_and_refused_by_name_beyond` (2559, 2560, 2561, 4000) | tested |
| Searching the data directory, the logs and an exported diagnostic for a secret, in any encoding | `DataDirectorySearch` | `No_file_the_app_writes_holds_a_credential_in_any_encoding_...` (a 2404-byte token and a typed password; UTF-8, UTF-16 both orders, Latin-1, hex, base64 at three alignments, percent, reversed), and `The_search_itself_finds_a_credential_in_each_encoding_...` so a clean result means something | tested; the app's log is not covered because the app writes none |
| Reading a secret back | `SourceCredentials.Load` | `A_password_goes_to_the_vault_and_comes_back_...` | tested |
| Source unreachable, credentials rejected, a certificate not trusted: each named apart, grey | `SourceFailure`, `SourceMessages.State` | `Each_failure_of_a_source_is_named_apart_from_the_others`, `An_untrusted_certificate_carries_its_fingerprint_...` | tested; the grey row: wired, not proved |
| Automatic recovery, retry policy | the page checks each source at launch and on Test; no timer re-checks | none | not started: a source returns on the next Test or launch, not by itself |
| Metadata cache, source health visibility, refresh visibility | none | none | not started: the core's `MetadataCache` and `SourceHealth` are not on the seam |

## network-share (task 3.21)

| Scenario | Where | Evidence | State |
| --- | --- | --- | --- |
| Adding a share by address, user and password | `SourcesPage`, `SmbConnection` | `SourceProbeTests` | wired, not proved |
| Browsing to a subfolder | `SourcesPage.BrowseAsync` over `SmbShare.List` | the Samba test | not proved (needs Docker) |
| SMB 1 only server refused by name with the remedy, never fallen back to | `SourceProblem.Smb1Only`, `smb_error_smb1` | `Each_failure_of_a_source_is_named_apart_from_the_others` (the core's sentence); the server itself: the SMB 1 fixture | tested for the mapping; the refusal: not proved |
| Encrypted transport stated on the source | `SourceCheck.Transport` ("SMB 3.1.1 · encrypted") | the Samba test | not proved |
| Discovery the system does not offer: say so once, address field is the way in | `SourcesPage.DiscoveryNote` | none | wired, not proved (a Windows desktop) |
| Connection drops, sleep and wake, network change, repeated failure | none | none | not started: the seam has no way to open a file on a share, so there is nothing to drop (see the gaps) |
| Streaming reads, opening a large archive | none | none | not started: no `smb` open or read export; shares are listed, not read |
| Local network permission | Windows asks nothing for the MSIX `privateNetworkClientServer` capability, added to the manifest | `Package.appxmanifest` | not proved (needs Windows) |

## opds-catalog and kavita-server (task 3.21)

| Scenario | Where | Evidence | State |
| --- | --- | --- | --- |
| Adding a catalogue; HTTP authentication; version detection fails; a feed that is a web page | `SourcesPage.AddAsync` over `OpdsFeed` | `A_catalogue_page_crosses_as_a_record`, the mock test (`/private`, `/page`) | tested for the call; the sheet: wired, not proved |
| A self-signed certificate: fingerprint, trust, retry | `NetworkServices.Trust`, `PinBook` | `A_pin_goes_to_the_book_...` | tested for the book; the sheet: wired, not proved |
| Browsing a navigation, grouped and paginated feed; facets | `SourcesPage.BrowseAsync` shows navigation links, entries and "more" | `OpdsPage` records over the mock | wired, not proved; facets are not drawn |
| Search; a catalogue without search says so | the search box when `Searchable`; `LocalOnly` line | `OpdsRequest.Search` | wired, not proved |
| Acquisition: download the best format; no supported format | `OpdsEntry.Best`, `CanDownload`, `NetworkServices.Download` | `A_queued_download_lands_in_the_folder_through_the_core_and_the_row_finishes` | tested; the button: wired, not proved |
| Borrowing and indirect acquisition | none | none | not started |
| Kavita: adding a server with an API key; a revoked key | `SourcesPage`, `SourceProbe` | `The_kavita_mock_accepts_its_key_and_refuses_another_as_a_sign_in_problem` | tested |
| Kavita: browsing libraries, series, volumes with progress, the continue point | `SourcesPage.BrowseAsync` | `The_kavita_mock_signs_in_lists_libraries_series_and_volumes_...` | tested for the calls; the page: wired, not proved |
| Kavita: keeping a chapter on the device, reading it offline | none | none | not started: the core's `connect` does not return the session token a chapter download needs, and `storyarc_download_fetch` has no Kavita signing. The page says so in grey. |
| Kavita: progress pushed and pulled, marking read state, server collections, server search | none | none | not started: the seam has `continuePoint` and the totals only; `ProgressPull`, `KavitaExchange` and `push` are not exported |

## offline-downloads and desktop-experience, "Metered connections", "No presence when the app is closed" (task 3.23)

| Scenario | Where | Evidence | State |
| --- | --- | --- | --- |
| Metered: hold back what the policy queued and say why; start by hand | `DownloadCoordinator`, `DownloadQueuePanel.StateLine` | `A_metered_connection_holds_back_what_the_policy_queued_and_says_why_but_a_reader_can_still_start_one_by_hand` | tested; the grey line: wired, not proved |
| Not metered, or the system does not say | `CoreRuntime.Connection`, `DownloadPolicySettings.ConcurrencyFor` | `An_unmetered_connection_runs_the_policys_bound_...`, `The_hosts_bound_is_the_number_the_core_says_may_start` | tested |
| A network that changes mid-download | `DownloadCoordinator.NetworkChanged`, the timer's five-second poll in `NetworkServices.Tick` | `A_connection_that_turns_metered_mid_download_pauses_the_row_keeps_its_bytes_and_an_unmetered_one_resumes_it` | tested; a real tether: not proved |
| No connection: library reads, the queue waits in grey | same | `With_no_connection_the_queue_waits_in_grey_...` | tested |
| A download in progress at quit: say before quitting, partial file kept, resumes at the next launch | `AppHost.QuitAsync`, `MainWindow.ConfirmQuitAsync`, `DownloadCoordinator.QuitAsync/Start` | `Quitting_during_a_download_asks_first_stops_it_keeps_the_partial_file_and_the_next_launch_resumes_it` | tested; the dialog and the closing of the last window: wired, not proved |
| After quitting no process, tray or sync continues; no notification | no tray code, no background task, no notification call; `Exit` stops the transfers | by construction | not proved (needs Windows: Task Manager after a quit) |
| A finished download or a refresh raises no notification | `Landed` adds the folder to the library, nothing else | by construction | wired, not proved |
| Queue controls, resuming after an interruption, failure, concurrency | `DownloadCoordinator`, `DownloadQueuePanel` | `A_reader_pauses_resumes_and_removes_...`, the retry and verification tests | tested; the panel: wired, not proved |
| Retry: three attempts, two and four seconds | `DownloadBackoff` | `A_transfer_that_fails_is_tried_again_after_two_and_four_seconds_and_then_fails_for_good` | tested |
| Bytes that arrive and will not open: requeued once | `QueueOp.FailVerification` | `Bytes_that_arrive_whole_and_will_not_open_are_requeued_once_...` | tested |
| Storage view: each store sized and cleared on its own | `StorageUsage`, `PreferencesPage.StorageEditor` | `Each_store_is_measured_and_cleared_on_its_own` | tested; the menu: wired, not proved |
| Storage limit, automatic cleanup, low-storage warning | the policy takes `StorageLimitBytes` (settings), no control sets it | none | not started: no limit control; automatic cleanup is not built |
| A full disk: name it in grey, keep what it had, offer a cache to clear | `DiskFull`, the queue's disk line, the storage note | `A_full_disk_is_recognised_from_the_system_and_from_the_core_...` | tested; a real full disk: not proved |
| Where the data lives, nothing roams | `StateFiles` under the package's `LocalFolder`; the storage note says so | `StorageUsage` takes the folders it is given | wired, not proved (MSIX redirection needs Windows) |
| Removing the app's data before an uninstall | the Records clear runs at the next start | none | not started for the whole data folder; each store is clearable |
| Backup exclusion | none on Windows (the design drops the flag) | none | not applicable |

## desktop-experience, "Exporting a diagnostic to a file" and "Sync when the app runs" (task 3.23)

| Scenario | Where | Evidence | State |
| --- | --- | --- | --- |
| Saving the diagnostic: shown in full, a save dialog, a file written | `DiagnosticReport`, `PreferencesPage.ShowDiagnosticAsync`, `FileSavePicker` | `The_report_holds_the_phones_sections_...`, `Saving_writes_the_file_the_reader_named_and_nothing_else_beside_it` | tested; the picker: wired, not proved |
| Credentials, tokens and host names redacted as on a phone | `Diagnostics.Render` | `A_credential_and_a_host_name_are_redacted_wherever_they_could_have_come_from` | tested; the mobile suites' own redaction test is not run here |
| A place that cannot be written: named, another offered, nothing written elsewhere | `DiagnosticFile.Write`, the dialog stays open | `A_place_that_cannot_be_written_is_named_with_its_reason_and_nothing_is_written_elsewhere` | tested |
| Cancelling writes no file and keeps nothing | `ExportOutcome.Cancelled` | `Cancelling_the_save_dialog_writes_no_file` | tested |
| Sync at start: merge before Continue reading, never block the window | `NetworkServices.StartAsync` (two-second budget), `AppHost.StartLibraryAsync` | `At_start_the_sync_runs_on_a_worker_and_a_slow_location_never_holds_the_caller` | tested; the window: wired, not proved |
| Sync at quit: once more if the position changed, within five seconds, quit regardless | `LibrarySyncRunner.AtQuitAsync`, `AppHost.Exit` | `At_quit_a_location_slower_than_the_budget_is_left_behind_and_the_app_quits_regardless`, `At_quit_an_unchanged_position_writes_nothing`, `At_quit_a_changed_position_is_written_once_...` | tested; a write cut off by the process ending leaves the old document (the core writes over the version it read) |
| Offline: read normally, no red, sync when it returns | `SyncState.Unreachable`, retry after a minute | `A_folder_that_does_not_answer_is_grey_not_an_error_and_is_tried_again_after_a_minute` | tested |
| A document from a newer app | `SyncState.DocumentTooNew`, `sync_status_newer` | `A_document_from_a_newer_app_is_named_and_left_alone` | tested |
| Library import of a phone's document: positions, shelves, pins, sources needing a sign-in | `LibraryMerge`, `NetworkSourceList.Adopting`, `NetworkServices.Apply` | `A_phone_document_imports_exports_and_syncs_...`, `The_sources_a_phone_added_arrive_as_needing_a_sign_in_...` | tested; the import menu command: not started (only the sync folder imports) |
| Export the library with sealed secrets | `LibraryDocuments.Export(passphrase, credentials)` | `Credentials_travel_only_sealed_...` | tested; no screen calls it: not started |

## collections-and-reading-lists (task 3.23a)

| Scenario | Where | Evidence | State |
| --- | --- | --- | --- |
| Creating, renaming, deleting a collection or a list | `ShelvesPage`, `ShelfRules` | `DataSeamTests`, `ShelfScreensTests` | tested; the dialogs: wired, not proved |
| Adding to a collection from a selection (bulk) | `MainWindow` Add to shelf over `ShelfMembership.Adding` | `Membership_is_added_in_bulk_removed_and_shown_as_checkmarks_...` | tested; the menu: wired, not proved |
| A shelf made on a phone finds the same publication | `ShelfMemberId` (`path:`, `srv:`, `sha:`) | `A_shelf_made_on_a_phone_finds_the_same_publication_by_its_stable_id` | tested |
| Cover for a collection: the chosen one, else the first four available, else a placeholder | `ShelfPageModel.CoverIds` | `A_shelfs_tile_shows_the_chosen_cover_or_the_first_four_available_members` | tested; the tile is not drawn: the page lists rows without covers |
| Ordering a list; reading through a list; progress through a list; next entry | `ShelfPageModel`, move buttons | `A_reading_list_counts_what_is_finished_over_what_the_library_reports_and_names_the_next_entry` | tested; a drag to reorder: not started (buttons only) |
| An entry no longer available stays in grey | `ShelfPageRow.IsAvailable` | `A_collection_lists_its_members_by_title_...` | tested |
| Pinned order and Home | `PinnedShelves`, `HomeShelfRows`, `MainWindow.ShowHome` | `Pinned_shelves_keep_the_order_...`, `Home_draws_only_the_pinned_shelves_...`, `A_pinned_order_survives_the_library_document_both_ways` | tested; Home: wired, not proved |
| Editing while the server is unreachable: the edit waits, shown in grey | `ShelfEditQueue`, `ShelfRules.Project` | `A_pending_edit_shows_after_the_servers_own_rows_...`, `An_edit_waiting_for_a_server_shows_in_grey_...` | tested for the model; nothing fills it: not started (no Kavita shelf calls on the seam) |
| Conflicting edit: the server's version wins, the reader is told once | `ShelfRules.Pull` | `An_edit_for_the_same_entry_replaces_the_earlier_one_and_the_core_pushes_what_nobody_else_touched` | tested for the rule; the notice is not shown: not started |
| Mixed listing, converting a local list to a server list | none | none | not started |
| Downloading a collection, marking a list read | none | none | not started: bulk download from a shelf and bulk read state are not built |
| A source is removed: its shelves go | `NetworkServices.RemoveSource` | `ShelfOp.RemoveSource` in `DataSeamTests` | tested for the op; wired, not proved |
| Sidebar: each shelf is a child of Shelves | `MainWindow.SyncShelfItems` | none | wired, not proved |

## Gaps in the core's seam, found while walking

Worked around where the work could be done here, and named for the core's owner. Nothing in
`apps/desktop-core` was edited.

1. **No `marking` and no `recording_attempt` on the queue.** A row in flight stays queued in the
   core's value; `DownloadCoordinator` knows which rows are active and subtracts them from the
   bound, and keeps how each transfer began itself.
2. **A retry resets the attempts.** `storyarc_queue_apply`'s `resume` forgets them, so the coordinator
   counts failures itself and spends the three attempts with `fail(retryable: false)`.
3. **No `edits::projecting`, `ShelfEditQueue` editing, `PublicationIdentity::stable_id` or
   `cover_members`.** Each is a few lines and is mirrored in C# with a test; they should be exported
   or the mirror pinned to the core's own cases.
4. **No SMB open or read.** A share can be connected to and listed, not read, so a file on a share
   cannot be opened, streamed or downloaded from this app yet.
5. **No Kavita session token, no shelf calls, no progress exchange.** `connect` returns the account's
   name only, so a Kavita chapter cannot be downloaded; collections and reading lists of a server,
   `ProgressPull` and `push` are not exported.
6. **No progress listing.** The store is read by identity, so the sync snapshot asks it for each
   publication the library knows.
7. **No metadata cache, source health or refresh state** on the seam.

## What this walk did not cover

- Task 3.22's "Credential Manager backend" is the core's; on this host the vault is the
  session-only store, so the blob limit is enforced in C# on every host and the real store is run
  only by the first Windows session.
- `RELEASE_NOTES.md` is not touched: no desktop build is released.
- The Linux `.po` files changed only because `pnpm strings:desktop` writes both outputs from the one
  catalogue this lane added keys to.
