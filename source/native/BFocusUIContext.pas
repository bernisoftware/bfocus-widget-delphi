unit BFocusUIContext;

{ Estado compartilhado pelas telas nativas (o "App" do embed web): Api, /config do
  tenant, idioma, cor da marca, leitura local, sessão do chat e a navegação. As telas só
  conhecem esta classe; o controlador (BFocusNativeUI) implementa a navegação. }

{$I BFocusDefines.inc}

interface

uses
  SysUtils, Classes, Controls, ExtCtrls, Graphics, BFocusText, BFocusJson, BFocusConfig,
  BFocusApi, BFocusAsync, BFocusStorage, BFocusVMTickets, BFocusVMChat, BFocusI18n,
  BFocusGraphics, BFocusTokens, BFocusWidgetBase;

type
  TBFUIContext = class;

  { Tela (lista, novo, detalhe, chat): painel montado em código. }
  TBFPage = class(TCustomPanel)
  protected
    FCtx: TBFUIContext;
    function Run(Work: TBFJobWork; Done: TBFJobDone; const Args: array of string): TBFJob;
  public
    constructor CreatePage(AOwner: TComponent; ACtx: TBFUIContext); virtual;
    destructor Destroy; override;
    { Chamada depois de entrar na tela / ao sair. }
    procedure Activate; virtual;
    procedure Deactivate; virtual;
    { Widget mostrado/escondido (liga/desliga atualizações). }
    procedure VisibilityChanged(AVisible: Boolean); virtual;
    { Estado do chat mudou (evento, envio, disponibilidade). }
    procedure ChatChanged; virtual;
    { Arquivos arrastados para a janela. }
    procedure DropFiles(Files: TStrings); virtual;
    { A janela do widget voltou ao foco (as reconsultas "no foco" do embed web). }
    procedure WindowActivated; virtual;
    property Ctx: TBFUIContext read FCtx;
  end;

  TBFUIContext = class(TComponent)
  private
    FDlUrl: string;
    function DownloadInfoWork(Job: TBFJob): TBFJson;
    procedure DownloadInfoDone(Job: TBFJob);
    function DownloadFileWork(Job: TBFJob): TBFJson;
    procedure DownloadFileDone(Job: TBFJob);
  protected
    FWidget: TBFocusWidgetBase;
    FWidgetConfig: TBFJson;
    FChat: TBFChatSession;
    FReadState: TBFReadState;
    FVisible: Boolean;
  public
    constructor CreateContext(AOwner: TComponent; AWidget: TBFocusWidgetBase);
    destructor Destroy; override;
    function Api: TBFocusApi;
    function Config: TBFocusConfig;
    function Locale: string;
    function T(const Key: string): string;
    function RN(const Key: string): string;
    function PrimaryHex: string;
    function Primary: TColor;
    function TenantName: string;
    function CustomerName: string;
    function ChatEnabled: Boolean;
    function Run(Work: TBFJobWork; Done: TBFJobDone; Owner: TObject;
      const Args: array of string): TBFJob;
    { 401 de identidade em qualquer chamada: tela error_identity (nunca lista vazia). }
    function CheckIdentity(Job: TBFJob): Boolean;
    procedure ReportUnread(Count: Integer);
    procedure ReportSeen(const LatestEventAt: string);
    procedure OpenExternal(const Url: string);
    { Anexo: URL pré-assinada com o nome original → "salvar como". }
    procedure DownloadAttachment(const AttachmentId: string);
    procedure LinkClicked(Sender: TObject; const Url: string);

    // navegação (controlador)
    procedure GoList; virtual; abstract;
    procedure GoNew(const PrefillHtml: string; Attachments: TBFJson; const Notice: string); virtual; abstract;
    procedure GoDetail(const TicketId: string); virtual; abstract;
    procedure GoChat(const ContinueTicketId, TicketNumber: string); virtual; abstract;
    procedure CloseWidget; virtual; abstract;
    procedure IdentityRejected(const Code: string); virtual; abstract;
    { Chat (o stream vive no controlador para seguir enquanto se navega). }
    procedure ChatStart(const Html: string; Attachments: TBFJson; const ContinueTicketId: string); virtual; abstract;
    procedure ChatSend(const Html: string; Attachments: TBFJson); virtual; abstract;
    procedure ChatRetry(const TempId: string); virtual; abstract;
    procedure ChatDiscard(const TempId: string); virtual; abstract;
    procedure ChatCloseConversation; virtual; abstract;
    procedure ChatHandoff; virtual; abstract;
    procedure ChatReset; virtual; abstract;
    procedure RefreshAvailability; virtual; abstract;
    function ViewingChat: Boolean; virtual; abstract;

    property Widget: TBFocusWidgetBase read FWidget;
    property WidgetConfig: TBFJson read FWidgetConfig;
    property Chat: TBFChatSession read FChat;
    property ReadState: TBFReadState read FReadState;
    property Visible: Boolean read FVisible;
  end;

implementation

uses
  BFocusUIControls;

{ ── TBFPage ────────────────────────────────────────────────────────────── }

constructor TBFPage.CreatePage(AOwner: TComponent; ACtx: TBFUIContext);
begin
  inherited Create(AOwner);
  FCtx := ACtx;
  BevelOuter := bvNone;
  Caption := '';
  Color := BFClSurface;
end;

destructor TBFPage.Destroy;
begin
  // Respostas atrasadas não podem tocar numa tela já liberada.
  BFJobs.CancelOwner(Self);
  inherited Destroy;
