; The StoryArc installer for Windows (openspec change shared-release-train, design D5).
;
;   iscc /DAppVersion=0.2.1 /DArch=x64 /DSourceDir=<publish folder> /DOutputDir=<folder> StoryArc.iss
;
; It installs the self-contained, unpackaged build for the current user, with no administrator
; rights: into %LOCALAPPDATA%\Programs\StoryArc, with a Start menu entry and an uninstaller. The
; app keeps its data in %LOCALAPPDATA%\StoryArc (Shell/StateFiles.cs), which the uninstaller
; leaves, so a reinstall keeps the library.

#ifndef AppVersion
  #error Pass /DAppVersion=X.Y.Z
#endif
#ifndef Arch
  #error Pass /DArch=x64 or /DArch=arm64
#endif

[Setup]
; The AppId names this app to Windows across versions. Never change it: an upgrade would install beside the old copy.
AppId={{0034A7AF-18CE-424F-ABFD-70F4239E3245}
AppName=StoryArc
AppVersion={#AppVersion}
AppVerName=StoryArc {#AppVersion}
AppPublisher=me-cedric
AppPublisherURL=https://github.com/me-cedric/StoryArc
AppSupportURL=https://github.com/me-cedric/StoryArc/issues
VersionInfoVersion={#AppVersion}.0
DefaultDirName={autopf}\StoryArc
DisableDirPage=auto
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
#if Arch == "arm64"
ArchitecturesAllowed=arm64
ArchitecturesInstallIn64BitMode=arm64
#else
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
#endif
; Windows 11 24H2, the app's floor.
MinVersion=10.0.26100
SetupIconFile=..\src\StoryArc.Windows\Assets\AppIcon.ico
UninstallDisplayIcon={app}\StoryArc.exe
UninstallDisplayName=StoryArc
WizardStyle=modern
Compression=lzma2/max
SolidCompression=yes
CloseApplications=yes
OutputDir={#OutputDir}
OutputBaseFilename=StoryArc-{#AppVersion}-windows-{#Arch}-setup

[Languages]
Name: "en"; MessagesFile: "compiler:Default.isl"
Name: "de"; MessagesFile: "compiler:Languages\German.isl"
Name: "es"; MessagesFile: "compiler:Languages\Spanish.isl"
Name: "fr"; MessagesFile: "compiler:Languages\French.isl"

[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\StoryArc"; Filename: "{app}\StoryArc.exe"

[Run]
Filename: "{app}\StoryArc.exe"; Description: "{cm:LaunchProgram,StoryArc}"; Flags: nowait postinstall skipifsilent
