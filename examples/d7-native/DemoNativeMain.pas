unit DemoNativeMain;

{ Tela do exemplo nativo, montada em código (sem .dfm): mesmas units no Delphi 7 e no
  Lazarus. Troque chave, appId e identidade pelos do seu tenant; o userHash vem do SEU
  servidor (SDK do bFocus: sign_widget_identity). }

{$IFDEF FPC}
  {$MODE DELPHI}{$H+}
{$ENDIF}

interface

uses
  SysUtils, Classes, Controls, Forms, StdCtrls, ExtCtrls,
  BFocusConfig, BFocusWidgetBase, BFocusNativeWidget, BFocusGraphics;

type
  TDemoForm = class(TForm)
  private
    FWidget: TBFocusNativeWidget;
    FButton: TBFocusLauncherButton;
    FPill: TBFocusReleaseBadge;
    FLog: TMemo;
    procedure Log(const S: string);
    procedure BadgeChanged(Sender: TObject; const ALabel: string);
    procedure ReleaseNotesChanged(Sender: TObject; const ALabel: string; ADot: Boolean;
      BannerIds: TStrings);
    procedure WidgetError(Sender: TObject; const Code, Detail: string);
    procedure NewTicketClick(Sender: TObject);
    procedure ChatClick(Sender: TObject);
    procedure LogoutClick(Sender: TObject);
  public
    constructor Create(AOwner: TComponent); override;
  end;

var
  DemoForm: TDemoForm;

implementation

function AddButton(AOwner: TForm; const Caption: string; X: Integer; OnClick: TNotifyEvent): TButton;
begin
  Result := TButton.Create(AOwner);
  Result.Parent := AOwner;
  Result.SetBounds(X, 12, 130, 30);
  Result.Caption := Caption;
  Result.OnClick := OnClick;
end;

constructor TDemoForm.Create(AOwner: TComponent);
begin
  // CreateNew: tela sem .dfm/.lfm.
  inherited CreateNew(AOwner, 0);
  Caption := 'bFocus Widget - exemplo (UI nativa)';
  Width := 900;
  Height := 600;
  Position := poScreenCenter;

  FWidget := TBFocusNativeWidget.Create(Self);
  FWidget.Config.PublishableKey := 'bf_pk_SUA_CHAVE';
  FWidget.Config.AppId := 'com.suaempresa.erp';
  FWidget.Config.User.ExternalId := 'USR-1';
  FWidget.Config.User.Name := 'Ana Souza';
  FWidget.Config.Customer.ExternalId := 'ACME-1';
  FWidget.Config.Customer.Name := 'ACME Ltda';
  FWidget.Config.Notifications := True;
  FWidget.OnBadgeChanged := BadgeChanged;
  FWidget.OnReleaseNotesChanged := ReleaseNotesChanged;
  FWidget.OnError := WidgetError;

  FLog := TMemo.Create(Self);
  FLog.Parent := Self;
  FLog.SetBounds(12, 56, 500, 480);
  FLog.ReadOnly := True;

  AddButton(Self, 'Novo chamado', 12, NewTicketClick);
  AddButton(Self, 'Chat', 150, ChatClick);
  AddButton(Self, 'Sair (logout)', 288, LogoutClick);

  FPill := TBFocusReleaseBadge.Create(Self);
  FPill.Parent := Self;
  FPill.SetBounds(430, 16, 90, 24);
  FPill.Widget := FWidget;

  FButton := TBFocusLauncherButton.Create(Self);
  FButton.Parent := Self;
  FButton.SetBounds(ClientWidth - 80, ClientHeight - 80, 56, 56);
  FButton.Anchors := [akRight, akBottom];
  FButton.Widget := FWidget;

  FWidget.Init;
end;

procedure TDemoForm.Log(const S: string);
begin
  FLog.Lines.Add(FormatDateTime('hh:nn:ss', Now) + '  ' + S);
end;

procedure TDemoForm.BadgeChanged(Sender: TObject; const ALabel: string);
begin
  Log('badge: "' + ALabel + '"');
end;

procedure TDemoForm.ReleaseNotesChanged(Sender: TObject; const ALabel: string; ADot: Boolean;
  BannerIds: TStrings);
begin
  Log('release notes: ' + ALabel + ' dot=' + BoolToStr(ADot, True));
end;

procedure TDemoForm.WidgetError(Sender: TObject; const Code, Detail: string);
begin
  Log('erro: ' + Code + ' ' + Detail);
end;

procedure TDemoForm.NewTicketClick(Sender: TObject);
begin
  FWidget.OpenNewTicket;
end;

procedure TDemoForm.ChatClick(Sender: TObject);
begin
  FWidget.OpenChat;
end;

procedure TDemoForm.LogoutClick(Sender: TObject);
begin
  FWidget.Logout;
  Log('logout');
end;

end.
