unit BFocusI18n;

{ GERADO por tools/gen-resources.mjs a partir de widget/src/shared/i18n/*.json.
  NÃO EDITE: rode  node widgets-native/delphi/tools/gen-resources.mjs }

{$I BFocusDefines.inc}

interface

const
  BF_LOCALE_COUNT = 3;
  BF_LOCALES: array[0..BF_LOCALE_COUNT - 1] of string = ('pt_BR', 'en', 'es');

{ Texto do widget de chamados (seção "tickets"). Chave ausente no idioma cai para pt_BR;
  chave desconhecida devolve a própria chave (mesma regra do makeT do web). }
function BFT(const Locale, Key: string): string;
{ Texto do widget de release notes (seção "releaseNotes"). }
function BFRN(const Locale, Key: string): string;
{ Interpola o marcador (nome entre chaves) numa string traduzida: BFFill(BFT(L, 'chat_queue_size'), 'n', '3'). }
function BFFill(const S, Name, Value: string): string;
{ Índice do idioma em BF_LOCALES (desconhecido = 0, pt_BR). }
function BFLocaleIndex(const Locale: string): Integer;
{ Quantidade de chaves (para testes). }
function BFTicketKeyCount: Integer;
function BFTicketKey(I: Integer): string;
function BFReleaseNotesKeyCount: Integer;
function BFReleaseNotesKey(I: Integer): string;

implementation

uses
  SysUtils, BFocusText;

const
  TK_KEYS: array[0..140] of string = (
    'header_title',
    'tab_list',
    'tab_new',
    'empty_state_title',
    'empty_state_desc',
    'btn_new_ticket',
    'btn_back',
    'btn_close',
    'btn_send',
    'btn_create',
    'btn_attach',
    'attach_drag_hint',
    'attach_drop_here',
    'attach_uploading',
    'new_step_title',
    'new_step_priority',
    'new_step_describe',
    'new_field_title',
    'new_field_title_placeholder',
    'new_field_description',
    'new_field_description_placeholder',
    'new_field_department',
    'new_field_department_hint',
    'new_field_department_any',
    'priority_low',
    'priority_medium',
    'priority_high',
    'priority_critical',
    'type_support',
    'type_bug',
    'type_request',
    'type_incident',
    'status_open',
    'status_in_triage',
    'status_in_progress',
    'status_waiting_requester',
    'status_resolved',
    'status_closed',
    'status_cancelled',
    'detail_send_placeholder',
    'detail_no_messages',
    'you',
    'support_team',
    'loading',
    'error_generic',
    'error_load',
    'chat_online_title',
    'chat_online_desc',
    'chat_busy_title',
    'chat_busy_desc',
    'chat_queue_size',
    'chat_offline_title',
    'chat_offline_desc',
    'btn_chat_now',
    'btn_chat_queue',
    'btn_leave_message',
    'btn_open_ticket_instead',
    'chat_active_title',
    'btn_chat_resume',
    'chat_new_title',
    'chat_continue_title',
    'chat_new_intro',
    'chat_placeholder',
    'chat_protocol',
    'chat_status_queued',
    'chat_status_queued_pos',
    'chat_status_active',
    'chat_status_active_with',
    'chat_status_waiting_customer',
    'chat_status_closed',
    'btn_chat_end',
    'chat_end_confirm',
    'btn_cancel',
    'chat_closed_notice',
    'btn_chat_continue',
    'chat_msg_sending',
    'chat_msg_failed',
    'btn_retry',
    'btn_discard',
    'chat_reconnecting',
    'chat_connection_failed',
    'chat_offline_fallback',
    'chat_bot',
    'btn_attach_file',
    'btn_remove',
    'csat_title',
    'csat_comment_placeholder',
    'csat_submit',
    'csat_thanks',
    'csat_star',
    'error_identity',
    'chat_status_bot',
    'chat_status_bot_with',
    'chat_bot_hint',
    'btn_talk_to_human',
    'chat_handoff_requested',
    'chat_handoff_error',
    'chat_handoff_text',
    'chat_new_intro_bot',
    'chat_new_intro_bot_named',
    'chat_online_desc_bot',
    'csat_sending',
    'csat_retry',
    'csat_error_timeout',
    'csat_error_network',
    'csat_error_generic',
    'csat_not_resolved',
    'chat_followup_notice',
    'btn_view_ticket',
    'detail_chat_title',
    'detail_chat_with',
    'detail_chat_ongoing',
    'detail_chat_count_one',
    'detail_chat_count',
    'detail_chat_empty',
    'detail_chat_error',
    'detail_interactions_title',
    'detail_reopen_hint',
    'detail_reopen_hint_nodate',
    'detail_closed_notice',
    'detail_continuation_of',
    'splash_eyebrow',
    'splash_title',
    'splash_count_one',
    'splash_count_many',
    'splash_expand',
    'splash_collapse',
    'splash_mark_read',
    'splash_skip',
    'editor_bold',
    'editor_italic',
    'editor_strike',
    'editor_bullet_list',
    'editor_ordered_list',
    'editor_quote',
    'editor_code',
    'editor_link',
    'attach_file',
    'editor_link_placeholder',
    'editor_link_apply',
    'editor_link_remove');
{$IFDEF BF_UNICODE}
  TK_PT_BR: array[0..140] of string = (
    'Suporte',
    'Meus chamados',
    'Novo chamado',
    'Nenhum chamado ainda',
    'Abra seu primeiro chamado para come'#$00E7'ar.',
    'Abrir chamado',
    'Voltar',
    'Fechar',
    'Enviar',
    'Criar chamado',
    'Anexar',
    'Anexar ou arraste arquivos aqui',
    'Solte os arquivos para anexar',
    'Enviando'#$2026,
    'Sobre o que '#$00E9'?',
    'Prioridade',
    'Descreva o problema',
    'T'#$00ED'tulo',
    'Resumo curto do problema',
    'Descri'#$00E7#$00E3'o (opcional)',
    'Detalhes, passos para reproduzir, contexto...',
    'Departamento de destino',
    'Para qual departamento enviar a solicita'#$00E7#$00E3'o ' +
      #$2014' n'#$00E3'o o seu.',
    'Sem prefer'#$00EA'ncia',
    'Baixa',
    'M'#$00E9'dia',
    'Alta',
    'Cr'#$00ED'tica',
    'D'#$00FA'vida',
    'Erro',
    'Solicita'#$00E7#$00E3'o',
    'Incidente',
    'Aberto',
    'Em triagem',
    'Em andamento',
    'Aguardando voc'#$00EA,
    'Resolvido',
    'Fechado',
    'Cancelado',
    'Escreva sua mensagem...',
    'Nenhuma mensagem ainda.',
    'Voc'#$00EA,
    'Equipe de suporte',
    'Carregando...',
    'Algo deu errado. Tente novamente.',
    'Falha ao carregar.',
    'Fale com a gente',
    'Atendentes dispon'#$00ED'veis agora.',
    'Atendentes ocupados',
    'Todos est'#$00E3'o em atendimento. Entre na fila e voc' +
      #$00EA' ser'#$00E1' atendido assim que poss'#$00ED'vel.',
    '{n} na fila agora',
    'Estamos fora do ar agora',
    'Deixe sua mensagem e responderemos o quanto antes.',
    'Conversar agora',
    'Entrar na fila',
    'Deixe sua mensagem',
    'Prefiro abrir um chamado',
    'Conversa em andamento',
    'Voltar '#$00E0' conversa',
    'Nova conversa',
    'Continuar atendimento',
    'Ol'#$00E1'! Conte como podemos ajudar '#$2014 +
      ' um atendente vai responder por aqui.',
    'Escreva uma mensagem'#$2026,
    'Protocolo',
    'Na fila',
    'Na fila '#$2014' posi'#$00E7#$00E3'o {n}',
    'Em atendimento',
    'Em atendimento com {name}',
    'Aguardando voc'#$00EA,
    'Encerrado',
    'Encerrar',
    'Encerrar esta conversa?',
    'Cancelar',
    'Esta conversa foi encerrada.',
    'Continuar conversa',
    'Enviando'#$2026,
    'N'#$00E3'o enviada.',
    'Tentar novamente',
    'Descartar',
    'Reconectando'#$2026,
    'Sem conex'#$00E3 +
      'o em tempo real. Reabra o widget para tentar de no' + 'vo.',
    'Nossos atendentes ficaram indispon'#$00ED +
      'veis. Deixe sua mensagem aqui e responderemos o qu' +
      'anto antes.',
    'Assistente',
    'Anexar arquivo',
    'Remover',
    'Como foi o atendimento?',
    'Quer deixar um coment'#$00E1'rio? (opcional)',
    'Enviar avalia'#$00E7#$00E3'o',
    'Obrigado pela avalia'#$00E7#$00E3'o!',
    '{n} de 5',
    'N'#$00E3'o foi poss'#$00ED +
      'vel confirmar sua identidade. Recarregue a p'#$00E1 +
      'gina; se continuar, fale com o suporte do sistema.',
    'Com o assistente virtual',
    'Com {name}, assistente virtual',
    'Voc'#$00EA' est'#$00E1' falando com um assistente virtual.',
    'Falar com um atendente',
    'Pedido enviado: um atendente vai assumir a convers' + 'a.',
    'N'#$00E3'o foi poss'#$00ED +
      'vel chamar um atendente agora. Tente de novo.',
    'Quero falar com um atendente.',
    'Ol'#$00E1 +
      '! Sou o assistente virtual e respondo na hora. Se ' +
      'preferir, pe'#$00E7'a um atendente a qualquer momento.',
    'Ol'#$00E1 +
      '! Sou {name}, o assistente virtual, e respondo na ' +
      'hora. Se preferir, pe'#$00E7 +
      'a um atendente a qualquer momento.',
    'Nosso assistente virtual responde na hora, 24 hora' + 's. Voc' +
      #$00EA' pode pedir um atendente quando quiser.',
    'Enviando avalia'#$00E7#$00E3'o'#$2026,
    'Tentar de novo',
    'A avalia'#$00E7#$00E3'o n'#$00E3 +
      'o foi enviada: o servidor demorou demais para resp' +
      'onder. Verifique sua conex'#$00E3'o e tente de novo.',
    'Sem conex'#$00E3 +
      'o com o servidor. Verifique sua internet e tente d' +
      'e novo.',
    'N'#$00E3'o foi poss'#$00ED'vel enviar sua avalia'#$00E7 +
      #$00E3'o agora. Tente de novo.',
    'Seu chamado ainda est'#$00E1' em andamento. Voc'#$00EA +
      ' poder'#$00E1 +
      ' avaliar o atendimento assim que ele for resolvido' + '.',
    'Seu atendimento continua pelo chamado {n}. Voc'#$00EA +
      ' recebe a resposta por aqui e por e-mail.',
    'Ver chamado',
    'Conversa do chat',
    'com {name}',
    'em andamento',
    '1 mensagem',
    '{n} mensagens',
    'Nenhuma mensagem nesta conversa.',
    'N'#$00E3'o foi poss'#$00ED +
      'vel carregar a conversa do chat.',
    'Andamento do chamado',
    'Se o problema voltar, responda por aqui '#$2014 +
      ' o chamado '#$00E9' reaberto (at'#$00E9' {date}).',
    'Se o problema voltar, responda por aqui '#$2014 +
      ' o chamado '#$00E9' reaberto.',
    'Este chamado foi encerrado. Se precisar, abra uma ' +
      'nova conversa ou chamado '#$2014' ele ficar'#$00E1 +
      ' ligado a este.',
    'Continua'#$00E7#$00E3'o de {n}',
    'Novidades pra voc'#$00EA,
    'Antes de continuar '#$2014' confira o que mudou',
    '1 novidade aguardando sua leitura. Marque como lid' +
      'a pra continuar.',
    '{n} novidades aguardando. Marque cada uma como lid' +
      'a ou pule por agora.',
    'Ver detalhes',
    'Recolher',
    #$2713' Marcar como lida',
    'Pular por agora '#$2014 +
      ' volto a lembrar ao abrir o widget de novo',
    'Negrito',
    'It'#$00E1'lico',
    'Riscado',
    'Lista',
    'Lista numerada',
    'Cita'#$00E7#$00E3'o',
    'C'#$00F3'digo',
    'Link',
    'Anexar arquivo',
    'https://'#$2026,
    'Aplicar',
    'Remover link');
  TK_EN: array[0..140] of string = (
    'Support',
    'My tickets',
    'New ticket',
    'No tickets yet',
    'Open your first ticket to get started.',
    'Open ticket',
    'Back',
    'Close',
    'Send',
    'Create ticket',
    'Attach',
    'Attach or drag files here',
    'Drop files to attach',
    'Uploading'#$2026,
    'What is it about?',
    'Priority',
    'Describe the issue',
    'Title',
    'Short summary of the issue',
    'Description (optional)',
    'Details, steps to reproduce, context...',
    'Destination department',
    'Which department to send the request to '#$2014 +
      ' not your own.',
    'No preference',
    'Low',
    'Medium',
    'High',
    'Critical',
    'Question',
    'Bug',
    'Request',
    'Incident',
    'Open',
    'In triage',
    'In progress',
    'Waiting on you',
    'Resolved',
    'Closed',
    'Cancelled',
    'Write your message...',
    'No messages yet.',
    'You',
    'Support team',
    'Loading...',
    'Something went wrong. Try again.',
    'Failed to load.',
    'Chat with us',
    'Agents available now.',
    'Agents are busy',
    'Everyone is helping other people. Join the queue a' +
      'nd you will be served as soon as possible.',
    '{n} in the queue now',
    'We are offline right now',
    'Leave us a message and we will get back to you as ' +
      'soon as possible.',
    'Chat now',
    'Join the queue',
    'Leave a message',
    'I would rather open a ticket',
    'Ongoing conversation',
    'Back to conversation',
    'New conversation',
    'Continue conversation',
    'Hi! Tell us how we can help '#$2014 +
      ' an agent will reply right here.',
    'Write a message'#$2026,
    'Protocol',
    'In queue',
    'In queue '#$2014' position {n}',
    'Being served',
    'Being served by {name}',
    'Waiting on you',
    'Closed',
    'End',
    'End this conversation?',
    'Cancel',
    'This conversation has ended.',
    'Continue conversation',
    'Sending'#$2026,
    'Not sent.',
    'Try again',
    'Discard',
    'Reconnecting'#$2026,
    'No real-time connection. Reopen the widget to try ' + 'again.',
    'Our agents became unavailable. Leave your message ' +
      'here and we will get back to you as soon as possib' + 'le.',
    'Assistant',
    'Attach file',
    'Remove',
    'How was your experience?',
    'Want to leave a comment? (optional)',
    'Send rating',
    'Thanks for your feedback!',
    '{n} of 5',
    'We couldn''t verify your identity. Reload the page;' +
      ' if it keeps happening, contact the system''s suppo' + 'rt.',
    'With the virtual assistant',
    'With {name}, virtual assistant',
    'You are chatting with a virtual assistant.',
    'Talk to a person',
    'Request sent: a person will take over the conversa' + 'tion.',
    'We could not reach a person right now. Please try ' + 'again.',
    'I want to talk to a human agent.',
    'Hi! I am the virtual assistant and I answer right ' +
      'away. If you prefer, ask for a person at any time.',
    'Hi! I am {name}, the virtual assistant, and I answ' +
      'er right away. If you prefer, ask for a person at ' +
      'any time.',
    'Our virtual assistant answers right away, 24/7. Yo' +
      'u can ask for a person whenever you want.',
    'Sending rating'#$2026,
    'Try again',
    'Your rating was not sent: the server took too long' +
      ' to respond. Check your connection and try again.',
    'Could not reach the server. Check your internet co' +
      'nnection and try again.',
    'We could not send your rating right now. Please tr' +
      'y again.',
    'Your ticket is still in progress. You will be able' +
      ' to rate the service once it is resolved.',
    'Your request continues in ticket {n}. You will get' +
      ' the answer here and by email.',
    'View ticket',
    'Chat conversation',
    'with {name}',
    'ongoing',
    '1 message',
    '{n} messages',
    'No messages in this conversation.',
    'Could not load the chat conversation.',
    'Ticket updates',
    'If the problem comes back, reply here '#$2014 +
      ' the ticket will be reopened (until {date}).',
    'If the problem comes back, reply here '#$2014 +
      ' the ticket will be reopened.',
    'This ticket has been closed. If you need to, start' +
      ' a new conversation or ticket '#$2014 +
      ' it will be linked to this one.',
    'Continuation of {n}',
    'What'#$2019's new for you',
    'Before you continue '#$2014' see what changed',
    '1 update waiting for you. Mark it as read to conti' + 'nue.',
    '{n} updates waiting. Mark each one as read or skip' +
      ' for now.',
    'See details',
    'Collapse',
    #$2713' Mark as read',
    'Skip for now '#$2014' I'#$2019 +
      'll remind you next time you open the widget',
    'Bold',
    'Italic',
    'Strikethrough',
    'Bulleted list',
    'Numbered list',
    'Quote',
    'Code',
    'Link',
    'Attach file',
    'https://'#$2026,
    'Apply',
    'Remove link');
  TK_ES: array[0..140] of string = (
    'Soporte',
    'Mis tickets',
    'Nuevo ticket',
    'A'#$00FA'n no hay tickets',
    'Abre tu primer ticket para empezar.',
    'Abrir ticket',
    'Volver',
    'Cerrar',
    'Enviar',
    'Crear ticket',
    'Adjuntar',
    'Adjuntar o arrastra archivos aqu'#$00ED,
    'Suelta los archivos para adjuntar',
    'Subiendo'#$2026,
    #$00BF'Sobre qu'#$00E9' es?',
    'Prioridad',
    'Describe el problema',
    'T'#$00ED'tulo',
    'Resumen corto del problema',
    'Descripci'#$00F3'n (opcional)',
    'Detalles, pasos para reproducir, contexto...',
    'Departamento de destino',
    'A qu'#$00E9' departamento enviar la solicitud '#$2014 +
      ' no el tuyo.',
    'Sin preferencia',
    'Baja',
    'Media',
    'Alta',
    'Cr'#$00ED'tica',
    'Consulta',
    'Error',
    'Solicitud',
    'Incidente',
    'Abierto',
    'En triaje',
    'En curso',
    'Esperando tu respuesta',
    'Resuelto',
    'Cerrado',
    'Cancelado',
    'Escribe tu mensaje...',
    'A'#$00FA'n no hay mensajes.',
    'T'#$00FA,
    'Equipo de soporte',
    'Cargando...',
    'Algo sali'#$00F3' mal. Int'#$00E9'ntalo de nuevo.',
    'No se pudo cargar.',
    'Habla con nosotros',
    'Agentes disponibles ahora.',
    'Agentes ocupados',
    'Todos est'#$00E1 +
      'n atendiendo. Entra en la fila y te atenderemos lo' +
      ' antes posible.',
    '{n} en la fila ahora',
    'Estamos fuera de l'#$00ED'nea',
    'D'#$00E9 +
      'janos tu mensaje y te responderemos lo antes posib' + 'le.',
    'Chatear ahora',
    'Entrar en la fila',
    'Deja tu mensaje',
    'Prefiero abrir un ticket',
    'Conversaci'#$00F3'n en curso',
    'Volver a la conversaci'#$00F3'n',
    'Nueva conversaci'#$00F3'n',
    'Continuar atenci'#$00F3'n',
    #$00A1'Hola! Cu'#$00E9'ntanos c'#$00F3'mo podemos ayudarte ' +
      #$2014' un agente responder'#$00E1' aqu'#$00ED'.',
    'Escribe un mensaje'#$2026,
    'Protocolo',
    'En la fila',
    'En la fila '#$2014' posici'#$00F3'n {n}',
    'En atenci'#$00F3'n',
    'En atenci'#$00F3'n con {name}',
    'Esperando tu respuesta',
    'Finalizada',
    'Finalizar',
    #$00BF'Finalizar esta conversaci'#$00F3'n?',
    'Cancelar',
    'Esta conversaci'#$00F3'n ha finalizado.',
    'Continuar conversaci'#$00F3'n',
    'Enviando'#$2026,
    'No enviado.',
    'Reintentar',
    'Descartar',
    'Reconectando'#$2026,
    'Sin conexi'#$00F3 +
      'n en tiempo real. Vuelve a abrir el widget para in' +
      'tentarlo de nuevo.',
    'Nuestros agentes ya no est'#$00E1 +
      'n disponibles. Deja tu mensaje aqu'#$00ED +
      ' y te responderemos lo antes posible.',
    'Asistente',
    'Adjuntar archivo',
    'Quitar',
    #$00BF'C'#$00F3'mo fue la atenci'#$00F3'n?',
    #$00BF'Quieres dejar un comentario? (opcional)',
    'Enviar valoraci'#$00F3'n',
    #$00A1'Gracias por tu valoraci'#$00F3'n!',
    '{n} de 5',
    'No pudimos verificar tu identidad. Recarga la p'#$00E1 +
      'gina; si contin'#$00FA'a, contacta al soporte del sistema.',
    'Con el asistente virtual',
    'Con {name}, asistente virtual',
    'Est'#$00E1's hablando con un asistente virtual.',
    'Hablar con un agente',
    'Solicitud enviada: un agente tomar'#$00E1' la conversaci' +
      #$00F3'n.',
    'No pudimos llamar a un agente ahora. Int'#$00E9 +
      'ntalo de nuevo.',
    'Quiero hablar con un agente humano.',
    #$00A1'Hola! Soy el asistente virtual y respondo al insta' +
      'nte. Si lo prefieres, pide un agente en cualquier ' +
      'momento.',
    #$00A1'Hola! Soy {name}, el asistente virtual, y respondo' +
      ' al instante. Si lo prefieres, pide un agente en c' +
      'ualquier momento.',
    'Nuestro asistente virtual responde al instante, 24' +
      ' horas. Puedes pedir un agente cuando quieras.',
    'Enviando valoraci'#$00F3'n'#$2026,
    'Intentar de nuevo',
    'La valoraci'#$00F3'n no se envi'#$00F3': el servidor tard' +
      #$00F3' demasiado en responder. Revisa tu conexi'#$00F3 +
      'n e int'#$00E9'ntalo de nuevo.',
    'Sin conexi'#$00F3 +
      'n con el servidor. Revisa tu internet e int'#$00E9 +
      'ntalo de nuevo.',
    'No pudimos enviar tu valoraci'#$00F3'n ahora. Int'#$00E9 +
      'ntalo de nuevo.',
    'Tu ticket sigue en curso. Podr'#$00E1's valorar la atenci' +
      #$00F3'n cuando se resuelva.',
    'Tu atenci'#$00F3'n contin'#$00FA +
      'a en el ticket {n}. Recibir'#$00E1's la respuesta aqu' +
      #$00ED' y por correo electr'#$00F3'nico.',
    'Ver ticket',
    'Conversaci'#$00F3'n del chat',
    'con {name}',
    'en curso',
    '1 mensaje',
    '{n} mensajes',
    'No hay mensajes en esta conversaci'#$00F3'n.',
    'No se pudo cargar la conversaci'#$00F3'n del chat.',
    'Seguimiento del ticket',
    'Si el problema vuelve, responde aqu'#$00ED +
      ': el ticket se reabrir'#$00E1' (hasta el {date}).',
    'Si el problema vuelve, responde aqu'#$00ED +
      ': el ticket se reabrir'#$00E1'.',
    'Este ticket fue cerrado. Si lo necesitas, abre una' +
      ' nueva conversaci'#$00F3'n o ticket: quedar'#$00E1 +
      ' vinculado a este.',
    'Continuaci'#$00F3'n de {n}',
    'Novedades para ti',
    'Antes de continuar '#$2014' mira lo que cambi'#$00F3,
    '1 novedad esperando tu lectura. M'#$00E1'rcala como le' +
      #$00ED'da para continuar.',
    '{n} novedades esperando. Marca cada una como le'#$00ED +
      'da u omite por ahora.',
    'Ver detalles',
    'Contraer',
    #$2713' Marcar como le'#$00ED'da',
    'Omitir por ahora '#$2014 +
      ' te lo recuerdo al abrir el widget de nuevo',
    'Negrita',
    'Cursiva',
    'Tachado',
    'Lista',
    'Lista numerada',
    'Cita',
    'C'#$00F3'digo',
    'Enlace',
    'Adjuntar archivo',
    'https://'#$2026,
    'Aplicar',
    'Quitar enlace');
{$ELSE}
  TK_PT_BR: array[0..140] of TBFRaw = (
    'Suporte',
    'Meus chamados',
    'Novo chamado',
    'Nenhum chamado ainda',
    'Abra seu primeiro chamado para come'#$C3#$A7'ar.',
    'Abrir chamado',
    'Voltar',
    'Fechar',
    'Enviar',
    'Criar chamado',
    'Anexar',
    'Anexar ou arraste arquivos aqui',
    'Solte os arquivos para anexar',
    'Enviando'#$E2#$80#$A6,
    'Sobre o que '#$C3#$A9'?',
    'Prioridade',
    'Descreva o problema',
    'T'#$C3#$AD'tulo',
    'Resumo curto do problema',
    'Descri'#$C3#$A7#$C3#$A3'o (opcional)',
    'Detalhes, passos para reproduzir, contexto...',
    'Departamento de destino',
    'Para qual departamento enviar a solicita'#$C3#$A7#$C3#$A3 +
      'o '#$E2#$80#$94' n'#$C3#$A3'o o seu.',
    'Sem prefer'#$C3#$AA'ncia',
    'Baixa',
    'M'#$C3#$A9'dia',
    'Alta',
    'Cr'#$C3#$AD'tica',
    'D'#$C3#$BA'vida',
    'Erro',
    'Solicita'#$C3#$A7#$C3#$A3'o',
    'Incidente',
    'Aberto',
    'Em triagem',
    'Em andamento',
    'Aguardando voc'#$C3#$AA,
    'Resolvido',
    'Fechado',
    'Cancelado',
    'Escreva sua mensagem...',
    'Nenhuma mensagem ainda.',
    'Voc'#$C3#$AA,
    'Equipe de suporte',
    'Carregando...',
    'Algo deu errado. Tente novamente.',
    'Falha ao carregar.',
    'Fale com a gente',
    'Atendentes dispon'#$C3#$AD'veis agora.',
    'Atendentes ocupados',
    'Todos est'#$C3#$A3'o em atendimento. Entre na fila e voc' +
      #$C3#$AA' ser'#$C3#$A1' atendido assim que poss'#$C3#$AD +
      'vel.',
    '{n} na fila agora',
    'Estamos fora do ar agora',
    'Deixe sua mensagem e responderemos o quanto antes.',
    'Conversar agora',
    'Entrar na fila',
    'Deixe sua mensagem',
    'Prefiro abrir um chamado',
    'Conversa em andamento',
    'Voltar '#$C3#$A0' conversa',
    'Nova conversa',
    'Continuar atendimento',
    'Ol'#$C3#$A1'! Conte como podemos ajudar '#$E2#$80#$94 +
      ' um atendente vai responder por aqui.',
    'Escreva uma mensagem'#$E2#$80#$A6,
    'Protocolo',
    'Na fila',
    'Na fila '#$E2#$80#$94' posi'#$C3#$A7#$C3#$A3'o {n}',
    'Em atendimento',
    'Em atendimento com {name}',
    'Aguardando voc'#$C3#$AA,
    'Encerrado',
    'Encerrar',
    'Encerrar esta conversa?',
    'Cancelar',
    'Esta conversa foi encerrada.',
    'Continuar conversa',
    'Enviando'#$E2#$80#$A6,
    'N'#$C3#$A3'o enviada.',
    'Tentar novamente',
    'Descartar',
    'Reconectando'#$E2#$80#$A6,
    'Sem conex'#$C3#$A3 +
      'o em tempo real. Reabra o widget para tentar de no' + 'vo.',
    'Nossos atendentes ficaram indispon'#$C3#$AD +
      'veis. Deixe sua mensagem aqui e responderemos o qu' +
      'anto antes.',
    'Assistente',
    'Anexar arquivo',
    'Remover',
    'Como foi o atendimento?',
    'Quer deixar um coment'#$C3#$A1'rio? (opcional)',
    'Enviar avalia'#$C3#$A7#$C3#$A3'o',
    'Obrigado pela avalia'#$C3#$A7#$C3#$A3'o!',
    '{n} de 5',
    'N'#$C3#$A3'o foi poss'#$C3#$AD +
      'vel confirmar sua identidade. Recarregue a p'#$C3#$A1 +
      'gina; se continuar, fale com o suporte do sistema.',
    'Com o assistente virtual',
    'Com {name}, assistente virtual',
    'Voc'#$C3#$AA' est'#$C3#$A1 +
      ' falando com um assistente virtual.',
    'Falar com um atendente',
    'Pedido enviado: um atendente vai assumir a convers' + 'a.',
    'N'#$C3#$A3'o foi poss'#$C3#$AD +
      'vel chamar um atendente agora. Tente de novo.',
    'Quero falar com um atendente.',
    'Ol'#$C3#$A1 +
      '! Sou o assistente virtual e respondo na hora. Se ' +
      'preferir, pe'#$C3#$A7'a um atendente a qualquer momento.',
    'Ol'#$C3#$A1 +
      '! Sou {name}, o assistente virtual, e respondo na ' +
      'hora. Se preferir, pe'#$C3#$A7 +
      'a um atendente a qualquer momento.',
    'Nosso assistente virtual responde na hora, 24 hora' + 's. Voc' +
      #$C3#$AA' pode pedir um atendente quando quiser.',
    'Enviando avalia'#$C3#$A7#$C3#$A3'o'#$E2#$80#$A6,
    'Tentar de novo',
    'A avalia'#$C3#$A7#$C3#$A3'o n'#$C3#$A3 +
      'o foi enviada: o servidor demorou demais para resp' +
      'onder. Verifique sua conex'#$C3#$A3'o e tente de novo.',
    'Sem conex'#$C3#$A3 +
      'o com o servidor. Verifique sua internet e tente d' +
      'e novo.',
    'N'#$C3#$A3'o foi poss'#$C3#$AD'vel enviar sua avalia'#$C3 +
      #$A7#$C3#$A3'o agora. Tente de novo.',
    'Seu chamado ainda est'#$C3#$A1' em andamento. Voc'#$C3#$AA +
      ' poder'#$C3#$A1 +
      ' avaliar o atendimento assim que ele for resolvido' + '.',
    'Seu atendimento continua pelo chamado {n}. Voc'#$C3#$AA +
      ' recebe a resposta por aqui e por e-mail.',
    'Ver chamado',
    'Conversa do chat',
    'com {name}',
    'em andamento',
    '1 mensagem',
    '{n} mensagens',
    'Nenhuma mensagem nesta conversa.',
    'N'#$C3#$A3'o foi poss'#$C3#$AD +
      'vel carregar a conversa do chat.',
    'Andamento do chamado',
    'Se o problema voltar, responda por aqui '#$E2#$80#$94 +
      ' o chamado '#$C3#$A9' reaberto (at'#$C3#$A9' {date}).',
    'Se o problema voltar, responda por aqui '#$E2#$80#$94 +
      ' o chamado '#$C3#$A9' reaberto.',
    'Este chamado foi encerrado. Se precisar, abra uma ' +
      'nova conversa ou chamado '#$E2#$80#$94' ele ficar'#$C3#$A1 +
      ' ligado a este.',
    'Continua'#$C3#$A7#$C3#$A3'o de {n}',
    'Novidades pra voc'#$C3#$AA,
    'Antes de continuar '#$E2#$80#$94' confira o que mudou',
    '1 novidade aguardando sua leitura. Marque como lid' +
      'a pra continuar.',
    '{n} novidades aguardando. Marque cada uma como lid' +
      'a ou pule por agora.',
    'Ver detalhes',
    'Recolher',
    #$E2#$9C#$93' Marcar como lida',
    'Pular por agora '#$E2#$80#$94 +
      ' volto a lembrar ao abrir o widget de novo',
    'Negrito',
    'It'#$C3#$A1'lico',
    'Riscado',
    'Lista',
    'Lista numerada',
    'Cita'#$C3#$A7#$C3#$A3'o',
    'C'#$C3#$B3'digo',
    'Link',
    'Anexar arquivo',
    'https://'#$E2#$80#$A6,
    'Aplicar',
    'Remover link');
  TK_EN: array[0..140] of TBFRaw = (
    'Support',
    'My tickets',
    'New ticket',
    'No tickets yet',
    'Open your first ticket to get started.',
    'Open ticket',
    'Back',
    'Close',
    'Send',
    'Create ticket',
    'Attach',
    'Attach or drag files here',
    'Drop files to attach',
    'Uploading'#$E2#$80#$A6,
    'What is it about?',
    'Priority',
    'Describe the issue',
    'Title',
    'Short summary of the issue',
    'Description (optional)',
    'Details, steps to reproduce, context...',
    'Destination department',
    'Which department to send the request to '#$E2#$80#$94 +
      ' not your own.',
    'No preference',
    'Low',
    'Medium',
    'High',
    'Critical',
    'Question',
    'Bug',
    'Request',
    'Incident',
    'Open',
    'In triage',
    'In progress',
    'Waiting on you',
    'Resolved',
    'Closed',
    'Cancelled',
    'Write your message...',
    'No messages yet.',
    'You',
    'Support team',
    'Loading...',
    'Something went wrong. Try again.',
    'Failed to load.',
    'Chat with us',
    'Agents available now.',
    'Agents are busy',
    'Everyone is helping other people. Join the queue a' +
      'nd you will be served as soon as possible.',
    '{n} in the queue now',
    'We are offline right now',
    'Leave us a message and we will get back to you as ' +
      'soon as possible.',
    'Chat now',
    'Join the queue',
    'Leave a message',
    'I would rather open a ticket',
    'Ongoing conversation',
    'Back to conversation',
    'New conversation',
    'Continue conversation',
    'Hi! Tell us how we can help '#$E2#$80#$94 +
      ' an agent will reply right here.',
    'Write a message'#$E2#$80#$A6,
    'Protocol',
    'In queue',
    'In queue '#$E2#$80#$94' position {n}',
    'Being served',
    'Being served by {name}',
    'Waiting on you',
    'Closed',
    'End',
    'End this conversation?',
    'Cancel',
    'This conversation has ended.',
    'Continue conversation',
    'Sending'#$E2#$80#$A6,
    'Not sent.',
    'Try again',
    'Discard',
    'Reconnecting'#$E2#$80#$A6,
    'No real-time connection. Reopen the widget to try ' + 'again.',
    'Our agents became unavailable. Leave your message ' +
      'here and we will get back to you as soon as possib' + 'le.',
    'Assistant',
    'Attach file',
    'Remove',
    'How was your experience?',
    'Want to leave a comment? (optional)',
    'Send rating',
    'Thanks for your feedback!',
    '{n} of 5',
    'We couldn''t verify your identity. Reload the page;' +
      ' if it keeps happening, contact the system''s suppo' + 'rt.',
    'With the virtual assistant',
    'With {name}, virtual assistant',
    'You are chatting with a virtual assistant.',
    'Talk to a person',
    'Request sent: a person will take over the conversa' + 'tion.',
    'We could not reach a person right now. Please try ' + 'again.',
    'I want to talk to a human agent.',
    'Hi! I am the virtual assistant and I answer right ' +
      'away. If you prefer, ask for a person at any time.',
    'Hi! I am {name}, the virtual assistant, and I answ' +
      'er right away. If you prefer, ask for a person at ' +
      'any time.',
    'Our virtual assistant answers right away, 24/7. Yo' +
      'u can ask for a person whenever you want.',
    'Sending rating'#$E2#$80#$A6,
    'Try again',
    'Your rating was not sent: the server took too long' +
      ' to respond. Check your connection and try again.',
    'Could not reach the server. Check your internet co' +
      'nnection and try again.',
    'We could not send your rating right now. Please tr' +
      'y again.',
    'Your ticket is still in progress. You will be able' +
      ' to rate the service once it is resolved.',
    'Your request continues in ticket {n}. You will get' +
      ' the answer here and by email.',
    'View ticket',
    'Chat conversation',
    'with {name}',
    'ongoing',
    '1 message',
    '{n} messages',
    'No messages in this conversation.',
    'Could not load the chat conversation.',
    'Ticket updates',
    'If the problem comes back, reply here '#$E2#$80#$94 +
      ' the ticket will be reopened (until {date}).',
    'If the problem comes back, reply here '#$E2#$80#$94 +
      ' the ticket will be reopened.',
    'This ticket has been closed. If you need to, start' +
      ' a new conversation or ticket '#$E2#$80#$94 +
      ' it will be linked to this one.',
    'Continuation of {n}',
    'What'#$E2#$80#$99's new for you',
    'Before you continue '#$E2#$80#$94' see what changed',
    '1 update waiting for you. Mark it as read to conti' + 'nue.',
    '{n} updates waiting. Mark each one as read or skip' +
      ' for now.',
    'See details',
    'Collapse',
    #$E2#$9C#$93' Mark as read',
    'Skip for now '#$E2#$80#$94' I'#$E2#$80#$99 +
      'll remind you next time you open the widget',
    'Bold',
    'Italic',
    'Strikethrough',
    'Bulleted list',
    'Numbered list',
    'Quote',
    'Code',
    'Link',
    'Attach file',
    'https://'#$E2#$80#$A6,
    'Apply',
    'Remove link');
  TK_ES: array[0..140] of TBFRaw = (
    'Soporte',
    'Mis tickets',
    'Nuevo ticket',
    'A'#$C3#$BA'n no hay tickets',
    'Abre tu primer ticket para empezar.',
    'Abrir ticket',
    'Volver',
    'Cerrar',
    'Enviar',
    'Crear ticket',
    'Adjuntar',
    'Adjuntar o arrastra archivos aqu'#$C3#$AD,
    'Suelta los archivos para adjuntar',
    'Subiendo'#$E2#$80#$A6,
    #$C2#$BF'Sobre qu'#$C3#$A9' es?',
    'Prioridad',
    'Describe el problema',
    'T'#$C3#$AD'tulo',
    'Resumen corto del problema',
    'Descripci'#$C3#$B3'n (opcional)',
    'Detalles, pasos para reproducir, contexto...',
    'Departamento de destino',
    'A qu'#$C3#$A9' departamento enviar la solicitud '#$E2#$80 +
      #$94' no el tuyo.',
    'Sin preferencia',
    'Baja',
    'Media',
    'Alta',
    'Cr'#$C3#$AD'tica',
    'Consulta',
    'Error',
    'Solicitud',
    'Incidente',
    'Abierto',
    'En triaje',
    'En curso',
    'Esperando tu respuesta',
    'Resuelto',
    'Cerrado',
    'Cancelado',
    'Escribe tu mensaje...',
    'A'#$C3#$BA'n no hay mensajes.',
    'T'#$C3#$BA,
    'Equipo de soporte',
    'Cargando...',
    'Algo sali'#$C3#$B3' mal. Int'#$C3#$A9'ntalo de nuevo.',
    'No se pudo cargar.',
    'Habla con nosotros',
    'Agentes disponibles ahora.',
    'Agentes ocupados',
    'Todos est'#$C3#$A1 +
      'n atendiendo. Entra en la fila y te atenderemos lo' +
      ' antes posible.',
    '{n} en la fila ahora',
    'Estamos fuera de l'#$C3#$AD'nea',
    'D'#$C3#$A9 +
      'janos tu mensaje y te responderemos lo antes posib' + 'le.',
    'Chatear ahora',
    'Entrar en la fila',
    'Deja tu mensaje',
    'Prefiero abrir un ticket',
    'Conversaci'#$C3#$B3'n en curso',
    'Volver a la conversaci'#$C3#$B3'n',
    'Nueva conversaci'#$C3#$B3'n',
    'Continuar atenci'#$C3#$B3'n',
    #$C2#$A1'Hola! Cu'#$C3#$A9'ntanos c'#$C3#$B3 +
      'mo podemos ayudarte '#$E2#$80#$94' un agente responder'#$C3 +
      #$A1' aqu'#$C3#$AD'.',
    'Escribe un mensaje'#$E2#$80#$A6,
    'Protocolo',
    'En la fila',
    'En la fila '#$E2#$80#$94' posici'#$C3#$B3'n {n}',
    'En atenci'#$C3#$B3'n',
    'En atenci'#$C3#$B3'n con {name}',
    'Esperando tu respuesta',
    'Finalizada',
    'Finalizar',
    #$C2#$BF'Finalizar esta conversaci'#$C3#$B3'n?',
    'Cancelar',
    'Esta conversaci'#$C3#$B3'n ha finalizado.',
    'Continuar conversaci'#$C3#$B3'n',
    'Enviando'#$E2#$80#$A6,
    'No enviado.',
    'Reintentar',
    'Descartar',
    'Reconectando'#$E2#$80#$A6,
    'Sin conexi'#$C3#$B3 +
      'n en tiempo real. Vuelve a abrir el widget para in' +
      'tentarlo de nuevo.',
    'Nuestros agentes ya no est'#$C3#$A1 +
      'n disponibles. Deja tu mensaje aqu'#$C3#$AD +
      ' y te responderemos lo antes posible.',
    'Asistente',
    'Adjuntar archivo',
    'Quitar',
    #$C2#$BF'C'#$C3#$B3'mo fue la atenci'#$C3#$B3'n?',
    #$C2#$BF'Quieres dejar un comentario? (opcional)',
    'Enviar valoraci'#$C3#$B3'n',
    #$C2#$A1'Gracias por tu valoraci'#$C3#$B3'n!',
    '{n} de 5',
    'No pudimos verificar tu identidad. Recarga la p'#$C3#$A1 +
      'gina; si contin'#$C3#$BA +
      'a, contacta al soporte del sistema.',
    'Con el asistente virtual',
    'Con {name}, asistente virtual',
    'Est'#$C3#$A1's hablando con un asistente virtual.',
    'Hablar con un agente',
    'Solicitud enviada: un agente tomar'#$C3#$A1' la conversaci' +
      #$C3#$B3'n.',
    'No pudimos llamar a un agente ahora. Int'#$C3#$A9 +
      'ntalo de nuevo.',
    'Quiero hablar con un agente humano.',
    #$C2#$A1'Hola! Soy el asistente virtual y respondo al insta' +
      'nte. Si lo prefieres, pide un agente en cualquier ' +
      'momento.',
    #$C2#$A1'Hola! Soy {name}, el asistente virtual, y respondo' +
      ' al instante. Si lo prefieres, pide un agente en c' +
      'ualquier momento.',
    'Nuestro asistente virtual responde al instante, 24' +
      ' horas. Puedes pedir un agente cuando quieras.',
    'Enviando valoraci'#$C3#$B3'n'#$E2#$80#$A6,
    'Intentar de nuevo',
    'La valoraci'#$C3#$B3'n no se envi'#$C3#$B3 +
      ': el servidor tard'#$C3#$B3 +
      ' demasiado en responder. Revisa tu conexi'#$C3#$B3'n e int' +
      #$C3#$A9'ntalo de nuevo.',
    'Sin conexi'#$C3#$B3 +
      'n con el servidor. Revisa tu internet e int'#$C3#$A9 +
      'ntalo de nuevo.',
    'No pudimos enviar tu valoraci'#$C3#$B3'n ahora. Int'#$C3 +
      #$A9'ntalo de nuevo.',
    'Tu ticket sigue en curso. Podr'#$C3#$A1 +
      's valorar la atenci'#$C3#$B3'n cuando se resuelva.',
    'Tu atenci'#$C3#$B3'n contin'#$C3#$BA +
      'a en el ticket {n}. Recibir'#$C3#$A1's la respuesta aqu' +
      #$C3#$AD' y por correo electr'#$C3#$B3'nico.',
    'Ver ticket',
    'Conversaci'#$C3#$B3'n del chat',
    'con {name}',
    'en curso',
    '1 mensaje',
    '{n} mensajes',
    'No hay mensajes en esta conversaci'#$C3#$B3'n.',
    'No se pudo cargar la conversaci'#$C3#$B3'n del chat.',
    'Seguimiento del ticket',
    'Si el problema vuelve, responde aqu'#$C3#$AD +
      ': el ticket se reabrir'#$C3#$A1' (hasta el {date}).',
    'Si el problema vuelve, responde aqu'#$C3#$AD +
      ': el ticket se reabrir'#$C3#$A1'.',
    'Este ticket fue cerrado. Si lo necesitas, abre una' +
      ' nueva conversaci'#$C3#$B3'n o ticket: quedar'#$C3#$A1 +
      ' vinculado a este.',
    'Continuaci'#$C3#$B3'n de {n}',
    'Novedades para ti',
    'Antes de continuar '#$E2#$80#$94' mira lo que cambi'#$C3 +
      #$B3,
    '1 novedad esperando tu lectura. M'#$C3#$A1'rcala como le' +
      #$C3#$AD'da para continuar.',
    '{n} novedades esperando. Marca cada una como le'#$C3#$AD +
      'da u omite por ahora.',
    'Ver detalles',
    'Contraer',
    #$E2#$9C#$93' Marcar como le'#$C3#$AD'da',
    'Omitir por ahora '#$E2#$80#$94 +
      ' te lo recuerdo al abrir el widget de nuevo',
    'Negrita',
    'Cursiva',
    'Tachado',
    'Lista',
    'Lista numerada',
    'Cita',
    'C'#$C3#$B3'digo',
    'Enlace',
    'Adjuntar archivo',
    'https://'#$E2#$80#$A6,
    'Aplicar',
    'Quitar enlace');
{$ENDIF}
  RN_KEYS: array[0..12] of string = (
    'eyebrow',
    'ackEyebrow',
    'scrollHint',
    'ackButton',
    'ackSubmitting',
    'ackError',
    'dismissButton',
    'historyTitle',
    'currentLabel',
    'emptyHistory',
    'close',
    'expand',
    'collapse');
{$IFDEF BF_UNICODE}
  RN_PT_BR: array[0..12] of string = (
    'Novidades pra voc'#$00EA,
    'Ci'#$00EA'ncia exigida',
    'Role at'#$00E9' o fim para habilitar a confirma'#$00E7 +
      #$00E3'o',
    'Li e estou ciente das novas fun'#$00E7#$00F5'es e ajustes',
    'Registrando'#$2026,
    'N'#$00E3'o foi poss'#$00ED +
      'vel registrar. Verifique a conex'#$00E3'o e tente de novo.',
    'Entendi',
    'Novidades',
    'Vers'#$00E3'o atual',
    'Nenhuma novidade publicada ainda.',
    'Fechar',
    'Ver detalhes',
    'Recolher');
  RN_EN: array[0..12] of string = (
    'What''s new for you',
    'Acknowledgement required',
    'Scroll to the end to enable confirmation',
    'I have read and acknowledge the new features and c' + 'hanges',
    'Saving'#$2026,
    'Couldn''t save your confirmation. Check your connec' +
      'tion and try again.',
    'Got it',
    'What''s new',
    'Current version',
    'No release notes published yet.',
    'Close',
    'See details',
    'Collapse');
  RN_ES: array[0..12] of string = (
    'Novedades para ti',
    'Confirmaci'#$00F3'n requerida',
    'Despl'#$00E1 +
      'zate hasta el final para habilitar la confirmaci'#$00F3'n',
    'He le'#$00ED +
      'do y estoy al tanto de las nuevas funciones y ajus' + 'tes',
    'Registrando'#$2026,
    'No fue posible registrar. Verifica la conexi'#$00F3 +
      'n e int'#$00E9'ntalo de nuevo.',
    'Entendido',
    'Novedades',
    'Versi'#$00F3'n actual',
    'A'#$00FA'n no hay notas de versi'#$00F3'n publicadas.',
    'Cerrar',
    'Ver detalles',
    'Contraer');
{$ELSE}
  RN_PT_BR: array[0..12] of TBFRaw = (
    'Novidades pra voc'#$C3#$AA,
    'Ci'#$C3#$AA'ncia exigida',
    'Role at'#$C3#$A9' o fim para habilitar a confirma'#$C3#$A7 +
      #$C3#$A3'o',
    'Li e estou ciente das novas fun'#$C3#$A7#$C3#$B5 +
      'es e ajustes',
    'Registrando'#$E2#$80#$A6,
    'N'#$C3#$A3'o foi poss'#$C3#$AD +
      'vel registrar. Verifique a conex'#$C3#$A3 +
      'o e tente de novo.',
    'Entendi',
    'Novidades',
    'Vers'#$C3#$A3'o atual',
    'Nenhuma novidade publicada ainda.',
    'Fechar',
    'Ver detalhes',
    'Recolher');
  RN_EN: array[0..12] of TBFRaw = (
    'What''s new for you',
    'Acknowledgement required',
    'Scroll to the end to enable confirmation',
    'I have read and acknowledge the new features and c' + 'hanges',
    'Saving'#$E2#$80#$A6,
    'Couldn''t save your confirmation. Check your connec' +
      'tion and try again.',
    'Got it',
    'What''s new',
    'Current version',
    'No release notes published yet.',
    'Close',
    'See details',
    'Collapse');
  RN_ES: array[0..12] of TBFRaw = (
    'Novedades para ti',
    'Confirmaci'#$C3#$B3'n requerida',
    'Despl'#$C3#$A1 +
      'zate hasta el final para habilitar la confirmaci'#$C3#$B3 +
      'n',
    'He le'#$C3#$AD +
      'do y estoy al tanto de las nuevas funciones y ajus' + 'tes',
    'Registrando'#$E2#$80#$A6,
    'No fue posible registrar. Verifica la conexi'#$C3#$B3 +
      'n e int'#$C3#$A9'ntalo de nuevo.',
    'Entendido',
    'Novedades',
    'Versi'#$C3#$B3'n actual',
    'A'#$C3#$BA'n no hay notas de versi'#$C3#$B3'n publicadas.',
    'Cerrar',
    'Ver detalles',
    'Contraer');
{$ENDIF}

function BFLocaleIndex(const Locale: string): Integer;
var
  I: Integer;
begin
  Result := 0;
  for I := 0 to BF_LOCALE_COUNT - 1 do
    if BF_LOCALES[I] = Locale then
    begin
      Result := I;
      Exit;
    end;
end;

function IndexOfKey(const Keys: array of string; const Key: string): Integer;
var
  I: Integer;
begin
  for I := 0 to High(Keys) do
    if Keys[I] = Key then
    begin
      Result := I;
      Exit;
    end;
  Result := -1;
end;

{$IFDEF BF_UNICODE}
function Pick(const V: string): string;
begin
  Result := V;
end;
{$ELSE}
function Pick(const V: TBFRaw): string;
begin
  Result := BFFromUtf8(V);
end;
{$ENDIF}

function BFT(const Locale, Key: string): string;
var
  I: Integer;
begin
  I := IndexOfKey(TK_KEYS, Key);
  if I < 0 then
  begin
    Result := Key;
    Exit;
  end;
  case BFLocaleIndex(Locale) of
    1: Result := Pick(TK_EN[I]);
    2: Result := Pick(TK_ES[I]);
  else
    Result := '';
  end;
  if Result = '' then
    Result := Pick(TK_PT_BR[I]);
end;

function BFRN(const Locale, Key: string): string;
var
  I: Integer;
begin
  I := IndexOfKey(RN_KEYS, Key);
  if I < 0 then
  begin
    Result := Key;
    Exit;
  end;
  case BFLocaleIndex(Locale) of
    1: Result := Pick(RN_EN[I]);
    2: Result := Pick(RN_ES[I]);
  else
    Result := '';
  end;
  if Result = '' then
    Result := Pick(RN_PT_BR[I]);
end;

function BFFill(const S, Name, Value: string): string;
begin
  Result := StringReplace(S, '{' + Name + '}', Value, [rfReplaceAll]);
end;

function BFTicketKeyCount: Integer;
begin
  Result := Length(TK_KEYS);
end;

function BFTicketKey(I: Integer): string;
begin
  Result := TK_KEYS[I];
end;

function BFReleaseNotesKeyCount: Integer;
begin
  Result := Length(RN_KEYS);
end;

function BFReleaseNotesKey(I: Integer): string;
begin
  Result := RN_KEYS[I];
end;

end.
