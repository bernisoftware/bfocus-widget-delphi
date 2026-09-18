unit BFocusUIChat;

{ Chat ao vivo na UI nativa (behavior spec §5): cartão na lista, conversa com cabeçalho
  (protocolo, status com cor, encerrar com confirmação), faixa "falar com um atendente"
  do assistente, mensagens agrupadas em 2 min com avatar, fila de envio (enviando /
  não enviada com tentar de novo e descartar), composer (Enter envia, Shift+Enter quebra
  linha, anexos), desfecho (CSAT, acompanhamento, só aviso) e "continuar conversa".
  Também a bolha de mensagem e o carregador de prévias de imagem, usados no detalhe. }

{$I BFocusDefines.inc}

interface

uses
  SysUtils, Classes, Controls, Forms, Graphics, StdCtrls, ExtCtrls, BFocusText, BFocusJson,
  BFocusApi, BFocusAsync, BFocusFormat, BFocusVMChat, BFocusUIControls, BFocusUIContext,
  BFocusGraphics, BFocusTokens, BFocusI18n, BFocusModels;

type
  TBFAvatarMode = (amNone, amEmpty, amInitials, amBot);

  { Baixa e guarda as prévias de imagem dos anexos (clicar baixa com o nome original). }
  TBFPreviewLoader = class(TComponent)
  private
    FCtx: TBFUIContext;
    FCache: TStringList;   // id → TMemoryStream (dono)
    FCards: TStringList;   // id → TBFAttachmentCard (não é dono)
    FPending: TStringList;
    FOnLoaded: TNotifyEvent;
    function PreviewWork(Job: TBFJob): TBFJson;
    procedure PreviewDone(Job: TBFJob);
    procedure LoadInto(Card: TBFAttachmentCard; Stream: TMemoryStream; const Mime: string);
  public
    constructor CreateLoader(AOwner: TComponent; ACtx: TBFUIContext);
    destructor Destroy; override;
    procedure ResetCards;
    procedure Attach(Card: TBFAttachmentCard; const AttId, Url, Mime: string);
    property OnLoaded: TNotifyEvent read FOnLoaded write FOnLoaded;
  end;

  { Bolha de mensagem (chamado, transcrição do chat, conversa). }
  TBFBubble = class(TCustomControl, IBFMeasurable)
  private
    FCtx: TBFUIContext;
    FMine: Boolean;
    FSystem: Boolean;
    FPending: Boolean;
    FFailed: Boolean;
    FAccent: TColor;
    FHasContent: Boolean;
    FPlain: string;
    FHtml: TBFHtmlBox;
    FCards: TList;
    FMeta: TBFText;
    FActions: TBFRow;
    FAvatar: TBFAvatarMode;
    FAvatarText: string;
    FBubbleRect: TRect;
    FTempId: string;
    FOnRetry: TNotifyEvent;
    FOnDiscard: TNotifyEvent;
    function AvatarWidth: Integer;
    function BubbleWidth(AWidth: Integer): Integer;
    procedure CardClick(Sender: TObject);
    procedure RetryClick(Sender: TObject);
    procedure DiscardClick(Sender: TObject);
  protected
    procedure Paint; override;
    procedure Resize; override;
  public
    constructor CreateBubble(AOwner: TComponent; ACtx: TBFUIContext; Mine: Boolean;
      const Html: TBFRaw; Attachments: TBFJson; const Meta: string; Loader: TBFPreviewLoader);
    destructor Destroy; override;
    procedure SetAvatar(Mode: TBFAvatarMode; const Text: string);
    procedure MakeSystem;
    procedure MakePending(Failed: Boolean; const TempId: string; OnRetry, OnDiscard: TNotifyEvent);
    function MeasureHeight(AWidth: Integer): Integer;
    property TempId: string read FTempId;
  end;

  { Cartão do chat no topo da lista (§5.1). }
  TBFChatCard = class(TBFColumn)
  private
    FOnStart, FOnResume, FOnNewTicket: TNotifyEvent;
    procedure StartClick(Sender: TObject);
    procedure ResumeClick(Sender: TObject);
    procedure NewClick(Sender: TObject);
  public
    constructor CreateCard(AOwner: TComponent; Ctx: TBFUIContext; Mode: TBFHomeMode);
    property OnStart: TNotifyEvent read FOnStart write FOnStart;
    property OnResume: TNotifyEvent read FOnResume write FOnResume;
    property OnNewTicket: TNotifyEvent read FOnNewTicket write FOnNewTicket;
  end;

  TBFStars = class(TCustomControl)
  private
    FRating: Integer;
    FOnChange: TNotifyEvent;
  protected
    procedure Paint; override;
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
  public
    constructor Create(AOwner: TComponent); override;
    property Rating: Integer read FRating write FRating;
    property OnChange: TNotifyEvent read FOnChange write FOnChange;
  end;

  { Avaliação de 1 a 5 + comentário (até 2000), sem girar para sempre. }
  TBFCsatPanel = class(TBFColumn)
  private
    FCtx: TBFUIContext;
    FTicketId: string;
    FVM: TBFCsatVM;
    FStars: TBFStars;
    FComment: TMemo;
    FError: TBFText;
    FSubmit: TBFButton;
    FStatus: TBFText;
    FTitle: TBFText;
    procedure StarsChange(Sender: TObject);
    procedure SubmitClick(Sender: TObject);
    function SubmitWork(Job: TBFJob): TBFJson;
    procedure SubmitDone(Job: TBFJob);
    procedure Sync;
  public
    constructor CreateCsat(AOwner: TComponent; ACtx: TBFUIContext; const TicketId: string);
    destructor Destroy; override;
  end;

  { Cabeçalho da conversa: avatar, protocolo e status com a cor do token. }
  TBFChatHeader = class(TCustomControl, IBFMeasurable)
  private
    FProtocol, FTitle, FStatus: string;
    FStatusColor: TColor;
    FAvatar: TBFAvatarMode;
    FAvatarText: string;
    FAccent: TColor;
    FRightSpace: Integer;
  protected
    procedure Paint; override;
  public
    constructor Create(AOwner: TComponent); override;
    procedure Setup(const Protocol, Title, Status: string; StatusColor, Accent: TColor;
      Avatar: TBFAvatarMode; const AvatarText: string; RightSpace: Integer);
    function MeasureHeight(AWidth: Integer): Integer;
  end;

  TBFFootMode = (fmNone, fmComposer, fmTerminal);

  TBFChatPage = class(TBFPage)
  private
    FContinueTicketId, FTicketNumber: string;
    FHead: TBFColumn;
    FHeader: TBFChatHeader;
    FEnd: TBFButton;
    FConfirm: TBFRow;
    FConfirmEnd: TBFButton;
    FHandoff: TBFRow;
    FHandoffText: TBFText;
    FHandoffBtn: TBFButton;
    FBanner: TBFText;
    FStack: TBFStack;
    FFoot: TBFColumn;
    FFootMode: TBFFootMode;
    FFootConvId: string;
    FMemo: TMemo;
    FSend: TBFButton;
    FAttach: TBFButton;
    FChips: TBFColumn;
    FUploadError: TBFText;
    FFiles: TBFJson;
    FUploadQueue: TStringList;
    FUploading: Boolean;
    FSwallowEnter: Boolean;
    FFirstPendingHtml: string;
    FFirstPendingFiles: TBFJson;
    FStartError: Boolean;
    FConfirming: Boolean;
    FEnding: Boolean;
    FHandoffState: Integer; // 0 ocioso, 1 enviando, 2 pedido, 3 erro
    FLoader: TBFPreviewLoader;
    procedure BuildHead;
    procedure BuildBody;
    procedure BuildFoot;
    procedure FitAll;
    procedure BuildComposer;
    procedure BuildTerminal;
    procedure RebuildChips;
    procedure BackClick(Sender: TObject);
    procedure EndClick(Sender: TObject);
    procedure CancelEndClick(Sender: TObject);
    procedure ConfirmEndClick(Sender: TObject);
    procedure HandoffClick(Sender: TObject);
    procedure SendClick(Sender: TObject);
    procedure AttachClick(Sender: TObject);
    procedure RemoveFileClick(Sender: TObject);
    procedure MemoKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure MemoKeyPress(Sender: TObject; var Key: Char);
    procedure MemoChange(Sender: TObject);
    procedure RetryClick(Sender: TObject);
    procedure DiscardClick(Sender: TObject);
    procedure ContinueClick(Sender: TObject);
    procedure ViewTicketClick(Sender: TObject);
    procedure PreviewLoaded(Sender: TObject);
    procedure StartUploads(Files: TStrings);
    procedure NextUpload;
    function UploadWork(Job: TBFJob): TBFJson;
    procedure UploadDone(Job: TBFJob);
    procedure UpdateComposerState;
    procedure MarkRead;
  protected
    procedure Resize; override;
  public
    constructor CreateChat(AOwner: TComponent; ACtx: TBFUIContext;
      const ContinueTicketId, TicketNumber: string);
    destructor Destroy; override;
    procedure Activate; override;
    procedure ChatChanged; override;
    procedure DropFiles(Files: TStrings); override;
    procedure ChatStartFinished(R: TBFStartResult);
    procedure ChatCloseFinished(Ok: Boolean);
    { 0 = pedido feito, 1 = fallback por texto, 2 = erro. }
    procedure ChatHandoffFinished(Code: Integer);
  end;

