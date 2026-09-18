unit BFocusVMReleaseNotes;

{ Release notes sem UI (behavior spec §4 e §6): splash dentro dos chamados, banner com
  trava de rolagem e ciência, e histórico. As filas já vêm prontas do servidor
  (launcher-state.banner_ids no banner, GET /widget/release-notes no splash); aqui só se
  respeita a ordem e se trava a confirmação. }

{$I BFocusDefines.inc}

interface

uses
  SysUtils, Classes, BFocusText, BFocusJson, BFocusI18n, BFocusFormat;

const
  BF_BANNER_BOTTOM_SLACK = 8;   // libera ao chegar a 8 px do fim
  BF_BANNER_NO_SCROLL = 4;      // conteúdo que não rola (diferença ≤ 4 px) libera na hora
  BF_SPLASH_REFRESH_MS = 60000; // reconsulta do splash (e quando a janela volta ao foco)

type
  { Splash de novidades dentro dos chamados, POR USUÁRIO. A fila do servidor traz as que
    exigem ciência (mais antigas primeiro) + a mais recente que não exige.
    - Exige ciência: mesmo comportamento da ciência interna do bFocus (ReleaseNoteAckGate):
      cobre a lista, uma por vez ("1 / n"), sem fechar nem pular, botão só a 8 px do fim.
    - Não exige: cartões dispensáveis ("marcar como lida" = /seen, ou "Pular por agora"). }
  TBFSplashVM = class
  private
    FNotes: TBFJson;
    FAck: TList;          // nós de FNotes que exigem ciência, na ordem do servidor
    FOthers: TList;       // os demais (cartões)
    FAckId: string;       // release na trava agora; trocou = trava de novo
    FAtBottom: Boolean;
    FAckFailed: Boolean;
    procedure SyncGate;
  public
    Dismissed: Boolean;    // "Pular por agora": some com os cartões até o widget ser reaberto
    ExpandedId: string;
    Marking: Boolean;
    Submitting: Boolean;   // /acknowledge em andamento
    constructor Create;
    destructor Destroy; override;
    procedure ApplyList(Data: TBFJson);
    function Visible(ShowReleaseNotes: Boolean): Boolean;
    { Alguma release exige ciência: trava a lista, sem pular (um "Pular" anterior não vale). }
    function Locked: Boolean;
    { Cartões (as que não exigem ciência). }
    function Count: Integer;
    function Note(I: Integer): TBFJson;
    function NoteColor(I: Integer; const Primary: string): string;
    function CountText(const Locale: string): string;
    { "Pular por agora": esconde só os cartões. }
    procedure Dismiss;
    { Widget reaberto: o splash volta a aparecer. }
    procedure WidgetReopened;
    procedure ToggleExpanded(const Id: string);
    { ── trava de ciência ── }
    function AckCount: Integer;
    { A release na trava: a mais antiga que exige ciência (nil = nenhuma). }
    function AckNote: TBFJson;
    function AckColor(const Primary: string): string;
    function AckCounterText: string;
    { Reinicia a trava ao montar a release: conteúdo que não rola libera na hora. }
    procedure ResetGate(ScrollHeight, ClientHeight: Integer);
    procedure UpdateScroll(ScrollTop, ClientHeight, ScrollHeight: Integer);
    function AtBottom: Boolean;
    function AckEnabled: Boolean;
    function ShowScrollHint: Boolean;
    { ackButton, ou ackSubmitting enquanto registra. }
    function AckButtonText(const Locale: string): string;
    { O último /acknowledge falhou: ackError visível e a release fica. }
    function AckFailed: Boolean;
    { Clique no botão: False se travado ou já registrando. Limpa o erro anterior. }
    function BeginAck: Boolean;
    procedure AckError;
    { /acknowledge ok: sai da fila local (a reconsulta confirma). }
    procedure AckDone(const Id: string);
  end;

  TBFBannerVM = class
  private
    FIds: TStringList;
    FPending: TBFJson;
    FQueue: TList;          // referências para nós de FPending, na ordem dos ids
    FIndex: Integer;
    FAtBottom: Boolean;
    FLoaded: Boolean;
  public
    Submitting: Boolean;
    Failed: Boolean;        // o último registro falhou: ackError, a release fica na tela
    constructor Create;
    destructor Destroy; override;
    procedure SetIds(Ids: TStrings);
    { /release-notes/pending. Ids que não estão mais pendentes são ignorados. }
    procedure ApplyPending(Data: TBFJson);
    function Loaded: Boolean;
    { Carregou e não sobrou nada: fechar (bfocus:rn:done). }
    function IsDone: Boolean;
    function Count: Integer;
    function Index: Integer;
    function Current: TBFJson;
    function RequireAck: Boolean;
    { Reinicia a trava ao trocar de release: conteúdo que não rola libera na hora. }
    procedure ResetGate(ScrollHeight, ClientHeight: Integer);
    procedure UpdateScroll(ScrollTop, ClientHeight, ScrollHeight: Integer);
    function AtBottom: Boolean;
    function ConfirmEnabled: Boolean;
    function ShowScrollHint: Boolean;
    { Clique no botão: False se travado ou já registrando. Limpa o erro anterior. }
    function BeginConfirm: Boolean;
    { Falha de rede no /acknowledge ou /seen: a release fica e aparece ackError. }
    procedure ConfirmFailed;
    { Depois do /acknowledge ou /seen: True = acabou a fila. }
    function Advance: Boolean;
    function CounterText: string;
    function EyebrowText(const Locale: string): string;
    function ButtonText(const Locale: string): string;
    function Color(const Primary: string): string;
  end;

  TBFHistoryVM = class
  private
    FData: TBFJson;
  public
    Loading: Boolean;
    ExpandedId: string;
    constructor Create;
    destructor Destroy; override;
    procedure ApplyChangelog(Data: TBFJson);
    function Count: Integer;
    function Note(I: Integer): TBFJson;
    function IsEmpty: Boolean;
    function CurrentVersion: string;
    function DateText(I: Integer; const Locale: string): string;
    function NoteColor(I: Integer; const Primary: string): string;
    procedure ToggleExpanded(const Id: string);
  end;

