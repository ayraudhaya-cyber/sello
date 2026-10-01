; Step-by-step Sello setup wizard.
; Compile after Inno Setup 6 is installed:
;   & "C:\Program Files (x86)\Inno Setup 6\ISCC.exe" scripts\sello_windows.iss

#define AppVersion "1.0.11"
#define ReleaseDir "..\build\windows\x64\runner\Release"

[Setup]
AppId={{A7B3E6C1-4F28-4C9A-9D11-6E2B8F0C5A17}
AppName=Sello
AppVersion={#AppVersion}
AppVerName=Sello {#AppVersion}
AppPublisher=Unitech Solutions
AppPublisherURL=https://www.unitechsolutions.pro
AppSupportURL=https://www.cashro.pro
AppUpdatesURL=https://www.cashro.pro
VersionInfoCompany=Unitech Solutions
VersionInfoDescription=Sello setup
VersionInfoProductName=Sello
VersionInfoProductVersion={#AppVersion}
DefaultDirName={autopf}\Sello
DefaultGroupName=Sello
DisableProgramGroupPage=yes
UsePreviousAppDir=yes
CloseApplications=yes
RestartApplications=no
OutputDir=..\dist
OutputBaseFilename=sello-setup
Compression=lzma2
SolidCompression=yes
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
WizardStyle=modern
SetupLogging=no

[Messages]
WelcomeLabel1=Welcome to the Sello setup
WelcomeLabel2=This will install Sello %1 on your computer.%n%nSello is business software by Unitech Solutions.%n%n0765644465 / 0771916600%nwww.unitechsolutions.pro / www.cashro.pro%n%nClick Next to continue.
ClickNext=Next
ClickFinish=Finish
WizardSelectDir=Choose where to install Sello
SelectDirDesc=Where should Sello be installed?
SelectDirLabel3=Setup will install Sello in the following folder.
SelectDirBrowseLabel=To continue, click Next. If you would like to select a different folder, click Browse.
WizardReady=Ready to install
ReadyLabel1=Setup is ready to install Sello on your computer.
ReadyLabel2a=Click Install to continue, or Back if you want to review or change any settings.
FinishedHeadingLabel=Sello is installed
FinishedLabel=Sello has been installed on your computer.%n%nSoftware by Unitech Solutions%n0765644465 / 0771916600%nwww.unitechsolutions.pro / www.cashro.pro%n%nClick Finish to close this setup.

[Files]
Source: "{#ReleaseDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\Sello"; Filename: "{app}\sello.exe"
Name: "{autodesktop}\Sello"; Filename: "{app}\sello.exe"

[Run]
Filename: "{app}\sello.exe"; Description: "Open Sello"; Flags: nowait postinstall skipifsilent
