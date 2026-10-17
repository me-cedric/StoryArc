# Linux conformance walk, wave 3

Task 3.20 of `desktop-clients`, lane L, branch `lane/linux-wave3`, cut from `main` at `50ab00a9` (the wave 3 core and the
wave 2 walk fixes). The scenarios are those of the seven `desktop-experience` requirements the Linux wave 3 tasks
name: secrets, metered connections, exporting a diagnostic, storage, sync, finding and reaching a network share, and no
presence when the app is closed. Each is judged against the Linux app at the head of this branch. Results use the
words of the wave 2 walk: pass (a named test asserts it), seen (the walk under cage showed it), **fail**, later (a
later task builds it), not proved (it needs a real session or daemon this lane did not have).

**What the walk is.** The debug build ran under cage (headless wlroots, 1280 by 720) in an Ubuntu 24.04 container with
GTK 4.14 and libadwaita 1.5, driven by `wtype` and captured by `grim`, with a session D-Bus and no Secret Service.
The mock servers ran on the host and the container reached them through `host.docker.internal`: `pnpm opds` (port 4444),
`pnpm kavita` (port 5001, key `storyarc-test-key`), and the Samba fixture image of `docs/delivery/desktop-spike-smb.md`
on ports 4545 (plain), 4546 (encrypted) and 4550 (SMB 1 only), user `reader`. Captures were looked at and are not
committed. Two scripted-walk hooks were added beside `open-reader`: `app.add-network-source`, `app.show-network-source`,
`app.library-action` and `app.show-shelf`. In a headless cage the frame clock sleeps until a key arrives, so the walk
sends one key before each capture; a first Return after a run of Tab presses on a sidebar row was sometimes not
delivered, so the walk opens pages through the hooks where it matters (the harness may have lost it; a real session is
owed a check).

Defects the walk found and fixed on this branch: the add sheets were dropped when the function that presented them
returned, so Connect did nothing; two nested network pages shared one tag, so the second push failed; and a finished
download did not reach the library until the downloads folder became a hidden library of its own.

## Secrets in the system's own store

| Scenario | Result | Evidence |
| --- | --- | --- |
| Saving a password | pass | `secret_state` tests: a running store keeps the secret and the record holds only an id (`remote_sources` tests: the file holds id, name, address and user). The Secret Service backend itself is the core's and its Linux run needs a daemon: not proved on `gnome-keyring`. |
| A secure store that is not running | pass, seen | `no_service_holds_the_secret_for_the_session_and_says_so_once_in_grey`; the walk with no daemon showed the grey line in Settings, Storage, Passwords, and each seeded source with a user said "Needs a sign-in" after a relaunch. |
| A secret the store refuses | pass | `a_store_that_refuses_is_named_keeps_no_copy_and_leaves_the_source_needing_a_sign_in`. No walk against a locked keyring. |
| Searching the app's files | pass | `the_report_holds_no_secret_in_any_encoding_and_no_hostname` (diagnostic); `the_file_keeps_an_id_a_name_an_address_and_a_user_and_no_secret`. A search of the walk's data directory for the typed password was not run. |

Not proved: the walks on Hyprland, on GNOME with `gnome-keyring`, and in a Flatpak (the portal file keyring). The no
daemon case was walked in the container, which is the nearest this host gets to Hyprland.

## Metered connections

| Scenario | Result | Evidence |
| --- | --- | --- |
| A metered network | pass | `a_metered_connection_holds_back_what_the_policy_queued_and_says_why_in_grey`, `a_download_started_by_hand_runs_on_a_metered_connection`. |
| A network that is not metered | pass | `an_unmetered_or_undescribed_connection_runs_the_queue_as_the_policy_says`. |
| A network that changes mid-download | pass | `a_change_to_metered_mid_download_pauses_the_running_row_and_a_return_resumes_it`. |
| No connection | pass | `with_no_connection_the_queue_waits_in_grey_and_the_readers_pause_is_not_lifted`. |

