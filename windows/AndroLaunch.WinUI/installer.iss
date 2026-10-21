#ifndef PublishDir
  #error PublishDir must point to the self-contained WinUI publish directory
#endif
#ifndef ReleaseDir
  #define ReleaseDir "..\..\build\windows"
#endif

[Setup]
AppId={{C55DCA17-1B54-4FA6-932D-08EE92AD108A}
AppName=AndroLaunch
AppVersion=0.3.9
AppPublisher=AndroLaunch
AppPublisherURL=https://github.com/aman-senpai/AndroLaunch
DefaultDirName={localappdata}\Programs\AndroLaunch
DefaultGroupName=AndroLaunch
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0.17763
OutputDir={#ReleaseDir}
OutputBaseFilename=AndroLaunch-0.3.9-windows-x64-setup
SetupIconFile=Assets\app_icon.ico
UninstallDisplayIcon={app}\AndroLaunch.WinUI.exe
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
CloseApplications=yes
RestartApplications=no

[Files]
Source: "{#PublishDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\AndroLaunch"; Filename: "{app}\AndroLaunch.WinUI.exe"
Name: "{autodesktop}\AndroLaunch"; Filename: "{app}\AndroLaunch.WinUI.exe"; Tasks: desktopicon

[Tasks]
Name: desktopicon; Description: "Create a &desktop shortcut"; Flags: unchecked

[Run]
Filename: "{app}\AndroLaunch.WinUI.exe"; Description: "Launch AndroLaunch"; Flags: nowait postinstall skipifsilent

[UninstallDelete]
Type: filesandordirs; Name: "{app}\Assets"
