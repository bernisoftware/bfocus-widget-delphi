unit BFocusUIControls;

{ Controles da UI nativa (Fase 6), montados em código e compartilhados pela VCL
  (Delphi 7+) e pelo LCL (Lazarus): sem .dfm/.lfm. Pintura própria (cantos arredondados,
  cores dos tokens) porque TButton/TLabel nativos não aceitam a cor da marca na VCL
  temática. O layout é vertical e medido (IBFMeasurable): altura calculada para a largura
  disponível, igual nas duas bibliotecas.
  HTML do conteúdo: THtmlViewer (componente livre) com BFOCUS_HTMLVIEWER; sem ele, texto
  (diferença aceita §10 do behavior spec). }

{$I BFocusDefines.inc}

interface

uses
  SysUtils, Classes, Controls, Graphics, StdCtrls, ExtCtrls, Forms, Dialogs,
{$IFDEF BF_FPC}
  LCLIntf, LCLType,
{$ELSE}
  Windows, ShellAPI,
{$ENDIF}
{$IFDEF BFOCUS_HTMLVIEWER}
  HtmlGlobals, HtmlView,
{$ENDIF}
  BFocusText, BFocusFormat, BFocusGraphics, BFocusTokens, BFocusI18n;

const
  BF_PAD = 16;
  BF_GAP = 8;

