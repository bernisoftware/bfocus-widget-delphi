{ Diretivas comuns do bFocus Widget. O mesmo fonte compila em:
  - Delphi 7 até 2007 (string = AnsiString na página de código do Windows);
  - Delphi 2009+ / 10.4+ (string = UnicodeString);
  - Free Pascal / Lazarus (string = AnsiString com UTF-8, convenção do LCL).
  Só construções de Delphi 7: sem generics, métodos anônimos, variáveis inline,
  records com métodos, class var nem for..in. }

{$IFDEF FPC}
  {$MODE DELPHI}
  {$H+}
  {$DEFINE BF_FPC}
{$ELSE}
  {$IFDEF CONDITIONALEXPRESSIONS}
    {$IF CompilerVersion >= 34.0}
      {$DEFINE BF_D104}
    {$IFEND}
    {$IF CompilerVersion >= 20.0}
      {$DEFINE BF_D2009}
    {$IFEND}
    {$IF CompilerVersion >= 21.0}
      {$DEFINE BF_D2010}
    {$IFEND}
  {$ENDIF}
{$ENDIF}

{$IFDEF UNICODE}
  {$DEFINE BF_UNICODE}
{$ENDIF}

{ HtmlViewer (THtmlViewer, livre) renderiza o HTML do conteúdo na UI nativa. Sem ele o
  pacote cai para texto simples. Ligue definindo BFOCUS_HTMLVIEWER no projeto/pacote
  (Delphi: Project > Options > Conditional defines; Lazarus: -dBFOCUS_HTMLVIEWER). }
{.$DEFINE BFOCUS_HTMLVIEWER}
