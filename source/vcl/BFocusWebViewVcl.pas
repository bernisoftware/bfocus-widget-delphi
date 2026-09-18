unit BFocusWebViewVcl;

{ Janela com TEdgeBrowser (WebView2) que mostra embed.html / release-notes.html da CDN
  (Delphi 10.4+, VCL). Implementa o lado nativo do Host Protocol v1:
  - embed → host: chrome.webview.postMessage → OnWebMessageReceived, aceito só da origem
    do embedBaseUrl (args.Source) e só com tipos conhecidos;
  - host → embed: ExecuteScript("window.bFocusEmbed && window.bFocusEmbed.receive(...)");
  - navegação para outra origem é cancelada e aberta no navegador do sistema;
  - "carregando" até o bfocus:ready; falha de rede = tela "sem conexão" com nova tentativa;
  - banner: tela cheia que não fecha por Esc, Alt+F4 nem pelo X.
  Precisa do WebView2Loader.dll ao lado do .exe (vem com o RAD Studio: redist). }

{$I BFocusDefines.inc}

interface

uses
  Winapi.Windows, Winapi.Messages, Winapi.ShellAPI, Winapi.ActiveX, Winapi.WebView2,
  System.SysUtils, System.Classes, Vcl.Controls, Vcl.Forms, Vcl.StdCtrls, Vcl.ExtCtrls,
  Vcl.Graphics, Vcl.Edge, BFocusText, BFocusJson, BFocusConfig, BFocusModels, BFocusI18n;