implementation

{ Cor do produto da release; sem cor (null ou ''), a primária do tenant. }
function ProductColor(N: TBFJson; const Primary: string): string;
var
  P: TBFJson;
begin
  Result := '';
  if N <> nil then
  begin
    P := N.ObjOf('product');
    if P <> nil then
      Result := P.StrOf('color');
  end;
  if Result = '' then
    Result := Primary;
end;

{ ── splash ─────────────────────────────────────────────────────────────── }

constructor TBFSplashVM.Create;
begin
  inherited Create;
  FAck := TList.Create;
  FOthers := TList.Create;
end;

destructor TBFSplashVM.Destroy;
begin
  FOthers.Free;
  FAck.Free;
  FNotes.Free;
  inherited Destroy;
end;

procedure TBFSplashVM.ApplyList(Data: TBFJson);
var
  I: Integer;
begin
  FAck.Clear;
  FOthers.Clear;
  FNotes.Free;
  if (Data <> nil) and Data.IsArray then
    FNotes := Data
  else
  begin
    Data.Free;
    FNotes := TBFJson.NewArray;
  end;
  // A ordem do servidor já é a da fila (published_at crescente): não reordena.
  for I := 0 to FNotes.Count - 1 do
    if FNotes.Item(I).BoolOf('require_acknowledgement') then
      FAck.Add(FNotes.Item(I))
    else
      FOthers.Add(FNotes.Item(I));
  Marking := False;
  SyncGate;
end;

procedure TBFSplashVM.SyncGate;
var
  Id: string;
begin
  if AckNote <> nil then
    Id := AckNote.StrOf('id')
  else
    Id := '';
  // Mesma release (reconsulta de 60 s): mantém a rolagem já feita e o aviso de erro.
  if Id = FAckId then
    Exit;
  FAckId := Id;
  FAtBottom := False;
  FAckFailed := False;
end;

function TBFSplashVM.Visible(ShowReleaseNotes: Boolean): Boolean;
begin
  Result := ShowReleaseNotes and (Locked or (not Dismissed and (Count > 0)));
end;

function TBFSplashVM.Locked: Boolean;
begin
  Result := FAck.Count > 0;
end;

function TBFSplashVM.Count: Integer;
begin
  Result := FOthers.Count;
end;

function TBFSplashVM.Note(I: Integer): TBFJson;
begin
  Result := TBFJson(FOthers[I]);
end;

function TBFSplashVM.NoteColor(I: Integer; const Primary: string): string;
begin
  Result := ProductColor(Note(I), Primary);
end;

function TBFSplashVM.CountText(const Locale: string): string;
begin
  if Count = 1 then
    Result := BFT(Locale, 'splash_count_one')
  else
    Result := BFFill(BFT(Locale, 'splash_count_many'), 'n', IntToStr(Count));
end;

procedure TBFSplashVM.Dismiss;
begin
  Dismissed := True;
end;

procedure TBFSplashVM.WidgetReopened;
begin
  Dismissed := False;
