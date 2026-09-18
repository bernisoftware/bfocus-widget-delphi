unit BFocusNotifier;

{ Notificação do sistema no desktop (BRIEF §4.5): quando o "•" acende e notifications=true.
  - Lazarus (LCL) e Delphi 2009+: TTrayIcon com balão;
  - Delphi 7: Shell_NotifyIcon direto (o D7 não tem TTrayIcon).
  Clicar no balão (ou no ícone) chama OnClick, que abre o widget. }

{$I BFocusDefines.inc}

interface

uses
  SysUtils, Classes
{$IFDEF BF_FPC}
  , ExtCtrls, Forms
{$ELSE}
  {$IFDEF BF_D2009}
  , ExtCtrls, Forms
  {$ELSE}
  , Windows, Messages, ShellAPI, Forms
  {$ENDIF}
{$ENDIF}
  ;

type
  TBFNotifier = class(TComponent)
  private
    FOnClick: TNotifyEvent;
{$IFDEF BF_FPC}
    FTray: TTrayIcon;
{$ELSE}
  {$IFDEF BF_D2009}
    FTray: TTrayIcon;
  {$ELSE}
    FWnd: HWND;
    FAdded: Boolean;
    procedure WndProc(var Msg: TMessage);
    procedure RemoveIcon;
  {$ENDIF}
{$ENDIF}
    procedure TrayClick(Sender: TObject);
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    procedure Show(const Title, Body: string);
    procedure Hide;
    property OnClick: TNotifyEvent read FOnClick write FOnClick;
  end;

implementation

uses
  BFocusText, BFocusModels;

{$IFDEF BF_FPC}
  {$DEFINE BF_TRAYICON}
{$ENDIF}
{$IFDEF BF_D2009}
  {$DEFINE BF_TRAYICON}
{$ENDIF}

{$IFDEF BF_TRAYICON}

constructor TBFNotifier.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FTray := TTrayIcon.Create(Self);
  FTray.Icon.Assign(Application.Icon);
  FTray.OnClick := TrayClick;
  {$IFNDEF BF_FPC}
  FTray.OnBalloonClick := TrayClick;
  {$ENDIF}
end;

destructor TBFNotifier.Destroy;
begin
  if FTray <> nil then
    FTray.Visible := False;
  inherited Destroy;
end;

procedure TBFNotifier.Show(const Title, Body: string);
begin
  FTray.Hint := Title;
  FTray.BalloonTitle := Title;
  FTray.BalloonHint := Body;
  FTray.Visible := True;
  FTray.ShowBalloonHint;
end;

procedure TBFNotifier.Hide;
begin
  FTray.Visible := False;
end;

procedure TBFNotifier.TrayClick(Sender: TObject);
begin
  Hide;
  if Assigned(FOnClick) then
    FOnClick(Self);
end;

{$ELSE}

{ Delphi 7: NOTIFYICONDATA com balão (Shell32 5.0+, Windows 2000+), ANSI. }
type
  TNotifyIconDataV2 = record
    cbSize: DWORD;
    Wnd: HWND;
    uID: UINT;
    uFlags: UINT;
    uCallbackMessage: UINT;
    hIcon: HICON;
    szTip: array[0..127] of AnsiChar;
    dwState: DWORD;
    dwStateMask: DWORD;
    szInfo: array[0..255] of AnsiChar;
    uTimeout: UINT;
    szInfoTitle: array[0..63] of AnsiChar;
    dwInfoFlags: DWORD;
  end;

const
  NIF_INFO_ = $10;
  NIIF_INFO_ = $1;
  NIN_BALLOONUSERCLICK_ = WM_USER + 5;
  WM_BFOCUS_TRAY = WM_USER + 377;

function Shell_NotifyIconA_(dwMessage: DWORD; lpData: Pointer): BOOL; stdcall;
  external 'shell32.dll' name 'Shell_NotifyIconA';

procedure CopyTo(const S: string; Dest: PAnsiChar; Max: Integer);
var
  A: AnsiString;
begin
  A := AnsiString(Copy(S, 1, Max - 1));
  FillChar(Dest^, Max, 0);
  if A <> '' then
    Move(PAnsiChar(A)^, Dest^, Length(A));
end;

constructor TBFNotifier.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FWnd := Classes.AllocateHWnd(WndProc);
end;

destructor TBFNotifier.Destroy;
begin
  RemoveIcon;
  Classes.DeallocateHWnd(FWnd);
  inherited Destroy;
end;

procedure TBFNotifier.RemoveIcon;
var
  D: TNotifyIconDataV2;
begin
  if not FAdded then
    Exit;
  FillChar(D, SizeOf(D), 0);
  D.cbSize := SizeOf(D);
  D.Wnd := FWnd;
  D.uID := 1;
  Shell_NotifyIconA_(NIM_DELETE, @D);
  FAdded := False;
end;

procedure TBFNotifier.Show(const Title, Body: string);
var
  D: TNotifyIconDataV2;
begin
  FillChar(D, SizeOf(D), 0);
  D.cbSize := SizeOf(D);
  D.Wnd := FWnd;
  D.uID := 1;
  D.uFlags := NIF_ICON or NIF_TIP or NIF_MESSAGE or NIF_INFO_;
  D.uCallbackMessage := WM_BFOCUS_TRAY;
  D.hIcon := Application.Icon.Handle;
  CopyTo(Title, D.szTip, SizeOf(D.szTip));
  CopyTo(Body, D.szInfo, SizeOf(D.szInfo));
  CopyTo(Title, D.szInfoTitle, SizeOf(D.szInfoTitle));
  D.uTimeout := 10000;
  D.dwInfoFlags := NIIF_INFO_;
  if FAdded then
    Shell_NotifyIconA_(NIM_MODIFY, @D)
  else
    FAdded := Shell_NotifyIconA_(NIM_ADD, @D);
end;

procedure TBFNotifier.Hide;
begin
  RemoveIcon;
end;

procedure TBFNotifier.WndProc(var Msg: TMessage);
begin
  if Msg.Msg = WM_BFOCUS_TRAY then
  begin
    if (Msg.LParam = NIN_BALLOONUSERCLICK_) or (Msg.LParam = WM_LBUTTONUP) then
      TrayClick(Self);
    Msg.Result := 0;
  end
  else
    Msg.Result := DefWindowProc(FWnd, Msg.Msg, Msg.WParam, Msg.LParam);
end;

procedure TBFNotifier.TrayClick(Sender: TObject);
begin
  Hide;
  if Assigned(FOnClick) then
    FOnClick(Self);
end;

{$ENDIF}

end.