type
  TBFWebKind = (wkTickets, wkBanner, wkHistory);
  TBFEmbedMessageEvent = procedure(Sender: TObject; const MsgType: string; Msg: TBFJson) of object;

  TBFocusWebViewForm = class(TForm)
  private
    FEdge: TEdgeBrowser;
    FOverlay: TPanel;
    FOverlayLabel: TLabel;
    FRetry: TButton;
    FKind: TBFWebKind;
    FLocale: string;
    FUrl: string;
    FOrigin: string;
    FCreated: Boolean;
    FUnavailable: Boolean;
    FReady: Boolean;
    FLocked: Boolean;
    FAllowClose: Boolean;
    FPending: TStringList;
    FOnMessage: TBFEmbedMessageEvent;
    FOnUnavailable: TNotifyEvent;
    FOnUserClose: TNotifyEvent;
    FOnReady: TNotifyEvent;
    procedure EdgeCreated(Sender: TCustomEdgeBrowser; AResult: HResult);
    procedure EdgeNavStarting(Sender: TCustomEdgeBrowser; Args: TNavigationStartingEventArgs);
    procedure EdgeNavCompleted(Sender: TCustomEdgeBrowser; IsSuccess: Boolean;
      WebErrorStatus: COREWEBVIEW2_WEB_ERROR_STATUS);
    procedure EdgeMessage(Sender: TCustomEdgeBrowser; Args: TWebMessageReceivedEventArgs);
    procedure EdgeNewWindow(Sender: TCustomEdgeBrowser; Args: TNewWindowRequestedEventArgs);
    procedure RetryClick(Sender: TObject);
    procedure FormCloseQueryHandler(Sender: TObject; var CanClose: Boolean);
    procedure FormKeyDownHandler(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure ShowOverlay(const Text: string; WithRetry: Boolean);
    procedure HideOverlay;
    procedure RunScript(const Script: string);
  public
    constructor CreateFor(AOwner: TComponent; AKind: TBFWebKind; const ALocale, EmbedOrigin: string);
    destructor Destroy; override;
    procedure Load(const Url: string);
    procedure Reload;
    { Host → embed (mensagem JSON em UTF-8). }
    procedure PostToEmbed(const MessageJson: TBFRaw);
    { logout: apaga o localStorage da origem do embed (estado de "lido"). }
    procedure ClearOriginData;
    procedure ForceClose;
    property Ready: Boolean read FReady;
    property Unavailable: Boolean read FUnavailable;
    property Kind: TBFWebKind read FKind;
    property Locked: Boolean read FLocked write FLocked;
    property OnEmbedMessage: TBFEmbedMessageEvent read FOnMessage write FOnMessage;
    property OnUnavailable: TNotifyEvent read FOnUnavailable write FOnUnavailable;
    property OnUserClose: TNotifyEvent read FOnUserClose write FOnUserClose;
    property OnReady: TNotifyEvent read FOnReady write FOnReady;
  end;

{ Runtime do WebView2 instalado e WebView2Loader.dll acessível. }
function BFWebView2Available: Boolean;
procedure BFOpenInBrowser(const Url: string);
function BFWebViewDataFolder: string;

implementation

type
  TGetVersion = function(browserExecutableFolder: PWideChar;
    out versionInfo: PWideChar): HResult; stdcall;

function BFWebView2Available: Boolean;
var
  Lib: HMODULE;
  GetVersion: TGetVersion;
  Version: PWideChar;
begin
  Result := False;
  Lib := LoadLibrary('WebView2Loader.dll');
  if Lib = 0 then
    Exit;
  try
    @GetVersion := GetProcAddress(Lib, 'GetAvailableCoreWebView2BrowserVersionString');
    if not Assigned(GetVersion) then
      Exit;
    Version := nil;
    if Succeeded(GetVersion(nil, Version)) and (Version <> nil) then
    begin
      Result := Version^ <> #0;
      CoTaskMemFree(Version);
    end;
  finally
    FreeLibrary(Lib);
  end;
end;

procedure BFOpenInBrowser(const Url: string);
var
  Scheme: string;
begin
  // Só esquemas seguros: nada de file:, javascript: etc.
  Scheme := BFUrlScheme(Url);
  if (Scheme = 'https') or (Scheme = 'http') or BFStartsText(Url, 'mailto:') or
    BFStartsText(Url, 'tel:') then
    ShellExecute(0, 'open', PChar(Url), nil, nil, SW_SHOWNORMAL);
end;

function BFWebViewDataFolder: string;
begin
  // Pasta gravável por usuário (a padrão, ao lado do .exe, falha em Program Files).
  Result := GetEnvironmentVariable('LOCALAPPDATA');
  if Result = '' then
    Result := ExtractFilePath(ParamStr(0));
  Result := IncludeTrailingPathDelimiter(Result) + 'bFocus\WebView2';
end;

function TakeWide(P: PWideChar): string;
begin
  if P = nil then
    Result := ''
  else
  begin
    Result := P;
    CoTaskMemFree(P);
  end;
end;

{ ── TBFocusWebViewForm ─────────────────────────────────────────────────── }

constructor TBFocusWebViewForm.CreateFor(AOwner: TComponent; AKind: TBFWebKind;
  const ALocale, EmbedOrigin: string);
begin
  inherited CreateNew(AOwner);
  FKind := AKind;
  FLocale := ALocale;
  FOrigin := EmbedOrigin;
  FPending := TStringList.Create;
  KeyPreview := True;
  OnCloseQuery := FormCloseQueryHandler;
  OnKeyDown := FormKeyDownHandler;
  Color := clWhite;
  case AKind of
    wkBanner:
      begin
        // Modal em tela cheia: sem borda, sem X, acima das outras janelas.
        BorderStyle := bsNone;
        FormStyle := fsStayOnTop;
        WindowState := wsMaximized;
        FLocked := True;
      end;
    wkHistory:
      begin
        BorderStyle := bsSizeToolWin;
        Caption := BFRN(ALocale, 'historyTitle');
      end;
  else
    BorderStyle := bsSizeToolWin;
    Caption := BFT(ALocale, 'header_title');
  end;

  FEdge := TEdgeBrowser.Create(Self);
  FEdge.Parent := Self;
  FEdge.Align := alClient;
  FEdge.UserDataFolder := BFWebViewDataFolder;
  FEdge.OnCreateWebViewCompleted := EdgeCreated;
  FEdge.OnNavigationStarting := EdgeNavStarting;
  FEdge.OnNavigationCompleted := EdgeNavCompleted;
  FEdge.OnWebMessageReceived := EdgeMessage;
  FEdge.OnNewWindowRequested := EdgeNewWindow;

  FOverlay := TPanel.Create(Self);
  FOverlay.Parent := Self;
  FOverlay.Align := alClient;
  FOverlay.BevelOuter := bvNone;
  FOverlay.Color := clWhite;
  FOverlay.ParentBackground := False;
  FOverlayLabel := TLabel.Create(Self);
  FOverlayLabel.Parent := FOverlay;
  FOverlayLabel.Align := alClient;
  FOverlayLabel.Alignment := taCenter;
  FOverlayLabel.Layout := tlCenter;
  FOverlayLabel.WordWrap := True;
  FOverlayLabel.Font.Color := $008B7464; // #64748b
  FRetry := TButton.Create(Self);
  FRetry.Parent := FOverlay;
  FRetry.Align := alBottom;
  FRetry.Height := 36;
  FRetry.Caption := BFT(ALocale, 'btn_retry');
  FRetry.OnClick := RetryClick;
  FRetry.Visible := False;
  ShowOverlay(BFT(ALocale, 'loading'), False);
end;

destructor TBFocusWebViewForm.Destroy;
begin
  FPending.Free;
  inherited Destroy;
end;

procedure TBFocusWebViewForm.ShowOverlay(const Text: string; WithRetry: Boolean);
begin
  FOverlayLabel.Caption := Text;
  FRetry.Visible := WithRetry;
  FOverlay.Visible := True;
  FOverlay.BringToFront;
end;

procedure TBFocusWebViewForm.HideOverlay;
begin
  FOverlay.Visible := False;
end;

procedure TBFocusWebViewForm.Load(const Url: string);
begin
  FUrl := Url;
  FReady := False;
  ShowOverlay(BFT(FLocale, 'loading'), False);
  FEdge.Navigate(Url);
end;

procedure TBFocusWebViewForm.Reload;
begin
  if FUrl <> '' then
    Load(FUrl);
end;

procedure TBFocusWebViewForm.RetryClick(Sender: TObject);
begin
  Reload;
end;

procedure TBFocusWebViewForm.EdgeCreated(Sender: TCustomEdgeBrowser; AResult: HResult);
var
  I: Integer;
begin
  if Failed(AResult) then
  begin
    // Sem runtime do WebView2 (ou sem o loader): o componente cai para UI nativa/navegador.
    FUnavailable := True;
    if Assigned(FOnUnavailable) then
      FOnUnavailable(Self);
    Exit;
  end;
  FCreated := True;
  for I := 0 to FPending.Count - 1 do
    FEdge.ExecuteScript(FPending[I]);
  FPending.Clear;
end;

procedure TBFocusWebViewForm.EdgeNavStarting(Sender: TCustomEdgeBrowser;
  Args: TNavigationStartingEventArgs);
var
  P: PWideChar;
  Uri: string;
begin
  P := nil;
  Args.ArgsInterface.Get_uri(P);
  Uri := TakeWide(P);
  if BFStartsText(Uri, 'about:') or (BFOriginOf(Uri) = FOrigin) then
    Exit;
  // A WebView só navega dentro da origem do embed; o resto abre fora.
  Args.ArgsInterface.Set_Cancel(1);
  BFOpenInBrowser(Uri);
end;

procedure TBFocusWebViewForm.EdgeNavCompleted(Sender: TCustomEdgeBrowser; IsSuccess: Boolean;
  WebErrorStatus: COREWEBVIEW2_WEB_ERROR_STATUS);
begin
  if not IsSuccess then
    ShowOverlay(BFT(FLocale, 'error_load'), True);
end;

procedure TBFocusWebViewForm.EdgeNewWindow(Sender: TCustomEdgeBrowser;
  Args: TNewWindowRequestedEventArgs);
var
  P: PWideChar;
begin
  P := nil;
  Args.ArgsInterface.Get_uri(P);
  Args.ArgsInterface.Set_Handled(1);
  BFOpenInBrowser(TakeWide(P));
end;

procedure TBFocusWebViewForm.EdgeMessage(Sender: TCustomEdgeBrowser;
  Args: TWebMessageReceivedEventArgs);
var
  P: PWideChar;
  Source, Raw, MsgType: string;
  Msg: TBFJson;
begin
  P := nil;
  Args.ArgsInterface.Get_Source(P);
  Source := TakeWide(P);
  // Segurança da ponte: só a origem do embedBaseUrl.
  if BFOriginOf(Source) <> FOrigin then
    Exit;
  P := nil;
  if Failed(Args.ArgsInterface.TryGetWebMessageAsString(P)) then
    Exit;
  Raw := TakeWide(P);
  Msg := BFParseHostMessage(BFToUtf8(Raw), MsgType);
  if Msg = nil then
    Exit; // inválida ou tipo desconhecido: ignora
  try
    if MsgType = 'bfocus:ready' then
    begin
      FReady := Msg.Path('payload.hp').AsInt64(1) = BF_HOST_PROTOCOL;
      HideOverlay;
      if Assigned(FOnReady) then
        FOnReady(Self);
    end;
    if Assigned(FOnMessage) then
      FOnMessage(Self, MsgType, Msg);
  finally
    Msg.Free;
  end;
end;

procedure TBFocusWebViewForm.RunScript(const Script: string);
begin
  if FCreated then
    FEdge.ExecuteScript(Script)
  else
    FPending.Add(Script);
end;

procedure TBFocusWebViewForm.PostToEmbed(const MessageJson: TBFRaw);
begin
  RunScript(BFReceiveScript(MessageJson));
end;

procedure TBFocusWebViewForm.ClearOriginData;
begin
  RunScript('try{localStorage.clear();sessionStorage.clear()}catch(e){}');
end;

procedure TBFocusWebViewForm.ForceClose;
begin
  FAllowClose := True;
  Hide;
end;

procedure TBFocusWebViewForm.FormCloseQueryHandler(Sender: TObject; var CanClose: Boolean);
begin
  if FAllowClose then
  begin
    CanClose := True;
    Exit;
  end;
  // Fechar só esconde: a WebView fica para reabrir rápido. O banner nunca fecha sozinho.
  CanClose := False;
  if FLocked then
    Exit;
  Hide;
  if Assigned(FOnUserClose) then
    FOnUserClose(Self);
end;

procedure TBFocusWebViewForm.FormKeyDownHandler(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  if FLocked and ((Key = VK_ESCAPE) or ((Key = VK_F4) and (ssAlt in Shift))) then
    Key := 0;
end;

end.
