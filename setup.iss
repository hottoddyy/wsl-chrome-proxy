#define AppName      "WSL Chrome Proxy"
#define AppVersion   "1.3.3"
#define AppPublisher "hottoddyy"

[Setup]
AppId={{A1B2C3D4-E5F6-7890-ABCD-EF1234567890}
AppName={#AppName}
AppVersion={#AppVersion}
AppPublisher={#AppPublisher}
DefaultDirName={localappdata}\WslChromeProxy
DefaultGroupName={#AppName}
DisableDirPage=yes
DisableProgramGroupPage=yes
OutputDir=.
OutputBaseFilename=WSLChromeProxy-Setup
Compression=lzma2
SolidCompression=yes
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=
WizardStyle=modern
UninstallDisplayName={#AppName}
UninstallFilesDir={app}

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Files]
Source: "wsl\local-http-proxy.py";                    DestDir: "{app}\wsl";             Flags: ignoreversion
Source: "wsl\start-proxy.sh";                         DestDir: "{app}\wsl";             Flags: ignoreversion
Source: "scripts\chrome-extension-update-server.ps1"; DestDir: "{app}\scripts";         Flags: ignoreversion
Source: "scripts\proxy-control.ps1";                  DestDir: "{app}\scripts";         Flags: ignoreversion
Source: "chrome-extension.crx";                       DestDir: "{app}";                 Flags: ignoreversion
Source: "Install.ps1";                                DestDir: "{app}";                 Flags: ignoreversion
Source: "Uninstall.ps1";                              DestDir: "{app}";                 Flags: ignoreversion
Source: "VERSION";                                    DestDir: "{app}";                 Flags: ignoreversion

[Run]
Filename: "powershell.exe"; \
  Parameters: "-NoProfile -ExecutionPolicy Bypass -File ""{app}\Install.ps1"" -NoPause"; \
  WorkingDir: "{app}"; \
  Flags: waituntilterminated; \
  StatusMsg: "Configuring WSL Chrome Proxy..."

[Code]
// Run Uninstall.ps1 BEFORE Inno deletes the files
procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
var
  Script, Params: String;
  ResultCode: Integer;
begin
  if CurUninstallStep = usUninstall then begin
    Script := ExpandConstant('{app}\Uninstall.ps1');
    if FileExists(Script) then begin
      Params := '-NoProfile -ExecutionPolicy Bypass -File "' + Script + '" -Confirm';
      Exec('powershell.exe', Params, '', SW_SHOW, ewWaitUntilTerminated, ResultCode);
    end;
  end;
end;
