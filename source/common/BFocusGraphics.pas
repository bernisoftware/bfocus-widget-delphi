unit BFocusGraphics;

{ Ajudantes de desenho comuns à VCL (Delphi 7+) e ao LCL: cor '#rrggbb' → TColor,
  mistura de cores (substitui o color-mix/alpha do CSS) e o botão flutuante e a pílula
  de versão (BRIEF §3, componentes opcionais). }

{$I BFocusDefines.inc}

interface

uses
  SysUtils, Classes, Controls, Graphics, BFocusWidgetBase;

type
  { Botão redondo de 56 px na primary_color, com o balão e o badge (''/•/N/99+). }
  TBFocusLauncherButton = class(TCustomControl, IBFocusWidgetListener)
  private
    FWidget: TBFocusWidgetBase;
    FBadgeColor: TColor;
    procedure SetWidget(Value: TBFocusWidgetBase);
  protected
    procedure Paint; override;
    procedure Click; override;
    procedure Notification(AComponent: TComponent; Operation: TOperation); override;
    procedure BFocusStateChanged(Sender: TObject);
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
  published
    property Widget: TBFocusWidgetBase read FWidget write SetWidget;
    property BadgeColor: TColor read FBadgeColor write FBadgeColor default $004444EF;
    property Align;
    property Anchors;
    property Visible;
    property Hint;
    property ShowHint;
    property TabStop default True;
  end;

  { Pílula "v4.2.0"/"—" com ponto de novidade. Clicar abre o histórico. }
  TBFocusReleaseBadge = class(TCustomControl, IBFocusWidgetListener)
  private
    FWidget: TBFocusWidgetBase;
    procedure SetWidget(Value: TBFocusWidgetBase);
  protected
    procedure Paint; override;
    procedure Click; override;
    procedure Notification(AComponent: TComponent; Operation: TOperation); override;
    procedure BFocusStateChanged(Sender: TObject);
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
  published
    property Widget: TBFocusWidgetBase read FWidget write SetWidget;
    property Align;
    property Anchors;
    property Visible;
    property Font;
    property ParentFont;
  end;

{ '#rrggbb' → TColor (padrão se inválida). }
function BFColor(const Hex: string; Default: TColor): TColor;
{ Mistura A com B: Amount = fração de A (0..1). Ex.: fundo translúcido da marca. }
function BFMix(A, B: TColor; Amount: Double): TColor;
function BFDarken(C: TColor; Amount: Double): TColor;

implementation

uses
  BFocusText;

function BFColor(const Hex: string; Default: TColor): TColor;
var
  R, G, B: Byte;
begin
  if BFParseHexColor(Hex, R, G, B) then
    Result := TColor(R or (G shl 8) or (B shl 16))
  else
    Result := Default;
end;

function BFMix(A, B: TColor; Amount: Double): TColor;
var
  CA, CB: Longint;
  R, G, Bl: Integer;
begin
  CA := ColorToRGB(A);
  CB := ColorToRGB(B);
  R := Round((CA and $FF) * Amount + (CB and $FF) * (1 - Amount));
  G := Round(((CA shr 8) and $FF) * Amount + ((CB shr 8) and $FF) * (1 - Amount));
  Bl := Round(((CA shr 16) and $FF) * Amount + ((CB shr 16) and $FF) * (1 - Amount));
  Result := TColor(R or (G shl 8) or (Bl shl 16));
end;

function BFDarken(C: TColor; Amount: Double): TColor;
begin
  Result := BFMix(clBlack, C, Amount);
end;

{ ── botão ──────────────────────────────────────────────────────────────── }

constructor TBFocusLauncherButton.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  Width := 56;
  Height := 56;
  TabStop := True;
  Cursor := crHandPoint;
  FBadgeColor := $004444EF; // #EF4444
  ControlStyle := ControlStyle + [csOpaque] - [csSetCaption];
end;

destructor TBFocusLauncherButton.Destroy;
begin
  if FWidget <> nil then
    FWidget.RemoveListener(Self);
  inherited Destroy;
end;

procedure TBFocusLauncherButton.SetWidget(Value: TBFocusWidgetBase);
begin
  if FWidget = Value then
    Exit;
  if FWidget <> nil then
    FWidget.RemoveListener(Self);
  FWidget := Value;
  if FWidget <> nil then
  begin
    FWidget.FreeNotification(Self);
    FWidget.AddListener(Self);
  end;
  Invalidate;
end;

procedure TBFocusLauncherButton.Notification(AComponent: TComponent; Operation: TOperation);
begin
  inherited Notification(AComponent, Operation);
  if (Operation = opRemove) and (AComponent = FWidget) then
    FWidget := nil;
end;

procedure TBFocusLauncherButton.BFocusStateChanged(Sender: TObject);
begin
  Invalidate;
end;

procedure TBFocusLauncherButton.Click;
begin
  inherited Click;
  if (FWidget <> nil) and FWidget.Initialized then
    FWidget.Toggle;
end;

procedure TBFocusLauncherButton.Paint;
var
  Primary: TColor;
  S, Cx, Cy, R, W: Integer;
  Badge: string;
