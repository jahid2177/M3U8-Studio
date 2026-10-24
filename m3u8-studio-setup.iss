; One-click installer built from the COMPLETE Flutter Windows release folder.
; Run on a Windows x64 GitHub runner after `flutter build windows --release`.

#define AppName "M3U8 Studio"
#define AppVersion "1.0.1"
#define AppExeName "m3u8_studio.exe"

[Setup]
AppId={{E4F943D6-8B8A-4EB7-A2A0-1F61047AE113}
AppName={#AppName}
AppVersion={#AppVersion}
AppPublisher=Md Jahidul Islam
DefaultDirName={localappdata}\Programs\M3U8 Studio
DefaultGroupName={#AppName}
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
WizardStyle=modern
DisableWelcomePage=yes
DisableDirPage=yes
DisableProgramGroupPage=yes
DisableReadyPage=yes
OutputDir=build\installer
OutputBaseFilename=M3U8-Studio-Setup-x64
Compression=lzma2
SolidCompression=yes
UninstallDisplayIcon={app}\{#AppExeName}
CloseApplications=yes

[Files]
Source: "build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\M3U8 Studio"; Filename: "{app}\{#AppExeName}"; WorkingDir: "{app}"
Name: "{autodesktop}\M3U8 Studio"; Filename: "{app}\{#AppExeName}"; WorkingDir: "{app}"

[Run]
Filename: "{app}\{#AppExeName}"; Description: "Open M3U8 Studio"; Flags: nowait postinstall skipifsilent
