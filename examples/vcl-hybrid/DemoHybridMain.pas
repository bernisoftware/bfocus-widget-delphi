unit DemoHybridMain;

{ Tela do exemplo, montada em código (sem .dfm). Troque a chave, o appId e a identidade
  pelos do seu tenant. O userHash vem do SEU servidor (SDK do bFocus: sign_widget_identity);
  nunca coloque o segredo bf_whs_ no app. }

interface

uses
  System.SysUtils, System.Classes, Vcl.Controls, Vcl.Forms, Vcl.StdCtrls, Vcl.ExtCtrls,
  BFocusConfig, BFocusWidgetBase, BFocusWidgetVcl, BFocusGraphics;

type
  TDemoForm = class(TForm)
  private
    FWidget: TBFocusWidget;
    FButton: TBFocusLauncherButton;
    FPill: TBFocusReleaseBadge;
    FLog: TMemo;
    procedure Log(const S: string);
    procedure BadgeChanged(Sender: TObject; const ALabel: string);
    procedure ReleaseNotesChanged(Sender: TObject; const ALabel: string; ADot: Boolean;
      BannerIds: TStrings);
    procedure WidgetError(Sender: TObject; const Code, Detail: string);
    procedure UserHashRequest(Sender: TObject; var UserHash: string);
    procedure NewTicketClick(Sender: TObject);
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
  inherited CreateNew(AOwner);
  Caption := 'bFocus Widget - exemplo (VCL 10.4+)';
  Width := 900;
  Height := 600;
  Position := poScreenCenter;

  FWidget := TBFocusWidget.Create(Self);
  FWidget.Config.PublishableKey := 'bf_pk_SUA_CHAVE';
  FWidget.Config.AppId := 'com.suaempresa.erp';
  FWidget.Config.User.ExternalId := 'USR-1';
  FWidget.Config.User.Name := 'Ana Souza';
  FWidget.Config.User.Email := 'ana@empresa.com.br';
  FWidget.Config.Customer.ExternalId := 'ACME-1';
  FWidget.Config.Customer.Name := 'ACME Ltda';
  FWidget.Config.Notifications := True;
  FWidget.OnBadgeChanged := BadgeChanged;
  FWidget.OnReleaseNotesChanged := ReleaseNotesChanged;
  FWidget.OnError := WidgetError;
  FWidget.OnUserHashRequest := UserHashRequest;

  FLog := TMemo.Create(Self);
  FLog.Parent := Self;
  FLog.SetBounds(12, 56, 500, 480);
  FLog.ReadOnly := True;

  AddButton(Self, 'Novo chamado', 12, NewTicketClick);
  AddButton(Self, 'Sair (logout)', 150, LogoutClick);

  FPill := TBFocusReleaseBadge.Create(Self);
  FPill.Parent := Self;
  FPill.SetBounds(300, 16, 90, 24);
  FPill.Widget := FWidget;

  FButton := TBFocusLauncherButton.Create(Self);
  FButton.Parent := Self;
  FButton.SetBounds(ClientWidth - 80, ClientHeight - 80, 56, 56);
  FButton.Anchors := [akRight, akBottom];
  FButton.Widget := FWidget;

  // userHash calculado no servidor do integrador (aqui, deixado em branco = sessão não verificada).
  FWidget.Config.UserHash := '';
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
  Log('release notes: ' + ALabel + ' dot=' + BoolToStr(ADot, True) + ' banner=' +
    IntToStr(BannerIds.Count));
end;

procedure TDemoForm.WidgetError(Sender: TObject; const Code, Detail: string);
begin
  Log('erro: ' + Code + ' ' + Detail);
end;

procedure TDemoForm.UserHashRequest(Sender: TObject; var UserHash: string);
begin
  // Chame o SEU backend aqui e devolva o hash novo (HMAC v1 calculado lá).
  Log('pedindo userHash novo ao servidor do integrador');
end;

procedure TDemoForm.NewTicketClick(Sender: TObject);
begin
  FWidget.OpenNewTicket;
end;

procedure TDemoForm.LogoutClick(Sender: TObject);
begin
  FWidget.Logout;
  Log('logout');
end;

end.
