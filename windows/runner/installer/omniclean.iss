; OmniClean Engine - Windows installer script for Inno Setup 6.
;
; Build with:  ISCC.exe /Q windows\runner\installer\omniclean.iss
; (the release workflow runs this on windows-latest).

#define AppName "OmniClean Engine"
#define AppVersion "1.0.0"
#define AppExeName "omni_clean_engine.exe"
#define AppPublisher "OmniClean Engine"
#define AppUrl "https://github.com/aihams21/OmniClean-Engine"

[Setup]
AppId={{7C3F1A2E-9D4B-4E11-9C1F-2A6B8D5E7F30}
AppName={#AppName}
AppVersion={#AppVersion}
AppPublisher={#AppPublisher}
AppPublisherURL={#AppUrl}
AppSupportURL={#AppUrl}
AppUpdatesURL={#AppUrl}
DefaultDirName={autopf}\OmniClean Engine
DefaultGroupName={#AppName}
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
OutputDir=..\..\..\build\windows\x64\runner\installer\Output
OutputBaseFilename=OmniClean-Engine-{#AppVersion}-windows-x64-setup
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
ArchitecturesInstallIn64BitMode=x64compatible
UninstallDisplayIcon={app}\{#AppExeName}
SetupIconFile=..\..\..\resources\icon\omniclean-engine.ico
AppMutex=OmniCleanEngineMutex

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "Create a desktop shortcut"; GroupDescription: "Additional shortcuts:"

[Files]
; The whole Release folder: the runner executable plus data\ (Flutter assets) and
; lib\ (the GTK/GL loader DLLs that Flutter ships for Windows).
; Inno Setup resolves this relative to the .iss file, which lives in
; windows\runner\installer\, so the build output three levels up is
; windows\x64\runner\Release — not windows\runner\Release.
Source: "..\..\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\{#AppName}"; Filename: "{app}\{#AppExeName}"
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\{#AppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#AppExeName}"; Description: "Launch {#AppName}"; Flags: nowait postinstall skipifsilent

[UninstallDelete]
; User data (settings, quarantine) lives under %APPDATA% and is preserved on
; purpose: removing it would throw away anything still restorable.
Type: filesandordirs; Name: "{app}\logs"