begin
  S := Width;
  if Height < S then
    S := Height;
  if FWidget <> nil then
    Primary := BFColor(FWidget.PrimaryColor, BFColor('#6366F1', clNavy))
  else
    Primary := BFColor('#6366F1', clNavy);
  with Canvas do
  begin
    Brush.Color := Color;
    if Parent <> nil then
      Brush.Color := TWinControl(Parent).Brush.Color;
    FillRect(Rect(0, 0, Width, Height));
    Brush.Color := Primary;
    Pen.Color := Primary;
    Ellipse(0, 0, S, S);
    Cx := S div 2;
    Cy := S div 2;
    Pen.Color := clWhite;
    Pen.Width := 2;
    Brush.Style := bsClear;
    if (FWidget <> nil) and FWidget.IsOpen then
    begin
      // Aberto: vira um "X", como o launcher web.
      MoveTo(Cx - 7, Cy - 7); LineTo(Cx + 7, Cy + 7);
      MoveTo(Cx - 7, Cy + 7); LineTo(Cx + 7, Cy - 7);
    end
    else
    begin
      // Balão de conversa com três pontos.
      RoundRect(Cx - 12, Cy - 10, Cx + 12, Cy + 8, 14, 14);
      Brush.Style := bsSolid;
      Brush.Color := clWhite;
      Polygon([Point(Cx - 8, Cy + 6), Point(Cx - 11, Cy + 13), Point(Cx - 2, Cy + 7)]);
      Ellipse(Cx - 6, Cy - 2, Cx - 3, Cy + 1);
      Ellipse(Cx - 1, Cy - 2, Cx + 2, Cy + 1);
      Ellipse(Cx + 4, Cy - 2, Cx + 7, Cy + 1);
    end;
    Pen.Width := 1;
    Brush.Style := bsSolid;
    if FWidget <> nil then
      Badge := FWidget.BadgeText
    else
      Badge := '';
    if Badge <> '' then
    begin
      Font.Color := clWhite;
      Font.Style := [fsBold];
      Font.Size := 8;
      W := TextWidth(Badge) + 8;
      if W < 18 then
        W := 18;
      R := S - W;
      Brush.Color := FBadgeColor;
      Pen.Color := clWhite;
      RoundRect(R, 0, S, 18, 18, 18);
      Brush.Style := bsClear;
      TextOut(R + (W - TextWidth(Badge)) div 2, (18 - TextHeight(Badge)) div 2, Badge);
      Brush.Style := bsSolid;
    end;
  end;
end;

{ ── pílula ─────────────────────────────────────────────────────────────── }

constructor TBFocusReleaseBadge.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  Width := 84;
  Height := 24;
  Cursor := crHandPoint;
  ControlStyle := ControlStyle - [csSetCaption];
end;

destructor TBFocusReleaseBadge.Destroy;
begin
  if FWidget <> nil then
    FWidget.RemoveListener(Self);
  inherited Destroy;
end;

procedure TBFocusReleaseBadge.SetWidget(Value: TBFocusWidgetBase);
begin
  if FWidget = Value then
    Exit;
  if FWidget <> nil then
    FWidget.RemoveListener(Self);
  FWidget := Value;
  if FWidget <> nil then
  begin
    FWidget.FreeNotification(Self);
    FWidget.AddListener(Self);
  end;
  Invalidate;
end;

procedure TBFocusReleaseBadge.Notification(AComponent: TComponent; Operation: TOperation);
begin
  inherited Notification(AComponent, Operation);
  if (Operation = opRemove) and (AComponent = FWidget) then
    FWidget := nil;
end;

procedure TBFocusReleaseBadge.BFocusStateChanged(Sender: TObject);
begin
  Invalidate;
end;

procedure TBFocusReleaseBadge.Click;
begin
  inherited Click;
  if (FWidget <> nil) and FWidget.Initialized then
    FWidget.OpenReleaseNotesHistory;
end;

procedure TBFocusReleaseBadge.Paint;
var
  Primary: TColor;
  Txt: string;
  X, Y: Integer;
begin
  if FWidget <> nil then
  begin
    Primary := BFColor(FWidget.PrimaryColor, clNavy);
    Txt := FWidget.PillText;
  end
  else
  begin
    Primary := BFColor('#6366F1', clNavy);
    Txt := '...';
  end;
  with Canvas do
  begin
    Brush.Color := Color;
    if Parent <> nil then
      Brush.Color := TWinControl(Parent).Brush.Color;
    FillRect(Rect(0, 0, Width, Height));
    Brush.Color := BFMix(Primary, clWhite, 0.12);
    Pen.Color := BFMix(Primary, clWhite, 0.35);
    RoundRect(0, 0, Width, Height, Height, Height);
    // Estrela simplificada.
    Brush.Color := Primary;
    Pen.Color := Primary;
    Y := Height div 2;
    Polygon([Point(10, Y - 6), Point(12, Y - 2), Point(16, Y - 1), Point(13, Y + 2),
      Point(14, Y + 6), Point(10, Y + 4), Point(6, Y + 6), Point(7, Y + 2), Point(4, Y - 1),
      Point(8, Y - 2)]);
    Font.Assign(Self.Font);
    Font.Color := Primary;
    Font.Style := [fsBold];
    Brush.Style := bsClear;
    X := 22;
    TextOut(X, (Height - TextHeight(Txt)) div 2, Txt);
    Brush.Style := bsSolid;
    if (FWidget <> nil) and FWidget.PillDot then
    begin
      Brush.Color := $004444EF;
      Pen.Color := clWhite;
      Ellipse(Width - 12, 3, Width - 4, 11);
    end;
  end;
end;

end.
