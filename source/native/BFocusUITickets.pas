unit BFocusUITickets;

{ Chamados na UI nativa (behavior spec §3): lista (status com cores dos tokens, "não
  lido" com a regra do web e leitura local, cartão do chat, splash de novidades), novo
  chamado (tipo, prioridade, departamento, título ≤ 500, descrição, anexos) e detalhe
  (conversa, anexos com download, conversa do chat recolhível, reabrir ao responder um
  resolvido, fechado sem caixa de resposta). }

{$I BFocusDefines.inc}

interface

uses
  SysUtils, Classes, Controls, Forms, Graphics, StdCtrls, ExtCtrls, BFocusText, BFocusJson,
  BFocusApi, BFocusAsync, BFocusFormat, BFocusVMTickets, BFocusVMChat, BFocusUIControls,
  BFocusUIContext, BFocusUIChat, BFocusUIReleaseNotes, BFocusGraphics, BFocusTokens;

const
  BF_LIST_REFRESH_MS = 30000;
  BF_DETAIL_REFRESH_MS = 30000;

type
  { Linha da lista: número, pílula de status, título e data; não lido em destaque. }
  TBFTicketRow = class(TCustomControl, IBFMeasurable)
  private
    FNumber, FTitle, FStatus, FDate, FTicketId: string;
    FStatusColor, FPrimary: TColor;
    FUnread: Boolean;
  protected
    procedure Paint; override;
  public
    constructor Create(AOwner: TComponent); override;
    procedure Setup(const ATicketId, ANumber, ATitle, AStatus, ADate: string;
      AStatusColor, APrimary: TColor; AUnread: Boolean);
    function MeasureHeight(AWidth: Integer): Integer;
    property TicketId: string read FTicketId;
    property OnClick;
  end;

  TBFListPage = class(TBFPage)
  private
    FVM: TBFTicketListVM;
    FStack: TBFStack;
    FSplash: TBFSplashPanel;
    FTimer: TTimer;
    FAvailTimer: TTimer;
    procedure Build;
    procedure Load;
    function ListWork(Job: TBFJob): TBFJson;
    procedure ListDone(Job: TBFJob);
    procedure TimerTick(Sender: TObject);
    procedure AvailTick(Sender: TObject);
    procedure RowClick(Sender: TObject);
    procedure NewClick(Sender: TObject);
    procedure RetryClick(Sender: TObject);
    procedure ChatStartClick(Sender: TObject);
    procedure ChatResumeClick(Sender: TObject);
    function ShowChatCard: Boolean;
    procedure SplashVisibility(Sender: TObject);
  public
    constructor CreatePage(AOwner: TComponent; ACtx: TBFUIContext); override;
    destructor Destroy; override;
    procedure Activate; override;
    procedure Deactivate; override;
    procedure VisibilityChanged(AVisible: Boolean); override;
    procedure WindowActivated; override;
    procedure ChatChanged; override;
  end;

  TBFNewTicketPage = class(TBFPage)
  private
    FVM: TBFNewTicketVM;
    FHead: TBFColumn;
    FStack: TBFStack;
    FFoot: TBFColumn;
    FTypes: TBFChipBar;
    FPriorities: TBFChipBar;
    FDept: TComboBox;
    FTitle: TEdit;
    FEditor: TBFEditor;
    FUploads: TBFColumn;
    FAttach: TBFButton;
    FUploadError: TBFText;
    FCreate: TBFButton;
    FCreateError: TBFText;
    FQueue: TStringList;
    procedure BackClick(Sender: TObject);
    procedure TypeChange(Sender: TObject);
    procedure PriorityChange(Sender: TObject);
    procedure TitleChange(Sender: TObject);
    procedure AttachClick(Sender: TObject);
    procedure RemoveClick(Sender: TObject);
    procedure CreateClick(Sender: TObject);
    procedure RebuildUploads;
    procedure Sync;
    procedure NextUpload;
    function UploadWork(Job: TBFJob): TBFJson;
    procedure UploadDone(Job: TBFJob);
    function CreateWork(Job: TBFJob): TBFJson;
    procedure CreateDone(Job: TBFJob);
    function Lbl(const Text: string): TBFText;
  protected
    procedure Resize; override;
  public
    constructor CreateNewTicket(AOwner: TComponent; ACtx: TBFUIContext;
      const PrefillHtml: string; Attachments: TBFJson; const Notice: string);
    destructor Destroy; override;
    procedure DropFiles(Files: TStrings); override;
  end;

  TBFDetailPage = class(TBFPage)
  private
    FVM: TBFTicketDetailVM;
    FHead: TBFColumn;
    FHeadInfo: TBFText;
    FHeadTitle: TBFText;
    FHeadStatus: TBFText;
    FContinuation: TBFButton;
    FStack: TBFStack;
    FFoot: TBFColumn;
    FEditor: TBFEditor;
    FPending: TBFJson;
    FPendingCol: TBFColumn;
    FAttach: TBFButton;
    FSend: TBFButton;
    FSendError: TBFText;
    FUploading: Boolean;
    FTimer: TTimer;
    FLoader: TBFPreviewLoader;
    FFootBuiltFor: string;
    procedure Load;
    procedure LoadConversations;
    function TicketWork(Job: TBFJob): TBFJson;
    procedure TicketDone(Job: TBFJob);
    function ConvWork(Job: TBFJob): TBFJson;
    procedure ConvDone(Job: TBFJob);
    procedure Build;
    procedure BuildFoot;
    procedure RebuildPending;
    procedure SyncFoot;
    procedure FitAll;
    procedure BackClick(Sender: TObject);
    procedure ContinuationClick(Sender: TObject);
    procedure ConvToggle(Sender: TObject);
    procedure ConvRetryClick(Sender: TObject);
    procedure AttachClick(Sender: TObject);
    procedure RemovePendingClick(Sender: TObject);
    procedure SendClick(Sender: TObject);
    procedure EditorChange(Sender: TObject);
    procedure TimerTick(Sender: TObject);
    procedure PreviewLoaded(Sender: TObject);
    function UploadWork(Job: TBFJob): TBFJson;
    procedure UploadDone(Job: TBFJob);
    function SendWork(Job: TBFJob): TBFJson;
    procedure SendDone(Job: TBFJob);
  protected
    procedure Resize; override;
  public
    constructor CreateDetail(AOwner: TComponent; ACtx: TBFUIContext; const TicketId: string);
    destructor Destroy; override;
    procedure Activate; override;
    procedure Deactivate; override;
    procedure VisibilityChanged(AVisible: Boolean); override;
    procedure DropFiles(Files: TStrings); override;
  end;

implementation

function BackCaption(Ctx: TBFUIContext): string;
begin
  Result := BFFromUtf8(#$E2#$86#$90) + ' ' + Ctx.T('btn_back'); // ← Voltar
end;

function NewBackButton(AOwner: TComponent; Ctx: TBFUIContext; OnClick: TNotifyEvent): TBFButton;
begin
  Result := TBFButton.Create(AOwner);
  Result.Kind := bkLink;
  Result.Accent := Ctx.Primary;
  Result.Alignment := taLeftJustify;
  Result.ButtonHeight := 20;
  Result.Caption := BackCaption(Ctx);
  Result.OnClick := OnClick;
end;

function NewTimer(AOwner: TComponent; Interval: Integer; OnTimer: TNotifyEvent): TTimer;
begin
  Result := TTimer.Create(AOwner);
  Result.Enabled := False;
  Result.Interval := Interval;
  Result.OnTimer := OnTimer;
end;

{ ── TBFTicketRow ───────────────────────────────────────────────────────── }

constructor TBFTicketRow.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  Cursor := crHandPoint;
  Height := 76;
end;

procedure TBFTicketRow.Setup(const ATicketId, ANumber, ATitle, AStatus, ADate: string;
  AStatusColor, APrimary: TColor; AUnread: Boolean);
begin
  FTicketId := ATicketId;
  FNumber := ANumber;
  FTitle := ATitle;
  FStatus := AStatus;
  FDate := ADate;
  FStatusColor := AStatusColor;
  FPrimary := APrimary;
  FUnread := AUnread;
end;

function TBFTicketRow.MeasureHeight(AWidth: Integer): Integer;
var
  F: TFont;
begin
  F := TFont.Create;
  try
    BFStyleFont(F, 10, True, clBlack);
    Result := 12 + 18 + BFTextHeight(F, FTitle, AWidth - 28) + 4 + 16 + 12;
  finally
    F.Free;
  end;
end;

procedure TBFTicketRow.Paint;
var
  R: TRect;
  TitleH, Right: Integer;
begin
  with Canvas do
  begin
    Brush.Color := BFClSurface;
    FillRect(Rect(0, 0, Width, Height));
    // Não lido: fundo levemente na cor da marca, borda na cor primária e ponto.
    if FUnread then
    begin
      Brush.Color := BFMix(FPrimary, clWhite, 0.03);
      Pen.Color := BFMix(FPrimary, clWhite, 0.31);
    end
    else
    begin
      Brush.Color := clWhite;
      Pen.Color := BFClBorder;
    end;
    RoundRect(0, 0, Width, Height, 12, 12);
    Right := Width - 14;
    if FUnread then
    begin
      Brush.Color := FPrimary;
      Pen.Color := FPrimary;
      Ellipse(Width - 20, 12, Width - 12, 20);
      Right := Width - 30;
    end;
    BFStyleFont(Font, 7, True, BFClMuted);
    BFDrawTextIn(Canvas, FNumber, Rect(14, 12, Right - 90, 28), taLeftJustify, False);
    BFDrawPill(Canvas, Right, 11, FStatus, FStatusColor, True);
    if FUnread then
      BFStyleFont(Font, 10, True, BFClText)
    else
      BFStyleFont(Font, 10, False, BFClText);
    TitleH := BFTextHeight(Font, FTitle, Width - 28);
    R := Rect(14, 30, Width - 14, 30 + TitleH);
    BFDrawTextIn(Canvas, FTitle, R, taLeftJustify, True);
    if FUnread then
      BFStyleFont(Font, 7, True, FPrimary)
    else
      BFStyleFont(Font, 7, False, BFClSubtle);
    BFDrawTextIn(Canvas, FDate, Rect(14, 34 + TitleH, Width - 14, Height - 6), taLeftJustify, False);
  end;
end;

{ ── TBFListPage ────────────────────────────────────────────────────────── }

constructor TBFListPage.CreatePage(AOwner: TComponent; ACtx: TBFUIContext);
begin
  inherited CreatePage(AOwner, ACtx);
  FVM := TBFTicketListVM.Create(ACtx.ReadState, ACtx.Locale);
  FStack := TBFStack.Create(Self);
  FStack.Parent := Self;
  FStack.Align := alClient;
  FStack.Content.Box(clNone, clNone, 12, 16, 0);
  FSplash := TBFSplashPanel.CreateSplash(Self, ACtx);
  FSplash.Parent := Self;
  FSplash.Align := alClient;
  FSplash.OnVisibility := SplashVisibility;
  FTimer := NewTimer(Self, BF_LIST_REFRESH_MS, TimerTick);
  FAvailTimer := NewTimer(Self, BF_CHAT_AVAILABILITY_MS, AvailTick);
end;

destructor TBFListPage.Destroy;
begin
  FVM.Free;
  inherited Destroy;
end;

procedure TBFListPage.Activate;
begin
  Build;
  Load;
  FTimer.Enabled := True;
  FSplash.Start;
  if FCtx.ChatEnabled and not FCtx.Chat.HasOpenConversation then
    FCtx.RefreshAvailability;
  FAvailTimer.Enabled := FCtx.ChatEnabled;
end;

procedure TBFListPage.Deactivate;
begin
  FTimer.Enabled := False;
  FAvailTimer.Enabled := False;
  FSplash.Stop;
end;

procedure TBFListPage.VisibilityChanged(AVisible: Boolean);
begin
  FTimer.Enabled := AVisible;
  FAvailTimer.Enabled := AVisible and FCtx.ChatEnabled;
  if AVisible then
  begin
    FSplash.WidgetReopened;
    Load;
  end;
end;

procedure TBFListPage.WindowActivated;
begin
  // Release com ciência publicada enquanto a janela estava sem foco trava na hora.
  FSplash.Refresh;
end;

procedure TBFListPage.SplashVisibility(Sender: TObject);
begin
  // Coberta pelo splash, a lista não recebe foco nem teclado (não se escapa da ciência).
  FStack.Enabled := not FSplash.Visible;
end;

procedure TBFListPage.ChatChanged;
begin
  Build;
end;

function TBFListPage.ShowChatCard: Boolean;
begin
  Result := FCtx.ChatEnabled and (FCtx.Chat.HomeMode(True) <> hmHidden);
end;

procedure TBFListPage.Load;
begin
  Run(ListWork, ListDone, []);
end;

procedure TBFListPage.TimerTick(Sender: TObject);
begin
  if FCtx.Visible then
    Load;
end;

procedure TBFListPage.AvailTick(Sender: TObject);
begin
  // Disponibilidade só na tela inicial e sem conversa aberta (30 s).
  if FCtx.Visible and FCtx.ChatEnabled and not FCtx.Chat.HasOpenConversation then
    FCtx.RefreshAvailability;
end;

function TBFListPage.ListWork(Job: TBFJob): TBFJson;
begin
  Result := Job.Api.ListTickets;
end;

procedure TBFListPage.ListDone(Job: TBFJob);
begin
  if Job.Failed then
  begin
    if FCtx.CheckIdentity(Job) then
      Exit;
    FVM.ApplyError;
  end
  else
  begin
    FVM.ApplyList(Job.TakeData);
    // Badge do botão com o widget aberto = não lidos (bfocus:unread).
    FCtx.ReportUnread(FVM.UnreadCount);
  end;
  Build;
end;

procedure TBFListPage.Build;
var
  I: Integer;
  T: TBFJson;
  Row: TBFTicketRow;
  Txt: TBFText;
  B: TBFButton;
  Card: TBFChatCard;
  Chat: Boolean;
begin
  FStack.Clear;
  Chat := ShowChatCard;
  if Chat then
  begin
    Card := TBFChatCard.CreateCard(FStack, FCtx, FCtx.Chat.HomeMode(True));
    Card.OnStart := ChatStartClick;
    Card.OnResume := ChatResumeClick;
    Card.OnNewTicket := NewClick;
    FStack.Add(Card);
    Txt := TBFText.Create(FStack);
    Txt.Style(8, True, BFClSlate600);
    Txt.Text := FCtx.T('tab_list');
    FStack.Add(Txt);
  end
  else
  begin
    // O botão "Abrir chamado" some quando o cartão do chat aparece.
    B := TBFButton.Create(FStack);
    B.Accent := FCtx.Primary;
    B.ButtonHeight := 42;
    B.Caption := '+ ' + FCtx.T('btn_new_ticket');
    B.OnClick := NewClick;
    FStack.Add(B);
  end;
  if not FVM.Loaded and FVM.Loading then
  begin
    Txt := TBFText.Create(FStack);
    Txt.Style(9, False, FCtx.Primary);
    Txt.Alignment := taCenter;
    Txt.MarginY := 24;
    Txt.Text := FCtx.T('loading');
    FStack.Add(Txt);
  end
  else if FVM.Failed then
  begin
    Txt := TBFText.Create(FStack);
    Txt.Style(9, False, BFClMuted);
    Txt.Alignment := taCenter;
    Txt.MarginY := 16;
    Txt.Text := FCtx.T('error_load');
    FStack.Add(Txt);
    B := TBFButton.Create(FStack);
    B.Kind := bkNeutral;
    B.ButtonHeight := 32;
    B.Caption := BFFromUtf8(#$E2#$86#$BB); // ↻
    B.OnClick := RetryClick;
    FStack.Add(B);
  end
  else if FVM.IsEmpty then
  begin
    Txt := TBFText.Create(FStack);
    Txt.Style(10, True, BFClMuted);
    Txt.Alignment := taCenter;
    Txt.MarginY := 4;
    Txt.Text := BFGlyph(#$F0#$9F#$92#$AC, '') + sLineBreak + FCtx.T('empty_state_title');
    FStack.Add(Txt);
    Txt := TBFText.Create(FStack);
    Txt.Style(8, False, BFClMuted);
    Txt.Alignment := taCenter;
    Txt.Text := FCtx.T('empty_state_desc');
    FStack.Add(Txt);
  end
  else
    for I := 0 to FVM.Count - 1 do
    begin
      T := FVM.Ticket(I);
      Row := TBFTicketRow.Create(FStack);
      Row.Setup(T.StrOf('id'), T.StrOf('ticket_number'), T.StrOf('title'), FVM.StatusText(I),
        FVM.DateText(I), BFColor(FVM.StatusColor(I), BFClMuted), FCtx.Primary, FVM.IsUnread(I));
      Row.OnClick := RowClick;
      FStack.Add(Row);
    end;
  FStack.Relayout;
end;

procedure TBFListPage.RowClick(Sender: TObject);
var
  Id: string;
  Conv: TBFJson;
begin
  Id := TBFTicketRow(Sender).TicketId;
  Conv := FCtx.Chat.Conversation;
  // O chamado da conversa em andamento abre direto no chat.
  if (Conv <> nil) and FCtx.Chat.HasOpenConversation and (Conv.StrOf('ticket_id') = Id) then
    FCtx.GoChat('', '')
  else
    FCtx.GoDetail(Id);
end;

procedure TBFListPage.NewClick(Sender: TObject);
begin
  FCtx.GoNew('', nil, '');
end;

procedure TBFListPage.RetryClick(Sender: TObject);
begin
  FVM.Loading := True;
  Build;
  Load;
end;

procedure TBFListPage.ChatStartClick(Sender: TObject);
begin
  if FCtx.Chat.IsTerminal then
    FCtx.ChatReset;
  FCtx.GoChat('', '');
end;

procedure TBFListPage.ChatResumeClick(Sender: TObject);
begin
  FCtx.GoChat('', '');
end;

{ ── TBFNewTicketPage ───────────────────────────────────────────────────── }

constructor TBFNewTicketPage.CreateNewTicket(AOwner: TComponent; ACtx: TBFUIContext;
  const PrefillHtml: string; Attachments: TBFJson; const Notice: string);
var
  I: Integer;
  Txt: TBFText;
  Row: TBFRow;
begin
  inherited CreatePage(AOwner, ACtx);
  FVM := TBFNewTicketVM.Create(ACtx.WidgetConfig, ACtx.Locale);
  FQueue := TStringList.Create;
  if (PrefillHtml <> '') or (Notice <> '') or (Attachments <> nil) then
    FVM.ApplyPrefill(PrefillHtml, Attachments, Notice);

  FHead := TBFColumn.Create(Self);
  FHead.Parent := Self;
  FHead.Align := alTop;
  FHead.Color := clWhite;
  FHead.Box(clNone, clNone, 16, 12, 0);
  FHead.Add(NewBackButton(Self, ACtx, BackClick));

  FFoot := TBFColumn.Create(Self);
  FFoot.Parent := Self;
  FFoot.Align := alBottom;
  FFoot.Color := clWhite;
  FFoot.Box(clNone, clNone, 12, 12, 0);
  FCreate := TBFButton.Create(Self);
  FCreate.Accent := ACtx.Primary;
  FCreate.ButtonHeight := 42;
  FCreate.Caption := ACtx.T('btn_create');
  FCreate.OnClick := CreateClick;
  FFoot.Add(FCreate);
  FCreateError := TBFText.Create(Self);
  FCreateError.Style(8, False, BFClDanger);
  FCreateError.Alignment := taCenter;
  FCreateError.Text := ACtx.T('error_generic');
  FCreateError.Visible := False;
  FFoot.Add(FCreateError);

  FStack := TBFStack.Create(Self);
  FStack.Parent := Self;
  FStack.Align := alClient;
  FStack.Content.Box(clNone, clNone, 16, 16, 0);
  FStack.Content.Gap := 6;

  if FVM.Notice <> '' then
  begin
    Txt := TBFText.Create(FStack);
    Txt.Style(8, False, BFClAmberText);
    Txt.Box(BFClAmberBg, BFClAmberBorder, 12, 10);
    Txt.Text := FVM.Notice;
    FStack.Add(Txt);
  end;
  FStack.Add(Lbl(ACtx.T('new_step_title')));
  FTypes := TBFChipBar.Create(FStack);
  for I := 0 to FVM.TypeCount - 1 do
    FTypes.AddChip(FVM.TypeAt(I), FVM.TypeLabel(FVM.TypeAt(I)), ACtx.Primary);
  FTypes.Selected := FVM.TypeName;
  FTypes.OnChange := TypeChange;
  FStack.Add(FTypes);
  FStack.Add(Lbl(ACtx.T('new_step_priority')));
  FPriorities := TBFChipBar.Create(FStack);
  for I := 0 to High(BF_PRIORITIES) do
    FPriorities.AddChip(BF_PRIORITIES[I], FVM.PriorityLabel(BF_PRIORITIES[I]),
      BFColor(FVM.PriorityColor(BF_PRIORITIES[I]), BFClMuted));
  FPriorities.Selected := FVM.Priority;
  FPriorities.OnChange := PriorityChange;
  FStack.Add(FPriorities);
  // Departamento só quando há mais de um.
  if FVM.ShowDepartments then
  begin
    FStack.Add(Lbl(ACtx.T('new_field_department')));
    Txt := TBFText.Create(FStack);
    Txt.Style(7, False, BFClMuted);
    Txt.Text := ACtx.T('new_field_department_hint');
    FStack.Add(Txt);
    Row := TBFRow.Create(FStack);
    Row.RowHeight := 28;
    Row.Color := BFClSurface;
    FDept := TComboBox.Create(Self);
    FDept.Style := csDropDownList;
    Row.Add(FDept, -1);
    FStack.Add(Row);
    FDept.Items.Add(ACtx.T('new_field_department_any'));
    FDept.ItemIndex := 0;
    for I := 0 to FVM.DepartmentCount - 1 do
    begin
      FDept.Items.Add(FVM.DepartmentName(I));
      if FVM.DepartmentId_(I) = FVM.DepartmentId then
        FDept.ItemIndex := I + 1;
    end;
  end;
  FStack.Add(Lbl(ACtx.T('new_field_title')));
  Row := TBFRow.Create(FStack);
  Row.RowHeight := 28;
  Row.Color := BFClSurface;
  FTitle := TEdit.Create(Self);
  FTitle.MaxLength := BF_TITLE_MAX;
  FTitle.OnChange := TitleChange;
{$IFDEF BF_FPC}
  FTitle.TextHint := ACtx.T('new_field_title_placeholder');
{$ELSE}
  {$IFDEF BF_D2009}
  FTitle.TextHint := ACtx.T('new_field_title_placeholder');
  {$ENDIF}
{$ENDIF}
  Row.Add(FTitle, -1);
  FStack.Add(Row);
  FStack.Add(Lbl(ACtx.T('new_field_description')));
  FEditor := TBFEditor.CreateEditor(FStack, ACtx.Locale,
    ACtx.T('new_field_description_placeholder'), 120);
  if FVM.DescriptionHtml <> '' then
    FEditor.SetText(BFHtmlToText(FVM.DescriptionHtml));
  FStack.Add(FEditor);
  FStack.Add(Lbl(ACtx.T('btn_attach')));
  FUploads := TBFColumn.Create(FStack);
  FUploads.Color := BFClSurface;
  FUploads.Gap := 6;
  FStack.Add(FUploads);
  FAttach := TBFButton.Create(FStack);
  FAttach.Kind := bkNeutral;
  FAttach.ButtonHeight := 42;
  FAttach.OnClick := AttachClick;
  FStack.Add(FAttach);
  FUploadError := TBFText.Create(FStack);
  FUploadError.Style(8, False, BFClDanger);
  FUploadError.Visible := False;
  FStack.Add(FUploadError);
  RebuildUploads;
  Sync;
end;

destructor TBFNewTicketPage.Destroy;
begin
  FQueue.Free;
  FVM.Free;
  inherited Destroy;
end;

function TBFNewTicketPage.Lbl(const Text: string): TBFText;
begin
  Result := TBFText.Create(FStack);
  Result.Style(8, True, BFClSlate600);
  Result.MarginY := 2;
  Result.Text := Text;
end;

procedure TBFNewTicketPage.Resize;
begin
  inherited Resize;
  FHead.Height := FHead.MeasureHeight(Width);
  FFoot.Height := FFoot.MeasureHeight(Width);
  FFoot.Relayout;
  FStack.Relayout;
end;

procedure TBFNewTicketPage.Sync;
begin
  FCreate.Enabled := FVM.CanSubmit;
  FCreate.Busy := FVM.Submitting;
  FCreateError.Visible := FVM.SubmitFailed;
  if FVM.Uploading then
    FAttach.Caption := FCtx.T('attach_uploading')
  else
    FAttach.Caption := BFGlyph(#$F0#$9F#$93#$8E, '+') + ' ' + FCtx.T('attach_drag_hint');
  FAttach.Enabled := not FVM.Uploading;
  FUploadError.Text := FVM.UploadError;
  FUploadError.Visible := FVM.UploadError <> '';
  Resize;
end;

procedure TBFNewTicketPage.RebuildUploads;
var
  I: Integer;
  Row: TBFRow;
  T: TBFText;
  X: TBFButton;
  U: TBFJson;
begin
  FUploads.ClearItems;
  for I := 0 to FVM.UploadCount - 1 do
  begin
    U := FVM.Upload(I);
    Row := TBFRow.Create(Self);
    Row.RowHeight := 40;
    Row.Color := BFClSurface;
    T := TBFText.Create(Self);
    T.Style(9, False, BFClText);
    T.Box(BFClChip, BFColor('#cbd5e1', clSilver), 10, 4);
    T.Text := BFAttachmentIcon(U.StrOf('content_type')) + '  ' + U.StrOf('filename') +
      sLineBreak + BFPrettyBytes(U.IntOf('size'));
    Row.Add(T, -1);
    X := TBFButton.Create(Self);
    X.Kind := bkLink;
    X.Accent := BFClMuted;
    X.ButtonHeight := 40;
    X.Tag := I;
    X.Caption := BFGlyph(#$E2#$9C#$95, 'x');
    X.Hint := FCtx.T('btn_remove');
    X.OnClick := RemoveClick;
    Row.Add(X, 28);
    FUploads.Add(Row);
  end;
  FUploads.Visible := FVM.UploadCount > 0;
  FStack.Relayout;
end;

procedure TBFNewTicketPage.BackClick(Sender: TObject);
begin
  FCtx.GoList;
end;

procedure TBFNewTicketPage.TypeChange(Sender: TObject);
begin
  FVM.TypeName := FTypes.Selected;
end;

procedure TBFNewTicketPage.PriorityChange(Sender: TObject);
begin
  FVM.Priority := FPriorities.Selected;
end;

procedure TBFNewTicketPage.TitleChange(Sender: TObject);
begin
  FVM.Title := FTitle.Text;
  Sync;
end;

procedure TBFNewTicketPage.AttachClick(Sender: TObject);
var
  Files: TStringList;
begin
  Files := TStringList.Create;
  try
    if BFPickFiles(True, Files) then
      DropFiles(Files);
  finally
    Files.Free;
  end;
end;

procedure TBFNewTicketPage.DropFiles(Files: TStrings);
begin
  FQueue.AddStrings(Files);
  FVM.UploadError := '';
  NextUpload;
end;

procedure TBFNewTicketPage.NextUpload;
begin
  if FVM.Uploading or (FQueue.Count = 0) then
  begin
    Sync;
    Exit;
  end;
  FVM.Uploading := True;
  Sync;
  Run(UploadWork, UploadDone, [FQueue[0]]);
  FQueue.Delete(0);
end;

function TBFNewTicketPage.UploadWork(Job: TBFJob): TBFJson;
begin
  Result := Job.Api.UploadFile(Job.Arg(0));
end;

procedure TBFNewTicketPage.UploadDone(Job: TBFJob);
begin
  FVM.Uploading := False;
  if Job.Failed then
  begin
    FVM.UploadError := Job.ErrorMessage;
    FQueue.Clear;
  end
  else
    FVM.ApplyUpload(Job.TakeData);
  RebuildUploads;
  NextUpload;
end;

procedure TBFNewTicketPage.RemoveClick(Sender: TObject);
begin
  FVM.RemoveUpload(TComponent(Sender).Tag);
  RebuildUploads;
end;

procedure TBFNewTicketPage.CreateClick(Sender: TObject);
var
  Atts: TBFJson;
  Dept: string;
begin
  FVM.Title := FTitle.Text;
  FVM.DescriptionHtml := FEditor.Html;
  if not FVM.CanSubmit then
    Exit;
  Dept := FVM.DepartmentId;
  if (FDept <> nil) then
  begin
    if FDept.ItemIndex > 0 then
      Dept := FVM.DepartmentId_(FDept.ItemIndex - 1)
    else
      Dept := '';
  end;
  FVM.Submitting := True;
  FVM.SubmitFailed := False;
  Sync;
  Atts := FVM.AttachmentsForSend;
  try
    Run(CreateWork, CreateDone, [FVM.TypeName, Trim(FVM.Title), FVM.DescriptionForSend,
      FVM.Priority, Dept, Atts.ToJsonString]);
  finally
    Atts.Free;
  end;
end;

function TBFNewTicketPage.CreateWork(Job: TBFJob): TBFJson;
begin
  Result := Job.Api.CreateTicket(Job.Arg(0), Job.Arg(1), Job.Arg(2), Job.Arg(3), Job.Arg(4),
    TBFJson.Parse(BFToUtf8(Job.Arg(5))));
end;

procedure TBFNewTicketPage.CreateDone(Job: TBFJob);
begin
  FVM.Submitting := False;
  if Job.Failed or (Job.Data = nil) then
  begin
    if FCtx.CheckIdentity(Job) then
      Exit;
    FVM.SubmitFailed := True;
    Sync;
    Exit;
  end;
  // Depois de criar: abre o detalhe do chamado novo.
  FCtx.GoDetail(Job.Data.StrOf('id'));
end;

{ ── TBFDetailPage ──────────────────────────────────────────────────────── }

constructor TBFDetailPage.CreateDetail(AOwner: TComponent; ACtx: TBFUIContext; const TicketId: string);
begin
  inherited CreatePage(AOwner, ACtx);
  FVM := TBFTicketDetailVM.Create(ACtx.ReadState, ACtx.Locale, TicketId);
  FPending := TBFJson.NewArray;
  FLoader := TBFPreviewLoader.CreateLoader(Self, ACtx);
  FLoader.OnLoaded := PreviewLoaded;
  FHead := TBFColumn.Create(Self);
  FHead.Parent := Self;
  FHead.Align := alTop;
  FHead.Color := clWhite;
  FHead.Box(clNone, clNone, 16, 12, 0);
  FHead.Gap := 4;
  FHead.Add(NewBackButton(Self, ACtx, BackClick));
  FHeadInfo := TBFText.Create(Self);
  FHeadInfo.Style(7, True, BFClMuted);
  FHead.Add(FHeadInfo);
  FHeadTitle := TBFText.Create(Self);
  FHeadTitle.Style(11, True, BFClText);
  FHead.Add(FHeadTitle);
  FHeadStatus := TBFText.Create(Self);
  FHeadStatus.Style(7, True, BFClMuted);
  FHeadStatus.Box(BFClChip, clNone, 10, 2);
  FHeadStatus.Radius := 20;
  FHead.Add(FHeadStatus);
  FContinuation := TBFButton.Create(Self);
  FContinuation.Kind := bkLink;
  FContinuation.Accent := ACtx.Primary;
  FContinuation.Alignment := taLeftJustify;
  FContinuation.ButtonHeight := 18;
  FContinuation.FontSize := 8;
  FContinuation.OnClick := ContinuationClick;
  FContinuation.Visible := False;
  FHead.Add(FContinuation);
  FFoot := TBFColumn.Create(Self);
  FFoot.Parent := Self;
  FFoot.Align := alBottom;
  FFoot.Color := clWhite;
  FFoot.Box(clNone, clNone, 12, 12, 0);
  FStack := TBFStack.Create(Self);
  FStack.Parent := Self;
  FStack.Align := alClient;
  FStack.Content.Box(clNone, clNone, 12, 12, 0);
  FTimer := NewTimer(Self, BF_DETAIL_REFRESH_MS, TimerTick);
end;

destructor TBFDetailPage.Destroy;
begin
  FPending.Free;
  FVM.Free;
  inherited Destroy;
end;

procedure TBFDetailPage.Activate;
begin
  Build;
  Load;
  LoadConversations;
  FTimer.Enabled := True;
end;

procedure TBFDetailPage.Deactivate;
begin
  FTimer.Enabled := False;
end;

procedure TBFDetailPage.VisibilityChanged(AVisible: Boolean);
begin
  FTimer.Enabled := AVisible;
  if AVisible then
    Load;
end;

procedure TBFDetailPage.TimerTick(Sender: TObject);
begin
  if not FCtx.Visible then
    Exit;
  Load;
  // A transcrição do chat só recarrega enquanto a conversa estiver viva.
  if FVM.HasLiveConversation then
    LoadConversations;
end;

procedure TBFDetailPage.Load;
begin
  Run(TicketWork, TicketDone, [FVM.TicketId]);
end;

procedure TBFDetailPage.LoadConversations;
begin
  Run(ConvWork, ConvDone, [FVM.TicketId]);
end;

function TBFDetailPage.TicketWork(Job: TBFJob): TBFJson;
begin
  Result := Job.Api.GetTicket(Job.Arg(0));
end;

procedure TBFDetailPage.TicketDone(Job: TBFJob);
begin
  if Job.Failed then
  begin
    if FCtx.CheckIdentity(Job) then
      Exit;
    FVM.ApplyTicket(nil);
  end
  else
  begin
    FVM.ApplyTicket(Job.TakeData);
    // Abrir o chamado marca-o como lido localmente.
    FVM.MarkRead;
  end;
  Build;
end;

function TBFDetailPage.ConvWork(Job: TBFJob): TBFJson;
begin
  Result := Job.Api.ListTicketConversations(Job.Arg(0));
end;

procedure TBFDetailPage.ConvDone(Job: TBFJob);
begin
  if Job.Failed then
  begin
    FVM.ConversationsFailed := True;
    FCtx.CheckIdentity(Job);
  end
  else
  begin
    FVM.ApplyConversations(Job.TakeData);
    FVM.MarkRead;
  end;
  Build;
end;

procedure TBFDetailPage.Resize;
begin
  inherited Resize;
  FitAll;
end;

procedure TBFDetailPage.FitAll;
begin
  FHead.Height := FHead.MeasureHeight(Width);
  FHead.Relayout;
  FFoot.Height := FFoot.MeasureHeight(Width);
  FFoot.Relayout;
  FStack.Relayout;
end;

function Meta(const Author, Iso: string): string;
begin
  Result := Author + ' ' + BFFromUtf8(#$C2#$B7) + ' ' + BFFormatDateTime(Iso);
end;

procedure TBFDetailPage.Build;
var
  B: TBFBubbles;
  I, J: Integer;
  Txt: TBFText;
  Bubble: TBFBubble;
  Card: TBFColumn;
  Toggle: TBFButton;
  Tr: TBFBubbles;
  Btn: TBFButton;
  Ticket: TBFJson;
begin
  FLoader.ResetCards;
  FStack.Clear;
  Ticket := FVM.Ticket;
  if Ticket = nil then
  begin
    Txt := TBFText.Create(FStack);
    Txt.Alignment := taCenter;
    Txt.MarginY := 24;
    if FVM.Loading then
    begin
      Txt.Style(9, False, FCtx.Primary);
      Txt.Text := FCtx.T('loading');
    end
    else
    begin
      Txt.Style(9, False, BFClMuted);
      Txt.Text := FCtx.T('error_load');
    end;
    FStack.Add(Txt);
    FHeadInfo.Text := '';
    FHeadTitle.Text := '';
    FHeadStatus.Visible := False;
    FFoot.ClearItems;
    FFootBuiltFor := '';
    FitAll;
    Exit;
  end;
  FHeadInfo.Text := Ticket.StrOf('ticket_number');
  FHeadTitle.Text := Ticket.StrOf('title');
  FHeadStatus.Visible := True;
  FHeadStatus.Text := AnsiUpperCase(FVM.StatusText);
  FHeadStatus.TextColor := BFColor(FVM.StatusColor, BFClMuted);
  FHeadStatus.BoxColor := BFMix(FHeadStatus.TextColor, clWhite, 0.10);
  FContinuation.Visible := FVM.ContinuationText <> '';
  FContinuation.Caption := BFFromUtf8(#$E2#$86#$B3) + ' ' + FVM.ContinuationText;
  B := FVM.Bubbles;
  if Length(B) > 0 then
  begin
    Bubble := TBFBubble.CreateBubble(FStack, FCtx, not B[0].IsStaff, B[0].Html, B[0].Attachments,
      Meta(B[0].Author, B[0].Timestamp), FLoader);
    FStack.Add(Bubble);
  end;
  // Conversa do chat: seção recolhível, fora do andamento do chamado.
  if FVM.HasChat then
  begin
    Txt := TBFText.Create(FStack);
    Txt.Style(7, True, BFClMuted);
    Txt.MarginY := 4;
    Txt.Text := AnsiUpperCase(FCtx.T('detail_chat_title'));
    FStack.Add(Txt);
    for I := 0 to FVM.ConversationCount - 1 do
    begin
      Card := TBFColumn.Create(FStack);
      Card.Box(clWhite, BFClBorder, 10, 8, 12);
      Card.Gap := 4;
      Toggle := TBFButton.Create(FStack);
      Toggle.Kind := bkLink;
      Toggle.Accent := BFClText;
      Toggle.Alignment := taLeftJustify;
      Toggle.ButtonHeight := 36;
      Toggle.FontSize := 9;
      Toggle.Tag := I;
      if FVM.IsExpanded(I) then
        Toggle.Caption := BFGlyph(#$F0#$9F#$92#$AC, '') + ' ' + FVM.ConversationTitle(I) +
          sLineBreak + FVM.ConversationSubtitle(I) + '  ' + BFFromUtf8(#$E2#$96#$B2)
      else
        Toggle.Caption := BFGlyph(#$F0#$9F#$92#$AC, '') + ' ' + FVM.ConversationTitle(I) +
          sLineBreak + FVM.ConversationSubtitle(I) + '  ' + BFFromUtf8(#$E2#$96#$BC);
      Toggle.OnClick := ConvToggle;
      Card.Add(Toggle);
      if FVM.IsExpanded(I) then
      begin
        Tr := FVM.TranscriptBubbles(I);
        if Length(Tr) = 0 then
        begin
          Txt := TBFText.Create(FStack);
          Txt.Style(8, False, BFClSubtle);
          Txt.Alignment := taCenter;
          Txt.Text := FCtx.T('detail_chat_empty');
          Card.Add(Txt);
        end;
        for J := 0 to High(Tr) do
        begin
          Bubble := TBFBubble.CreateBubble(FStack, FCtx, not Tr[J].IsStaff, Tr[J].Html,
            Tr[J].Attachments, Meta(Tr[J].Author, Tr[J].Timestamp), FLoader);
          if Tr[J].Author = '' then
            Bubble.MakeSystem;
          Card.Add(Bubble);
        end;
      end;
      FStack.Add(Card);
    end;
  end;
  if FVM.ConversationsFailed then
  begin
    Txt := TBFText.Create(FStack);
    Txt.Style(8, False, BFClMuted);
    Txt.Alignment := taCenter;
    Txt.Text := FCtx.T('detail_chat_error');
    FStack.Add(Txt);
    Btn := TBFButton.Create(FStack);
    Btn.Kind := bkLink;
    Btn.Accent := FCtx.Primary;
    Btn.Alignment := taCenter;
    Btn.ButtonHeight := 20;
    Btn.FontSize := 8;
    Btn.Caption := FCtx.T('btn_retry');
    Btn.OnClick := ConvRetryClick;
    FStack.Add(Btn);
  end;
  if FVM.ShowInteractionsTitle then
  begin
    Txt := TBFText.Create(FStack);
    Txt.Style(7, True, BFClMuted);
    Txt.MarginY := 4;
    Txt.Text := AnsiUpperCase(FCtx.T('detail_interactions_title'));
    FStack.Add(Txt);
  end;
  if FVM.ShowNoMessages then
  begin
    Txt := TBFText.Create(FStack);
    Txt.Style(9, False, BFClSubtle);
    Txt.Alignment := taCenter;
    Txt.MarginY := 16;
    Txt.Text := FCtx.T('detail_no_messages');
    FStack.Add(Txt);
  end;
  for I := 1 to High(B) do
  begin
    Bubble := TBFBubble.CreateBubble(FStack, FCtx, not B[I].IsStaff, B[I].Html,
      B[I].Attachments, Meta(B[I].Author, B[I].Timestamp), FLoader);
    FStack.Add(Bubble);
  end;
  // Chamado sem descrição: a primeira bolha já é uma interação.
  if (Length(B) > 0) and B[0].IsStaff then ;
  BuildFoot;
  FitAll;
end;

procedure TBFDetailPage.BuildFoot;
var
  Key: string;
  Txt: TBFText;
  Row: TBFRow;
begin
  // Refaz o rodapé só quando o tipo muda (preserva o rascunho a cada atualização).
  if FVM.IsClosed then Key := 'closed'
  else if FVM.IsResolved then Key := 'resolved:' + FVM.ReopenHint
  else Key := 'open';
  if Key = FFootBuiltFor then
  begin
    SyncFoot;
    Exit;
  end;
  FFootBuiltFor := Key;
  FFoot.ClearItems;
  FEditor := nil;
  FSend := nil;
  FAttach := nil;
  FPendingCol := nil;
  FSendError := nil;
  if FVM.IsClosed then
  begin
    // Fechado/cancelado: sem resposta; um novo contato vira chamado ligado a este.
    Txt := TBFText.Create(Self);
    Txt.Style(8, False, BFClSlate600);
    Txt.Alignment := taCenter;
    Txt.Text := FVM.ClosedNotice;
    FFoot.Add(Txt);
    Exit;
  end;
  if FVM.IsResolved then
  begin
    Txt := TBFText.Create(Self);
    Txt.Style(8, False, BFColor('#065f46', clGreen));
    Txt.Box(BFColor('#ecfdf5', clWhite), BFColor('#a7f3d0', clLime), 10, 6);
    Txt.Text := FVM.ReopenHint;
    FFoot.Add(Txt);
  end;
  FPendingCol := TBFColumn.Create(Self);
  FPendingCol.Color := clWhite;
  FPendingCol.Gap := 4;
  FFoot.Add(FPendingCol);
  FEditor := TBFEditor.CreateEditor(Self, FCtx.Locale, FCtx.T('detail_send_placeholder'), 60);
  FEditor.OnChange := EditorChange;
  FFoot.Add(FEditor);
  Row := TBFRow.Create(Self);
  Row.RowHeight := 36;
  Row.Color := clWhite;
  FAttach := TBFButton.Create(Self);
  FAttach.Kind := bkNeutral;
  FAttach.ButtonHeight := 36;
  FAttach.Caption := BFGlyph(#$F0#$9F#$93#$8E, '+');
  FAttach.Hint := FCtx.T('attach_file');
  FAttach.ShowHint := True;
  FAttach.OnClick := AttachClick;
  Row.Add(FAttach, 36);
  Txt := TBFText.Create(Self);
  Row.Add(Txt, -1);
  FSend := TBFButton.Create(Self);
  FSend.Accent := FCtx.Primary;
  FSend.ButtonHeight := 36;
  FSend.Caption := FCtx.T('btn_send');
  FSend.OnClick := SendClick;
  Row.Add(FSend, FSend.PreferredWidth + 8);
  FFoot.Add(Row);
  FSendError := TBFText.Create(Self);
  FSendError.Style(8, False, BFClDanger);
  FSendError.Text := FCtx.T('error_generic');
  FSendError.Visible := False;
  FFoot.Add(FSendError);
  RebuildPending;
  SyncFoot;
end;

procedure TBFDetailPage.RebuildPending;
var
  I: Integer;
  Row: TBFRow;
  T: TBFText;
  X: TBFButton;
begin
  if FPendingCol = nil then
    Exit;
  FPendingCol.ClearItems;
  for I := 0 to FPending.Count - 1 do
  begin
    Row := TBFRow.Create(Self);
    Row.RowHeight := 24;
    Row.Color := clWhite;
    T := TBFText.Create(Self);
    T.Style(8, False, BFClText);
    T.Box(BFClChip, BFColor('#cbd5e1', clSilver), 8, 3);
    T.Radius := 20;
    T.Text := BFAttachmentIcon(FPending.Item(I).StrOf('content_type')) + ' ' +
      FPending.Item(I).StrOf('filename');
    Row.Add(T, -1);
    X := TBFButton.Create(Self);
    X.Kind := bkLink;
    X.Accent := BFClMuted;
    X.ButtonHeight := 24;
    X.Tag := I;
    X.Caption := BFGlyph(#$E2#$9C#$95, 'x');
    X.Hint := FCtx.T('btn_remove');
    X.OnClick := RemovePendingClick;
    Row.Add(X, 24);
    FPendingCol.Add(Row);
  end;
  FPendingCol.Visible := FPending.Count > 0;
  FitAll;
end;

procedure TBFDetailPage.SyncFoot;
begin
  if FSend = nil then
    Exit;
  FSend.Enabled := FVM.CanSend(FEditor.Html, FPending.Count) and not FUploading;
  FSend.Busy := FVM.Sending;
  FAttach.Busy := FUploading;
  FAttach.Enabled := not FUploading;
  FSendError.Visible := FVM.SendFailed;
end;

procedure TBFDetailPage.EditorChange(Sender: TObject);
begin
  SyncFoot;
end;

procedure TBFDetailPage.BackClick(Sender: TObject);
begin
  FCtx.GoList;
end;

procedure TBFDetailPage.ContinuationClick(Sender: TObject);
begin
  if FVM.PreviousId <> '' then
    FCtx.GoDetail(FVM.PreviousId);
end;

procedure TBFDetailPage.ConvToggle(Sender: TObject);
begin
  FVM.ToggleExpanded(TComponent(Sender).Tag);
  Build;
end;

procedure TBFDetailPage.ConvRetryClick(Sender: TObject);
begin
  FVM.ConversationsFailed := False;
  LoadConversations;
end;

procedure TBFDetailPage.PreviewLoaded(Sender: TObject);
begin
  FStack.Relayout;
end;

procedure TBFDetailPage.AttachClick(Sender: TObject);
var
  Files: TStringList;
begin
  // Resposta: um anexo por vez (como no web).
  Files := TStringList.Create;
  try
    if BFPickFiles(False, Files) and (Files.Count > 0) then
      DropFiles(Files);
  finally
    Files.Free;
  end;
end;

procedure TBFDetailPage.DropFiles(Files: TStrings);
begin
  if FUploading or FVM.IsClosed or (Files.Count = 0) then
    Exit;
  FUploading := True;
  SyncFoot;
  Run(UploadWork, UploadDone, [Files[0]]);
end;

function TBFDetailPage.UploadWork(Job: TBFJob): TBFJson;
begin
  Result := Job.Api.UploadFile(Job.Arg(0));
end;

procedure TBFDetailPage.UploadDone(Job: TBFJob);
var
  R, A: TBFJson;
begin
  FUploading := False;
  if not Job.Failed then
  begin
    R := Job.TakeData;
    try
      if R <> nil then
      begin
        A := FPending.Add(TBFJson.NewObject);
        A.PutUtf8('url', R.Utf8Of('url'));
        A.PutUtf8('filename', R.Utf8Of('filename'));
        A.PutInt('size', R.IntOf('size'));
        A.PutUtf8('content_type', R.Utf8Of('mime'));
      end;
    finally
      R.Free;
    end;
  end;
  RebuildPending;
  SyncFoot;
end;

procedure TBFDetailPage.RemovePendingClick(Sender: TObject);
begin
  FPending.Delete(TComponent(Sender).Tag);
  RebuildPending;
  SyncFoot;
end;

procedure TBFDetailPage.SendClick(Sender: TObject);
begin
  if (FEditor = nil) or not FVM.CanSend(FEditor.Html, FPending.Count) then
    Exit;
  FVM.Sending := True;
  FVM.SendFailed := False;
  SyncFoot;
  Run(SendWork, SendDone, [FVM.TicketId, FEditor.Html, FPending.ToJsonString]);
end;

function TBFDetailPage.SendWork(Job: TBFJob): TBFJson;
begin
  Result := Job.Api.AddInteraction(Job.Arg(0), Job.Arg(1), TBFJson.Parse(BFToUtf8(Job.Arg(2))));
end;

procedure TBFDetailPage.SendDone(Job: TBFJob);
begin
  FVM.Sending := False;
  if Job.Failed then
  begin
    if FCtx.CheckIdentity(Job) then
      Exit;
    FVM.SendFailed := True;
    // 409 TICKET_CLOSED: foi fechado com a tela aberta → recarrega (vira o aviso).
    if FVM.NeedsReloadAfterSendError(Job.ErrorStatus) then
      Load;
    SyncFoot;
    Exit;
  end;
  // Responder um resolvido o reabre: o recarregamento traz o status novo.
  FEditor.Clear;
  FPending.Clear;
  RebuildPending;
  SyncFoot;
  Load;
end;

end.