end;

procedure TBFSplashVM.ToggleExpanded(const Id: string);
begin
  if ExpandedId = Id then ExpandedId := '' else ExpandedId := Id;
end;

function TBFSplashVM.AckCount: Integer;
begin
  Result := FAck.Count;
end;

function TBFSplashVM.AckNote: TBFJson;
begin
  if FAck.Count > 0 then
    Result := TBFJson(FAck[0])
  else
    Result := nil;
end;

function TBFSplashVM.AckColor(const Primary: string): string;
begin
  Result := ProductColor(AckNote, Primary);
end;

function TBFSplashVM.AckCounterText: string;
begin
  // Sempre a primeira da fila: some da fila ao confirmar.
  if FAck.Count > 1 then
    Result := '1 / ' + IntToStr(FAck.Count)
  else
    Result := '';
end;

procedure TBFSplashVM.ResetGate(ScrollHeight, ClientHeight: Integer);
begin
  FAtBottom := ScrollHeight - ClientHeight <= BF_BANNER_NO_SCROLL;
end;

procedure TBFSplashVM.UpdateScroll(ScrollTop, ClientHeight, ScrollHeight: Integer);
begin
  if ScrollTop + ClientHeight >= ScrollHeight - BF_BANNER_BOTTOM_SLACK then
    FAtBottom := True;
end;

function TBFSplashVM.AtBottom: Boolean;
begin
  Result := FAtBottom;
end;

function TBFSplashVM.AckEnabled: Boolean;
begin
  Result := (AckNote <> nil) and not Submitting and FAtBottom;
end;

function TBFSplashVM.ShowScrollHint: Boolean;
begin
  Result := (AckNote <> nil) and not FAtBottom;
end;

function TBFSplashVM.AckButtonText(const Locale: string): string;
begin
  if Submitting then
    Result := BFRN(Locale, 'ackSubmitting')
  else
    Result := BFRN(Locale, 'ackButton');
end;

function TBFSplashVM.AckFailed: Boolean;
begin
  Result := FAckFailed;
end;

function TBFSplashVM.BeginAck: Boolean;
begin
  Result := AckEnabled;
  if Result then
  begin
    Submitting := True;
    FAckFailed := False;
  end;
end;

procedure TBFSplashVM.AckError;
begin
  Submitting := False;
  FAckFailed := True;
end;

procedure TBFSplashVM.AckDone(const Id: string);
var
  I: Integer;
begin
  Submitting := False;
  for I := FAck.Count - 1 downto 0 do
    if TBFJson(FAck[I]).StrOf('id') = Id then
      FAck.Delete(I);
  SyncGate;
end;

{ ── banner ─────────────────────────────────────────────────────────────── }

constructor TBFBannerVM.Create;
begin
  inherited Create;
  FIds := TStringList.Create;
  FQueue := TList.Create;
end;

destructor TBFBannerVM.Destroy;
begin
  FQueue.Free;
  FPending.Free;
  FIds.Free;
  inherited Destroy;
end;

procedure TBFBannerVM.SetIds(Ids: TStrings);
begin
  FIds.Assign(Ids);
end;

procedure TBFBannerVM.ApplyPending(Data: TBFJson);
var
  I, J: Integer;
begin
  FPending.Free;
  if (Data <> nil) and Data.IsArray then
    FPending := Data
  else
  begin
    Data.Free;
    FPending := TBFJson.NewArray;
  end;
  FQueue.Clear;
  if FIds.Count > 0 then
  begin
    // Ordem da fila do launcher; ignora ids que não estão mais pendentes.
    for I := 0 to FIds.Count - 1 do
      for J := 0 to FPending.Count - 1 do
        if FPending.Item(J).StrOf('id') = FIds[I] then
        begin
          FQueue.Add(FPending.Item(J));
          Break;
        end;
  end
  else
    for J := 0 to FPending.Count - 1 do
      FQueue.Add(FPending.Item(J));
  FIndex := 0;
  FAtBottom := False;
  FLoaded := True;
end;

function TBFBannerVM.Loaded: Boolean;
begin
  Result := FLoaded;
end;

function TBFBannerVM.IsDone: Boolean;
begin
  Result := FLoaded and (FIndex >= FQueue.Count);
end;

function TBFBannerVM.Count: Integer;
begin
  Result := FQueue.Count;
end;

function TBFBannerVM.Index: Integer;
begin
  Result := FIndex;
end;

function TBFBannerVM.Current: TBFJson;
begin
  if (FIndex >= 0) and (FIndex < FQueue.Count) then
    Result := TBFJson(FQueue[FIndex])
  else
    Result := nil;
