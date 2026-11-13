[Setup]
AppId={{APP_ID}}
AppVersion={{APP_VERSION}}
VersionInfoVersion={#GetVersionNumbersString("{{SOURCE_DIR}}\{{EXECUTABLE_NAME}}")}
VersionInfoProductVersion={#GetVersionNumbersString("{{SOURCE_DIR}}\{{EXECUTABLE_NAME}}")}
VersionInfoProductName={{DISPLAY_NAME}}
VersionInfoDescription=Elephant Network Installer ({{ARCH}})
AppName={{DISPLAY_NAME}}
AppVerName={{DISPLAY_NAME}}
AppPublisher={{PUBLISHER_NAME}}
AppPublisherURL={{PUBLISHER_URL}}
AppSupportURL={{PUBLISHER_URL}}
AppUpdatesURL={{PUBLISHER_URL}}
UninstallDisplayName={{DISPLAY_NAME}}
UninstallDisplayIcon={app}\\{{EXECUTABLE_NAME}}
DefaultDirName={{INSTALL_DIR_NAME}}
DisableProgramGroupPage=yes
OutputDir=.
OutputBaseFilename={{OUTPUT_BASE_FILENAME}}
Compression=lzma
SolidCompression=yes
SetupIconFile={{SETUP_ICON_FILE}}
WizardStyle=modern
PrivilegesRequired={{PRIVILEGES_REQUIRED}}
ArchitecturesAllowed={{ARCH}}
ArchitecturesInstallIn64BitMode={{ARCH}}

[Code]
function OpenProcess(Access: LongWord; Inherit: Boolean; ProcessID: LongWord): THandle;
  external 'OpenProcess@kernel32.dll stdcall';
function WaitForSingleObject(Handle: THandle; Milliseconds: LongWord): LongWord;
  external 'WaitForSingleObject@kernel32.dll stdcall';
function CloseHandle(Handle: THandle): Boolean;
  external 'CloseHandle@kernel32.dll stdcall';

function IsInAppUpdate: Boolean;
begin
  Result := ExpandConstant('{param:INAPPUPDATE|0}') = '1';
end;

function InitializeSetup: Boolean;
var
  TaskID: String;
  Index: Integer;
  Script: String;
  ResultCode: Integer;
begin
  Result := True;
  if not IsInAppUpdate then Exit;
  TaskID := ExpandConstant('{param:UPDATETASK|}');
  Result := Length(TaskID) = 32;
  for Index := 1 to Length(TaskID) do
    if Pos(TaskID[Index], '0123456789abcdef') = 0 then Result := False;
  if not Result then Exit;
  Script := '$ErrorActionPreference = ''Stop''; ' +
    '$root = [Environment]::GetFolderPath(''ApplicationData''); ' +
    '$state = Join-Path $root ''com.elephantroute\ElephantNetwork\updates\' + TaskID + '\install-state.json''; ' +
    'if (-not (Test-Path -LiteralPath (Split-Path $state))) { exit 1 }; ' +
    '$json = @{state=''waitingForExit''} | ConvertTo-Json -Compress; ' +
    '[IO.File]::WriteAllText(($state + ''.part''), $json); ' +
    'Move-Item -LiteralPath ($state + ''.part'') -Destination $state -Force';
  Result := ExecAsOriginalUser(ExpandConstant('{sys}\WindowsPowerShell\v1.0\powershell.exe'),
    '-NoProfile -NonInteractive -Command "' + Script + '"', '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
  if Result then Result := ResultCode = 0;
end;

function WaitForApplicationExit: Boolean;
var
  ProcessID: Integer;
  Handle: THandle;
begin
  Result := False;
  ProcessID := StrToIntDef(ExpandConstant('{param:UPDATEPID|0}'), 0);
  if ProcessID <= 1 then Exit;
  Handle := OpenProcess($00100000, False, ProcessID);
  if Handle = 0 then
  begin
    Result := True;
    Exit;
  end;
  Result := WaitForSingleObject(Handle, 45000) = 0;
  CloseHandle(Handle);
end;

procedure KillProcesses;
var
  InstallPath: String;
  Script: String;
  ResultCode: Integer;
begin
  InstallPath := ExpandConstant('{app}');
  StringChangeEx(InstallPath, '''', '''''', True);
  Script := 'Get-CimInstance Win32_Process | Where-Object { ' +
    '$_.ExecutablePath -and ' +
    '([IO.Path]::GetDirectoryName($_.ExecutablePath) -eq ''' + InstallPath + ''') -and ' +
    '(@(''ElephantNetwork.exe'', ''ElephantNetworkService.exe'', ''sing-box-windows-amd64.exe'', ' +
    '''FlClashCore.exe'', ''FlClashHelperService.exe'', ''ElephantNetworkHelperService.exe'') -contains $_.Name)' +
    ' } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force }';
  Exec(ExpandConstant('{sys}\WindowsPowerShell\v1.0\powershell.exe'),
    '-NoProfile -NonInteractive -Command "' + Script + '"', '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
end;

procedure RemoveLegacyService;
var
  ResultCode: Integer;
begin
  Exec(ExpandConstant('{sys}\sc.exe'), 'stop ElephantNetworkService', '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
  Exec(ExpandConstant('{sys}\sc.exe'), 'delete ElephantNetworkService', '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
end;

procedure RestoreOwnedLegacyProxy;
var
  ProxyServer: String;
  ProxyEnabled: Cardinal;
begin
  if RegQueryDWordValue(HKCU,
      'Software\Microsoft\Windows\CurrentVersion\Internet Settings',
      'ProxyEnable', ProxyEnabled) and (ProxyEnabled = 1) and
     RegQueryStringValue(HKCU,
      'Software\Microsoft\Windows\CurrentVersion\Internet Settings',
      'ProxyServer', ProxyServer) and
     ((CompareText(ProxyServer, '127.0.0.1:2334') = 0) or
      (CompareText(ProxyServer, 'localhost:2334') = 0)) then
  begin
    RegWriteDWordValue(HKCU,
      'Software\Microsoft\Windows\CurrentVersion\Internet Settings',
      'ProxyEnable', 0);
    RegDeleteValue(HKCU,
      'Software\Microsoft\Windows\CurrentVersion\Internet Settings',
      'ProxyServer');
  end;
end;

function IsOwnedHelperImagePath(const ImagePath, HelperPath: String): Boolean;
var
  Command: String;
  Executable: String;
begin
  Command := Lowercase(Trim(ImagePath));
  Executable := Lowercase(HelperPath);
  Result := (Command = Executable) or
    (Command = '"' + Executable + '"') or
    (Pos(Executable + ' --owner-sid ', Command) = 1) or
    (Pos('"' + Executable + '" --owner-sid ', Command) = 1);
end;

procedure UnregisterOwnedHelper(const FileName, ServiceName: String);
var
  HelperPath: String;
  ImagePath: String;
  ResultCode: Integer;
begin
  HelperPath := AddBackslash(ExpandConstant('{app}')) + FileName;
  if FileExists(HelperPath) and
     RegQueryStringValue(HKLM,
       'SYSTEM\CurrentControlSet\Services\' + ServiceName, 'ImagePath', ImagePath) and
     IsOwnedHelperImagePath(ImagePath, HelperPath) then
  begin
    Exec(HelperPath, 'uninstall', '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
  end;
end;

procedure UnregisterHelperService;
begin
  UnregisterOwnedHelper('ElephantNetworkHelperService.exe', 'ElephantNetworkHelperService');
  UnregisterOwnedHelper('FlClashHelperService.exe', 'FlClashHelperService');
end;

function PrepareToInstall(var NeedsRestart: Boolean): String;
begin
  Result := '';
  if IsInAppUpdate and not WaitForApplicationExit then
  begin
    Result := 'The application is still running. Close it and retry.';
    Exit;
  end;
  UnregisterHelperService;
  RemoveLegacyService;
  if not IsInAppUpdate then KillProcesses;
  RestoreOwnedLegacyProxy;
end;

function InitializeUninstall(): Boolean;
begin
  UnregisterHelperService;
  RemoveLegacyService;
  KillProcesses;
  RestoreOwnedLegacyProxy;
  Result := True;
end;

[Languages]
{% for locale in LOCALES %}
{% if locale.lang == 'en' %}Name: "english"; MessagesFile: "compiler:Default.isl"{% endif %}
{% if locale.lang == 'hy' %}Name: "armenian"; MessagesFile: "compiler:Languages\\Armenian.isl"{% endif %}
{% if locale.lang == 'bg' %}Name: "bulgarian"; MessagesFile: "compiler:Languages\\Bulgarian.isl"{% endif %}
{% if locale.lang == 'ca' %}Name: "catalan"; MessagesFile: "compiler:Languages\\Catalan.isl"{% endif %}
{% if locale.lang == 'zh' %}
Name: "chineseSimplified"; MessagesFile: {% if locale.file %}{{ locale.file }}{% else %}"compiler:Languages\\ChineseSimplified.isl"{% endif %}
{% endif %}
{% if locale.lang == 'co' %}Name: "corsican"; MessagesFile: "compiler:Languages\\Corsican.isl"{% endif %}
{% if locale.lang == 'cs' %}Name: "czech"; MessagesFile: "compiler:Languages\\Czech.isl"{% endif %}
{% if locale.lang == 'da' %}Name: "danish"; MessagesFile: "compiler:Languages\\Danish.isl"{% endif %}
{% if locale.lang == 'nl' %}Name: "dutch"; MessagesFile: "compiler:Languages\\Dutch.isl"{% endif %}
{% if locale.lang == 'fi' %}Name: "finnish"; MessagesFile: "compiler:Languages\\Finnish.isl"{% endif %}
{% if locale.lang == 'fr' %}Name: "french"; MessagesFile: "compiler:Languages\\French.isl"{% endif %}
{% if locale.lang == 'de' %}Name: "german"; MessagesFile: "compiler:Languages\\German.isl"{% endif %}
{% if locale.lang == 'he' %}Name: "hebrew"; MessagesFile: "compiler:Languages\\Hebrew.isl"{% endif %}
{% if locale.lang == 'is' %}Name: "icelandic"; MessagesFile: "compiler:Languages\\Icelandic.isl"{% endif %}
{% if locale.lang == 'it' %}Name: "italian"; MessagesFile: "compiler:Languages\\Italian.isl"{% endif %}
{% if locale.lang == 'ja' %}Name: "japanese"; MessagesFile: "compiler:Languages\\Japanese.isl"{% endif %}
{% if locale.lang == 'no' %}Name: "norwegian"; MessagesFile: "compiler:Languages\\Norwegian.isl"{% endif %}
{% if locale.lang == 'pl' %}Name: "polish"; MessagesFile: "compiler:Languages\\Polish.isl"{% endif %}
{% if locale.lang == 'pt' %}Name: "portuguese"; MessagesFile: "compiler:Languages\\Portuguese.isl"{% endif %}
{% if locale.lang == 'ru' %}Name: "russian"; MessagesFile: "compiler:Languages\\Russian.isl"{% endif %}
{% if locale.lang == 'sk' %}Name: "slovak"; MessagesFile: "compiler:Languages\\Slovak.isl"{% endif %}
{% if locale.lang == 'sl' %}Name: "slovenian"; MessagesFile: "compiler:Languages\\Slovenian.isl"{% endif %}
{% if locale.lang == 'es' %}Name: "spanish"; MessagesFile: "compiler:Languages\\Spanish.isl"{% endif %}
{% if locale.lang == 'tr' %}Name: "turkish"; MessagesFile: "compiler:Languages\\Turkish.isl"{% endif %}
{% if locale.lang == 'uk' %}Name: "ukrainian"; MessagesFile: "compiler:Languages\\Ukrainian.isl"{% endif %}
{% endfor %}

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: {% if CREATE_DESKTOP_ICON != true %}unchecked{% else %}checkedonce{% endif %}
[Files]
Source: "{{SOURCE_DIR}}\\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\\{{DISPLAY_NAME}}"; Filename: "{app}\\{{EXECUTABLE_NAME}}"
Name: "{autodesktop}\\{{DISPLAY_NAME}}"; Filename: "{app}\\{{EXECUTABLE_NAME}}"; IconFilename: "{app}\\data\\flutter_assets\\assets\\images\\icon.ico"; Tasks: desktopicon
[Run]
Filename: "{app}\\{{EXECUTABLE_NAME}}"; Description: "{cm:LaunchProgram,{{DISPLAY_NAME}}}"; Flags: {% if PRIVILEGES_REQUIRED == 'admin' %}runasoriginaluser{% endif %} nowait postinstall skipifsilent

Filename: "{app}\\{{EXECUTABLE_NAME}}"; Flags: runasoriginaluser nowait; Check: IsInAppUpdate
