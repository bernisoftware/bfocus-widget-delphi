# Changelog

## 0.1.0 — 2026-09-15

Primeira versão.

- **Núcleo** (Delphi 7+ e FPC): JSON próprio com ordem de chaves, base64, URL RFC 3986,
  payload do usuário, URL do embed, request do `launcher-state`, badge, pílula, push e o
  cliente completo da API do widget (chamados, anexos, release notes, chat).
- **Delphi 10.4+ VCL**: `TBFocusWidget` híbrido com `TEdgeBrowser` (WebView2), ponte do
  Host Protocol v1 com checagem de origem, navegação travada, download com "salvar como",
  banner modal sem fechar, notificação na bandeja, `TBFocusLauncherButton` e
  `TBFocusReleaseBadge`. Sem WebView2: telas nativas (padrão) ou modo navegador.
- **Delphi 10.4+ FMX**: `TBFocusFmxWidget` com `TWebBrowser` e ponte por fragmento de URL.
- **Delphi 7+ (VCL)**: `TBFocusNativeWidget`, telas nativas da Fase 6 (lista, novo
  chamado, detalhe, chat em modo poll, splash, banner e histórico de release notes).
- Testes do núcleo com FPC sobre `scenarios.json` + integração com o servidor simulado.
