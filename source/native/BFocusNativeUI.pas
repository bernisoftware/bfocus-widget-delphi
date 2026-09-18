unit BFocusNativeUI;

{ Controlador da UI nativa (o App.tsx do embed, em VCL/LCL): janela de 400 x 620 com o
  cabeçalho da marca, carregamento (/config → /session → conversa ativa), telas de erro
  (error_load com detalhe, error_identity), navegação entre lista/novo/detalhe/chat,
  tempo real do chat em modo poll (vive aqui para seguir enquanto se navega), banner e
  histórico de release notes. Usado por TBFocusNativeWidget (Delphi 7+/Lazarus) e como
  reserva do TBFocusWidget (10.4+) sem WebView2. }

{$I BFocusDefines.inc}

interface

uses
  SysUtils, Classes, Controls, Forms, Graphics, ExtCtrls, StdCtrls,
{$IFNDEF BF_FPC}
  Windows, Messages, ShellAPI,
{$ENDIF}
  BFocusText, BFocusJson, BFocusConfig, BFocusApi, BFocusAsync, BFocusVMChat,
  BFocusWidgetBase, BFocusUIControls, BFocusUIContext, BFocusUITickets, BFocusUIChat,
  BFocusUIReleaseNotes, BFocusGraphics, BFocusFormat;

type
  TBFocusNativeUI = class;

  { Cabeçalho: fundo primary_color, logo (ou a inicial num quadrado translúcido),
    header_title, nome do tenant, nome do cliente e ✕. }
  TBFAppHeader = class(TCustomControl)
  private
    FCtx: TBFUIContext;
    FClose: TBFButton;
    FLogo: TPicture;
  protected
    procedure Paint; override;
    procedure Resize; override;
  public
    constructor CreateHeader(AOwner: TComponent; ACtx: TBFUIContext; OnClose: TNotifyEvent);
    destructor Destroy; override;
    procedure Refresh_;
    property Logo: TPicture read FLogo;
  end;

  TBFocusNativeForm = class(TForm)
  private
    FUI: TBFocusNativeUI;
    FHeader: TBFAppHeader;
    FHost: TPanel;
    FMsgPanel: TPanel;
    FMessage: TBFText;
    FDetail: TBFText;
    procedure CloseQueryHandler(Sender: TObject; var CanClose: Boolean);
    procedure HeaderClose(Sender: TObject);
    procedure ResizeHandler(Sender: TObject);
    procedure ActivateHandler(Sender: TObject);
{$IFDEF BF_FPC}
    procedure DropFilesHandler(Sender: TObject; const FileNames: array of string);
{$ELSE}
    procedure WMDropFiles(var Msg: TMessage); message WM_DROPFILES;
  protected
    procedure CreateWnd; override;
{$ENDIF}
  public
    constructor CreateFor(AOwner: TComponent; AUI: TBFocusNativeUI);
    procedure ShowMessageScreen(const Text, Detail: string);
    procedure HideMessageScreen;
    property Host: TPanel read FHost;
    property Header: TBFAppHeader read FHeader;
  end;

  TBFUIState = (usIdle, usLoading, usReady, usConfigError, usIdentityError);

  TBFocusNativeUI = class(TBFUIContext)
  private
    FForm: TBFocusNativeForm;
    FPage: TBFPage;
    FTrash: TList;
    FFreeTimer: TTimer;
    FBanner: TBFBannerForm;
    FHistory: TBFHistoryForm;
    FState: TBFUIState;
    FPendingView: TBFOpenView;
    FPendingId: string;
    FAutoRouted: Boolean;
    FSessionTimer: TTimer;
    FStreamTimer: TTimer;
    FStreamAction: Integer; // 1 = pedir ticket, 2 = poll
    FQueueTimer: TTimer;
    FPanelWidth, FPanelHeight: Integer;
    procedure EnsureForm;
    procedure SetPage(P: TBFPage);
    procedure FreeTick(Sender: TObject);
    procedure StartLoad;
    procedure Ready;
    procedure Route(View: TBFOpenView; const Id: string);
    procedure NotifyChat;
    procedure ChatStreamSync;
    procedure RequestTicket;
    procedure SchedulePoll(Action, Delay: Integer);
    procedure StreamTick(Sender: TObject);
    procedure LoadSnapshot;
    procedure SessionTick(Sender: TObject);
    procedure QueueTick(Sender: TObject);
    function ConfigWork(Job: TBFJob): TBFJson;
    procedure ConfigDone(Job: TBFJob);
    function SessionWork(Job: TBFJob): TBFJson;
    procedure SessionDone(Job: TBFJob);
    procedure SessionRefreshDone(Job: TBFJob);
    function ActiveWork(Job: TBFJob): TBFJson;
    procedure ActiveDone(Job: TBFJob);
    function LogoWork(Job: TBFJob): TBFJson;
    procedure LogoDone(Job: TBFJob);
    function TicketWork(Job: TBFJob): TBFJson;
    procedure TicketDone(Job: TBFJob);
    function PollWork(Job: TBFJob): TBFJson;
    procedure PollDone(Job: TBFJob);
    function SnapshotWork(Job: TBFJob): TBFJson;
    procedure SnapshotDone(Job: TBFJob);
    function CreateWork(Job: TBFJob): TBFJson;
    procedure CreateDone(Job: TBFJob);
    function SendWork(Job: TBFJob): TBFJson;
    procedure SendDone(Job: TBFJob);
    function CloseWork(Job: TBFJob): TBFJson;
    procedure CloseDone(Job: TBFJob);
    function HandoffWork(Job: TBFJob): TBFJson;
    procedure HandoffDone(Job: TBFJob);
    function AvailWork(Job: TBFJob): TBFJson;
    procedure AvailDone(Job: TBFJob);
    procedure PostSend(const TempId, Html: string; Attachments: TBFJson);
    function ChatPage: TBFChatPage;
    procedure FormActivated;
  public
    constructor CreateFor(AOwner: TComponent; AWidget: TBFocusWidgetBase);
    destructor Destroy; override;
    procedure ShowWidget(View: TBFOpenView; const Id: string);
    procedure HideWidget;
    procedure OpenBanner(Ids: TStrings);
    procedure OpenHistory;
    procedure ResetUI;
    procedure ApiChanged;
    procedure FilesDropped(Files: TStrings);

    procedure GoList; override;
    procedure GoNew(const PrefillHtml: string; Attachments: TBFJson; const Notice: string); override;
    procedure GoDetail(const TicketId: string); override;
    procedure GoChat(const ContinueTicketId, TicketNumber: string); override;
    procedure CloseWidget; override;
    procedure IdentityRejected(const Code: string); override;
    procedure ChatStart(const Html: string; Attachments: TBFJson; const ContinueTicketId: string); override;
    procedure ChatSend(const Html: string; Attachments: TBFJson); override;
    procedure ChatRetry(const TempId: string); override;
    procedure ChatDiscard(const TempId: string); override;
    procedure ChatCloseConversation; override;
    procedure ChatHandoff; override;
    procedure ChatReset; override;
    procedure RefreshAvailability; override;
    function ViewingChat: Boolean; override;

    property PanelWidth: Integer read FPanelWidth write FPanelWidth;
    property PanelHeight: Integer read FPanelHeight write FPanelHeight;
  end;

