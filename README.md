# bFocus Widget para Delphi

> **English summary.** Native package of the bFocus support widget (tickets, live chat and
> release notes) for Delphi. **Delphi 10.4+ (VCL)**: `TBFocusWidget` hosts the CDN widget in
> `TEdgeBrowser` (WebView2) and speaks Host Protocol v1; without WebView2 it falls back to
> native screens (default) or browser mode. **Delphi 10.4+ (FMX, Windows/macOS)**:
> `TBFocusFmxWidget` with `TWebBrowser`. **Delphi 7+ (VCL)**: `TBFocusNativeWidget`, fully
> native screens built in code (no .dfm), live chat in poll mode. Install with Boss
> (`boss install github.com/bernisoftware/bfocus-widget-delphi`). Put only the public key
> `bf_pk_…` and a `userHash` computed **on your server** in the app. MIT licensed.

Pacote nativo do widget de suporte do bFocus: chamados, chat ao vivo e release notes, com o
**mesmo comportamento do widget web** (`docs/widget-behavior-spec.md`).

| Delphi | Componente | Como mostra o widget |
|---|---|---|
| 10.4+ VCL | `TBFocusWidget` | `embed.html` da CDN num `TEdgeBrowser` (WebView2). Sem WebView2: telas nativas (`NoWebViewFallback = nwNativeUI`, padrão) ou navegador (`nwBrowser`) |
| 10.4+ FMX (Windows, macOS) | `TBFocusFmxWidget` | `TWebBrowser` (Edge no Windows, WKWebView no macOS) |
| 7 até 11/12 VCL | `TBFocusNativeWidget` | telas nativas VCL (Fase 6), chat em modo poll |

Todos têm a mesma API (BRIEF §3), o botão flutuante `TBFocusLauncherButton` e a pílula de
versão `TBFocusReleaseBadge` (no FMX: `TBFocusFmxLauncherButton` e `TBFocusFmxReleaseBadge`).

## Instalação

### Boss (Delphi 10.4+)

```
boss install github.com/bernisoftware/bfocus-widget-delphi
```

O Boss põe `source/` no library path. Se a sua versão do Boss não incluir as subpastas,
acrescente: `source\core;source\common;source\native;source\vcl` (e `source\fmx` no FMX).

Pacotes (em `packages/Delphi10.4+/`, abra e instale nesta ordem):

1. `BFocusCore.dpk` — núcleo sem UI (runtime);
2. `BFocusWidgetVCL.dpk` — VCL: híbrido + telas nativas (runtime);
3. `BFocusWidgetVCLDesign.dpk` — registra na paleta **bFocus** (design);
4. `BFocusWidgetFMX.dpk` e `BFocusWidgetFMXDesign.dpk` — se usar FMX.

As units comuns usam nomes sem escopo (`SysUtils`, `Forms`): o projeto precisa dos *unit
scope names* padrão do Delphi (System, Winapi, Vcl…), que já vêm em projetos novos.

**WebView2:** copie o `WebView2Loader.dll` (redist do RAD Studio, 32 ou 64 bits) para a
pasta do executável. A máquina precisa do runtime do WebView2 (já vem no Windows 11 e nos
Windows 10 atualizados). Sem ele, o `Open` usa as telas nativas.

### Delphi 7 a 2007

1. Descompacte o pacote e abra `packages/Delphi7/BFocusWidgetD7.dpk`.
2. **Compile** e **Install** (paleta **bFocus**: `TBFocusNativeWidget`, botão e pílula).
3. Em Tools > Environment Options > Library > Library path, acrescente
   `source\core;source\common;source\native`.

HTTP pelo WinInet do Windows (HTTPS sem DLL extra). Delphi 7 é ANSI: textos fora da página de
código do Windows (emoji, alguns símbolos) viram "?", e o ícone dos anexos vira uma sigla
(PDF, IMG…).

### HtmlViewer (opcional, recomendado na UI nativa)