type
  IBFMeasurable = interface
    ['{C7A1E0F2-3B94-4D58-8E6A-1F2B3C4D5E6F}']
    function MeasureHeight(AWidth: Integer): Integer;
  end;

  TBFLinkEvent = procedure(Sender: TObject; const Url: string) of object;

  { Texto com quebra de linha, opcionalmente numa caixa arredondada (avisos, rótulos). }
  TBFText = class(TGraphicControl, IBFMeasurable)
  private
    FText: string;
    FTextColor: TColor;
    FFontSize: Integer;
    FBold: Boolean;
    FItalic: Boolean;
    FAlignment: TAlignment;
    FBoxColor: TColor;
    FBorderColor: TColor;
    FMarginX, FMarginY, FPadX, FPadY, FRadius: Integer;
    procedure SetText(const Value: string);
    procedure PrepareFont(F: TFont);
  protected
    procedure Paint; override;
  public
    constructor Create(AOwner: TComponent); override;
    function MeasureHeight(AWidth: Integer): Integer;
    procedure Style(ASize: Integer; ABold: Boolean; AColor: TColor);
    procedure Box(ABox, ABorder: TColor; APadX, APadY: Integer);
    property Text: string read FText write SetText;
    property TextColor: TColor read FTextColor write FTextColor;
    property FontSize: Integer read FFontSize write FFontSize;
    property Bold: Boolean read FBold write FBold;
    property Italic: Boolean read FItalic write FItalic;
    property Alignment: TAlignment read FAlignment write FAlignment;
    property BoxColor: TColor read FBoxColor write FBoxColor;
    property BorderColor: TColor read FBorderColor write FBorderColor;
    property MarginX: Integer read FMarginX write FMarginX;
    property MarginY: Integer read FMarginY write FMarginY;
    property Radius: Integer read FRadius write FRadius;
    property OnClick;
  end;

  TBFButtonKind = (bkPrimary, bkOutline, bkLink, bkGhost, bkDanger, bkNeutral, bkHeader);

  TBFButton = class(TCustomControl, IBFMeasurable)
  private
    FKind: TBFButtonKind;
    FAccent: TColor;
    FFontSize: Integer;
    FBusy: Boolean;
    FButtonHeight: Integer;
    FMarginX, FMarginY: Integer;
    FAlignment: TAlignment;
    procedure SetBusy(Value: Boolean);
  protected
    procedure Paint; override;
    procedure KeyDown(var Key: Word; Shift: TShiftState); override;
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
  public
    constructor Create(AOwner: TComponent); override;
    function MeasureHeight(AWidth: Integer): Integer;
    function PreferredWidth: Integer;
    procedure SetCaption(const Value: string);
    property Kind: TBFButtonKind read FKind write FKind;
    property Accent: TColor read FAccent write FAccent;
    property FontSize: Integer read FFontSize write FFontSize;
    property Busy: Boolean read FBusy write SetBusy;
    property ButtonHeight: Integer read FButtonHeight write FButtonHeight;
    property MarginX: Integer read FMarginX write FMarginX;
    property MarginY: Integer read FMarginY write FMarginY;
    property Alignment: TAlignment read FAlignment write FAlignment;
    property Caption;
    property Enabled;
    property OnClick;
  end;

  { Chips (tipo e prioridade do novo chamado), com quebra de linha. }
  TBFChipBar = class(TCustomControl, IBFMeasurable)
  private
    FCaptions: TStringList;
    FKeys: TStringList;
    FColors: array of TColor;
    FSelected: string;
    FOnChange: TNotifyEvent;
    FRects: array of TRect;
    procedure Layout(AWidth: Integer; Apply: Boolean; out H: Integer);
    procedure SetSelected(const Value: string);
  protected
    procedure Paint; override;
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure Resize; override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    procedure AddChip(const Key, ACaption: string; AColor: TColor);
    function MeasureHeight(AWidth: Integer): Integer;
    property Selected: string read FSelected write SetSelected;
    property OnChange: TNotifyEvent read FOnChange write FOnChange;
  end;

  { Coluna medida: filhos empilhados com espaçamento, dentro de uma caixa opcional. }
  TBFColumn = class(TCustomControl, IBFMeasurable)
  private
    FItems: TList;
    FGap: Integer;
    FPadX, FPadY, FMarginX, FMarginY, FRadius: Integer;
    FBoxColor, FBorderColor, FAccentBorder: TColor;
    FBorderWidth: Integer;
    function ChildHeight(C: TControl; W: Integer): Integer;
  protected
    procedure Paint; override;
    procedure Resize; override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    function Add(C: TControl): TControl;
    procedure ClearItems;
    function ItemCount: Integer;
    function MeasureHeight(AWidth: Integer): Integer;
    procedure Relayout;
    procedure Box(ABox, ABorder: TColor; APadX, APadY, ARadius: Integer);
    property Gap: Integer read FGap write FGap;
    property MarginX: Integer read FMarginX write FMarginX;
    property MarginY: Integer read FMarginY write FMarginY;
    property BoxColor: TColor read FBoxColor write FBoxColor;
    property BorderColor: TColor read FBorderColor write FBorderColor;
    property BorderWidthPx: Integer read FBorderWidth write FBorderWidth;
    property Color;
    property OnClick;
  end;

  { Linha: filhos lado a lado; Width = -1 ocupa o que sobrar. }
  TBFRow = class(TCustomControl, IBFMeasurable)
  private
    FItems: TList;
    FWidths: array of Integer;
    FGap, FMarginX, FRowHeight: Integer;
  protected
    procedure Paint; override;
    procedure Resize; override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    function Add(C: TControl; AWidth: Integer): TControl;
    procedure Relayout;
    function MeasureHeight(AWidth: Integer): Integer;
    property Gap: Integer read FGap write FGap;
    property MarginX: Integer read FMarginX write FMarginX;
    property RowHeight: Integer read FRowHeight write FRowHeight;
    property Color;
  end;

  { Área rolável com uma coluna dentro (listas, conversas). }
  TBFStack = class(TScrollBox)
  private
    FContent: TBFColumn;
  protected
    procedure Resize; override;
  public
    constructor Create(AOwner: TComponent); override;
    procedure Relayout;
    procedure Clear;
    function Add(C: TControl): TControl;
    procedure ScrollToBottom;
    function NearBottom: Boolean;
    function ScrollPos: Integer;
    function ScrollMax: Integer;
    property Content: TBFColumn read FContent;
  end;

  { Conteúdo HTML sanitizado do servidor (UTF-8). }
  TBFHtmlBox = class(TCustomControl, IBFMeasurable)
  private
    FHtml: TBFRaw;
    FText: string;
    FTextColor: TColor;
    FLinkColor: TColor;
    FFontSize: Integer;
    FOnLink: TBFLinkEvent;
{$IFDEF BFOCUS_HTMLVIEWER}
    FViewer: THtmlViewer;
    procedure HotSpotClick(Sender: TObject; const SRC: ThtString; var Handled: Boolean);
{$ENDIF}
  protected
    procedure Paint; override;
    procedure Resize; override;
  public
    constructor Create(AOwner: TComponent); override;
    procedure SetHtml(const Html: TBFRaw);
    function MeasureHeight(AWidth: Integer): Integer;
    property TextColor: TColor read FTextColor write FTextColor;
    property LinkColor: TColor read FLinkColor write FLinkColor;
    property FontSize: Integer read FFontSize write FFontSize;
    property OnLink: TBFLinkEvent read FOnLink write FOnLink;
    property Color;
  end;

  { Editor da descrição/resposta: texto simples com negrito, itálico, riscado, listas,
    citação, código e link (marcação leve → HTML; diferença aceita §10). O link usa o
    campo sob a barra: Enter aplica, Esc cancela, vazio remove, sem esquema = https://. }
  TBFEditor = class(TCustomControl, IBFMeasurable)
  private
    FToolbar: TBFRow;
    FMemo: TMemo;
    FHint: TBFText;
    FLinkRow: TBFRow;
    FLinkEdit: TEdit;
    FLinkApply: TBFButton;
    FLinkRemove: TBFButton;
    FMinHeight: Integer;
    FOnChange: TNotifyEvent;
    FSelStart, FSelLength: Integer;
    procedure ToolClick(Sender: TObject);
    procedure MemoChange(Sender: TObject);
    procedure LinkKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure LinkApplyClick(Sender: TObject);
    procedure LinkRemoveClick(Sender: TObject);
    procedure Wrap(const Marker: string);
    procedure PrefixLines(const Prefix: string; Numbered: Boolean);
    procedure ShowLinkRow(Show: Boolean);
    procedure ApplyLink(const Url: string);
  protected
    procedure Resize; override;
    procedure Paint; override;
  public
    constructor CreateEditor(AOwner: TComponent; const Locale, Placeholder: string;
      AMinHeight: Integer);
    function MeasureHeight(AWidth: Integer): Integer;
    function Html: string;
    function IsEmpty: Boolean;
    procedure Clear;
    procedure SetText(const S: string);
    property Memo: TMemo read FMemo;
    property OnChange: TNotifyEvent read FOnChange write FOnChange;
  end;

  { Anexo: cartão de arquivo ou prévia da imagem (quando carregada). }
  TBFAttachmentCard = class(TCustomControl, IBFMeasurable)
  private
    FFileName: string;
    FMime: string;
    FSize: Int64;
    FPicture: TPicture;
    FAccent: TColor;
    FMarginX: Integer;
    FRightAlign: Boolean;
    FClickable: Boolean;
  protected
    procedure Paint; override;
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    procedure Setup(const AFileName, AMime: string; ASize: Int64; AAccent: TColor);
    function MeasureHeight(AWidth: Integer): Integer;
    function HasPicture: Boolean;
    property Picture: TPicture read FPicture;
    property MarginX: Integer read FMarginX write FMarginX;
    property RightAlign: Boolean read FRightAlign write FRightAlign;
    property Clickable: Boolean read FClickable write FClickable;
    property OnClick;
  end;

  { Espaço vertical fixo. }
  TBFSpacer = class(TGraphicControl)
  public
    constructor CreateH(AOwner: TComponent; AHeight: Integer);
  end;

var
  { Neutros de tokens.json (preenchidos na inicialização). }
  BFClText, BFClMuted, BFClSubtle, BFClBorder, BFClSurface, BFClBg, BFClSlate600,
  BFClChip, BFClDanger, BFClAmberBg, BFClAmberBorder, BFClAmberText: TColor;
  BFFontName: string;

procedure BFStyleFont(F: TFont; ASize: Integer; ABold: Boolean; AColor: TColor);
{ Altura do texto quebrado na largura (medição fora de tela). }
function BFTextHeight(F: TFont; const S: string; AWidth: Integer): Integer;
function BFTextWidth(F: TFont; const S: string): Integer;
procedure BFDrawTextIn(C: TCanvas; const S: string; R: TRect; Align: TAlignment;
  WordWrap: Boolean);
{ Pílula de status: fundo translúcido + texto em maiúsculas. Devolve a largura. }
function BFDrawPill(C: TCanvas; X, Y: Integer; const Text: string; AColor: TColor;
  RightAligned: Boolean): Integer;
{ Gradiente diagonal aproximado (cabeçalhos do splash/banner/histórico). }
procedure BFGradient(C: TCanvas; R: TRect; C1, C2: TColor);
function BFOpenUrl(const Url: string): Boolean;
function BFPickFiles(Multi: Boolean; Files: TStrings): Boolean;
function BFSaveAs(const FileName: string; out Path: string): Boolean;
{ PNG/JPEG/GIF → TPicture (LCL e Delphi 2010+; Delphi 7 só JPEG). }
function BFLoadPicture(Stream: TStream; const Mime: string; Pic: TPicture): Boolean;
function BFMeasure(C: TControl; AWidth: Integer): Integer;
{ Emoji onde a biblioteca desenha (LCL, Delphi 2009+); sigla ASCII no Delphi 7. }
function BFGlyph(const Utf8: TBFRaw; const Fallback: string): string;

implementation

{$IFNDEF BF_FPC}
  {$IFNDEF BF_D2010}
uses
  jpeg;
  {$ENDIF}
{$ENDIF}

var
  GMeasure: TBitmap;

function MeasureCanvas: TCanvas;
begin
  if GMeasure = nil then
  begin
    GMeasure := TBitmap.Create;
    GMeasure.Width := 16;
    GMeasure.Height := 16;
  end;
  Result := GMeasure.Canvas;
end;

procedure BFStyleFont(F: TFont; ASize: Integer; ABold: Boolean; AColor: TColor);
begin
  if BFFontName <> '' then
    F.Name := BFFontName;
  F.Size := ASize;
  if ABold then
    F.Style := [fsBold]
  else
    F.Style := [];
  F.Color := AColor;
end;

function DTFlags(Align: TAlignment; WordWrap: Boolean): Cardinal;
begin
  Result := DT_NOPREFIX;
  if WordWrap then
    Result := Result or DT_WORDBREAK
  else
    Result := Result or DT_SINGLELINE or DT_END_ELLIPSIS;
  case Align of
    taCenter: Result := Result or DT_CENTER;
    taRightJustify: Result := Result or DT_RIGHT;
  else
    Result := Result or DT_LEFT;
  end;
end;

function BFTextHeight(F: TFont; const S: string; AWidth: Integer): Integer;
var
  C: TCanvas;
  R: TRect;
begin
  if (S = '') or (AWidth <= 0) then
  begin
    Result := 0;
    Exit;
  end;
  C := MeasureCanvas;
  C.Font.Assign(F);
  R := Rect(0, 0, AWidth, 0);
  DrawText(C.Handle, PChar(S), Length(S), R, DTFlags(taLeftJustify, True) or DT_CALCRECT);
  Result := R.Bottom - R.Top;
end;

function BFTextWidth(F: TFont; const S: string): Integer;
var
  C: TCanvas;
begin
  C := MeasureCanvas;
  C.Font.Assign(F);
  Result := C.TextWidth(S);
end;

procedure BFDrawTextIn(C: TCanvas; const S: string; R: TRect; Align: TAlignment;
  WordWrap: Boolean);
begin
  C.Brush.Style := bsClear;
  DrawText(C.Handle, PChar(S), Length(S), R, DTFlags(Align, WordWrap));
  C.Brush.Style := bsSolid;
end;

function BFDrawPill(C: TCanvas; X, Y: Integer; const Text: string; AColor: TColor;
  RightAligned: Boolean): Integer;
var
  T: string;
  W, H: Integer;
begin
  T := AnsiUpperCase(Text);
  C.Font.Size := 7;
  C.Font.Style := [fsBold];
  W := C.TextWidth(T) + 16;
  H := C.TextHeight(T) + 4;
  if RightAligned then
    X := X - W;
  C.Brush.Color := BFMix(AColor, clWhite, 0.10);
  C.Pen.Color := C.Brush.Color;
  C.RoundRect(X, Y, X + W, Y + H, H, H);
  C.Font.Color := AColor;
  C.Brush.Style := bsClear;
  C.TextOut(X + 8, Y + 2, T);
  C.Brush.Style := bsSolid;
  Result := W;
end;

procedure BFGradient(C: TCanvas; R: TRect; C1, C2: TColor);
var
  I, Steps: Integer;
begin
  Steps := R.Right - R.Left;
  if Steps <= 0 then
    Exit;
  // Horizontal da cor da marca para ela escurecida (o web usa 135°).
  for I := 0 to Steps - 1 do
  begin
    C.Pen.Color := BFMix(C2, C1, I / Steps);
    C.MoveTo(R.Left + I, R.Top);
    C.LineTo(R.Left + I, R.Bottom);
  end;
end;

function BFOpenUrl(const Url: string): Boolean;
var
  Scheme: string;
begin
  Result := False;
  Scheme := BFUrlScheme(Url);
  if not ((Scheme = 'https') or (Scheme = 'http') or BFStartsText(Url, 'mailto:') or
    BFStartsText(Url, 'tel:')) then
    Exit;
{$IFDEF BF_FPC}
  Result := OpenURL(Url);
{$ELSE}
  Result := ShellExecute(0, 'open', PChar(Url), nil, nil, SW_SHOWNORMAL) > 32;
{$ENDIF}
end;

function BFPickFiles(Multi: Boolean; Files: TStrings): Boolean;
var
  D: TOpenDialog;
begin
  D := TOpenDialog.Create(nil);
  try
    D.Options := [ofFileMustExist, ofEnableSizing];
    if Multi then
      D.Options := D.Options + [ofAllowMultiSelect];
    Result := D.Execute;
    if Result then
      Files.Assign(D.Files);
  finally
    D.Free;
  end;
end;

function BFSaveAs(const FileName: string; out Path: string): Boolean;
var
  D: TSaveDialog;
begin
  D := TSaveDialog.Create(nil);
  try
    D.FileName := ExtractFileName(FileName);
    D.Options := [ofOverwritePrompt, ofEnableSizing];
    Result := D.Execute;
    if Result then
      Path := D.FileName;
  finally
    D.Free;
  end;
end;

function BFLoadPicture(Stream: TStream; const Mime: string; Pic: TPicture): Boolean;
{$IFDEF BF_FPC}
begin
  Result := False;
  try
    Stream.Position := 0;
    Pic.LoadFromStream(Stream);
    Result := (Pic.Graphic <> nil) and not Pic.Graphic.Empty;
  except
    Result := False;
  end;
end;
{$ELSE}
  {$IFDEF BF_D2010}
var
  W: TWICImage;
begin
  Result := False;
  W := TWICImage.Create;
  try
    try
      Stream.Position := 0;
      W.LoadFromStream(Stream);
      Pic.Assign(W);
      Result := not W.Empty;
    except
      Result := False;
    end;
  finally
    W.Free;
  end;
end;
  {$ELSE}
var
  J: TJPEGImage;
begin
  Result := False;
  if Pos('jpeg', BFLowerAscii(Mime)) = 0 then
    Exit; // Delphi 7 sem PNG/GIF: fica o cartão de arquivo
  J := TJPEGImage.Create;
  try
    try
      Stream.Position := 0;
      J.LoadFromStream(Stream);
      Pic.Assign(J);
      Result := True;
    except
      Result := False;
    end;
  finally
    J.Free;
  end;
end;
  {$ENDIF}
{$ENDIF}

function BFMeasure(C: TControl; AWidth: Integer): Integer;
var
  M: IBFMeasurable;
begin
  if Supports(C, IBFMeasurable, M) then
    Result := M.MeasureHeight(AWidth)
  else
    Result := C.Height;
end;

function BFGlyph(const Utf8: TBFRaw; const Fallback: string): string;
begin
{$IFDEF BF_UNICODE}
  Result := BFFromUtf8(Utf8);
{$ELSE}
  {$IFDEF BF_FPC}
  Result := BFFromUtf8(Utf8);
  {$ELSE}
  Result := Fallback;
  {$ENDIF}
{$ENDIF}
end;

function ParentBg(C: TControl): TColor;
begin
  if C.Parent <> nil then
    Result := C.Parent.Brush.Color
  else
    Result := BFClBg;
end;

{ ── TBFText ─────────────────────────────────────────────────────────────── }

constructor TBFText.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FTextColor := BFClText;
  FFontSize := 9;
  FAlignment := taLeftJustify;
  FBoxColor := clNone;
  FBorderColor := clNone;
  FRadius := 8;
  Height := 18;
end;

procedure TBFText.SetText(const Value: string);
begin
  FText := Value;
  Invalidate;
end;

procedure TBFText.Style(ASize: Integer; ABold: Boolean; AColor: TColor);
begin
  FFontSize := ASize;
  FBold := ABold;
  FTextColor := AColor;
end;

procedure TBFText.Box(ABox, ABorder: TColor; APadX, APadY: Integer);
begin
  FBoxColor := ABox;
  FBorderColor := ABorder;
  FPadX := APadX;
  FPadY := APadY;
end;

procedure TBFText.PrepareFont(F: TFont);
begin
  BFStyleFont(F, FFontSize, FBold, FTextColor);
  if FItalic then
    F.Style := F.Style + [fsItalic];
end;

function TBFText.MeasureHeight(AWidth: Integer): Integer;
var
  F: TFont;
begin
  F := TFont.Create;
  try
    PrepareFont(F);
    Result := BFTextHeight(F, FText, AWidth - 2 * (FMarginX + FPadX)) + 2 * (FMarginY + FPadY);
  finally
    F.Free;
  end;
end;

procedure TBFText.Paint;
var
  R: TRect;
begin
  with Canvas do
  begin
    if (FBoxColor <> clNone) or (FBorderColor <> clNone) then
    begin
      if FBoxColor <> clNone then Brush.Color := FBoxColor else Brush.Style := bsClear;
      if FBorderColor <> clNone then Pen.Color := FBorderColor else Pen.Color := FBoxColor;
      RoundRect(FMarginX, FMarginY, Width - FMarginX, Height - FMarginY, FRadius, FRadius);
      Brush.Style := bsSolid;
    end;
    PrepareFont(Font);
    R := Rect(FMarginX + FPadX, FMarginY + FPadY, Width - FMarginX - FPadX, Height - FMarginY - FPadY);
    BFDrawTextIn(Canvas, FText, R, FAlignment, True);
  end;
end;

{ ── TBFButton ──────────────────────────────────────────────────────────── }

constructor TBFButton.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FKind := bkPrimary;
  FAccent := BFColor(BF_BRAND_FALLBACK, clNavy);
  FFontSize := 9;
  FButtonHeight := 36;
  FAlignment := taCenter;
  TabStop := True;
  Cursor := crHandPoint;
  Width := 120;
  Height := FButtonHeight;
  ControlStyle := ControlStyle - [csSetCaption];
end;

procedure TBFButton.SetCaption(const Value: string);
begin
  Caption := Value;
  Invalidate;
end;

procedure TBFButton.SetBusy(Value: Boolean);
begin
  FBusy := Value;
  Invalidate;
end;

function TBFButton.MeasureHeight(AWidth: Integer): Integer;
begin
  Result := FButtonHeight + 2 * FMarginY;
end;

function TBFButton.PreferredWidth: Integer;
var
  F: TFont;
begin
  F := TFont.Create;
  try
    BFStyleFont(F, FFontSize, True, clBlack);
    Result := BFTextWidth(F, Caption) + 24 + 2 * FMarginX;
  finally
    F.Free;
  end;
end;

procedure TBFButton.Paint;
var
  R: TRect;
  Fill, Border, Fg: TColor;
  Txt: string;
begin
  R := Rect(FMarginX, FMarginY, Width - FMarginX, Height - FMarginY);
  Fill := clNone;
  Border := clNone;
  case FKind of
    bkPrimary: begin Fill := FAccent; Fg := clWhite; end;
    bkDanger: begin Fill := BFClDanger; Fg := clWhite; end;
    bkOutline: begin Fill := clWhite; Border := FAccent; Fg := FAccent; end;
    bkNeutral: begin Fill := clWhite; Border := BFClBorder; Fg := BFClSlate600; end;
    bkGhost: begin Fill := BFClChip; Fg := BFClSlate600; end;
    bkHeader: begin Fill := BFMix(clWhite, FAccent, 0.15); Fg := clWhite; end;
  else
    Fg := FAccent; // bkLink
  end;
  if not Enabled then
  begin
    if FKind in [bkPrimary, bkDanger] then Fill := $00E1D5CB // #cbd5e1
    else Fg := BFClSubtle;
  end;
  with Canvas do
  begin
    Brush.Color := ParentBg(Self);
    FillRect(Rect(0, 0, Width, Height));
    if Fill <> clNone then
    begin
      Brush.Color := Fill;
      if Border <> clNone then Pen.Color := Border else Pen.Color := Fill;
      RoundRect(R.Left, R.Top, R.Right, R.Bottom, 10, 10);
    end;
    BFStyleFont(Font, FFontSize, True, Fg);
    Txt := Caption;
    if FBusy then
      Txt := BFFromUtf8(#$E2#$80#$A6); // "…" enquanto envia
    if FKind = bkLink then
      BFDrawTextIn(Canvas, Txt, Rect(R.Left, R.Top, R.Right, R.Bottom), FAlignment, True)
    else
    begin
      R.Top := R.Top + (R.Bottom - R.Top - TextHeight('Ag')) div 2;
      BFDrawTextIn(Canvas, Txt, Rect(R.Left + 8, R.Top, R.Right - 8, R.Bottom), FAlignment, False);
    end;
    if Focused and (FKind <> bkLink) then
    begin
      Brush.Style := bsClear;
      Pen.Color := BFClSubtle;
      Pen.Style := psDot;
      RoundRect(FMarginX + 2, FMarginY + 2, Width - FMarginX - 2, Height - FMarginY - 2, 8, 8);
      Pen.Style := psSolid;
      Brush.Style := bsSolid;
    end;
  end;
end;

procedure TBFButton.KeyDown(var Key: Word; Shift: TShiftState);
begin
  inherited KeyDown(Key, Shift);
  if ((Key = 13) or (Key = 32)) and Enabled then
  begin
    Key := 0;
    Click;
  end;
end;

procedure TBFButton.MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  inherited MouseUp(Button, Shift, X, Y);
  if CanFocus then
    SetFocus;
end;

{ ── TBFChipBar ─────────────────────────────────────────────────────────── }

constructor TBFChipBar.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FCaptions := TStringList.Create;
  FKeys := TStringList.Create;
  Cursor := crHandPoint;
  Height := 30;
end;

destructor TBFChipBar.Destroy;
begin
  FCaptions.Free;
  FKeys.Free;
  inherited Destroy;
end;

procedure TBFChipBar.AddChip(const Key, ACaption: string; AColor: TColor);
begin
  FKeys.Add(Key);
  FCaptions.Add(ACaption);
  SetLength(FColors, FKeys.Count);
  FColors[FKeys.Count - 1] := AColor;
  Invalidate;
end;

procedure TBFChipBar.SetSelected(const Value: string);
begin
  FSelected := Value;
  Invalidate;
end;

procedure TBFChipBar.Layout(AWidth: Integer; Apply: Boolean; out H: Integer);
var
  I, X, Y, W: Integer;
  F: TFont;
begin
  F := TFont.Create;
  try
    BFStyleFont(F, 8, True, clBlack);
    X := 0;
    Y := 0;
    if Apply then
      SetLength(FRects, FKeys.Count);
    for I := 0 to FKeys.Count - 1 do
    begin
      W := BFTextWidth(F, FCaptions[I]) + 28;
      if (X > 0) and (X + W > AWidth) then
      begin
        X := 0;
        Inc(Y, 34);
      end;
      if Apply then
        FRects[I] := Rect(X, Y, X + W, Y + 28);
      Inc(X, W + 6);
    end;
    H := Y + 30;
  finally
    F.Free;
  end;
end;

function TBFChipBar.MeasureHeight(AWidth: Integer): Integer;
begin
  Layout(AWidth, False, Result);
end;

procedure TBFChipBar.Resize;
var
  H: Integer;
begin
  inherited Resize;
  Layout(Width, True, H);
end;

procedure TBFChipBar.Paint;
var
  I, H: Integer;
  Sel: Boolean;
begin
  Layout(Width, True, H);
  with Canvas do
  begin
    Brush.Color := ParentBg(Self);
    FillRect(Rect(0, 0, Width, Height));
    for I := 0 to FKeys.Count - 1 do
    begin
      Sel := FKeys[I] = FSelected;
      if Sel then
      begin
        Brush.Color := FColors[I];
        Pen.Color := FColors[I];
      end
      else
      begin
        Brush.Color := clWhite;
        Pen.Color := $00E1D5CB;
      end;
      RoundRect(FRects[I].Left, FRects[I].Top, FRects[I].Right, FRects[I].Bottom, 28, 28);
      if Sel then
        BFStyleFont(Font, 8, True, clWhite)
      else
        BFStyleFont(Font, 8, True, BFClSlate600);
      BFDrawTextIn(Canvas, FCaptions[I], Rect(FRects[I].Left, FRects[I].Top + 6, FRects[I].Right,
        FRects[I].Bottom), taCenter, False);
    end;
  end;
end;

procedure TBFChipBar.MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  I: Integer;
begin
  inherited MouseUp(Button, Shift, X, Y);
  for I := 0 to High(FRects) do
    if (X >= FRects[I].Left) and (X < FRects[I].Right) and (Y >= FRects[I].Top) and
      (Y < FRects[I].Bottom) then
    begin
      FSelected := FKeys[I];
      Invalidate;
      if Assigned(FOnChange) then
        FOnChange(Self);
      Exit;
    end;
end;

{ ── TBFColumn ──────────────────────────────────────────────────────────── }

constructor TBFColumn.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FItems := TList.Create;
  FGap := BF_GAP;
  FBoxColor := clNone;
  FBorderColor := clNone;
  FAccentBorder := clNone;
  FBorderWidth := 1;
  FRadius := 12;
  Color := BFClSurface;
  Height := 10;
end;

destructor TBFColumn.Destroy;
begin
  FItems.Free;
  inherited Destroy;
end;

procedure TBFColumn.Box(ABox, ABorder: TColor; APadX, APadY, ARadius: Integer);
begin
  FBoxColor := ABox;
  FBorderColor := ABorder;
  FPadX := APadX;
  FPadY := APadY;
  FRadius := ARadius;
end;

function TBFColumn.Add(C: TControl): TControl;
begin
  C.Parent := Self;
  FItems.Add(C);
  Result := C;
end;

procedure TBFColumn.ClearItems;
var
  I: Integer;
begin
  for I := FItems.Count - 1 downto 0 do
    TControl(FItems[I]).Free;
  FItems.Clear;
end;

function TBFColumn.ItemCount: Integer;
begin
  Result := FItems.Count;
end;

function TBFColumn.ChildHeight(C: TControl; W: Integer): Integer;
begin
  if not C.Visible then
    Result := -1
  else
    Result := BFMeasure(C, W);
end;

function TBFColumn.MeasureHeight(AWidth: Integer): Integer;
var
  I, W, H, N: Integer;
begin
  W := AWidth - 2 * (FMarginX + FPadX);
  Result := 2 * (FMarginY + FPadY);
  N := 0;
  for I := 0 to FItems.Count - 1 do
  begin
    H := ChildHeight(TControl(FItems[I]), W);
    if H < 0 then
      Continue;
    if N > 0 then
      Inc(Result, FGap);
    Inc(Result, H);
    Inc(N);
  end;
end;

procedure TBFColumn.Relayout;
var
  I, W, H, Y, N: Integer;
  C: TControl;
begin
  W := Width - 2 * (FMarginX + FPadX);
  Y := FMarginY + FPadY;
  N := 0;
  for I := 0 to FItems.Count - 1 do
  begin
    C := TControl(FItems[I]);
    H := ChildHeight(C, W);
    if H < 0 then
      Continue;
    if N > 0 then
      Inc(Y, FGap);
    C.SetBounds(FMarginX + FPadX, Y, W, H);
    if C is TBFColumn then
      TBFColumn(C).Relayout
    else if C is TBFRow then
      TBFRow(C).Relayout;
    Inc(Y, H);
    Inc(N);
  end;
  Invalidate;
end;

procedure TBFColumn.Resize;
begin
  inherited Resize;
  Relayout;
end;

procedure TBFColumn.Paint;
begin
  with Canvas do
  begin
    if FBoxColor <> clNone then
      Brush.Color := ParentBg(Self)
    else
      Brush.Color := Color;
    FillRect(Rect(0, 0, Width, Height));
    if FBoxColor <> clNone then
    begin
      Brush.Color := FBoxColor;
      if FBorderColor <> clNone then Pen.Color := FBorderColor else Pen.Color := FBoxColor;
      Pen.Width := FBorderWidth;
      RoundRect(FMarginX, FMarginY, Width - FMarginX, Height - FMarginY, FRadius, FRadius);
      Pen.Width := 1;
    end;
  end;
end;

{ ── TBFRow ─────────────────────────────────────────────────────────────── }

constructor TBFRow.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FItems := TList.Create;
  FGap := BF_GAP;
  FRowHeight := 36;
  Height := FRowHeight;
  Color := BFClBg;
end;

destructor TBFRow.Destroy;
begin
  FItems.Free;
  inherited Destroy;
end;

function TBFRow.Add(C: TControl; AWidth: Integer): TControl;
begin
  C.Parent := Self;
  FItems.Add(C);
  SetLength(FWidths, FItems.Count);
  FWidths[FItems.Count - 1] := AWidth;
  Result := C;
end;

function TBFRow.MeasureHeight(AWidth: Integer): Integer;
begin
  Result := FRowHeight;
end;

procedure TBFRow.Relayout;
var
  I, Fixed, Flex, X, W, FlexW, N: Integer;
  C: TControl;
begin
  Fixed := 0;
  Flex := 0;
  N := 0;
  for I := 0 to FItems.Count - 1 do
  begin
    if not TControl(FItems[I]).Visible then
      Continue;
    Inc(N);
    W := FWidths[I];
    if W < 0 then Inc(Flex) else Inc(Fixed, W);
  end;
  if N = 0 then
    Exit;
  FlexW := Width - 2 * FMarginX - Fixed - FGap * (N - 1);
  if Flex > 0 then
    FlexW := FlexW div Flex;
  if FlexW < 0 then
    FlexW := 0;
  X := FMarginX;
  for I := 0 to FItems.Count - 1 do
  begin
    C := TControl(FItems[I]);
    if not C.Visible then
      Continue;
    W := FWidths[I];
    if W < 0 then
      W := FlexW;
    C.SetBounds(X, 0, W, FRowHeight);
    Inc(X, W + FGap);
  end;
end;

procedure TBFRow.Resize;
begin
  inherited Resize;
  Relayout;
end;

procedure TBFRow.Paint;
begin
  Canvas.Brush.Color := Color;
  Canvas.FillRect(Rect(0, 0, Width, Height));
end;

{ ── TBFStack ───────────────────────────────────────────────────────────── }

constructor TBFStack.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  BorderStyle := bsNone;
  HorzScrollBar.Visible := False;
  VertScrollBar.Tracking := True;
  Color := BFClSurface;
  FContent := TBFColumn.Create(Self);
  FContent.Parent := Self;
  FContent.Color := BFClSurface;
  FContent.Align := alTop;
end;

procedure TBFStack.Relayout;
begin
  FContent.Height := FContent.MeasureHeight(ClientWidth);
  FContent.Relayout;
end;

procedure TBFStack.Resize;
begin
  inherited Resize;
  Relayout;
end;

procedure TBFStack.Clear;
begin
  FContent.ClearItems;
end;

function TBFStack.Add(C: TControl): TControl;
begin
  Result := FContent.Add(C);
end;

procedure TBFStack.ScrollToBottom;
begin
  VertScrollBar.Position := VertScrollBar.Range;
end;

function TBFStack.NearBottom: Boolean;
begin
  Result := VertScrollBar.Range - VertScrollBar.Position - ClientHeight < 80;
end;

function TBFStack.ScrollPos: Integer;
begin
  Result := VertScrollBar.Position;
end;

function TBFStack.ScrollMax: Integer;
begin
  Result := VertScrollBar.Range;
end;

{ ── TBFHtmlBox ─────────────────────────────────────────────────────────── }

{$IFDEF BFOCUS_HTMLVIEWER}
function HtmlString(const Raw: TBFRaw): ThtString;
begin
  {$IFDEF BF_UNICODE}
  Result := UTF8ToString(Raw);
  {$ELSE}
  Result := UTF8Decode(Raw);
  {$ENDIF}
end;

function ColorHex(C: TColor): string;
var
  V: Longint;
begin
  V := ColorToRGB(C);
  Result := '#' + IntToHex(V and $FF, 2) + IntToHex((V shr 8) and $FF, 2) +
    IntToHex((V shr 16) and $FF, 2);
end;
{$ENDIF}

constructor TBFHtmlBox.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FTextColor := BFClText;
  FLinkColor := BFColor(BF_BRAND_FALLBACK, clNavy);
  FFontSize := 9;
  Color := clWhite;
  Height := 20;
{$IFDEF BFOCUS_HTMLVIEWER}
  FViewer := THtmlViewer.Create(Self);
  FViewer.Parent := Self;
  FViewer.Align := alClient;
  FViewer.BorderStyle := htNone;
  FViewer.ScrollBars := ssNone;
  FViewer.OnHotSpotClick := HotSpotClick;
{$ENDIF}
end;

{$IFDEF BFOCUS_HTMLVIEWER}
procedure TBFHtmlBox.HotSpotClick(Sender: TObject; const SRC: ThtString; var Handled: Boolean);
begin
  // Links do conteúdo nunca navegam dentro do widget: abrem fora.
  Handled := True;
  if Assigned(FOnLink) then
    FOnLink(Self, string(SRC))
  else
    BFOpenUrl(string(SRC));
end;
{$ENDIF}

procedure TBFHtmlBox.SetHtml(const Html: TBFRaw);
begin
  FHtml := Html;
  FText := BFHtmlToText(BFFromUtf8(Html));
{$IFDEF BFOCUS_HTMLVIEWER}
  FViewer.DefFontName := BFFontName;
  FViewer.DefFontSize := FFontSize;
  FViewer.DefFontColor := FTextColor;
  FViewer.DefHotSpotColor := FLinkColor;
  FViewer.DefBackground := Color;
  FViewer.LoadFromString(HtmlString('<body style="margin:0;padding:0;color:' +
    TBFRaw(ColorHex(FTextColor)) + '">' + Html + '</body>'));
{$ENDIF}
  Invalidate;
end;

function TBFHtmlBox.MeasureHeight(AWidth: Integer): Integer;
var
  F: TFont;
begin
{$IFDEF BFOCUS_HTMLVIEWER}
  Result := FViewer.FullDisplaySize(AWidth).cy + 2;
{$ELSE}
  F := TFont.Create;
  try
    BFStyleFont(F, FFontSize, False, FTextColor);
    Result := BFTextHeight(F, FText, AWidth);
  finally
    F.Free;
  end;
{$ENDIF}
end;

procedure TBFHtmlBox.Resize;
begin
  inherited Resize;
  Invalidate;
end;

procedure TBFHtmlBox.Paint;
begin
{$IFNDEF BFOCUS_HTMLVIEWER}
  with Canvas do
  begin
    Brush.Color := Color;
    FillRect(Rect(0, 0, Width, Height));
    BFStyleFont(Font, FFontSize, False, FTextColor);
    BFDrawTextIn(Canvas, FText, Rect(0, 0, Width, Height), taLeftJustify, True);
  end;
{$ENDIF}
end;

{ ── TBFEditor ──────────────────────────────────────────────────────────── }

type
  TBFToolKind = (tkBold, tkItalic, tkStrike, tkBullet, tkOrdered, tkQuote, tkCode, tkLink);

const
  TOOL_CAPTIONS: array[TBFToolKind] of string = ('B', 'I', 'S', '-', '1.', '"', '<>', '@');
  TOOL_HINTS: array[TBFToolKind] of string = ('editor_bold', 'editor_italic', 'editor_strike',
    'editor_bullet_list', 'editor_ordered_list', 'editor_quote', 'editor_code', 'editor_link');

constructor TBFEditor.CreateEditor(AOwner: TComponent; const Locale, Placeholder: string;
  AMinHeight: Integer);
var
  K: TBFToolKind;
  B: TBFButton;
begin
  inherited Create(AOwner);
  FMinHeight := AMinHeight;
  Color := BFClBg;
  FToolbar := TBFRow.Create(Self);
  FToolbar.Parent := Self;
  FToolbar.RowHeight := 26;
  FToolbar.Gap := 2;
  for K := Low(TBFToolKind) to High(TBFToolKind) do
  begin
    B := TBFButton.Create(Self);
    B.Kind := bkGhost;
    B.ButtonHeight := 26;
    B.FontSize := 8;
    B.Tag := Ord(K);
    B.Caption := TOOL_CAPTIONS[K];
    B.Hint := BFT(Locale, TOOL_HINTS[K]);
    B.ShowHint := True;
    B.TabStop := False;
    B.OnClick := ToolClick;
    FToolbar.Add(B, 30);
  end;
  FMemo := TMemo.Create(Self);
  FMemo.Parent := Self;
  FMemo.ScrollBars := ssVertical;
  FMemo.WordWrap := True;
  FMemo.OnChange := MemoChange;
  BFStyleFont(FMemo.Font, 10, False, BFClText);
  FHint := TBFText.Create(Self);
  FHint.Parent := Self;
  FHint.Style(9, False, BFClSubtle);
  FHint.Text := Placeholder;
  FLinkRow := TBFRow.Create(Self);
  FLinkRow.Parent := Self;
  FLinkRow.RowHeight := 28;
  FLinkRow.Visible := False;
  FLinkEdit := TEdit.Create(Self);
  FLinkEdit.OnKeyDown := LinkKeyDown;
{$IFDEF BF_FPC}
  FLinkEdit.TextHint := BFT(Locale, 'editor_link_placeholder');
{$ELSE}
  {$IFDEF BF_D2009}
  FLinkEdit.TextHint := BFT(Locale, 'editor_link_placeholder');
  {$ENDIF}
{$ENDIF}
  FLinkRow.Add(FLinkEdit, -1);
  FLinkApply := TBFButton.Create(Self);
  FLinkApply.Kind := bkPrimary;
  FLinkApply.ButtonHeight := 28;
  FLinkApply.Caption := BFT(Locale, 'editor_link_apply');
  FLinkApply.OnClick := LinkApplyClick;
  FLinkRow.Add(FLinkApply, FLinkApply.PreferredWidth);
  FLinkRemove := TBFButton.Create(Self);
  FLinkRemove.Kind := bkNeutral;
  FLinkRemove.ButtonHeight := 28;
  FLinkRemove.Caption := BFT(Locale, 'editor_link_remove');
  FLinkRemove.OnClick := LinkRemoveClick;
  FLinkRow.Add(FLinkRemove, FLinkRemove.PreferredWidth);
  Height := MeasureHeight(300);
end;

function TBFEditor.MeasureHeight(AWidth: Integer): Integer;
begin
  Result := 26 + 4 + FMinHeight;
  if FLinkRow.Visible then
    Inc(Result, 32);
end;

procedure TBFEditor.Resize;
var
  Y: Integer;
begin
  inherited Resize;
  FToolbar.SetBounds(0, 0, Width, 26);
  Y := 30;
  if FLinkRow.Visible then
  begin
    FLinkRow.SetBounds(0, Y, Width, 28);
    FLinkRow.Relayout;
    Inc(Y, 32);
  end;
  FMemo.SetBounds(0, Y, Width, Height - Y);
  FHint.SetBounds(6, Y + 4, Width - 12, 18);
  FHint.Visible := FMemo.Text = '';
end;

procedure TBFEditor.Paint;
begin
  Canvas.Brush.Color := Color;
  Canvas.FillRect(Rect(0, 0, Width, Height));
end;

procedure TBFEditor.MemoChange(Sender: TObject);
begin
  FHint.Visible := FMemo.Text = '';
  if Assigned(FOnChange) then
    FOnChange(Self);
end;

procedure TBFEditor.Wrap(const Marker: string);
var
  S, L: Integer;
  Sel: string;
begin
  S := FMemo.SelStart;
  L := FMemo.SelLength;
  Sel := FMemo.SelText;
  FMemo.SelText := Marker + Sel + Marker;
  if L = 0 then
    FMemo.SelStart := S + Length(Marker);
  FMemo.SetFocus;
end;

procedure TBFEditor.PrefixLines(const Prefix: string; Numbered: Boolean);
var
  Lines: TStringList;
  I, N: Integer;
  Sel: string;
begin
  Sel := FMemo.SelText;
  if Sel = '' then
  begin
    FMemo.SelText := Prefix;
    FMemo.SetFocus;
    Exit;
  end;
  Lines := TStringList.Create;
  try
    Lines.Text := Sel;
    N := 1;
    for I := 0 to Lines.Count - 1 do
      if Numbered then
      begin
        Lines[I] := IntToStr(N) + '. ' + Lines[I];
        Inc(N);
      end
      else
        Lines[I] := Prefix + Lines[I];
    FMemo.SelText := TrimRight(Lines.Text);
  finally
    Lines.Free;
  end;
  FMemo.SetFocus;
end;

procedure TBFEditor.ShowLinkRow(Show: Boolean);
begin
  if Show then
  begin
    // Guarda a seleção: o foco vai para o campo do link.
    FSelStart := FMemo.SelStart;
    FSelLength := FMemo.SelLength;
  end;
  FLinkRow.Visible := Show;
  Height := MeasureHeight(Width);
  Resize;
  if Parent is TBFColumn then
    TBFColumn(Parent).Relayout;
  if Show then
  begin
    FLinkEdit.Text := '';
    if FLinkEdit.CanFocus then
      FLinkEdit.SetFocus;
  end
  else if FMemo.CanFocus then
    FMemo.SetFocus;
end;

procedure TBFEditor.ApplyLink(const Url: string);
var
  Txt, U: string;
begin
  FMemo.SelStart := FSelStart;
  FMemo.SelLength := FSelLength;
  U := BFNormalizeLinkUrl(Url);
  Txt := FMemo.SelText;
  if U = '' then
  begin
    LinkRemoveClick(nil);
    Exit;
  end;
  if Txt = '' then
    Txt := U;
  FMemo.SelText := '[' + Txt + '](' + U + ')';
  ShowLinkRow(False);
end;

procedure TBFEditor.LinkApplyClick(Sender: TObject);
begin
  ApplyLink(FLinkEdit.Text);
end;

procedure TBFEditor.LinkRemoveClick(Sender: TObject);
var
  Sel: string;
  P, Q: Integer;
begin
  // Remove a marcação [texto](url) da seleção, deixando só o texto.
  FMemo.SelStart := FSelStart;
  FMemo.SelLength := FSelLength;
  Sel := FMemo.SelText;
  P := Pos('](', Sel);
  Q := Length(Sel);
  if (Sel <> '') and (Sel[1] = '[') and (P > 0) and (Sel[Q] = ')') then
    FMemo.SelText := Copy(Sel, 2, P - 2);
  ShowLinkRow(False);
end;

procedure TBFEditor.LinkKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  if Key = 13 then
  begin
    Key := 0;
    ApplyLink(FLinkEdit.Text);
  end
  else if Key = 27 then
  begin
    Key := 0;
    ShowLinkRow(False);
  end;
end;

procedure TBFEditor.ToolClick(Sender: TObject);
begin
  case TBFToolKind(TComponent(Sender).Tag) of
    tkBold: Wrap('**');
    tkItalic: Wrap('*');
    tkStrike: Wrap('~~');
    tkCode: Wrap('`');
    tkBullet: PrefixLines('- ', False);
    tkOrdered: PrefixLines('', True);
    tkQuote: PrefixLines('> ', False);
    tkLink: ShowLinkRow(not FLinkRow.Visible);
  end;
end;

function TBFEditor.Html: string;
begin
  Result := BFMarkupToHtml(FMemo.Text);
end;

function TBFEditor.IsEmpty: Boolean;
begin
  Result := Trim(FMemo.Text) = '';
end;

procedure TBFEditor.Clear;
begin
  FMemo.Clear;
  FHint.Visible := True;
end;

procedure TBFEditor.SetText(const S: string);
begin
  FMemo.Text := S;
  FHint.Visible := S = '';
end;

{ ── TBFAttachmentCard ──────────────────────────────────────────────────── }

constructor TBFAttachmentCard.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FPicture := TPicture.Create;
  FClickable := True;
  Cursor := crHandPoint;
  Height := 52;
end;

destructor TBFAttachmentCard.Destroy;
begin
  FPicture.Free;
  inherited Destroy;
end;

procedure TBFAttachmentCard.Setup(const AFileName, AMime: string; ASize: Int64; AAccent: TColor);
begin
  FFileName := AFileName;
  FMime := AMime;
  FSize := ASize;
  FAccent := AAccent;
  Invalidate;
end;

function TBFAttachmentCard.HasPicture: Boolean;
begin
  Result := (FPicture.Graphic <> nil) and (FPicture.Width > 0);
end;

function TBFAttachmentCard.MeasureHeight(AWidth: Integer): Integer;
var
  W, H: Integer;
begin
  if HasPicture then
  begin
    // Prévia até 240 x 200, mais a linha do nome.
    W := AWidth - 2 * FMarginX;
    if W > 240 then W := 240;
    H := Round(FPicture.Height * (W / FPicture.Width));
    if H > 200 then H := 200;
    Result := H + 26;
  end
  else
    Result := 52;
end;

procedure TBFAttachmentCard.Paint;
var
  X, W, H, ImgH: Integer;
  R: TRect;
  Meta, Icon: string;
begin
  W := Width - 2 * FMarginX;
  if W > 260 then W := 260;
  if FRightAlign then X := Width - FMarginX - W else X := FMarginX;
  with Canvas do
  begin
    Brush.Color := ParentBg(Self);
    FillRect(Rect(0, 0, Width, Height));
    Brush.Color := clWhite;
    Pen.Color := BFClBorder;
    RoundRect(X, 0, X + W, Height, 12, 12);
    if HasPicture then
    begin
      ImgH := Height - 26;
      StretchDraw(Rect(X + 1, 1, X + W - 1, ImgH), FPicture.Graphic);
      BFStyleFont(Font, 7, False, BFClSlate600);
      Meta := FFileName;
      if FSize > 0 then
        Meta := Meta + ' ' + BFFromUtf8(#$C2#$B7) + ' ' + BFPrettyBytes(FSize);
      BFDrawTextIn(Canvas, Meta, Rect(X + 10, ImgH + 6, X + W - 24, Height), taLeftJustify, False);
      if FClickable then
        TextOut(X + W - 18, ImgH + 5, BFFromUtf8(#$E2#$AC#$87));
      Exit;
    end;
    Brush.Color := BFMix(FAccent, clWhite, 0.10);
    Pen.Color := Brush.Color;
    RoundRect(X + 10, 8, X + 46, 44, 8, 8);
    Icon := BFAttachmentIcon(FMime);
    BFStyleFont(Font, 11, False, FAccent);
    BFDrawTextIn(Canvas, Icon, Rect(X + 10, 16, X + 46, 44), taCenter, False);
    BFStyleFont(Font, 9, False, BFClText);
    BFDrawTextIn(Canvas, FFileName, Rect(X + 56, 9, X + W - 28, 27), taLeftJustify, False);
    Meta := BFPrettyBytes(FSize);
    if (FSize > 0) and (FMime <> '') then
      Meta := Meta + ' ' + BFFromUtf8(#$C2#$B7) + ' ';
    Meta := Meta + FMime;
    if FSize <= 0 then
      Meta := FMime;
    BFStyleFont(Font, 7, False, BFClMuted);
    H := Height;
    R := Rect(X + 56, 28, X + W - 28, H - 4);
    BFDrawTextIn(Canvas, Meta, R, taLeftJustify, False);
    if FClickable then
    begin
      BFStyleFont(Font, 10, False, BFClMuted);
      TextOut(X + W - 22, 16, BFFromUtf8(#$E2#$AC#$87)); // ⬇
    end;
  end;
end;

procedure TBFAttachmentCard.MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  // Sem clique enquanto a mensagem ainda está em envio.
  if FClickable then
    inherited MouseUp(Button, Shift, X, Y);
end;

constructor TBFSpacer.CreateH(AOwner: TComponent; AHeight: Integer);
begin
  inherited Create(AOwner);
  Height := AHeight;
end;

initialization
  BFClText := BFColor(BFTokenColor('neutral', 'text'), clBlack);
  BFClMuted := BFColor(BFTokenColor('neutral', 'muted'), clGray);
  BFClSubtle := BFColor(BFTokenColor('neutral', 'subtle'), clGray);
  BFClBorder := BFColor(BFTokenColor('neutral', 'border'), clSilver);
  BFClSurface := BFColor(BFTokenColor('neutral', 'surface'), clWhite);
  BFClBg := BFColor(BFTokenColor('neutral', 'background'), clWhite);
  BFClSlate600 := BFColor('#475569', clGray);
  BFClChip := BFColor('#f1f5f9', clBtnFace);
  BFClDanger := BFColor('#ef4444', clRed);
  BFClAmberBg := BFColor('#fffbeb', clInfoBk);
  BFClAmberBorder := BFColor('#fde68a', clYellow);
  BFClAmberText := BFColor('#92400e', clMaroon);
{$IFDEF MSWINDOWS}
  BFFontName := 'Segoe UI';
{$ELSE}
  BFFontName := '';
{$ENDIF}

finalization
  FreeAndNil(GMeasure);

end.