const
  BF_CHAT_MAX_FILES = 10;

procedure BFDrawAvatar(C: TCanvas; X, Y, Size: Integer; Mode: TBFAvatarMode;
  const Text: string; Accent: TColor);

implementation

procedure BFDrawAvatar(C: TCanvas; X, Y, Size: Integer; Mode: TBFAvatarMode;
  const Text: string; Accent: TColor);
var
  T: string;
begin
  if Mode in [amNone, amEmpty] then
    Exit;
  C.Brush.Color := BFMix(Accent, clWhite, 0.14);
  C.Pen.Color := C.Brush.Color;
  C.Ellipse(X, Y, X + Size, Y + Size);
  if Mode = amBot then
    T := BFGlyph(#$F0#$9F#$A4#$96, 'IA') // robô
  else
    T := Text;
  BFStyleFont(C.Font, Size div 3, True, Accent);
  BFDrawTextIn(C, T, Rect(X, Y + (Size - C.TextHeight('Ag')) div 2, X + Size, Y + Size),
    taCenter, False);
end;

{ ── TBFPreviewLoader ───────────────────────────────────────────────────── }

constructor TBFPreviewLoader.CreateLoader(AOwner: TComponent; ACtx: TBFUIContext);
begin
  inherited Create(AOwner);
  FCtx := ACtx;
  FCache := TStringList.Create;
  FCards := TStringList.Create;
  FPending := TStringList.Create;
end;

destructor TBFPreviewLoader.Destroy;
var
  I: Integer;
begin
  BFJobs.CancelOwner(Self);
  for I := 0 to FCache.Count - 1 do
    FCache.Objects[I].Free;
  FCache.Free;
  FCards.Free;
  FPending.Free;
  inherited Destroy;
end;

procedure TBFPreviewLoader.ResetCards;
begin
  FCards.Clear;
end;

procedure TBFPreviewLoader.LoadInto(Card: TBFAttachmentCard; Stream: TMemoryStream;
  const Mime: string);
begin
  if not BFLoadPicture(Stream, Mime, Card.Picture) then
    Card.Picture.Assign(nil);
end;

procedure TBFPreviewLoader.Attach(Card: TBFAttachmentCard; const AttId, Url, Mime: string);
var
  I: Integer;
begin
  // Sem URL (transcrição do chat) não há prévia: fica o cartão de arquivo.
  if (Url = '') or (AttId = '') or not BFIsImageMime(Mime) then
    Exit;
  FCards.AddObject(AttId, Card);
  I := FCache.IndexOf(AttId);
  if I >= 0 then
  begin
    LoadInto(Card, TMemoryStream(FCache.Objects[I]), Mime);
    Exit;
  end;
  if FPending.IndexOf(AttId) >= 0 then
    Exit;
  FPending.Add(AttId);
  BFJobs.Run(FCtx.Api, PreviewWork, PreviewDone, Self, [Url, AttId, Mime]);
end;

function TBFPreviewLoader.PreviewWork(Job: TBFJob): TBFJson;
begin
  Job.Api.DownloadTo(Job.Arg(0), Job.Stream);
  Result := nil;
end;

procedure TBFPreviewLoader.PreviewDone(Job: TBFJob);
var
  M: TMemoryStream;
  I: Integer;
  Any: Boolean;
begin
  I := FPending.IndexOf(Job.Arg(1));
  if I >= 0 then
    FPending.Delete(I);
  if Job.Failed then
    Exit;
  M := TMemoryStream.Create;
  Job.Stream.Position := 0;
  M.CopyFrom(Job.Stream, Job.Stream.Size);
  FCache.AddObject(Job.Arg(1), M);
  Any := False;
  for I := 0 to FCards.Count - 1 do
    if FCards[I] = Job.Arg(1) then
    begin
      LoadInto(TBFAttachmentCard(FCards.Objects[I]), M, Job.Arg(2));
      Any := True;
    end;
  if Any and Assigned(FOnLoaded) then
    FOnLoaded(Self);
end;

{ ── TBFBubble ──────────────────────────────────────────────────────────── }

constructor TBFBubble.CreateBubble(AOwner: TComponent; ACtx: TBFUIContext; Mine: Boolean;
  const Html: TBFRaw; Attachments: TBFJson; const Meta: string; Loader: TBFPreviewLoader);
var
  I: Integer;
  A: TBFJson;
  Card: TBFAttachmentCard;
  Mime: string;
begin
  inherited Create(AOwner);
  FCtx := ACtx;
  FMine := Mine;
  FAccent := ACtx.Primary;
  FCards := TList.Create;
  FHasContent := not BFIsHtmlEmpty(BFFromUtf8(Html));
  FPlain := BFHtmlToText(BFFromUtf8(Html));
  FHtml := TBFHtmlBox.Create(Self);
  FHtml.Parent := Self;
  if Mine then
  begin
    FHtml.Color := FAccent;
    FHtml.TextColor := clWhite;
    FHtml.LinkColor := clWhite;
  end
  else
  begin
    FHtml.Color := clWhite;
    FHtml.LinkColor := FAccent;
  end;
  FHtml.OnLink := ACtx.LinkClicked;
  FHtml.SetHtml(Html);
  FHtml.Visible := FHasContent;
  if Attachments <> nil then
    for I := 0 to Attachments.Count - 1 do
    begin
      A := Attachments.Item(I);
      Mime := A.StrOf('content_type', A.StrOf('mime_type'));
      Card := TBFAttachmentCard.Create(Self);
      Card.Parent := Self;
      Card.RightAlign := Mine;
      Card.Setup(A.StrOf('filename'), Mime, A.IntOf('size', -1), FAccent);
      Card.Hint := A.StrOf('id');
      Card.OnClick := CardClick;
      if Loader <> nil then
        Loader.Attach(Card, A.StrOf('id'), A.StrOf('url'), Mime);
      FCards.Add(Card);
    end;
  FMeta := TBFText.Create(Self);
  FMeta.Parent := Self;
  FMeta.Style(7, False, BFClSubtle);
  FMeta.Text := Meta;
  if Mine then
    FMeta.Alignment := taRightJustify;
  Color := BFClSurface;
end;

destructor TBFBubble.Destroy;
begin
  FCards.Free;
  inherited Destroy;
end;

procedure TBFBubble.SetAvatar(Mode: TBFAvatarMode; const Text: string);
begin
  FAvatar := Mode;
  FAvatarText := Text;
end;

procedure TBFBubble.MakeSystem;
begin
  FSystem := True;
  FHtml.Color := BFClChip;
  FHtml.TextColor := BFClMuted;
  FHtml.FontSize := 8;
  FHtml.SetHtml(TBFRaw(BFToUtf8('<p>' + BFEscapeHtml(FPlain) + '</p>')));
  FMeta.Visible := False;
end;

procedure TBFBubble.MakePending(Failed: Boolean; const TempId: string; OnRetry,
  OnDiscard: TNotifyEvent);
var
  B: TBFButton;
  I: Integer;
begin
  FPending := not Failed;
  FFailed := Failed;
  FTempId := TempId;
  FOnRetry := OnRetry;
  FOnDiscard := OnDiscard;
  // Em envio: anexos não são clicáveis.
  for I := 0 to FCards.Count - 1 do
    TBFAttachmentCard(FCards[I]).Clickable := False;
  if Failed then
  begin
    FMeta.Text := FCtx.T('chat_msg_failed');
    FMeta.TextColor := BFClDanger;
    FActions := TBFRow.Create(Self);
    FActions.Parent := Self;
    FActions.RowHeight := 20;
    FActions.Color := BFClSurface;
    if Assigned(OnRetry) then
    begin
      B := TBFButton.Create(Self);
      B.Kind := bkLink;
      B.Accent := BFClDanger;
      B.FontSize := 7;
      B.ButtonHeight := 20;
      B.Caption := FCtx.T('btn_retry');
      B.OnClick := RetryClick;
      FActions.Add(B, B.PreferredWidth);
    end;
    if Assigned(OnDiscard) then
    begin
      B := TBFButton.Create(Self);
      B.Kind := bkLink;
      B.Accent := BFClDanger;
      B.FontSize := 7;
      B.ButtonHeight := 20;
      B.Caption := FCtx.T('btn_discard');
      B.OnClick := DiscardClick;
      FActions.Add(B, B.PreferredWidth);
    end;
  end
  else
  begin
    FMeta.Text := FCtx.T('chat_msg_sending');
    // "Enviando": bolha mais clara (o web usa opacidade 0,7).
    FHtml.Color := BFMix(FAccent, clWhite, 0.7);
  end;
end;

function TBFBubble.AvatarWidth: Integer;
begin
  if FAvatar = amNone then Result := 0 else Result := 30;
end;

function TBFBubble.BubbleWidth(AWidth: Integer): Integer;
var
  Max, Natural, I: Integer;
  F: TFont;
  Lines: TStringList;
begin
  if FSystem then
  begin
    Result := Round(AWidth * 0.9);
    Exit;
  end;
  Max := Round((AWidth - AvatarWidth) * 0.85);
  F := TFont.Create;
  Lines := TStringList.Create;
  try
    BFStyleFont(F, 9, False, clBlack);
    Lines.Text := FPlain;
    Natural := 0;
    for I := 0 to Lines.Count - 1 do
      if BFTextWidth(F, Lines[I]) > Natural then
        Natural := BFTextWidth(F, Lines[I]);
  finally
    Lines.Free;
    F.Free;
  end;
  Result := Natural + 26;
  if Result < 48 then Result := 48;
  if Result > Max then Result := Max;
end;

function TBFBubble.MeasureHeight(AWidth: Integer): Integer;
var
  BW, I: Integer;
begin
  Result := 0;
  BW := BubbleWidth(AWidth);
  if FHasContent then
    Inc(Result, FHtml.MeasureHeight(BW - 24) + 16 + 4);
  for I := 0 to FCards.Count - 1 do
    Inc(Result, TBFAttachmentCard(FCards[I]).MeasureHeight(Round((AWidth - AvatarWidth) * 0.85)) + 4);
  if FMeta.Visible and (FMeta.Text <> '') then
    Inc(Result, FMeta.MeasureHeight(AWidth - AvatarWidth));
  if FActions <> nil then
    Inc(Result, 20);
  if Result < 8 then
    Result := 8;
end;

procedure TBFBubble.Resize;
var
  BW, X, Y, H, I, CardW, AvW: Integer;
  Card: TBFAttachmentCard;
begin
  inherited Resize;
  AvW := AvatarWidth;
  BW := BubbleWidth(Width);
  if FSystem then
    X := (Width - BW) div 2
  else if FMine then
    X := Width - BW
  else
    X := AvW;
  Y := 0;
  if FHasContent then
  begin
    H := FHtml.MeasureHeight(BW - 24);
    FBubbleRect := Rect(X, 0, X + BW, H + 16);
    FHtml.SetBounds(X + 12, 8, BW - 24, H);
    Y := H + 16 + 4;
  end
  else
    FBubbleRect := Rect(0, 0, 0, 0);
  CardW := Round((Width - AvW) * 0.85);
  for I := 0 to FCards.Count - 1 do
  begin
    Card := TBFAttachmentCard(FCards[I]);
    H := Card.MeasureHeight(CardW);
    if FMine then
      Card.SetBounds(Width - CardW, Y, CardW, H)
    else
      Card.SetBounds(AvW, Y, CardW, H);
    Inc(Y, H + 4);
  end;
  if FMeta.Visible and (FMeta.Text <> '') then
  begin
    H := FMeta.MeasureHeight(Width - AvW);
    FMeta.SetBounds(AvW, Y, Width - AvW, H);
    Inc(Y, H);
  end;
  if FActions <> nil then
  begin
    FActions.SetBounds(AvW, Y, Width - AvW, 20);
    FActions.Relayout;
  end;
end;

procedure TBFBubble.Paint;
var
  R: TRect;
begin
  with Canvas do
  begin
    Brush.Color := BFClSurface;
    FillRect(Rect(0, 0, Width, Height));
    if FHasContent then
    begin
      R := FBubbleRect;
      Brush.Color := FHtml.Color;
      if FFailed then
        Pen.Color := BFClDanger
      else if FMine or FSystem then
        Pen.Color := FHtml.Color
      else
        Pen.Color := BFClBorder;
      if FFailed then
        Pen.Width := 2;
      RoundRect(R.Left, R.Top, R.Right, R.Bottom, 14, 14);
      Pen.Width := 1;
    end;
    if not FMine and not FSystem then
      BFDrawAvatar(Canvas, 0, FBubbleRect.Bottom - 24, 24, FAvatar, FAvatarText, FAccent);
  end;
end;

procedure TBFBubble.CardClick(Sender: TObject);
begin
  // Baixa pelo endpoint (URL pré-assinada com o nome original).
  if TBFAttachmentCard(Sender).Hint <> '' then
    FCtx.DownloadAttachment(TBFAttachmentCard(Sender).Hint);
end;

procedure TBFBubble.RetryClick(Sender: TObject);
begin
  if Assigned(FOnRetry) then
    FOnRetry(Self);
end;

procedure TBFBubble.DiscardClick(Sender: TObject);
begin
  if Assigned(FOnDiscard) then
    FOnDiscard(Self);
end;

{ ── TBFChatCard ────────────────────────────────────────────────────────── }

function DotText(Mode: TBFHomeMode): string;
begin
  Result := BFFromUtf8(#$E2#$97#$8F) + ' '; // ●
end;

constructor TBFChatCard.CreateCard(AOwner: TComponent; Ctx: TBFUIContext; Mode: TBFHomeMode);
var
  Title, Desc, Extra: TBFText;
  Cta, Link: TBFButton;
  Conv: TBFJson;
  Queue: Int64;
  T: string;
begin
  inherited Create(AOwner);
  Box(clWhite, BFClBorder, 14, 14, 12);
  Gap := 6;
  if Mode = hmLoading then
  begin
    Title := TBFText.Create(Self);
    Title.Style(9, False, Ctx.Primary);
    Title.Alignment := taCenter;
    Title.Text := Ctx.T('loading');
    Add(Title);
    Exit;
  end;
  Title := TBFText.Create(Self);
  Title.Style(10, True, BFClText);
  Add(Title);
  Desc := TBFText.Create(Self);
  Desc.Style(8, False, BFClMuted);
  Add(Desc);
  Cta := TBFButton.Create(Self);
  Cta.Accent := Ctx.Primary;
  Cta.ButtonHeight := 40;
  if Mode = hmActive then
  begin
    Conv := Ctx.Chat.Conversation;
    T := Ctx.T('chat_active_title');
    if Ctx.Chat.Unread > 0 then
      T := T + '  (' + BFBadgeCountLabel(Ctx.Chat.Unread) + ')';
    Title.Text := DotText(Mode) + T;
    Desc.Text := Conv.StrOf('ticket_number') + ' ' + BFFromUtf8(#$C2#$B7) + ' ' +
      BFChatStatusLabel(Ctx.Locale, Conv);
    Cta.Caption := Ctx.T('btn_chat_resume');
    Cta.OnClick := ResumeClick;
    Add(Cta);
    Exit;
  end;
  Queue := 0;
  if Ctx.Chat.Availability <> nil then
    Queue := Ctx.Chat.Availability.IntOf('queue_size');
  case Mode of
    hmBusy:
      begin
        Title.Text := DotText(Mode) + Ctx.T('chat_busy_title');
        Desc.Text := Ctx.T('chat_busy_desc');
        Cta.Caption := BFGlyph(#$F0#$9F#$92#$AC, '') + ' ' + Ctx.T('btn_chat_queue');
        Cta.OnClick := StartClick;
      end;
    hmOffline:
      begin
        Title.Text := DotText(Mode) + Ctx.T('chat_offline_title');
        Desc.Text := Ctx.T('chat_offline_desc');
        Cta.Caption := BFGlyph(#$E2#$9C#$89, '') + ' ' + Ctx.T('btn_leave_message');
        Cta.OnClick := NewClick;
      end;
  else
    Title.Text := DotText(Mode) + Ctx.T('chat_online_title');
    // Produto autônomo (Fase 4): o assistente atende na hora.
    if BFIsBotAvailability(Ctx.Chat.Availability) then
      Desc.Text := Ctx.T('chat_online_desc_bot')
    else
      Desc.Text := Ctx.T('chat_online_desc');
    Cta.Caption := BFGlyph(#$F0#$9F#$92#$AC, '') + ' ' + Ctx.T('btn_chat_now');
    Cta.OnClick := StartClick;
  end;
  Title.TextColor := BFClText;
  if (Mode = hmBusy) and (Queue > 0) then
  begin
    Extra := TBFText.Create(Self);
    Extra.Style(8, True, BFClMuted);
    Extra.Text := BFFill(Ctx.T('chat_queue_size'), 'n', IntToStr(Queue));
    Add(Extra);
  end;
  Add(Cta);
  if Mode <> hmOffline then
  begin
    Link := TBFButton.Create(Self);
    Link.Kind := bkLink;
    Link.Accent := BFClMuted;
    Link.Alignment := taCenter;
    Link.ButtonHeight := 22;
    Link.FontSize := 8;
    Link.Caption := Ctx.T('btn_open_ticket_instead');
    Link.OnClick := NewClick;
    Add(Link);
  end;
end;

procedure TBFChatCard.StartClick(Sender: TObject);
begin
  if Assigned(FOnStart) then FOnStart(Self);
end;

procedure TBFChatCard.ResumeClick(Sender: TObject);
begin
  if Assigned(FOnResume) then FOnResume(Self);
end;

procedure TBFChatCard.NewClick(Sender: TObject);
begin
  if Assigned(FOnNewTicket) then FOnNewTicket(Self);
end;

{ ── TBFStars ───────────────────────────────────────────────────────────── }

constructor TBFStars.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  Height := 34;
  Cursor := crHandPoint;
end;

procedure TBFStars.Paint;
var
  I, X0: Integer;
  Star: string;
begin
  with Canvas do
  begin
    Brush.Color := BFClSurface;
    FillRect(Rect(0, 0, Width, Height));
    Star := BFGlyph(#$E2#$98#$85, '*');
    X0 := (Width - 5 * 32) div 2;
    for I := 1 to 5 do
    begin
      if I <= FRating then
        BFStyleFont(Font, 18, False, BFColor('#f59e0b', clOlive))
      else
        BFStyleFont(Font, 18, False, BFColor('#cbd5e1', clSilver));
      BFDrawTextIn(Canvas, Star, Rect(X0 + (I - 1) * 32, 0, X0 + I * 32, Height), taCenter, False);
    end;
  end;
end;

procedure TBFStars.MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  X0, N: Integer;
begin
  inherited MouseUp(Button, Shift, X, Y);
  if not Enabled then
    Exit;
  X0 := (Width - 5 * 32) div 2;
  N := (X - X0) div 32 + 1;
  if (N >= 1) and (N <= 5) then
  begin
    FRating := N;
    Invalidate;
    if Assigned(FOnChange) then
      FOnChange(Self);
  end;
end;

{ ── TBFCsatPanel ───────────────────────────────────────────────────────── }

constructor TBFCsatPanel.CreateCsat(AOwner: TComponent; ACtx: TBFUIContext; const TicketId: string);
begin
  inherited Create(AOwner);
  FCtx := ACtx;
  FTicketId := TicketId;
  FVM := TBFCsatVM.Create;
  Box(BFClSurface, BFClBorder, 10, 10, 12);
  Gap := 6;
  FTitle := TBFText.Create(Self);
  FTitle.Style(9, True, BFClText);
  FTitle.Alignment := taCenter;
  FTitle.Text := FCtx.T('csat_title');
  Add(FTitle);
  FStars := TBFStars.Create(Self);
  FStars.OnChange := StarsChange;
  Add(FStars);
  FComment := TMemo.Create(Self);
  FComment.Height := 48;
  FComment.MaxLength := BF_CSAT_COMMENT_MAX;
  FComment.ScrollBars := ssVertical;
  BFStyleFont(FComment.Font, 9, False, BFClText);
  FComment.Visible := False;
  Add(FComment);
  FError := TBFText.Create(Self);
  FError.Style(8, False, BFColor('#b91c1c', clRed));
  FError.Visible := False;
  Add(FError);
  FSubmit := TBFButton.Create(Self);
  FSubmit.Accent := FCtx.Primary;
  FSubmit.ButtonHeight := 36;
  FSubmit.OnClick := SubmitClick;
  FSubmit.Visible := False;
  Add(FSubmit);
  FStatus := TBFText.Create(Self);
  FStatus.Alignment := taCenter;
  FStatus.Visible := False;
  Add(FStatus);
  Sync;
end;

destructor TBFCsatPanel.Destroy;
begin
  BFJobs.CancelOwner(Self);
  FVM.Free;
  inherited Destroy;
end;

procedure TBFCsatPanel.Sync;
var
  Done: Boolean;
begin
  Done := FVM.State in [csDone, csNotResolved];
  FTitle.Visible := not Done;
  FStars.Visible := not Done;
  FStars.Enabled := FVM.State <> csSending;
  FComment.Visible := not Done and (FVM.Rating > 0);
  FComment.ReadOnly := FVM.State = csSending;
  FSubmit.Visible := not Done and (FVM.Rating > 0);
  FSubmit.Caption := FVM.ButtonText(FCtx.Locale);
  FSubmit.Busy := FVM.State = csSending;
  FError.Visible := FVM.State = csError;
  FError.Text := FVM.ErrorText;
  FStatus.Visible := Done;
  if FVM.State = csDone then
  begin
    FStatus.Style(9, True, BFClText);
    FStatus.Text := FCtx.T('csat_thanks');
  end
  else if FVM.State = csNotResolved then
  begin
    FStatus.Style(9, False, BFClSlate600);
    FStatus.Text := FCtx.T('csat_not_resolved');
  end;
  if Parent is TBFColumn then
  begin
    Height := MeasureHeight(Width);
    TBFColumn(Parent).Relayout;
  end;
  Relayout;
end;

procedure TBFCsatPanel.StarsChange(Sender: TObject);
begin
  FVM.Rating := FStars.Rating;
  Sync;
end;

procedure TBFCsatPanel.SubmitClick(Sender: TObject);
begin
  FVM.Comment := FComment.Text;
  if not FVM.BeginSubmit then
    Exit;
  Sync;
  BFJobs.Run(FCtx.Api, SubmitWork, SubmitDone, Self,
    [FTicketId, IntToStr(FVM.Rating), FVM.Comment]);
end;

function TBFCsatPanel.SubmitWork(Job: TBFJob): TBFJson;
begin
  Job.Api.SubmitSatisfaction(Job.Arg(0), StrToIntDef(Job.Arg(1), 0), Job.Arg(2));
  Result := nil;
end;

procedure TBFCsatPanel.SubmitDone(Job: TBFJob);
var
  E: Exception;
begin
  if Job.Failed then
  begin
    E := Job.MakeError;
    try
      FVM.ApplyError(E, FCtx.Locale);
    finally
      E.Free;
    end;
  end
  else
    FVM.ApplySuccess;
  Sync;
end;

{ ── TBFChatHeader ──────────────────────────────────────────────────────── }

constructor TBFChatHeader.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  Height := 40;
  Color := clWhite;
end;

procedure TBFChatHeader.Setup(const Protocol, Title, Status: string; StatusColor, Accent: TColor;
  Avatar: TBFAvatarMode; const AvatarText: string; RightSpace: Integer);
begin
  FProtocol := Protocol;
  FTitle := Title;
  FStatus := Status;
  FStatusColor := StatusColor;
  FAccent := Accent;
  FAvatar := Avatar;
  FAvatarText := AvatarText;
  FRightSpace := RightSpace;
  Invalidate;
end;

function TBFChatHeader.MeasureHeight(AWidth: Integer): Integer;
begin
  Result := 40;
end;

procedure TBFChatHeader.Paint;
var
  X: Integer;
begin
  with Canvas do
  begin
    Brush.Color := clWhite;
    FillRect(Rect(0, 0, Width, Height));
    X := 0;
    if FAvatar in [amInitials, amBot] then
    begin
      BFDrawAvatar(Canvas, 0, 4, 32, FAvatar, FAvatarText, FAccent);
      X := 42;
    end;
    if FProtocol <> '' then
    begin
      BFStyleFont(Font, 7, True, BFClMuted);
      BFDrawTextIn(Canvas, FProtocol, Rect(X, 2, Width - FRightSpace, 18), taLeftJustify, False);
    end;
    if FTitle <> '' then
    begin
      BFStyleFont(Font, 10, True, BFClText);
      BFDrawTextIn(Canvas, FTitle, Rect(X, 18, Width - FRightSpace, 40), taLeftJustify, False);
    end
    else
    begin
      Brush.Color := FStatusColor;
      Pen.Color := FStatusColor;
      Ellipse(X, 25, X + 8, 33);
      BFStyleFont(Font, 9, True, FStatusColor);
      BFDrawTextIn(Canvas, FStatus, Rect(X + 14, 20, Width - FRightSpace, 40), taLeftJustify, False);
    end;
  end;
end;

{ ── TBFChatPage ────────────────────────────────────────────────────────── }

constructor TBFChatPage.CreateChat(AOwner: TComponent; ACtx: TBFUIContext;
  const ContinueTicketId, TicketNumber: string);
var
  Back, Cancel: TBFButton;
  Q: TBFText;
begin
  inherited CreatePage(AOwner, ACtx);
  FContinueTicketId := ContinueTicketId;
  FTicketNumber := TicketNumber;
  FFiles := TBFJson.NewArray;
  FUploadQueue := TStringList.Create;
  FLoader := TBFPreviewLoader.CreateLoader(Self, ACtx);
  FLoader.OnLoaded := PreviewLoaded;

  FHead := TBFColumn.Create(Self);
  FHead.Parent := Self;
  FHead.Align := alTop;
  FHead.Color := clWhite;
  FHead.Box(clNone, clNone, 16, 12, 0);
  Back := TBFButton.Create(Self);
  Back.Kind := bkLink;
  Back.Accent := ACtx.Primary;
  Back.Alignment := taLeftJustify;
  Back.ButtonHeight := 20;
  Back.Caption := BFFromUtf8(#$E2#$86#$90) + ' ' + ACtx.T('btn_back');
  Back.OnClick := BackClick;
  FHead.Add(Back);
  FHeader := TBFChatHeader.Create(Self);
  FHead.Add(FHeader);
  FEnd := TBFButton.Create(Self);
  FEnd.Parent := FHeader;
  FEnd.Kind := bkNeutral;
  FEnd.ButtonHeight := 30;
  FEnd.FontSize := 8;
  FEnd.Caption := ACtx.T('btn_chat_end');
  FEnd.OnClick := EndClick;
  FConfirm := TBFRow.Create(Self);
  FConfirm.RowHeight := 30;
  FConfirm.Color := BFColor('#fef2f2', clWhite);
  Q := TBFText.Create(Self);
  Q.Style(9, False, BFColor('#7f1d1d', clMaroon));
  Q.MarginY := 6;
  Q.Text := ACtx.T('chat_end_confirm');
  FConfirm.Add(Q, -1);
  Cancel := TBFButton.Create(Self);
  Cancel.Kind := bkLink;
  Cancel.Accent := BFClMuted;
  Cancel.ButtonHeight := 30;
  Cancel.Caption := ACtx.T('btn_cancel');
  Cancel.OnClick := CancelEndClick;
  FConfirm.Add(Cancel, Cancel.PreferredWidth);
  FConfirmEnd := TBFButton.Create(Self);
  FConfirmEnd.Kind := bkDanger;
  FConfirmEnd.ButtonHeight := 30;
  FConfirmEnd.FontSize := 8;
  FConfirmEnd.Caption := ACtx.T('btn_chat_end');
  FConfirmEnd.OnClick := ConfirmEndClick;
  FConfirm.Add(FConfirmEnd, FConfirmEnd.PreferredWidth);
  FConfirm.Visible := False;
  FHead.Add(FConfirm);

  FHandoff := TBFRow.Create(Self);
  FHandoff.Parent := Self;
  FHandoff.Align := alTop;
  FHandoff.RowHeight := 40;
  FHandoff.Color := BFColor('#f0f9ff', clWhite);
  FHandoff.MarginX := 12;
  FHandoffText := TBFText.Create(Self);
  FHandoffText.Style(8, False, BFColor('#075985', clNavy));
  FHandoffText.MarginY := 4;
  FHandoff.Add(FHandoffText, -1);
  FHandoffBtn := TBFButton.Create(Self);
  FHandoffBtn.Kind := bkOutline;
  FHandoffBtn.Accent := ACtx.Primary;
  FHandoffBtn.ButtonHeight := 32;
  FHandoffBtn.MarginY := 4;
  FHandoffBtn.FontSize := 8;
  FHandoffBtn.Caption := ACtx.T('btn_talk_to_human');
  FHandoffBtn.OnClick := HandoffClick;
  FHandoff.Add(FHandoffBtn, FHandoffBtn.PreferredWidth + 8);
  FHandoff.Visible := False;

  FBanner := TBFText.Create(Self);
  FBanner.Parent := Self;
  FBanner.Align := alTop;
  FBanner.Style(8, False, BFClAmberText);
  FBanner.Box(BFClAmberBg, BFClAmberBorder, 16, 6);
  FBanner.Radius := 0;
  FBanner.Alignment := taCenter;
  FBanner.Visible := False;

  FFoot := TBFColumn.Create(Self);
  FFoot.Parent := Self;
  FFoot.Align := alBottom;
  FFoot.Color := clWhite;
  FFoot.Box(clNone, clNone, 12, 10, 0);

  FStack := TBFStack.Create(Self);
  FStack.Parent := Self;
  FStack.Align := alClient;
  FStack.Content.Box(clNone, clNone, 12, 12, 0);
  FStack.Content.Gap := 6;
end;

destructor TBFChatPage.Destroy;
begin
  FFiles.Free;
  FFirstPendingFiles.Free;
  FUploadQueue.Free;
  inherited Destroy;
end;

procedure TBFChatPage.Activate;
begin
  ChatChanged;
end;

procedure TBFChatPage.Resize;
begin
  inherited Resize;
  FitAll;
end;

procedure TBFChatPage.FitAll;
begin
  FHead.Height := FHead.MeasureHeight(Width);
  FHead.Relayout;
  FEnd.SetBounds(FHeader.Width - 80, 5, 80, 30);
  FHandoff.Relayout;
  if FBanner.Visible then
    FBanner.Height := FBanner.MeasureHeight(Width);
  FFoot.Height := FFoot.MeasureHeight(Width);
  FFoot.Relayout;
  FStack.Relayout;
end;

procedure TBFChatPage.ChatChanged;
var
  Stick: Boolean;
begin
  Stick := FStack.NearBottom;
  BuildHead;
  BuildFoot;
  BuildBody;
  FitAll;
  if Stick then
    FStack.ScrollToBottom;
  if FCtx.ViewingChat then
    FCtx.Chat.MarkSeen;
  MarkRead;
end;

procedure TBFChatPage.MarkRead;
var
  Conv: TBFJson;
begin
  // Chamado visto: a lista não acende "não lido" por mensagens do chat.
  Conv := FCtx.Chat.Conversation;
  if (Conv <> nil) and (FCtx.Chat.MessageCount > 0) then
    FCtx.ReadState.MarkRead(Conv.StrOf('ticket_id'),
      FCtx.Chat.Message(FCtx.Chat.MessageCount - 1).StrOf('created_at'));
end;

procedure TBFChatPage.BuildHead;
var
  Conv, Agent, Bot: TBFJson;
  Title: string;
  Mode: TBFAvatarMode;
  AvText: string;
  Terminal, WithBot: Boolean;
begin
  Conv := FCtx.Chat.Conversation;
  if Conv = nil then
  begin
    if FContinueTicketId <> '' then Title := FCtx.T('chat_continue_title')
    else Title := FCtx.T('chat_new_title');
    if FTicketNumber <> '' then
      FHeader.Setup(FCtx.T('chat_protocol') + ' ' + FTicketNumber, Title, '', clNone,
        FCtx.Primary, amNone, '', 0)
    else
      FHeader.Setup('', Title, '', clNone, FCtx.Primary, amNone, '', 0);
    FEnd.Visible := False;
    FConfirm.Visible := False;
    FHandoff.Visible := False;
    FBanner.Visible := False;
    Exit;
  end;
  Terminal := FCtx.Chat.IsTerminal;
  WithBot := (Conv.StrOf('status') = 'bot') and not Terminal;
  Agent := Conv.ObjOf('assigned_to');
  Bot := BFBotAgent(Conv);
  Mode := amNone;
  AvText := '';
  if WithBot then
    Mode := amBot
  else if Agent <> nil then
  begin
    Mode := amInitials;
    AvText := BFInitials(Agent.StrOf('name'));
  end;
  if Bot <> nil then ;
  FHeader.Setup(FCtx.T('chat_protocol') + ' ' + Conv.StrOf('ticket_number'), '',
    BFChatStatusLabel(FCtx.Locale, Conv), BFColor(BFChatStatusColor(Conv.StrOf('status')), BFClMuted),
    FCtx.Primary, Mode, AvText, 90);
  FEnd.Visible := not Terminal and not FConfirming;
  FConfirm.Visible := FConfirming and not Terminal;
  FConfirmEnd.Busy := FEnding;
  FConfirmEnd.Enabled := not FEnding;
  // Assistente conduzindo: "falar com um atendente" sempre à vista.
  FHandoff.Visible := WithBot;
  case FHandoffState of
    2: FHandoffText.Text := FCtx.T('chat_handoff_requested');
    3: FHandoffText.Text := FCtx.T('chat_handoff_error');
  else
    FHandoffText.Text := FCtx.T('chat_bot_hint');
  end;
  FHandoffBtn.Busy := FHandoffState = 1;
  FHandoffBtn.Enabled := FHandoffState <> 1;
  FBanner.Visible := not Terminal and (FCtx.Chat.StreamStatus in [ssReconnecting, ssFailed]);
  if FCtx.Chat.StreamStatus = ssReconnecting then
    FBanner.Text := FCtx.T('chat_reconnecting')
  else
    FBanner.Text := FCtx.T('chat_connection_failed');
end;

procedure TBFChatPage.BuildBody;
var
  S: TBFChatSession;
  I: Integer;
  M, Next, Conv, Bot: TBFJson;
  B: TBFBubble;
  Mine, Grouped: Boolean;
  Meta, Author: string;
  T: TBFText;
  Item: TBFOutboxItem;
  Mode: TBFAvatarMode;
begin
  S := FCtx.Chat;
  Conv := S.Conversation;
  FLoader.ResetCards;
  FStack.Clear;
  if Conv = nil then
  begin
    // Nova conversa: apresentação (assistente quando o produto é autônomo).
    T := TBFText.Create(FStack);
    T.Style(8, False, BFClMuted);
    T.Alignment := taCenter;
    T.Box(BFClChip, clNone, 10, 6);
    T.Radius := 10;
    T.Text := BFChatIntro(FCtx.Locale, S.Availability);
    FStack.Add(T);
    if FFirstPendingHtml <> '' then
    begin
      B := TBFBubble.CreateBubble(FStack, FCtx, True, BFToUtf8(FFirstPendingHtml),
        FFirstPendingFiles, '', nil);
      B.MakePending(False, 'first', nil, nil);
      FStack.Add(B);
    end;
    if FStartError then
    begin
      T := TBFText.Create(FStack);
      T.Style(8, False, BFClDanger);
      T.Alignment := taCenter;
      T.Text := FCtx.T('error_generic');
      FStack.Add(T);
    end;
    Exit;
  end;
  Bot := BFBotAgent(Conv);
  if not S.Loaded and (S.MessageCount = 0) then
  begin
    T := TBFText.Create(FStack);
    T.Style(9, False, FCtx.Primary);
    T.Alignment := taCenter;
    T.MarginY := 24;
    T.Text := FCtx.T('loading');
    FStack.Add(T);
  end;
  for I := 0 to S.MessageCount - 1 do
  begin
    M := S.Message(I);
    if I + 1 < S.MessageCount then Next := S.Message(I + 1) else Next := nil;
    if M.StrOf('author_kind') = 'system' then
    begin
      B := TBFBubble.CreateBubble(FStack, FCtx, False, M.Utf8Of('content'), nil, '', nil);
      B.MakeSystem;
      FStack.Add(B);
      Continue;
    end;
    Mine := BFChatIsMine(M);
    // Mensagens seguidas do mesmo autor em 2 min: rodapé e avatar só na última.
    Grouped := BFChatGroupedWithNext(M, Next);
    Author := BFChatAuthorName(FCtx.Locale, M, Conv);
    if Grouped then
      Meta := ''
    else
      Meta := Author + ' ' + BFFromUtf8(#$C2#$B7) + ' ' + BFFormatChatTime(M.StrOf('created_at'));
    B := TBFBubble.CreateBubble(FStack, FCtx, Mine, M.Utf8Of('content'), M.ArrOf('attachments'),
      Meta, FLoader);
    if not Mine then
    begin
      if Grouped then
        Mode := amEmpty
      else if M.StrOf('author_kind') = 'bot' then
        Mode := amBot
      else
        Mode := amInitials;
      B.SetAvatar(Mode, BFInitials(M.StrOf('author_name')));
    end;
    FStack.Add(B);
  end;
  if Bot <> nil then ;
  for I := 0 to S.OutboxCount - 1 do
  begin
    Item := S.OutboxItem(I);
    B := TBFBubble.CreateBubble(FStack, FCtx, True, BFToUtf8(Item.ContentHtml), Item.Attachments,
      '', nil);
    B.MakePending(Item.State = obFailed, Item.TempId, RetryClick, DiscardClick);
    FStack.Add(B);
  end;
  if S.IsTerminal then
  begin
    T := TBFText.Create(FStack);
    T.Style(8, False, BFClMuted);
    T.Alignment := taCenter;
    T.Box(BFClChip, clNone, 10, 6);
    T.Radius := 10;
    T.Text := FCtx.T('chat_closed_notice');
    FStack.Add(T);
  end;
end;

procedure TBFChatPage.BuildFoot;
var
  Mode: TBFFootMode;
begin
  if FCtx.Chat.IsTerminal then Mode := fmTerminal else Mode := fmComposer;
  // O composer só é refeito quando o modo muda (preserva o texto digitado).
  if (Mode = FFootMode) and (FFootConvId = FCtx.Chat.ConversationId) then
  begin
    UpdateComposerState;
    Exit;
  end;
  FFootMode := Mode;
  FFootConvId := FCtx.Chat.ConversationId;
  FFoot.ClearItems;
  FMemo := nil;
  FSend := nil;
  FAttach := nil;
  FChips := nil;
  FUploadError := nil;
  if Mode = fmTerminal then
    BuildTerminal
  else
    BuildComposer;
end;

procedure TBFChatPage.BuildComposer;
var
  Row: TBFRow;
begin
  FChips := TBFColumn.Create(Self);
  FChips.Color := clWhite;
  FChips.Gap := 4;
  FFoot.Add(FChips);
  Row := TBFRow.Create(Self);
  Row.RowHeight := 56;
  Row.Color := clWhite;
  FAttach := TBFButton.Create(Self);
  FAttach.Kind := bkNeutral;
  FAttach.ButtonHeight := 36;
  FAttach.MarginY := 10;
  FAttach.Caption := BFGlyph(#$F0#$9F#$93#$8E, '+');
  FAttach.Hint := FCtx.T('btn_attach_file');
  FAttach.ShowHint := True;
  FAttach.OnClick := AttachClick;
  Row.Add(FAttach, 36);
  FMemo := TMemo.Create(Self);
  FMemo.WordWrap := True;
  FMemo.ScrollBars := ssVertical;
  FMemo.OnKeyDown := MemoKeyDown;
  FMemo.OnKeyPress := MemoKeyPress;
  FMemo.OnChange := MemoChange;
  BFStyleFont(FMemo.Font, 10, False, BFClText);
{$IFDEF BF_FPC}
  FMemo.TextHint := FCtx.T('chat_placeholder');
{$ENDIF}
  Row.Add(FMemo, -1);
  FSend := TBFButton.Create(Self);
  FSend.Accent := FCtx.Primary;
  FSend.ButtonHeight := 36;
  FSend.MarginY := 10;
  FSend.Caption := BFGlyph(#$E2#$9E#$A4, '>');
  FSend.Hint := FCtx.T('btn_send');
  FSend.ShowHint := True;
  FSend.OnClick := SendClick;
  Row.Add(FSend, 36);
  FFoot.Add(Row);
  FUploadError := TBFText.Create(Self);
  FUploadError.Style(8, False, BFClDanger);
  FUploadError.Visible := False;
  FFoot.Add(FUploadError);
  RebuildChips;
  UpdateComposerState;
end;

procedure TBFChatPage.BuildTerminal;
var
  Conv: TBFJson;
  Outcome: TBFClosingOutcome;
  Box: TBFColumn;
  T: TBFText;
  B: TBFButton;
begin
  Conv := FCtx.Chat.Conversation;
  Outcome := BFClosingOutcome(Conv);
  if Outcome = coCsat then
    FFoot.Add(TBFCsatPanel.CreateCsat(Self, FCtx, Conv.StrOf('ticket_id')));
  if Outcome = coFollowUp then
  begin
    Box := TBFColumn.Create(Self);
    Box.Box(BFMix(FCtx.Primary, clWhite, 0.06), BFMix(FCtx.Primary, clWhite, 0.28), 12, 12, 12);
    T := TBFText.Create(Self);
    T.Style(9, False, BFClText);
    T.Text := BFFill(FCtx.T('chat_followup_notice'), 'n', Conv.StrOf('ticket_number'));
    Box.Add(T);
    B := TBFButton.Create(Self);
    B.Accent := FCtx.Primary;
    B.ButtonHeight := 40;
    B.Caption := FCtx.T('btn_view_ticket');
    B.OnClick := ViewTicketClick;
    Box.Add(B);
    FFoot.Add(Box);
  end;
  // Sempre há "continuar conversa", ligada ao mesmo chamado.
  B := TBFButton.Create(Self);
  B.Kind := bkOutline;
  B.Accent := FCtx.Primary;
  B.ButtonHeight := 40;
  B.Caption := FCtx.T('btn_chat_continue');
  B.OnClick := ContinueClick;
  FFoot.Add(B);
  if Outcome <> coFollowUp then
  begin
    B := TBFButton.Create(Self);
    B.Kind := bkLink;
    B.Accent := BFClMuted;
    B.Alignment := taCenter;
    B.ButtonHeight := 22;
    B.FontSize := 8;
    B.Caption := FCtx.T('btn_view_ticket') + ' ' + Conv.StrOf('ticket_number');
    B.OnClick := ViewTicketClick;
    FFoot.Add(B);
  end;
end;

procedure TBFChatPage.RebuildChips;
var
  I: Integer;
  Row: TBFRow;
  T: TBFText;
  X: TBFButton;
  A: TBFJson;
begin
  if FChips = nil then
    Exit;
  FChips.ClearItems;
  for I := 0 to FFiles.Count - 1 do
  begin
    A := FFiles.Item(I);
    Row := TBFRow.Create(Self);
    Row.RowHeight := 24;
    Row.Color := clWhite;
    T := TBFText.Create(Self);
    T.Style(8, False, BFClText);
    T.Box(BFClChip, BFColor('#cbd5e1', clSilver), 8, 3);
    T.Radius := 20;
    T.Text := BFAttachmentIcon(A.StrOf('content_type')) + ' ' + A.StrOf('filename');
    Row.Add(T, -1);
    X := TBFButton.Create(Self);
    X.Kind := bkLink;
    X.Accent := BFClMuted;
    X.ButtonHeight := 24;
    X.Tag := I;
    X.Caption := BFGlyph(#$E2#$9C#$95, 'x');
    X.Hint := FCtx.T('btn_remove');
    X.OnClick := RemoveFileClick;
    Row.Add(X, 24);
    FChips.Add(Row);
  end;
  FChips.Visible := FFiles.Count > 0;
  FitAll;
end;

procedure TBFChatPage.UpdateComposerState;
var
  HasText: Boolean;
begin
  if FSend = nil then
    Exit;
  HasText := (FMemo <> nil) and (Trim(FMemo.Text) <> '');
  FSend.Enabled := (FFirstPendingHtml = '') and not FUploading and (HasText or (FFiles.Count > 0));
  FAttach.Busy := FUploading;
  if FMemo <> nil then
    FMemo.Enabled := FFirstPendingHtml = '';
end;

procedure TBFChatPage.MemoChange(Sender: TObject);
begin
  UpdateComposerState;
end;

procedure TBFChatPage.MemoKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  // Enter envia; Shift+Enter quebra a linha.
  FSwallowEnter := False;
  if (Key = 13) and not (ssShift in Shift) then
  begin
    FSwallowEnter := True;
    Key := 0;
    SendClick(nil);
  end;
end;

procedure TBFChatPage.MemoKeyPress(Sender: TObject; var Key: Char);
begin
  if (Key = #13) and FSwallowEnter then
  begin
    Key := #0;
    FSwallowEnter := False;
  end;
end;

procedure TBFChatPage.SendClick(Sender: TObject);
var
  Html: string;
begin
  if (FMemo = nil) or (FSend = nil) or not FSend.Enabled then
    Exit;
  Html := BFTextToHtml(FMemo.Text);
  if (Html = '') and (FFiles.Count = 0) then
    Exit;
  if FCtx.Chat.Conversation = nil then
  begin
    FStartError := False;
    FFirstPendingHtml := Html;
    FreeAndNil(FFirstPendingFiles);
    FFirstPendingFiles := FFiles.Clone;
    FCtx.ChatStart(Html, FFiles.Clone, FContinueTicketId);
    ChatChanged;
    Exit;
  end;
  FCtx.ChatSend(Html, FFiles.Clone);
  FMemo.Clear;
  FFiles.Clear;
  RebuildChips;
  FStack.ScrollToBottom;
  ChatChanged;
  FStack.ScrollToBottom;
end;

procedure TBFChatPage.ChatStartFinished(R: TBFStartResult);
var
  Html: string;
  Files: TBFJson;
begin
  Html := FFirstPendingHtml;
  FFirstPendingHtml := '';
  case R of
    srOk:
      begin
        if FMemo <> nil then
          FMemo.Clear;
        FFiles.Clear;
        FreeAndNil(FFirstPendingFiles);
        RebuildChips;
      end;
    srOffline:
      begin
        // 409 CHAT_OFFLINE: formulário de chamado com o texto já digitado.
        Files := FFirstPendingFiles;
        FFirstPendingFiles := nil;
        FCtx.GoNew(Html, Files, FCtx.T('chat_offline_fallback'));
        Files.Free;
        Exit;
      end;
  else
    FStartError := True;
  end;
  ChatChanged;
end;

procedure TBFChatPage.ChatCloseFinished(Ok: Boolean);
begin
  FEnding := False;
  if Ok then
    FConfirming := False;
  ChatChanged;
end;

procedure TBFChatPage.ChatHandoffFinished(Code: Integer);
begin
  if Code = 2 then FHandoffState := 3 else FHandoffState := 2;
  ChatChanged;
end;

procedure TBFChatPage.BackClick(Sender: TObject);
begin
  if FCtx.Chat.IsTerminal then
    FCtx.ChatReset;
  FCtx.GoList;
end;

procedure TBFChatPage.EndClick(Sender: TObject);
begin
  FConfirming := True;
  ChatChanged;
end;

procedure TBFChatPage.CancelEndClick(Sender: TObject);
begin
  FConfirming := False;
  ChatChanged;
end;

procedure TBFChatPage.ConfirmEndClick(Sender: TObject);
begin
  if FEnding then
    Exit;
  FEnding := True;
  ChatChanged;
  FCtx.ChatCloseConversation;
end;

procedure TBFChatPage.HandoffClick(Sender: TObject);
begin
  FHandoffState := 1;
  ChatChanged;
  FCtx.ChatHandoff;
end;

procedure TBFChatPage.RetryClick(Sender: TObject);
begin
  FCtx.ChatRetry(TBFBubble(Sender).TempId);
end;

procedure TBFChatPage.DiscardClick(Sender: TObject);
begin
  FCtx.ChatDiscard(TBFBubble(Sender).TempId);
end;

procedure TBFChatPage.ContinueClick(Sender: TObject);
var
  Conv: TBFJson;
  Id, Num: string;
begin
  // Nova conversa ligada ao mesmo chamado (continue_ticket_id).
  Conv := FCtx.Chat.Conversation;
  Id := Conv.StrOf('ticket_id');
  Num := Conv.StrOf('ticket_number');
  FCtx.ChatReset;
  FCtx.GoChat(Id, Num);
end;

procedure TBFChatPage.ViewTicketClick(Sender: TObject);
var
  Id: string;
begin
  Id := FCtx.Chat.Conversation.StrOf('ticket_id');
  if FCtx.Chat.IsTerminal then
    FCtx.ChatReset;
  FCtx.GoDetail(Id);
end;

procedure TBFChatPage.PreviewLoaded(Sender: TObject);
begin
  FStack.Relayout;
end;

procedure TBFChatPage.AttachClick(Sender: TObject);
var
  Files: TStringList;
begin
  Files := TStringList.Create;
  try
    if BFPickFiles(True, Files) then
      StartUploads(Files);
  finally
    Files.Free;
  end;
end;

procedure TBFChatPage.DropFiles(Files: TStrings);
begin
  if FFootMode = fmComposer then
    StartUploads(Files);
end;

procedure TBFChatPage.StartUploads(Files: TStrings);
var
  I: Integer;
begin
  for I := 0 to Files.Count - 1 do
    if FFiles.Count + FUploadQueue.Count < BF_CHAT_MAX_FILES then
      FUploadQueue.Add(Files[I]);
  if FUploadError <> nil then
    FUploadError.Visible := False;
  NextUpload;
end;

procedure TBFChatPage.NextUpload;
begin
  if FUploading or (FUploadQueue.Count = 0) then
  begin
    UpdateComposerState;
    Exit;
  end;
  FUploading := True;
  UpdateComposerState;
  Run(UploadWork, UploadDone, [FUploadQueue[0]]);
  FUploadQueue.Delete(0);
end;

function TBFChatPage.UploadWork(Job: TBFJob): TBFJson;
begin
  Result := Job.Api.UploadFile(Job.Arg(0));
end;

procedure TBFChatPage.UploadDone(Job: TBFJob);
var
  R, A: TBFJson;
begin
  FUploading := False;
  if Job.Failed then
  begin
    if FUploadError <> nil then
    begin
      FUploadError.Text := FCtx.T('error_generic');
      FUploadError.Visible := True;
    end;
  end
  else
  begin
    R := Job.TakeData;
    try
      if R <> nil then
      begin
        A := FFiles.Add(TBFJson.NewObject);
        A.PutUtf8('url', R.Utf8Of('url'));
        A.PutUtf8('filename', R.Utf8Of('filename'));
        A.PutInt('size', R.IntOf('size'));
        A.PutUtf8('content_type', R.Utf8Of('mime'));
      end;
    finally
      R.Free;
    end;
  end;
  RebuildChips;
  NextUpload;
end;

procedure TBFChatPage.RemoveFileClick(Sender: TObject);
begin
  FFiles.Delete(TComponent(Sender).Tag);
  RebuildChips;
  UpdateComposerState;
end;

end.
