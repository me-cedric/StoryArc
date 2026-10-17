# Windows MSIX and the Store dry run

**Task 6.7 of `desktop-clients`. Written 2026-10-17 on a Mac, from vendor documentation and the research
file [`desktop-research-windows-2026-10-07.md`](desktop-research-windows-2026-10-07.md); no call below has
run on Windows and nothing has been submitted.** Open Question 9 of
[`design.md`](../openspec/changes/desktop-clients/design.md) asks whether a single-project app makes an MSIX
without Visual Studio, and the research (spike 4) asks for a hello-world submission. This page records what the
repository now does, and the steps a Windows host owes to close both. Confidence labels follow ADR-0005:
**Known** is read in Microsoft Learn, **Reported** comes from secondary sources, **Inferred** is a consequence
the text does not state, **Open** waits for a host.

## Exit criterion

A Store certification result for an MSIX built by the workflow, and the `runFullTrust` friction written in the
last section. On paper the build is ready; the submission is the owner's, with a Windows host and a Partner
Center account.

## What the repository does now

| Decision | Setting | Why |
| --- | --- | --- |
| Trimming | `PublishTrimmed=false` | Trimming needs a self-contained app (NETSDK1102). The app is framework dependent, so the base sets neither. **Known** |
| ReadyToRun | `PublishReadyToRun=false` | Same error, same reason. **Known** |
| Native AOT | `PublishAot=false` | Open Question 6 stays open: WinUI 3 with the interop layer is untried. |
| Signing | `AppxPackageSigningEnabled=false` | The Store signs the package after submission. A direct download waits on a signing identity (Open Question 8). **Known** |
| Bundle | `AppxBundle=Never`, one MSIX per architecture | The single-project page says it "doesn't currently support producing MSIX bundles"; the CI page shows a bundle with `AppxBundle=Always`. **Known, with a conflict**: the host steps below settle it. |
| Package step | `pwsh apps/desktop-windows/build.ps1 -Platform x64 -Package` | `dotnet build` with `GenerateAppxPackageOnBuild=true`, into `.build/msix/<platform>/`. **Open** whether the .NET SDK alone makes the package, or whether it needs the Visual Studio `msbuild` that the research names. |
| CI | `build-windows` and `build-windows-arm64` run the step with `continue-on-error: true` and upload `storyarc-msix-x64` and `storyarc-msix-arm64` | The step is unproven. Read the first runs, then drop `continue-on-error`. |

The package carries `THIRD_PARTY_NOTICES.md` and, when fetched, `pdfium.dll` beside the executable. The manifest
declares the three comic file types, the `storyarc` protocol (task 5.8), the `storyarc.exe` alias and the
capabilities `internetClient`, `privateNetworkClientServer` and `runFullTrust`. Its `Identity` and `Publisher`
are placeholders.

## Steps a Windows host owes

1. **Read the CI run.** Open the artifacts `storyarc-msix-x64` and `storyarc-msix-arm64` of a run on
   `windows-2025-vs2026`. Record: did the step pass with the .NET SDK alone? If it failed, copy the error here,
   add `microsoft/setup-msbuild` to the workflow and run `msbuild /restore` with the same properties.
2. **Register.** Partner Center registration is free for individuals and companies. **Known**
3. **Reserve the name** `StoryArc`. Partner Center then shows the package identity: `Name`, `Publisher` and
   `PublisherDisplayName`. Put all three in `Package.appxmanifest`; the upload is refused if they differ.
   **Known**
4. **Build the upload.** Add `-p:UapAppxPackageBuildMode=StoreUpload` to the build. It makes the `.msixupload`.
   Record whether x64 and ARM64 go in one submission as two packages, or need one `.msixbundle` made with
   `makeappx bundle /d <folder> /p StoryArc.msixbundle`. **Known** (the mode), **Open** (the bundle)
5. **Run the Windows App Certification Kit** on the package on a Windows 11 24H2 machine. Record each failed
   test by name. Store review runs the same tests. **Known**
6. **Install the package unsigned.** An unsigned MSIX does not install. For a local walk, sign a copy with a dev
   certificate: `winapp cert generate --publisher "CN=StoryArc Dev" --install-cert`, then `winapp pack`. The
   walk: launch, add a folder, open a comic, double click a `.cbz` while the app runs (one window, no second
   process), `storyarc "C:\path\comic.cbz"` from a terminal, `start storyarc://publication/<title>`. **Known**
7. **Submit** with the justification below, the privacy policy URL, the age rating answers, and no price.
8. **Write the result here**: the certification outcome, any question from review, the days it took.

## The `runFullTrust` friction

**Why the app declares it.** A WinUI 3 desktop app is a Win32 process. A packaged Win32 process runs only with
the restricted capability `runFullTrust`; there is no packaged WinUI 3 app without it. **Known**
The app also loads two native libraries (`storyarc_ffi.dll`, `pdfium.dll`) and opens the folders the reader
chose by path, which the capability allows without a broker. The other two capabilities are general and ask for
no justification. **Known**

**What review does.** A restricted capability makes the submission ask for a justification in the notes for
certification. **Reported**: review may ask a follow-up for apps that read user-provided content. **Open**
whether it does for a comic reader. The draft to paste, written for a reviewer:

> StoryArc is a WinUI 3 desktop app, a Win32 process, so it needs runFullTrust to start. It reads comics, ebooks
> and audiobooks from folders the reader chooses and from servers the reader configures (OPDS, Kavita, SMB). It
> loads its own Rust library and the PDFium library from its package folder, and opens the reader's folders by
> path. It does not change system settings, does not run files it opens, and does not install anything. Book
> content never reaches the network.

**Other friction to expect.** The package asks for Windows 11 24H2 (`MinVersion` 10.0.26100.0), so the listing
excludes older systems. The `storyarc` protocol and the `storyarc.exe` alias are declared, and a link opens a name
and never runs a command (`StoryArcLink`), which is the answer if review asks. A privacy policy URL is required
because the app reaches the network. **Inferred** for these three; no source states that review asks.

## Not done here

No Windows machine, no Partner Center account, no certification run. Steps 1 to 8 are the whole of what is owed.