implementation

uses
  BFocusVMTickets;

{ ── TBFAppHeader ───────────────────────────────────────────────────────── }

constructor TBFAppHeader.CreateHeader(AOwner: TComponent; ACtx: TBFUIContext; OnClose: TNotifyEvent);
begin
  inherited Create(AOwner);
  FCtx := ACtx;
  FLogo := TPicture.Create;
  Height := 64;
  FClose := TBFButton.Create(Self);
  FClose.Parent := Self;
  FClose.Kind := bkHeader;
  FClose.ButtonHeight := 32;
  FClose.Caption := BFGlyph(#$E2#$9C#$95, 'X');
  FClose.Hint := ACtx.T('btn_close');
  FClose.ShowHint := True;
  FClose.OnClick := OnClose;
end;

destructor TBFAppHeader.Destroy;
begin
  FLogo.Free;
  inherited Destroy;
end;

procedure TBFAppHeader.Refresh_;
begin
  FClose.Accent := FCtx.Primary;
  if FCtx.CustomerName <> '' then Height := 72 else Height := 60;
  Resize;
  Invalidate;
  FClose.Invalidate;
end;

procedure TBFAppHeader.Resize;
begin
  inherited Resize;
  FClose.SetBounds(Width - 48, (Height - 32) div 2, 32, 32);
end;

procedure TBFAppHeader.Paint;
var
  Primary: TColor;
  Name, Initial: string;
  Y: Integer;
begin
  Primary := FCtx.Primary;
  with Canvas do
  begin
    Brush.Color := Primary;
    FillRect(Rect(0, 0, Width, Height));
    Y := (Height - 28) div 2;
    if (FLogo.Graphic <> nil) and (FLogo.Width > 0) then
    begin
      Brush.Color := clWhite;
      Pen.Color := clWhite;
      RoundRect(16, Y, 44, Y + 28, 6, 6);
      StretchDraw(Rect(16, Y, 44, Y + 28), FLogo.Graphic);
    end
    else
    begin
      Brush.Color := BFMix(clWhite, Primary, 0.18);
      Pen.Color := Brush.Color;
      RoundRect(16, Y, 44, Y + 28, 6, 6);
      Name := FCtx.TenantName;
      if Name <> '' then Initial := AnsiUpperCase(Copy(Name, 1, 1)) else Initial := '';
      BFStyleFont(Font, 10, True, clWhite);
      BFDrawTextIn(Canvas, Initial, Rect(16, Y + 5, 44, Y + 28), taCenter, False);
    end;
    BFStyleFont(Font, 8, False, BFMix(clWhite, Primary, 0.8));
    BFDrawTextIn(Canvas, FCtx.T('header_title'), Rect(56, 10, Width - 56, 26), taLeftJustify, False);
    BFStyleFont(Font, 10, True, clWhite);
    BFDrawTextIn(Canvas, FCtx.TenantName, Rect(56, 26, Width - 56, 46), taLeftJustify, False);
    if FCtx.CustomerName <> '' then
    begin
      BFStyleFont(Font, 7, False, BFMix(clWhite, Primary, 0.75));
      BFDrawTextIn(Canvas, FCtx.CustomerName, Rect(56, 47, Width - 56, 62), taLeftJustify, False);
    end;
  end;
end;

{ ── TBFocusNativeForm ──────────────────────────────────────────────────── }

constructor TBFocusNativeForm.CreateFor(AOwner: TComponent; AUI: TBFocusNativeUI);
begin
  inherited CreateNew(AOwner, 0);
  FUI := AUI;
  BorderStyle := bsSizeToolWin;
  Caption := AUI.T('header_title');
  Color := BFClSurface;
  OnCloseQuery := CloseQueryHandler;
  OnResize := ResizeHandler;
  OnActivate := ActivateHandler;
  FHeader := TBFAppHeader.CreateHeader(Self, AUI, HeaderClose);
  FHeader.Parent := Self;
  FHeader.Align := alTop;
  FHost := TPanel.Create(Self);
  FHost.Parent := Self;
  FHost.Align := alClient;
  FHost.BevelOuter := bvNone;
  FHost.Caption := '';
  FHost.Color := BFClSurface;
  FMsgPanel := TPanel.Create(Self);
  FMsgPanel.Parent := Self;
  FMsgPanel.Align := alClient;
  FMsgPanel.BevelOuter := bvNone;
  FMsgPanel.Caption := '';
  FMsgPanel.Color := clWhite;
  FMsgPanel.Visible := False;
  FMessage := TBFText.Create(Self);
  FMessage.Parent := FMsgPanel;
  FMessage.Style(10, False, BFClText);
  FMessage.Alignment := taCenter;
  FDetail := TBFText.Create(Self);
  FDetail.Parent := FMsgPanel;
  FDetail.Style(8, False, BFColor('#888888', clGray));
  FDetail.Alignment := taCenter;
{$IFDEF BF_FPC}
  AllowDropFiles := True;
  OnDropFiles := DropFilesHandler;
{$ENDIF}
end;

{$IFNDEF BF_FPC}
procedure TBFocusNativeForm.CreateWnd;
begin
  inherited CreateWnd;
  // Arrastar e soltar arquivos (anexos) direto na janela.
  DragAcceptFiles(Handle, True);
end;

procedure TBFocusNativeForm.WMDropFiles(var Msg: TMessage);
var
  Drop: THandle;
  I, N: Integer;
  Buf: array[0..1023] of Char;
  Files: TStringList;
begin
  Drop := THandle(Msg.WParam);
  Files := TStringList.Create;
  try
    N := DragQueryFile(Drop, $FFFFFFFF, nil, 0);
    for I := 0 to N - 1 do
    begin
      DragQueryFile(Drop, I, Buf, Length(Buf));
      Files.Add(Buf);
    end;
    DragFinish(Drop);
    FUI.FilesDropped(Files);
  finally
    Files.Free;
  end;
  Msg.Result := 0;
end;
{$ELSE}
procedure TBFocusNativeForm.DropFilesHandler(Sender: TObject; const FileNames: array of string);
var
  Files: TStringList;
  I: Integer;
begin
  Files := TStringList.Create;
  try
    for I := 0 to High(FileNames) do
      Files.Add(FileNames[I]);
    FUI.FilesDropped(Files);
  finally
    Files.Free;
  end;
end;
{$ENDIF}

procedure TBFocusNativeForm.ResizeHandler(Sender: TObject);
var
  H, Y: Integer;
begin
  if not FMsgPanel.Visible then
    Exit;
  H := FMessage.MeasureHeight(FMsgPanel.ClientWidth - 48);
  Y := (FMsgPanel.ClientHeight - H) div 2 - 20;
  if Y < 16 then Y := 16;
  FMessage.SetBounds(24, Y, FMsgPanel.ClientWidth - 48, H);
  FDetail.SetBounds(24, Y + H + 8, FMsgPanel.ClientWidth - 48,
    FDetail.MeasureHeight(FMsgPanel.ClientWidth - 48));
end;

procedure TBFocusNativeForm.ShowMessageScreen(const Text, Detail: string);
begin
  FMessage.Text := Text;
  FDetail.Text := Detail;
  FDetail.Visible := Detail <> '';
  FMsgPanel.Visible := True;
  FMsgPanel.BringToFront;
  ResizeHandler(nil);
end;

procedure TBFocusNativeForm.HideMessageScreen;
begin
  FMsgPanel.Visible := False;
end;

procedure TBFocusNativeForm.HeaderClose(Sender: TObject);
begin
  FUI.CloseWidget;
end;

procedure TBFocusNativeForm.CloseQueryHandler(Sender: TObject; var CanClose: Boolean);
begin
  // Fechar só esconde: a tela é preservada para reabrir rápido.
  CanClose := False;
  FUI.CloseWidget;
end;

procedure TBFocusNativeForm.ActivateHandler(Sender: TObject);
begin
  FUI.FormActivated;
end;

{ ── TBFocusNativeUI ────────────────────────────────────────────────────── }

function MakeTimer(AOwner: TComponent; Interval: Integer; OnTimer: TNotifyEvent): TTimer;
begin
  Result := TTimer.Create(AOwner);
  Result.Enabled := False;
  Result.Interval := Interval;
  Result.OnTimer := OnTimer;
end;

constructor TBFocusNativeUI.CreateFor(AOwner: TComponent; AWidget: TBFocusWidgetBase);
begin
  inherited CreateContext(AOwner, AWidget);
  FTrash := TList.Create;
  FFreeTimer := MakeTimer(Self, 1, FreeTick);
  FSessionTimer := MakeTimer(Self, 30000, SessionTick);
  FStreamTimer := MakeTimer(Self, 5000, StreamTick);
  FQueueTimer := MakeTimer(Self, BF_CHAT_QUEUE_REFRESH_MS, QueueTick);
  FPanelWidth := 400;
  FPanelHeight := 620;
end;

destructor TBFocusNativeUI.Destroy;
begin
  BFJobs.CancelOwner(Self);
  FreeTick(nil);
  FTrash.Free;
  inherited Destroy;
end;

procedure TBFocusNativeUI.EnsureForm;
var
  WA: TRect;
begin
  if FForm <> nil then
    Exit;
  FForm := TBFocusNativeForm.CreateFor(Self, Self);
  // Painel de 400 x 620 no canto inferior direito (como o launcher web).
  WA := Screen.WorkAreaRect;
  FForm.Width := FPanelWidth;
  FForm.Height := FPanelHeight;
  if FForm.Height > WA.Bottom - WA.Top - 24 then
    FForm.Height := WA.Bottom - WA.Top - 24;
  FForm.Left := WA.Right - FForm.Width - 24;
  FForm.Top := WA.Bottom - FForm.Height - 24;
end;

procedure TBFocusNativeUI.FreeTick(Sender: TObject);
var
  I: Integer;
begin
  FFreeTimer.Enabled := False;
  for I := 0 to FTrash.Count - 1 do
    TObject(FTrash[I]).Free;
  FTrash.Clear;
end;

procedure TBFocusNativeUI.SetPage(P: TBFPage);
begin
  if FPage <> nil then
  begin
    // A tela antiga pode estar no meio de um clique: some agora, é liberada depois.
    FPage.Deactivate;
    BFJobs.CancelOwner(FPage);
    FPage.Visible := False;
    FTrash.Add(FPage);
    FFreeTimer.Enabled := True;
  end;
  FPage := P;
  if P <> nil then
  begin
    P.Parent := FForm.Host;
    P.Align := alClient;
    P.Visible := True;
    P.Activate;
  end;
end;

procedure TBFocusNativeUI.ShowWidget(View: TBFOpenView; const Id: string);
begin
  EnsureForm;
  FVisible := True;
  FForm.Show;
  FWidget.WidgetShown;
  case FState of
    usIdle:
      begin
        FPendingView := View;
        FPendingId := Id;
        StartLoad;
      end;
    usLoading:
      begin
        FPendingView := View;
        FPendingId := Id;
      end;
    usReady:
      begin
        if (View <> ovList) or (FPage = nil) then
          Route(View, Id)
        else
          FPage.VisibilityChanged(True);
        FSessionTimer.Enabled := True;
        SessionTick(nil);
      end;
  end;
  FQueueTimer.Enabled := True;
  ChatStreamSync;
end;

procedure TBFocusNativeUI.HideWidget;
begin
  if not FVisible then
    Exit;
  FVisible := False;
  if FForm <> nil then
    FForm.Hide;
  if FPage <> nil then
    FPage.VisibilityChanged(False);
  FSessionTimer.Enabled := False;
  FQueueTimer.Enabled := False;
  // Widget escondido: o tempo real do chat desliga (§5.3).
  ChatStreamSync;
  FWidget.WidgetHidden;
end;

procedure TBFocusNativeUI.CloseWidget;
begin
  HideWidget;
end;

procedure TBFocusNativeUI.StartLoad;
begin
  FState := usLoading;
  FForm.Header.Refresh_;
  FForm.ShowMessageScreen(T('loading'), '');
  Run(ConfigWork, ConfigDone, Self, []);
end;

function TBFocusNativeUI.ConfigWork(Job: TBFJob): TBFJson;
begin
  Result := Job.Api.GetConfig;
end;

procedure TBFocusNativeUI.ConfigDone(Job: TBFJob);
var
  Logo: string;
begin
  if Job.Failed or (Job.Data = nil) then
  begin
    if CheckIdentity(Job) then
      Exit;
    // Config falhou (403 de origem, 401 de chave, widget desligado): error_load + detalhe.
    FState := usConfigError;
    SetPage(nil);
    FForm.ShowMessageScreen(T('error_load'), Job.ErrorMessage);
    FWidget.HostError('WIDGET_CONFIG_FAILED', Job.ErrorMessage);
    Exit;
  end;
  FWidgetConfig.Free;
  FWidgetConfig := Job.TakeData;
  FWidget.HostBranding(PrimaryHex);
  FForm.Header.Refresh_;
  Logo := '';
  if FWidgetConfig.ObjOf('tenant') <> nil then
    Logo := FWidgetConfig.ObjOf('tenant').StrOf('logo_url');
  if Logo <> '' then
    Run(LogoWork, LogoDone, Self, [Logo]);
  Run(SessionWork, SessionDone, Self, []);
end;

function TBFocusNativeUI.LogoWork(Job: TBFJob): TBFJson;
begin
  Job.Api.DownloadTo(Job.Arg(0), Job.Stream);
  Result := nil;
end;

procedure TBFocusNativeUI.LogoDone(Job: TBFJob);
begin
  if Job.Failed or (FForm = nil) then
    Exit;
  if BFLoadPicture(Job.Stream, '', FForm.Header.Logo) then
    FForm.Header.Invalidate;
end;

function TBFocusNativeUI.SessionWork(Job: TBFJob): TBFJson;
begin
  Result := Job.Api.Session;
end;

procedure TBFocusNativeUI.SessionDone(Job: TBFJob);
begin
  if Job.Failed then
  begin
    // Assinatura HMAC ausente/inválida: explica em vez de mostrar listas vazias.
    if CheckIdentity(Job) then
      Exit;
  end
  else if Job.Data <> nil then
    ReportSeen(Job.Data.StrOf('latest_event_at'));
  if ChatEnabled then
    Run(ActiveWork, ActiveDone, Self, [])
  else
    Ready;
end;

procedure TBFocusNativeUI.SessionTick(Sender: TObject);
begin
  if FVisible and (FState = usReady) then
    Run(SessionWork, SessionRefreshDone, Self, []);
end;

procedure TBFocusNativeUI.SessionRefreshDone(Job: TBFJob);
begin
  if Job.Failed then
    CheckIdentity(Job)
  else if Job.Data <> nil then
    ReportSeen(Job.Data.StrOf('latest_event_at'));
end;

function TBFocusNativeUI.ActiveWork(Job: TBFJob): TBFJson;
var
  C: TBFJson;
begin
  // Embrulha para distinguir "sem conversa" de erro.
  C := Job.Api.ChatActive;
  Result := TBFJson.NewObject;
  if C <> nil then
    Result.Put('conversation', C);
end;

procedure TBFocusNativeUI.ActiveDone(Job: TBFJob);
var
  E: Exception;
begin
  if Job.Failed then
  begin
    E := Job.MakeError;
    try
      FChat.ApplyActiveFailed(E);
    finally
      E.Free;
    end;
    if CheckIdentity(Job) then
      Exit;
  end
  else
    FChat.ApplyActive(Job.Data.ExtractKey('conversation'));
  Ready;
end;

procedure TBFocusNativeUI.Ready;
begin
  FState := usReady;
  FForm.HideMessageScreen;
  FSessionTimer.Enabled := FVisible;
  // Com uma conversa aberta, o widget já abre direto nela (uma vez).
  if not FAutoRouted and FChat.HasOpenConversation and (FPendingView = ovList) then
    GoChat('', '')
  else
    Route(FPendingView, FPendingId);
  FAutoRouted := True;
  ChatStreamSync;
end;

procedure TBFocusNativeUI.Route(View: TBFOpenView; const Id: string);
begin
  case View of
    ovTicket: GoDetail(Id);
    ovNew: GoNew('', nil, '');
    ovChat:
      if ChatEnabled then GoChat('', '') else GoList;
  else
    GoList;
  end;
end;

procedure TBFocusNativeUI.GoList;
begin
  SetPage(TBFListPage.CreatePage(FForm, Self));
end;

procedure TBFocusNativeUI.GoNew(const PrefillHtml: string; Attachments: TBFJson; const Notice: string);
begin
  SetPage(TBFNewTicketPage.CreateNewTicket(FForm, Self, PrefillHtml, Attachments, Notice));
end;

procedure TBFocusNativeUI.GoDetail(const TicketId: string);
begin
  SetPage(TBFDetailPage.CreateDetail(FForm, Self, TicketId));
end;

procedure TBFocusNativeUI.GoChat(const ContinueTicketId, TicketNumber: string);
begin
  // Chat pedido com o chat desligado: volta à lista.
  if not ChatEnabled then
  begin
    GoList;
    Exit;
  end;
  SetPage(TBFChatPage.CreateChat(FForm, Self, ContinueTicketId, TicketNumber));
  FChat.MarkSeen;
  ChatStreamSync;
end;

function TBFocusNativeUI.ViewingChat: Boolean;
begin
  Result := FPage is TBFChatPage;
end;

function TBFocusNativeUI.ChatPage: TBFChatPage;
begin
  if FPage is TBFChatPage then
    Result := TBFChatPage(FPage)
  else
    Result := nil;
end;

procedure TBFocusNativeUI.NotifyChat;
begin
  if FChat.IdentityError and (FState = usReady) then
  begin
    IdentityRejected('WIDGET_USER_HASH_INVALID');
    Exit;
  end;
  if ViewingChat and FVisible then
    FChat.MarkSeen;
  if FPage <> nil then
    FPage.ChatChanged;
end;

procedure TBFocusNativeUI.IdentityRejected(const Code: string);
begin
  // Com userHashProvider, tenta um hash novo uma vez e recarrega.
  if FWidget.HostIdentityRefresh then
  begin
    ResetUI;
    if FVisible then
    begin
      EnsureForm;
      StartLoad;
    end;
    Exit;
  end;
  FState := usIdentityError;
  FChat.StreamStop;
  FStreamTimer.Enabled := False;
  SetPage(nil);
  if FForm <> nil then
    FForm.ShowMessageScreen(T('error_identity'), '');
  FWidget.HostError(Code, '');
end;

{ ── tempo real (poll) ──────────────────────────────────────────────────── }

procedure TBFocusNativeUI.ChatStreamSync;
var
  Should: Boolean;
begin
  // Um stream por conversa, só com o widget visível e conversa aberta.
  Should := FVisible and (FState = usReady) and FChat.HasOpenConversation;
  if Should and not FChat.StreamRunning then
  begin
    FChat.StreamStart;
    RequestTicket;
  end
  else if not Should and FChat.StreamRunning then
  begin
    FChat.StreamStop;
    FStreamTimer.Enabled := False;
  end;
end;

procedure TBFocusNativeUI.RequestTicket;
begin
  Run(TicketWork, TicketDone, Self, [FChat.ConversationId, IntToStr(FChat.StreamGeneration)]);
end;

procedure TBFocusNativeUI.SchedulePoll(Action, Delay: Integer);
begin
  FStreamTimer.Enabled := False;
  if Delay < 0 then
    Exit;
  if Delay < 10 then
    Delay := 10;
  FStreamAction := Action;
  FStreamTimer.Interval := Delay;
  FStreamTimer.Enabled := True;
end;

procedure TBFocusNativeUI.StreamTick(Sender: TObject);
begin
  FStreamTimer.Enabled := False;
  if not FChat.StreamRunning then
    Exit;
  if FStreamAction = 1 then
    RequestTicket
  else
    Run(PollWork, PollDone, Self, [FChat.ConversationId, IntToStr(FChat.LastEventId),
      IntToStr(FChat.StreamGeneration)]);
end;

function TBFocusNativeUI.TicketWork(Job: TBFJob): TBFJson;
begin
  Result := Job.Api.ChatStreamTicket(Job.Arg(0));
end;

procedure TBFocusNativeUI.TicketDone(Job: TBFJob);
var
  E: Exception;
  Delay: Integer;
begin
  if IntToStr(FChat.StreamGeneration) <> Job.Arg(1) then
    Exit; // resposta de uma conexão antiga
  if Job.Failed then
  begin
    E := Job.MakeError;
    try
      Delay := FChat.StreamTicketFailed(E);
    finally
      E.Free;
    end;
    SchedulePoll(1, Delay);
    NotifyChat;
    Exit;
  end;
  // Modo poll sempre (Delphi 7/Lazarus sem SSE): o ticket só dá o last_event_id.
  SchedulePoll(2, FChat.StreamApplyTicket(Job.TakeData));
  NotifyChat;
end;

function TBFocusNativeUI.PollWork(Job: TBFJob): TBFJson;
begin
  Result := Job.Api.ChatEvents(Job.Arg(0), StrToInt64Def(Job.Arg(1), 0));
end;

procedure TBFocusNativeUI.PollDone(Job: TBFJob);
var
  E: Exception;
  Delay: Integer;
  Reconnected: Boolean;
begin
  if IntToStr(FChat.StreamGeneration) <> Job.Arg(2) then
    Exit;
  if Job.Failed then
  begin
    E := Job.MakeError;
    try
      Delay := FChat.StreamPollFailed(E);
    finally
      E.Free;
    end;
    SchedulePoll(2, Delay);
    NotifyChat;
    Exit;
  end;
  Delay := FChat.StreamApplyPoll(Job.TakeData, ViewingChat and FVisible, Reconnected);
  // A cada (re)conexão, recarrega a conversa inteira.
  if Reconnected then
    LoadSnapshot;
  if FChat.IsTerminal then
    ChatStreamSync
  else
    SchedulePoll(2, Delay);
  NotifyChat;
end;

procedure TBFocusNativeUI.LoadSnapshot;
begin
  if FChat.ConversationId <> '' then
    Run(SnapshotWork, SnapshotDone, Self, [FChat.ConversationId, IntToStr(BFNowUnixMs)]);
end;

function TBFocusNativeUI.SnapshotWork(Job: TBFJob): TBFJson;
begin
  Result := Job.Api.ChatGet(Job.Arg(0));
end;

procedure TBFocusNativeUI.SnapshotDone(Job: TBFJob);
var
  E: Exception;
begin
  if Job.Failed then
  begin
    E := Job.MakeError;
    try
      FChat.NoteError(E);
    finally
      E.Free;
    end;
    NotifyChat;
    Exit;
  end;
  FChat.ApplySnapshot(Job.Arg(0), Job.TakeData, StrToInt64Def(Job.Arg(1), 0));
  ChatStreamSync;
  NotifyChat;
end;

procedure TBFocusNativeUI.QueueTick(Sender: TObject);
begin
  // Rede de segurança para a posição na fila.
  if FVisible and FChat.NeedsQueueRefresh then
    LoadSnapshot;
end;

{ ── ações do chat ──────────────────────────────────────────────────────── }

procedure TBFocusNativeUI.ChatStart(const Html: string; Attachments: TBFJson;
  const ContinueTicketId: string);
var
  A: string;
begin
  if Attachments <> nil then A := Attachments.ToJsonString else A := '[]';
  Attachments.Free;
  Run(CreateWork, CreateDone, Self, [Html, A, ContinueTicketId]);
end;

function TBFocusNativeUI.CreateWork(Job: TBFJob): TBFJson;
begin
  Result := Job.Api.ChatCreate(Job.Arg(0), TBFJson.Parse(BFToUtf8(Job.Arg(1))), Job.Arg(2));
end;

procedure TBFocusNativeUI.CreateDone(Job: TBFJob);
var
  R: TBFStartResult;
begin
  if Job.Failed then
  begin
    if Job.ErrorCode = 'CHAT_OFFLINE' then
    begin
      R := srOffline;
      RefreshAvailability;
    end
    else
    begin
      R := srError;
      if CheckIdentity(Job) then
        Exit;
    end;
  end
  else
  begin
    FChat.OpenConversation(Job.TakeData);
    R := srOk;
    ChatStreamSync;
  end;
  if ChatPage <> nil then
    ChatPage.ChatStartFinished(R);
end;

procedure TBFocusNativeUI.PostSend(const TempId, Html: string; Attachments: TBFJson);
var
  A: string;
begin
  if Attachments <> nil then A := Attachments.ToJsonString else A := '[]';
  Run(SendWork, SendDone, Self, [FChat.ConversationId, Html, TempId, A]);
end;

procedure TBFocusNativeUI.ChatSend(const Html: string; Attachments: TBFJson);
var
  Item: TBFOutboxItem;
begin
  if FChat.ConversationId = '' then
  begin
    Attachments.Free;
    Exit;
  end;
  // Envio otimista: aparece na hora e vai para a fila de envio.
  Item := FChat.AddOutbox(Html, Attachments);
  PostSend(Item.TempId, Html, Item.Attachments);
  NotifyChat;
end;

function TBFocusNativeUI.SendWork(Job: TBFJob): TBFJson;
begin
  Result := Job.Api.ChatSend(Job.Arg(0), Job.Arg(1), TBFJson.Parse(BFToUtf8(Job.Arg(3))));
end;

procedure TBFocusNativeUI.SendDone(Job: TBFJob);
var
  E: Exception;
begin
  if Job.Failed then
  begin
    FChat.FailOutbox(Job.Arg(2));
    E := Job.MakeError;
    try
      FChat.NoteError(E);
    finally
      E.Free;
    end;
    if Job.ErrorCode = 'CONVERSATION_CLOSED' then
      LoadSnapshot;
  end
  else
    FChat.ConfirmOutbox(Job.Arg(2), Job.TakeData);
  NotifyChat;
end;

procedure TBFocusNativeUI.ChatRetry(const TempId: string);
var
  Item: TBFOutboxItem;
begin
  Item := FChat.RetryOutbox(TempId);
  if Item <> nil then
    PostSend(Item.TempId, Item.ContentHtml, Item.Attachments);
  NotifyChat;
end;

procedure TBFocusNativeUI.ChatDiscard(const TempId: string);
begin
  FChat.DiscardOutbox(TempId);
  NotifyChat;
end;

procedure TBFocusNativeUI.ChatCloseConversation;
begin
  if FChat.ConversationId <> '' then
    Run(CloseWork, CloseDone, Self, [FChat.ConversationId]);
end;

function TBFocusNativeUI.CloseWork(Job: TBFJob): TBFJson;
begin
  Result := Job.Api.ChatClose(Job.Arg(0));
end;

procedure TBFocusNativeUI.CloseDone(Job: TBFJob);
begin
  if Job.Failed then
  begin
    if CheckIdentity(Job) then
      Exit;
  end
  else
    FChat.ApplyConversation(Job.TakeData);
  ChatStreamSync;
  if ChatPage <> nil then
    ChatPage.ChatCloseFinished(not Job.Failed);
  NotifyChat;
end;

procedure TBFocusNativeUI.ChatHandoff;
begin
  if FChat.ConversationId <> '' then
    Run(HandoffWork, HandoffDone, Self, [FChat.ConversationId]);
end;

function TBFocusNativeUI.HandoffWork(Job: TBFJob): TBFJson;
var
  C: TBFJson;
begin
  C := Job.Api.ChatHandoff(Job.Arg(0));
  Result := TBFJson.NewObject;
  if C <> nil then
    Result.Put('conversation', C);
end;

procedure TBFocusNativeUI.HandoffDone(Job: TBFJob);
var
  Code: Integer;
  C: TBFJson;
begin
  Code := 0;
  if Job.Failed then
  begin
    if CheckIdentity(Job) then
      Exit;
    // Servidor sem a rota (404 sem código): o pedido por texto também transfere.
    if (Job.ErrorStatus = 404) and (Job.ErrorCode = '') then
    begin
      ChatSend('<p>' + BFEscapeHtml(T('chat_handoff_text')) + '</p>', nil);
      Code := 1;
    end
    else
    begin
      if Job.ErrorCode = 'CONVERSATION_CLOSED' then
        LoadSnapshot;
      Code := 2;
    end;
  end
  else
  begin
    C := Job.Data.ExtractKey('conversation');
    if C <> nil then
      FChat.ApplyConversation(C)
    else
      LoadSnapshot;
  end;
  if ChatPage <> nil then
    ChatPage.ChatHandoffFinished(Code);
  NotifyChat;
end;

procedure TBFocusNativeUI.ChatReset;
begin
  FChat.Reset;
  FStreamTimer.Enabled := False;
  RefreshAvailability;
end;

procedure TBFocusNativeUI.RefreshAvailability;
begin
  if ChatEnabled then
    Run(AvailWork, AvailDone, Self, []);
end;

function TBFocusNativeUI.AvailWork(Job: TBFJob): TBFJson;
begin
  Result := Job.Api.ChatAvailability;
end;

procedure TBFocusNativeUI.AvailDone(Job: TBFJob);
var
  E: Exception;
begin
  if Job.Failed then
  begin
    E := Job.MakeError;
    try
      FChat.ApplyAvailabilityFailed(E);
    finally
      E.Free;
    end;
  end
  else
    FChat.ApplyAvailability(Job.TakeData);
  NotifyChat;
end;

{ ── release notes, identidade, arquivos ────────────────────────────────── }

procedure TBFocusNativeUI.OpenBanner(Ids: TStrings);
begin
  if FBanner <> nil then
    Exit;
  FBanner := TBFBannerForm.CreateBanner(Self, Self, Ids);
  FBanner.FreeNotification(Self);
  FBanner.Show;
end;

procedure TBFocusNativeUI.OpenHistory;
begin
  if FHistory = nil then
    FHistory := TBFHistoryForm.CreateHistory(Self, Self)
  else
    FHistory.Reload;
  FHistory.Show;
end;

procedure TBFocusNativeUI.ResetUI;
begin
  BFJobs.CancelOwner(Self);
  FChat.Reset;
  FStreamTimer.Enabled := False;
  FSessionTimer.Enabled := False;
  SetPage(nil);
  FreeAndNil(FHistory);
  FWidgetConfig.Free;
  FWidgetConfig := nil;
  FState := usIdle;
  FAutoRouted := False;
  FreeAndNil(FReadState);
  FReadState := TBFReadState.Create(FWidget.Storage, BFScopeKey(FWidget.Config));
  if (FForm <> nil) and not FVisible then
    FreeAndNil(FForm);
end;

procedure TBFocusNativeUI.ApiChanged;
begin
  // As telas leem a Api do widget a cada chamada; nada a trocar aqui.
end;

procedure TBFocusNativeUI.FilesDropped(Files: TStrings);
begin
  if FPage <> nil then
    FPage.DropFiles(Files);
end;

procedure TBFocusNativeUI.FormActivated;
begin
  // Como o refetchOnWindowFocus do embed: a tela reconsulta o que depende do foco.
  if FVisible and (FState = usReady) and (FPage <> nil) then
    FPage.WindowActivated;
end;

end.
