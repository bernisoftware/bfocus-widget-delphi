unit BFocusUIReleaseNotes;

{ Release notes na UI nativa (behavior spec §4 e §6):
  - TBFSplashPanel: novidades do usuário cobrindo a lista de chamados; release que exige
    ciência trava (uma por vez, sem pular), as demais são cartões dispensáveis;
  - TBFBannerForm: modal em tela cheia sem fechar, uma release por vez, trava de rolagem
    quando exige ciência, /acknowledge ou /seen com ackSubmitting/ackError, e rn:done no fim;
  - TBFHistoryForm: /changelog, versão atual destacada, ⚠ nas que exigem ciência. }

{$I BFocusDefines.inc}

interface

uses
  SysUtils, Classes, Controls, Forms, Graphics, ExtCtrls, BFocusText, BFocusJson,
  BFocusApi, BFocusAsync, BFocusVMReleaseNotes, BFocusUIControls, BFocusUIContext,
  BFocusGraphics, BFocusFormat;

type
  { Cabeçalho em gradiente: sobretítulo, título, linha extra e contador. }
  TBFGradientHeader = class(TCustomControl, IBFMeasurable)
  private
    FColor1: TColor;
    FEyebrow, FTitle, FLine, FSub: string;
    FTitleSize: Integer;
    FPadX, FPadY: Integer;
  protected
    procedure Paint; override;
  public
    constructor Create(AOwner: TComponent); override;
    procedure Setup(AColor: TColor; const AEyebrow, ALine, ATitle, ASub: string);
    function MeasureHeight(AWidth: Integer): Integer;
    property TitleSize: Integer read FTitleSize write FTitleSize;
  end;

  { Cartão de uma release (splash e histórico). }
  TBFNoteCard = class(TBFColumn)
  private
    FNoteId: string;
    FHtml: TBFHtmlBox;
    FExpand: TBFButton;
    FMark: TBFButton;
    FOnToggle: TNotifyEvent;
    FOnMark: TNotifyEvent;
    procedure ExpandClick(Sender: TObject);
    procedure MarkClick(Sender: TObject);
  public
    constructor CreateCard(AOwner: TComponent; Ctx: TBFUIContext; Note: TBFJson;
      AColor: TColor; Expanded, IsCurrent, WithMark: Boolean; const DateText, ExpandText,
      CollapseText, CurrentText: string);
    property NoteId: string read FNoteId;
    property MarkButton: TBFButton read FMark;
    property OnToggle: TNotifyEvent read FOnToggle write FOnToggle;
    property OnMark: TNotifyEvent read FOnMark write FOnMark;
  end;

  { Splash de novidades cobrindo a lista de chamados, em dois modos:
    - trava de ciência: cabeçalho ⚠ com produto, versão, título e "1 / n", conteúdo
      aberto que rola, botão só no fim, ackSubmitting e ackError; sem pular;
    - cartões das que não exigem: "ver detalhes", "marcar como lida" (/seen) e
      "Pular por agora". }
  TBFSplashPanel = class(TCustomPanel)
  private
    FCtx: TBFUIContext;
    FVM: TBFSplashVM;
    FHeader: TBFGradientHeader;
    FStack: TBFStack;
    FSkip: TBFButton;
    FFooter: TBFColumn;     // trava: dica, botão e erro
    FHint: TBFText;
    FAck: TBFButton;
    FError: TBFText;
    FGateId: string;        // release montada na trava ('' = modo cartões)
    FTimer: TTimer;
    FGate: TTimer;
    FOnVisibility: TNotifyEvent;
    procedure Rebuild;
    procedure BuildCards;
    procedure BuildGate;
    procedure UpdateGate;
    procedure Load;
    function ListWork(Job: TBFJob): TBFJson;
    procedure ListDone(Job: TBFJob);
    function MarkWork(Job: TBFJob): TBFJson;
    procedure MarkDone(Job: TBFJob);
    function AckWork(Job: TBFJob): TBFJson;
    procedure AckDone(Job: TBFJob);
    procedure CardToggle(Sender: TObject);
    procedure CardMark(Sender: TObject);
    procedure SkipClick(Sender: TObject);
    procedure AckClick(Sender: TObject);
    procedure TimerTick(Sender: TObject);
    procedure GateTick(Sender: TObject);
  protected
    procedure Resize; override;
  public
    constructor CreateSplash(AOwner: TComponent; ACtx: TBFUIContext);
    destructor Destroy; override;
    procedure Start;
    procedure Stop;
    procedure WidgetReopened;
    { A janela voltou ao foco: reconsulta (release com ciência publicada agora trava). }
    procedure Refresh;
    function ShouldShow: Boolean;
    property OnVisibility: TNotifyEvent read FOnVisibility write FOnVisibility;
  end;

  TBFBannerForm = class(TForm)
  private
    FCtx: TBFUIContext;
    FVM: TBFBannerVM;
    FCard: TPanel;
    FHeader: TBFGradientHeader;
    FBody: TBFStack;
    FHtml: TBFHtmlBox;
    FFooter: TBFColumn;
    FHint: TBFText;
    FButton: TBFButton;
    FError: TBFText;
    FGate: TTimer;
    FAllowClose: Boolean;
    FDone: Boolean;
    procedure ShowCurrent;
    procedure LayoutCard;
    procedure UpdateFooter;
    procedure GateTick(Sender: TObject);
    procedure ConfirmClick(Sender: TObject);
    function PendingWork(Job: TBFJob): TBFJson;
    procedure PendingDone(Job: TBFJob);
    function ConfirmWork(Job: TBFJob): TBFJson;
    procedure ConfirmDone(Job: TBFJob);
    procedure Finish;
    procedure CloseQueryHandler(Sender: TObject; var CanClose: Boolean);
    procedure KeyDownHandler(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure ResizeHandler(Sender: TObject);
  public
    constructor CreateBanner(AOwner: TComponent; ACtx: TBFUIContext; Ids: TStrings);
    destructor Destroy; override;
  end;

  TBFHistoryForm = class(TForm)
  private
    FCtx: TBFUIContext;
    FVM: TBFHistoryVM;
    FHeader: TBFGradientHeader;
    FClose: TBFButton;
    FStack: TBFStack;
    procedure Rebuild;
    function ChangelogWork(Job: TBFJob): TBFJson;
    procedure ChangelogDone(Job: TBFJob);
    procedure CardToggle(Sender: TObject);
    procedure CloseClick(Sender: TObject);
    procedure ResizeHandler(Sender: TObject);
  public
    constructor CreateHistory(AOwner: TComponent; ACtx: TBFUIContext);
    destructor Destroy; override;
    procedure Reload;
  end;

implementation

{ ── TBFGradientHeader ──────────────────────────────────────────────────── }

constructor TBFGradientHeader.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FTitleSize := 13;
  FPadX := 18;
  FPadY := 16;
  Height := 90;
end;

procedure TBFGradientHeader.Setup(AColor: TColor; const AEyebrow, ALine, ATitle, ASub: string);
begin
  FColor1 := AColor;
  FEyebrow := AEyebrow;
  FLine := ALine;
  FTitle := ATitle;
  FSub := ASub;
  Invalidate;
end;

function TBFGradientHeader.MeasureHeight(AWidth: Integer): Integer;
var
  F: TFont;
  W: Integer;
begin
  W := AWidth - 2 * FPadX;
  F := TFont.Create;
  try
    Result := 2 * FPadY;
    if FEyebrow <> '' then
    begin
      BFStyleFont(F, 7, True, clWhite);
      Inc(Result, BFTextHeight(F, FEyebrow, W) + 6);
    end;
    if FLine <> '' then
    begin
      BFStyleFont(F, 8, False, clWhite);
      Inc(Result, BFTextHeight(F, FLine, W) + 6);
    end;
    BFStyleFont(F, FTitleSize, True, clWhite);
    Inc(Result, BFTextHeight(F, FTitle, W));
    if FSub <> '' then
    begin
      BFStyleFont(F, 8, False, clWhite);
      Inc(Result, BFTextHeight(F, FSub, W) + 6);
    end;
  finally
    F.Free;
  end;
end;

procedure TBFGradientHeader.Paint;
var
  Y, W, H: Integer;
begin
  W := Width - 2 * FPadX;
  BFGradient(Canvas, Rect(0, 0, Width, Height), FColor1, BFDarken(FColor1, 0.38));
  Y := FPadY;
  with Canvas do
  begin
    if FEyebrow <> '' then
    begin
      BFStyleFont(Font, 7, True, clWhite);
      H := BFTextHeight(Font, FEyebrow, W);
      BFDrawTextIn(Canvas, AnsiUpperCase(FEyebrow), Rect(FPadX, Y, FPadX + W, Y + H), taLeftJustify, True);
      Inc(Y, H + 6);
    end;
    if FLine <> '' then
    begin
      BFStyleFont(Font, 8, False, clWhite);
      H := BFTextHeight(Font, FLine, W);
      BFDrawTextIn(Canvas, FLine, Rect(FPadX, Y, FPadX + W, Y + H), taLeftJustify, True);
      Inc(Y, H + 6);
    end;
    BFStyleFont(Font, FTitleSize, True, clWhite);
    H := BFTextHeight(Font, FTitle, W);
    BFDrawTextIn(Canvas, FTitle, Rect(FPadX, Y, FPadX + W, Y + H), taLeftJustify, True);
    Inc(Y, H + 6);
    if FSub <> '' then
    begin
      BFStyleFont(Font, 8, False, clWhite);
      H := BFTextHeight(Font, FSub, W);
      BFDrawTextIn(Canvas, FSub, Rect(FPadX, Y, FPadX + W, Y + H), taLeftJustify, True);
    end;
  end;
end;

{ ── TBFNoteCard ────────────────────────────────────────────────────────── }

constructor TBFNoteCard.CreateCard(AOwner: TComponent; Ctx: TBFUIContext; Note: TBFJson;
  AColor: TColor; Expanded, IsCurrent, WithMark: Boolean; const DateText, ExpandText,
  CollapseText, CurrentText: string);
var
  Meta, Title: TBFText;
  Row: TBFRow;
  Line: string;
  Product: TBFJson;
begin
  inherited Create(AOwner);
  FNoteId := Note.StrOf('id');
  if IsCurrent then
    Box(clWhite, AColor, 14, 12, 12)
  else
    Box(clWhite, BFClBorder, 14, 12, 12);
  Gap := 6;
  // Linha de metadados: produto · vVersão [atual] [⚠] data.
  Meta := TBFText.Create(Self);
  Meta.Style(7, False, BFClMuted);
  Product := Note.ObjOf('product');
  Line := 'v' + Note.StrOf('version');
  if (Product <> nil) and (Product.StrOf('name') <> '') and not IsCurrent and (CurrentText = '') then
    Line := Product.StrOf('name') + ' ' + BFFromUtf8(#$E2#$80#$A2) + ' ' + Line;
  if IsCurrent then
    Line := Line + '   ' + AnsiUpperCase(CurrentText);
  if Note.BoolOf('require_acknowledgement') then
    Line := Line + '  ' + BFGlyph(#$E2#$9A#$A0, '(!)');
  if DateText <> '' then
    Line := Line + '   ' + DateText;
  Meta.Text := Line;
  if IsCurrent then
    Meta.TextColor := AColor;
  Add(Meta);
  Title := TBFText.Create(Self);
  Title.Style(10, True, BFClText);
  Title.Text := Note.StrOf('title');
  Add(Title);
  FHtml := TBFHtmlBox.Create(Self);
  FHtml.Color := BFClSurface;
  FHtml.FontSize := 9;
  FHtml.TextColor := BFColor('#334155', BFClText);
  FHtml.LinkColor := AColor;
  FHtml.OnLink := Ctx.LinkClicked;
  FHtml.SetHtml(Note.Utf8Of('description'));
  FHtml.Visible := Expanded;
  Add(FHtml);
  Row := TBFRow.Create(Self);
  Row.RowHeight := 30;
  Row.Color := clWhite;
  Row.Gap := 6;
  FExpand := TBFButton.Create(Self);
  FExpand.Kind := bkGhost;
  FExpand.ButtonHeight := 30;
  FExpand.FontSize := 8;
  if Expanded then FExpand.Caption := CollapseText else FExpand.Caption := ExpandText;
  FExpand.OnClick := ExpandClick;
  Row.Add(FExpand, -1);
  if WithMark then
  begin
    FMark := TBFButton.Create(Self);
    FMark.Kind := bkPrimary;
    FMark.Accent := AColor;
    FMark.ButtonHeight := 30;
    FMark.FontSize := 8;
    FMark.Caption := Ctx.T('splash_mark_read');
    FMark.OnClick := MarkClick;
    Row.Add(FMark, -1);
  end;
  Add(Row);
end;

procedure TBFNoteCard.ExpandClick(Sender: TObject);
begin
  if Assigned(FOnToggle) then
    FOnToggle(Self);
end;

procedure TBFNoteCard.MarkClick(Sender: TObject);
begin
  if Assigned(FOnMark) then
    FOnMark(Self);
end;

{ ── TBFSplashPanel ─────────────────────────────────────────────────────── }

constructor TBFSplashPanel.CreateSplash(AOwner: TComponent; ACtx: TBFUIContext);
begin
  inherited Create(AOwner);
  FCtx := ACtx;
  BevelOuter := bvNone;
  Caption := '';
  Color := clWhite;
  FVM := TBFSplashVM.Create;
  FHeader := TBFGradientHeader.Create(Self);
  FHeader.Parent := Self;
  FHeader.Align := alTop;
  FSkip := TBFButton.Create(Self);
  FSkip.Parent := Self;
  FSkip.Align := alBottom;
  FSkip.Kind := bkLink;
  FSkip.Accent := BFClMuted;
  FSkip.Alignment := taCenter;
  FSkip.ButtonHeight := 44;
  FSkip.Height := 44;
  FSkip.FontSize := 8;
  FSkip.Caption := FCtx.T('splash_skip');
  FSkip.OnClick := SkipClick;
  FFooter := TBFColumn.Create(Self);
  FFooter.Parent := Self;
  FFooter.Align := alBottom;
  FFooter.Color := clWhite;
  FFooter.Box(clNone, clNone, 16, 12, 0);
  FFooter.Visible := False;
  FHint := TBFText.Create(Self);
  FHint.Style(8, True, BFClSubtle);
  FHint.Alignment := taCenter;
  FHint.Text := FCtx.RN('scrollHint');
  FFooter.Add(FHint);
  FAck := TBFButton.Create(Self);
  FAck.ButtonHeight := 44;
  FAck.OnClick := AckClick;
  FFooter.Add(FAck);
  FError := TBFText.Create(Self);
  FError.Style(8, False, BFColor('#b91c1c', BFClDanger));
  FError.Alignment := taCenter;
  FError.Text := FCtx.RN('ackError');
  FError.Visible := False;
  FFooter.Add(FError);
  FStack := TBFStack.Create(Self);
  FStack.Parent := Self;
  FStack.Align := alClient;
  FStack.Content.Box(clNone, clNone, 12, 12, 0);
  FTimer := TTimer.Create(Self);
  FTimer.Enabled := False;
  FTimer.Interval := BF_SPLASH_REFRESH_MS;
  FTimer.OnTimer := TimerTick;
  FGate := TTimer.Create(Self);
  FGate.Enabled := False;
  FGate.Interval := 150;
  FGate.OnTimer := GateTick;
  Visible := False;
end;

destructor TBFSplashPanel.Destroy;
begin
  BFJobs.CancelOwner(Self);
  FVM.Free;
  inherited Destroy;
end;

function TBFSplashPanel.ShouldShow: Boolean;
begin
  Result := FVM.Visible(FCtx.Config.ShowReleaseNotes);
end;

procedure TBFSplashPanel.Start;
begin
  if not FCtx.Config.ShowReleaseNotes then
    Exit;
  Load;
  FTimer.Enabled := True;
end;

procedure TBFSplashPanel.Stop;
begin
  FTimer.Enabled := False;
  FGate.Enabled := False;
end;

procedure TBFSplashPanel.WidgetReopened;
begin
  // "Pular por agora" vale até o widget ser reaberto; reabrir também reconsulta.
  FVM.WidgetReopened;
  Rebuild;
  Refresh;
end;

procedure TBFSplashPanel.Refresh;
begin
  // Só com o splash ligado e o widget à vista; uma consulta (ou registro) em curso basta.
  if FTimer.Enabled and FCtx.Visible and (BFJobs.RunningFor(Self) = 0) then
    Load;
end;

procedure TBFSplashPanel.Load;
begin
  BFJobs.Run(FCtx.Api, ListWork, ListDone, Self, []);
end;

procedure TBFSplashPanel.TimerTick(Sender: TObject);
begin
  if FCtx.Visible then
    Load;
end;

function TBFSplashPanel.ListWork(Job: TBFJob): TBFJson;
begin
  Result := Job.Api.ListReleaseNotes;
end;

procedure TBFSplashPanel.ListDone(Job: TBFJob);
begin
  if Job.Failed then
    Exit; // splash é opcional: falha não atrapalha a lista
  FVM.ApplyList(Job.TakeData);
  Rebuild;
end;

procedure TBFSplashPanel.Rebuild;
begin
  // Visível antes de montar: o alClient já dá o tamanho real para medir a trava.
  Visible := ShouldShow;
  if Visible then
    BringToFront;
  if FVM.Locked then
    BuildGate
  else
    BuildCards;
  Resize;
  FGate.Enabled := Visible and FVM.Locked;
  if Assigned(FOnVisibility) then
    FOnVisibility(Self);
end;

procedure TBFSplashPanel.BuildGate;
var
  N, P: TBFJson;
  Accent: TColor;
  Line: string;
  Html: TBFHtmlBox;
begin
  N := FVM.AckNote;
  Accent := BFColor(FVM.AckColor(FCtx.PrimaryHex), FCtx.Primary);
  P := N.ObjOf('product');
  Line := 'v' + N.StrOf('version');
  if (P <> nil) and (P.StrOf('name') <> '') then
    Line := P.StrOf('name') + '   ' + Line;
  // Sem "Pular": só o botão de ciência tira a trava.
  FHeader.Setup(Accent, BFGlyph(#$E2#$9A#$A0, '!') + ' ' + FCtx.RN('ackEyebrow'), Line,
    N.StrOf('title'), FVM.AckCounterText);
  FSkip.Visible := False;
  FFooter.Visible := True;
  FAck.Accent := Accent;
  // A reconsulta de 60 s com a mesma release não remonta: a rolagem já feita vale.
  if FGateId <> N.StrOf('id') then
  begin
    FGateId := N.StrOf('id');
    FStack.Color := clWhite;
    FStack.Content.Color := clWhite;
    FStack.Content.Box(clNone, clNone, 18, 14, 0);
    FStack.Clear;
    Html := TBFHtmlBox.Create(FStack);
    Html.FontSize := 10;
    Html.TextColor := BFColor('#334155', BFClText);
    Html.LinkColor := Accent;
    Html.OnLink := FCtx.LinkClicked;
    Html.SetHtml(N.Utf8Of('description'));
    FStack.Add(Html);
    UpdateGate;
    Resize;
    FStack.VertScrollBar.Position := 0;
    // Conteúdo que não rola libera na hora; senão, só a 8 px do fim.
    FVM.ResetGate(FStack.Content.Height, FStack.ClientHeight);
  end;
  UpdateGate;
end;

procedure TBFSplashPanel.UpdateGate;
var
  S: string;
begin
  FHint.Visible := FVM.ShowScrollHint;
  FAck.Enabled := FVM.AckEnabled;
  S := FVM.AckButtonText(FCtx.Locale);
  if FAck.Caption <> S then
    FAck.SetCaption(S);
  FError.Visible := FVM.AckFailed;
  if FFooter.Visible and (FFooter.Height <> FFooter.MeasureHeight(Width)) then
    Resize;
end;

procedure TBFSplashPanel.GateTick(Sender: TObject);
begin
  if not Visible or not FVM.Locked then
    Exit;
  FVM.UpdateScroll(FStack.VertScrollBar.Position, FStack.ClientHeight, FStack.Content.Height);
  UpdateGate;
end;

procedure TBFSplashPanel.BuildCards;
var
  I: Integer;
  Card: TBFNoteCard;
  N: TBFJson;
begin
  FGateId := '';
  FFooter.Visible := False;
  FSkip.Visible := True;
  FStack.Color := BFClSurface;
  FStack.Content.Color := BFClSurface;
  FStack.Content.Box(clNone, clNone, 12, 12, 0);
  FHeader.Setup(FCtx.Primary, BFGlyph(#$E2#$9C#$A8, '*') + ' ' + FCtx.T('splash_eyebrow'), '',
    FCtx.T('splash_title'), FVM.CountText(FCtx.Locale));
  FStack.Clear;
  for I := 0 to FVM.Count - 1 do
  begin
    N := FVM.Note(I);
    Card := TBFNoteCard.CreateCard(FStack, FCtx, N,
      BFColor(FVM.NoteColor(I, FCtx.PrimaryHex), FCtx.Primary), FVM.ExpandedId = N.StrOf('id'),
      False, True, '', FCtx.T('splash_expand'), FCtx.T('splash_collapse'), '');
    Card.OnToggle := CardToggle;
    Card.OnMark := CardMark;
    if FVM.Marking then
      Card.MarkButton.Enabled := False;
    FStack.Add(Card);
  end;
end;

procedure TBFSplashPanel.Resize;
begin
  inherited Resize;
  FHeader.Height := FHeader.MeasureHeight(Width);
  if FFooter.Visible then
  begin
    FFooter.Height := FFooter.MeasureHeight(Width);
    FFooter.Relayout;
  end;
  FStack.Relayout;
end;

procedure TBFSplashPanel.CardToggle(Sender: TObject);
begin
  FVM.ToggleExpanded(TBFNoteCard(Sender).NoteId);
  Rebuild;
end;

procedure TBFSplashPanel.CardMark(Sender: TObject);
begin
  if FVM.Marking then
    Exit;
  FVM.Marking := True;
  BFJobs.Run(FCtx.Api, MarkWork, MarkDone, Self, [TBFNoteCard(Sender).NoteId]);
  Rebuild;
end;

function TBFSplashPanel.MarkWork(Job: TBFJob): TBFJson;
begin
  // "Marcar como lida" = vista POR USUÁRIO (widget_release_note_views), não o mark-read legado.
  Job.Api.MarkReleaseNoteSeen(Job.Arg(0));
  Result := Job.Api.ListReleaseNotes;
end;

procedure TBFSplashPanel.MarkDone(Job: TBFJob);
begin
  FVM.Marking := False;
  if not Job.Failed then
    FVM.ApplyList(Job.TakeData);
  Rebuild;
end;

procedure TBFSplashPanel.SkipClick(Sender: TObject);
begin
  // Só os cartões: release com ciência (agora ou publicada depois) trava do mesmo jeito.
  FVM.Dismiss;
  Rebuild;
end;

procedure TBFSplashPanel.AckClick(Sender: TObject);
begin
  if not FVM.BeginAck then
    Exit;
  UpdateGate; // ackSubmitting
  BFJobs.Run(FCtx.Api, AckWork, AckDone, Self, [FVM.AckNote.StrOf('id')]);
end;

function TBFSplashPanel.AckWork(Job: TBFJob): TBFJson;
begin
  Job.Api.AcknowledgeReleaseNote(Job.Arg(0));
  Result := nil;
end;

procedure TBFSplashPanel.AckDone(Job: TBFJob);
begin
  if Job.Failed then
  begin
    // A release fica na tela e aparece ackError (sem isso o clique parecia ignorado).
    FVM.AckError;
    if FCtx.CheckIdentity(Job) then
      Exit;
    // 409 ACK_NOT_REQUIRED: deixou de exigir ciência; a reconsulta a devolve como cartão.
    if Job.ErrorCode = 'ACK_NOT_REQUIRED' then
      Load;
    UpdateGate;
    Exit;
  end;
  FVM.AckDone(Job.Arg(0));
  Rebuild;
  // Confirma com o servidor (e traz uma release que tenha chegado nesse meio tempo).
  Load;
end;

{ ── TBFBannerForm ──────────────────────────────────────────────────────── }

constructor TBFBannerForm.CreateBanner(AOwner: TComponent; ACtx: TBFUIContext; Ids: TStrings);
begin
  inherited CreateNew(AOwner, 0);
  FCtx := ACtx;
  FVM := TBFBannerVM.Create;
  FVM.SetIds(Ids);
  // Modal em tela cheia que o usuário não fecha (sem borda, sem X, Esc/Alt+F4 travados).
  BorderStyle := bsNone;
  FormStyle := fsStayOnTop;
  WindowState := wsMaximized;
  Color := BFDarken(BFClText, 0.2);
  KeyPreview := True;
  OnCloseQuery := CloseQueryHandler;
  OnKeyDown := KeyDownHandler;
  OnResize := ResizeHandler;
  FCard := TPanel.Create(Self);
  FCard.Parent := Self;
  FCard.BevelOuter := bvNone;
  FCard.Caption := '';
  FCard.Color := clWhite;
  FHeader := TBFGradientHeader.Create(Self);
  FHeader.Parent := FCard;
  FHeader.Align := alTop;
  FHeader.TitleSize := 15;
  FFooter := TBFColumn.Create(Self);
  FFooter.Parent := FCard;
  FFooter.Align := alBottom;
  FFooter.Color := clWhite;
  FFooter.Box(clNone, clNone, 18, 14, 0);
  FHint := TBFText.Create(Self);
  FHint.Style(8, True, BFClSubtle);
  FHint.Alignment := taCenter;
  FHint.Text := FCtx.RN('scrollHint');
  FFooter.Add(FHint);
  FButton := TBFButton.Create(Self);
  FButton.ButtonHeight := 44;
  FButton.OnClick := ConfirmClick;
  FFooter.Add(FButton);
  FError := TBFText.Create(Self);
  FError.Style(8, False, BFColor('#b91c1c', BFClDanger));
  FError.Alignment := taCenter;
  FError.Text := FCtx.RN('ackError');
  FError.Visible := False;
  FFooter.Add(FError);
  FBody := TBFStack.Create(Self);
  FBody.Parent := FCard;
  FBody.Align := alClient;
  FBody.Color := clWhite;
  FBody.Content.Color := clWhite;
  FBody.Content.Box(clNone, clNone, 22, 18, 0);
  FHtml := TBFHtmlBox.Create(Self);
  FHtml.FontSize := 10;
  FHtml.TextColor := BFColor('#334155', BFClText);
  FHtml.OnLink := FCtx.LinkClicked;
  FBody.Add(FHtml);
  FGate := TTimer.Create(Self);
  FGate.Interval := 150;
  FGate.OnTimer := GateTick;
  FGate.Enabled := False;
  FButton.Enabled := False;
  BFJobs.Run(FCtx.Api, PendingWork, PendingDone, Self, []);
end;

destructor TBFBannerForm.Destroy;
begin
  BFJobs.CancelOwner(Self);
  FVM.Free;
  inherited Destroy;
end;

function TBFBannerForm.PendingWork(Job: TBFJob): TBFJson;
begin
  Result := Job.Api.ReleaseNotesPending;
end;

procedure TBFBannerForm.PendingDone(Job: TBFJob);
begin
  if Job.Failed then
  begin
    // Sem a fila não há o que confirmar: fecha e o launcher tenta no próximo ciclo.
    FCtx.CheckIdentity(Job);
    Finish;
    Exit;
  end;
  FVM.ApplyPending(Job.TakeData);
  if FVM.IsDone then
    Finish
  else
    ShowCurrent;
end;

procedure TBFBannerForm.LayoutCard;
var
  W, H, MaxH: Integer;
begin
  W := ClientWidth - 32;
  if W > 560 then
    W := 560;
  MaxH := ClientHeight - 32;
  FHeader.Height := FHeader.MeasureHeight(W);
  FFooter.Height := FFooter.MeasureHeight(W);
  H := FHeader.Height + FFooter.Height + FHtml.MeasureHeight(W - 44) + 36;
  if H > MaxH then
    H := MaxH;
  FCard.SetBounds((ClientWidth - W) div 2, (ClientHeight - H) div 2, W, H);
  FFooter.Relayout;
  FBody.Relayout;
end;

procedure TBFBannerForm.ResizeHandler(Sender: TObject);
begin
  if FVM.Current <> nil then
    LayoutCard;
end;

procedure TBFBannerForm.ShowCurrent;
var
  N, P: TBFJson;
  Accent: TColor;
  Line: string;
begin
  N := FVM.Current;
  if N = nil then
    Exit;
  Accent := BFColor(FVM.Color(FCtx.PrimaryHex), FCtx.Primary);
  P := N.ObjOf('product');
  Line := 'v' + N.StrOf('version');
  if P <> nil then
    Line := P.StrOf('name') + '   ' + Line;
  if FVM.RequireAck then
    FHeader.Setup(Accent, BFGlyph(#$E2#$9A#$A0, '!') + ' ' + FVM.EyebrowText(FCtx.Locale), Line,
      N.StrOf('title'), FVM.CounterText)
  else
    FHeader.Setup(Accent, BFGlyph(#$E2#$9C#$A8, '*') + ' ' + FVM.EyebrowText(FCtx.Locale), Line,
      N.StrOf('title'), FVM.CounterText);
  FHtml.SetHtml(N.Utf8Of('description'));
  FButton.Accent := Accent;
  FButton.Caption := FVM.ButtonText(FCtx.Locale);
  LayoutCard;
  FBody.VertScrollBar.Position := 0;
  // Conteúdo que não rola libera na hora; senão, só a 8 px do fim.
  FVM.ResetGate(FBody.Content.Height, FBody.ClientHeight);
  GateTick(nil);
  FGate.Enabled := True;
end;

procedure TBFBannerForm.UpdateFooter;
var
  S: string;
begin
  FHint.Visible := FVM.ShowScrollHint;
  FButton.Enabled := FVM.ConfirmEnabled;
  S := FVM.ButtonText(FCtx.Locale);
  if FButton.Caption <> S then
    FButton.SetCaption(S);
  FError.Visible := FVM.Failed;
  if FFooter.Height <> FFooter.MeasureHeight(FCard.Width) then
    LayoutCard;
end;

procedure TBFBannerForm.GateTick(Sender: TObject);
begin
  FVM.UpdateScroll(FBody.VertScrollBar.Position, FBody.ClientHeight, FBody.Content.Height);
  UpdateFooter;
end;

procedure TBFBannerForm.ConfirmClick(Sender: TObject);
var
  N: TBFJson;
  Action: string;
begin
  N := FVM.Current;
  if (N = nil) or not FVM.BeginConfirm then
    Exit;
  UpdateFooter; // ackSubmitting
  if FVM.RequireAck then Action := 'ack' else Action := 'seen';
  BFJobs.Run(FCtx.Api, ConfirmWork, ConfirmDone, Self, [N.StrOf('id'), Action]);
end;

function TBFBannerForm.ConfirmWork(Job: TBFJob): TBFJson;
begin
  if Job.Arg(1) = 'ack' then
    Job.Api.AcknowledgeReleaseNote(Job.Arg(0))
  else
    Job.Api.MarkReleaseNoteSeen(Job.Arg(0));
  Result := nil;
end;

procedure TBFBannerForm.ConfirmDone(Job: TBFJob);
begin
  if Job.Failed then
  begin
    // Falha de rede: a release fica na tela e aparece ackError (limpo ao tentar de novo).
    FVM.ConfirmFailed;
    FCtx.CheckIdentity(Job);
    UpdateFooter;
    Exit;
  end;
  if FVM.Advance then
    Finish
  else
    ShowCurrent;
end;

procedure TBFBannerForm.Finish;
begin
  if FDone then
    Exit;
  FDone := True;
  FGate.Enabled := False;
  FAllowClose := True;
  Hide;
  // Equivale ao bfocus:rn:done: fecha e o launcher consulta o estado de novo.
  FCtx.Widget.HostBannerDone;
  Release;
end;

procedure TBFBannerForm.CloseQueryHandler(Sender: TObject; var CanClose: Boolean);
begin
  CanClose := FAllowClose;
end;

procedure TBFBannerForm.KeyDownHandler(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  if (Key = 27) or ((Key = 115) and (ssAlt in Shift)) then
    Key := 0;
end;

{ ── TBFHistoryForm ─────────────────────────────────────────────────────── }

constructor TBFHistoryForm.CreateHistory(AOwner: TComponent; ACtx: TBFUIContext);
begin
  inherited CreateNew(AOwner, 0);
  FCtx := ACtx;
  FVM := TBFHistoryVM.Create;
  BorderStyle := bsSizeToolWin;
  Caption := FCtx.RN('historyTitle');
  Color := BFClSurface;
  Width := 400;
  Height := 620;
  Left := Screen.WorkAreaRect.Right - Width - 24;
  Top := Screen.WorkAreaRect.Bottom - Height - 24;
  OnResize := ResizeHandler;
  FHeader := TBFGradientHeader.Create(Self);
  FHeader.Parent := Self;
  FHeader.Align := alTop;
  FClose := TBFButton.Create(Self);
  FClose.Parent := FHeader;
  FClose.Kind := bkHeader;
  FClose.Accent := FCtx.Primary;
  FClose.ButtonHeight := 32;
  FClose.Caption := BFGlyph(#$E2#$9C#$95, 'X');
  FClose.Hint := FCtx.RN('close');
  FClose.ShowHint := True;
  FClose.OnClick := CloseClick;
  FStack := TBFStack.Create(Self);
  FStack.Parent := Self;
  FStack.Align := alClient;
  FStack.Content.Box(clNone, clNone, 12, 12, 0);
  Reload;
end;

destructor TBFHistoryForm.Destroy;
begin
  BFJobs.CancelOwner(Self);
  FVM.Free;
  inherited Destroy;
end;

procedure TBFHistoryForm.Reload;
begin
  FVM.Loading := True;
  Rebuild;
  // O histórico NÃO marca nada como visto.
  BFJobs.Run(FCtx.Api, ChangelogWork, ChangelogDone, Self, []);
end;

function TBFHistoryForm.ChangelogWork(Job: TBFJob): TBFJson;
begin
  Result := Job.Api.ReleaseNotesChangelog;
end;

procedure TBFHistoryForm.ChangelogDone(Job: TBFJob);
begin
  if Job.Failed then
  begin
    FCtx.CheckIdentity(Job);
    FVM.ApplyChangelog(nil);
  end
  else
    FVM.ApplyChangelog(Job.TakeData);
  Rebuild;
end;

procedure TBFHistoryForm.Rebuild;
var
  I: Integer;
  N: TBFJson;
  Card: TBFNoteCard;
  Txt: TBFText;
  Sub: string;
begin
  Sub := '';
  if FVM.CurrentVersion <> '' then
    Sub := FCtx.RN('currentLabel') + ': v' + FVM.CurrentVersion;
  FHeader.Setup(FCtx.Primary, '', FCtx.TenantName, FCtx.RN('historyTitle'), Sub);
  FStack.Clear;
  if FVM.Loading then
  begin
    Txt := TBFText.Create(FStack);
    Txt.Style(9, False, BFClSubtle);
    Txt.Alignment := taCenter;
    Txt.MarginY := 24;
    Txt.Text := BFFromUtf8(#$E2#$80#$A6);
    FStack.Add(Txt);
  end
  else if FVM.IsEmpty then
  begin
    Txt := TBFText.Create(FStack);
    Txt.Style(9, False, BFClSubtle);
    Txt.Alignment := taCenter;
    Txt.MarginY := 24;
    Txt.Text := FCtx.RN('emptyHistory');
    FStack.Add(Txt);
  end
  else
    for I := 0 to FVM.Count - 1 do
    begin
      N := FVM.Note(I);
      Card := TBFNoteCard.CreateCard(FStack, FCtx, N,
        BFColor(FVM.NoteColor(I, FCtx.PrimaryHex), FCtx.Primary), FVM.ExpandedId = N.StrOf('id'),
        N.BoolOf('is_current'), False, FVM.DateText(I, FCtx.Locale), FCtx.RN('expand'),
        FCtx.RN('collapse'), FCtx.RN('currentLabel'));
      Card.OnToggle := CardToggle;
      FStack.Add(Card);
    end;
  ResizeHandler(nil);
end;

procedure TBFHistoryForm.ResizeHandler(Sender: TObject);
begin
  FHeader.Height := FHeader.MeasureHeight(ClientWidth);
  FClose.SetBounds(ClientWidth - 48, 14, 32, 32);
  FStack.Relayout;
end;

procedure TBFHistoryForm.CardToggle(Sender: TObject);
begin
  FVM.ToggleExpanded(TBFNoteCard(Sender).NoteId);
  Rebuild;
end;

procedure TBFHistoryForm.CloseClick(Sender: TObject);
begin
  Hide;
end;

end.