O conteúdo (respostas da equipe, release notes) é HTML sanitizado. Com o
[HtmlViewer](https://github.com/BerndGabriel/HtmlViewer) (livre, Delphi 7+ e Lazarus) ele é
renderizado com formatação e links clicáveis; sem ele, vira texto com os links entre
parênteses. Para ligar: instale o HtmlViewer, acrescente o pacote dele ao `requires` do seu
pacote/projeto e defina `BFOCUS_HTMLVIEWER` (Project > Options > Conditional defines).

## Uso

```pascal
uses BFocusConfig, BFocusWidgetVcl;   // Delphi 7: BFocusNativeWidget

procedure TMainForm.FormCreate(Sender: TObject);
begin
  BFocus := TBFocusWidget.Create(Self);            // ou TBFocusNativeWidget
  BFocus.Config.PublishableKey := 'bf_pk_...';     // chave PÚBLICA
  BFocus.Config.AppId := 'com.suaempresa.erp';     // vira a origem app://com.suaempresa.erp
  BFocus.Config.User.ExternalId := Usuario.Id;
  BFocus.Config.User.Name := Usuario.Nome;
  BFocus.Config.User.Email := Usuario.Email;
  BFocus.Config.Customer.ExternalId := Cliente.Id;
  BFocus.Config.Customer.Name := Cliente.Nome;
  BFocus.Config.UserHash := BuscarUserHashNoMeuServidor(Usuario.Id, Cliente.Id);
  BFocus.Config.Notifications := True;             // notificação do sistema quando "•" acende
  BFocus.OnUserHashRequest := PedirHashNovo;       // opcional (hash vencido/rotacionado)
  BFocus.OnError := WidgetErro;
  BFocus.Init;                                      // valida e faz a 1ª consulta

  LauncherButton.Widget := BFocus;                  // TBFocusLauncherButton (opcional)
  ReleaseBadge.Widget := BFocus;                    // TBFocusReleaseBadge (opcional)
end;
```

O `appId` precisa estar cadastrado no bFocus em **Integrações → Apps nativos** (é a origem
permitida `app://<appId em minúsculas>`).

### Configuração (`Config`)

| Campo | Padrão | Observação |
|---|---|---|
| `PublishableKey` | — | obrigatório, `bf_pk_…` |
| `AppId` | — | obrigatório no desktop |
| `User`, `Customer` | — | `ExternalId` obrigatório nos dois |
| `UserHash` | — | HMAC calculado no servidor (abaixo) |
| `Product`, `Audience` | — | slug do produto; `external`, `internal` ou `both` |
| `Locale` | idioma do Windows | `pt_BR`, `en`, `es` (`pt*` → `pt_BR`, `es*` → `es`, resto → `en`) |
| `ShowReleaseNotes` | `True` | splash de novidades dentro dos chamados |
| `AutoShowReleaseBanner` | `True` | abre o banner de ciência sozinho |
| `ApiBaseUrl`, `EmbedBaseUrl` | produção | homologação/testes (`http://` só para 127.0.0.1/localhost) |
| `PollIntervalSeconds` | `60` | consulta do `launcher-state` |
| `Notifications` | `False` | balão na bandeja quando o "•" acende; clicar abre o widget |

### Métodos e eventos

| Método | Efeito |
|---|---|
| `Init` | valida a configuração e faz a primeira consulta (nada roda em paralelo com ela) |
| `Open(ovList \| ovNew \| ovTicket \| ovChat, Id)`, `OpenTicket`, `OpenNewTicket`, `OpenChat` | abre o widget (deep link) |
| `Close`, `Toggle` | fecha mantendo a tela para reabrir rápido |
| `OpenReleaseNotesHistory` | histórico de versões |
| `Refresh` | consulta o `launcher-state` agora |
| `Logout` | para a consulta, cancela push, limpa o estado local e os dados da origem do embed |
| `RegisterPushToken`, `HandlePush(TStrings)` | por completude do contrato (push é só mobile) |

Eventos: `OnBadgeChanged(label)` com `''`/`•`/`N`/`99+`, `OnReleaseNotesChanged(label,
dot, bannerIds)`, `OnError(code, detail)`, `OnOpen`, `OnClose`, `OnUserHashRequest(var
hash)`.

A consulta roda a cada `PollIntervalSeconds` **enquanto o app estiver aberto, mesmo sem foco,
com o widget fechado** (senão a notificação nunca apareceria). Rede ou 5xx: silêncio.

### Erros (`OnError`)

| Código | Quando |
|---|---|
| `WIDGET_USER_HASH_INVALID`, `WIDGET_USER_HASH_EXPIRED`, `WIDGET_VERIFIED_SESSION_REQUIRED` | identidade recusada (401; `_EXPIRED` = assinatura v2 fora dos 7 dias, renovada sem avisar quando há `OnUserHashRequest`). Com `OnUserHashRequest`, o pacote pede um hash novo **uma vez** e repete; só avisa se a repetição também for recusada. O mesmo código é avisado uma vez, até o próximo sucesso |
| `HTTP_403` (ou o código do envelope) | outros 4xx do `launcher-state`, ex.: origem não cadastrada |
| `WIDGET_CONFIG_FAILED` | `/config` falhou ao abrir o widget |
| `DOWNLOAD_FAILED` | download de anexo (híbrido) |

### Modo navegador

Com `NoWebViewFallback = nwBrowser` e sem WebView2, o `Open` abre o navegador padrão na URL
do embed com `host=browser`. Badge e pílula continuam pelo REST. O banner de ciência **não**
abre sozinho nesse modo: a pílula acende o ponto e o banner aparece quando o usuário abre as
novidades.

## Segurança

- No app vão **só** a chave pública `bf_pk_…` e o `userHash`. **Nunca** `bf_whs_…` (segredo
  do widget), `bf_live_…` ou `bf_sk_…`: o `Init` recusa esses prefixos.
- O `userHash` é `hex(HMAC-SHA256(segredo, "v1:" + user.externalId + ":" + customer.externalId))`,
  calculado no **seu servidor** com os SDKs do bFocus (`sign_widget_identity`) e entregue ao
  app depois do login.
- A origem `app://…` é só um rótulo. A proteção real é o `userHash` + "Exigir sessão
  verificada" ligado no tenant.
- Híbrido: a ponte aceita mensagens só da origem do `EmbedBaseUrl` (`args.Source` do
  WebView2) e só tipos conhecidos; navegação para outra origem é cancelada e aberta no
  navegador.

## Diferenças aceitas (UI nativa, behavior spec §10)

- Editor: texto simples com marcação leve — **negrito** (`**x**`), *itálico* (`*x*`),
  ~~riscado~~, listas (`- `, `1. `), citação (`> `), `código` e link (campo sob a barra:
  Enter aplica, Esc cancela, vazio remove, sem esquema vira `https://`). Imagem colada não.
- HTML pelo HtmlViewer (ou texto, sem ele).
- Chat sempre em modo poll (5 s), sem SSE.

## FMX: como a página fala com o host

O `TWebBrowser` do FMX não entrega mensagens da página ao Delphi. O pacote injeta
`window.bFocusHost.postMessage` (canal genérico do Host Protocol) e o shim coloca cada
mensagem no fragmento da URL (`#bfq=<seq>:<json>`); o host lê `TWebBrowser.URL` a cada
200 ms e confirma com `window.__bfAck(seq)`. Não dá para cancelar navegações no FMX: links
para fora são abertos no navegador e o embed é recarregado.

## Testes

O núcleo compila em Free Pascal e é testado no CI (o Delphi não roda em CI):

```
sh tests/build-fpc.sh tests/out
node tests/run-tests.mjs tests/out/BFocusTests
```

Roda `scenarios.json` (payload do usuário, URL do embed, `launcher-state`, badge, pílula,
push), os view-models das telas e a integração HTTP contra o servidor simulado
(`tests/conformance/mock-server.mjs`). No Delphi 2009+, compile `tests/BFocusTests.dpr` com
`dcc32 --codepage:65001` (os testes são UTF-8).

`tools/check-sources.mjs` barra construções que só o Delphi pega (literal com acento, `{`
dentro de comentário). `tools/gen-resources.mjs` regera `BFocusI18n.pas` e
`BFocusTokens.pas` a partir de `widget/src/shared/{i18n,tokens}.json` (monorepo).

## Dependências

- Delphi 10.4+: RTL/VCL/FMX, `Vcl.Edge` + `WebView2Loader.dll` (redist do RAD Studio).
- Delphi 7: RTL/VCL, `jpeg` (prévia de imagens JPEG).
- Opcional: HtmlViewer (MIT).
- Nenhuma outra dependência de terceiros.

## Licença

MIT — Copyright (c) 2026 Berni Software.
