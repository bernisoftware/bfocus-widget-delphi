unit BFocusNativeWidget;

{ TBFocusNativeWidget — o widget com telas nativas (Fase 6): Delphi 7+ (VCL) e Lazarus
  (LCL). Mesma API do TBFocusWidget híbrido (BRIEF §3); o chat usa o modo poll. }

{$I BFocusDefines.inc}

interface

uses
  SysUtils, Classes, BFocusConfig, BFocusWidgetBase, BFocusNativeUI;

type
  TBFocusNativeWidget = class(TBFocusWidgetBase)
  private
    FUI: TBFocusNativeUI;
    FPanelWidth: Integer;
    FPanelHeight: Integer;
    function UI: TBFocusNativeUI;
  protected
    procedure DoShowWidget(View: TBFOpenView; const Id: string); override;
    procedure DoHideWidget; override;
    procedure DoOpenBanner(Ids: TStrings); override;
    procedure DoOpenHistory; override;
    procedure DoResetUI(ClearData: Boolean); override;
  public
    constructor Create(AOwner: TComponent); override;
  published
    property PanelWidth: Integer read FPanelWidth write FPanelWidth default 400;
    property PanelHeight: Integer read FPanelHeight write FPanelHeight default 620;
  end;

implementation

constructor TBFocusNativeWidget.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FPanelWidth := 400;
  FPanelHeight := 620;
end;

function TBFocusNativeWidget.UI: TBFocusNativeUI;
begin
  if FUI = nil then
  begin
    FUI := TBFocusNativeUI.CreateFor(Self, Self);
    FUI.PanelWidth := FPanelWidth;
    FUI.PanelHeight := FPanelHeight;
  end;
  Result := FUI;
end;

procedure TBFocusNativeWidget.DoShowWidget(View: TBFOpenView; const Id: string);
begin
  UI.ShowWidget(View, Id);
end;

procedure TBFocusNativeWidget.DoHideWidget;
begin
  if FUI <> nil then
    FUI.HideWidget
  else
    WidgetHidden;
end;

procedure TBFocusNativeWidget.DoOpenBanner(Ids: TStrings);
begin
  UI.OpenBanner(Ids);
end;

procedure TBFocusNativeWidget.DoOpenHistory;
begin
  UI.OpenHistory;
end;

procedure TBFocusNativeWidget.DoResetUI(ClearData: Boolean);
begin
  if FUI = nil then
    Exit;
  if ClearData then
    FreeAndNil(FUI) // logout: nada da sessão anterior sobrevive
  else
    FUI.ResetUI;
end;

end.