end;

function TBFBannerVM.RequireAck: Boolean;
begin
  Result := (Current <> nil) and Current.BoolOf('require_acknowledgement');
end;

procedure TBFBannerVM.ResetGate(ScrollHeight, ClientHeight: Integer);
begin
  FAtBottom := ScrollHeight - ClientHeight <= BF_BANNER_NO_SCROLL;
end;

procedure TBFBannerVM.UpdateScroll(ScrollTop, ClientHeight, ScrollHeight: Integer);
begin
  if ScrollTop + ClientHeight >= ScrollHeight - BF_BANNER_BOTTOM_SLACK then
    FAtBottom := True;
end;

function TBFBannerVM.AtBottom: Boolean;
begin
  Result := FAtBottom;
end;

function TBFBannerVM.ConfirmEnabled: Boolean;
begin
  Result := (Current <> nil) and not Submitting and (not RequireAck or FAtBottom);
end;

function TBFBannerVM.ShowScrollHint: Boolean;
begin
  Result := RequireAck and not FAtBottom;
end;

function TBFBannerVM.BeginConfirm: Boolean;
begin
  Result := ConfirmEnabled;
  if Result then
  begin
    Submitting := True;
    Failed := False;
  end;
end;

procedure TBFBannerVM.ConfirmFailed;
begin
  Submitting := False;
  Failed := True;
end;

function TBFBannerVM.Advance: Boolean;
begin
  Submitting := False;
  Failed := False;
  Inc(FIndex);
  FAtBottom := False;
  Result := FIndex >= FQueue.Count;
end;

function TBFBannerVM.CounterText: string;
begin
  if FQueue.Count > 1 then
    Result := IntToStr(FIndex + 1) + ' / ' + IntToStr(FQueue.Count)
  else
    Result := '';
end;

function TBFBannerVM.EyebrowText(const Locale: string): string;
begin
  if RequireAck then
    Result := BFRN(Locale, 'ackEyebrow')
  else
    Result := BFRN(Locale, 'eyebrow');
end;

function TBFBannerVM.ButtonText(const Locale: string): string;
begin
  if Submitting then
    Result := BFRN(Locale, 'ackSubmitting')
  else if RequireAck then
    Result := BFRN(Locale, 'ackButton')
  else
    Result := BFRN(Locale, 'dismissButton');
end;

function TBFBannerVM.Color(const Primary: string): string;
var
  P: TBFJson;
begin
  Result := '';
  if Current <> nil then
  begin
    P := Current.ObjOf('product');
    if P <> nil then
      Result := P.StrOf('color');
  end;
  if Result = '' then
    Result := Primary;
end;

{ ── histórico ──────────────────────────────────────────────────────────── }

constructor TBFHistoryVM.Create;
begin
  inherited Create;
  Loading := True;
end;

destructor TBFHistoryVM.Destroy;
begin
  FData.Free;
  inherited Destroy;
end;

procedure TBFHistoryVM.ApplyChangelog(Data: TBFJson);
begin
  FData.Free;
  FData := Data;
  Loading := False;
end;

function TBFHistoryVM.Count: Integer;
var
  N: TBFJson;
begin
  Result := 0;
  if FData <> nil then
  begin
    N := FData.ArrOf('notes');
    if N <> nil then
      Result := N.Count;
  end;
end;

function TBFHistoryVM.Note(I: Integer): TBFJson;
begin
  Result := FData.ArrOf('notes').Item(I);
end;

function TBFHistoryVM.IsEmpty: Boolean;
begin
  Result := not Loading and (Count = 0);
end;

function TBFHistoryVM.CurrentVersion: string;
var
  P: TBFJson;
begin
  Result := '';
  if FData = nil then Exit;
  P := FData.ArrOf('products');
  if (P <> nil) and (P.Count > 0) then
    Result := P.Item(0).StrOf('current_version');
end;

function TBFHistoryVM.DateText(I: Integer; const Locale: string): string;
begin
  Result := BFFormatHistoryDate(Note(I).StrOf('published_at'), Locale);
end;

function TBFHistoryVM.NoteColor(I: Integer; const Primary: string): string;
var
  P: TBFJson;
begin
  P := Note(I).ObjOf('product');
  Result := '';
  if P <> nil then
    Result := P.StrOf('color');
  if Result = '' then
    Result := Primary;
end;

procedure TBFHistoryVM.ToggleExpanded(const Id: string);
begin
  if ExpandedId = Id then ExpandedId := '' else ExpandedId := Id;
end;

end.