end;

function TBFPage.Run(Work: TBFJobWork; Done: TBFJobDone; const Args: array of string): TBFJob;
begin
  Result := FCtx.Run(Work, Done, Self, Args);
end;

procedure TBFPage.Activate;
begin
end;

procedure TBFPage.Deactivate;
begin
end;

procedure TBFPage.VisibilityChanged(AVisible: Boolean);
begin
end;

procedure TBFPage.ChatChanged;
begin
end;

procedure TBFPage.DropFiles(Files: TStrings);
begin
end;

procedure TBFPage.WindowActivated;
begin
end;

{ ── TBFUIContext ───────────────────────────────────────────────────────── }

constructor TBFUIContext.CreateContext(AOwner: TComponent; AWidget: TBFocusWidgetBase);
begin
  inherited Create(AOwner);
  FWidget := AWidget;
  FChat := TBFChatSession.Create;
  FReadState := TBFReadState.Create(AWidget.Storage, BFScopeKey(AWidget.Config));
end;

destructor TBFUIContext.Destroy;
begin
  BFJobs.CancelOwner(Self);
  FReadState.Free;
  FChat.Free;
  FWidgetConfig.Free;
  inherited Destroy;
end;

function TBFUIContext.Api: TBFocusApi;
begin
  Result := FWidget.Api;
end;

function TBFUIContext.Config: TBFocusConfig;
begin
  Result := FWidget.Config;
end;

function TBFUIContext.Locale: string;
begin
  Result := FWidget.Locale;
  if Result = '' then
    Result := BFLocaleOf(FWidget.Config);
end;

function TBFUIContext.T(const Key: string): string;
begin
  Result := BFT(Locale, Key);
end;

function TBFUIContext.RN(const Key: string): string;
begin
  Result := BFRN(Locale, Key);
end;

function TBFUIContext.PrimaryHex: string;
var
  Tenant: TBFJson;
begin
  Result := '';
  if FWidgetConfig <> nil then
  begin
    Tenant := FWidgetConfig.ObjOf('tenant');
    if Tenant <> nil then
      Result := Tenant.StrOf('primary_color');
  end;
  // O backend pode mandar '' vazio: cai para a marca do bFocus.
  if Result = '' then
    Result := FWidget.PrimaryColor;
  if Result = '' then
    Result := BF_BRAND_FALLBACK;
end;

function TBFUIContext.Primary: TColor;
begin
  Result := BFColor(PrimaryHex, BFColor(BF_BRAND_FALLBACK, clNavy));
end;

function TBFUIContext.TenantName: string;
begin
  Result := '';
  if (FWidgetConfig <> nil) and (FWidgetConfig.ObjOf('tenant') <> nil) then
    Result := FWidgetConfig.ObjOf('tenant').StrOf('name');
end;

function TBFUIContext.CustomerName: string;
begin
  Result := FWidget.Config.Customer.Name;
end;

function TBFUIContext.ChatEnabled: Boolean;
begin
  Result := (FWidgetConfig <> nil) and (FWidgetConfig.ObjOf('chat') <> nil) and
    FWidgetConfig.ObjOf('chat').BoolOf('enabled') and not FChat.IdentityError;
end;

function TBFUIContext.Run(Work: TBFJobWork; Done: TBFJobDone; Owner: TObject;
  const Args: array of string): TBFJob;
begin
  Result := BFJobs.Run(Api, Work, Done, Owner, Args);
end;

function TBFUIContext.CheckIdentity(Job: TBFJob): Boolean;
begin
  Result := Job.IsIdentityError;
  if Result then
    IdentityRejected(Job.ErrorCode);
end;

procedure TBFUIContext.ReportUnread(Count: Integer);
begin
  if FVisible then
    FWidget.HostUnread(Count);
end;

procedure TBFUIContext.ReportSeen(const LatestEventAt: string);
begin
  if LatestEventAt <> '' then
    FWidget.HostSeen(LatestEventAt);
end;

procedure TBFUIContext.OpenExternal(const Url: string);
begin
  BFOpenUrl(Url);
end;

procedure TBFUIContext.LinkClicked(Sender: TObject; const Url: string);
begin
  OpenExternal(Url);
end;

procedure TBFUIContext.DownloadAttachment(const AttachmentId: string);
begin
  Run(DownloadInfoWork, DownloadInfoDone, Self, [AttachmentId]);
end;

function TBFUIContext.DownloadInfoWork(Job: TBFJob): TBFJson;
begin
  Result := Job.Api.DownloadInfo(Job.Arg(0));
end;

procedure TBFUIContext.DownloadInfoDone(Job: TBFJob);
var
  Path: string;
begin
  if Job.Failed or (Job.Data = nil) then
  begin
    CheckIdentity(Job);
    Exit;
  end;
  FDlUrl := Job.Data.StrOf('url');
  if not BFSaveAs(Job.Data.StrOf('filename'), Path) then
    Exit;
  Run(DownloadFileWork, DownloadFileDone, Self, [FDlUrl, Path]);
end;

function TBFUIContext.DownloadFileWork(Job: TBFJob): TBFJson;
begin
  Job.Api.DownloadTo(Job.Arg(0), Job.Stream);
  Result := nil;
end;

procedure TBFUIContext.DownloadFileDone(Job: TBFJob);
begin
  if not Job.Failed then
    Job.Stream.SaveToFile(Job.Arg(1));
end;

end.
