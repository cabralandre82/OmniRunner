import 'package:equatable/equatable.dart';

/// L05-29 — Uma linha do histórico de `.fit` do atleta.
///
/// Espelha `public.coaching_workout_export_log` com o join opcional de
/// `coaching_workout_templates(name)` e
/// `coaching_workout_assignments(scheduled_date)`. Ambos os joins podem
/// voltar `null` em três cenários:
///
/// 1. `assignment_id` é NULL na row (export de template avulso).
/// 2. RLS bloqueou o acesso ao template ou ao assignment (caso raro;
///    atleta normalmente lê seus próprios).
/// 3. Snapshot antigo antes do join estar disponível.
///
/// Em qualquer um dos casos, o campo derivado (`templateName`,
/// `scheduledDate`) vira null. A tela ainda consegue renderizar a row
/// usando só o `createdAt` e o `surface`.
class AthleteWorkoutExport extends Equatable {
  const AthleteWorkoutExport({
    required this.id,
    this.templateId,
    this.templateName,
    this.assignmentId,
    this.scheduledDate,
    required this.surface,
    required this.kind,
    this.deviceHint,
    this.bytes,
    this.errorCode,
    required this.createdAt,
  });

  final String id;
  final String? templateId;
  final String? templateName;
  final String? assignmentId;
  final DateTime? scheduledDate;

  /// 'app' (atleta no Flutter) ou 'portal' (coach baixando pelo web).
  final String surface;

  /// 'generated' | 'shared' | 'delivered' | 'failed'.
  ///
  /// Qualquer valor fora desse conjunto é mantido como-veio e tratado
  /// como 'other' na UI (defensivo contra futuros kinds adicionados no
  /// servidor antes do client ser atualizado).
  final String kind;

  /// 'garmin' | 'coros' | 'suunto' | 'polar' | 'apple_watch' |
  /// 'wear_os' | 'other' | null.
  ///
  /// `fromJson` coage valores inesperados para 'other' — assim a UI
  /// sempre consegue exibir alguma label mesmo que o servidor adicione
  /// vendors novos.
  final String? deviceHint;

  final int? bytes;

  /// Populado quando `kind='failed'`. Os códigos são strings curtas
  /// definidas pela Edge Function (e.g. 'not_found', 'encode_failed').
  final String? errorCode;

  final DateTime createdAt;

  static const _knownDeviceHints = <String>{
    'garmin',
    'coros',
    'suunto',
    'polar',
    'apple_watch',
    'wear_os',
    'other',
  };

  factory AthleteWorkoutExport.fromJson(Map<String, dynamic> json) {
    final rawCreatedAt = json['created_at'];
    DateTime created;
    if (rawCreatedAt is String) {
      created = DateTime.tryParse(rawCreatedAt)?.toLocal() ??
          DateTime.fromMillisecondsSinceEpoch(0);
    } else if (rawCreatedAt is DateTime) {
      created = rawCreatedAt.toLocal();
    } else {
      created = DateTime.fromMillisecondsSinceEpoch(0);
    }

    final rawScheduled = _readScalarFromJoin(
      json['coaching_workout_assignments'],
      'scheduled_date',
    );
    DateTime? scheduled;
    if (rawScheduled is String) {
      scheduled = DateTime.tryParse(rawScheduled);
    }

    final rawTemplateName = _readScalarFromJoin(
      json['coaching_workout_templates'],
      'name',
    );

    final rawDevice = json['device_hint'] as String?;
    final device = rawDevice == null
        ? null
        : _knownDeviceHints.contains(rawDevice)
            ? rawDevice
            : 'other';

    return AthleteWorkoutExport(
      id: json['id'] as String,
      templateId: json['template_id'] as String?,
      templateName: rawTemplateName is String ? rawTemplateName : null,
      assignmentId: json['assignment_id'] as String?,
      scheduledDate: scheduled,
      surface: (json['surface'] as String?) ?? 'app',
      kind: (json['kind'] as String?) ?? 'generated',
      deviceHint: device,
      bytes: (json['bytes'] as num?)?.toInt(),
      errorCode: json['error_code'] as String?,
      createdAt: created,
    );
  }

  /// Supabase devolve joins embedados ora como `Map<String, dynamic>`
  /// (to-one FK) ora como `List<Map<String, dynamic>>` (to-many).
  /// `coaching_workout_export_log` tem FKs singulares para template e
  /// assignment, mas o postgrest-dart às vezes embrulha em lista. Esse
  /// helper cobre os dois casos e retorna `null` se a row não existe
  /// (RLS bloqueou) ou a chave `key` está ausente.
  static Object? _readScalarFromJoin(Object? embedded, String key) {
    if (embedded == null) return null;
    if (embedded is Map) {
      return embedded[key];
    }
    if (embedded is List && embedded.isNotEmpty) {
      final first = embedded.first;
      if (first is Map) return first[key];
    }
    return null;
  }

  /// Label amigável do `kind` em pt-BR.
  String get kindLabel => switch (kind) {
        'generated' => 'Enviado',
        'shared' => 'Compartilhado',
        'delivered' => 'Entregue no relógio',
        'failed' => 'Falhou',
        _ => kind,
      };

  /// Label amigável do `device_hint` em pt-BR (marca do relógio).
  String? get deviceLabel => switch (deviceHint) {
        'garmin' => 'Garmin',
        'coros' => 'Coros',
        'suunto' => 'Suunto',
        'polar' => 'Polar',
        'apple_watch' => 'Apple Watch',
        'wear_os' => 'Wear OS',
        'other' => 'Outro relógio',
        _ => null,
      };

  String get surfaceLabel => switch (surface) {
        'app' => 'Pelo app',
        'portal' => 'Pelo coach',
        _ => surface,
      };

  bool get isFailure => kind == 'failed';

  /// True quando a row representa um push bem-sucedido (bytes gerados,
  /// ou confirmação do relógio). A UI usa isso pra decidir cor do card
  /// e se mostra CTA de "tentar novamente".
  bool get isSuccess => kind == 'generated' ||
      kind == 'shared' ||
      kind == 'delivered';

  @override
  List<Object?> get props => [
        id,
        templateId,
        templateName,
        assignmentId,
        scheduledDate,
        surface,
        kind,
        deviceHint,
        bytes,
        errorCode,
        createdAt,
      ];
}