Not proved: the NetworkManager and portal readings on a phone tether (the core's provider is not run here), and a walk
of the preference row on a metered link.

## Exporting a diagnostic to a file

| Scenario | Result | Evidence |
| --- | --- | --- |
| Saving the diagnostic | pass | `saving_writes_the_text_to_the_chosen_file`; redaction in `the_report_holds_no_secret_...`. The dialog and the save chooser were not reached by keys in the walk: not proved as seen. |
| A place the file cannot be written | pass | `a_place_that_cannot_be_written_is_named_and_nothing_is_written_elsewhere`. |
| Cancelling | pass | `cancelling_writes_nothing`. |

## Storage on a desktop

| Scenario | Result | Evidence |
| --- | --- | --- |
| Where the data lives | pass, seen | `each_store_has_its_own_folder_and_none_is_roaming`, `the_size_counts_...`, `clearing_one_store_empties_it_and_touches_no_other`; the walk showed Settings, Storage with the three sizes and a Clear on downloads and covers. |
| A full disk | pass | `a_full_disk_is_named_and_another_failure_is_not_called_one`. No full disk was made in the walk. |
| Removing the app | later | The preference to remove the app's data before uninstalling is not built; Clear on each store is the nearest. |

## Sync when the app runs

| Scenario | Result | Evidence |
| --- | --- | --- |
| At start | pass (partly) | The merge runs on a worker and never blocks the window (`sync_ui::at_start`). It merges after the window is up, not before Continue reading is drawn: Home redraws when the merge lands. Not walked against a folder. |
| At quit | pass | `a_slow_sync_location_never_holds_the_quit_past_its_budget`, `quit_writes_the_document_only_when_a_position_changed_and_a_place_exists`. Not walked. |
| Offline | pass | `a_quick_sync_answers_and_an_unreachable_place_is_grey_not_an_error`. |

## Finding and reaching a network share

| Scenario | Result | Evidence |
| --- | --- | --- |
| Discovery that the system offers | pass | `avahi_lines_become_suggestions_once_per_host`. No Avahi daemon in the container: not proved on a LAN. |
| Discovery the system does not offer | seen | The sheet said "This system does not announce shares (Avahi is not running), so enter the address by hand." in grey, with the fields below. |
| An old protocol | seen | Against the SMB 1 only Samba the sheet named SMB 1 and the server setting to change; it did not connect. |
| Encryption | seen | The encrypted Samba on 4546 connected and the share was added; the added toast names the dialect and whether it is encrypted (not captured). |
| A server that cannot be reached | seen | Unreachable host, missing share and refused password each gave a different grey sentence (`every_named_share_failure_is_grey_...` asserts the three differ). |
| A laptop that sleeps | not proved | The core's reconnect is its own test; no sleep was made. |

## No presence when the app is closed

| Scenario | Result | Evidence |
| --- | --- | --- |
| After quitting | pass | The app has no tray, daemon or notification code; the core's transfers are cancelled in `finish_quit` before the process ends. No process listing after quit was taken. |
| A download in progress | pass | `quitting_with_a_download_running_asks_and_says_it_pauses_and_resumes`, `a_launch_puts_a_row_that_was_running_back_in_the_queue_and_keeps_its_bytes`. The prompt was not seen: a mock download finishes before a key can quit. |
| A finished download or a refresh | seen | A download from the catalogue finished, appeared under Downloads and in the Library with no notification. |

## Wave 3 capability walks

| Capability | Result | Evidence |
| --- | --- | --- |
| `opds-catalog` add and browse | seen | Added the mock catalogue by address, opened its feed, queued "Flaky Transfer", watched it land in Downloads (2.0 kB) and in the Library. Basic auth and the certificate pin were not driven through the sheet. |
| `kavita-server` add | seen | Added with the API key; a wrong key said it was refused in grey. Browsing a series and the progress exchange were not walked. |
| `network-share` add and list | seen | Added from typed fields; files are listed in a share's page, but reading a file in place is not built (the reader opens paths): later. |
| `collections-and-reading-lists` | seen, pass | Created a collection from the selection (27 titles), opened its page, pinned it so Home draws it, selected on its page. `shelf_rules` tests cover membership, order, bulk removal, pins, tombstones and pending edits. Server shelves and renaming are not built. |
| Source states | seen | A source whose secret is gone is grey "Needs a sign-in", in the sidebar, its page and Settings. |

Remaining: the Kavita progress exchange and library sync of its positions in the app; server-defined shelves; the share's
files opened without a download; rename of a shelf; the diagnostic dialog seen; a Flatpak, Hyprland and GNOME run.
