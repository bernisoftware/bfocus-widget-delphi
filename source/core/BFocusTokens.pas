unit BFocusTokens;

{ GERADO por tools/gen-resources.mjs a partir de widget/src/shared/tokens.json.
  NÃO EDITE: rode  node widgets-native/delphi/tools/gen-resources.mjs }

{$I BFocusDefines.inc}

interface

const
  BF_BRAND_FALLBACK = '#6366F1';

{ Cor '#rrggbb' do token (grupo: ticketStatus, chatStatus, priority, neutral).
  Desconhecido = Default. }
function BFTokenColor(const Group, Name: string; const Default: string = ''): string;
function BFTokenCount: Integer;

implementation

const
  TOKEN_COUNT = 24;
  TOKEN_GROUPS: array[0..TOKEN_COUNT - 1] of string = (
    '',
    'ticketStatus',
    'ticketStatus',
    'ticketStatus',
    'ticketStatus',
    'ticketStatus',
    'ticketStatus',
    'ticketStatus',
    'chatStatus',
    'chatStatus',
    'chatStatus',
    'chatStatus',
    'chatStatus',
    'chatStatus',
    'priority',
    'priority',
    'priority',
    'priority',
    'neutral',
    'neutral',
    'neutral',
    'neutral',
    'neutral',
    'neutral');
  TOKEN_NAMES: array[0..TOKEN_COUNT - 1] of string = (
    'brandFallback',
    'open',
    'in_triage',
    'in_progress',
    'waiting_requester',
    'resolved',
    'closed',
    'cancelled',
    'queued',
    'bot',
    'active',
    'waiting_customer',
    'closed',
    'abandoned',
    'low',
    'medium',
    'high',
    'critical',
    'text',
    'muted',
    'subtle',
    'border',
    'surface',
    'background');
  TOKEN_VALUES: array[0..TOKEN_COUNT - 1] of string = (
    '#6366F1',
    '#3b82f6',
    '#a855f7',
    '#f59e0b',
    '#06b6d4',
    '#10b981',
    '#64748b',
    '#94a3b8',
    '#f59e0b',
    '#0ea5e9',
    '#10b981',
    '#06b6d4',
    '#64748b',
    '#64748b',
    '#10b981',
    '#3b82f6',
    '#f59e0b',
    '#ef4444',
    '#0f172a',
    '#64748b',
    '#94a3b8',
    '#e2e8f0',
    '#f8fafc',
    '#ffffff');

function BFTokenColor(const Group, Name: string; const Default: string): string;
var
  I: Integer;
begin
  for I := 0 to TOKEN_COUNT - 1 do
    if (TOKEN_GROUPS[I] = Group) and (TOKEN_NAMES[I] = Name) then
    begin
      Result := TOKEN_VALUES[I];
      Exit;
    end;
  Result := Default;
end;

function BFTokenCount: Integer;
begin
  Result := TOKEN_COUNT;
end;

end.
