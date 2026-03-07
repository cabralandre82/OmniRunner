// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'drift_database.dart';

// ignore_for_file: type=lint
class $LocationPointsTable extends LocationPoints
    with TableInfo<$LocationPointsTable, LocationPoint> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $LocationPointsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _sessionIdMeta = const VerificationMeta(
    'sessionId',
  );
  @override
  late final GeneratedColumn<String> sessionId = GeneratedColumn<String>(
    'session_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _latMeta = const VerificationMeta('lat');
  @override
  late final GeneratedColumn<double> lat = GeneratedColumn<double>(
    'lat',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _lngMeta = const VerificationMeta('lng');
  @override
  late final GeneratedColumn<double> lng = GeneratedColumn<double>(
    'lng',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _altMeta = const VerificationMeta('alt');
  @override
  late final GeneratedColumn<double> alt = GeneratedColumn<double>(
    'alt',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _accuracyMeta = const VerificationMeta(
    'accuracy',
  );
  @override
  late final GeneratedColumn<double> accuracy = GeneratedColumn<double>(
    'accuracy',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _speedMeta = const VerificationMeta('speed');
  @override
  late final GeneratedColumn<double> speed = GeneratedColumn<double>(
    'speed',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _bearingMeta = const VerificationMeta(
    'bearing',
  );
  @override
  late final GeneratedColumn<double> bearing = GeneratedColumn<double>(
    'bearing',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _timestampMsMeta = const VerificationMeta(
    'timestampMs',
  );
  @override
  late final GeneratedColumn<int> timestampMs = GeneratedColumn<int>(
    'timestamp_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    sessionId,
    lat,
    lng,
    alt,
    accuracy,
    speed,
    bearing,
    timestampMs,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'location_points';
  @override
  VerificationContext validateIntegrity(
    Insertable<LocationPoint> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('session_id')) {
      context.handle(
        _sessionIdMeta,
        sessionId.isAcceptableOrUnknown(data['session_id']!, _sessionIdMeta),
      );
    } else if (isInserting) {
      context.missing(_sessionIdMeta);
    }
    if (data.containsKey('lat')) {
      context.handle(
        _latMeta,
        lat.isAcceptableOrUnknown(data['lat']!, _latMeta),
      );
    } else if (isInserting) {
      context.missing(_latMeta);
    }
    if (data.containsKey('lng')) {
      context.handle(
        _lngMeta,
        lng.isAcceptableOrUnknown(data['lng']!, _lngMeta),
      );
    } else if (isInserting) {
      context.missing(_lngMeta);
    }
    if (data.containsKey('alt')) {
      context.handle(
        _altMeta,
        alt.isAcceptableOrUnknown(data['alt']!, _altMeta),
      );
    }
    if (data.containsKey('accuracy')) {
      context.handle(
        _accuracyMeta,
        accuracy.isAcceptableOrUnknown(data['accuracy']!, _accuracyMeta),
      );
    }
    if (data.containsKey('speed')) {
      context.handle(
        _speedMeta,
        speed.isAcceptableOrUnknown(data['speed']!, _speedMeta),
      );
    }
    if (data.containsKey('bearing')) {
      context.handle(
        _bearingMeta,
        bearing.isAcceptableOrUnknown(data['bearing']!, _bearingMeta),
      );
    }
    if (data.containsKey('timestamp_ms')) {
      context.handle(
        _timestampMsMeta,
        timestampMs.isAcceptableOrUnknown(
          data['timestamp_ms']!,
          _timestampMsMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_timestampMsMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  LocationPoint map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return LocationPoint(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      sessionId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}session_id'],
      )!,
      lat: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}lat'],
      )!,
      lng: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}lng'],
      )!,
      alt: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}alt'],
      ),
      accuracy: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}accuracy'],
      ),
      speed: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}speed'],
      ),
      bearing: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}bearing'],
      ),
      timestampMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}timestamp_ms'],
      )!,
    );
  }

  @override
  $LocationPointsTable createAlias(String alias) {
    return $LocationPointsTable(attachedDatabase, alias);
  }
}

class LocationPoint extends DataClass implements Insertable<LocationPoint> {
  final int id;
  final String sessionId;
  final double lat;
  final double lng;
  final double? alt;
  final double? accuracy;
  final double? speed;
  final double? bearing;
  final int timestampMs;
  const LocationPoint({
    required this.id,
    required this.sessionId,
    required this.lat,
    required this.lng,
    this.alt,
    this.accuracy,
    this.speed,
    this.bearing,
    required this.timestampMs,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['session_id'] = Variable<String>(sessionId);
    map['lat'] = Variable<double>(lat);
    map['lng'] = Variable<double>(lng);
    if (!nullToAbsent || alt != null) {
      map['alt'] = Variable<double>(alt);
    }
    if (!nullToAbsent || accuracy != null) {
      map['accuracy'] = Variable<double>(accuracy);
    }
    if (!nullToAbsent || speed != null) {
      map['speed'] = Variable<double>(speed);
    }
    if (!nullToAbsent || bearing != null) {
      map['bearing'] = Variable<double>(bearing);
    }
    map['timestamp_ms'] = Variable<int>(timestampMs);
    return map;
  }

  LocationPointsCompanion toCompanion(bool nullToAbsent) {
    return LocationPointsCompanion(
      id: Value(id),
      sessionId: Value(sessionId),
      lat: Value(lat),
      lng: Value(lng),
      alt: alt == null && nullToAbsent ? const Value.absent() : Value(alt),
      accuracy: accuracy == null && nullToAbsent
          ? const Value.absent()
          : Value(accuracy),
      speed: speed == null && nullToAbsent
          ? const Value.absent()
          : Value(speed),
      bearing: bearing == null && nullToAbsent
          ? const Value.absent()
          : Value(bearing),
      timestampMs: Value(timestampMs),
    );
  }

  factory LocationPoint.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return LocationPoint(
      id: serializer.fromJson<int>(json['id']),
      sessionId: serializer.fromJson<String>(json['sessionId']),
      lat: serializer.fromJson<double>(json['lat']),
      lng: serializer.fromJson<double>(json['lng']),
      alt: serializer.fromJson<double?>(json['alt']),
      accuracy: serializer.fromJson<double?>(json['accuracy']),
      speed: serializer.fromJson<double?>(json['speed']),
      bearing: serializer.fromJson<double?>(json['bearing']),
      timestampMs: serializer.fromJson<int>(json['timestampMs']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'sessionId': serializer.toJson<String>(sessionId),
      'lat': serializer.toJson<double>(lat),
      'lng': serializer.toJson<double>(lng),
      'alt': serializer.toJson<double?>(alt),
      'accuracy': serializer.toJson<double?>(accuracy),
      'speed': serializer.toJson<double?>(speed),
      'bearing': serializer.toJson<double?>(bearing),
      'timestampMs': serializer.toJson<int>(timestampMs),
    };
  }

  LocationPoint copyWith({
    int? id,
    String? sessionId,
    double? lat,
    double? lng,
    Value<double?> alt = const Value.absent(),
    Value<double?> accuracy = const Value.absent(),
    Value<double?> speed = const Value.absent(),
    Value<double?> bearing = const Value.absent(),
    int? timestampMs,
  }) => LocationPoint(
    id: id ?? this.id,
    sessionId: sessionId ?? this.sessionId,
    lat: lat ?? this.lat,
    lng: lng ?? this.lng,
    alt: alt.present ? alt.value : this.alt,
    accuracy: accuracy.present ? accuracy.value : this.accuracy,
    speed: speed.present ? speed.value : this.speed,
    bearing: bearing.present ? bearing.value : this.bearing,
    timestampMs: timestampMs ?? this.timestampMs,
  );
  LocationPoint copyWithCompanion(LocationPointsCompanion data) {
    return LocationPoint(
      id: data.id.present ? data.id.value : this.id,
      sessionId: data.sessionId.present ? data.sessionId.value : this.sessionId,
      lat: data.lat.present ? data.lat.value : this.lat,
      lng: data.lng.present ? data.lng.value : this.lng,
      alt: data.alt.present ? data.alt.value : this.alt,
      accuracy: data.accuracy.present ? data.accuracy.value : this.accuracy,
      speed: data.speed.present ? data.speed.value : this.speed,
      bearing: data.bearing.present ? data.bearing.value : this.bearing,
      timestampMs: data.timestampMs.present
          ? data.timestampMs.value
          : this.timestampMs,
    );
  }

  @override
  String toString() {
    return (StringBuffer('LocationPoint(')
          ..write('id: $id, ')
          ..write('sessionId: $sessionId, ')
          ..write('lat: $lat, ')
          ..write('lng: $lng, ')
          ..write('alt: $alt, ')
          ..write('accuracy: $accuracy, ')
          ..write('speed: $speed, ')
          ..write('bearing: $bearing, ')
          ..write('timestampMs: $timestampMs')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    sessionId,
    lat,
    lng,
    alt,
    accuracy,
    speed,
    bearing,
    timestampMs,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is LocationPoint &&
          other.id == this.id &&
          other.sessionId == this.sessionId &&
          other.lat == this.lat &&
          other.lng == this.lng &&
          other.alt == this.alt &&
          other.accuracy == this.accuracy &&
          other.speed == this.speed &&
          other.bearing == this.bearing &&
          other.timestampMs == this.timestampMs);
}

class LocationPointsCompanion extends UpdateCompanion<LocationPoint> {
  final Value<int> id;
  final Value<String> sessionId;
  final Value<double> lat;
  final Value<double> lng;
  final Value<double?> alt;
  final Value<double?> accuracy;
  final Value<double?> speed;
  final Value<double?> bearing;
  final Value<int> timestampMs;
  const LocationPointsCompanion({
    this.id = const Value.absent(),
    this.sessionId = const Value.absent(),
    this.lat = const Value.absent(),
    this.lng = const Value.absent(),
    this.alt = const Value.absent(),
    this.accuracy = const Value.absent(),
    this.speed = const Value.absent(),
    this.bearing = const Value.absent(),
    this.timestampMs = const Value.absent(),
  });
  LocationPointsCompanion.insert({
    this.id = const Value.absent(),
    required String sessionId,
    required double lat,
    required double lng,
    this.alt = const Value.absent(),
    this.accuracy = const Value.absent(),
    this.speed = const Value.absent(),
    this.bearing = const Value.absent(),
    required int timestampMs,
  }) : sessionId = Value(sessionId),
       lat = Value(lat),
       lng = Value(lng),
       timestampMs = Value(timestampMs);
  static Insertable<LocationPoint> custom({
    Expression<int>? id,
    Expression<String>? sessionId,
    Expression<double>? lat,
    Expression<double>? lng,
    Expression<double>? alt,
    Expression<double>? accuracy,
    Expression<double>? speed,
    Expression<double>? bearing,
    Expression<int>? timestampMs,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (sessionId != null) 'session_id': sessionId,
      if (lat != null) 'lat': lat,
      if (lng != null) 'lng': lng,
      if (alt != null) 'alt': alt,
      if (accuracy != null) 'accuracy': accuracy,
      if (speed != null) 'speed': speed,
      if (bearing != null) 'bearing': bearing,
      if (timestampMs != null) 'timestamp_ms': timestampMs,
    });
  }

  LocationPointsCompanion copyWith({
    Value<int>? id,
    Value<String>? sessionId,
    Value<double>? lat,
    Value<double>? lng,
    Value<double?>? alt,
    Value<double?>? accuracy,
    Value<double?>? speed,
    Value<double?>? bearing,
    Value<int>? timestampMs,
  }) {
    return LocationPointsCompanion(
      id: id ?? this.id,
      sessionId: sessionId ?? this.sessionId,
      lat: lat ?? this.lat,
      lng: lng ?? this.lng,
      alt: alt ?? this.alt,
      accuracy: accuracy ?? this.accuracy,
      speed: speed ?? this.speed,
      bearing: bearing ?? this.bearing,
      timestampMs: timestampMs ?? this.timestampMs,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (sessionId.present) {
      map['session_id'] = Variable<String>(sessionId.value);
    }
    if (lat.present) {
      map['lat'] = Variable<double>(lat.value);
    }
    if (lng.present) {
      map['lng'] = Variable<double>(lng.value);
    }
    if (alt.present) {
      map['alt'] = Variable<double>(alt.value);
    }
    if (accuracy.present) {
      map['accuracy'] = Variable<double>(accuracy.value);
    }
    if (speed.present) {
      map['speed'] = Variable<double>(speed.value);
    }
    if (bearing.present) {
      map['bearing'] = Variable<double>(bearing.value);
    }
    if (timestampMs.present) {
      map['timestamp_ms'] = Variable<int>(timestampMs.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('LocationPointsCompanion(')
          ..write('id: $id, ')
          ..write('sessionId: $sessionId, ')
          ..write('lat: $lat, ')
          ..write('lng: $lng, ')
          ..write('alt: $alt, ')
          ..write('accuracy: $accuracy, ')
          ..write('speed: $speed, ')
          ..write('bearing: $bearing, ')
          ..write('timestampMs: $timestampMs')
          ..write(')'))
        .toString();
  }
}

class $WorkoutSessionsTable extends WorkoutSessions
    with TableInfo<$WorkoutSessionsTable, WorkoutSession> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $WorkoutSessionsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _sessionUuidMeta = const VerificationMeta(
    'sessionUuid',
  );
  @override
  late final GeneratedColumn<String> sessionUuid = GeneratedColumn<String>(
    'session_uuid',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways('UNIQUE'),
  );
  static const VerificationMeta _userIdMeta = const VerificationMeta('userId');
  @override
  late final GeneratedColumn<String> userId = GeneratedColumn<String>(
    'user_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<int> status = GeneratedColumn<int>(
    'status',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _startTimeMsMeta = const VerificationMeta(
    'startTimeMs',
  );
  @override
  late final GeneratedColumn<int> startTimeMs = GeneratedColumn<int>(
    'start_time_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _endTimeMsMeta = const VerificationMeta(
    'endTimeMs',
  );
  @override
  late final GeneratedColumn<int> endTimeMs = GeneratedColumn<int>(
    'end_time_ms',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _totalDistanceMMeta = const VerificationMeta(
    'totalDistanceM',
  );
  @override
  late final GeneratedColumn<double> totalDistanceM = GeneratedColumn<double>(
    'total_distance_m',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _movingMsMeta = const VerificationMeta(
    'movingMs',
  );
  @override
  late final GeneratedColumn<int> movingMs = GeneratedColumn<int>(
    'moving_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _isVerifiedMeta = const VerificationMeta(
    'isVerified',
  );
  @override
  late final GeneratedColumn<bool> isVerified = GeneratedColumn<bool>(
    'is_verified',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_verified" IN (0, 1))',
    ),
  );
  static const VerificationMeta _isSyncedMeta = const VerificationMeta(
    'isSynced',
  );
  @override
  late final GeneratedColumn<bool> isSynced = GeneratedColumn<bool>(
    'is_synced',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_synced" IN (0, 1))',
    ),
  );
  static const VerificationMeta _ghostSessionIdMeta = const VerificationMeta(
    'ghostSessionId',
  );
  @override
  late final GeneratedColumn<String> ghostSessionId = GeneratedColumn<String>(
    'ghost_session_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  late final GeneratedColumnWithTypeConverter<List<String>, String>
  integrityFlags = GeneratedColumn<String>(
    'integrity_flags',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('[]'),
  ).withConverter<List<String>>($WorkoutSessionsTable.$converterintegrityFlags);
  static const VerificationMeta _avgBpmMeta = const VerificationMeta('avgBpm');
  @override
  late final GeneratedColumn<int> avgBpm = GeneratedColumn<int>(
    'avg_bpm',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _maxBpmMeta = const VerificationMeta('maxBpm');
  @override
  late final GeneratedColumn<int> maxBpm = GeneratedColumn<int>(
    'max_bpm',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _avgCadenceSpmMeta = const VerificationMeta(
    'avgCadenceSpm',
  );
  @override
  late final GeneratedColumn<double> avgCadenceSpm = GeneratedColumn<double>(
    'avg_cadence_spm',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _sourceMeta = const VerificationMeta('source');
  @override
  late final GeneratedColumn<String> source = GeneratedColumn<String>(
    'source',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('app'),
  );
  static const VerificationMeta _deviceNameMeta = const VerificationMeta(
    'deviceName',
  );
  @override
  late final GeneratedColumn<String> deviceName = GeneratedColumn<String>(
    'device_name',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    sessionUuid,
    userId,
    status,
    startTimeMs,
    endTimeMs,
    totalDistanceM,
    movingMs,
    isVerified,
    isSynced,
    ghostSessionId,
    integrityFlags,
    avgBpm,
    maxBpm,
    avgCadenceSpm,
    source,
    deviceName,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'workout_sessions';
  @override
  VerificationContext validateIntegrity(
    Insertable<WorkoutSession> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('session_uuid')) {
      context.handle(
        _sessionUuidMeta,
        sessionUuid.isAcceptableOrUnknown(
          data['session_uuid']!,
          _sessionUuidMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_sessionUuidMeta);
    }
    if (data.containsKey('user_id')) {
      context.handle(
        _userIdMeta,
        userId.isAcceptableOrUnknown(data['user_id']!, _userIdMeta),
      );
    }
    if (data.containsKey('status')) {
      context.handle(
        _statusMeta,
        status.isAcceptableOrUnknown(data['status']!, _statusMeta),
      );
    } else if (isInserting) {
      context.missing(_statusMeta);
    }
    if (data.containsKey('start_time_ms')) {
      context.handle(
        _startTimeMsMeta,
        startTimeMs.isAcceptableOrUnknown(
          data['start_time_ms']!,
          _startTimeMsMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_startTimeMsMeta);
    }
    if (data.containsKey('end_time_ms')) {
      context.handle(
        _endTimeMsMeta,
        endTimeMs.isAcceptableOrUnknown(data['end_time_ms']!, _endTimeMsMeta),
      );
    }
    if (data.containsKey('total_distance_m')) {
      context.handle(
        _totalDistanceMMeta,
        totalDistanceM.isAcceptableOrUnknown(
          data['total_distance_m']!,
          _totalDistanceMMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_totalDistanceMMeta);
    }
    if (data.containsKey('moving_ms')) {
      context.handle(
        _movingMsMeta,
        movingMs.isAcceptableOrUnknown(data['moving_ms']!, _movingMsMeta),
      );
    } else if (isInserting) {
      context.missing(_movingMsMeta);
    }
    if (data.containsKey('is_verified')) {
      context.handle(
        _isVerifiedMeta,
        isVerified.isAcceptableOrUnknown(data['is_verified']!, _isVerifiedMeta),
      );
    } else if (isInserting) {
      context.missing(_isVerifiedMeta);
    }
    if (data.containsKey('is_synced')) {
      context.handle(
        _isSyncedMeta,
        isSynced.isAcceptableOrUnknown(data['is_synced']!, _isSyncedMeta),
      );
    } else if (isInserting) {
      context.missing(_isSyncedMeta);
    }
    if (data.containsKey('ghost_session_id')) {
      context.handle(
        _ghostSessionIdMeta,
        ghostSessionId.isAcceptableOrUnknown(
          data['ghost_session_id']!,
          _ghostSessionIdMeta,
        ),
      );
    }
    if (data.containsKey('avg_bpm')) {
      context.handle(
        _avgBpmMeta,
        avgBpm.isAcceptableOrUnknown(data['avg_bpm']!, _avgBpmMeta),
      );
    }
    if (data.containsKey('max_bpm')) {
      context.handle(
        _maxBpmMeta,
        maxBpm.isAcceptableOrUnknown(data['max_bpm']!, _maxBpmMeta),
      );
    }
    if (data.containsKey('avg_cadence_spm')) {
      context.handle(
        _avgCadenceSpmMeta,
        avgCadenceSpm.isAcceptableOrUnknown(
          data['avg_cadence_spm']!,
          _avgCadenceSpmMeta,
        ),
      );
    }
    if (data.containsKey('source')) {
      context.handle(
        _sourceMeta,
        source.isAcceptableOrUnknown(data['source']!, _sourceMeta),
      );
    }
    if (data.containsKey('device_name')) {
      context.handle(
        _deviceNameMeta,
        deviceName.isAcceptableOrUnknown(data['device_name']!, _deviceNameMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  WorkoutSession map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return WorkoutSession(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      sessionUuid: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}session_uuid'],
      )!,
      userId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}user_id'],
      ),
      status: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}status'],
      )!,
      startTimeMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}start_time_ms'],
      )!,
      endTimeMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}end_time_ms'],
      ),
      totalDistanceM: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}total_distance_m'],
      )!,
      movingMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}moving_ms'],
      )!,
      isVerified: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_verified'],
      )!,
      isSynced: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_synced'],
      )!,
      ghostSessionId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}ghost_session_id'],
      ),
      integrityFlags: $WorkoutSessionsTable.$converterintegrityFlags.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}integrity_flags'],
        )!,
      ),
      avgBpm: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}avg_bpm'],
      ),
      maxBpm: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}max_bpm'],
      ),
      avgCadenceSpm: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}avg_cadence_spm'],
      ),
      source: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}source'],
      )!,
      deviceName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}device_name'],
      ),
    );
  }

  @override
  $WorkoutSessionsTable createAlias(String alias) {
    return $WorkoutSessionsTable(attachedDatabase, alias);
  }

  static TypeConverter<List<String>, String> $converterintegrityFlags =
      const StringListConverter();
}

class WorkoutSession extends DataClass implements Insertable<WorkoutSession> {
  final int id;
  final String sessionUuid;
  final String? userId;
  final int status;
  final int startTimeMs;
  final int? endTimeMs;
  final double totalDistanceM;
  final int movingMs;
  final bool isVerified;
  final bool isSynced;
  final String? ghostSessionId;
  final List<String> integrityFlags;
  final int? avgBpm;
  final int? maxBpm;
  final double? avgCadenceSpm;
  final String source;
  final String? deviceName;
  const WorkoutSession({
    required this.id,
    required this.sessionUuid,
    this.userId,
    required this.status,
    required this.startTimeMs,
    this.endTimeMs,
    required this.totalDistanceM,
    required this.movingMs,
    required this.isVerified,
    required this.isSynced,
    this.ghostSessionId,
    required this.integrityFlags,
    this.avgBpm,
    this.maxBpm,
    this.avgCadenceSpm,
    required this.source,
    this.deviceName,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['session_uuid'] = Variable<String>(sessionUuid);
    if (!nullToAbsent || userId != null) {
      map['user_id'] = Variable<String>(userId);
    }
    map['status'] = Variable<int>(status);
    map['start_time_ms'] = Variable<int>(startTimeMs);
    if (!nullToAbsent || endTimeMs != null) {
      map['end_time_ms'] = Variable<int>(endTimeMs);
    }
    map['total_distance_m'] = Variable<double>(totalDistanceM);
    map['moving_ms'] = Variable<int>(movingMs);
    map['is_verified'] = Variable<bool>(isVerified);
    map['is_synced'] = Variable<bool>(isSynced);
    if (!nullToAbsent || ghostSessionId != null) {
      map['ghost_session_id'] = Variable<String>(ghostSessionId);
    }
    {
      map['integrity_flags'] = Variable<String>(
        $WorkoutSessionsTable.$converterintegrityFlags.toSql(integrityFlags),
      );
    }
    if (!nullToAbsent || avgBpm != null) {
      map['avg_bpm'] = Variable<int>(avgBpm);
    }
    if (!nullToAbsent || maxBpm != null) {
      map['max_bpm'] = Variable<int>(maxBpm);
    }
    if (!nullToAbsent || avgCadenceSpm != null) {
      map['avg_cadence_spm'] = Variable<double>(avgCadenceSpm);
    }
    map['source'] = Variable<String>(source);
    if (!nullToAbsent || deviceName != null) {
      map['device_name'] = Variable<String>(deviceName);
    }
    return map;
  }

  WorkoutSessionsCompanion toCompanion(bool nullToAbsent) {
    return WorkoutSessionsCompanion(
      id: Value(id),
      sessionUuid: Value(sessionUuid),
      userId: userId == null && nullToAbsent
          ? const Value.absent()
          : Value(userId),
      status: Value(status),
      startTimeMs: Value(startTimeMs),
      endTimeMs: endTimeMs == null && nullToAbsent
          ? const Value.absent()
          : Value(endTimeMs),
      totalDistanceM: Value(totalDistanceM),
      movingMs: Value(movingMs),
      isVerified: Value(isVerified),
      isSynced: Value(isSynced),
      ghostSessionId: ghostSessionId == null && nullToAbsent
          ? const Value.absent()
          : Value(ghostSessionId),
      integrityFlags: Value(integrityFlags),
      avgBpm: avgBpm == null && nullToAbsent
          ? const Value.absent()
          : Value(avgBpm),
      maxBpm: maxBpm == null && nullToAbsent
          ? const Value.absent()
          : Value(maxBpm),
      avgCadenceSpm: avgCadenceSpm == null && nullToAbsent
          ? const Value.absent()
          : Value(avgCadenceSpm),
      source: Value(source),
      deviceName: deviceName == null && nullToAbsent
          ? const Value.absent()
          : Value(deviceName),
    );
  }

  factory WorkoutSession.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return WorkoutSession(
      id: serializer.fromJson<int>(json['id']),
      sessionUuid: serializer.fromJson<String>(json['sessionUuid']),
      userId: serializer.fromJson<String?>(json['userId']),
      status: serializer.fromJson<int>(json['status']),
      startTimeMs: serializer.fromJson<int>(json['startTimeMs']),
      endTimeMs: serializer.fromJson<int?>(json['endTimeMs']),
      totalDistanceM: serializer.fromJson<double>(json['totalDistanceM']),
      movingMs: serializer.fromJson<int>(json['movingMs']),
      isVerified: serializer.fromJson<bool>(json['isVerified']),
      isSynced: serializer.fromJson<bool>(json['isSynced']),
      ghostSessionId: serializer.fromJson<String?>(json['ghostSessionId']),
      integrityFlags: serializer.fromJson<List<String>>(json['integrityFlags']),
      avgBpm: serializer.fromJson<int?>(json['avgBpm']),
      maxBpm: serializer.fromJson<int?>(json['maxBpm']),
      avgCadenceSpm: serializer.fromJson<double?>(json['avgCadenceSpm']),
      source: serializer.fromJson<String>(json['source']),
      deviceName: serializer.fromJson<String?>(json['deviceName']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'sessionUuid': serializer.toJson<String>(sessionUuid),
      'userId': serializer.toJson<String?>(userId),
      'status': serializer.toJson<int>(status),
      'startTimeMs': serializer.toJson<int>(startTimeMs),
      'endTimeMs': serializer.toJson<int?>(endTimeMs),
      'totalDistanceM': serializer.toJson<double>(totalDistanceM),
      'movingMs': serializer.toJson<int>(movingMs),
      'isVerified': serializer.toJson<bool>(isVerified),
      'isSynced': serializer.toJson<bool>(isSynced),
      'ghostSessionId': serializer.toJson<String?>(ghostSessionId),
      'integrityFlags': serializer.toJson<List<String>>(integrityFlags),
      'avgBpm': serializer.toJson<int?>(avgBpm),
      'maxBpm': serializer.toJson<int?>(maxBpm),
      'avgCadenceSpm': serializer.toJson<double?>(avgCadenceSpm),
      'source': serializer.toJson<String>(source),
      'deviceName': serializer.toJson<String?>(deviceName),
    };
  }

  WorkoutSession copyWith({
    int? id,
    String? sessionUuid,
    Value<String?> userId = const Value.absent(),
    int? status,
    int? startTimeMs,
    Value<int?> endTimeMs = const Value.absent(),
    double? totalDistanceM,
    int? movingMs,
    bool? isVerified,
    bool? isSynced,
    Value<String?> ghostSessionId = const Value.absent(),
    List<String>? integrityFlags,
    Value<int?> avgBpm = const Value.absent(),
    Value<int?> maxBpm = const Value.absent(),
    Value<double?> avgCadenceSpm = const Value.absent(),
    String? source,
    Value<String?> deviceName = const Value.absent(),
  }) => WorkoutSession(
    id: id ?? this.id,
    sessionUuid: sessionUuid ?? this.sessionUuid,
    userId: userId.present ? userId.value : this.userId,
    status: status ?? this.status,
    startTimeMs: startTimeMs ?? this.startTimeMs,
    endTimeMs: endTimeMs.present ? endTimeMs.value : this.endTimeMs,
    totalDistanceM: totalDistanceM ?? this.totalDistanceM,
    movingMs: movingMs ?? this.movingMs,
    isVerified: isVerified ?? this.isVerified,
    isSynced: isSynced ?? this.isSynced,
    ghostSessionId: ghostSessionId.present
        ? ghostSessionId.value
        : this.ghostSessionId,
    integrityFlags: integrityFlags ?? this.integrityFlags,
    avgBpm: avgBpm.present ? avgBpm.value : this.avgBpm,
    maxBpm: maxBpm.present ? maxBpm.value : this.maxBpm,
    avgCadenceSpm: avgCadenceSpm.present
        ? avgCadenceSpm.value
        : this.avgCadenceSpm,
    source: source ?? this.source,
    deviceName: deviceName.present ? deviceName.value : this.deviceName,
  );
  WorkoutSession copyWithCompanion(WorkoutSessionsCompanion data) {
    return WorkoutSession(
      id: data.id.present ? data.id.value : this.id,
      sessionUuid: data.sessionUuid.present
          ? data.sessionUuid.value
          : this.sessionUuid,
      userId: data.userId.present ? data.userId.value : this.userId,
      status: data.status.present ? data.status.value : this.status,
      startTimeMs: data.startTimeMs.present
          ? data.startTimeMs.value
          : this.startTimeMs,
      endTimeMs: data.endTimeMs.present ? data.endTimeMs.value : this.endTimeMs,
      totalDistanceM: data.totalDistanceM.present
          ? data.totalDistanceM.value
          : this.totalDistanceM,
      movingMs: data.movingMs.present ? data.movingMs.value : this.movingMs,
      isVerified: data.isVerified.present
          ? data.isVerified.value
          : this.isVerified,
      isSynced: data.isSynced.present ? data.isSynced.value : this.isSynced,
      ghostSessionId: data.ghostSessionId.present
          ? data.ghostSessionId.value
          : this.ghostSessionId,
      integrityFlags: data.integrityFlags.present
          ? data.integrityFlags.value
          : this.integrityFlags,
      avgBpm: data.avgBpm.present ? data.avgBpm.value : this.avgBpm,
      maxBpm: data.maxBpm.present ? data.maxBpm.value : this.maxBpm,
      avgCadenceSpm: data.avgCadenceSpm.present
          ? data.avgCadenceSpm.value
          : this.avgCadenceSpm,
      source: data.source.present ? data.source.value : this.source,
      deviceName: data.deviceName.present
          ? data.deviceName.value
          : this.deviceName,
    );
  }

  @override
  String toString() {
    return (StringBuffer('WorkoutSession(')
          ..write('id: $id, ')
          ..write('sessionUuid: $sessionUuid, ')
          ..write('userId: $userId, ')
          ..write('status: $status, ')
          ..write('startTimeMs: $startTimeMs, ')
          ..write('endTimeMs: $endTimeMs, ')
          ..write('totalDistanceM: $totalDistanceM, ')
          ..write('movingMs: $movingMs, ')
          ..write('isVerified: $isVerified, ')
          ..write('isSynced: $isSynced, ')
          ..write('ghostSessionId: $ghostSessionId, ')
          ..write('integrityFlags: $integrityFlags, ')
          ..write('avgBpm: $avgBpm, ')
          ..write('maxBpm: $maxBpm, ')
          ..write('avgCadenceSpm: $avgCadenceSpm, ')
          ..write('source: $source, ')
          ..write('deviceName: $deviceName')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    sessionUuid,
    userId,
    status,
    startTimeMs,
    endTimeMs,
    totalDistanceM,
    movingMs,
    isVerified,
    isSynced,
    ghostSessionId,
    integrityFlags,
    avgBpm,
    maxBpm,
    avgCadenceSpm,
    source,
    deviceName,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is WorkoutSession &&
          other.id == this.id &&
          other.sessionUuid == this.sessionUuid &&
          other.userId == this.userId &&
          other.status == this.status &&
          other.startTimeMs == this.startTimeMs &&
          other.endTimeMs == this.endTimeMs &&
          other.totalDistanceM == this.totalDistanceM &&
          other.movingMs == this.movingMs &&
          other.isVerified == this.isVerified &&
          other.isSynced == this.isSynced &&
          other.ghostSessionId == this.ghostSessionId &&
          other.integrityFlags == this.integrityFlags &&
          other.avgBpm == this.avgBpm &&
          other.maxBpm == this.maxBpm &&
          other.avgCadenceSpm == this.avgCadenceSpm &&
          other.source == this.source &&
          other.deviceName == this.deviceName);
}

class WorkoutSessionsCompanion extends UpdateCompanion<WorkoutSession> {
  final Value<int> id;
  final Value<String> sessionUuid;
  final Value<String?> userId;
  final Value<int> status;
  final Value<int> startTimeMs;
  final Value<int?> endTimeMs;
  final Value<double> totalDistanceM;
  final Value<int> movingMs;
  final Value<bool> isVerified;
  final Value<bool> isSynced;
  final Value<String?> ghostSessionId;
  final Value<List<String>> integrityFlags;
  final Value<int?> avgBpm;
  final Value<int?> maxBpm;
  final Value<double?> avgCadenceSpm;
  final Value<String> source;
  final Value<String?> deviceName;
  const WorkoutSessionsCompanion({
    this.id = const Value.absent(),
    this.sessionUuid = const Value.absent(),
    this.userId = const Value.absent(),
    this.status = const Value.absent(),
    this.startTimeMs = const Value.absent(),
    this.endTimeMs = const Value.absent(),
    this.totalDistanceM = const Value.absent(),
    this.movingMs = const Value.absent(),
    this.isVerified = const Value.absent(),
    this.isSynced = const Value.absent(),
    this.ghostSessionId = const Value.absent(),
    this.integrityFlags = const Value.absent(),
    this.avgBpm = const Value.absent(),
    this.maxBpm = const Value.absent(),
    this.avgCadenceSpm = const Value.absent(),
    this.source = const Value.absent(),
    this.deviceName = const Value.absent(),
  });
  WorkoutSessionsCompanion.insert({
    this.id = const Value.absent(),
    required String sessionUuid,
    this.userId = const Value.absent(),
    required int status,
    required int startTimeMs,
    this.endTimeMs = const Value.absent(),
    required double totalDistanceM,
    required int movingMs,
    required bool isVerified,
    required bool isSynced,
    this.ghostSessionId = const Value.absent(),
    this.integrityFlags = const Value.absent(),
    this.avgBpm = const Value.absent(),
    this.maxBpm = const Value.absent(),
    this.avgCadenceSpm = const Value.absent(),
    this.source = const Value.absent(),
    this.deviceName = const Value.absent(),
  }) : sessionUuid = Value(sessionUuid),
       status = Value(status),
       startTimeMs = Value(startTimeMs),
       totalDistanceM = Value(totalDistanceM),
       movingMs = Value(movingMs),
       isVerified = Value(isVerified),
       isSynced = Value(isSynced);
  static Insertable<WorkoutSession> custom({
    Expression<int>? id,
    Expression<String>? sessionUuid,
    Expression<String>? userId,
    Expression<int>? status,
    Expression<int>? startTimeMs,
    Expression<int>? endTimeMs,
    Expression<double>? totalDistanceM,
    Expression<int>? movingMs,
    Expression<bool>? isVerified,
    Expression<bool>? isSynced,
    Expression<String>? ghostSessionId,
    Expression<String>? integrityFlags,
    Expression<int>? avgBpm,
    Expression<int>? maxBpm,
    Expression<double>? avgCadenceSpm,
    Expression<String>? source,
    Expression<String>? deviceName,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (sessionUuid != null) 'session_uuid': sessionUuid,
      if (userId != null) 'user_id': userId,
      if (status != null) 'status': status,
      if (startTimeMs != null) 'start_time_ms': startTimeMs,
      if (endTimeMs != null) 'end_time_ms': endTimeMs,
      if (totalDistanceM != null) 'total_distance_m': totalDistanceM,
      if (movingMs != null) 'moving_ms': movingMs,
      if (isVerified != null) 'is_verified': isVerified,
      if (isSynced != null) 'is_synced': isSynced,
      if (ghostSessionId != null) 'ghost_session_id': ghostSessionId,
      if (integrityFlags != null) 'integrity_flags': integrityFlags,
      if (avgBpm != null) 'avg_bpm': avgBpm,
      if (maxBpm != null) 'max_bpm': maxBpm,
      if (avgCadenceSpm != null) 'avg_cadence_spm': avgCadenceSpm,
      if (source != null) 'source': source,
      if (deviceName != null) 'device_name': deviceName,
    });
  }

  WorkoutSessionsCompanion copyWith({
    Value<int>? id,
    Value<String>? sessionUuid,
    Value<String?>? userId,
    Value<int>? status,
    Value<int>? startTimeMs,
    Value<int?>? endTimeMs,
    Value<double>? totalDistanceM,
    Value<int>? movingMs,
    Value<bool>? isVerified,
    Value<bool>? isSynced,
    Value<String?>? ghostSessionId,
    Value<List<String>>? integrityFlags,
    Value<int?>? avgBpm,
    Value<int?>? maxBpm,
    Value<double?>? avgCadenceSpm,
    Value<String>? source,
    Value<String?>? deviceName,
  }) {
    return WorkoutSessionsCompanion(
      id: id ?? this.id,
      sessionUuid: sessionUuid ?? this.sessionUuid,
      userId: userId ?? this.userId,
      status: status ?? this.status,
      startTimeMs: startTimeMs ?? this.startTimeMs,
      endTimeMs: endTimeMs ?? this.endTimeMs,
      totalDistanceM: totalDistanceM ?? this.totalDistanceM,
      movingMs: movingMs ?? this.movingMs,
      isVerified: isVerified ?? this.isVerified,
      isSynced: isSynced ?? this.isSynced,
      ghostSessionId: ghostSessionId ?? this.ghostSessionId,
      integrityFlags: integrityFlags ?? this.integrityFlags,
      avgBpm: avgBpm ?? this.avgBpm,
      maxBpm: maxBpm ?? this.maxBpm,
      avgCadenceSpm: avgCadenceSpm ?? this.avgCadenceSpm,
      source: source ?? this.source,
      deviceName: deviceName ?? this.deviceName,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (sessionUuid.present) {
      map['session_uuid'] = Variable<String>(sessionUuid.value);
    }
    if (userId.present) {
      map['user_id'] = Variable<String>(userId.value);
    }
    if (status.present) {
      map['status'] = Variable<int>(status.value);
    }
    if (startTimeMs.present) {
      map['start_time_ms'] = Variable<int>(startTimeMs.value);
    }
    if (endTimeMs.present) {
      map['end_time_ms'] = Variable<int>(endTimeMs.value);
    }
    if (totalDistanceM.present) {
      map['total_distance_m'] = Variable<double>(totalDistanceM.value);
    }
    if (movingMs.present) {
      map['moving_ms'] = Variable<int>(movingMs.value);
    }
    if (isVerified.present) {
      map['is_verified'] = Variable<bool>(isVerified.value);
    }
    if (isSynced.present) {
      map['is_synced'] = Variable<bool>(isSynced.value);
    }
    if (ghostSessionId.present) {
      map['ghost_session_id'] = Variable<String>(ghostSessionId.value);
    }
    if (integrityFlags.present) {
      map['integrity_flags'] = Variable<String>(
        $WorkoutSessionsTable.$converterintegrityFlags.toSql(
          integrityFlags.value,
        ),
      );
    }
    if (avgBpm.present) {
      map['avg_bpm'] = Variable<int>(avgBpm.value);
    }
    if (maxBpm.present) {
      map['max_bpm'] = Variable<int>(maxBpm.value);
    }
    if (avgCadenceSpm.present) {
      map['avg_cadence_spm'] = Variable<double>(avgCadenceSpm.value);
    }
    if (source.present) {
      map['source'] = Variable<String>(source.value);
    }
    if (deviceName.present) {
      map['device_name'] = Variable<String>(deviceName.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('WorkoutSessionsCompanion(')
          ..write('id: $id, ')
          ..write('sessionUuid: $sessionUuid, ')
          ..write('userId: $userId, ')
          ..write('status: $status, ')
          ..write('startTimeMs: $startTimeMs, ')
          ..write('endTimeMs: $endTimeMs, ')
          ..write('totalDistanceM: $totalDistanceM, ')
          ..write('movingMs: $movingMs, ')
          ..write('isVerified: $isVerified, ')
          ..write('isSynced: $isSynced, ')
          ..write('ghostSessionId: $ghostSessionId, ')
          ..write('integrityFlags: $integrityFlags, ')
          ..write('avgBpm: $avgBpm, ')
          ..write('maxBpm: $maxBpm, ')
          ..write('avgCadenceSpm: $avgCadenceSpm, ')
          ..write('source: $source, ')
          ..write('deviceName: $deviceName')
          ..write(')'))
        .toString();
  }
}

class $ChallengesTable extends Challenges
    with TableInfo<$ChallengesTable, Challenge> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ChallengesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _challengeUuidMeta = const VerificationMeta(
    'challengeUuid',
  );
  @override
  late final GeneratedColumn<String> challengeUuid = GeneratedColumn<String>(
    'challenge_uuid',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways('UNIQUE'),
  );
  static const VerificationMeta _creatorUserIdMeta = const VerificationMeta(
    'creatorUserId',
  );
  @override
  late final GeneratedColumn<String> creatorUserId = GeneratedColumn<String>(
    'creator_user_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<String> status = GeneratedColumn<String>(
    'status',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _typeMeta = const VerificationMeta('type');
  @override
  late final GeneratedColumn<String> type = GeneratedColumn<String>(
    'type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
    'title',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _metricOrdinalMeta = const VerificationMeta(
    'metricOrdinal',
  );
  @override
  late final GeneratedColumn<String> metricOrdinal = GeneratedColumn<String>(
    'metric_ordinal',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _targetMeta = const VerificationMeta('target');
  @override
  late final GeneratedColumn<double> target = GeneratedColumn<double>(
    'target',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _windowMsMeta = const VerificationMeta(
    'windowMs',
  );
  @override
  late final GeneratedColumn<int> windowMs = GeneratedColumn<int>(
    'window_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _startModeOrdinalMeta = const VerificationMeta(
    'startModeOrdinal',
  );
  @override
  late final GeneratedColumn<String> startModeOrdinal = GeneratedColumn<String>(
    'start_mode_ordinal',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _fixedStartMsMeta = const VerificationMeta(
    'fixedStartMs',
  );
  @override
  late final GeneratedColumn<int> fixedStartMs = GeneratedColumn<int>(
    'fixed_start_ms',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _minSessionDistanceMMeta =
      const VerificationMeta('minSessionDistanceM');
  @override
  late final GeneratedColumn<double> minSessionDistanceM =
      GeneratedColumn<double>(
        'min_session_distance_m',
        aliasedName,
        false,
        type: DriftSqlType.double,
        requiredDuringInsert: true,
      );
  static const VerificationMeta _antiCheatPolicyOrdinalMeta =
      const VerificationMeta('antiCheatPolicyOrdinal');
  @override
  late final GeneratedColumn<String> antiCheatPolicyOrdinal =
      GeneratedColumn<String>(
        'anti_cheat_policy_ordinal',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      );
  static const VerificationMeta _entryFeeCoinsMeta = const VerificationMeta(
    'entryFeeCoins',
  );
  @override
  late final GeneratedColumn<int> entryFeeCoins = GeneratedColumn<int>(
    'entry_fee_coins',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _createdAtMsMeta = const VerificationMeta(
    'createdAtMs',
  );
  @override
  late final GeneratedColumn<int> createdAtMs = GeneratedColumn<int>(
    'created_at_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _startsAtMsMeta = const VerificationMeta(
    'startsAtMs',
  );
  @override
  late final GeneratedColumn<int> startsAtMs = GeneratedColumn<int>(
    'starts_at_ms',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _endsAtMsMeta = const VerificationMeta(
    'endsAtMs',
  );
  @override
  late final GeneratedColumn<int> endsAtMs = GeneratedColumn<int>(
    'ends_at_ms',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _teamAGroupIdMeta = const VerificationMeta(
    'teamAGroupId',
  );
  @override
  late final GeneratedColumn<String> teamAGroupId = GeneratedColumn<String>(
    'team_a_group_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _teamBGroupIdMeta = const VerificationMeta(
    'teamBGroupId',
  );
  @override
  late final GeneratedColumn<String> teamBGroupId = GeneratedColumn<String>(
    'team_b_group_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _teamAGroupNameMeta = const VerificationMeta(
    'teamAGroupName',
  );
  @override
  late final GeneratedColumn<String> teamAGroupName = GeneratedColumn<String>(
    'team_a_group_name',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _teamBGroupNameMeta = const VerificationMeta(
    'teamBGroupName',
  );
  @override
  late final GeneratedColumn<String> teamBGroupName = GeneratedColumn<String>(
    'team_b_group_name',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _acceptDeadlineMsMeta = const VerificationMeta(
    'acceptDeadlineMs',
  );
  @override
  late final GeneratedColumn<int> acceptDeadlineMs = GeneratedColumn<int>(
    'accept_deadline_ms',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  @override
  late final GeneratedColumnWithTypeConverter<List<String>, String>
  participantsJson = GeneratedColumn<String>(
    'participants_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('[]'),
  ).withConverter<List<String>>($ChallengesTable.$converterparticipantsJson);
  @override
  List<GeneratedColumn> get $columns => [
    id,
    challengeUuid,
    creatorUserId,
    status,
    type,
    title,
    metricOrdinal,
    target,
    windowMs,
    startModeOrdinal,
    fixedStartMs,
    minSessionDistanceM,
    antiCheatPolicyOrdinal,
    entryFeeCoins,
    createdAtMs,
    startsAtMs,
    endsAtMs,
    teamAGroupId,
    teamBGroupId,
    teamAGroupName,
    teamBGroupName,
    acceptDeadlineMs,
    participantsJson,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'challenges';
  @override
  VerificationContext validateIntegrity(
    Insertable<Challenge> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('challenge_uuid')) {
      context.handle(
        _challengeUuidMeta,
        challengeUuid.isAcceptableOrUnknown(
          data['challenge_uuid']!,
          _challengeUuidMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_challengeUuidMeta);
    }
    if (data.containsKey('creator_user_id')) {
      context.handle(
        _creatorUserIdMeta,
        creatorUserId.isAcceptableOrUnknown(
          data['creator_user_id']!,
          _creatorUserIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_creatorUserIdMeta);
    }
    if (data.containsKey('status')) {
      context.handle(
        _statusMeta,
        status.isAcceptableOrUnknown(data['status']!, _statusMeta),
      );
    } else if (isInserting) {
      context.missing(_statusMeta);
    }
    if (data.containsKey('type')) {
      context.handle(
        _typeMeta,
        type.isAcceptableOrUnknown(data['type']!, _typeMeta),
      );
    } else if (isInserting) {
      context.missing(_typeMeta);
    }
    if (data.containsKey('title')) {
      context.handle(
        _titleMeta,
        title.isAcceptableOrUnknown(data['title']!, _titleMeta),
      );
    }
    if (data.containsKey('metric_ordinal')) {
      context.handle(
        _metricOrdinalMeta,
        metricOrdinal.isAcceptableOrUnknown(
          data['metric_ordinal']!,
          _metricOrdinalMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_metricOrdinalMeta);
    }
    if (data.containsKey('target')) {
      context.handle(
        _targetMeta,
        target.isAcceptableOrUnknown(data['target']!, _targetMeta),
      );
    }
    if (data.containsKey('window_ms')) {
      context.handle(
        _windowMsMeta,
        windowMs.isAcceptableOrUnknown(data['window_ms']!, _windowMsMeta),
      );
    } else if (isInserting) {
      context.missing(_windowMsMeta);
    }
    if (data.containsKey('start_mode_ordinal')) {
      context.handle(
        _startModeOrdinalMeta,
        startModeOrdinal.isAcceptableOrUnknown(
          data['start_mode_ordinal']!,
          _startModeOrdinalMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_startModeOrdinalMeta);
    }
    if (data.containsKey('fixed_start_ms')) {
      context.handle(
        _fixedStartMsMeta,
        fixedStartMs.isAcceptableOrUnknown(
          data['fixed_start_ms']!,
          _fixedStartMsMeta,
        ),
      );
    }
    if (data.containsKey('min_session_distance_m')) {
      context.handle(
        _minSessionDistanceMMeta,
        minSessionDistanceM.isAcceptableOrUnknown(
          data['min_session_distance_m']!,
          _minSessionDistanceMMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_minSessionDistanceMMeta);
    }
    if (data.containsKey('anti_cheat_policy_ordinal')) {
      context.handle(
        _antiCheatPolicyOrdinalMeta,
        antiCheatPolicyOrdinal.isAcceptableOrUnknown(
          data['anti_cheat_policy_ordinal']!,
          _antiCheatPolicyOrdinalMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_antiCheatPolicyOrdinalMeta);
    }
    if (data.containsKey('entry_fee_coins')) {
      context.handle(
        _entryFeeCoinsMeta,
        entryFeeCoins.isAcceptableOrUnknown(
          data['entry_fee_coins']!,
          _entryFeeCoinsMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_entryFeeCoinsMeta);
    }
    if (data.containsKey('created_at_ms')) {
      context.handle(
        _createdAtMsMeta,
        createdAtMs.isAcceptableOrUnknown(
          data['created_at_ms']!,
          _createdAtMsMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_createdAtMsMeta);
    }
    if (data.containsKey('starts_at_ms')) {
      context.handle(
        _startsAtMsMeta,
        startsAtMs.isAcceptableOrUnknown(
          data['starts_at_ms']!,
          _startsAtMsMeta,
        ),
      );
    }
    if (data.containsKey('ends_at_ms')) {
      context.handle(
        _endsAtMsMeta,
        endsAtMs.isAcceptableOrUnknown(data['ends_at_ms']!, _endsAtMsMeta),
      );
    }
    if (data.containsKey('team_a_group_id')) {
      context.handle(
        _teamAGroupIdMeta,
        teamAGroupId.isAcceptableOrUnknown(
          data['team_a_group_id']!,
          _teamAGroupIdMeta,
        ),
      );
    }
    if (data.containsKey('team_b_group_id')) {
      context.handle(
        _teamBGroupIdMeta,
        teamBGroupId.isAcceptableOrUnknown(
          data['team_b_group_id']!,
          _teamBGroupIdMeta,
        ),
      );
    }
    if (data.containsKey('team_a_group_name')) {
      context.handle(
        _teamAGroupNameMeta,
        teamAGroupName.isAcceptableOrUnknown(
          data['team_a_group_name']!,
          _teamAGroupNameMeta,
        ),
      );
    }
    if (data.containsKey('team_b_group_name')) {
      context.handle(
        _teamBGroupNameMeta,
        teamBGroupName.isAcceptableOrUnknown(
          data['team_b_group_name']!,
          _teamBGroupNameMeta,
        ),
      );
    }
    if (data.containsKey('accept_deadline_ms')) {
      context.handle(
        _acceptDeadlineMsMeta,
        acceptDeadlineMs.isAcceptableOrUnknown(
          data['accept_deadline_ms']!,
          _acceptDeadlineMsMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Challenge map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Challenge(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      challengeUuid: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}challenge_uuid'],
      )!,
      creatorUserId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}creator_user_id'],
      )!,
      status: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}status'],
      )!,
      type: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}type'],
      )!,
      title: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title'],
      ),
      metricOrdinal: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}metric_ordinal'],
      )!,
      target: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}target'],
      ),
      windowMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}window_ms'],
      )!,
      startModeOrdinal: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}start_mode_ordinal'],
      )!,
      fixedStartMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}fixed_start_ms'],
      ),
      minSessionDistanceM: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}min_session_distance_m'],
      )!,
      antiCheatPolicyOrdinal: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}anti_cheat_policy_ordinal'],
      )!,
      entryFeeCoins: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}entry_fee_coins'],
      )!,
      createdAtMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_at_ms'],
      )!,
      startsAtMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}starts_at_ms'],
      ),
      endsAtMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}ends_at_ms'],
      ),
      teamAGroupId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}team_a_group_id'],
      ),
      teamBGroupId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}team_b_group_id'],
      ),
      teamAGroupName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}team_a_group_name'],
      ),
      teamBGroupName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}team_b_group_name'],
      ),
      acceptDeadlineMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}accept_deadline_ms'],
      ),
      participantsJson: $ChallengesTable.$converterparticipantsJson.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}participants_json'],
        )!,
      ),
    );
  }

  @override
  $ChallengesTable createAlias(String alias) {
    return $ChallengesTable(attachedDatabase, alias);
  }

  static TypeConverter<List<String>, String> $converterparticipantsJson =
      const StringListConverter();
}

class Challenge extends DataClass implements Insertable<Challenge> {
  final int id;
  final String challengeUuid;
  final String creatorUserId;
  final String status;
  final String type;
  final String? title;
  final String metricOrdinal;
  final double? target;
  final int windowMs;
  final String startModeOrdinal;
  final int? fixedStartMs;
  final double minSessionDistanceM;
  final String antiCheatPolicyOrdinal;
  final int entryFeeCoins;
  final int createdAtMs;
  final int? startsAtMs;
  final int? endsAtMs;
  final String? teamAGroupId;
  final String? teamBGroupId;
  final String? teamAGroupName;
  final String? teamBGroupName;
  final int? acceptDeadlineMs;
  final List<String> participantsJson;
  const Challenge({
    required this.id,
    required this.challengeUuid,
    required this.creatorUserId,
    required this.status,
    required this.type,
    this.title,
    required this.metricOrdinal,
    this.target,
    required this.windowMs,
    required this.startModeOrdinal,
    this.fixedStartMs,
    required this.minSessionDistanceM,
    required this.antiCheatPolicyOrdinal,
    required this.entryFeeCoins,
    required this.createdAtMs,
    this.startsAtMs,
    this.endsAtMs,
    this.teamAGroupId,
    this.teamBGroupId,
    this.teamAGroupName,
    this.teamBGroupName,
    this.acceptDeadlineMs,
    required this.participantsJson,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['challenge_uuid'] = Variable<String>(challengeUuid);
    map['creator_user_id'] = Variable<String>(creatorUserId);
    map['status'] = Variable<String>(status);
    map['type'] = Variable<String>(type);
    if (!nullToAbsent || title != null) {
      map['title'] = Variable<String>(title);
    }
    map['metric_ordinal'] = Variable<String>(metricOrdinal);
    if (!nullToAbsent || target != null) {
      map['target'] = Variable<double>(target);
    }
    map['window_ms'] = Variable<int>(windowMs);
    map['start_mode_ordinal'] = Variable<String>(startModeOrdinal);
    if (!nullToAbsent || fixedStartMs != null) {
      map['fixed_start_ms'] = Variable<int>(fixedStartMs);
    }
    map['min_session_distance_m'] = Variable<double>(minSessionDistanceM);
    map['anti_cheat_policy_ordinal'] = Variable<String>(antiCheatPolicyOrdinal);
    map['entry_fee_coins'] = Variable<int>(entryFeeCoins);
    map['created_at_ms'] = Variable<int>(createdAtMs);
    if (!nullToAbsent || startsAtMs != null) {
      map['starts_at_ms'] = Variable<int>(startsAtMs);
    }
    if (!nullToAbsent || endsAtMs != null) {
      map['ends_at_ms'] = Variable<int>(endsAtMs);
    }
    if (!nullToAbsent || teamAGroupId != null) {
      map['team_a_group_id'] = Variable<String>(teamAGroupId);
    }
    if (!nullToAbsent || teamBGroupId != null) {
      map['team_b_group_id'] = Variable<String>(teamBGroupId);
    }
    if (!nullToAbsent || teamAGroupName != null) {
      map['team_a_group_name'] = Variable<String>(teamAGroupName);
    }
    if (!nullToAbsent || teamBGroupName != null) {
      map['team_b_group_name'] = Variable<String>(teamBGroupName);
    }
    if (!nullToAbsent || acceptDeadlineMs != null) {
      map['accept_deadline_ms'] = Variable<int>(acceptDeadlineMs);
    }
    {
      map['participants_json'] = Variable<String>(
        $ChallengesTable.$converterparticipantsJson.toSql(participantsJson),
      );
    }
    return map;
  }

  ChallengesCompanion toCompanion(bool nullToAbsent) {
    return ChallengesCompanion(
      id: Value(id),
      challengeUuid: Value(challengeUuid),
      creatorUserId: Value(creatorUserId),
      status: Value(status),
      type: Value(type),
      title: title == null && nullToAbsent
          ? const Value.absent()
          : Value(title),
      metricOrdinal: Value(metricOrdinal),
      target: target == null && nullToAbsent
          ? const Value.absent()
          : Value(target),
      windowMs: Value(windowMs),
      startModeOrdinal: Value(startModeOrdinal),
      fixedStartMs: fixedStartMs == null && nullToAbsent
          ? const Value.absent()
          : Value(fixedStartMs),
      minSessionDistanceM: Value(minSessionDistanceM),
      antiCheatPolicyOrdinal: Value(antiCheatPolicyOrdinal),
      entryFeeCoins: Value(entryFeeCoins),
      createdAtMs: Value(createdAtMs),
      startsAtMs: startsAtMs == null && nullToAbsent
          ? const Value.absent()
          : Value(startsAtMs),
      endsAtMs: endsAtMs == null && nullToAbsent
          ? const Value.absent()
          : Value(endsAtMs),
      teamAGroupId: teamAGroupId == null && nullToAbsent
          ? const Value.absent()
          : Value(teamAGroupId),
      teamBGroupId: teamBGroupId == null && nullToAbsent
          ? const Value.absent()
          : Value(teamBGroupId),
      teamAGroupName: teamAGroupName == null && nullToAbsent
          ? const Value.absent()
          : Value(teamAGroupName),
      teamBGroupName: teamBGroupName == null && nullToAbsent
          ? const Value.absent()
          : Value(teamBGroupName),
      acceptDeadlineMs: acceptDeadlineMs == null && nullToAbsent
          ? const Value.absent()
          : Value(acceptDeadlineMs),
      participantsJson: Value(participantsJson),
    );
  }

  factory Challenge.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Challenge(
      id: serializer.fromJson<int>(json['id']),
      challengeUuid: serializer.fromJson<String>(json['challengeUuid']),
      creatorUserId: serializer.fromJson<String>(json['creatorUserId']),
      status: serializer.fromJson<String>(json['status']),
      type: serializer.fromJson<String>(json['type']),
      title: serializer.fromJson<String?>(json['title']),
      metricOrdinal: serializer.fromJson<String>(json['metricOrdinal']),
      target: serializer.fromJson<double?>(json['target']),
      windowMs: serializer.fromJson<int>(json['windowMs']),
      startModeOrdinal: serializer.fromJson<String>(json['startModeOrdinal']),
      fixedStartMs: serializer.fromJson<int?>(json['fixedStartMs']),
      minSessionDistanceM: serializer.fromJson<double>(
        json['minSessionDistanceM'],
      ),
      antiCheatPolicyOrdinal: serializer.fromJson<String>(
        json['antiCheatPolicyOrdinal'],
      ),
      entryFeeCoins: serializer.fromJson<int>(json['entryFeeCoins']),
      createdAtMs: serializer.fromJson<int>(json['createdAtMs']),
      startsAtMs: serializer.fromJson<int?>(json['startsAtMs']),
      endsAtMs: serializer.fromJson<int?>(json['endsAtMs']),
      teamAGroupId: serializer.fromJson<String?>(json['teamAGroupId']),
      teamBGroupId: serializer.fromJson<String?>(json['teamBGroupId']),
      teamAGroupName: serializer.fromJson<String?>(json['teamAGroupName']),
      teamBGroupName: serializer.fromJson<String?>(json['teamBGroupName']),
      acceptDeadlineMs: serializer.fromJson<int?>(json['acceptDeadlineMs']),
      participantsJson: serializer.fromJson<List<String>>(
        json['participantsJson'],
      ),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'challengeUuid': serializer.toJson<String>(challengeUuid),
      'creatorUserId': serializer.toJson<String>(creatorUserId),
      'status': serializer.toJson<String>(status),
      'type': serializer.toJson<String>(type),
      'title': serializer.toJson<String?>(title),
      'metricOrdinal': serializer.toJson<String>(metricOrdinal),
      'target': serializer.toJson<double?>(target),
      'windowMs': serializer.toJson<int>(windowMs),
      'startModeOrdinal': serializer.toJson<String>(startModeOrdinal),
      'fixedStartMs': serializer.toJson<int?>(fixedStartMs),
      'minSessionDistanceM': serializer.toJson<double>(minSessionDistanceM),
      'antiCheatPolicyOrdinal': serializer.toJson<String>(
        antiCheatPolicyOrdinal,
      ),
      'entryFeeCoins': serializer.toJson<int>(entryFeeCoins),
      'createdAtMs': serializer.toJson<int>(createdAtMs),
      'startsAtMs': serializer.toJson<int?>(startsAtMs),
      'endsAtMs': serializer.toJson<int?>(endsAtMs),
      'teamAGroupId': serializer.toJson<String?>(teamAGroupId),
      'teamBGroupId': serializer.toJson<String?>(teamBGroupId),
      'teamAGroupName': serializer.toJson<String?>(teamAGroupName),
      'teamBGroupName': serializer.toJson<String?>(teamBGroupName),
      'acceptDeadlineMs': serializer.toJson<int?>(acceptDeadlineMs),
      'participantsJson': serializer.toJson<List<String>>(participantsJson),
    };
  }

  Challenge copyWith({
    int? id,
    String? challengeUuid,
    String? creatorUserId,
    String? status,
    String? type,
    Value<String?> title = const Value.absent(),
    String? metricOrdinal,
    Value<double?> target = const Value.absent(),
    int? windowMs,
    String? startModeOrdinal,
    Value<int?> fixedStartMs = const Value.absent(),
    double? minSessionDistanceM,
    String? antiCheatPolicyOrdinal,
    int? entryFeeCoins,
    int? createdAtMs,
    Value<int?> startsAtMs = const Value.absent(),
    Value<int?> endsAtMs = const Value.absent(),
    Value<String?> teamAGroupId = const Value.absent(),
    Value<String?> teamBGroupId = const Value.absent(),
    Value<String?> teamAGroupName = const Value.absent(),
    Value<String?> teamBGroupName = const Value.absent(),
    Value<int?> acceptDeadlineMs = const Value.absent(),
    List<String>? participantsJson,
  }) => Challenge(
    id: id ?? this.id,
    challengeUuid: challengeUuid ?? this.challengeUuid,
    creatorUserId: creatorUserId ?? this.creatorUserId,
    status: status ?? this.status,
    type: type ?? this.type,
    title: title.present ? title.value : this.title,
    metricOrdinal: metricOrdinal ?? this.metricOrdinal,
    target: target.present ? target.value : this.target,
    windowMs: windowMs ?? this.windowMs,
    startModeOrdinal: startModeOrdinal ?? this.startModeOrdinal,
    fixedStartMs: fixedStartMs.present ? fixedStartMs.value : this.fixedStartMs,
    minSessionDistanceM: minSessionDistanceM ?? this.minSessionDistanceM,
    antiCheatPolicyOrdinal:
        antiCheatPolicyOrdinal ?? this.antiCheatPolicyOrdinal,
    entryFeeCoins: entryFeeCoins ?? this.entryFeeCoins,
    createdAtMs: createdAtMs ?? this.createdAtMs,
    startsAtMs: startsAtMs.present ? startsAtMs.value : this.startsAtMs,
    endsAtMs: endsAtMs.present ? endsAtMs.value : this.endsAtMs,
    teamAGroupId: teamAGroupId.present ? teamAGroupId.value : this.teamAGroupId,
    teamBGroupId: teamBGroupId.present ? teamBGroupId.value : this.teamBGroupId,
    teamAGroupName: teamAGroupName.present
        ? teamAGroupName.value
        : this.teamAGroupName,
    teamBGroupName: teamBGroupName.present
        ? teamBGroupName.value
        : this.teamBGroupName,
    acceptDeadlineMs: acceptDeadlineMs.present
        ? acceptDeadlineMs.value
        : this.acceptDeadlineMs,
    participantsJson: participantsJson ?? this.participantsJson,
  );
  Challenge copyWithCompanion(ChallengesCompanion data) {
    return Challenge(
      id: data.id.present ? data.id.value : this.id,
      challengeUuid: data.challengeUuid.present
          ? data.challengeUuid.value
          : this.challengeUuid,
      creatorUserId: data.creatorUserId.present
          ? data.creatorUserId.value
          : this.creatorUserId,
      status: data.status.present ? data.status.value : this.status,
      type: data.type.present ? data.type.value : this.type,
      title: data.title.present ? data.title.value : this.title,
      metricOrdinal: data.metricOrdinal.present
          ? data.metricOrdinal.value
          : this.metricOrdinal,
      target: data.target.present ? data.target.value : this.target,
      windowMs: data.windowMs.present ? data.windowMs.value : this.windowMs,
      startModeOrdinal: data.startModeOrdinal.present
          ? data.startModeOrdinal.value
          : this.startModeOrdinal,
      fixedStartMs: data.fixedStartMs.present
          ? data.fixedStartMs.value
          : this.fixedStartMs,
      minSessionDistanceM: data.minSessionDistanceM.present
          ? data.minSessionDistanceM.value
          : this.minSessionDistanceM,
      antiCheatPolicyOrdinal: data.antiCheatPolicyOrdinal.present
          ? data.antiCheatPolicyOrdinal.value
          : this.antiCheatPolicyOrdinal,
      entryFeeCoins: data.entryFeeCoins.present
          ? data.entryFeeCoins.value
          : this.entryFeeCoins,
      createdAtMs: data.createdAtMs.present
          ? data.createdAtMs.value
          : this.createdAtMs,
      startsAtMs: data.startsAtMs.present
          ? data.startsAtMs.value
          : this.startsAtMs,
      endsAtMs: data.endsAtMs.present ? data.endsAtMs.value : this.endsAtMs,
      teamAGroupId: data.teamAGroupId.present
          ? data.teamAGroupId.value
          : this.teamAGroupId,
      teamBGroupId: data.teamBGroupId.present
          ? data.teamBGroupId.value
          : this.teamBGroupId,
      teamAGroupName: data.teamAGroupName.present
          ? data.teamAGroupName.value
          : this.teamAGroupName,
      teamBGroupName: data.teamBGroupName.present
          ? data.teamBGroupName.value
          : this.teamBGroupName,
      acceptDeadlineMs: data.acceptDeadlineMs.present
          ? data.acceptDeadlineMs.value
          : this.acceptDeadlineMs,
      participantsJson: data.participantsJson.present
          ? data.participantsJson.value
          : this.participantsJson,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Challenge(')
          ..write('id: $id, ')
          ..write('challengeUuid: $challengeUuid, ')
          ..write('creatorUserId: $creatorUserId, ')
          ..write('status: $status, ')
          ..write('type: $type, ')
          ..write('title: $title, ')
          ..write('metricOrdinal: $metricOrdinal, ')
          ..write('target: $target, ')
          ..write('windowMs: $windowMs, ')
          ..write('startModeOrdinal: $startModeOrdinal, ')
          ..write('fixedStartMs: $fixedStartMs, ')
          ..write('minSessionDistanceM: $minSessionDistanceM, ')
          ..write('antiCheatPolicyOrdinal: $antiCheatPolicyOrdinal, ')
          ..write('entryFeeCoins: $entryFeeCoins, ')
          ..write('createdAtMs: $createdAtMs, ')
          ..write('startsAtMs: $startsAtMs, ')
          ..write('endsAtMs: $endsAtMs, ')
          ..write('teamAGroupId: $teamAGroupId, ')
          ..write('teamBGroupId: $teamBGroupId, ')
          ..write('teamAGroupName: $teamAGroupName, ')
          ..write('teamBGroupName: $teamBGroupName, ')
          ..write('acceptDeadlineMs: $acceptDeadlineMs, ')
          ..write('participantsJson: $participantsJson')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hashAll([
    id,
    challengeUuid,
    creatorUserId,
    status,
    type,
    title,
    metricOrdinal,
    target,
    windowMs,
    startModeOrdinal,
    fixedStartMs,
    minSessionDistanceM,
    antiCheatPolicyOrdinal,
    entryFeeCoins,
    createdAtMs,
    startsAtMs,
    endsAtMs,
    teamAGroupId,
    teamBGroupId,
    teamAGroupName,
    teamBGroupName,
    acceptDeadlineMs,
    participantsJson,
  ]);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Challenge &&
          other.id == this.id &&
          other.challengeUuid == this.challengeUuid &&
          other.creatorUserId == this.creatorUserId &&
          other.status == this.status &&
          other.type == this.type &&
          other.title == this.title &&
          other.metricOrdinal == this.metricOrdinal &&
          other.target == this.target &&
          other.windowMs == this.windowMs &&
          other.startModeOrdinal == this.startModeOrdinal &&
          other.fixedStartMs == this.fixedStartMs &&
          other.minSessionDistanceM == this.minSessionDistanceM &&
          other.antiCheatPolicyOrdinal == this.antiCheatPolicyOrdinal &&
          other.entryFeeCoins == this.entryFeeCoins &&
          other.createdAtMs == this.createdAtMs &&
          other.startsAtMs == this.startsAtMs &&
          other.endsAtMs == this.endsAtMs &&
          other.teamAGroupId == this.teamAGroupId &&
          other.teamBGroupId == this.teamBGroupId &&
          other.teamAGroupName == this.teamAGroupName &&
          other.teamBGroupName == this.teamBGroupName &&
          other.acceptDeadlineMs == this.acceptDeadlineMs &&
          other.participantsJson == this.participantsJson);
}

class ChallengesCompanion extends UpdateCompanion<Challenge> {
  final Value<int> id;
  final Value<String> challengeUuid;
  final Value<String> creatorUserId;
  final Value<String> status;
  final Value<String> type;
  final Value<String?> title;
  final Value<String> metricOrdinal;
  final Value<double?> target;
  final Value<int> windowMs;
  final Value<String> startModeOrdinal;
  final Value<int?> fixedStartMs;
  final Value<double> minSessionDistanceM;
  final Value<String> antiCheatPolicyOrdinal;
  final Value<int> entryFeeCoins;
  final Value<int> createdAtMs;
  final Value<int?> startsAtMs;
  final Value<int?> endsAtMs;
  final Value<String?> teamAGroupId;
  final Value<String?> teamBGroupId;
  final Value<String?> teamAGroupName;
  final Value<String?> teamBGroupName;
  final Value<int?> acceptDeadlineMs;
  final Value<List<String>> participantsJson;
  const ChallengesCompanion({
    this.id = const Value.absent(),
    this.challengeUuid = const Value.absent(),
    this.creatorUserId = const Value.absent(),
    this.status = const Value.absent(),
    this.type = const Value.absent(),
    this.title = const Value.absent(),
    this.metricOrdinal = const Value.absent(),
    this.target = const Value.absent(),
    this.windowMs = const Value.absent(),
    this.startModeOrdinal = const Value.absent(),
    this.fixedStartMs = const Value.absent(),
    this.minSessionDistanceM = const Value.absent(),
    this.antiCheatPolicyOrdinal = const Value.absent(),
    this.entryFeeCoins = const Value.absent(),
    this.createdAtMs = const Value.absent(),
    this.startsAtMs = const Value.absent(),
    this.endsAtMs = const Value.absent(),
    this.teamAGroupId = const Value.absent(),
    this.teamBGroupId = const Value.absent(),
    this.teamAGroupName = const Value.absent(),
    this.teamBGroupName = const Value.absent(),
    this.acceptDeadlineMs = const Value.absent(),
    this.participantsJson = const Value.absent(),
  });
  ChallengesCompanion.insert({
    this.id = const Value.absent(),
    required String challengeUuid,
    required String creatorUserId,
    required String status,
    required String type,
    this.title = const Value.absent(),
    required String metricOrdinal,
    this.target = const Value.absent(),
    required int windowMs,
    required String startModeOrdinal,
    this.fixedStartMs = const Value.absent(),
    required double minSessionDistanceM,
    required String antiCheatPolicyOrdinal,
    required int entryFeeCoins,
    required int createdAtMs,
    this.startsAtMs = const Value.absent(),
    this.endsAtMs = const Value.absent(),
    this.teamAGroupId = const Value.absent(),
    this.teamBGroupId = const Value.absent(),
    this.teamAGroupName = const Value.absent(),
    this.teamBGroupName = const Value.absent(),
    this.acceptDeadlineMs = const Value.absent(),
    this.participantsJson = const Value.absent(),
  }) : challengeUuid = Value(challengeUuid),
       creatorUserId = Value(creatorUserId),
       status = Value(status),
       type = Value(type),
       metricOrdinal = Value(metricOrdinal),
       windowMs = Value(windowMs),
       startModeOrdinal = Value(startModeOrdinal),
       minSessionDistanceM = Value(minSessionDistanceM),
       antiCheatPolicyOrdinal = Value(antiCheatPolicyOrdinal),
       entryFeeCoins = Value(entryFeeCoins),
       createdAtMs = Value(createdAtMs);
  static Insertable<Challenge> custom({
    Expression<int>? id,
    Expression<String>? challengeUuid,
    Expression<String>? creatorUserId,
    Expression<String>? status,
    Expression<String>? type,
    Expression<String>? title,
    Expression<String>? metricOrdinal,
    Expression<double>? target,
    Expression<int>? windowMs,
    Expression<String>? startModeOrdinal,
    Expression<int>? fixedStartMs,
    Expression<double>? minSessionDistanceM,
    Expression<String>? antiCheatPolicyOrdinal,
    Expression<int>? entryFeeCoins,
    Expression<int>? createdAtMs,
    Expression<int>? startsAtMs,
    Expression<int>? endsAtMs,
    Expression<String>? teamAGroupId,
    Expression<String>? teamBGroupId,
    Expression<String>? teamAGroupName,
    Expression<String>? teamBGroupName,
    Expression<int>? acceptDeadlineMs,
    Expression<String>? participantsJson,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (challengeUuid != null) 'challenge_uuid': challengeUuid,
      if (creatorUserId != null) 'creator_user_id': creatorUserId,
      if (status != null) 'status': status,
      if (type != null) 'type': type,
      if (title != null) 'title': title,
      if (metricOrdinal != null) 'metric_ordinal': metricOrdinal,
      if (target != null) 'target': target,
      if (windowMs != null) 'window_ms': windowMs,
      if (startModeOrdinal != null) 'start_mode_ordinal': startModeOrdinal,
      if (fixedStartMs != null) 'fixed_start_ms': fixedStartMs,
      if (minSessionDistanceM != null)
        'min_session_distance_m': minSessionDistanceM,
      if (antiCheatPolicyOrdinal != null)
        'anti_cheat_policy_ordinal': antiCheatPolicyOrdinal,
      if (entryFeeCoins != null) 'entry_fee_coins': entryFeeCoins,
      if (createdAtMs != null) 'created_at_ms': createdAtMs,
      if (startsAtMs != null) 'starts_at_ms': startsAtMs,
      if (endsAtMs != null) 'ends_at_ms': endsAtMs,
      if (teamAGroupId != null) 'team_a_group_id': teamAGroupId,
      if (teamBGroupId != null) 'team_b_group_id': teamBGroupId,
      if (teamAGroupName != null) 'team_a_group_name': teamAGroupName,
      if (teamBGroupName != null) 'team_b_group_name': teamBGroupName,
      if (acceptDeadlineMs != null) 'accept_deadline_ms': acceptDeadlineMs,
      if (participantsJson != null) 'participants_json': participantsJson,
    });
  }

  ChallengesCompanion copyWith({
    Value<int>? id,
    Value<String>? challengeUuid,
    Value<String>? creatorUserId,
    Value<String>? status,
    Value<String>? type,
    Value<String?>? title,
    Value<String>? metricOrdinal,
    Value<double?>? target,
    Value<int>? windowMs,
    Value<String>? startModeOrdinal,
    Value<int?>? fixedStartMs,
    Value<double>? minSessionDistanceM,
    Value<String>? antiCheatPolicyOrdinal,
    Value<int>? entryFeeCoins,
    Value<int>? createdAtMs,
    Value<int?>? startsAtMs,
    Value<int?>? endsAtMs,
    Value<String?>? teamAGroupId,
    Value<String?>? teamBGroupId,
    Value<String?>? teamAGroupName,
    Value<String?>? teamBGroupName,
    Value<int?>? acceptDeadlineMs,
    Value<List<String>>? participantsJson,
  }) {
    return ChallengesCompanion(
      id: id ?? this.id,
      challengeUuid: challengeUuid ?? this.challengeUuid,
      creatorUserId: creatorUserId ?? this.creatorUserId,
      status: status ?? this.status,
      type: type ?? this.type,
      title: title ?? this.title,
      metricOrdinal: metricOrdinal ?? this.metricOrdinal,
      target: target ?? this.target,
      windowMs: windowMs ?? this.windowMs,
      startModeOrdinal: startModeOrdinal ?? this.startModeOrdinal,
      fixedStartMs: fixedStartMs ?? this.fixedStartMs,
      minSessionDistanceM: minSessionDistanceM ?? this.minSessionDistanceM,
      antiCheatPolicyOrdinal:
          antiCheatPolicyOrdinal ?? this.antiCheatPolicyOrdinal,
      entryFeeCoins: entryFeeCoins ?? this.entryFeeCoins,
      createdAtMs: createdAtMs ?? this.createdAtMs,
      startsAtMs: startsAtMs ?? this.startsAtMs,
      endsAtMs: endsAtMs ?? this.endsAtMs,
      teamAGroupId: teamAGroupId ?? this.teamAGroupId,
      teamBGroupId: teamBGroupId ?? this.teamBGroupId,
      teamAGroupName: teamAGroupName ?? this.teamAGroupName,
      teamBGroupName: teamBGroupName ?? this.teamBGroupName,
      acceptDeadlineMs: acceptDeadlineMs ?? this.acceptDeadlineMs,
      participantsJson: participantsJson ?? this.participantsJson,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (challengeUuid.present) {
      map['challenge_uuid'] = Variable<String>(challengeUuid.value);
    }
    if (creatorUserId.present) {
      map['creator_user_id'] = Variable<String>(creatorUserId.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    if (type.present) {
      map['type'] = Variable<String>(type.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (metricOrdinal.present) {
      map['metric_ordinal'] = Variable<String>(metricOrdinal.value);
    }
    if (target.present) {
      map['target'] = Variable<double>(target.value);
    }
    if (windowMs.present) {
      map['window_ms'] = Variable<int>(windowMs.value);
    }
    if (startModeOrdinal.present) {
      map['start_mode_ordinal'] = Variable<String>(startModeOrdinal.value);
    }
    if (fixedStartMs.present) {
      map['fixed_start_ms'] = Variable<int>(fixedStartMs.value);
    }
    if (minSessionDistanceM.present) {
      map['min_session_distance_m'] = Variable<double>(
        minSessionDistanceM.value,
      );
    }
    if (antiCheatPolicyOrdinal.present) {
      map['anti_cheat_policy_ordinal'] = Variable<String>(
        antiCheatPolicyOrdinal.value,
      );
    }
    if (entryFeeCoins.present) {
      map['entry_fee_coins'] = Variable<int>(entryFeeCoins.value);
    }
    if (createdAtMs.present) {
      map['created_at_ms'] = Variable<int>(createdAtMs.value);
    }
    if (startsAtMs.present) {
      map['starts_at_ms'] = Variable<int>(startsAtMs.value);
    }
    if (endsAtMs.present) {
      map['ends_at_ms'] = Variable<int>(endsAtMs.value);
    }
    if (teamAGroupId.present) {
      map['team_a_group_id'] = Variable<String>(teamAGroupId.value);
    }
    if (teamBGroupId.present) {
      map['team_b_group_id'] = Variable<String>(teamBGroupId.value);
    }
    if (teamAGroupName.present) {
      map['team_a_group_name'] = Variable<String>(teamAGroupName.value);
    }
    if (teamBGroupName.present) {
      map['team_b_group_name'] = Variable<String>(teamBGroupName.value);
    }
    if (acceptDeadlineMs.present) {
      map['accept_deadline_ms'] = Variable<int>(acceptDeadlineMs.value);
    }
    if (participantsJson.present) {
      map['participants_json'] = Variable<String>(
        $ChallengesTable.$converterparticipantsJson.toSql(
          participantsJson.value,
        ),
      );
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ChallengesCompanion(')
          ..write('id: $id, ')
          ..write('challengeUuid: $challengeUuid, ')
          ..write('creatorUserId: $creatorUserId, ')
          ..write('status: $status, ')
          ..write('type: $type, ')
          ..write('title: $title, ')
          ..write('metricOrdinal: $metricOrdinal, ')
          ..write('target: $target, ')
          ..write('windowMs: $windowMs, ')
          ..write('startModeOrdinal: $startModeOrdinal, ')
          ..write('fixedStartMs: $fixedStartMs, ')
          ..write('minSessionDistanceM: $minSessionDistanceM, ')
          ..write('antiCheatPolicyOrdinal: $antiCheatPolicyOrdinal, ')
          ..write('entryFeeCoins: $entryFeeCoins, ')
          ..write('createdAtMs: $createdAtMs, ')
          ..write('startsAtMs: $startsAtMs, ')
          ..write('endsAtMs: $endsAtMs, ')
          ..write('teamAGroupId: $teamAGroupId, ')
          ..write('teamBGroupId: $teamBGroupId, ')
          ..write('teamAGroupName: $teamAGroupName, ')
          ..write('teamBGroupName: $teamBGroupName, ')
          ..write('acceptDeadlineMs: $acceptDeadlineMs, ')
          ..write('participantsJson: $participantsJson')
          ..write(')'))
        .toString();
  }
}

class $ChallengeResultsTable extends ChallengeResults
    with TableInfo<$ChallengeResultsTable, ChallengeResult> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ChallengeResultsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _challengeIdMeta = const VerificationMeta(
    'challengeId',
  );
  @override
  late final GeneratedColumn<String> challengeId = GeneratedColumn<String>(
    'challenge_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways('UNIQUE'),
  );
  static const VerificationMeta _metricOrdinalMeta = const VerificationMeta(
    'metricOrdinal',
  );
  @override
  late final GeneratedColumn<String> metricOrdinal = GeneratedColumn<String>(
    'metric_ordinal',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _totalCoinsDistributedMeta =
      const VerificationMeta('totalCoinsDistributed');
  @override
  late final GeneratedColumn<int> totalCoinsDistributed = GeneratedColumn<int>(
    'total_coins_distributed',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _calculatedAtMsMeta = const VerificationMeta(
    'calculatedAtMs',
  );
  @override
  late final GeneratedColumn<int> calculatedAtMs = GeneratedColumn<int>(
    'calculated_at_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  late final GeneratedColumnWithTypeConverter<List<String>, String>
  resultsJson = GeneratedColumn<String>(
    'results_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('[]'),
  ).withConverter<List<String>>($ChallengeResultsTable.$converterresultsJson);
  @override
  List<GeneratedColumn> get $columns => [
    id,
    challengeId,
    metricOrdinal,
    totalCoinsDistributed,
    calculatedAtMs,
    resultsJson,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'challenge_results';
  @override
  VerificationContext validateIntegrity(
    Insertable<ChallengeResult> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('challenge_id')) {
      context.handle(
        _challengeIdMeta,
        challengeId.isAcceptableOrUnknown(
          data['challenge_id']!,
          _challengeIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_challengeIdMeta);
    }
    if (data.containsKey('metric_ordinal')) {
      context.handle(
        _metricOrdinalMeta,
        metricOrdinal.isAcceptableOrUnknown(
          data['metric_ordinal']!,
          _metricOrdinalMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_metricOrdinalMeta);
    }
    if (data.containsKey('total_coins_distributed')) {
      context.handle(
        _totalCoinsDistributedMeta,
        totalCoinsDistributed.isAcceptableOrUnknown(
          data['total_coins_distributed']!,
          _totalCoinsDistributedMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_totalCoinsDistributedMeta);
    }
    if (data.containsKey('calculated_at_ms')) {
      context.handle(
        _calculatedAtMsMeta,
        calculatedAtMs.isAcceptableOrUnknown(
          data['calculated_at_ms']!,
          _calculatedAtMsMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_calculatedAtMsMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  ChallengeResult map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ChallengeResult(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      challengeId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}challenge_id'],
      )!,
      metricOrdinal: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}metric_ordinal'],
      )!,
      totalCoinsDistributed: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}total_coins_distributed'],
      )!,
      calculatedAtMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}calculated_at_ms'],
      )!,
      resultsJson: $ChallengeResultsTable.$converterresultsJson.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}results_json'],
        )!,
      ),
    );
  }

  @override
  $ChallengeResultsTable createAlias(String alias) {
    return $ChallengeResultsTable(attachedDatabase, alias);
  }

  static TypeConverter<List<String>, String> $converterresultsJson =
      const StringListConverter();
}

class ChallengeResult extends DataClass implements Insertable<ChallengeResult> {
  final int id;
  final String challengeId;
  final String metricOrdinal;
  final int totalCoinsDistributed;
  final int calculatedAtMs;
  final List<String> resultsJson;
  const ChallengeResult({
    required this.id,
    required this.challengeId,
    required this.metricOrdinal,
    required this.totalCoinsDistributed,
    required this.calculatedAtMs,
    required this.resultsJson,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['challenge_id'] = Variable<String>(challengeId);
    map['metric_ordinal'] = Variable<String>(metricOrdinal);
    map['total_coins_distributed'] = Variable<int>(totalCoinsDistributed);
    map['calculated_at_ms'] = Variable<int>(calculatedAtMs);
    {
      map['results_json'] = Variable<String>(
        $ChallengeResultsTable.$converterresultsJson.toSql(resultsJson),
      );
    }
    return map;
  }

  ChallengeResultsCompanion toCompanion(bool nullToAbsent) {
    return ChallengeResultsCompanion(
      id: Value(id),
      challengeId: Value(challengeId),
      metricOrdinal: Value(metricOrdinal),
      totalCoinsDistributed: Value(totalCoinsDistributed),
      calculatedAtMs: Value(calculatedAtMs),
      resultsJson: Value(resultsJson),
    );
  }

  factory ChallengeResult.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ChallengeResult(
      id: serializer.fromJson<int>(json['id']),
      challengeId: serializer.fromJson<String>(json['challengeId']),
      metricOrdinal: serializer.fromJson<String>(json['metricOrdinal']),
      totalCoinsDistributed: serializer.fromJson<int>(
        json['totalCoinsDistributed'],
      ),
      calculatedAtMs: serializer.fromJson<int>(json['calculatedAtMs']),
      resultsJson: serializer.fromJson<List<String>>(json['resultsJson']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'challengeId': serializer.toJson<String>(challengeId),
      'metricOrdinal': serializer.toJson<String>(metricOrdinal),
      'totalCoinsDistributed': serializer.toJson<int>(totalCoinsDistributed),
      'calculatedAtMs': serializer.toJson<int>(calculatedAtMs),
      'resultsJson': serializer.toJson<List<String>>(resultsJson),
    };
  }

  ChallengeResult copyWith({
    int? id,
    String? challengeId,
    String? metricOrdinal,
    int? totalCoinsDistributed,
    int? calculatedAtMs,
    List<String>? resultsJson,
  }) => ChallengeResult(
    id: id ?? this.id,
    challengeId: challengeId ?? this.challengeId,
    metricOrdinal: metricOrdinal ?? this.metricOrdinal,
    totalCoinsDistributed: totalCoinsDistributed ?? this.totalCoinsDistributed,
    calculatedAtMs: calculatedAtMs ?? this.calculatedAtMs,
    resultsJson: resultsJson ?? this.resultsJson,
  );
  ChallengeResult copyWithCompanion(ChallengeResultsCompanion data) {
    return ChallengeResult(
      id: data.id.present ? data.id.value : this.id,
      challengeId: data.challengeId.present
          ? data.challengeId.value
          : this.challengeId,
      metricOrdinal: data.metricOrdinal.present
          ? data.metricOrdinal.value
          : this.metricOrdinal,
      totalCoinsDistributed: data.totalCoinsDistributed.present
          ? data.totalCoinsDistributed.value
          : this.totalCoinsDistributed,
      calculatedAtMs: data.calculatedAtMs.present
          ? data.calculatedAtMs.value
          : this.calculatedAtMs,
      resultsJson: data.resultsJson.present
          ? data.resultsJson.value
          : this.resultsJson,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ChallengeResult(')
          ..write('id: $id, ')
          ..write('challengeId: $challengeId, ')
          ..write('metricOrdinal: $metricOrdinal, ')
          ..write('totalCoinsDistributed: $totalCoinsDistributed, ')
          ..write('calculatedAtMs: $calculatedAtMs, ')
          ..write('resultsJson: $resultsJson')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    challengeId,
    metricOrdinal,
    totalCoinsDistributed,
    calculatedAtMs,
    resultsJson,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ChallengeResult &&
          other.id == this.id &&
          other.challengeId == this.challengeId &&
          other.metricOrdinal == this.metricOrdinal &&
          other.totalCoinsDistributed == this.totalCoinsDistributed &&
          other.calculatedAtMs == this.calculatedAtMs &&
          other.resultsJson == this.resultsJson);
}

class ChallengeResultsCompanion extends UpdateCompanion<ChallengeResult> {
  final Value<int> id;
  final Value<String> challengeId;
  final Value<String> metricOrdinal;
  final Value<int> totalCoinsDistributed;
  final Value<int> calculatedAtMs;
  final Value<List<String>> resultsJson;
  const ChallengeResultsCompanion({
    this.id = const Value.absent(),
    this.challengeId = const Value.absent(),
    this.metricOrdinal = const Value.absent(),
    this.totalCoinsDistributed = const Value.absent(),
    this.calculatedAtMs = const Value.absent(),
    this.resultsJson = const Value.absent(),
  });
  ChallengeResultsCompanion.insert({
    this.id = const Value.absent(),
    required String challengeId,
    required String metricOrdinal,
    required int totalCoinsDistributed,
    required int calculatedAtMs,
    this.resultsJson = const Value.absent(),
  }) : challengeId = Value(challengeId),
       metricOrdinal = Value(metricOrdinal),
       totalCoinsDistributed = Value(totalCoinsDistributed),
       calculatedAtMs = Value(calculatedAtMs);
  static Insertable<ChallengeResult> custom({
    Expression<int>? id,
    Expression<String>? challengeId,
    Expression<String>? metricOrdinal,
    Expression<int>? totalCoinsDistributed,
    Expression<int>? calculatedAtMs,
    Expression<String>? resultsJson,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (challengeId != null) 'challenge_id': challengeId,
      if (metricOrdinal != null) 'metric_ordinal': metricOrdinal,
      if (totalCoinsDistributed != null)
        'total_coins_distributed': totalCoinsDistributed,
      if (calculatedAtMs != null) 'calculated_at_ms': calculatedAtMs,
      if (resultsJson != null) 'results_json': resultsJson,
    });
  }

  ChallengeResultsCompanion copyWith({
    Value<int>? id,
    Value<String>? challengeId,
    Value<String>? metricOrdinal,
    Value<int>? totalCoinsDistributed,
    Value<int>? calculatedAtMs,
    Value<List<String>>? resultsJson,
  }) {
    return ChallengeResultsCompanion(
      id: id ?? this.id,
      challengeId: challengeId ?? this.challengeId,
      metricOrdinal: metricOrdinal ?? this.metricOrdinal,
      totalCoinsDistributed:
          totalCoinsDistributed ?? this.totalCoinsDistributed,
      calculatedAtMs: calculatedAtMs ?? this.calculatedAtMs,
      resultsJson: resultsJson ?? this.resultsJson,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (challengeId.present) {
      map['challenge_id'] = Variable<String>(challengeId.value);
    }
    if (metricOrdinal.present) {
      map['metric_ordinal'] = Variable<String>(metricOrdinal.value);
    }
    if (totalCoinsDistributed.present) {
      map['total_coins_distributed'] = Variable<int>(
        totalCoinsDistributed.value,
      );
    }
    if (calculatedAtMs.present) {
      map['calculated_at_ms'] = Variable<int>(calculatedAtMs.value);
    }
    if (resultsJson.present) {
      map['results_json'] = Variable<String>(
        $ChallengeResultsTable.$converterresultsJson.toSql(resultsJson.value),
      );
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ChallengeResultsCompanion(')
          ..write('id: $id, ')
          ..write('challengeId: $challengeId, ')
          ..write('metricOrdinal: $metricOrdinal, ')
          ..write('totalCoinsDistributed: $totalCoinsDistributed, ')
          ..write('calculatedAtMs: $calculatedAtMs, ')
          ..write('resultsJson: $resultsJson')
          ..write(')'))
        .toString();
  }
}

class $WalletsTable extends Wallets with TableInfo<$WalletsTable, Wallet> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $WalletsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _userIdMeta = const VerificationMeta('userId');
  @override
  late final GeneratedColumn<String> userId = GeneratedColumn<String>(
    'user_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways('UNIQUE'),
  );
  static const VerificationMeta _balanceCoinsMeta = const VerificationMeta(
    'balanceCoins',
  );
  @override
  late final GeneratedColumn<int> balanceCoins = GeneratedColumn<int>(
    'balance_coins',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _pendingCoinsMeta = const VerificationMeta(
    'pendingCoins',
  );
  @override
  late final GeneratedColumn<int> pendingCoins = GeneratedColumn<int>(
    'pending_coins',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _lifetimeEarnedCoinsMeta =
      const VerificationMeta('lifetimeEarnedCoins');
  @override
  late final GeneratedColumn<int> lifetimeEarnedCoins = GeneratedColumn<int>(
    'lifetime_earned_coins',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _lifetimeSpentCoinsMeta =
      const VerificationMeta('lifetimeSpentCoins');
  @override
  late final GeneratedColumn<int> lifetimeSpentCoins = GeneratedColumn<int>(
    'lifetime_spent_coins',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _lastReconciledAtMsMeta =
      const VerificationMeta('lastReconciledAtMs');
  @override
  late final GeneratedColumn<int> lastReconciledAtMs = GeneratedColumn<int>(
    'last_reconciled_at_ms',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    userId,
    balanceCoins,
    pendingCoins,
    lifetimeEarnedCoins,
    lifetimeSpentCoins,
    lastReconciledAtMs,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'wallets';
  @override
  VerificationContext validateIntegrity(
    Insertable<Wallet> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('user_id')) {
      context.handle(
        _userIdMeta,
        userId.isAcceptableOrUnknown(data['user_id']!, _userIdMeta),
      );
    } else if (isInserting) {
      context.missing(_userIdMeta);
    }
    if (data.containsKey('balance_coins')) {
      context.handle(
        _balanceCoinsMeta,
        balanceCoins.isAcceptableOrUnknown(
          data['balance_coins']!,
          _balanceCoinsMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_balanceCoinsMeta);
    }
    if (data.containsKey('pending_coins')) {
      context.handle(
        _pendingCoinsMeta,
        pendingCoins.isAcceptableOrUnknown(
          data['pending_coins']!,
          _pendingCoinsMeta,
        ),
      );
    }
    if (data.containsKey('lifetime_earned_coins')) {
      context.handle(
        _lifetimeEarnedCoinsMeta,
        lifetimeEarnedCoins.isAcceptableOrUnknown(
          data['lifetime_earned_coins']!,
          _lifetimeEarnedCoinsMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_lifetimeEarnedCoinsMeta);
    }
    if (data.containsKey('lifetime_spent_coins')) {
      context.handle(
        _lifetimeSpentCoinsMeta,
        lifetimeSpentCoins.isAcceptableOrUnknown(
          data['lifetime_spent_coins']!,
          _lifetimeSpentCoinsMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_lifetimeSpentCoinsMeta);
    }
    if (data.containsKey('last_reconciled_at_ms')) {
      context.handle(
        _lastReconciledAtMsMeta,
        lastReconciledAtMs.isAcceptableOrUnknown(
          data['last_reconciled_at_ms']!,
          _lastReconciledAtMsMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Wallet map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Wallet(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      userId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}user_id'],
      )!,
      balanceCoins: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}balance_coins'],
      )!,
      pendingCoins: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}pending_coins'],
      )!,
      lifetimeEarnedCoins: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}lifetime_earned_coins'],
      )!,
      lifetimeSpentCoins: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}lifetime_spent_coins'],
      )!,
      lastReconciledAtMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}last_reconciled_at_ms'],
      ),
    );
  }

  @override
  $WalletsTable createAlias(String alias) {
    return $WalletsTable(attachedDatabase, alias);
  }
}

class Wallet extends DataClass implements Insertable<Wallet> {
  final int id;
  final String userId;
  final int balanceCoins;
  final int pendingCoins;
  final int lifetimeEarnedCoins;
  final int lifetimeSpentCoins;
  final int? lastReconciledAtMs;
  const Wallet({
    required this.id,
    required this.userId,
    required this.balanceCoins,
    required this.pendingCoins,
    required this.lifetimeEarnedCoins,
    required this.lifetimeSpentCoins,
    this.lastReconciledAtMs,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['user_id'] = Variable<String>(userId);
    map['balance_coins'] = Variable<int>(balanceCoins);
    map['pending_coins'] = Variable<int>(pendingCoins);
    map['lifetime_earned_coins'] = Variable<int>(lifetimeEarnedCoins);
    map['lifetime_spent_coins'] = Variable<int>(lifetimeSpentCoins);
    if (!nullToAbsent || lastReconciledAtMs != null) {
      map['last_reconciled_at_ms'] = Variable<int>(lastReconciledAtMs);
    }
    return map;
  }

  WalletsCompanion toCompanion(bool nullToAbsent) {
    return WalletsCompanion(
      id: Value(id),
      userId: Value(userId),
      balanceCoins: Value(balanceCoins),
      pendingCoins: Value(pendingCoins),
      lifetimeEarnedCoins: Value(lifetimeEarnedCoins),
      lifetimeSpentCoins: Value(lifetimeSpentCoins),
      lastReconciledAtMs: lastReconciledAtMs == null && nullToAbsent
          ? const Value.absent()
          : Value(lastReconciledAtMs),
    );
  }

  factory Wallet.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Wallet(
      id: serializer.fromJson<int>(json['id']),
      userId: serializer.fromJson<String>(json['userId']),
      balanceCoins: serializer.fromJson<int>(json['balanceCoins']),
      pendingCoins: serializer.fromJson<int>(json['pendingCoins']),
      lifetimeEarnedCoins: serializer.fromJson<int>(
        json['lifetimeEarnedCoins'],
      ),
      lifetimeSpentCoins: serializer.fromJson<int>(json['lifetimeSpentCoins']),
      lastReconciledAtMs: serializer.fromJson<int?>(json['lastReconciledAtMs']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'userId': serializer.toJson<String>(userId),
      'balanceCoins': serializer.toJson<int>(balanceCoins),
      'pendingCoins': serializer.toJson<int>(pendingCoins),
      'lifetimeEarnedCoins': serializer.toJson<int>(lifetimeEarnedCoins),
      'lifetimeSpentCoins': serializer.toJson<int>(lifetimeSpentCoins),
      'lastReconciledAtMs': serializer.toJson<int?>(lastReconciledAtMs),
    };
  }

  Wallet copyWith({
    int? id,
    String? userId,
    int? balanceCoins,
    int? pendingCoins,
    int? lifetimeEarnedCoins,
    int? lifetimeSpentCoins,
    Value<int?> lastReconciledAtMs = const Value.absent(),
  }) => Wallet(
    id: id ?? this.id,
    userId: userId ?? this.userId,
    balanceCoins: balanceCoins ?? this.balanceCoins,
    pendingCoins: pendingCoins ?? this.pendingCoins,
    lifetimeEarnedCoins: lifetimeEarnedCoins ?? this.lifetimeEarnedCoins,
    lifetimeSpentCoins: lifetimeSpentCoins ?? this.lifetimeSpentCoins,
    lastReconciledAtMs: lastReconciledAtMs.present
        ? lastReconciledAtMs.value
        : this.lastReconciledAtMs,
  );
  Wallet copyWithCompanion(WalletsCompanion data) {
    return Wallet(
      id: data.id.present ? data.id.value : this.id,
      userId: data.userId.present ? data.userId.value : this.userId,
      balanceCoins: data.balanceCoins.present
          ? data.balanceCoins.value
          : this.balanceCoins,
      pendingCoins: data.pendingCoins.present
          ? data.pendingCoins.value
          : this.pendingCoins,
      lifetimeEarnedCoins: data.lifetimeEarnedCoins.present
          ? data.lifetimeEarnedCoins.value
          : this.lifetimeEarnedCoins,
      lifetimeSpentCoins: data.lifetimeSpentCoins.present
          ? data.lifetimeSpentCoins.value
          : this.lifetimeSpentCoins,
      lastReconciledAtMs: data.lastReconciledAtMs.present
          ? data.lastReconciledAtMs.value
          : this.lastReconciledAtMs,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Wallet(')
          ..write('id: $id, ')
          ..write('userId: $userId, ')
          ..write('balanceCoins: $balanceCoins, ')
          ..write('pendingCoins: $pendingCoins, ')
          ..write('lifetimeEarnedCoins: $lifetimeEarnedCoins, ')
          ..write('lifetimeSpentCoins: $lifetimeSpentCoins, ')
          ..write('lastReconciledAtMs: $lastReconciledAtMs')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    userId,
    balanceCoins,
    pendingCoins,
    lifetimeEarnedCoins,
    lifetimeSpentCoins,
    lastReconciledAtMs,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Wallet &&
          other.id == this.id &&
          other.userId == this.userId &&
          other.balanceCoins == this.balanceCoins &&
          other.pendingCoins == this.pendingCoins &&
          other.lifetimeEarnedCoins == this.lifetimeEarnedCoins &&
          other.lifetimeSpentCoins == this.lifetimeSpentCoins &&
          other.lastReconciledAtMs == this.lastReconciledAtMs);
}

class WalletsCompanion extends UpdateCompanion<Wallet> {
  final Value<int> id;
  final Value<String> userId;
  final Value<int> balanceCoins;
  final Value<int> pendingCoins;
  final Value<int> lifetimeEarnedCoins;
  final Value<int> lifetimeSpentCoins;
  final Value<int?> lastReconciledAtMs;
  const WalletsCompanion({
    this.id = const Value.absent(),
    this.userId = const Value.absent(),
    this.balanceCoins = const Value.absent(),
    this.pendingCoins = const Value.absent(),
    this.lifetimeEarnedCoins = const Value.absent(),
    this.lifetimeSpentCoins = const Value.absent(),
    this.lastReconciledAtMs = const Value.absent(),
  });
  WalletsCompanion.insert({
    this.id = const Value.absent(),
    required String userId,
    required int balanceCoins,
    this.pendingCoins = const Value.absent(),
    required int lifetimeEarnedCoins,
    required int lifetimeSpentCoins,
    this.lastReconciledAtMs = const Value.absent(),
  }) : userId = Value(userId),
       balanceCoins = Value(balanceCoins),
       lifetimeEarnedCoins = Value(lifetimeEarnedCoins),
       lifetimeSpentCoins = Value(lifetimeSpentCoins);
  static Insertable<Wallet> custom({
    Expression<int>? id,
    Expression<String>? userId,
    Expression<int>? balanceCoins,
    Expression<int>? pendingCoins,
    Expression<int>? lifetimeEarnedCoins,
    Expression<int>? lifetimeSpentCoins,
    Expression<int>? lastReconciledAtMs,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (userId != null) 'user_id': userId,
      if (balanceCoins != null) 'balance_coins': balanceCoins,
      if (pendingCoins != null) 'pending_coins': pendingCoins,
      if (lifetimeEarnedCoins != null)
        'lifetime_earned_coins': lifetimeEarnedCoins,
      if (lifetimeSpentCoins != null)
        'lifetime_spent_coins': lifetimeSpentCoins,
      if (lastReconciledAtMs != null)
        'last_reconciled_at_ms': lastReconciledAtMs,
    });
  }

  WalletsCompanion copyWith({
    Value<int>? id,
    Value<String>? userId,
    Value<int>? balanceCoins,
    Value<int>? pendingCoins,
    Value<int>? lifetimeEarnedCoins,
    Value<int>? lifetimeSpentCoins,
    Value<int?>? lastReconciledAtMs,
  }) {
    return WalletsCompanion(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      balanceCoins: balanceCoins ?? this.balanceCoins,
      pendingCoins: pendingCoins ?? this.pendingCoins,
      lifetimeEarnedCoins: lifetimeEarnedCoins ?? this.lifetimeEarnedCoins,
      lifetimeSpentCoins: lifetimeSpentCoins ?? this.lifetimeSpentCoins,
      lastReconciledAtMs: lastReconciledAtMs ?? this.lastReconciledAtMs,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (userId.present) {
      map['user_id'] = Variable<String>(userId.value);
    }
    if (balanceCoins.present) {
      map['balance_coins'] = Variable<int>(balanceCoins.value);
    }
    if (pendingCoins.present) {
      map['pending_coins'] = Variable<int>(pendingCoins.value);
    }
    if (lifetimeEarnedCoins.present) {
      map['lifetime_earned_coins'] = Variable<int>(lifetimeEarnedCoins.value);
    }
    if (lifetimeSpentCoins.present) {
      map['lifetime_spent_coins'] = Variable<int>(lifetimeSpentCoins.value);
    }
    if (lastReconciledAtMs.present) {
      map['last_reconciled_at_ms'] = Variable<int>(lastReconciledAtMs.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('WalletsCompanion(')
          ..write('id: $id, ')
          ..write('userId: $userId, ')
          ..write('balanceCoins: $balanceCoins, ')
          ..write('pendingCoins: $pendingCoins, ')
          ..write('lifetimeEarnedCoins: $lifetimeEarnedCoins, ')
          ..write('lifetimeSpentCoins: $lifetimeSpentCoins, ')
          ..write('lastReconciledAtMs: $lastReconciledAtMs')
          ..write(')'))
        .toString();
  }
}

class $LedgerEntriesTable extends LedgerEntries
    with TableInfo<$LedgerEntriesTable, LedgerEntry> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $LedgerEntriesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _entryUuidMeta = const VerificationMeta(
    'entryUuid',
  );
  @override
  late final GeneratedColumn<String> entryUuid = GeneratedColumn<String>(
    'entry_uuid',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways('UNIQUE'),
  );
  static const VerificationMeta _userIdMeta = const VerificationMeta('userId');
  @override
  late final GeneratedColumn<String> userId = GeneratedColumn<String>(
    'user_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _deltaCoinsMeta = const VerificationMeta(
    'deltaCoins',
  );
  @override
  late final GeneratedColumn<int> deltaCoins = GeneratedColumn<int>(
    'delta_coins',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _reasonOrdinalMeta = const VerificationMeta(
    'reasonOrdinal',
  );
  @override
  late final GeneratedColumn<String> reasonOrdinal = GeneratedColumn<String>(
    'reason_ordinal',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _refIdMeta = const VerificationMeta('refId');
  @override
  late final GeneratedColumn<String> refId = GeneratedColumn<String>(
    'ref_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _issuerGroupIdMeta = const VerificationMeta(
    'issuerGroupId',
  );
  @override
  late final GeneratedColumn<String> issuerGroupId = GeneratedColumn<String>(
    'issuer_group_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMsMeta = const VerificationMeta(
    'createdAtMs',
  );
  @override
  late final GeneratedColumn<int> createdAtMs = GeneratedColumn<int>(
    'created_at_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    entryUuid,
    userId,
    deltaCoins,
    reasonOrdinal,
    refId,
    issuerGroupId,
    createdAtMs,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'ledger_entries';
  @override
  VerificationContext validateIntegrity(
    Insertable<LedgerEntry> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('entry_uuid')) {
      context.handle(
        _entryUuidMeta,
        entryUuid.isAcceptableOrUnknown(data['entry_uuid']!, _entryUuidMeta),
      );
    } else if (isInserting) {
      context.missing(_entryUuidMeta);
    }
    if (data.containsKey('user_id')) {
      context.handle(
        _userIdMeta,
        userId.isAcceptableOrUnknown(data['user_id']!, _userIdMeta),
      );
    } else if (isInserting) {
      context.missing(_userIdMeta);
    }
    if (data.containsKey('delta_coins')) {
      context.handle(
        _deltaCoinsMeta,
        deltaCoins.isAcceptableOrUnknown(data['delta_coins']!, _deltaCoinsMeta),
      );
    } else if (isInserting) {
      context.missing(_deltaCoinsMeta);
    }
    if (data.containsKey('reason_ordinal')) {
      context.handle(
        _reasonOrdinalMeta,
        reasonOrdinal.isAcceptableOrUnknown(
          data['reason_ordinal']!,
          _reasonOrdinalMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_reasonOrdinalMeta);
    }
    if (data.containsKey('ref_id')) {
      context.handle(
        _refIdMeta,
        refId.isAcceptableOrUnknown(data['ref_id']!, _refIdMeta),
      );
    }
    if (data.containsKey('issuer_group_id')) {
      context.handle(
        _issuerGroupIdMeta,
        issuerGroupId.isAcceptableOrUnknown(
          data['issuer_group_id']!,
          _issuerGroupIdMeta,
        ),
      );
    }
    if (data.containsKey('created_at_ms')) {
      context.handle(
        _createdAtMsMeta,
        createdAtMs.isAcceptableOrUnknown(
          data['created_at_ms']!,
          _createdAtMsMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_createdAtMsMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  LedgerEntry map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return LedgerEntry(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      entryUuid: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}entry_uuid'],
      )!,
      userId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}user_id'],
      )!,
      deltaCoins: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}delta_coins'],
      )!,
      reasonOrdinal: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}reason_ordinal'],
      )!,
      refId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}ref_id'],
      ),
      issuerGroupId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}issuer_group_id'],
      ),
      createdAtMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_at_ms'],
      )!,
    );
  }

  @override
  $LedgerEntriesTable createAlias(String alias) {
    return $LedgerEntriesTable(attachedDatabase, alias);
  }
}

class LedgerEntry extends DataClass implements Insertable<LedgerEntry> {
  final int id;
  final String entryUuid;
  final String userId;
  final int deltaCoins;
  final String reasonOrdinal;
  final String? refId;
  final String? issuerGroupId;
  final int createdAtMs;
  const LedgerEntry({
    required this.id,
    required this.entryUuid,
    required this.userId,
    required this.deltaCoins,
    required this.reasonOrdinal,
    this.refId,
    this.issuerGroupId,
    required this.createdAtMs,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['entry_uuid'] = Variable<String>(entryUuid);
    map['user_id'] = Variable<String>(userId);
    map['delta_coins'] = Variable<int>(deltaCoins);
    map['reason_ordinal'] = Variable<String>(reasonOrdinal);
    if (!nullToAbsent || refId != null) {
      map['ref_id'] = Variable<String>(refId);
    }
    if (!nullToAbsent || issuerGroupId != null) {
      map['issuer_group_id'] = Variable<String>(issuerGroupId);
    }
    map['created_at_ms'] = Variable<int>(createdAtMs);
    return map;
  }

  LedgerEntriesCompanion toCompanion(bool nullToAbsent) {
    return LedgerEntriesCompanion(
      id: Value(id),
      entryUuid: Value(entryUuid),
      userId: Value(userId),
      deltaCoins: Value(deltaCoins),
      reasonOrdinal: Value(reasonOrdinal),
      refId: refId == null && nullToAbsent
          ? const Value.absent()
          : Value(refId),
      issuerGroupId: issuerGroupId == null && nullToAbsent
          ? const Value.absent()
          : Value(issuerGroupId),
      createdAtMs: Value(createdAtMs),
    );
  }

  factory LedgerEntry.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return LedgerEntry(
      id: serializer.fromJson<int>(json['id']),
      entryUuid: serializer.fromJson<String>(json['entryUuid']),
      userId: serializer.fromJson<String>(json['userId']),
      deltaCoins: serializer.fromJson<int>(json['deltaCoins']),
      reasonOrdinal: serializer.fromJson<String>(json['reasonOrdinal']),
      refId: serializer.fromJson<String?>(json['refId']),
      issuerGroupId: serializer.fromJson<String?>(json['issuerGroupId']),
      createdAtMs: serializer.fromJson<int>(json['createdAtMs']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'entryUuid': serializer.toJson<String>(entryUuid),
      'userId': serializer.toJson<String>(userId),
      'deltaCoins': serializer.toJson<int>(deltaCoins),
      'reasonOrdinal': serializer.toJson<String>(reasonOrdinal),
      'refId': serializer.toJson<String?>(refId),
      'issuerGroupId': serializer.toJson<String?>(issuerGroupId),
      'createdAtMs': serializer.toJson<int>(createdAtMs),
    };
  }

  LedgerEntry copyWith({
    int? id,
    String? entryUuid,
    String? userId,
    int? deltaCoins,
    String? reasonOrdinal,
    Value<String?> refId = const Value.absent(),
    Value<String?> issuerGroupId = const Value.absent(),
    int? createdAtMs,
  }) => LedgerEntry(
    id: id ?? this.id,
    entryUuid: entryUuid ?? this.entryUuid,
    userId: userId ?? this.userId,
    deltaCoins: deltaCoins ?? this.deltaCoins,
    reasonOrdinal: reasonOrdinal ?? this.reasonOrdinal,
    refId: refId.present ? refId.value : this.refId,
    issuerGroupId: issuerGroupId.present
        ? issuerGroupId.value
        : this.issuerGroupId,
    createdAtMs: createdAtMs ?? this.createdAtMs,
  );
  LedgerEntry copyWithCompanion(LedgerEntriesCompanion data) {
    return LedgerEntry(
      id: data.id.present ? data.id.value : this.id,
      entryUuid: data.entryUuid.present ? data.entryUuid.value : this.entryUuid,
      userId: data.userId.present ? data.userId.value : this.userId,
      deltaCoins: data.deltaCoins.present
          ? data.deltaCoins.value
          : this.deltaCoins,
      reasonOrdinal: data.reasonOrdinal.present
          ? data.reasonOrdinal.value
          : this.reasonOrdinal,
      refId: data.refId.present ? data.refId.value : this.refId,
      issuerGroupId: data.issuerGroupId.present
          ? data.issuerGroupId.value
          : this.issuerGroupId,
      createdAtMs: data.createdAtMs.present
          ? data.createdAtMs.value
          : this.createdAtMs,
    );
  }

  @override
  String toString() {
    return (StringBuffer('LedgerEntry(')
          ..write('id: $id, ')
          ..write('entryUuid: $entryUuid, ')
          ..write('userId: $userId, ')
          ..write('deltaCoins: $deltaCoins, ')
          ..write('reasonOrdinal: $reasonOrdinal, ')
          ..write('refId: $refId, ')
          ..write('issuerGroupId: $issuerGroupId, ')
          ..write('createdAtMs: $createdAtMs')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    entryUuid,
    userId,
    deltaCoins,
    reasonOrdinal,
    refId,
    issuerGroupId,
    createdAtMs,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is LedgerEntry &&
          other.id == this.id &&
          other.entryUuid == this.entryUuid &&
          other.userId == this.userId &&
          other.deltaCoins == this.deltaCoins &&
          other.reasonOrdinal == this.reasonOrdinal &&
          other.refId == this.refId &&
          other.issuerGroupId == this.issuerGroupId &&
          other.createdAtMs == this.createdAtMs);
}

class LedgerEntriesCompanion extends UpdateCompanion<LedgerEntry> {
  final Value<int> id;
  final Value<String> entryUuid;
  final Value<String> userId;
  final Value<int> deltaCoins;
  final Value<String> reasonOrdinal;
  final Value<String?> refId;
  final Value<String?> issuerGroupId;
  final Value<int> createdAtMs;
  const LedgerEntriesCompanion({
    this.id = const Value.absent(),
    this.entryUuid = const Value.absent(),
    this.userId = const Value.absent(),
    this.deltaCoins = const Value.absent(),
    this.reasonOrdinal = const Value.absent(),
    this.refId = const Value.absent(),
    this.issuerGroupId = const Value.absent(),
    this.createdAtMs = const Value.absent(),
  });
  LedgerEntriesCompanion.insert({
    this.id = const Value.absent(),
    required String entryUuid,
    required String userId,
    required int deltaCoins,
    required String reasonOrdinal,
    this.refId = const Value.absent(),
    this.issuerGroupId = const Value.absent(),
    required int createdAtMs,
  }) : entryUuid = Value(entryUuid),
       userId = Value(userId),
       deltaCoins = Value(deltaCoins),
       reasonOrdinal = Value(reasonOrdinal),
       createdAtMs = Value(createdAtMs);
  static Insertable<LedgerEntry> custom({
    Expression<int>? id,
    Expression<String>? entryUuid,
    Expression<String>? userId,
    Expression<int>? deltaCoins,
    Expression<String>? reasonOrdinal,
    Expression<String>? refId,
    Expression<String>? issuerGroupId,
    Expression<int>? createdAtMs,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (entryUuid != null) 'entry_uuid': entryUuid,
      if (userId != null) 'user_id': userId,
      if (deltaCoins != null) 'delta_coins': deltaCoins,
      if (reasonOrdinal != null) 'reason_ordinal': reasonOrdinal,
      if (refId != null) 'ref_id': refId,
      if (issuerGroupId != null) 'issuer_group_id': issuerGroupId,
      if (createdAtMs != null) 'created_at_ms': createdAtMs,
    });
  }

  LedgerEntriesCompanion copyWith({
    Value<int>? id,
    Value<String>? entryUuid,
    Value<String>? userId,
    Value<int>? deltaCoins,
    Value<String>? reasonOrdinal,
    Value<String?>? refId,
    Value<String?>? issuerGroupId,
    Value<int>? createdAtMs,
  }) {
    return LedgerEntriesCompanion(
      id: id ?? this.id,
      entryUuid: entryUuid ?? this.entryUuid,
      userId: userId ?? this.userId,
      deltaCoins: deltaCoins ?? this.deltaCoins,
      reasonOrdinal: reasonOrdinal ?? this.reasonOrdinal,
      refId: refId ?? this.refId,
      issuerGroupId: issuerGroupId ?? this.issuerGroupId,
      createdAtMs: createdAtMs ?? this.createdAtMs,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (entryUuid.present) {
      map['entry_uuid'] = Variable<String>(entryUuid.value);
    }
    if (userId.present) {
      map['user_id'] = Variable<String>(userId.value);
    }
    if (deltaCoins.present) {
      map['delta_coins'] = Variable<int>(deltaCoins.value);
    }
    if (reasonOrdinal.present) {
      map['reason_ordinal'] = Variable<String>(reasonOrdinal.value);
    }
    if (refId.present) {
      map['ref_id'] = Variable<String>(refId.value);
    }
    if (issuerGroupId.present) {
      map['issuer_group_id'] = Variable<String>(issuerGroupId.value);
    }
    if (createdAtMs.present) {
      map['created_at_ms'] = Variable<int>(createdAtMs.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('LedgerEntriesCompanion(')
          ..write('id: $id, ')
          ..write('entryUuid: $entryUuid, ')
          ..write('userId: $userId, ')
          ..write('deltaCoins: $deltaCoins, ')
          ..write('reasonOrdinal: $reasonOrdinal, ')
          ..write('refId: $refId, ')
          ..write('issuerGroupId: $issuerGroupId, ')
          ..write('createdAtMs: $createdAtMs')
          ..write(')'))
        .toString();
  }
}

class $ProfileProgressesTable extends ProfileProgresses
    with TableInfo<$ProfileProgressesTable, ProfileProgress> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ProfileProgressesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _userIdMeta = const VerificationMeta('userId');
  @override
  late final GeneratedColumn<String> userId = GeneratedColumn<String>(
    'user_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways('UNIQUE'),
  );
  static const VerificationMeta _totalXpMeta = const VerificationMeta(
    'totalXp',
  );
  @override
  late final GeneratedColumn<int> totalXp = GeneratedColumn<int>(
    'total_xp',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _seasonXpMeta = const VerificationMeta(
    'seasonXp',
  );
  @override
  late final GeneratedColumn<int> seasonXp = GeneratedColumn<int>(
    'season_xp',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _currentSeasonIdMeta = const VerificationMeta(
    'currentSeasonId',
  );
  @override
  late final GeneratedColumn<String> currentSeasonId = GeneratedColumn<String>(
    'current_season_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _dailyStreakCountMeta = const VerificationMeta(
    'dailyStreakCount',
  );
  @override
  late final GeneratedColumn<int> dailyStreakCount = GeneratedColumn<int>(
    'daily_streak_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _streakBestMeta = const VerificationMeta(
    'streakBest',
  );
  @override
  late final GeneratedColumn<int> streakBest = GeneratedColumn<int>(
    'streak_best',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _lastStreakDayMsMeta = const VerificationMeta(
    'lastStreakDayMs',
  );
  @override
  late final GeneratedColumn<int> lastStreakDayMs = GeneratedColumn<int>(
    'last_streak_day_ms',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _hasFreezeAvailableMeta =
      const VerificationMeta('hasFreezeAvailable');
  @override
  late final GeneratedColumn<bool> hasFreezeAvailable = GeneratedColumn<bool>(
    'has_freeze_available',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("has_freeze_available" IN (0, 1))',
    ),
  );
  static const VerificationMeta _weeklySessionCountMeta =
      const VerificationMeta('weeklySessionCount');
  @override
  late final GeneratedColumn<int> weeklySessionCount = GeneratedColumn<int>(
    'weekly_session_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _monthlySessionCountMeta =
      const VerificationMeta('monthlySessionCount');
  @override
  late final GeneratedColumn<int> monthlySessionCount = GeneratedColumn<int>(
    'monthly_session_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _lifetimeSessionCountMeta =
      const VerificationMeta('lifetimeSessionCount');
  @override
  late final GeneratedColumn<int> lifetimeSessionCount = GeneratedColumn<int>(
    'lifetime_session_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _lifetimeDistanceMMeta = const VerificationMeta(
    'lifetimeDistanceM',
  );
  @override
  late final GeneratedColumn<double> lifetimeDistanceM =
      GeneratedColumn<double>(
        'lifetime_distance_m',
        aliasedName,
        false,
        type: DriftSqlType.double,
        requiredDuringInsert: true,
      );
  static const VerificationMeta _lifetimeMovingMsMeta = const VerificationMeta(
    'lifetimeMovingMs',
  );
  @override
  late final GeneratedColumn<int> lifetimeMovingMs = GeneratedColumn<int>(
    'lifetime_moving_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    userId,
    totalXp,
    seasonXp,
    currentSeasonId,
    dailyStreakCount,
    streakBest,
    lastStreakDayMs,
    hasFreezeAvailable,
    weeklySessionCount,
    monthlySessionCount,
    lifetimeSessionCount,
    lifetimeDistanceM,
    lifetimeMovingMs,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'profile_progresses';
  @override
  VerificationContext validateIntegrity(
    Insertable<ProfileProgress> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('user_id')) {
      context.handle(
        _userIdMeta,
        userId.isAcceptableOrUnknown(data['user_id']!, _userIdMeta),
      );
    } else if (isInserting) {
      context.missing(_userIdMeta);
    }
    if (data.containsKey('total_xp')) {
      context.handle(
        _totalXpMeta,
        totalXp.isAcceptableOrUnknown(data['total_xp']!, _totalXpMeta),
      );
    } else if (isInserting) {
      context.missing(_totalXpMeta);
    }
    if (data.containsKey('season_xp')) {
      context.handle(
        _seasonXpMeta,
        seasonXp.isAcceptableOrUnknown(data['season_xp']!, _seasonXpMeta),
      );
    } else if (isInserting) {
      context.missing(_seasonXpMeta);
    }
    if (data.containsKey('current_season_id')) {
      context.handle(
        _currentSeasonIdMeta,
        currentSeasonId.isAcceptableOrUnknown(
          data['current_season_id']!,
          _currentSeasonIdMeta,
        ),
      );
    }
    if (data.containsKey('daily_streak_count')) {
      context.handle(
        _dailyStreakCountMeta,
        dailyStreakCount.isAcceptableOrUnknown(
          data['daily_streak_count']!,
          _dailyStreakCountMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_dailyStreakCountMeta);
    }
    if (data.containsKey('streak_best')) {
      context.handle(
        _streakBestMeta,
        streakBest.isAcceptableOrUnknown(data['streak_best']!, _streakBestMeta),
      );
    } else if (isInserting) {
      context.missing(_streakBestMeta);
    }
    if (data.containsKey('last_streak_day_ms')) {
      context.handle(
        _lastStreakDayMsMeta,
        lastStreakDayMs.isAcceptableOrUnknown(
          data['last_streak_day_ms']!,
          _lastStreakDayMsMeta,
        ),
      );
    }
    if (data.containsKey('has_freeze_available')) {
      context.handle(
        _hasFreezeAvailableMeta,
        hasFreezeAvailable.isAcceptableOrUnknown(
          data['has_freeze_available']!,
          _hasFreezeAvailableMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_hasFreezeAvailableMeta);
    }
    if (data.containsKey('weekly_session_count')) {
      context.handle(
        _weeklySessionCountMeta,
        weeklySessionCount.isAcceptableOrUnknown(
          data['weekly_session_count']!,
          _weeklySessionCountMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_weeklySessionCountMeta);
    }
    if (data.containsKey('monthly_session_count')) {
      context.handle(
        _monthlySessionCountMeta,
        monthlySessionCount.isAcceptableOrUnknown(
          data['monthly_session_count']!,
          _monthlySessionCountMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_monthlySessionCountMeta);
    }
    if (data.containsKey('lifetime_session_count')) {
      context.handle(
        _lifetimeSessionCountMeta,
        lifetimeSessionCount.isAcceptableOrUnknown(
          data['lifetime_session_count']!,
          _lifetimeSessionCountMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_lifetimeSessionCountMeta);
    }
    if (data.containsKey('lifetime_distance_m')) {
      context.handle(
        _lifetimeDistanceMMeta,
        lifetimeDistanceM.isAcceptableOrUnknown(
          data['lifetime_distance_m']!,
          _lifetimeDistanceMMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_lifetimeDistanceMMeta);
    }
    if (data.containsKey('lifetime_moving_ms')) {
      context.handle(
        _lifetimeMovingMsMeta,
        lifetimeMovingMs.isAcceptableOrUnknown(
          data['lifetime_moving_ms']!,
          _lifetimeMovingMsMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_lifetimeMovingMsMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  ProfileProgress map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ProfileProgress(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      userId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}user_id'],
      )!,
      totalXp: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}total_xp'],
      )!,
      seasonXp: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}season_xp'],
      )!,
      currentSeasonId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}current_season_id'],
      ),
      dailyStreakCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}daily_streak_count'],
      )!,
      streakBest: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}streak_best'],
      )!,
      lastStreakDayMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}last_streak_day_ms'],
      ),
      hasFreezeAvailable: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}has_freeze_available'],
      )!,
      weeklySessionCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}weekly_session_count'],
      )!,
      monthlySessionCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}monthly_session_count'],
      )!,
      lifetimeSessionCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}lifetime_session_count'],
      )!,
      lifetimeDistanceM: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}lifetime_distance_m'],
      )!,
      lifetimeMovingMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}lifetime_moving_ms'],
      )!,
    );
  }

  @override
  $ProfileProgressesTable createAlias(String alias) {
    return $ProfileProgressesTable(attachedDatabase, alias);
  }
}

class ProfileProgress extends DataClass implements Insertable<ProfileProgress> {
  final int id;
  final String userId;
  final int totalXp;
  final int seasonXp;
  final String? currentSeasonId;
  final int dailyStreakCount;
  final int streakBest;
  final int? lastStreakDayMs;
  final bool hasFreezeAvailable;
  final int weeklySessionCount;
  final int monthlySessionCount;
  final int lifetimeSessionCount;
  final double lifetimeDistanceM;
  final int lifetimeMovingMs;
  const ProfileProgress({
    required this.id,
    required this.userId,
    required this.totalXp,
    required this.seasonXp,
    this.currentSeasonId,
    required this.dailyStreakCount,
    required this.streakBest,
    this.lastStreakDayMs,
    required this.hasFreezeAvailable,
    required this.weeklySessionCount,
    required this.monthlySessionCount,
    required this.lifetimeSessionCount,
    required this.lifetimeDistanceM,
    required this.lifetimeMovingMs,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['user_id'] = Variable<String>(userId);
    map['total_xp'] = Variable<int>(totalXp);
    map['season_xp'] = Variable<int>(seasonXp);
    if (!nullToAbsent || currentSeasonId != null) {
      map['current_season_id'] = Variable<String>(currentSeasonId);
    }
    map['daily_streak_count'] = Variable<int>(dailyStreakCount);
    map['streak_best'] = Variable<int>(streakBest);
    if (!nullToAbsent || lastStreakDayMs != null) {
      map['last_streak_day_ms'] = Variable<int>(lastStreakDayMs);
    }
    map['has_freeze_available'] = Variable<bool>(hasFreezeAvailable);
    map['weekly_session_count'] = Variable<int>(weeklySessionCount);
    map['monthly_session_count'] = Variable<int>(monthlySessionCount);
    map['lifetime_session_count'] = Variable<int>(lifetimeSessionCount);
    map['lifetime_distance_m'] = Variable<double>(lifetimeDistanceM);
    map['lifetime_moving_ms'] = Variable<int>(lifetimeMovingMs);
    return map;
  }

  ProfileProgressesCompanion toCompanion(bool nullToAbsent) {
    return ProfileProgressesCompanion(
      id: Value(id),
      userId: Value(userId),
      totalXp: Value(totalXp),
      seasonXp: Value(seasonXp),
      currentSeasonId: currentSeasonId == null && nullToAbsent
          ? const Value.absent()
          : Value(currentSeasonId),
      dailyStreakCount: Value(dailyStreakCount),
      streakBest: Value(streakBest),
      lastStreakDayMs: lastStreakDayMs == null && nullToAbsent
          ? const Value.absent()
          : Value(lastStreakDayMs),
      hasFreezeAvailable: Value(hasFreezeAvailable),
      weeklySessionCount: Value(weeklySessionCount),
      monthlySessionCount: Value(monthlySessionCount),
      lifetimeSessionCount: Value(lifetimeSessionCount),
      lifetimeDistanceM: Value(lifetimeDistanceM),
      lifetimeMovingMs: Value(lifetimeMovingMs),
    );
  }

  factory ProfileProgress.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ProfileProgress(
      id: serializer.fromJson<int>(json['id']),
      userId: serializer.fromJson<String>(json['userId']),
      totalXp: serializer.fromJson<int>(json['totalXp']),
      seasonXp: serializer.fromJson<int>(json['seasonXp']),
      currentSeasonId: serializer.fromJson<String?>(json['currentSeasonId']),
      dailyStreakCount: serializer.fromJson<int>(json['dailyStreakCount']),
      streakBest: serializer.fromJson<int>(json['streakBest']),
      lastStreakDayMs: serializer.fromJson<int?>(json['lastStreakDayMs']),
      hasFreezeAvailable: serializer.fromJson<bool>(json['hasFreezeAvailable']),
      weeklySessionCount: serializer.fromJson<int>(json['weeklySessionCount']),
      monthlySessionCount: serializer.fromJson<int>(
        json['monthlySessionCount'],
      ),
      lifetimeSessionCount: serializer.fromJson<int>(
        json['lifetimeSessionCount'],
      ),
      lifetimeDistanceM: serializer.fromJson<double>(json['lifetimeDistanceM']),
      lifetimeMovingMs: serializer.fromJson<int>(json['lifetimeMovingMs']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'userId': serializer.toJson<String>(userId),
      'totalXp': serializer.toJson<int>(totalXp),
      'seasonXp': serializer.toJson<int>(seasonXp),
      'currentSeasonId': serializer.toJson<String?>(currentSeasonId),
      'dailyStreakCount': serializer.toJson<int>(dailyStreakCount),
      'streakBest': serializer.toJson<int>(streakBest),
      'lastStreakDayMs': serializer.toJson<int?>(lastStreakDayMs),
      'hasFreezeAvailable': serializer.toJson<bool>(hasFreezeAvailable),
      'weeklySessionCount': serializer.toJson<int>(weeklySessionCount),
      'monthlySessionCount': serializer.toJson<int>(monthlySessionCount),
      'lifetimeSessionCount': serializer.toJson<int>(lifetimeSessionCount),
      'lifetimeDistanceM': serializer.toJson<double>(lifetimeDistanceM),
      'lifetimeMovingMs': serializer.toJson<int>(lifetimeMovingMs),
    };
  }

  ProfileProgress copyWith({
    int? id,
    String? userId,
    int? totalXp,
    int? seasonXp,
    Value<String?> currentSeasonId = const Value.absent(),
    int? dailyStreakCount,
    int? streakBest,
    Value<int?> lastStreakDayMs = const Value.absent(),
    bool? hasFreezeAvailable,
    int? weeklySessionCount,
    int? monthlySessionCount,
    int? lifetimeSessionCount,
    double? lifetimeDistanceM,
    int? lifetimeMovingMs,
  }) => ProfileProgress(
    id: id ?? this.id,
    userId: userId ?? this.userId,
    totalXp: totalXp ?? this.totalXp,
    seasonXp: seasonXp ?? this.seasonXp,
    currentSeasonId: currentSeasonId.present
        ? currentSeasonId.value
        : this.currentSeasonId,
    dailyStreakCount: dailyStreakCount ?? this.dailyStreakCount,
    streakBest: streakBest ?? this.streakBest,
    lastStreakDayMs: lastStreakDayMs.present
        ? lastStreakDayMs.value
        : this.lastStreakDayMs,
    hasFreezeAvailable: hasFreezeAvailable ?? this.hasFreezeAvailable,
    weeklySessionCount: weeklySessionCount ?? this.weeklySessionCount,
    monthlySessionCount: monthlySessionCount ?? this.monthlySessionCount,
    lifetimeSessionCount: lifetimeSessionCount ?? this.lifetimeSessionCount,
    lifetimeDistanceM: lifetimeDistanceM ?? this.lifetimeDistanceM,
    lifetimeMovingMs: lifetimeMovingMs ?? this.lifetimeMovingMs,
  );
  ProfileProgress copyWithCompanion(ProfileProgressesCompanion data) {
    return ProfileProgress(
      id: data.id.present ? data.id.value : this.id,
      userId: data.userId.present ? data.userId.value : this.userId,
      totalXp: data.totalXp.present ? data.totalXp.value : this.totalXp,
      seasonXp: data.seasonXp.present ? data.seasonXp.value : this.seasonXp,
      currentSeasonId: data.currentSeasonId.present
          ? data.currentSeasonId.value
          : this.currentSeasonId,
      dailyStreakCount: data.dailyStreakCount.present
          ? data.dailyStreakCount.value
          : this.dailyStreakCount,
      streakBest: data.streakBest.present
          ? data.streakBest.value
          : this.streakBest,
      lastStreakDayMs: data.lastStreakDayMs.present
          ? data.lastStreakDayMs.value
          : this.lastStreakDayMs,
      hasFreezeAvailable: data.hasFreezeAvailable.present
          ? data.hasFreezeAvailable.value
          : this.hasFreezeAvailable,
      weeklySessionCount: data.weeklySessionCount.present
          ? data.weeklySessionCount.value
          : this.weeklySessionCount,
      monthlySessionCount: data.monthlySessionCount.present
          ? data.monthlySessionCount.value
          : this.monthlySessionCount,
      lifetimeSessionCount: data.lifetimeSessionCount.present
          ? data.lifetimeSessionCount.value
          : this.lifetimeSessionCount,
      lifetimeDistanceM: data.lifetimeDistanceM.present
          ? data.lifetimeDistanceM.value
          : this.lifetimeDistanceM,
      lifetimeMovingMs: data.lifetimeMovingMs.present
          ? data.lifetimeMovingMs.value
          : this.lifetimeMovingMs,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ProfileProgress(')
          ..write('id: $id, ')
          ..write('userId: $userId, ')
          ..write('totalXp: $totalXp, ')
          ..write('seasonXp: $seasonXp, ')
          ..write('currentSeasonId: $currentSeasonId, ')
          ..write('dailyStreakCount: $dailyStreakCount, ')
          ..write('streakBest: $streakBest, ')
          ..write('lastStreakDayMs: $lastStreakDayMs, ')
          ..write('hasFreezeAvailable: $hasFreezeAvailable, ')
          ..write('weeklySessionCount: $weeklySessionCount, ')
          ..write('monthlySessionCount: $monthlySessionCount, ')
          ..write('lifetimeSessionCount: $lifetimeSessionCount, ')
          ..write('lifetimeDistanceM: $lifetimeDistanceM, ')
          ..write('lifetimeMovingMs: $lifetimeMovingMs')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    userId,
    totalXp,
    seasonXp,
    currentSeasonId,
    dailyStreakCount,
    streakBest,
    lastStreakDayMs,
    hasFreezeAvailable,
    weeklySessionCount,
    monthlySessionCount,
    lifetimeSessionCount,
    lifetimeDistanceM,
    lifetimeMovingMs,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ProfileProgress &&
          other.id == this.id &&
          other.userId == this.userId &&
          other.totalXp == this.totalXp &&
          other.seasonXp == this.seasonXp &&
          other.currentSeasonId == this.currentSeasonId &&
          other.dailyStreakCount == this.dailyStreakCount &&
          other.streakBest == this.streakBest &&
          other.lastStreakDayMs == this.lastStreakDayMs &&
          other.hasFreezeAvailable == this.hasFreezeAvailable &&
          other.weeklySessionCount == this.weeklySessionCount &&
          other.monthlySessionCount == this.monthlySessionCount &&
          other.lifetimeSessionCount == this.lifetimeSessionCount &&
          other.lifetimeDistanceM == this.lifetimeDistanceM &&
          other.lifetimeMovingMs == this.lifetimeMovingMs);
}

class ProfileProgressesCompanion extends UpdateCompanion<ProfileProgress> {
  final Value<int> id;
  final Value<String> userId;
  final Value<int> totalXp;
  final Value<int> seasonXp;
  final Value<String?> currentSeasonId;
  final Value<int> dailyStreakCount;
  final Value<int> streakBest;
  final Value<int?> lastStreakDayMs;
  final Value<bool> hasFreezeAvailable;
  final Value<int> weeklySessionCount;
  final Value<int> monthlySessionCount;
  final Value<int> lifetimeSessionCount;
  final Value<double> lifetimeDistanceM;
  final Value<int> lifetimeMovingMs;
  const ProfileProgressesCompanion({
    this.id = const Value.absent(),
    this.userId = const Value.absent(),
    this.totalXp = const Value.absent(),
    this.seasonXp = const Value.absent(),
    this.currentSeasonId = const Value.absent(),
    this.dailyStreakCount = const Value.absent(),
    this.streakBest = const Value.absent(),
    this.lastStreakDayMs = const Value.absent(),
    this.hasFreezeAvailable = const Value.absent(),
    this.weeklySessionCount = const Value.absent(),
    this.monthlySessionCount = const Value.absent(),
    this.lifetimeSessionCount = const Value.absent(),
    this.lifetimeDistanceM = const Value.absent(),
    this.lifetimeMovingMs = const Value.absent(),
  });
  ProfileProgressesCompanion.insert({
    this.id = const Value.absent(),
    required String userId,
    required int totalXp,
    required int seasonXp,
    this.currentSeasonId = const Value.absent(),
    required int dailyStreakCount,
    required int streakBest,
    this.lastStreakDayMs = const Value.absent(),
    required bool hasFreezeAvailable,
    required int weeklySessionCount,
    required int monthlySessionCount,
    required int lifetimeSessionCount,
    required double lifetimeDistanceM,
    required int lifetimeMovingMs,
  }) : userId = Value(userId),
       totalXp = Value(totalXp),
       seasonXp = Value(seasonXp),
       dailyStreakCount = Value(dailyStreakCount),
       streakBest = Value(streakBest),
       hasFreezeAvailable = Value(hasFreezeAvailable),
       weeklySessionCount = Value(weeklySessionCount),
       monthlySessionCount = Value(monthlySessionCount),
       lifetimeSessionCount = Value(lifetimeSessionCount),
       lifetimeDistanceM = Value(lifetimeDistanceM),
       lifetimeMovingMs = Value(lifetimeMovingMs);
  static Insertable<ProfileProgress> custom({
    Expression<int>? id,
    Expression<String>? userId,
    Expression<int>? totalXp,
    Expression<int>? seasonXp,
    Expression<String>? currentSeasonId,
    Expression<int>? dailyStreakCount,
    Expression<int>? streakBest,
    Expression<int>? lastStreakDayMs,
    Expression<bool>? hasFreezeAvailable,
    Expression<int>? weeklySessionCount,
    Expression<int>? monthlySessionCount,
    Expression<int>? lifetimeSessionCount,
    Expression<double>? lifetimeDistanceM,
    Expression<int>? lifetimeMovingMs,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (userId != null) 'user_id': userId,
      if (totalXp != null) 'total_xp': totalXp,
      if (seasonXp != null) 'season_xp': seasonXp,
      if (currentSeasonId != null) 'current_season_id': currentSeasonId,
      if (dailyStreakCount != null) 'daily_streak_count': dailyStreakCount,
      if (streakBest != null) 'streak_best': streakBest,
      if (lastStreakDayMs != null) 'last_streak_day_ms': lastStreakDayMs,
      if (hasFreezeAvailable != null)
        'has_freeze_available': hasFreezeAvailable,
      if (weeklySessionCount != null)
        'weekly_session_count': weeklySessionCount,
      if (monthlySessionCount != null)
        'monthly_session_count': monthlySessionCount,
      if (lifetimeSessionCount != null)
        'lifetime_session_count': lifetimeSessionCount,
      if (lifetimeDistanceM != null) 'lifetime_distance_m': lifetimeDistanceM,
      if (lifetimeMovingMs != null) 'lifetime_moving_ms': lifetimeMovingMs,
    });
  }

  ProfileProgressesCompanion copyWith({
    Value<int>? id,
    Value<String>? userId,
    Value<int>? totalXp,
    Value<int>? seasonXp,
    Value<String?>? currentSeasonId,
    Value<int>? dailyStreakCount,
    Value<int>? streakBest,
    Value<int?>? lastStreakDayMs,
    Value<bool>? hasFreezeAvailable,
    Value<int>? weeklySessionCount,
    Value<int>? monthlySessionCount,
    Value<int>? lifetimeSessionCount,
    Value<double>? lifetimeDistanceM,
    Value<int>? lifetimeMovingMs,
  }) {
    return ProfileProgressesCompanion(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      totalXp: totalXp ?? this.totalXp,
      seasonXp: seasonXp ?? this.seasonXp,
      currentSeasonId: currentSeasonId ?? this.currentSeasonId,
      dailyStreakCount: dailyStreakCount ?? this.dailyStreakCount,
      streakBest: streakBest ?? this.streakBest,
      lastStreakDayMs: lastStreakDayMs ?? this.lastStreakDayMs,
      hasFreezeAvailable: hasFreezeAvailable ?? this.hasFreezeAvailable,
      weeklySessionCount: weeklySessionCount ?? this.weeklySessionCount,
      monthlySessionCount: monthlySessionCount ?? this.monthlySessionCount,
      lifetimeSessionCount: lifetimeSessionCount ?? this.lifetimeSessionCount,
      lifetimeDistanceM: lifetimeDistanceM ?? this.lifetimeDistanceM,
      lifetimeMovingMs: lifetimeMovingMs ?? this.lifetimeMovingMs,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (userId.present) {
      map['user_id'] = Variable<String>(userId.value);
    }
    if (totalXp.present) {
      map['total_xp'] = Variable<int>(totalXp.value);
    }
    if (seasonXp.present) {
      map['season_xp'] = Variable<int>(seasonXp.value);
    }
    if (currentSeasonId.present) {
      map['current_season_id'] = Variable<String>(currentSeasonId.value);
    }
    if (dailyStreakCount.present) {
      map['daily_streak_count'] = Variable<int>(dailyStreakCount.value);
    }
    if (streakBest.present) {
      map['streak_best'] = Variable<int>(streakBest.value);
    }
    if (lastStreakDayMs.present) {
      map['last_streak_day_ms'] = Variable<int>(lastStreakDayMs.value);
    }
    if (hasFreezeAvailable.present) {
      map['has_freeze_available'] = Variable<bool>(hasFreezeAvailable.value);
    }
    if (weeklySessionCount.present) {
      map['weekly_session_count'] = Variable<int>(weeklySessionCount.value);
    }
    if (monthlySessionCount.present) {
      map['monthly_session_count'] = Variable<int>(monthlySessionCount.value);
    }
    if (lifetimeSessionCount.present) {
      map['lifetime_session_count'] = Variable<int>(lifetimeSessionCount.value);
    }
    if (lifetimeDistanceM.present) {
      map['lifetime_distance_m'] = Variable<double>(lifetimeDistanceM.value);
    }
    if (lifetimeMovingMs.present) {
      map['lifetime_moving_ms'] = Variable<int>(lifetimeMovingMs.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ProfileProgressesCompanion(')
          ..write('id: $id, ')
          ..write('userId: $userId, ')
          ..write('totalXp: $totalXp, ')
          ..write('seasonXp: $seasonXp, ')
          ..write('currentSeasonId: $currentSeasonId, ')
          ..write('dailyStreakCount: $dailyStreakCount, ')
          ..write('streakBest: $streakBest, ')
          ..write('lastStreakDayMs: $lastStreakDayMs, ')
          ..write('hasFreezeAvailable: $hasFreezeAvailable, ')
          ..write('weeklySessionCount: $weeklySessionCount, ')
          ..write('monthlySessionCount: $monthlySessionCount, ')
          ..write('lifetimeSessionCount: $lifetimeSessionCount, ')
          ..write('lifetimeDistanceM: $lifetimeDistanceM, ')
          ..write('lifetimeMovingMs: $lifetimeMovingMs')
          ..write(')'))
        .toString();
  }
}

class $XpTransactionsTable extends XpTransactions
    with TableInfo<$XpTransactionsTable, XpTransaction> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $XpTransactionsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _txUuidMeta = const VerificationMeta('txUuid');
  @override
  late final GeneratedColumn<String> txUuid = GeneratedColumn<String>(
    'tx_uuid',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways('UNIQUE'),
  );
  static const VerificationMeta _userIdMeta = const VerificationMeta('userId');
  @override
  late final GeneratedColumn<String> userId = GeneratedColumn<String>(
    'user_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _xpMeta = const VerificationMeta('xp');
  @override
  late final GeneratedColumn<int> xp = GeneratedColumn<int>(
    'xp',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sourceOrdinalMeta = const VerificationMeta(
    'sourceOrdinal',
  );
  @override
  late final GeneratedColumn<String> sourceOrdinal = GeneratedColumn<String>(
    'source_ordinal',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _refIdMeta = const VerificationMeta('refId');
  @override
  late final GeneratedColumn<String> refId = GeneratedColumn<String>(
    'ref_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMsMeta = const VerificationMeta(
    'createdAtMs',
  );
  @override
  late final GeneratedColumn<int> createdAtMs = GeneratedColumn<int>(
    'created_at_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    txUuid,
    userId,
    xp,
    sourceOrdinal,
    refId,
    createdAtMs,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'xp_transactions';
  @override
  VerificationContext validateIntegrity(
    Insertable<XpTransaction> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('tx_uuid')) {
      context.handle(
        _txUuidMeta,
        txUuid.isAcceptableOrUnknown(data['tx_uuid']!, _txUuidMeta),
      );
    } else if (isInserting) {
      context.missing(_txUuidMeta);
    }
    if (data.containsKey('user_id')) {
      context.handle(
        _userIdMeta,
        userId.isAcceptableOrUnknown(data['user_id']!, _userIdMeta),
      );
    } else if (isInserting) {
      context.missing(_userIdMeta);
    }
    if (data.containsKey('xp')) {
      context.handle(_xpMeta, xp.isAcceptableOrUnknown(data['xp']!, _xpMeta));
    } else if (isInserting) {
      context.missing(_xpMeta);
    }
    if (data.containsKey('source_ordinal')) {
      context.handle(
        _sourceOrdinalMeta,
        sourceOrdinal.isAcceptableOrUnknown(
          data['source_ordinal']!,
          _sourceOrdinalMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_sourceOrdinalMeta);
    }
    if (data.containsKey('ref_id')) {
      context.handle(
        _refIdMeta,
        refId.isAcceptableOrUnknown(data['ref_id']!, _refIdMeta),
      );
    }
    if (data.containsKey('created_at_ms')) {
      context.handle(
        _createdAtMsMeta,
        createdAtMs.isAcceptableOrUnknown(
          data['created_at_ms']!,
          _createdAtMsMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_createdAtMsMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  XpTransaction map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return XpTransaction(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      txUuid: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}tx_uuid'],
      )!,
      userId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}user_id'],
      )!,
      xp: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}xp'],
      )!,
      sourceOrdinal: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}source_ordinal'],
      )!,
      refId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}ref_id'],
      ),
      createdAtMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_at_ms'],
      )!,
    );
  }

  @override
  $XpTransactionsTable createAlias(String alias) {
    return $XpTransactionsTable(attachedDatabase, alias);
  }
}

class XpTransaction extends DataClass implements Insertable<XpTransaction> {
  final int id;
  final String txUuid;
  final String userId;
  final int xp;
  final String sourceOrdinal;
  final String? refId;
  final int createdAtMs;
  const XpTransaction({
    required this.id,
    required this.txUuid,
    required this.userId,
    required this.xp,
    required this.sourceOrdinal,
    this.refId,
    required this.createdAtMs,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['tx_uuid'] = Variable<String>(txUuid);
    map['user_id'] = Variable<String>(userId);
    map['xp'] = Variable<int>(xp);
    map['source_ordinal'] = Variable<String>(sourceOrdinal);
    if (!nullToAbsent || refId != null) {
      map['ref_id'] = Variable<String>(refId);
    }
    map['created_at_ms'] = Variable<int>(createdAtMs);
    return map;
  }

  XpTransactionsCompanion toCompanion(bool nullToAbsent) {
    return XpTransactionsCompanion(
      id: Value(id),
      txUuid: Value(txUuid),
      userId: Value(userId),
      xp: Value(xp),
      sourceOrdinal: Value(sourceOrdinal),
      refId: refId == null && nullToAbsent
          ? const Value.absent()
          : Value(refId),
      createdAtMs: Value(createdAtMs),
    );
  }

  factory XpTransaction.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return XpTransaction(
      id: serializer.fromJson<int>(json['id']),
      txUuid: serializer.fromJson<String>(json['txUuid']),
      userId: serializer.fromJson<String>(json['userId']),
      xp: serializer.fromJson<int>(json['xp']),
      sourceOrdinal: serializer.fromJson<String>(json['sourceOrdinal']),
      refId: serializer.fromJson<String?>(json['refId']),
      createdAtMs: serializer.fromJson<int>(json['createdAtMs']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'txUuid': serializer.toJson<String>(txUuid),
      'userId': serializer.toJson<String>(userId),
      'xp': serializer.toJson<int>(xp),
      'sourceOrdinal': serializer.toJson<String>(sourceOrdinal),
      'refId': serializer.toJson<String?>(refId),
      'createdAtMs': serializer.toJson<int>(createdAtMs),
    };
  }

  XpTransaction copyWith({
    int? id,
    String? txUuid,
    String? userId,
    int? xp,
    String? sourceOrdinal,
    Value<String?> refId = const Value.absent(),
    int? createdAtMs,
  }) => XpTransaction(
    id: id ?? this.id,
    txUuid: txUuid ?? this.txUuid,
    userId: userId ?? this.userId,
    xp: xp ?? this.xp,
    sourceOrdinal: sourceOrdinal ?? this.sourceOrdinal,
    refId: refId.present ? refId.value : this.refId,
    createdAtMs: createdAtMs ?? this.createdAtMs,
  );
  XpTransaction copyWithCompanion(XpTransactionsCompanion data) {
    return XpTransaction(
      id: data.id.present ? data.id.value : this.id,
      txUuid: data.txUuid.present ? data.txUuid.value : this.txUuid,
      userId: data.userId.present ? data.userId.value : this.userId,
      xp: data.xp.present ? data.xp.value : this.xp,
      sourceOrdinal: data.sourceOrdinal.present
          ? data.sourceOrdinal.value
          : this.sourceOrdinal,
      refId: data.refId.present ? data.refId.value : this.refId,
      createdAtMs: data.createdAtMs.present
          ? data.createdAtMs.value
          : this.createdAtMs,
    );
  }

  @override
  String toString() {
    return (StringBuffer('XpTransaction(')
          ..write('id: $id, ')
          ..write('txUuid: $txUuid, ')
          ..write('userId: $userId, ')
          ..write('xp: $xp, ')
          ..write('sourceOrdinal: $sourceOrdinal, ')
          ..write('refId: $refId, ')
          ..write('createdAtMs: $createdAtMs')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, txUuid, userId, xp, sourceOrdinal, refId, createdAtMs);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is XpTransaction &&
          other.id == this.id &&
          other.txUuid == this.txUuid &&
          other.userId == this.userId &&
          other.xp == this.xp &&
          other.sourceOrdinal == this.sourceOrdinal &&
          other.refId == this.refId &&
          other.createdAtMs == this.createdAtMs);
}

class XpTransactionsCompanion extends UpdateCompanion<XpTransaction> {
  final Value<int> id;
  final Value<String> txUuid;
  final Value<String> userId;
  final Value<int> xp;
  final Value<String> sourceOrdinal;
  final Value<String?> refId;
  final Value<int> createdAtMs;
  const XpTransactionsCompanion({
    this.id = const Value.absent(),
    this.txUuid = const Value.absent(),
    this.userId = const Value.absent(),
    this.xp = const Value.absent(),
    this.sourceOrdinal = const Value.absent(),
    this.refId = const Value.absent(),
    this.createdAtMs = const Value.absent(),
  });
  XpTransactionsCompanion.insert({
    this.id = const Value.absent(),
    required String txUuid,
    required String userId,
    required int xp,
    required String sourceOrdinal,
    this.refId = const Value.absent(),
    required int createdAtMs,
  }) : txUuid = Value(txUuid),
       userId = Value(userId),
       xp = Value(xp),
       sourceOrdinal = Value(sourceOrdinal),
       createdAtMs = Value(createdAtMs);
  static Insertable<XpTransaction> custom({
    Expression<int>? id,
    Expression<String>? txUuid,
    Expression<String>? userId,
    Expression<int>? xp,
    Expression<String>? sourceOrdinal,
    Expression<String>? refId,
    Expression<int>? createdAtMs,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (txUuid != null) 'tx_uuid': txUuid,
      if (userId != null) 'user_id': userId,
      if (xp != null) 'xp': xp,
      if (sourceOrdinal != null) 'source_ordinal': sourceOrdinal,
      if (refId != null) 'ref_id': refId,
      if (createdAtMs != null) 'created_at_ms': createdAtMs,
    });
  }

  XpTransactionsCompanion copyWith({
    Value<int>? id,
    Value<String>? txUuid,
    Value<String>? userId,
    Value<int>? xp,
    Value<String>? sourceOrdinal,
    Value<String?>? refId,
    Value<int>? createdAtMs,
  }) {
    return XpTransactionsCompanion(
      id: id ?? this.id,
      txUuid: txUuid ?? this.txUuid,
      userId: userId ?? this.userId,
      xp: xp ?? this.xp,
      sourceOrdinal: sourceOrdinal ?? this.sourceOrdinal,
      refId: refId ?? this.refId,
      createdAtMs: createdAtMs ?? this.createdAtMs,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (txUuid.present) {
      map['tx_uuid'] = Variable<String>(txUuid.value);
    }
    if (userId.present) {
      map['user_id'] = Variable<String>(userId.value);
    }
    if (xp.present) {
      map['xp'] = Variable<int>(xp.value);
    }
    if (sourceOrdinal.present) {
      map['source_ordinal'] = Variable<String>(sourceOrdinal.value);
    }
    if (refId.present) {
      map['ref_id'] = Variable<String>(refId.value);
    }
    if (createdAtMs.present) {
      map['created_at_ms'] = Variable<int>(createdAtMs.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('XpTransactionsCompanion(')
          ..write('id: $id, ')
          ..write('txUuid: $txUuid, ')
          ..write('userId: $userId, ')
          ..write('xp: $xp, ')
          ..write('sourceOrdinal: $sourceOrdinal, ')
          ..write('refId: $refId, ')
          ..write('createdAtMs: $createdAtMs')
          ..write(')'))
        .toString();
  }
}

class $BadgeAwardsTable extends BadgeAwards
    with TableInfo<$BadgeAwardsTable, BadgeAward> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $BadgeAwardsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _awardUuidMeta = const VerificationMeta(
    'awardUuid',
  );
  @override
  late final GeneratedColumn<String> awardUuid = GeneratedColumn<String>(
    'award_uuid',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways('UNIQUE'),
  );
  static const VerificationMeta _userIdMeta = const VerificationMeta('userId');
  @override
  late final GeneratedColumn<String> userId = GeneratedColumn<String>(
    'user_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _badgeIdMeta = const VerificationMeta(
    'badgeId',
  );
  @override
  late final GeneratedColumn<String> badgeId = GeneratedColumn<String>(
    'badge_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _triggerSessionIdMeta = const VerificationMeta(
    'triggerSessionId',
  );
  @override
  late final GeneratedColumn<String> triggerSessionId = GeneratedColumn<String>(
    'trigger_session_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _unlockedAtMsMeta = const VerificationMeta(
    'unlockedAtMs',
  );
  @override
  late final GeneratedColumn<int> unlockedAtMs = GeneratedColumn<int>(
    'unlocked_at_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _xpAwardedMeta = const VerificationMeta(
    'xpAwarded',
  );
  @override
  late final GeneratedColumn<int> xpAwarded = GeneratedColumn<int>(
    'xp_awarded',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _coinsAwardedMeta = const VerificationMeta(
    'coinsAwarded',
  );
  @override
  late final GeneratedColumn<int> coinsAwarded = GeneratedColumn<int>(
    'coins_awarded',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    awardUuid,
    userId,
    badgeId,
    triggerSessionId,
    unlockedAtMs,
    xpAwarded,
    coinsAwarded,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'badge_awards';
  @override
  VerificationContext validateIntegrity(
    Insertable<BadgeAward> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('award_uuid')) {
      context.handle(
        _awardUuidMeta,
        awardUuid.isAcceptableOrUnknown(data['award_uuid']!, _awardUuidMeta),
      );
    } else if (isInserting) {
      context.missing(_awardUuidMeta);
    }
    if (data.containsKey('user_id')) {
      context.handle(
        _userIdMeta,
        userId.isAcceptableOrUnknown(data['user_id']!, _userIdMeta),
      );
    } else if (isInserting) {
      context.missing(_userIdMeta);
    }
    if (data.containsKey('badge_id')) {
      context.handle(
        _badgeIdMeta,
        badgeId.isAcceptableOrUnknown(data['badge_id']!, _badgeIdMeta),
      );
    } else if (isInserting) {
      context.missing(_badgeIdMeta);
    }
    if (data.containsKey('trigger_session_id')) {
      context.handle(
        _triggerSessionIdMeta,
        triggerSessionId.isAcceptableOrUnknown(
          data['trigger_session_id']!,
          _triggerSessionIdMeta,
        ),
      );
    }
    if (data.containsKey('unlocked_at_ms')) {
      context.handle(
        _unlockedAtMsMeta,
        unlockedAtMs.isAcceptableOrUnknown(
          data['unlocked_at_ms']!,
          _unlockedAtMsMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_unlockedAtMsMeta);
    }
    if (data.containsKey('xp_awarded')) {
      context.handle(
        _xpAwardedMeta,
        xpAwarded.isAcceptableOrUnknown(data['xp_awarded']!, _xpAwardedMeta),
      );
    } else if (isInserting) {
      context.missing(_xpAwardedMeta);
    }
    if (data.containsKey('coins_awarded')) {
      context.handle(
        _coinsAwardedMeta,
        coinsAwarded.isAcceptableOrUnknown(
          data['coins_awarded']!,
          _coinsAwardedMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_coinsAwardedMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  BadgeAward map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return BadgeAward(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      awardUuid: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}award_uuid'],
      )!,
      userId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}user_id'],
      )!,
      badgeId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}badge_id'],
      )!,
      triggerSessionId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}trigger_session_id'],
      ),
      unlockedAtMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}unlocked_at_ms'],
      )!,
      xpAwarded: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}xp_awarded'],
      )!,
      coinsAwarded: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}coins_awarded'],
      )!,
    );
  }

  @override
  $BadgeAwardsTable createAlias(String alias) {
    return $BadgeAwardsTable(attachedDatabase, alias);
  }
}

class BadgeAward extends DataClass implements Insertable<BadgeAward> {
  final int id;
  final String awardUuid;
  final String userId;
  final String badgeId;
  final String? triggerSessionId;
  final int unlockedAtMs;
  final int xpAwarded;
  final int coinsAwarded;
  const BadgeAward({
    required this.id,
    required this.awardUuid,
    required this.userId,
    required this.badgeId,
    this.triggerSessionId,
    required this.unlockedAtMs,
    required this.xpAwarded,
    required this.coinsAwarded,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['award_uuid'] = Variable<String>(awardUuid);
    map['user_id'] = Variable<String>(userId);
    map['badge_id'] = Variable<String>(badgeId);
    if (!nullToAbsent || triggerSessionId != null) {
      map['trigger_session_id'] = Variable<String>(triggerSessionId);
    }
    map['unlocked_at_ms'] = Variable<int>(unlockedAtMs);
    map['xp_awarded'] = Variable<int>(xpAwarded);
    map['coins_awarded'] = Variable<int>(coinsAwarded);
    return map;
  }

  BadgeAwardsCompanion toCompanion(bool nullToAbsent) {
    return BadgeAwardsCompanion(
      id: Value(id),
      awardUuid: Value(awardUuid),
      userId: Value(userId),
      badgeId: Value(badgeId),
      triggerSessionId: triggerSessionId == null && nullToAbsent
          ? const Value.absent()
          : Value(triggerSessionId),
      unlockedAtMs: Value(unlockedAtMs),
      xpAwarded: Value(xpAwarded),
      coinsAwarded: Value(coinsAwarded),
    );
  }

  factory BadgeAward.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return BadgeAward(
      id: serializer.fromJson<int>(json['id']),
      awardUuid: serializer.fromJson<String>(json['awardUuid']),
      userId: serializer.fromJson<String>(json['userId']),
      badgeId: serializer.fromJson<String>(json['badgeId']),
      triggerSessionId: serializer.fromJson<String?>(json['triggerSessionId']),
      unlockedAtMs: serializer.fromJson<int>(json['unlockedAtMs']),
      xpAwarded: serializer.fromJson<int>(json['xpAwarded']),
      coinsAwarded: serializer.fromJson<int>(json['coinsAwarded']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'awardUuid': serializer.toJson<String>(awardUuid),
      'userId': serializer.toJson<String>(userId),
      'badgeId': serializer.toJson<String>(badgeId),
      'triggerSessionId': serializer.toJson<String?>(triggerSessionId),
      'unlockedAtMs': serializer.toJson<int>(unlockedAtMs),
      'xpAwarded': serializer.toJson<int>(xpAwarded),
      'coinsAwarded': serializer.toJson<int>(coinsAwarded),
    };
  }

  BadgeAward copyWith({
    int? id,
    String? awardUuid,
    String? userId,
    String? badgeId,
    Value<String?> triggerSessionId = const Value.absent(),
    int? unlockedAtMs,
    int? xpAwarded,
    int? coinsAwarded,
  }) => BadgeAward(
    id: id ?? this.id,
    awardUuid: awardUuid ?? this.awardUuid,
    userId: userId ?? this.userId,
    badgeId: badgeId ?? this.badgeId,
    triggerSessionId: triggerSessionId.present
        ? triggerSessionId.value
        : this.triggerSessionId,
    unlockedAtMs: unlockedAtMs ?? this.unlockedAtMs,
    xpAwarded: xpAwarded ?? this.xpAwarded,
    coinsAwarded: coinsAwarded ?? this.coinsAwarded,
  );
  BadgeAward copyWithCompanion(BadgeAwardsCompanion data) {
    return BadgeAward(
      id: data.id.present ? data.id.value : this.id,
      awardUuid: data.awardUuid.present ? data.awardUuid.value : this.awardUuid,
      userId: data.userId.present ? data.userId.value : this.userId,
      badgeId: data.badgeId.present ? data.badgeId.value : this.badgeId,
      triggerSessionId: data.triggerSessionId.present
          ? data.triggerSessionId.value
          : this.triggerSessionId,
      unlockedAtMs: data.unlockedAtMs.present
          ? data.unlockedAtMs.value
          : this.unlockedAtMs,
      xpAwarded: data.xpAwarded.present ? data.xpAwarded.value : this.xpAwarded,
      coinsAwarded: data.coinsAwarded.present
          ? data.coinsAwarded.value
          : this.coinsAwarded,
    );
  }

  @override
  String toString() {
    return (StringBuffer('BadgeAward(')
          ..write('id: $id, ')
          ..write('awardUuid: $awardUuid, ')
          ..write('userId: $userId, ')
          ..write('badgeId: $badgeId, ')
          ..write('triggerSessionId: $triggerSessionId, ')
          ..write('unlockedAtMs: $unlockedAtMs, ')
          ..write('xpAwarded: $xpAwarded, ')
          ..write('coinsAwarded: $coinsAwarded')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    awardUuid,
    userId,
    badgeId,
    triggerSessionId,
    unlockedAtMs,
    xpAwarded,
    coinsAwarded,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is BadgeAward &&
          other.id == this.id &&
          other.awardUuid == this.awardUuid &&
          other.userId == this.userId &&
          other.badgeId == this.badgeId &&
          other.triggerSessionId == this.triggerSessionId &&
          other.unlockedAtMs == this.unlockedAtMs &&
          other.xpAwarded == this.xpAwarded &&
          other.coinsAwarded == this.coinsAwarded);
}

class BadgeAwardsCompanion extends UpdateCompanion<BadgeAward> {
  final Value<int> id;
  final Value<String> awardUuid;
  final Value<String> userId;
  final Value<String> badgeId;
  final Value<String?> triggerSessionId;
  final Value<int> unlockedAtMs;
  final Value<int> xpAwarded;
  final Value<int> coinsAwarded;
  const BadgeAwardsCompanion({
    this.id = const Value.absent(),
    this.awardUuid = const Value.absent(),
    this.userId = const Value.absent(),
    this.badgeId = const Value.absent(),
    this.triggerSessionId = const Value.absent(),
    this.unlockedAtMs = const Value.absent(),
    this.xpAwarded = const Value.absent(),
    this.coinsAwarded = const Value.absent(),
  });
  BadgeAwardsCompanion.insert({
    this.id = const Value.absent(),
    required String awardUuid,
    required String userId,
    required String badgeId,
    this.triggerSessionId = const Value.absent(),
    required int unlockedAtMs,
    required int xpAwarded,
    required int coinsAwarded,
  }) : awardUuid = Value(awardUuid),
       userId = Value(userId),
       badgeId = Value(badgeId),
       unlockedAtMs = Value(unlockedAtMs),
       xpAwarded = Value(xpAwarded),
       coinsAwarded = Value(coinsAwarded);
  static Insertable<BadgeAward> custom({
    Expression<int>? id,
    Expression<String>? awardUuid,
    Expression<String>? userId,
    Expression<String>? badgeId,
    Expression<String>? triggerSessionId,
    Expression<int>? unlockedAtMs,
    Expression<int>? xpAwarded,
    Expression<int>? coinsAwarded,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (awardUuid != null) 'award_uuid': awardUuid,
      if (userId != null) 'user_id': userId,
      if (badgeId != null) 'badge_id': badgeId,
      if (triggerSessionId != null) 'trigger_session_id': triggerSessionId,
      if (unlockedAtMs != null) 'unlocked_at_ms': unlockedAtMs,
      if (xpAwarded != null) 'xp_awarded': xpAwarded,
      if (coinsAwarded != null) 'coins_awarded': coinsAwarded,
    });
  }

  BadgeAwardsCompanion copyWith({
    Value<int>? id,
    Value<String>? awardUuid,
    Value<String>? userId,
    Value<String>? badgeId,
    Value<String?>? triggerSessionId,
    Value<int>? unlockedAtMs,
    Value<int>? xpAwarded,
    Value<int>? coinsAwarded,
  }) {
    return BadgeAwardsCompanion(
      id: id ?? this.id,
      awardUuid: awardUuid ?? this.awardUuid,
      userId: userId ?? this.userId,
      badgeId: badgeId ?? this.badgeId,
      triggerSessionId: triggerSessionId ?? this.triggerSessionId,
      unlockedAtMs: unlockedAtMs ?? this.unlockedAtMs,
      xpAwarded: xpAwarded ?? this.xpAwarded,
      coinsAwarded: coinsAwarded ?? this.coinsAwarded,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (awardUuid.present) {
      map['award_uuid'] = Variable<String>(awardUuid.value);
    }
    if (userId.present) {
      map['user_id'] = Variable<String>(userId.value);
    }
    if (badgeId.present) {
      map['badge_id'] = Variable<String>(badgeId.value);
    }
    if (triggerSessionId.present) {
      map['trigger_session_id'] = Variable<String>(triggerSessionId.value);
    }
    if (unlockedAtMs.present) {
      map['unlocked_at_ms'] = Variable<int>(unlockedAtMs.value);
    }
    if (xpAwarded.present) {
      map['xp_awarded'] = Variable<int>(xpAwarded.value);
    }
    if (coinsAwarded.present) {
      map['coins_awarded'] = Variable<int>(coinsAwarded.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('BadgeAwardsCompanion(')
          ..write('id: $id, ')
          ..write('awardUuid: $awardUuid, ')
          ..write('userId: $userId, ')
          ..write('badgeId: $badgeId, ')
          ..write('triggerSessionId: $triggerSessionId, ')
          ..write('unlockedAtMs: $unlockedAtMs, ')
          ..write('xpAwarded: $xpAwarded, ')
          ..write('coinsAwarded: $coinsAwarded')
          ..write(')'))
        .toString();
  }
}

class $MissionProgressesTable extends MissionProgresses
    with TableInfo<$MissionProgressesTable, MissionProgress> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $MissionProgressesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _progressUuidMeta = const VerificationMeta(
    'progressUuid',
  );
  @override
  late final GeneratedColumn<String> progressUuid = GeneratedColumn<String>(
    'progress_uuid',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways('UNIQUE'),
  );
  static const VerificationMeta _userIdMeta = const VerificationMeta('userId');
  @override
  late final GeneratedColumn<String> userId = GeneratedColumn<String>(
    'user_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _missionIdMeta = const VerificationMeta(
    'missionId',
  );
  @override
  late final GeneratedColumn<String> missionId = GeneratedColumn<String>(
    'mission_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _statusOrdinalMeta = const VerificationMeta(
    'statusOrdinal',
  );
  @override
  late final GeneratedColumn<String> statusOrdinal = GeneratedColumn<String>(
    'status_ordinal',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _currentValueMeta = const VerificationMeta(
    'currentValue',
  );
  @override
  late final GeneratedColumn<double> currentValue = GeneratedColumn<double>(
    'current_value',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _targetValueMeta = const VerificationMeta(
    'targetValue',
  );
  @override
  late final GeneratedColumn<double> targetValue = GeneratedColumn<double>(
    'target_value',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _assignedAtMsMeta = const VerificationMeta(
    'assignedAtMs',
  );
  @override
  late final GeneratedColumn<int> assignedAtMs = GeneratedColumn<int>(
    'assigned_at_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _completedAtMsMeta = const VerificationMeta(
    'completedAtMs',
  );
  @override
  late final GeneratedColumn<int> completedAtMs = GeneratedColumn<int>(
    'completed_at_ms',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _completionCountMeta = const VerificationMeta(
    'completionCount',
  );
  @override
  late final GeneratedColumn<int> completionCount = GeneratedColumn<int>(
    'completion_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _contributingSessionIdsJsonMeta =
      const VerificationMeta('contributingSessionIdsJson');
  @override
  late final GeneratedColumn<String> contributingSessionIdsJson =
      GeneratedColumn<String>(
        'contributing_session_ids_json',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    progressUuid,
    userId,
    missionId,
    statusOrdinal,
    currentValue,
    targetValue,
    assignedAtMs,
    completedAtMs,
    completionCount,
    contributingSessionIdsJson,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'mission_progresses';
  @override
  VerificationContext validateIntegrity(
    Insertable<MissionProgress> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('progress_uuid')) {
      context.handle(
        _progressUuidMeta,
        progressUuid.isAcceptableOrUnknown(
          data['progress_uuid']!,
          _progressUuidMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_progressUuidMeta);
    }
    if (data.containsKey('user_id')) {
      context.handle(
        _userIdMeta,
        userId.isAcceptableOrUnknown(data['user_id']!, _userIdMeta),
      );
    } else if (isInserting) {
      context.missing(_userIdMeta);
    }
    if (data.containsKey('mission_id')) {
      context.handle(
        _missionIdMeta,
        missionId.isAcceptableOrUnknown(data['mission_id']!, _missionIdMeta),
      );
    } else if (isInserting) {
      context.missing(_missionIdMeta);
    }
    if (data.containsKey('status_ordinal')) {
      context.handle(
        _statusOrdinalMeta,
        statusOrdinal.isAcceptableOrUnknown(
          data['status_ordinal']!,
          _statusOrdinalMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_statusOrdinalMeta);
    }
    if (data.containsKey('current_value')) {
      context.handle(
        _currentValueMeta,
        currentValue.isAcceptableOrUnknown(
          data['current_value']!,
          _currentValueMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_currentValueMeta);
    }
    if (data.containsKey('target_value')) {
      context.handle(
        _targetValueMeta,
        targetValue.isAcceptableOrUnknown(
          data['target_value']!,
          _targetValueMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_targetValueMeta);
    }
    if (data.containsKey('assigned_at_ms')) {
      context.handle(
        _assignedAtMsMeta,
        assignedAtMs.isAcceptableOrUnknown(
          data['assigned_at_ms']!,
          _assignedAtMsMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_assignedAtMsMeta);
    }
    if (data.containsKey('completed_at_ms')) {
      context.handle(
        _completedAtMsMeta,
        completedAtMs.isAcceptableOrUnknown(
          data['completed_at_ms']!,
          _completedAtMsMeta,
        ),
      );
    }
    if (data.containsKey('completion_count')) {
      context.handle(
        _completionCountMeta,
        completionCount.isAcceptableOrUnknown(
          data['completion_count']!,
          _completionCountMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_completionCountMeta);
    }
    if (data.containsKey('contributing_session_ids_json')) {
      context.handle(
        _contributingSessionIdsJsonMeta,
        contributingSessionIdsJson.isAcceptableOrUnknown(
          data['contributing_session_ids_json']!,
          _contributingSessionIdsJsonMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_contributingSessionIdsJsonMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  MissionProgress map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return MissionProgress(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      progressUuid: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}progress_uuid'],
      )!,
      userId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}user_id'],
      )!,
      missionId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}mission_id'],
      )!,
      statusOrdinal: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}status_ordinal'],
      )!,
      currentValue: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}current_value'],
      )!,
      targetValue: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}target_value'],
      )!,
      assignedAtMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}assigned_at_ms'],
      )!,
      completedAtMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}completed_at_ms'],
      ),
      completionCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}completion_count'],
      )!,
      contributingSessionIdsJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}contributing_session_ids_json'],
      )!,
    );
  }

  @override
  $MissionProgressesTable createAlias(String alias) {
    return $MissionProgressesTable(attachedDatabase, alias);
  }
}

class MissionProgress extends DataClass implements Insertable<MissionProgress> {
  final int id;
  final String progressUuid;
  final String userId;
  final String missionId;
  final String statusOrdinal;
  final double currentValue;
  final double targetValue;
  final int assignedAtMs;
  final int? completedAtMs;
  final int completionCount;
  final String contributingSessionIdsJson;
  const MissionProgress({
    required this.id,
    required this.progressUuid,
    required this.userId,
    required this.missionId,
    required this.statusOrdinal,
    required this.currentValue,
    required this.targetValue,
    required this.assignedAtMs,
    this.completedAtMs,
    required this.completionCount,
    required this.contributingSessionIdsJson,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['progress_uuid'] = Variable<String>(progressUuid);
    map['user_id'] = Variable<String>(userId);
    map['mission_id'] = Variable<String>(missionId);
    map['status_ordinal'] = Variable<String>(statusOrdinal);
    map['current_value'] = Variable<double>(currentValue);
    map['target_value'] = Variable<double>(targetValue);
    map['assigned_at_ms'] = Variable<int>(assignedAtMs);
    if (!nullToAbsent || completedAtMs != null) {
      map['completed_at_ms'] = Variable<int>(completedAtMs);
    }
    map['completion_count'] = Variable<int>(completionCount);
    map['contributing_session_ids_json'] = Variable<String>(
      contributingSessionIdsJson,
    );
    return map;
  }

  MissionProgressesCompanion toCompanion(bool nullToAbsent) {
    return MissionProgressesCompanion(
      id: Value(id),
      progressUuid: Value(progressUuid),
      userId: Value(userId),
      missionId: Value(missionId),
      statusOrdinal: Value(statusOrdinal),
      currentValue: Value(currentValue),
      targetValue: Value(targetValue),
      assignedAtMs: Value(assignedAtMs),
      completedAtMs: completedAtMs == null && nullToAbsent
          ? const Value.absent()
          : Value(completedAtMs),
      completionCount: Value(completionCount),
      contributingSessionIdsJson: Value(contributingSessionIdsJson),
    );
  }

  factory MissionProgress.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return MissionProgress(
      id: serializer.fromJson<int>(json['id']),
      progressUuid: serializer.fromJson<String>(json['progressUuid']),
      userId: serializer.fromJson<String>(json['userId']),
      missionId: serializer.fromJson<String>(json['missionId']),
      statusOrdinal: serializer.fromJson<String>(json['statusOrdinal']),
      currentValue: serializer.fromJson<double>(json['currentValue']),
      targetValue: serializer.fromJson<double>(json['targetValue']),
      assignedAtMs: serializer.fromJson<int>(json['assignedAtMs']),
      completedAtMs: serializer.fromJson<int?>(json['completedAtMs']),
      completionCount: serializer.fromJson<int>(json['completionCount']),
      contributingSessionIdsJson: serializer.fromJson<String>(
        json['contributingSessionIdsJson'],
      ),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'progressUuid': serializer.toJson<String>(progressUuid),
      'userId': serializer.toJson<String>(userId),
      'missionId': serializer.toJson<String>(missionId),
      'statusOrdinal': serializer.toJson<String>(statusOrdinal),
      'currentValue': serializer.toJson<double>(currentValue),
      'targetValue': serializer.toJson<double>(targetValue),
      'assignedAtMs': serializer.toJson<int>(assignedAtMs),
      'completedAtMs': serializer.toJson<int?>(completedAtMs),
      'completionCount': serializer.toJson<int>(completionCount),
      'contributingSessionIdsJson': serializer.toJson<String>(
        contributingSessionIdsJson,
      ),
    };
  }

  MissionProgress copyWith({
    int? id,
    String? progressUuid,
    String? userId,
    String? missionId,
    String? statusOrdinal,
    double? currentValue,
    double? targetValue,
    int? assignedAtMs,
    Value<int?> completedAtMs = const Value.absent(),
    int? completionCount,
    String? contributingSessionIdsJson,
  }) => MissionProgress(
    id: id ?? this.id,
    progressUuid: progressUuid ?? this.progressUuid,
    userId: userId ?? this.userId,
    missionId: missionId ?? this.missionId,
    statusOrdinal: statusOrdinal ?? this.statusOrdinal,
    currentValue: currentValue ?? this.currentValue,
    targetValue: targetValue ?? this.targetValue,
    assignedAtMs: assignedAtMs ?? this.assignedAtMs,
    completedAtMs: completedAtMs.present
        ? completedAtMs.value
        : this.completedAtMs,
    completionCount: completionCount ?? this.completionCount,
    contributingSessionIdsJson:
        contributingSessionIdsJson ?? this.contributingSessionIdsJson,
  );
  MissionProgress copyWithCompanion(MissionProgressesCompanion data) {
    return MissionProgress(
      id: data.id.present ? data.id.value : this.id,
      progressUuid: data.progressUuid.present
          ? data.progressUuid.value
          : this.progressUuid,
      userId: data.userId.present ? data.userId.value : this.userId,
      missionId: data.missionId.present ? data.missionId.value : this.missionId,
      statusOrdinal: data.statusOrdinal.present
          ? data.statusOrdinal.value
          : this.statusOrdinal,
      currentValue: data.currentValue.present
          ? data.currentValue.value
          : this.currentValue,
      targetValue: data.targetValue.present
          ? data.targetValue.value
          : this.targetValue,
      assignedAtMs: data.assignedAtMs.present
          ? data.assignedAtMs.value
          : this.assignedAtMs,
      completedAtMs: data.completedAtMs.present
          ? data.completedAtMs.value
          : this.completedAtMs,
      completionCount: data.completionCount.present
          ? data.completionCount.value
          : this.completionCount,
      contributingSessionIdsJson: data.contributingSessionIdsJson.present
          ? data.contributingSessionIdsJson.value
          : this.contributingSessionIdsJson,
    );
  }

  @override
  String toString() {
    return (StringBuffer('MissionProgress(')
          ..write('id: $id, ')
          ..write('progressUuid: $progressUuid, ')
          ..write('userId: $userId, ')
          ..write('missionId: $missionId, ')
          ..write('statusOrdinal: $statusOrdinal, ')
          ..write('currentValue: $currentValue, ')
          ..write('targetValue: $targetValue, ')
          ..write('assignedAtMs: $assignedAtMs, ')
          ..write('completedAtMs: $completedAtMs, ')
          ..write('completionCount: $completionCount, ')
          ..write('contributingSessionIdsJson: $contributingSessionIdsJson')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    progressUuid,
    userId,
    missionId,
    statusOrdinal,
    currentValue,
    targetValue,
    assignedAtMs,
    completedAtMs,
    completionCount,
    contributingSessionIdsJson,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is MissionProgress &&
          other.id == this.id &&
          other.progressUuid == this.progressUuid &&
          other.userId == this.userId &&
          other.missionId == this.missionId &&
          other.statusOrdinal == this.statusOrdinal &&
          other.currentValue == this.currentValue &&
          other.targetValue == this.targetValue &&
          other.assignedAtMs == this.assignedAtMs &&
          other.completedAtMs == this.completedAtMs &&
          other.completionCount == this.completionCount &&
          other.contributingSessionIdsJson == this.contributingSessionIdsJson);
}

class MissionProgressesCompanion extends UpdateCompanion<MissionProgress> {
  final Value<int> id;
  final Value<String> progressUuid;
  final Value<String> userId;
  final Value<String> missionId;
  final Value<String> statusOrdinal;
  final Value<double> currentValue;
  final Value<double> targetValue;
  final Value<int> assignedAtMs;
  final Value<int?> completedAtMs;
  final Value<int> completionCount;
  final Value<String> contributingSessionIdsJson;
  const MissionProgressesCompanion({
    this.id = const Value.absent(),
    this.progressUuid = const Value.absent(),
    this.userId = const Value.absent(),
    this.missionId = const Value.absent(),
    this.statusOrdinal = const Value.absent(),
    this.currentValue = const Value.absent(),
    this.targetValue = const Value.absent(),
    this.assignedAtMs = const Value.absent(),
    this.completedAtMs = const Value.absent(),
    this.completionCount = const Value.absent(),
    this.contributingSessionIdsJson = const Value.absent(),
  });
  MissionProgressesCompanion.insert({
    this.id = const Value.absent(),
    required String progressUuid,
    required String userId,
    required String missionId,
    required String statusOrdinal,
    required double currentValue,
    required double targetValue,
    required int assignedAtMs,
    this.completedAtMs = const Value.absent(),
    required int completionCount,
    required String contributingSessionIdsJson,
  }) : progressUuid = Value(progressUuid),
       userId = Value(userId),
       missionId = Value(missionId),
       statusOrdinal = Value(statusOrdinal),
       currentValue = Value(currentValue),
       targetValue = Value(targetValue),
       assignedAtMs = Value(assignedAtMs),
       completionCount = Value(completionCount),
       contributingSessionIdsJson = Value(contributingSessionIdsJson);
  static Insertable<MissionProgress> custom({
    Expression<int>? id,
    Expression<String>? progressUuid,
    Expression<String>? userId,
    Expression<String>? missionId,
    Expression<String>? statusOrdinal,
    Expression<double>? currentValue,
    Expression<double>? targetValue,
    Expression<int>? assignedAtMs,
    Expression<int>? completedAtMs,
    Expression<int>? completionCount,
    Expression<String>? contributingSessionIdsJson,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (progressUuid != null) 'progress_uuid': progressUuid,
      if (userId != null) 'user_id': userId,
      if (missionId != null) 'mission_id': missionId,
      if (statusOrdinal != null) 'status_ordinal': statusOrdinal,
      if (currentValue != null) 'current_value': currentValue,
      if (targetValue != null) 'target_value': targetValue,
      if (assignedAtMs != null) 'assigned_at_ms': assignedAtMs,
      if (completedAtMs != null) 'completed_at_ms': completedAtMs,
      if (completionCount != null) 'completion_count': completionCount,
      if (contributingSessionIdsJson != null)
        'contributing_session_ids_json': contributingSessionIdsJson,
    });
  }

  MissionProgressesCompanion copyWith({
    Value<int>? id,
    Value<String>? progressUuid,
    Value<String>? userId,
    Value<String>? missionId,
    Value<String>? statusOrdinal,
    Value<double>? currentValue,
    Value<double>? targetValue,
    Value<int>? assignedAtMs,
    Value<int?>? completedAtMs,
    Value<int>? completionCount,
    Value<String>? contributingSessionIdsJson,
  }) {
    return MissionProgressesCompanion(
      id: id ?? this.id,
      progressUuid: progressUuid ?? this.progressUuid,
      userId: userId ?? this.userId,
      missionId: missionId ?? this.missionId,
      statusOrdinal: statusOrdinal ?? this.statusOrdinal,
      currentValue: currentValue ?? this.currentValue,
      targetValue: targetValue ?? this.targetValue,
      assignedAtMs: assignedAtMs ?? this.assignedAtMs,
      completedAtMs: completedAtMs ?? this.completedAtMs,
      completionCount: completionCount ?? this.completionCount,
      contributingSessionIdsJson:
          contributingSessionIdsJson ?? this.contributingSessionIdsJson,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (progressUuid.present) {
      map['progress_uuid'] = Variable<String>(progressUuid.value);
    }
    if (userId.present) {
      map['user_id'] = Variable<String>(userId.value);
    }
    if (missionId.present) {
      map['mission_id'] = Variable<String>(missionId.value);
    }
    if (statusOrdinal.present) {
      map['status_ordinal'] = Variable<String>(statusOrdinal.value);
    }
    if (currentValue.present) {
      map['current_value'] = Variable<double>(currentValue.value);
    }
    if (targetValue.present) {
      map['target_value'] = Variable<double>(targetValue.value);
    }
    if (assignedAtMs.present) {
      map['assigned_at_ms'] = Variable<int>(assignedAtMs.value);
    }
    if (completedAtMs.present) {
      map['completed_at_ms'] = Variable<int>(completedAtMs.value);
    }
    if (completionCount.present) {
      map['completion_count'] = Variable<int>(completionCount.value);
    }
    if (contributingSessionIdsJson.present) {
      map['contributing_session_ids_json'] = Variable<String>(
        contributingSessionIdsJson.value,
      );
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('MissionProgressesCompanion(')
          ..write('id: $id, ')
          ..write('progressUuid: $progressUuid, ')
          ..write('userId: $userId, ')
          ..write('missionId: $missionId, ')
          ..write('statusOrdinal: $statusOrdinal, ')
          ..write('currentValue: $currentValue, ')
          ..write('targetValue: $targetValue, ')
          ..write('assignedAtMs: $assignedAtMs, ')
          ..write('completedAtMs: $completedAtMs, ')
          ..write('completionCount: $completionCount, ')
          ..write('contributingSessionIdsJson: $contributingSessionIdsJson')
          ..write(')'))
        .toString();
  }
}

class $SeasonsTable extends Seasons with TableInfo<$SeasonsTable, Season> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SeasonsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _seasonUuidMeta = const VerificationMeta(
    'seasonUuid',
  );
  @override
  late final GeneratedColumn<String> seasonUuid = GeneratedColumn<String>(
    'season_uuid',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways('UNIQUE'),
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _statusOrdinalMeta = const VerificationMeta(
    'statusOrdinal',
  );
  @override
  late final GeneratedColumn<String> statusOrdinal = GeneratedColumn<String>(
    'status_ordinal',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _startsAtMsMeta = const VerificationMeta(
    'startsAtMs',
  );
  @override
  late final GeneratedColumn<int> startsAtMs = GeneratedColumn<int>(
    'starts_at_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _endsAtMsMeta = const VerificationMeta(
    'endsAtMs',
  );
  @override
  late final GeneratedColumn<int> endsAtMs = GeneratedColumn<int>(
    'ends_at_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _passXpMilestonesStrMeta =
      const VerificationMeta('passXpMilestonesStr');
  @override
  late final GeneratedColumn<String> passXpMilestonesStr =
      GeneratedColumn<String>(
        'pass_xp_milestones_str',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    seasonUuid,
    name,
    statusOrdinal,
    startsAtMs,
    endsAtMs,
    passXpMilestonesStr,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'seasons';
  @override
  VerificationContext validateIntegrity(
    Insertable<Season> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('season_uuid')) {
      context.handle(
        _seasonUuidMeta,
        seasonUuid.isAcceptableOrUnknown(data['season_uuid']!, _seasonUuidMeta),
      );
    } else if (isInserting) {
      context.missing(_seasonUuidMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('status_ordinal')) {
      context.handle(
        _statusOrdinalMeta,
        statusOrdinal.isAcceptableOrUnknown(
          data['status_ordinal']!,
          _statusOrdinalMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_statusOrdinalMeta);
    }
    if (data.containsKey('starts_at_ms')) {
      context.handle(
        _startsAtMsMeta,
        startsAtMs.isAcceptableOrUnknown(
          data['starts_at_ms']!,
          _startsAtMsMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_startsAtMsMeta);
    }
    if (data.containsKey('ends_at_ms')) {
      context.handle(
        _endsAtMsMeta,
        endsAtMs.isAcceptableOrUnknown(data['ends_at_ms']!, _endsAtMsMeta),
      );
    } else if (isInserting) {
      context.missing(_endsAtMsMeta);
    }
    if (data.containsKey('pass_xp_milestones_str')) {
      context.handle(
        _passXpMilestonesStrMeta,
        passXpMilestonesStr.isAcceptableOrUnknown(
          data['pass_xp_milestones_str']!,
          _passXpMilestonesStrMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_passXpMilestonesStrMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Season map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Season(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      seasonUuid: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}season_uuid'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      statusOrdinal: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}status_ordinal'],
      )!,
      startsAtMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}starts_at_ms'],
      )!,
      endsAtMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}ends_at_ms'],
      )!,
      passXpMilestonesStr: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}pass_xp_milestones_str'],
      )!,
    );
  }

  @override
  $SeasonsTable createAlias(String alias) {
    return $SeasonsTable(attachedDatabase, alias);
  }
}

class Season extends DataClass implements Insertable<Season> {
  final int id;
  final String seasonUuid;
  final String name;
  final String statusOrdinal;
  final int startsAtMs;
  final int endsAtMs;
  final String passXpMilestonesStr;
  const Season({
    required this.id,
    required this.seasonUuid,
    required this.name,
    required this.statusOrdinal,
    required this.startsAtMs,
    required this.endsAtMs,
    required this.passXpMilestonesStr,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['season_uuid'] = Variable<String>(seasonUuid);
    map['name'] = Variable<String>(name);
    map['status_ordinal'] = Variable<String>(statusOrdinal);
    map['starts_at_ms'] = Variable<int>(startsAtMs);
    map['ends_at_ms'] = Variable<int>(endsAtMs);
    map['pass_xp_milestones_str'] = Variable<String>(passXpMilestonesStr);
    return map;
  }

  SeasonsCompanion toCompanion(bool nullToAbsent) {
    return SeasonsCompanion(
      id: Value(id),
      seasonUuid: Value(seasonUuid),
      name: Value(name),
      statusOrdinal: Value(statusOrdinal),
      startsAtMs: Value(startsAtMs),
      endsAtMs: Value(endsAtMs),
      passXpMilestonesStr: Value(passXpMilestonesStr),
    );
  }

  factory Season.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Season(
      id: serializer.fromJson<int>(json['id']),
      seasonUuid: serializer.fromJson<String>(json['seasonUuid']),
      name: serializer.fromJson<String>(json['name']),
      statusOrdinal: serializer.fromJson<String>(json['statusOrdinal']),
      startsAtMs: serializer.fromJson<int>(json['startsAtMs']),
      endsAtMs: serializer.fromJson<int>(json['endsAtMs']),
      passXpMilestonesStr: serializer.fromJson<String>(
        json['passXpMilestonesStr'],
      ),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'seasonUuid': serializer.toJson<String>(seasonUuid),
      'name': serializer.toJson<String>(name),
      'statusOrdinal': serializer.toJson<String>(statusOrdinal),
      'startsAtMs': serializer.toJson<int>(startsAtMs),
      'endsAtMs': serializer.toJson<int>(endsAtMs),
      'passXpMilestonesStr': serializer.toJson<String>(passXpMilestonesStr),
    };
  }

  Season copyWith({
    int? id,
    String? seasonUuid,
    String? name,
    String? statusOrdinal,
    int? startsAtMs,
    int? endsAtMs,
    String? passXpMilestonesStr,
  }) => Season(
    id: id ?? this.id,
    seasonUuid: seasonUuid ?? this.seasonUuid,
    name: name ?? this.name,
    statusOrdinal: statusOrdinal ?? this.statusOrdinal,
    startsAtMs: startsAtMs ?? this.startsAtMs,
    endsAtMs: endsAtMs ?? this.endsAtMs,
    passXpMilestonesStr: passXpMilestonesStr ?? this.passXpMilestonesStr,
  );
  Season copyWithCompanion(SeasonsCompanion data) {
    return Season(
      id: data.id.present ? data.id.value : this.id,
      seasonUuid: data.seasonUuid.present
          ? data.seasonUuid.value
          : this.seasonUuid,
      name: data.name.present ? data.name.value : this.name,
      statusOrdinal: data.statusOrdinal.present
          ? data.statusOrdinal.value
          : this.statusOrdinal,
      startsAtMs: data.startsAtMs.present
          ? data.startsAtMs.value
          : this.startsAtMs,
      endsAtMs: data.endsAtMs.present ? data.endsAtMs.value : this.endsAtMs,
      passXpMilestonesStr: data.passXpMilestonesStr.present
          ? data.passXpMilestonesStr.value
          : this.passXpMilestonesStr,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Season(')
          ..write('id: $id, ')
          ..write('seasonUuid: $seasonUuid, ')
          ..write('name: $name, ')
          ..write('statusOrdinal: $statusOrdinal, ')
          ..write('startsAtMs: $startsAtMs, ')
          ..write('endsAtMs: $endsAtMs, ')
          ..write('passXpMilestonesStr: $passXpMilestonesStr')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    seasonUuid,
    name,
    statusOrdinal,
    startsAtMs,
    endsAtMs,
    passXpMilestonesStr,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Season &&
          other.id == this.id &&
          other.seasonUuid == this.seasonUuid &&
          other.name == this.name &&
          other.statusOrdinal == this.statusOrdinal &&
          other.startsAtMs == this.startsAtMs &&
          other.endsAtMs == this.endsAtMs &&
          other.passXpMilestonesStr == this.passXpMilestonesStr);
}

class SeasonsCompanion extends UpdateCompanion<Season> {
  final Value<int> id;
  final Value<String> seasonUuid;
  final Value<String> name;
  final Value<String> statusOrdinal;
  final Value<int> startsAtMs;
  final Value<int> endsAtMs;
  final Value<String> passXpMilestonesStr;
  const SeasonsCompanion({
    this.id = const Value.absent(),
    this.seasonUuid = const Value.absent(),
    this.name = const Value.absent(),
    this.statusOrdinal = const Value.absent(),
    this.startsAtMs = const Value.absent(),
    this.endsAtMs = const Value.absent(),
    this.passXpMilestonesStr = const Value.absent(),
  });
  SeasonsCompanion.insert({
    this.id = const Value.absent(),
    required String seasonUuid,
    required String name,
    required String statusOrdinal,
    required int startsAtMs,
    required int endsAtMs,
    required String passXpMilestonesStr,
  }) : seasonUuid = Value(seasonUuid),
       name = Value(name),
       statusOrdinal = Value(statusOrdinal),
       startsAtMs = Value(startsAtMs),
       endsAtMs = Value(endsAtMs),
       passXpMilestonesStr = Value(passXpMilestonesStr);
  static Insertable<Season> custom({
    Expression<int>? id,
    Expression<String>? seasonUuid,
    Expression<String>? name,
    Expression<String>? statusOrdinal,
    Expression<int>? startsAtMs,
    Expression<int>? endsAtMs,
    Expression<String>? passXpMilestonesStr,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (seasonUuid != null) 'season_uuid': seasonUuid,
      if (name != null) 'name': name,
      if (statusOrdinal != null) 'status_ordinal': statusOrdinal,
      if (startsAtMs != null) 'starts_at_ms': startsAtMs,
      if (endsAtMs != null) 'ends_at_ms': endsAtMs,
      if (passXpMilestonesStr != null)
        'pass_xp_milestones_str': passXpMilestonesStr,
    });
  }

  SeasonsCompanion copyWith({
    Value<int>? id,
    Value<String>? seasonUuid,
    Value<String>? name,
    Value<String>? statusOrdinal,
    Value<int>? startsAtMs,
    Value<int>? endsAtMs,
    Value<String>? passXpMilestonesStr,
  }) {
    return SeasonsCompanion(
      id: id ?? this.id,
      seasonUuid: seasonUuid ?? this.seasonUuid,
      name: name ?? this.name,
      statusOrdinal: statusOrdinal ?? this.statusOrdinal,
      startsAtMs: startsAtMs ?? this.startsAtMs,
      endsAtMs: endsAtMs ?? this.endsAtMs,
      passXpMilestonesStr: passXpMilestonesStr ?? this.passXpMilestonesStr,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (seasonUuid.present) {
      map['season_uuid'] = Variable<String>(seasonUuid.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (statusOrdinal.present) {
      map['status_ordinal'] = Variable<String>(statusOrdinal.value);
    }
    if (startsAtMs.present) {
      map['starts_at_ms'] = Variable<int>(startsAtMs.value);
    }
    if (endsAtMs.present) {
      map['ends_at_ms'] = Variable<int>(endsAtMs.value);
    }
    if (passXpMilestonesStr.present) {
      map['pass_xp_milestones_str'] = Variable<String>(
        passXpMilestonesStr.value,
      );
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SeasonsCompanion(')
          ..write('id: $id, ')
          ..write('seasonUuid: $seasonUuid, ')
          ..write('name: $name, ')
          ..write('statusOrdinal: $statusOrdinal, ')
          ..write('startsAtMs: $startsAtMs, ')
          ..write('endsAtMs: $endsAtMs, ')
          ..write('passXpMilestonesStr: $passXpMilestonesStr')
          ..write(')'))
        .toString();
  }
}

class $SeasonProgressesTable extends SeasonProgresses
    with TableInfo<$SeasonProgressesTable, SeasonProgress> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SeasonProgressesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _userIdMeta = const VerificationMeta('userId');
  @override
  late final GeneratedColumn<String> userId = GeneratedColumn<String>(
    'user_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _seasonIdMeta = const VerificationMeta(
    'seasonId',
  );
  @override
  late final GeneratedColumn<String> seasonId = GeneratedColumn<String>(
    'season_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _seasonXpMeta = const VerificationMeta(
    'seasonXp',
  );
  @override
  late final GeneratedColumn<int> seasonXp = GeneratedColumn<int>(
    'season_xp',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _claimedMilestoneIndicesStrMeta =
      const VerificationMeta('claimedMilestoneIndicesStr');
  @override
  late final GeneratedColumn<String> claimedMilestoneIndicesStr =
      GeneratedColumn<String>(
        'claimed_milestone_indices_str',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      );
  static const VerificationMeta _endRewardsClaimedMeta = const VerificationMeta(
    'endRewardsClaimed',
  );
  @override
  late final GeneratedColumn<bool> endRewardsClaimed = GeneratedColumn<bool>(
    'end_rewards_claimed',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("end_rewards_claimed" IN (0, 1))',
    ),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    userId,
    seasonId,
    seasonXp,
    claimedMilestoneIndicesStr,
    endRewardsClaimed,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'season_progresses';
  @override
  VerificationContext validateIntegrity(
    Insertable<SeasonProgress> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('user_id')) {
      context.handle(
        _userIdMeta,
        userId.isAcceptableOrUnknown(data['user_id']!, _userIdMeta),
      );
    } else if (isInserting) {
      context.missing(_userIdMeta);
    }
    if (data.containsKey('season_id')) {
      context.handle(
        _seasonIdMeta,
        seasonId.isAcceptableOrUnknown(data['season_id']!, _seasonIdMeta),
      );
    } else if (isInserting) {
      context.missing(_seasonIdMeta);
    }
    if (data.containsKey('season_xp')) {
      context.handle(
        _seasonXpMeta,
        seasonXp.isAcceptableOrUnknown(data['season_xp']!, _seasonXpMeta),
      );
    } else if (isInserting) {
      context.missing(_seasonXpMeta);
    }
    if (data.containsKey('claimed_milestone_indices_str')) {
      context.handle(
        _claimedMilestoneIndicesStrMeta,
        claimedMilestoneIndicesStr.isAcceptableOrUnknown(
          data['claimed_milestone_indices_str']!,
          _claimedMilestoneIndicesStrMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_claimedMilestoneIndicesStrMeta);
    }
    if (data.containsKey('end_rewards_claimed')) {
      context.handle(
        _endRewardsClaimedMeta,
        endRewardsClaimed.isAcceptableOrUnknown(
          data['end_rewards_claimed']!,
          _endRewardsClaimedMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_endRewardsClaimedMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  SeasonProgress map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SeasonProgress(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      userId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}user_id'],
      )!,
      seasonId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}season_id'],
      )!,
      seasonXp: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}season_xp'],
      )!,
      claimedMilestoneIndicesStr: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}claimed_milestone_indices_str'],
      )!,
      endRewardsClaimed: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}end_rewards_claimed'],
      )!,
    );
  }

  @override
  $SeasonProgressesTable createAlias(String alias) {
    return $SeasonProgressesTable(attachedDatabase, alias);
  }
}

class SeasonProgress extends DataClass implements Insertable<SeasonProgress> {
  final int id;
  final String userId;
  final String seasonId;
  final int seasonXp;
  final String claimedMilestoneIndicesStr;
  final bool endRewardsClaimed;
  const SeasonProgress({
    required this.id,
    required this.userId,
    required this.seasonId,
    required this.seasonXp,
    required this.claimedMilestoneIndicesStr,
    required this.endRewardsClaimed,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['user_id'] = Variable<String>(userId);
    map['season_id'] = Variable<String>(seasonId);
    map['season_xp'] = Variable<int>(seasonXp);
    map['claimed_milestone_indices_str'] = Variable<String>(
      claimedMilestoneIndicesStr,
    );
    map['end_rewards_claimed'] = Variable<bool>(endRewardsClaimed);
    return map;
  }

  SeasonProgressesCompanion toCompanion(bool nullToAbsent) {
    return SeasonProgressesCompanion(
      id: Value(id),
      userId: Value(userId),
      seasonId: Value(seasonId),
      seasonXp: Value(seasonXp),
      claimedMilestoneIndicesStr: Value(claimedMilestoneIndicesStr),
      endRewardsClaimed: Value(endRewardsClaimed),
    );
  }

  factory SeasonProgress.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SeasonProgress(
      id: serializer.fromJson<int>(json['id']),
      userId: serializer.fromJson<String>(json['userId']),
      seasonId: serializer.fromJson<String>(json['seasonId']),
      seasonXp: serializer.fromJson<int>(json['seasonXp']),
      claimedMilestoneIndicesStr: serializer.fromJson<String>(
        json['claimedMilestoneIndicesStr'],
      ),
      endRewardsClaimed: serializer.fromJson<bool>(json['endRewardsClaimed']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'userId': serializer.toJson<String>(userId),
      'seasonId': serializer.toJson<String>(seasonId),
      'seasonXp': serializer.toJson<int>(seasonXp),
      'claimedMilestoneIndicesStr': serializer.toJson<String>(
        claimedMilestoneIndicesStr,
      ),
      'endRewardsClaimed': serializer.toJson<bool>(endRewardsClaimed),
    };
  }

  SeasonProgress copyWith({
    int? id,
    String? userId,
    String? seasonId,
    int? seasonXp,
    String? claimedMilestoneIndicesStr,
    bool? endRewardsClaimed,
  }) => SeasonProgress(
    id: id ?? this.id,
    userId: userId ?? this.userId,
    seasonId: seasonId ?? this.seasonId,
    seasonXp: seasonXp ?? this.seasonXp,
    claimedMilestoneIndicesStr:
        claimedMilestoneIndicesStr ?? this.claimedMilestoneIndicesStr,
    endRewardsClaimed: endRewardsClaimed ?? this.endRewardsClaimed,
  );
  SeasonProgress copyWithCompanion(SeasonProgressesCompanion data) {
    return SeasonProgress(
      id: data.id.present ? data.id.value : this.id,
      userId: data.userId.present ? data.userId.value : this.userId,
      seasonId: data.seasonId.present ? data.seasonId.value : this.seasonId,
      seasonXp: data.seasonXp.present ? data.seasonXp.value : this.seasonXp,
      claimedMilestoneIndicesStr: data.claimedMilestoneIndicesStr.present
          ? data.claimedMilestoneIndicesStr.value
          : this.claimedMilestoneIndicesStr,
      endRewardsClaimed: data.endRewardsClaimed.present
          ? data.endRewardsClaimed.value
          : this.endRewardsClaimed,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SeasonProgress(')
          ..write('id: $id, ')
          ..write('userId: $userId, ')
          ..write('seasonId: $seasonId, ')
          ..write('seasonXp: $seasonXp, ')
          ..write('claimedMilestoneIndicesStr: $claimedMilestoneIndicesStr, ')
          ..write('endRewardsClaimed: $endRewardsClaimed')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    userId,
    seasonId,
    seasonXp,
    claimedMilestoneIndicesStr,
    endRewardsClaimed,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SeasonProgress &&
          other.id == this.id &&
          other.userId == this.userId &&
          other.seasonId == this.seasonId &&
          other.seasonXp == this.seasonXp &&
          other.claimedMilestoneIndicesStr == this.claimedMilestoneIndicesStr &&
          other.endRewardsClaimed == this.endRewardsClaimed);
}

class SeasonProgressesCompanion extends UpdateCompanion<SeasonProgress> {
  final Value<int> id;
  final Value<String> userId;
  final Value<String> seasonId;
  final Value<int> seasonXp;
  final Value<String> claimedMilestoneIndicesStr;
  final Value<bool> endRewardsClaimed;
  const SeasonProgressesCompanion({
    this.id = const Value.absent(),
    this.userId = const Value.absent(),
    this.seasonId = const Value.absent(),
    this.seasonXp = const Value.absent(),
    this.claimedMilestoneIndicesStr = const Value.absent(),
    this.endRewardsClaimed = const Value.absent(),
  });
  SeasonProgressesCompanion.insert({
    this.id = const Value.absent(),
    required String userId,
    required String seasonId,
    required int seasonXp,
    required String claimedMilestoneIndicesStr,
    required bool endRewardsClaimed,
  }) : userId = Value(userId),
       seasonId = Value(seasonId),
       seasonXp = Value(seasonXp),
       claimedMilestoneIndicesStr = Value(claimedMilestoneIndicesStr),
       endRewardsClaimed = Value(endRewardsClaimed);
  static Insertable<SeasonProgress> custom({
    Expression<int>? id,
    Expression<String>? userId,
    Expression<String>? seasonId,
    Expression<int>? seasonXp,
    Expression<String>? claimedMilestoneIndicesStr,
    Expression<bool>? endRewardsClaimed,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (userId != null) 'user_id': userId,
      if (seasonId != null) 'season_id': seasonId,
      if (seasonXp != null) 'season_xp': seasonXp,
      if (claimedMilestoneIndicesStr != null)
        'claimed_milestone_indices_str': claimedMilestoneIndicesStr,
      if (endRewardsClaimed != null) 'end_rewards_claimed': endRewardsClaimed,
    });
  }

  SeasonProgressesCompanion copyWith({
    Value<int>? id,
    Value<String>? userId,
    Value<String>? seasonId,
    Value<int>? seasonXp,
    Value<String>? claimedMilestoneIndicesStr,
    Value<bool>? endRewardsClaimed,
  }) {
    return SeasonProgressesCompanion(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      seasonId: seasonId ?? this.seasonId,
      seasonXp: seasonXp ?? this.seasonXp,
      claimedMilestoneIndicesStr:
          claimedMilestoneIndicesStr ?? this.claimedMilestoneIndicesStr,
      endRewardsClaimed: endRewardsClaimed ?? this.endRewardsClaimed,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (userId.present) {
      map['user_id'] = Variable<String>(userId.value);
    }
    if (seasonId.present) {
      map['season_id'] = Variable<String>(seasonId.value);
    }
    if (seasonXp.present) {
      map['season_xp'] = Variable<int>(seasonXp.value);
    }
    if (claimedMilestoneIndicesStr.present) {
      map['claimed_milestone_indices_str'] = Variable<String>(
        claimedMilestoneIndicesStr.value,
      );
    }
    if (endRewardsClaimed.present) {
      map['end_rewards_claimed'] = Variable<bool>(endRewardsClaimed.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SeasonProgressesCompanion(')
          ..write('id: $id, ')
          ..write('userId: $userId, ')
          ..write('seasonId: $seasonId, ')
          ..write('seasonXp: $seasonXp, ')
          ..write('claimedMilestoneIndicesStr: $claimedMilestoneIndicesStr, ')
          ..write('endRewardsClaimed: $endRewardsClaimed')
          ..write(')'))
        .toString();
  }
}

class $CoachingGroupsTable extends CoachingGroups
    with TableInfo<$CoachingGroupsTable, CoachingGroup> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CoachingGroupsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _groupUuidMeta = const VerificationMeta(
    'groupUuid',
  );
  @override
  late final GeneratedColumn<String> groupUuid = GeneratedColumn<String>(
    'group_uuid',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways('UNIQUE'),
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _logoUrlMeta = const VerificationMeta(
    'logoUrl',
  );
  @override
  late final GeneratedColumn<String> logoUrl = GeneratedColumn<String>(
    'logo_url',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _coachUserIdMeta = const VerificationMeta(
    'coachUserId',
  );
  @override
  late final GeneratedColumn<String> coachUserId = GeneratedColumn<String>(
    'coach_user_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _descriptionMeta = const VerificationMeta(
    'description',
  );
  @override
  late final GeneratedColumn<String> description = GeneratedColumn<String>(
    'description',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _cityMeta = const VerificationMeta('city');
  @override
  late final GeneratedColumn<String> city = GeneratedColumn<String>(
    'city',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _inviteCodeMeta = const VerificationMeta(
    'inviteCode',
  );
  @override
  late final GeneratedColumn<String> inviteCode = GeneratedColumn<String>(
    'invite_code',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways('UNIQUE'),
  );
  static const VerificationMeta _inviteEnabledMeta = const VerificationMeta(
    'inviteEnabled',
  );
  @override
  late final GeneratedColumn<bool> inviteEnabled = GeneratedColumn<bool>(
    'invite_enabled',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("invite_enabled" IN (0, 1))',
    ),
  );
  static const VerificationMeta _createdAtMsMeta = const VerificationMeta(
    'createdAtMs',
  );
  @override
  late final GeneratedColumn<int> createdAtMs = GeneratedColumn<int>(
    'created_at_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    groupUuid,
    name,
    logoUrl,
    coachUserId,
    description,
    city,
    inviteCode,
    inviteEnabled,
    createdAtMs,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'coaching_groups';
  @override
  VerificationContext validateIntegrity(
    Insertable<CoachingGroup> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('group_uuid')) {
      context.handle(
        _groupUuidMeta,
        groupUuid.isAcceptableOrUnknown(data['group_uuid']!, _groupUuidMeta),
      );
    } else if (isInserting) {
      context.missing(_groupUuidMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('logo_url')) {
      context.handle(
        _logoUrlMeta,
        logoUrl.isAcceptableOrUnknown(data['logo_url']!, _logoUrlMeta),
      );
    }
    if (data.containsKey('coach_user_id')) {
      context.handle(
        _coachUserIdMeta,
        coachUserId.isAcceptableOrUnknown(
          data['coach_user_id']!,
          _coachUserIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_coachUserIdMeta);
    }
    if (data.containsKey('description')) {
      context.handle(
        _descriptionMeta,
        description.isAcceptableOrUnknown(
          data['description']!,
          _descriptionMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_descriptionMeta);
    }
    if (data.containsKey('city')) {
      context.handle(
        _cityMeta,
        city.isAcceptableOrUnknown(data['city']!, _cityMeta),
      );
    } else if (isInserting) {
      context.missing(_cityMeta);
    }
    if (data.containsKey('invite_code')) {
      context.handle(
        _inviteCodeMeta,
        inviteCode.isAcceptableOrUnknown(data['invite_code']!, _inviteCodeMeta),
      );
    }
    if (data.containsKey('invite_enabled')) {
      context.handle(
        _inviteEnabledMeta,
        inviteEnabled.isAcceptableOrUnknown(
          data['invite_enabled']!,
          _inviteEnabledMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_inviteEnabledMeta);
    }
    if (data.containsKey('created_at_ms')) {
      context.handle(
        _createdAtMsMeta,
        createdAtMs.isAcceptableOrUnknown(
          data['created_at_ms']!,
          _createdAtMsMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_createdAtMsMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  CoachingGroup map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CoachingGroup(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      groupUuid: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}group_uuid'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      logoUrl: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}logo_url'],
      ),
      coachUserId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}coach_user_id'],
      )!,
      description: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}description'],
      )!,
      city: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}city'],
      )!,
      inviteCode: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}invite_code'],
      ),
      inviteEnabled: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}invite_enabled'],
      )!,
      createdAtMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_at_ms'],
      )!,
    );
  }

  @override
  $CoachingGroupsTable createAlias(String alias) {
    return $CoachingGroupsTable(attachedDatabase, alias);
  }
}

class CoachingGroup extends DataClass implements Insertable<CoachingGroup> {
  final int id;
  final String groupUuid;
  final String name;
  final String? logoUrl;
  final String coachUserId;
  final String description;
  final String city;
  final String? inviteCode;
  final bool inviteEnabled;
  final int createdAtMs;
  const CoachingGroup({
    required this.id,
    required this.groupUuid,
    required this.name,
    this.logoUrl,
    required this.coachUserId,
    required this.description,
    required this.city,
    this.inviteCode,
    required this.inviteEnabled,
    required this.createdAtMs,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['group_uuid'] = Variable<String>(groupUuid);
    map['name'] = Variable<String>(name);
    if (!nullToAbsent || logoUrl != null) {
      map['logo_url'] = Variable<String>(logoUrl);
    }
    map['coach_user_id'] = Variable<String>(coachUserId);
    map['description'] = Variable<String>(description);
    map['city'] = Variable<String>(city);
    if (!nullToAbsent || inviteCode != null) {
      map['invite_code'] = Variable<String>(inviteCode);
    }
    map['invite_enabled'] = Variable<bool>(inviteEnabled);
    map['created_at_ms'] = Variable<int>(createdAtMs);
    return map;
  }

  CoachingGroupsCompanion toCompanion(bool nullToAbsent) {
    return CoachingGroupsCompanion(
      id: Value(id),
      groupUuid: Value(groupUuid),
      name: Value(name),
      logoUrl: logoUrl == null && nullToAbsent
          ? const Value.absent()
          : Value(logoUrl),
      coachUserId: Value(coachUserId),
      description: Value(description),
      city: Value(city),
      inviteCode: inviteCode == null && nullToAbsent
          ? const Value.absent()
          : Value(inviteCode),
      inviteEnabled: Value(inviteEnabled),
      createdAtMs: Value(createdAtMs),
    );
  }

  factory CoachingGroup.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CoachingGroup(
      id: serializer.fromJson<int>(json['id']),
      groupUuid: serializer.fromJson<String>(json['groupUuid']),
      name: serializer.fromJson<String>(json['name']),
      logoUrl: serializer.fromJson<String?>(json['logoUrl']),
      coachUserId: serializer.fromJson<String>(json['coachUserId']),
      description: serializer.fromJson<String>(json['description']),
      city: serializer.fromJson<String>(json['city']),
      inviteCode: serializer.fromJson<String?>(json['inviteCode']),
      inviteEnabled: serializer.fromJson<bool>(json['inviteEnabled']),
      createdAtMs: serializer.fromJson<int>(json['createdAtMs']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'groupUuid': serializer.toJson<String>(groupUuid),
      'name': serializer.toJson<String>(name),
      'logoUrl': serializer.toJson<String?>(logoUrl),
      'coachUserId': serializer.toJson<String>(coachUserId),
      'description': serializer.toJson<String>(description),
      'city': serializer.toJson<String>(city),
      'inviteCode': serializer.toJson<String?>(inviteCode),
      'inviteEnabled': serializer.toJson<bool>(inviteEnabled),
      'createdAtMs': serializer.toJson<int>(createdAtMs),
    };
  }

  CoachingGroup copyWith({
    int? id,
    String? groupUuid,
    String? name,
    Value<String?> logoUrl = const Value.absent(),
    String? coachUserId,
    String? description,
    String? city,
    Value<String?> inviteCode = const Value.absent(),
    bool? inviteEnabled,
    int? createdAtMs,
  }) => CoachingGroup(
    id: id ?? this.id,
    groupUuid: groupUuid ?? this.groupUuid,
    name: name ?? this.name,
    logoUrl: logoUrl.present ? logoUrl.value : this.logoUrl,
    coachUserId: coachUserId ?? this.coachUserId,
    description: description ?? this.description,
    city: city ?? this.city,
    inviteCode: inviteCode.present ? inviteCode.value : this.inviteCode,
    inviteEnabled: inviteEnabled ?? this.inviteEnabled,
    createdAtMs: createdAtMs ?? this.createdAtMs,
  );
  CoachingGroup copyWithCompanion(CoachingGroupsCompanion data) {
    return CoachingGroup(
      id: data.id.present ? data.id.value : this.id,
      groupUuid: data.groupUuid.present ? data.groupUuid.value : this.groupUuid,
      name: data.name.present ? data.name.value : this.name,
      logoUrl: data.logoUrl.present ? data.logoUrl.value : this.logoUrl,
      coachUserId: data.coachUserId.present
          ? data.coachUserId.value
          : this.coachUserId,
      description: data.description.present
          ? data.description.value
          : this.description,
      city: data.city.present ? data.city.value : this.city,
      inviteCode: data.inviteCode.present
          ? data.inviteCode.value
          : this.inviteCode,
      inviteEnabled: data.inviteEnabled.present
          ? data.inviteEnabled.value
          : this.inviteEnabled,
      createdAtMs: data.createdAtMs.present
          ? data.createdAtMs.value
          : this.createdAtMs,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CoachingGroup(')
          ..write('id: $id, ')
          ..write('groupUuid: $groupUuid, ')
          ..write('name: $name, ')
          ..write('logoUrl: $logoUrl, ')
          ..write('coachUserId: $coachUserId, ')
          ..write('description: $description, ')
          ..write('city: $city, ')
          ..write('inviteCode: $inviteCode, ')
          ..write('inviteEnabled: $inviteEnabled, ')
          ..write('createdAtMs: $createdAtMs')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    groupUuid,
    name,
    logoUrl,
    coachUserId,
    description,
    city,
    inviteCode,
    inviteEnabled,
    createdAtMs,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CoachingGroup &&
          other.id == this.id &&
          other.groupUuid == this.groupUuid &&
          other.name == this.name &&
          other.logoUrl == this.logoUrl &&
          other.coachUserId == this.coachUserId &&
          other.description == this.description &&
          other.city == this.city &&
          other.inviteCode == this.inviteCode &&
          other.inviteEnabled == this.inviteEnabled &&
          other.createdAtMs == this.createdAtMs);
}

class CoachingGroupsCompanion extends UpdateCompanion<CoachingGroup> {
  final Value<int> id;
  final Value<String> groupUuid;
  final Value<String> name;
  final Value<String?> logoUrl;
  final Value<String> coachUserId;
  final Value<String> description;
  final Value<String> city;
  final Value<String?> inviteCode;
  final Value<bool> inviteEnabled;
  final Value<int> createdAtMs;
  const CoachingGroupsCompanion({
    this.id = const Value.absent(),
    this.groupUuid = const Value.absent(),
    this.name = const Value.absent(),
    this.logoUrl = const Value.absent(),
    this.coachUserId = const Value.absent(),
    this.description = const Value.absent(),
    this.city = const Value.absent(),
    this.inviteCode = const Value.absent(),
    this.inviteEnabled = const Value.absent(),
    this.createdAtMs = const Value.absent(),
  });
  CoachingGroupsCompanion.insert({
    this.id = const Value.absent(),
    required String groupUuid,
    required String name,
    this.logoUrl = const Value.absent(),
    required String coachUserId,
    required String description,
    required String city,
    this.inviteCode = const Value.absent(),
    required bool inviteEnabled,
    required int createdAtMs,
  }) : groupUuid = Value(groupUuid),
       name = Value(name),
       coachUserId = Value(coachUserId),
       description = Value(description),
       city = Value(city),
       inviteEnabled = Value(inviteEnabled),
       createdAtMs = Value(createdAtMs);
  static Insertable<CoachingGroup> custom({
    Expression<int>? id,
    Expression<String>? groupUuid,
    Expression<String>? name,
    Expression<String>? logoUrl,
    Expression<String>? coachUserId,
    Expression<String>? description,
    Expression<String>? city,
    Expression<String>? inviteCode,
    Expression<bool>? inviteEnabled,
    Expression<int>? createdAtMs,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (groupUuid != null) 'group_uuid': groupUuid,
      if (name != null) 'name': name,
      if (logoUrl != null) 'logo_url': logoUrl,
      if (coachUserId != null) 'coach_user_id': coachUserId,
      if (description != null) 'description': description,
      if (city != null) 'city': city,
      if (inviteCode != null) 'invite_code': inviteCode,
      if (inviteEnabled != null) 'invite_enabled': inviteEnabled,
      if (createdAtMs != null) 'created_at_ms': createdAtMs,
    });
  }

  CoachingGroupsCompanion copyWith({
    Value<int>? id,
    Value<String>? groupUuid,
    Value<String>? name,
    Value<String?>? logoUrl,
    Value<String>? coachUserId,
    Value<String>? description,
    Value<String>? city,
    Value<String?>? inviteCode,
    Value<bool>? inviteEnabled,
    Value<int>? createdAtMs,
  }) {
    return CoachingGroupsCompanion(
      id: id ?? this.id,
      groupUuid: groupUuid ?? this.groupUuid,
      name: name ?? this.name,
      logoUrl: logoUrl ?? this.logoUrl,
      coachUserId: coachUserId ?? this.coachUserId,
      description: description ?? this.description,
      city: city ?? this.city,
      inviteCode: inviteCode ?? this.inviteCode,
      inviteEnabled: inviteEnabled ?? this.inviteEnabled,
      createdAtMs: createdAtMs ?? this.createdAtMs,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (groupUuid.present) {
      map['group_uuid'] = Variable<String>(groupUuid.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (logoUrl.present) {
      map['logo_url'] = Variable<String>(logoUrl.value);
    }
    if (coachUserId.present) {
      map['coach_user_id'] = Variable<String>(coachUserId.value);
    }
    if (description.present) {
      map['description'] = Variable<String>(description.value);
    }
    if (city.present) {
      map['city'] = Variable<String>(city.value);
    }
    if (inviteCode.present) {
      map['invite_code'] = Variable<String>(inviteCode.value);
    }
    if (inviteEnabled.present) {
      map['invite_enabled'] = Variable<bool>(inviteEnabled.value);
    }
    if (createdAtMs.present) {
      map['created_at_ms'] = Variable<int>(createdAtMs.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CoachingGroupsCompanion(')
          ..write('id: $id, ')
          ..write('groupUuid: $groupUuid, ')
          ..write('name: $name, ')
          ..write('logoUrl: $logoUrl, ')
          ..write('coachUserId: $coachUserId, ')
          ..write('description: $description, ')
          ..write('city: $city, ')
          ..write('inviteCode: $inviteCode, ')
          ..write('inviteEnabled: $inviteEnabled, ')
          ..write('createdAtMs: $createdAtMs')
          ..write(')'))
        .toString();
  }
}

class $CoachingMembersTable extends CoachingMembers
    with TableInfo<$CoachingMembersTable, CoachingMember> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CoachingMembersTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _memberUuidMeta = const VerificationMeta(
    'memberUuid',
  );
  @override
  late final GeneratedColumn<String> memberUuid = GeneratedColumn<String>(
    'member_uuid',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways('UNIQUE'),
  );
  static const VerificationMeta _groupIdMeta = const VerificationMeta(
    'groupId',
  );
  @override
  late final GeneratedColumn<String> groupId = GeneratedColumn<String>(
    'group_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _userIdMeta = const VerificationMeta('userId');
  @override
  late final GeneratedColumn<String> userId = GeneratedColumn<String>(
    'user_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _displayNameMeta = const VerificationMeta(
    'displayName',
  );
  @override
  late final GeneratedColumn<String> displayName = GeneratedColumn<String>(
    'display_name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _roleOrdinalMeta = const VerificationMeta(
    'roleOrdinal',
  );
  @override
  late final GeneratedColumn<String> roleOrdinal = GeneratedColumn<String>(
    'role_ordinal',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _joinedAtMsMeta = const VerificationMeta(
    'joinedAtMs',
  );
  @override
  late final GeneratedColumn<int> joinedAtMs = GeneratedColumn<int>(
    'joined_at_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    memberUuid,
    groupId,
    userId,
    displayName,
    roleOrdinal,
    joinedAtMs,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'coaching_members';
  @override
  VerificationContext validateIntegrity(
    Insertable<CoachingMember> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('member_uuid')) {
      context.handle(
        _memberUuidMeta,
        memberUuid.isAcceptableOrUnknown(data['member_uuid']!, _memberUuidMeta),
      );
    } else if (isInserting) {
      context.missing(_memberUuidMeta);
    }
    if (data.containsKey('group_id')) {
      context.handle(
        _groupIdMeta,
        groupId.isAcceptableOrUnknown(data['group_id']!, _groupIdMeta),
      );
    } else if (isInserting) {
      context.missing(_groupIdMeta);
    }
    if (data.containsKey('user_id')) {
      context.handle(
        _userIdMeta,
        userId.isAcceptableOrUnknown(data['user_id']!, _userIdMeta),
      );
    } else if (isInserting) {
      context.missing(_userIdMeta);
    }
    if (data.containsKey('display_name')) {
      context.handle(
        _displayNameMeta,
        displayName.isAcceptableOrUnknown(
          data['display_name']!,
          _displayNameMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_displayNameMeta);
    }
    if (data.containsKey('role_ordinal')) {
      context.handle(
        _roleOrdinalMeta,
        roleOrdinal.isAcceptableOrUnknown(
          data['role_ordinal']!,
          _roleOrdinalMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_roleOrdinalMeta);
    }
    if (data.containsKey('joined_at_ms')) {
      context.handle(
        _joinedAtMsMeta,
        joinedAtMs.isAcceptableOrUnknown(
          data['joined_at_ms']!,
          _joinedAtMsMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_joinedAtMsMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  List<Set<GeneratedColumn>> get uniqueKeys => [
    {groupId, userId},
  ];
  @override
  CoachingMember map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CoachingMember(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      memberUuid: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}member_uuid'],
      )!,
      groupId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}group_id'],
      )!,
      userId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}user_id'],
      )!,
      displayName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}display_name'],
      )!,
      roleOrdinal: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}role_ordinal'],
      )!,
      joinedAtMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}joined_at_ms'],
      )!,
    );
  }

  @override
  $CoachingMembersTable createAlias(String alias) {
    return $CoachingMembersTable(attachedDatabase, alias);
  }
}

class CoachingMember extends DataClass implements Insertable<CoachingMember> {
  final int id;
  final String memberUuid;
  final String groupId;
  final String userId;
  final String displayName;
  final String roleOrdinal;
  final int joinedAtMs;
  const CoachingMember({
    required this.id,
    required this.memberUuid,
    required this.groupId,
    required this.userId,
    required this.displayName,
    required this.roleOrdinal,
    required this.joinedAtMs,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['member_uuid'] = Variable<String>(memberUuid);
    map['group_id'] = Variable<String>(groupId);
    map['user_id'] = Variable<String>(userId);
    map['display_name'] = Variable<String>(displayName);
    map['role_ordinal'] = Variable<String>(roleOrdinal);
    map['joined_at_ms'] = Variable<int>(joinedAtMs);
    return map;
  }

  CoachingMembersCompanion toCompanion(bool nullToAbsent) {
    return CoachingMembersCompanion(
      id: Value(id),
      memberUuid: Value(memberUuid),
      groupId: Value(groupId),
      userId: Value(userId),
      displayName: Value(displayName),
      roleOrdinal: Value(roleOrdinal),
      joinedAtMs: Value(joinedAtMs),
    );
  }

  factory CoachingMember.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CoachingMember(
      id: serializer.fromJson<int>(json['id']),
      memberUuid: serializer.fromJson<String>(json['memberUuid']),
      groupId: serializer.fromJson<String>(json['groupId']),
      userId: serializer.fromJson<String>(json['userId']),
      displayName: serializer.fromJson<String>(json['displayName']),
      roleOrdinal: serializer.fromJson<String>(json['roleOrdinal']),
      joinedAtMs: serializer.fromJson<int>(json['joinedAtMs']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'memberUuid': serializer.toJson<String>(memberUuid),
      'groupId': serializer.toJson<String>(groupId),
      'userId': serializer.toJson<String>(userId),
      'displayName': serializer.toJson<String>(displayName),
      'roleOrdinal': serializer.toJson<String>(roleOrdinal),
      'joinedAtMs': serializer.toJson<int>(joinedAtMs),
    };
  }

  CoachingMember copyWith({
    int? id,
    String? memberUuid,
    String? groupId,
    String? userId,
    String? displayName,
    String? roleOrdinal,
    int? joinedAtMs,
  }) => CoachingMember(
    id: id ?? this.id,
    memberUuid: memberUuid ?? this.memberUuid,
    groupId: groupId ?? this.groupId,
    userId: userId ?? this.userId,
    displayName: displayName ?? this.displayName,
    roleOrdinal: roleOrdinal ?? this.roleOrdinal,
    joinedAtMs: joinedAtMs ?? this.joinedAtMs,
  );
  CoachingMember copyWithCompanion(CoachingMembersCompanion data) {
    return CoachingMember(
      id: data.id.present ? data.id.value : this.id,
      memberUuid: data.memberUuid.present
          ? data.memberUuid.value
          : this.memberUuid,
      groupId: data.groupId.present ? data.groupId.value : this.groupId,
      userId: data.userId.present ? data.userId.value : this.userId,
      displayName: data.displayName.present
          ? data.displayName.value
          : this.displayName,
      roleOrdinal: data.roleOrdinal.present
          ? data.roleOrdinal.value
          : this.roleOrdinal,
      joinedAtMs: data.joinedAtMs.present
          ? data.joinedAtMs.value
          : this.joinedAtMs,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CoachingMember(')
          ..write('id: $id, ')
          ..write('memberUuid: $memberUuid, ')
          ..write('groupId: $groupId, ')
          ..write('userId: $userId, ')
          ..write('displayName: $displayName, ')
          ..write('roleOrdinal: $roleOrdinal, ')
          ..write('joinedAtMs: $joinedAtMs')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    memberUuid,
    groupId,
    userId,
    displayName,
    roleOrdinal,
    joinedAtMs,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CoachingMember &&
          other.id == this.id &&
          other.memberUuid == this.memberUuid &&
          other.groupId == this.groupId &&
          other.userId == this.userId &&
          other.displayName == this.displayName &&
          other.roleOrdinal == this.roleOrdinal &&
          other.joinedAtMs == this.joinedAtMs);
}

class CoachingMembersCompanion extends UpdateCompanion<CoachingMember> {
  final Value<int> id;
  final Value<String> memberUuid;
  final Value<String> groupId;
  final Value<String> userId;
  final Value<String> displayName;
  final Value<String> roleOrdinal;
  final Value<int> joinedAtMs;
  const CoachingMembersCompanion({
    this.id = const Value.absent(),
    this.memberUuid = const Value.absent(),
    this.groupId = const Value.absent(),
    this.userId = const Value.absent(),
    this.displayName = const Value.absent(),
    this.roleOrdinal = const Value.absent(),
    this.joinedAtMs = const Value.absent(),
  });
  CoachingMembersCompanion.insert({
    this.id = const Value.absent(),
    required String memberUuid,
    required String groupId,
    required String userId,
    required String displayName,
    required String roleOrdinal,
    required int joinedAtMs,
  }) : memberUuid = Value(memberUuid),
       groupId = Value(groupId),
       userId = Value(userId),
       displayName = Value(displayName),
       roleOrdinal = Value(roleOrdinal),
       joinedAtMs = Value(joinedAtMs);
  static Insertable<CoachingMember> custom({
    Expression<int>? id,
    Expression<String>? memberUuid,
    Expression<String>? groupId,
    Expression<String>? userId,
    Expression<String>? displayName,
    Expression<String>? roleOrdinal,
    Expression<int>? joinedAtMs,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (memberUuid != null) 'member_uuid': memberUuid,
      if (groupId != null) 'group_id': groupId,
      if (userId != null) 'user_id': userId,
      if (displayName != null) 'display_name': displayName,
      if (roleOrdinal != null) 'role_ordinal': roleOrdinal,
      if (joinedAtMs != null) 'joined_at_ms': joinedAtMs,
    });
  }

  CoachingMembersCompanion copyWith({
    Value<int>? id,
    Value<String>? memberUuid,
    Value<String>? groupId,
    Value<String>? userId,
    Value<String>? displayName,
    Value<String>? roleOrdinal,
    Value<int>? joinedAtMs,
  }) {
    return CoachingMembersCompanion(
      id: id ?? this.id,
      memberUuid: memberUuid ?? this.memberUuid,
      groupId: groupId ?? this.groupId,
      userId: userId ?? this.userId,
      displayName: displayName ?? this.displayName,
      roleOrdinal: roleOrdinal ?? this.roleOrdinal,
      joinedAtMs: joinedAtMs ?? this.joinedAtMs,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (memberUuid.present) {
      map['member_uuid'] = Variable<String>(memberUuid.value);
    }
    if (groupId.present) {
      map['group_id'] = Variable<String>(groupId.value);
    }
    if (userId.present) {
      map['user_id'] = Variable<String>(userId.value);
    }
    if (displayName.present) {
      map['display_name'] = Variable<String>(displayName.value);
    }
    if (roleOrdinal.present) {
      map['role_ordinal'] = Variable<String>(roleOrdinal.value);
    }
    if (joinedAtMs.present) {
      map['joined_at_ms'] = Variable<int>(joinedAtMs.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CoachingMembersCompanion(')
          ..write('id: $id, ')
          ..write('memberUuid: $memberUuid, ')
          ..write('groupId: $groupId, ')
          ..write('userId: $userId, ')
          ..write('displayName: $displayName, ')
          ..write('roleOrdinal: $roleOrdinal, ')
          ..write('joinedAtMs: $joinedAtMs')
          ..write(')'))
        .toString();
  }
}

class $CoachingInvitesTable extends CoachingInvites
    with TableInfo<$CoachingInvitesTable, CoachingInvite> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CoachingInvitesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _inviteUuidMeta = const VerificationMeta(
    'inviteUuid',
  );
  @override
  late final GeneratedColumn<String> inviteUuid = GeneratedColumn<String>(
    'invite_uuid',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways('UNIQUE'),
  );
  static const VerificationMeta _groupIdMeta = const VerificationMeta(
    'groupId',
  );
  @override
  late final GeneratedColumn<String> groupId = GeneratedColumn<String>(
    'group_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _invitedUserIdMeta = const VerificationMeta(
    'invitedUserId',
  );
  @override
  late final GeneratedColumn<String> invitedUserId = GeneratedColumn<String>(
    'invited_user_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _invitedByUserIdMeta = const VerificationMeta(
    'invitedByUserId',
  );
  @override
  late final GeneratedColumn<String> invitedByUserId = GeneratedColumn<String>(
    'invited_by_user_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _statusOrdinalMeta = const VerificationMeta(
    'statusOrdinal',
  );
  @override
  late final GeneratedColumn<String> statusOrdinal = GeneratedColumn<String>(
    'status_ordinal',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _expiresAtMsMeta = const VerificationMeta(
    'expiresAtMs',
  );
  @override
  late final GeneratedColumn<int> expiresAtMs = GeneratedColumn<int>(
    'expires_at_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _createdAtMsMeta = const VerificationMeta(
    'createdAtMs',
  );
  @override
  late final GeneratedColumn<int> createdAtMs = GeneratedColumn<int>(
    'created_at_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    inviteUuid,
    groupId,
    invitedUserId,
    invitedByUserId,
    statusOrdinal,
    expiresAtMs,
    createdAtMs,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'coaching_invites';
  @override
  VerificationContext validateIntegrity(
    Insertable<CoachingInvite> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('invite_uuid')) {
      context.handle(
        _inviteUuidMeta,
        inviteUuid.isAcceptableOrUnknown(data['invite_uuid']!, _inviteUuidMeta),
      );
    } else if (isInserting) {
      context.missing(_inviteUuidMeta);
    }
    if (data.containsKey('group_id')) {
      context.handle(
        _groupIdMeta,
        groupId.isAcceptableOrUnknown(data['group_id']!, _groupIdMeta),
      );
    } else if (isInserting) {
      context.missing(_groupIdMeta);
    }
    if (data.containsKey('invited_user_id')) {
      context.handle(
        _invitedUserIdMeta,
        invitedUserId.isAcceptableOrUnknown(
          data['invited_user_id']!,
          _invitedUserIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_invitedUserIdMeta);
    }
    if (data.containsKey('invited_by_user_id')) {
      context.handle(
        _invitedByUserIdMeta,
        invitedByUserId.isAcceptableOrUnknown(
          data['invited_by_user_id']!,
          _invitedByUserIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_invitedByUserIdMeta);
    }
    if (data.containsKey('status_ordinal')) {
      context.handle(
        _statusOrdinalMeta,
        statusOrdinal.isAcceptableOrUnknown(
          data['status_ordinal']!,
          _statusOrdinalMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_statusOrdinalMeta);
    }
    if (data.containsKey('expires_at_ms')) {
      context.handle(
        _expiresAtMsMeta,
        expiresAtMs.isAcceptableOrUnknown(
          data['expires_at_ms']!,
          _expiresAtMsMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_expiresAtMsMeta);
    }
    if (data.containsKey('created_at_ms')) {
      context.handle(
        _createdAtMsMeta,
        createdAtMs.isAcceptableOrUnknown(
          data['created_at_ms']!,
          _createdAtMsMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_createdAtMsMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  CoachingInvite map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CoachingInvite(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      inviteUuid: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}invite_uuid'],
      )!,
      groupId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}group_id'],
      )!,
      invitedUserId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}invited_user_id'],
      )!,
      invitedByUserId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}invited_by_user_id'],
      )!,
      statusOrdinal: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}status_ordinal'],
      )!,
      expiresAtMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}expires_at_ms'],
      )!,
      createdAtMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_at_ms'],
      )!,
    );
  }

  @override
  $CoachingInvitesTable createAlias(String alias) {
    return $CoachingInvitesTable(attachedDatabase, alias);
  }
}

class CoachingInvite extends DataClass implements Insertable<CoachingInvite> {
  final int id;
  final String inviteUuid;
  final String groupId;
  final String invitedUserId;
  final String invitedByUserId;
  final String statusOrdinal;
  final int expiresAtMs;
  final int createdAtMs;
  const CoachingInvite({
    required this.id,
    required this.inviteUuid,
    required this.groupId,
    required this.invitedUserId,
    required this.invitedByUserId,
    required this.statusOrdinal,
    required this.expiresAtMs,
    required this.createdAtMs,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['invite_uuid'] = Variable<String>(inviteUuid);
    map['group_id'] = Variable<String>(groupId);
    map['invited_user_id'] = Variable<String>(invitedUserId);
    map['invited_by_user_id'] = Variable<String>(invitedByUserId);
    map['status_ordinal'] = Variable<String>(statusOrdinal);
    map['expires_at_ms'] = Variable<int>(expiresAtMs);
    map['created_at_ms'] = Variable<int>(createdAtMs);
    return map;
  }

  CoachingInvitesCompanion toCompanion(bool nullToAbsent) {
    return CoachingInvitesCompanion(
      id: Value(id),
      inviteUuid: Value(inviteUuid),
      groupId: Value(groupId),
      invitedUserId: Value(invitedUserId),
      invitedByUserId: Value(invitedByUserId),
      statusOrdinal: Value(statusOrdinal),
      expiresAtMs: Value(expiresAtMs),
      createdAtMs: Value(createdAtMs),
    );
  }

  factory CoachingInvite.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CoachingInvite(
      id: serializer.fromJson<int>(json['id']),
      inviteUuid: serializer.fromJson<String>(json['inviteUuid']),
      groupId: serializer.fromJson<String>(json['groupId']),
      invitedUserId: serializer.fromJson<String>(json['invitedUserId']),
      invitedByUserId: serializer.fromJson<String>(json['invitedByUserId']),
      statusOrdinal: serializer.fromJson<String>(json['statusOrdinal']),
      expiresAtMs: serializer.fromJson<int>(json['expiresAtMs']),
      createdAtMs: serializer.fromJson<int>(json['createdAtMs']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'inviteUuid': serializer.toJson<String>(inviteUuid),
      'groupId': serializer.toJson<String>(groupId),
      'invitedUserId': serializer.toJson<String>(invitedUserId),
      'invitedByUserId': serializer.toJson<String>(invitedByUserId),
      'statusOrdinal': serializer.toJson<String>(statusOrdinal),
      'expiresAtMs': serializer.toJson<int>(expiresAtMs),
      'createdAtMs': serializer.toJson<int>(createdAtMs),
    };
  }

  CoachingInvite copyWith({
    int? id,
    String? inviteUuid,
    String? groupId,
    String? invitedUserId,
    String? invitedByUserId,
    String? statusOrdinal,
    int? expiresAtMs,
    int? createdAtMs,
  }) => CoachingInvite(
    id: id ?? this.id,
    inviteUuid: inviteUuid ?? this.inviteUuid,
    groupId: groupId ?? this.groupId,
    invitedUserId: invitedUserId ?? this.invitedUserId,
    invitedByUserId: invitedByUserId ?? this.invitedByUserId,
    statusOrdinal: statusOrdinal ?? this.statusOrdinal,
    expiresAtMs: expiresAtMs ?? this.expiresAtMs,
    createdAtMs: createdAtMs ?? this.createdAtMs,
  );
  CoachingInvite copyWithCompanion(CoachingInvitesCompanion data) {
    return CoachingInvite(
      id: data.id.present ? data.id.value : this.id,
      inviteUuid: data.inviteUuid.present
          ? data.inviteUuid.value
          : this.inviteUuid,
      groupId: data.groupId.present ? data.groupId.value : this.groupId,
      invitedUserId: data.invitedUserId.present
          ? data.invitedUserId.value
          : this.invitedUserId,
      invitedByUserId: data.invitedByUserId.present
          ? data.invitedByUserId.value
          : this.invitedByUserId,
      statusOrdinal: data.statusOrdinal.present
          ? data.statusOrdinal.value
          : this.statusOrdinal,
      expiresAtMs: data.expiresAtMs.present
          ? data.expiresAtMs.value
          : this.expiresAtMs,
      createdAtMs: data.createdAtMs.present
          ? data.createdAtMs.value
          : this.createdAtMs,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CoachingInvite(')
          ..write('id: $id, ')
          ..write('inviteUuid: $inviteUuid, ')
          ..write('groupId: $groupId, ')
          ..write('invitedUserId: $invitedUserId, ')
          ..write('invitedByUserId: $invitedByUserId, ')
          ..write('statusOrdinal: $statusOrdinal, ')
          ..write('expiresAtMs: $expiresAtMs, ')
          ..write('createdAtMs: $createdAtMs')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    inviteUuid,
    groupId,
    invitedUserId,
    invitedByUserId,
    statusOrdinal,
    expiresAtMs,
    createdAtMs,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CoachingInvite &&
          other.id == this.id &&
          other.inviteUuid == this.inviteUuid &&
          other.groupId == this.groupId &&
          other.invitedUserId == this.invitedUserId &&
          other.invitedByUserId == this.invitedByUserId &&
          other.statusOrdinal == this.statusOrdinal &&
          other.expiresAtMs == this.expiresAtMs &&
          other.createdAtMs == this.createdAtMs);
}

class CoachingInvitesCompanion extends UpdateCompanion<CoachingInvite> {
  final Value<int> id;
  final Value<String> inviteUuid;
  final Value<String> groupId;
  final Value<String> invitedUserId;
  final Value<String> invitedByUserId;
  final Value<String> statusOrdinal;
  final Value<int> expiresAtMs;
  final Value<int> createdAtMs;
  const CoachingInvitesCompanion({
    this.id = const Value.absent(),
    this.inviteUuid = const Value.absent(),
    this.groupId = const Value.absent(),
    this.invitedUserId = const Value.absent(),
    this.invitedByUserId = const Value.absent(),
    this.statusOrdinal = const Value.absent(),
    this.expiresAtMs = const Value.absent(),
    this.createdAtMs = const Value.absent(),
  });
  CoachingInvitesCompanion.insert({
    this.id = const Value.absent(),
    required String inviteUuid,
    required String groupId,
    required String invitedUserId,
    required String invitedByUserId,
    required String statusOrdinal,
    required int expiresAtMs,
    required int createdAtMs,
  }) : inviteUuid = Value(inviteUuid),
       groupId = Value(groupId),
       invitedUserId = Value(invitedUserId),
       invitedByUserId = Value(invitedByUserId),
       statusOrdinal = Value(statusOrdinal),
       expiresAtMs = Value(expiresAtMs),
       createdAtMs = Value(createdAtMs);
  static Insertable<CoachingInvite> custom({
    Expression<int>? id,
    Expression<String>? inviteUuid,
    Expression<String>? groupId,
    Expression<String>? invitedUserId,
    Expression<String>? invitedByUserId,
    Expression<String>? statusOrdinal,
    Expression<int>? expiresAtMs,
    Expression<int>? createdAtMs,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (inviteUuid != null) 'invite_uuid': inviteUuid,
      if (groupId != null) 'group_id': groupId,
      if (invitedUserId != null) 'invited_user_id': invitedUserId,
      if (invitedByUserId != null) 'invited_by_user_id': invitedByUserId,
      if (statusOrdinal != null) 'status_ordinal': statusOrdinal,
      if (expiresAtMs != null) 'expires_at_ms': expiresAtMs,
      if (createdAtMs != null) 'created_at_ms': createdAtMs,
    });
  }

  CoachingInvitesCompanion copyWith({
    Value<int>? id,
    Value<String>? inviteUuid,
    Value<String>? groupId,
    Value<String>? invitedUserId,
    Value<String>? invitedByUserId,
    Value<String>? statusOrdinal,
    Value<int>? expiresAtMs,
    Value<int>? createdAtMs,
  }) {
    return CoachingInvitesCompanion(
      id: id ?? this.id,
      inviteUuid: inviteUuid ?? this.inviteUuid,
      groupId: groupId ?? this.groupId,
      invitedUserId: invitedUserId ?? this.invitedUserId,
      invitedByUserId: invitedByUserId ?? this.invitedByUserId,
      statusOrdinal: statusOrdinal ?? this.statusOrdinal,
      expiresAtMs: expiresAtMs ?? this.expiresAtMs,
      createdAtMs: createdAtMs ?? this.createdAtMs,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (inviteUuid.present) {
      map['invite_uuid'] = Variable<String>(inviteUuid.value);
    }
    if (groupId.present) {
      map['group_id'] = Variable<String>(groupId.value);
    }
    if (invitedUserId.present) {
      map['invited_user_id'] = Variable<String>(invitedUserId.value);
    }
    if (invitedByUserId.present) {
      map['invited_by_user_id'] = Variable<String>(invitedByUserId.value);
    }
    if (statusOrdinal.present) {
      map['status_ordinal'] = Variable<String>(statusOrdinal.value);
    }
    if (expiresAtMs.present) {
      map['expires_at_ms'] = Variable<int>(expiresAtMs.value);
    }
    if (createdAtMs.present) {
      map['created_at_ms'] = Variable<int>(createdAtMs.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CoachingInvitesCompanion(')
          ..write('id: $id, ')
          ..write('inviteUuid: $inviteUuid, ')
          ..write('groupId: $groupId, ')
          ..write('invitedUserId: $invitedUserId, ')
          ..write('invitedByUserId: $invitedByUserId, ')
          ..write('statusOrdinal: $statusOrdinal, ')
          ..write('expiresAtMs: $expiresAtMs, ')
          ..write('createdAtMs: $createdAtMs')
          ..write(')'))
        .toString();
  }
}

class $CoachingRankingsTable extends CoachingRankings
    with TableInfo<$CoachingRankingsTable, CoachingRanking> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CoachingRankingsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _rankingUuidMeta = const VerificationMeta(
    'rankingUuid',
  );
  @override
  late final GeneratedColumn<String> rankingUuid = GeneratedColumn<String>(
    'ranking_uuid',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways('UNIQUE'),
  );
  static const VerificationMeta _groupIdMeta = const VerificationMeta(
    'groupId',
  );
  @override
  late final GeneratedColumn<String> groupId = GeneratedColumn<String>(
    'group_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _metricOrdinalMeta = const VerificationMeta(
    'metricOrdinal',
  );
  @override
  late final GeneratedColumn<String> metricOrdinal = GeneratedColumn<String>(
    'metric_ordinal',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _periodOrdinalMeta = const VerificationMeta(
    'periodOrdinal',
  );
  @override
  late final GeneratedColumn<String> periodOrdinal = GeneratedColumn<String>(
    'period_ordinal',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _periodKeyMeta = const VerificationMeta(
    'periodKey',
  );
  @override
  late final GeneratedColumn<String> periodKey = GeneratedColumn<String>(
    'period_key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _startsAtMsMeta = const VerificationMeta(
    'startsAtMs',
  );
  @override
  late final GeneratedColumn<int> startsAtMs = GeneratedColumn<int>(
    'starts_at_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _endsAtMsMeta = const VerificationMeta(
    'endsAtMs',
  );
  @override
  late final GeneratedColumn<int> endsAtMs = GeneratedColumn<int>(
    'ends_at_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _computedAtMsMeta = const VerificationMeta(
    'computedAtMs',
  );
  @override
  late final GeneratedColumn<int> computedAtMs = GeneratedColumn<int>(
    'computed_at_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    rankingUuid,
    groupId,
    metricOrdinal,
    periodOrdinal,
    periodKey,
    startsAtMs,
    endsAtMs,
    computedAtMs,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'coaching_rankings';
  @override
  VerificationContext validateIntegrity(
    Insertable<CoachingRanking> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('ranking_uuid')) {
      context.handle(
        _rankingUuidMeta,
        rankingUuid.isAcceptableOrUnknown(
          data['ranking_uuid']!,
          _rankingUuidMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_rankingUuidMeta);
    }
    if (data.containsKey('group_id')) {
      context.handle(
        _groupIdMeta,
        groupId.isAcceptableOrUnknown(data['group_id']!, _groupIdMeta),
      );
    } else if (isInserting) {
      context.missing(_groupIdMeta);
    }
    if (data.containsKey('metric_ordinal')) {
      context.handle(
        _metricOrdinalMeta,
        metricOrdinal.isAcceptableOrUnknown(
          data['metric_ordinal']!,
          _metricOrdinalMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_metricOrdinalMeta);
    }
    if (data.containsKey('period_ordinal')) {
      context.handle(
        _periodOrdinalMeta,
        periodOrdinal.isAcceptableOrUnknown(
          data['period_ordinal']!,
          _periodOrdinalMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_periodOrdinalMeta);
    }
    if (data.containsKey('period_key')) {
      context.handle(
        _periodKeyMeta,
        periodKey.isAcceptableOrUnknown(data['period_key']!, _periodKeyMeta),
      );
    } else if (isInserting) {
      context.missing(_periodKeyMeta);
    }
    if (data.containsKey('starts_at_ms')) {
      context.handle(
        _startsAtMsMeta,
        startsAtMs.isAcceptableOrUnknown(
          data['starts_at_ms']!,
          _startsAtMsMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_startsAtMsMeta);
    }
    if (data.containsKey('ends_at_ms')) {
      context.handle(
        _endsAtMsMeta,
        endsAtMs.isAcceptableOrUnknown(data['ends_at_ms']!, _endsAtMsMeta),
      );
    } else if (isInserting) {
      context.missing(_endsAtMsMeta);
    }
    if (data.containsKey('computed_at_ms')) {
      context.handle(
        _computedAtMsMeta,
        computedAtMs.isAcceptableOrUnknown(
          data['computed_at_ms']!,
          _computedAtMsMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_computedAtMsMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  CoachingRanking map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CoachingRanking(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      rankingUuid: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}ranking_uuid'],
      )!,
      groupId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}group_id'],
      )!,
      metricOrdinal: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}metric_ordinal'],
      )!,
      periodOrdinal: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}period_ordinal'],
      )!,
      periodKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}period_key'],
      )!,
      startsAtMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}starts_at_ms'],
      )!,
      endsAtMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}ends_at_ms'],
      )!,
      computedAtMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}computed_at_ms'],
      )!,
    );
  }

  @override
  $CoachingRankingsTable createAlias(String alias) {
    return $CoachingRankingsTable(attachedDatabase, alias);
  }
}

class CoachingRanking extends DataClass implements Insertable<CoachingRanking> {
  final int id;
  final String rankingUuid;
  final String groupId;
  final String metricOrdinal;
  final String periodOrdinal;
  final String periodKey;
  final int startsAtMs;
  final int endsAtMs;
  final int computedAtMs;
  const CoachingRanking({
    required this.id,
    required this.rankingUuid,
    required this.groupId,
    required this.metricOrdinal,
    required this.periodOrdinal,
    required this.periodKey,
    required this.startsAtMs,
    required this.endsAtMs,
    required this.computedAtMs,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['ranking_uuid'] = Variable<String>(rankingUuid);
    map['group_id'] = Variable<String>(groupId);
    map['metric_ordinal'] = Variable<String>(metricOrdinal);
    map['period_ordinal'] = Variable<String>(periodOrdinal);
    map['period_key'] = Variable<String>(periodKey);
    map['starts_at_ms'] = Variable<int>(startsAtMs);
    map['ends_at_ms'] = Variable<int>(endsAtMs);
    map['computed_at_ms'] = Variable<int>(computedAtMs);
    return map;
  }

  CoachingRankingsCompanion toCompanion(bool nullToAbsent) {
    return CoachingRankingsCompanion(
      id: Value(id),
      rankingUuid: Value(rankingUuid),
      groupId: Value(groupId),
      metricOrdinal: Value(metricOrdinal),
      periodOrdinal: Value(periodOrdinal),
      periodKey: Value(periodKey),
      startsAtMs: Value(startsAtMs),
      endsAtMs: Value(endsAtMs),
      computedAtMs: Value(computedAtMs),
    );
  }

  factory CoachingRanking.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CoachingRanking(
      id: serializer.fromJson<int>(json['id']),
      rankingUuid: serializer.fromJson<String>(json['rankingUuid']),
      groupId: serializer.fromJson<String>(json['groupId']),
      metricOrdinal: serializer.fromJson<String>(json['metricOrdinal']),
      periodOrdinal: serializer.fromJson<String>(json['periodOrdinal']),
      periodKey: serializer.fromJson<String>(json['periodKey']),
      startsAtMs: serializer.fromJson<int>(json['startsAtMs']),
      endsAtMs: serializer.fromJson<int>(json['endsAtMs']),
      computedAtMs: serializer.fromJson<int>(json['computedAtMs']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'rankingUuid': serializer.toJson<String>(rankingUuid),
      'groupId': serializer.toJson<String>(groupId),
      'metricOrdinal': serializer.toJson<String>(metricOrdinal),
      'periodOrdinal': serializer.toJson<String>(periodOrdinal),
      'periodKey': serializer.toJson<String>(periodKey),
      'startsAtMs': serializer.toJson<int>(startsAtMs),
      'endsAtMs': serializer.toJson<int>(endsAtMs),
      'computedAtMs': serializer.toJson<int>(computedAtMs),
    };
  }

  CoachingRanking copyWith({
    int? id,
    String? rankingUuid,
    String? groupId,
    String? metricOrdinal,
    String? periodOrdinal,
    String? periodKey,
    int? startsAtMs,
    int? endsAtMs,
    int? computedAtMs,
  }) => CoachingRanking(
    id: id ?? this.id,
    rankingUuid: rankingUuid ?? this.rankingUuid,
    groupId: groupId ?? this.groupId,
    metricOrdinal: metricOrdinal ?? this.metricOrdinal,
    periodOrdinal: periodOrdinal ?? this.periodOrdinal,
    periodKey: periodKey ?? this.periodKey,
    startsAtMs: startsAtMs ?? this.startsAtMs,
    endsAtMs: endsAtMs ?? this.endsAtMs,
    computedAtMs: computedAtMs ?? this.computedAtMs,
  );
  CoachingRanking copyWithCompanion(CoachingRankingsCompanion data) {
    return CoachingRanking(
      id: data.id.present ? data.id.value : this.id,
      rankingUuid: data.rankingUuid.present
          ? data.rankingUuid.value
          : this.rankingUuid,
      groupId: data.groupId.present ? data.groupId.value : this.groupId,
      metricOrdinal: data.metricOrdinal.present
          ? data.metricOrdinal.value
          : this.metricOrdinal,
      periodOrdinal: data.periodOrdinal.present
          ? data.periodOrdinal.value
          : this.periodOrdinal,
      periodKey: data.periodKey.present ? data.periodKey.value : this.periodKey,
      startsAtMs: data.startsAtMs.present
          ? data.startsAtMs.value
          : this.startsAtMs,
      endsAtMs: data.endsAtMs.present ? data.endsAtMs.value : this.endsAtMs,
      computedAtMs: data.computedAtMs.present
          ? data.computedAtMs.value
          : this.computedAtMs,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CoachingRanking(')
          ..write('id: $id, ')
          ..write('rankingUuid: $rankingUuid, ')
          ..write('groupId: $groupId, ')
          ..write('metricOrdinal: $metricOrdinal, ')
          ..write('periodOrdinal: $periodOrdinal, ')
          ..write('periodKey: $periodKey, ')
          ..write('startsAtMs: $startsAtMs, ')
          ..write('endsAtMs: $endsAtMs, ')
          ..write('computedAtMs: $computedAtMs')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    rankingUuid,
    groupId,
    metricOrdinal,
    periodOrdinal,
    periodKey,
    startsAtMs,
    endsAtMs,
    computedAtMs,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CoachingRanking &&
          other.id == this.id &&
          other.rankingUuid == this.rankingUuid &&
          other.groupId == this.groupId &&
          other.metricOrdinal == this.metricOrdinal &&
          other.periodOrdinal == this.periodOrdinal &&
          other.periodKey == this.periodKey &&
          other.startsAtMs == this.startsAtMs &&
          other.endsAtMs == this.endsAtMs &&
          other.computedAtMs == this.computedAtMs);
}

class CoachingRankingsCompanion extends UpdateCompanion<CoachingRanking> {
  final Value<int> id;
  final Value<String> rankingUuid;
  final Value<String> groupId;
  final Value<String> metricOrdinal;
  final Value<String> periodOrdinal;
  final Value<String> periodKey;
  final Value<int> startsAtMs;
  final Value<int> endsAtMs;
  final Value<int> computedAtMs;
  const CoachingRankingsCompanion({
    this.id = const Value.absent(),
    this.rankingUuid = const Value.absent(),
    this.groupId = const Value.absent(),
    this.metricOrdinal = const Value.absent(),
    this.periodOrdinal = const Value.absent(),
    this.periodKey = const Value.absent(),
    this.startsAtMs = const Value.absent(),
    this.endsAtMs = const Value.absent(),
    this.computedAtMs = const Value.absent(),
  });
  CoachingRankingsCompanion.insert({
    this.id = const Value.absent(),
    required String rankingUuid,
    required String groupId,
    required String metricOrdinal,
    required String periodOrdinal,
    required String periodKey,
    required int startsAtMs,
    required int endsAtMs,
    required int computedAtMs,
  }) : rankingUuid = Value(rankingUuid),
       groupId = Value(groupId),
       metricOrdinal = Value(metricOrdinal),
       periodOrdinal = Value(periodOrdinal),
       periodKey = Value(periodKey),
       startsAtMs = Value(startsAtMs),
       endsAtMs = Value(endsAtMs),
       computedAtMs = Value(computedAtMs);
  static Insertable<CoachingRanking> custom({
    Expression<int>? id,
    Expression<String>? rankingUuid,
    Expression<String>? groupId,
    Expression<String>? metricOrdinal,
    Expression<String>? periodOrdinal,
    Expression<String>? periodKey,
    Expression<int>? startsAtMs,
    Expression<int>? endsAtMs,
    Expression<int>? computedAtMs,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (rankingUuid != null) 'ranking_uuid': rankingUuid,
      if (groupId != null) 'group_id': groupId,
      if (metricOrdinal != null) 'metric_ordinal': metricOrdinal,
      if (periodOrdinal != null) 'period_ordinal': periodOrdinal,
      if (periodKey != null) 'period_key': periodKey,
      if (startsAtMs != null) 'starts_at_ms': startsAtMs,
      if (endsAtMs != null) 'ends_at_ms': endsAtMs,
      if (computedAtMs != null) 'computed_at_ms': computedAtMs,
    });
  }

  CoachingRankingsCompanion copyWith({
    Value<int>? id,
    Value<String>? rankingUuid,
    Value<String>? groupId,
    Value<String>? metricOrdinal,
    Value<String>? periodOrdinal,
    Value<String>? periodKey,
    Value<int>? startsAtMs,
    Value<int>? endsAtMs,
    Value<int>? computedAtMs,
  }) {
    return CoachingRankingsCompanion(
      id: id ?? this.id,
      rankingUuid: rankingUuid ?? this.rankingUuid,
      groupId: groupId ?? this.groupId,
      metricOrdinal: metricOrdinal ?? this.metricOrdinal,
      periodOrdinal: periodOrdinal ?? this.periodOrdinal,
      periodKey: periodKey ?? this.periodKey,
      startsAtMs: startsAtMs ?? this.startsAtMs,
      endsAtMs: endsAtMs ?? this.endsAtMs,
      computedAtMs: computedAtMs ?? this.computedAtMs,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (rankingUuid.present) {
      map['ranking_uuid'] = Variable<String>(rankingUuid.value);
    }
    if (groupId.present) {
      map['group_id'] = Variable<String>(groupId.value);
    }
    if (metricOrdinal.present) {
      map['metric_ordinal'] = Variable<String>(metricOrdinal.value);
    }
    if (periodOrdinal.present) {
      map['period_ordinal'] = Variable<String>(periodOrdinal.value);
    }
    if (periodKey.present) {
      map['period_key'] = Variable<String>(periodKey.value);
    }
    if (startsAtMs.present) {
      map['starts_at_ms'] = Variable<int>(startsAtMs.value);
    }
    if (endsAtMs.present) {
      map['ends_at_ms'] = Variable<int>(endsAtMs.value);
    }
    if (computedAtMs.present) {
      map['computed_at_ms'] = Variable<int>(computedAtMs.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CoachingRankingsCompanion(')
          ..write('id: $id, ')
          ..write('rankingUuid: $rankingUuid, ')
          ..write('groupId: $groupId, ')
          ..write('metricOrdinal: $metricOrdinal, ')
          ..write('periodOrdinal: $periodOrdinal, ')
          ..write('periodKey: $periodKey, ')
          ..write('startsAtMs: $startsAtMs, ')
          ..write('endsAtMs: $endsAtMs, ')
          ..write('computedAtMs: $computedAtMs')
          ..write(')'))
        .toString();
  }
}

class $CoachingRankingEntriesTable extends CoachingRankingEntries
    with TableInfo<$CoachingRankingEntriesTable, CoachingRankingEntry> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CoachingRankingEntriesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _rankingIdMeta = const VerificationMeta(
    'rankingId',
  );
  @override
  late final GeneratedColumn<String> rankingId = GeneratedColumn<String>(
    'ranking_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _userIdMeta = const VerificationMeta('userId');
  @override
  late final GeneratedColumn<String> userId = GeneratedColumn<String>(
    'user_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _displayNameMeta = const VerificationMeta(
    'displayName',
  );
  @override
  late final GeneratedColumn<String> displayName = GeneratedColumn<String>(
    'display_name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _valueMeta = const VerificationMeta('value');
  @override
  late final GeneratedColumn<double> value = GeneratedColumn<double>(
    'value',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _rankMeta = const VerificationMeta('rank');
  @override
  late final GeneratedColumn<int> rank = GeneratedColumn<int>(
    'rank',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sessionCountMeta = const VerificationMeta(
    'sessionCount',
  );
  @override
  late final GeneratedColumn<int> sessionCount = GeneratedColumn<int>(
    'session_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    rankingId,
    userId,
    displayName,
    value,
    rank,
    sessionCount,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'coaching_ranking_entries';
  @override
  VerificationContext validateIntegrity(
    Insertable<CoachingRankingEntry> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('ranking_id')) {
      context.handle(
        _rankingIdMeta,
        rankingId.isAcceptableOrUnknown(data['ranking_id']!, _rankingIdMeta),
      );
    } else if (isInserting) {
      context.missing(_rankingIdMeta);
    }
    if (data.containsKey('user_id')) {
      context.handle(
        _userIdMeta,
        userId.isAcceptableOrUnknown(data['user_id']!, _userIdMeta),
      );
    } else if (isInserting) {
      context.missing(_userIdMeta);
    }
    if (data.containsKey('display_name')) {
      context.handle(
        _displayNameMeta,
        displayName.isAcceptableOrUnknown(
          data['display_name']!,
          _displayNameMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_displayNameMeta);
    }
    if (data.containsKey('value')) {
      context.handle(
        _valueMeta,
        value.isAcceptableOrUnknown(data['value']!, _valueMeta),
      );
    } else if (isInserting) {
      context.missing(_valueMeta);
    }
    if (data.containsKey('rank')) {
      context.handle(
        _rankMeta,
        rank.isAcceptableOrUnknown(data['rank']!, _rankMeta),
      );
    } else if (isInserting) {
      context.missing(_rankMeta);
    }
    if (data.containsKey('session_count')) {
      context.handle(
        _sessionCountMeta,
        sessionCount.isAcceptableOrUnknown(
          data['session_count']!,
          _sessionCountMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_sessionCountMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  CoachingRankingEntry map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CoachingRankingEntry(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      rankingId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}ranking_id'],
      )!,
      userId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}user_id'],
      )!,
      displayName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}display_name'],
      )!,
      value: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}value'],
      )!,
      rank: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}rank'],
      )!,
      sessionCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}session_count'],
      )!,
    );
  }

  @override
  $CoachingRankingEntriesTable createAlias(String alias) {
    return $CoachingRankingEntriesTable(attachedDatabase, alias);
  }
}

class CoachingRankingEntry extends DataClass
    implements Insertable<CoachingRankingEntry> {
  final int id;
  final String rankingId;
  final String userId;
  final String displayName;
  final double value;
  final int rank;
  final int sessionCount;
  const CoachingRankingEntry({
    required this.id,
    required this.rankingId,
    required this.userId,
    required this.displayName,
    required this.value,
    required this.rank,
    required this.sessionCount,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['ranking_id'] = Variable<String>(rankingId);
    map['user_id'] = Variable<String>(userId);
    map['display_name'] = Variable<String>(displayName);
    map['value'] = Variable<double>(value);
    map['rank'] = Variable<int>(rank);
    map['session_count'] = Variable<int>(sessionCount);
    return map;
  }

  CoachingRankingEntriesCompanion toCompanion(bool nullToAbsent) {
    return CoachingRankingEntriesCompanion(
      id: Value(id),
      rankingId: Value(rankingId),
      userId: Value(userId),
      displayName: Value(displayName),
      value: Value(value),
      rank: Value(rank),
      sessionCount: Value(sessionCount),
    );
  }

  factory CoachingRankingEntry.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CoachingRankingEntry(
      id: serializer.fromJson<int>(json['id']),
      rankingId: serializer.fromJson<String>(json['rankingId']),
      userId: serializer.fromJson<String>(json['userId']),
      displayName: serializer.fromJson<String>(json['displayName']),
      value: serializer.fromJson<double>(json['value']),
      rank: serializer.fromJson<int>(json['rank']),
      sessionCount: serializer.fromJson<int>(json['sessionCount']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'rankingId': serializer.toJson<String>(rankingId),
      'userId': serializer.toJson<String>(userId),
      'displayName': serializer.toJson<String>(displayName),
      'value': serializer.toJson<double>(value),
      'rank': serializer.toJson<int>(rank),
      'sessionCount': serializer.toJson<int>(sessionCount),
    };
  }

  CoachingRankingEntry copyWith({
    int? id,
    String? rankingId,
    String? userId,
    String? displayName,
    double? value,
    int? rank,
    int? sessionCount,
  }) => CoachingRankingEntry(
    id: id ?? this.id,
    rankingId: rankingId ?? this.rankingId,
    userId: userId ?? this.userId,
    displayName: displayName ?? this.displayName,
    value: value ?? this.value,
    rank: rank ?? this.rank,
    sessionCount: sessionCount ?? this.sessionCount,
  );
  CoachingRankingEntry copyWithCompanion(CoachingRankingEntriesCompanion data) {
    return CoachingRankingEntry(
      id: data.id.present ? data.id.value : this.id,
      rankingId: data.rankingId.present ? data.rankingId.value : this.rankingId,
      userId: data.userId.present ? data.userId.value : this.userId,
      displayName: data.displayName.present
          ? data.displayName.value
          : this.displayName,
      value: data.value.present ? data.value.value : this.value,
      rank: data.rank.present ? data.rank.value : this.rank,
      sessionCount: data.sessionCount.present
          ? data.sessionCount.value
          : this.sessionCount,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CoachingRankingEntry(')
          ..write('id: $id, ')
          ..write('rankingId: $rankingId, ')
          ..write('userId: $userId, ')
          ..write('displayName: $displayName, ')
          ..write('value: $value, ')
          ..write('rank: $rank, ')
          ..write('sessionCount: $sessionCount')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    rankingId,
    userId,
    displayName,
    value,
    rank,
    sessionCount,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CoachingRankingEntry &&
          other.id == this.id &&
          other.rankingId == this.rankingId &&
          other.userId == this.userId &&
          other.displayName == this.displayName &&
          other.value == this.value &&
          other.rank == this.rank &&
          other.sessionCount == this.sessionCount);
}

class CoachingRankingEntriesCompanion
    extends UpdateCompanion<CoachingRankingEntry> {
  final Value<int> id;
  final Value<String> rankingId;
  final Value<String> userId;
  final Value<String> displayName;
  final Value<double> value;
  final Value<int> rank;
  final Value<int> sessionCount;
  const CoachingRankingEntriesCompanion({
    this.id = const Value.absent(),
    this.rankingId = const Value.absent(),
    this.userId = const Value.absent(),
    this.displayName = const Value.absent(),
    this.value = const Value.absent(),
    this.rank = const Value.absent(),
    this.sessionCount = const Value.absent(),
  });
  CoachingRankingEntriesCompanion.insert({
    this.id = const Value.absent(),
    required String rankingId,
    required String userId,
    required String displayName,
    required double value,
    required int rank,
    required int sessionCount,
  }) : rankingId = Value(rankingId),
       userId = Value(userId),
       displayName = Value(displayName),
       value = Value(value),
       rank = Value(rank),
       sessionCount = Value(sessionCount);
  static Insertable<CoachingRankingEntry> custom({
    Expression<int>? id,
    Expression<String>? rankingId,
    Expression<String>? userId,
    Expression<String>? displayName,
    Expression<double>? value,
    Expression<int>? rank,
    Expression<int>? sessionCount,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (rankingId != null) 'ranking_id': rankingId,
      if (userId != null) 'user_id': userId,
      if (displayName != null) 'display_name': displayName,
      if (value != null) 'value': value,
      if (rank != null) 'rank': rank,
      if (sessionCount != null) 'session_count': sessionCount,
    });
  }

  CoachingRankingEntriesCompanion copyWith({
    Value<int>? id,
    Value<String>? rankingId,
    Value<String>? userId,
    Value<String>? displayName,
    Value<double>? value,
    Value<int>? rank,
    Value<int>? sessionCount,
  }) {
    return CoachingRankingEntriesCompanion(
      id: id ?? this.id,
      rankingId: rankingId ?? this.rankingId,
      userId: userId ?? this.userId,
      displayName: displayName ?? this.displayName,
      value: value ?? this.value,
      rank: rank ?? this.rank,
      sessionCount: sessionCount ?? this.sessionCount,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (rankingId.present) {
      map['ranking_id'] = Variable<String>(rankingId.value);
    }
    if (userId.present) {
      map['user_id'] = Variable<String>(userId.value);
    }
    if (displayName.present) {
      map['display_name'] = Variable<String>(displayName.value);
    }
    if (value.present) {
      map['value'] = Variable<double>(value.value);
    }
    if (rank.present) {
      map['rank'] = Variable<int>(rank.value);
    }
    if (sessionCount.present) {
      map['session_count'] = Variable<int>(sessionCount.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CoachingRankingEntriesCompanion(')
          ..write('id: $id, ')
          ..write('rankingId: $rankingId, ')
          ..write('userId: $userId, ')
          ..write('displayName: $displayName, ')
          ..write('value: $value, ')
          ..write('rank: $rank, ')
          ..write('sessionCount: $sessionCount')
          ..write(')'))
        .toString();
  }
}

class $AthleteBaselinesTable extends AthleteBaselines
    with TableInfo<$AthleteBaselinesTable, AthleteBaseline> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $AthleteBaselinesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _baselineUuidMeta = const VerificationMeta(
    'baselineUuid',
  );
  @override
  late final GeneratedColumn<String> baselineUuid = GeneratedColumn<String>(
    'baseline_uuid',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways('UNIQUE'),
  );
  static const VerificationMeta _userIdMeta = const VerificationMeta('userId');
  @override
  late final GeneratedColumn<String> userId = GeneratedColumn<String>(
    'user_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _groupIdMeta = const VerificationMeta(
    'groupId',
  );
  @override
  late final GeneratedColumn<String> groupId = GeneratedColumn<String>(
    'group_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _metricOrdinalMeta = const VerificationMeta(
    'metricOrdinal',
  );
  @override
  late final GeneratedColumn<String> metricOrdinal = GeneratedColumn<String>(
    'metric_ordinal',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _valueMeta = const VerificationMeta('value');
  @override
  late final GeneratedColumn<double> value = GeneratedColumn<double>(
    'value',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sampleSizeMeta = const VerificationMeta(
    'sampleSize',
  );
  @override
  late final GeneratedColumn<int> sampleSize = GeneratedColumn<int>(
    'sample_size',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _windowStartMsMeta = const VerificationMeta(
    'windowStartMs',
  );
  @override
  late final GeneratedColumn<int> windowStartMs = GeneratedColumn<int>(
    'window_start_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _windowEndMsMeta = const VerificationMeta(
    'windowEndMs',
  );
  @override
  late final GeneratedColumn<int> windowEndMs = GeneratedColumn<int>(
    'window_end_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _computedAtMsMeta = const VerificationMeta(
    'computedAtMs',
  );
  @override
  late final GeneratedColumn<int> computedAtMs = GeneratedColumn<int>(
    'computed_at_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    baselineUuid,
    userId,
    groupId,
    metricOrdinal,
    value,
    sampleSize,
    windowStartMs,
    windowEndMs,
    computedAtMs,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'athlete_baselines';
  @override
  VerificationContext validateIntegrity(
    Insertable<AthleteBaseline> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('baseline_uuid')) {
      context.handle(
        _baselineUuidMeta,
        baselineUuid.isAcceptableOrUnknown(
          data['baseline_uuid']!,
          _baselineUuidMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_baselineUuidMeta);
    }
    if (data.containsKey('user_id')) {
      context.handle(
        _userIdMeta,
        userId.isAcceptableOrUnknown(data['user_id']!, _userIdMeta),
      );
    } else if (isInserting) {
      context.missing(_userIdMeta);
    }
    if (data.containsKey('group_id')) {
      context.handle(
        _groupIdMeta,
        groupId.isAcceptableOrUnknown(data['group_id']!, _groupIdMeta),
      );
    } else if (isInserting) {
      context.missing(_groupIdMeta);
    }
    if (data.containsKey('metric_ordinal')) {
      context.handle(
        _metricOrdinalMeta,
        metricOrdinal.isAcceptableOrUnknown(
          data['metric_ordinal']!,
          _metricOrdinalMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_metricOrdinalMeta);
    }
    if (data.containsKey('value')) {
      context.handle(
        _valueMeta,
        value.isAcceptableOrUnknown(data['value']!, _valueMeta),
      );
    } else if (isInserting) {
      context.missing(_valueMeta);
    }
    if (data.containsKey('sample_size')) {
      context.handle(
        _sampleSizeMeta,
        sampleSize.isAcceptableOrUnknown(data['sample_size']!, _sampleSizeMeta),
      );
    } else if (isInserting) {
      context.missing(_sampleSizeMeta);
    }
    if (data.containsKey('window_start_ms')) {
      context.handle(
        _windowStartMsMeta,
        windowStartMs.isAcceptableOrUnknown(
          data['window_start_ms']!,
          _windowStartMsMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_windowStartMsMeta);
    }
    if (data.containsKey('window_end_ms')) {
      context.handle(
        _windowEndMsMeta,
        windowEndMs.isAcceptableOrUnknown(
          data['window_end_ms']!,
          _windowEndMsMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_windowEndMsMeta);
    }
    if (data.containsKey('computed_at_ms')) {
      context.handle(
        _computedAtMsMeta,
        computedAtMs.isAcceptableOrUnknown(
          data['computed_at_ms']!,
          _computedAtMsMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_computedAtMsMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  AthleteBaseline map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return AthleteBaseline(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      baselineUuid: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}baseline_uuid'],
      )!,
      userId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}user_id'],
      )!,
      groupId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}group_id'],
      )!,
      metricOrdinal: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}metric_ordinal'],
      )!,
      value: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}value'],
      )!,
      sampleSize: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}sample_size'],
      )!,
      windowStartMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}window_start_ms'],
      )!,
      windowEndMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}window_end_ms'],
      )!,
      computedAtMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}computed_at_ms'],
      )!,
    );
  }

  @override
  $AthleteBaselinesTable createAlias(String alias) {
    return $AthleteBaselinesTable(attachedDatabase, alias);
  }
}

class AthleteBaseline extends DataClass implements Insertable<AthleteBaseline> {
  final int id;
  final String baselineUuid;
  final String userId;
  final String groupId;
  final String metricOrdinal;
  final double value;
  final int sampleSize;
  final int windowStartMs;
  final int windowEndMs;
  final int computedAtMs;
  const AthleteBaseline({
    required this.id,
    required this.baselineUuid,
    required this.userId,
    required this.groupId,
    required this.metricOrdinal,
    required this.value,
    required this.sampleSize,
    required this.windowStartMs,
    required this.windowEndMs,
    required this.computedAtMs,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['baseline_uuid'] = Variable<String>(baselineUuid);
    map['user_id'] = Variable<String>(userId);
    map['group_id'] = Variable<String>(groupId);
    map['metric_ordinal'] = Variable<String>(metricOrdinal);
    map['value'] = Variable<double>(value);
    map['sample_size'] = Variable<int>(sampleSize);
    map['window_start_ms'] = Variable<int>(windowStartMs);
    map['window_end_ms'] = Variable<int>(windowEndMs);
    map['computed_at_ms'] = Variable<int>(computedAtMs);
    return map;
  }

  AthleteBaselinesCompanion toCompanion(bool nullToAbsent) {
    return AthleteBaselinesCompanion(
      id: Value(id),
      baselineUuid: Value(baselineUuid),
      userId: Value(userId),
      groupId: Value(groupId),
      metricOrdinal: Value(metricOrdinal),
      value: Value(value),
      sampleSize: Value(sampleSize),
      windowStartMs: Value(windowStartMs),
      windowEndMs: Value(windowEndMs),
      computedAtMs: Value(computedAtMs),
    );
  }

  factory AthleteBaseline.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return AthleteBaseline(
      id: serializer.fromJson<int>(json['id']),
      baselineUuid: serializer.fromJson<String>(json['baselineUuid']),
      userId: serializer.fromJson<String>(json['userId']),
      groupId: serializer.fromJson<String>(json['groupId']),
      metricOrdinal: serializer.fromJson<String>(json['metricOrdinal']),
      value: serializer.fromJson<double>(json['value']),
      sampleSize: serializer.fromJson<int>(json['sampleSize']),
      windowStartMs: serializer.fromJson<int>(json['windowStartMs']),
      windowEndMs: serializer.fromJson<int>(json['windowEndMs']),
      computedAtMs: serializer.fromJson<int>(json['computedAtMs']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'baselineUuid': serializer.toJson<String>(baselineUuid),
      'userId': serializer.toJson<String>(userId),
      'groupId': serializer.toJson<String>(groupId),
      'metricOrdinal': serializer.toJson<String>(metricOrdinal),
      'value': serializer.toJson<double>(value),
      'sampleSize': serializer.toJson<int>(sampleSize),
      'windowStartMs': serializer.toJson<int>(windowStartMs),
      'windowEndMs': serializer.toJson<int>(windowEndMs),
      'computedAtMs': serializer.toJson<int>(computedAtMs),
    };
  }

  AthleteBaseline copyWith({
    int? id,
    String? baselineUuid,
    String? userId,
    String? groupId,
    String? metricOrdinal,
    double? value,
    int? sampleSize,
    int? windowStartMs,
    int? windowEndMs,
    int? computedAtMs,
  }) => AthleteBaseline(
    id: id ?? this.id,
    baselineUuid: baselineUuid ?? this.baselineUuid,
    userId: userId ?? this.userId,
    groupId: groupId ?? this.groupId,
    metricOrdinal: metricOrdinal ?? this.metricOrdinal,
    value: value ?? this.value,
    sampleSize: sampleSize ?? this.sampleSize,
    windowStartMs: windowStartMs ?? this.windowStartMs,
    windowEndMs: windowEndMs ?? this.windowEndMs,
    computedAtMs: computedAtMs ?? this.computedAtMs,
  );
  AthleteBaseline copyWithCompanion(AthleteBaselinesCompanion data) {
    return AthleteBaseline(
      id: data.id.present ? data.id.value : this.id,
      baselineUuid: data.baselineUuid.present
          ? data.baselineUuid.value
          : this.baselineUuid,
      userId: data.userId.present ? data.userId.value : this.userId,
      groupId: data.groupId.present ? data.groupId.value : this.groupId,
      metricOrdinal: data.metricOrdinal.present
          ? data.metricOrdinal.value
          : this.metricOrdinal,
      value: data.value.present ? data.value.value : this.value,
      sampleSize: data.sampleSize.present
          ? data.sampleSize.value
          : this.sampleSize,
      windowStartMs: data.windowStartMs.present
          ? data.windowStartMs.value
          : this.windowStartMs,
      windowEndMs: data.windowEndMs.present
          ? data.windowEndMs.value
          : this.windowEndMs,
      computedAtMs: data.computedAtMs.present
          ? data.computedAtMs.value
          : this.computedAtMs,
    );
  }

  @override
  String toString() {
    return (StringBuffer('AthleteBaseline(')
          ..write('id: $id, ')
          ..write('baselineUuid: $baselineUuid, ')
          ..write('userId: $userId, ')
          ..write('groupId: $groupId, ')
          ..write('metricOrdinal: $metricOrdinal, ')
          ..write('value: $value, ')
          ..write('sampleSize: $sampleSize, ')
          ..write('windowStartMs: $windowStartMs, ')
          ..write('windowEndMs: $windowEndMs, ')
          ..write('computedAtMs: $computedAtMs')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    baselineUuid,
    userId,
    groupId,
    metricOrdinal,
    value,
    sampleSize,
    windowStartMs,
    windowEndMs,
    computedAtMs,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is AthleteBaseline &&
          other.id == this.id &&
          other.baselineUuid == this.baselineUuid &&
          other.userId == this.userId &&
          other.groupId == this.groupId &&
          other.metricOrdinal == this.metricOrdinal &&
          other.value == this.value &&
          other.sampleSize == this.sampleSize &&
          other.windowStartMs == this.windowStartMs &&
          other.windowEndMs == this.windowEndMs &&
          other.computedAtMs == this.computedAtMs);
}

class AthleteBaselinesCompanion extends UpdateCompanion<AthleteBaseline> {
  final Value<int> id;
  final Value<String> baselineUuid;
  final Value<String> userId;
  final Value<String> groupId;
  final Value<String> metricOrdinal;
  final Value<double> value;
  final Value<int> sampleSize;
  final Value<int> windowStartMs;
  final Value<int> windowEndMs;
  final Value<int> computedAtMs;
  const AthleteBaselinesCompanion({
    this.id = const Value.absent(),
    this.baselineUuid = const Value.absent(),
    this.userId = const Value.absent(),
    this.groupId = const Value.absent(),
    this.metricOrdinal = const Value.absent(),
    this.value = const Value.absent(),
    this.sampleSize = const Value.absent(),
    this.windowStartMs = const Value.absent(),
    this.windowEndMs = const Value.absent(),
    this.computedAtMs = const Value.absent(),
  });
  AthleteBaselinesCompanion.insert({
    this.id = const Value.absent(),
    required String baselineUuid,
    required String userId,
    required String groupId,
    required String metricOrdinal,
    required double value,
    required int sampleSize,
    required int windowStartMs,
    required int windowEndMs,
    required int computedAtMs,
  }) : baselineUuid = Value(baselineUuid),
       userId = Value(userId),
       groupId = Value(groupId),
       metricOrdinal = Value(metricOrdinal),
       value = Value(value),
       sampleSize = Value(sampleSize),
       windowStartMs = Value(windowStartMs),
       windowEndMs = Value(windowEndMs),
       computedAtMs = Value(computedAtMs);
  static Insertable<AthleteBaseline> custom({
    Expression<int>? id,
    Expression<String>? baselineUuid,
    Expression<String>? userId,
    Expression<String>? groupId,
    Expression<String>? metricOrdinal,
    Expression<double>? value,
    Expression<int>? sampleSize,
    Expression<int>? windowStartMs,
    Expression<int>? windowEndMs,
    Expression<int>? computedAtMs,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (baselineUuid != null) 'baseline_uuid': baselineUuid,
      if (userId != null) 'user_id': userId,
      if (groupId != null) 'group_id': groupId,
      if (metricOrdinal != null) 'metric_ordinal': metricOrdinal,
      if (value != null) 'value': value,
      if (sampleSize != null) 'sample_size': sampleSize,
      if (windowStartMs != null) 'window_start_ms': windowStartMs,
      if (windowEndMs != null) 'window_end_ms': windowEndMs,
      if (computedAtMs != null) 'computed_at_ms': computedAtMs,
    });
  }

  AthleteBaselinesCompanion copyWith({
    Value<int>? id,
    Value<String>? baselineUuid,
    Value<String>? userId,
    Value<String>? groupId,
    Value<String>? metricOrdinal,
    Value<double>? value,
    Value<int>? sampleSize,
    Value<int>? windowStartMs,
    Value<int>? windowEndMs,
    Value<int>? computedAtMs,
  }) {
    return AthleteBaselinesCompanion(
      id: id ?? this.id,
      baselineUuid: baselineUuid ?? this.baselineUuid,
      userId: userId ?? this.userId,
      groupId: groupId ?? this.groupId,
      metricOrdinal: metricOrdinal ?? this.metricOrdinal,
      value: value ?? this.value,
      sampleSize: sampleSize ?? this.sampleSize,
      windowStartMs: windowStartMs ?? this.windowStartMs,
      windowEndMs: windowEndMs ?? this.windowEndMs,
      computedAtMs: computedAtMs ?? this.computedAtMs,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (baselineUuid.present) {
      map['baseline_uuid'] = Variable<String>(baselineUuid.value);
    }
    if (userId.present) {
      map['user_id'] = Variable<String>(userId.value);
    }
    if (groupId.present) {
      map['group_id'] = Variable<String>(groupId.value);
    }
    if (metricOrdinal.present) {
      map['metric_ordinal'] = Variable<String>(metricOrdinal.value);
    }
    if (value.present) {
      map['value'] = Variable<double>(value.value);
    }
    if (sampleSize.present) {
      map['sample_size'] = Variable<int>(sampleSize.value);
    }
    if (windowStartMs.present) {
      map['window_start_ms'] = Variable<int>(windowStartMs.value);
    }
    if (windowEndMs.present) {
      map['window_end_ms'] = Variable<int>(windowEndMs.value);
    }
    if (computedAtMs.present) {
      map['computed_at_ms'] = Variable<int>(computedAtMs.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('AthleteBaselinesCompanion(')
          ..write('id: $id, ')
          ..write('baselineUuid: $baselineUuid, ')
          ..write('userId: $userId, ')
          ..write('groupId: $groupId, ')
          ..write('metricOrdinal: $metricOrdinal, ')
          ..write('value: $value, ')
          ..write('sampleSize: $sampleSize, ')
          ..write('windowStartMs: $windowStartMs, ')
          ..write('windowEndMs: $windowEndMs, ')
          ..write('computedAtMs: $computedAtMs')
          ..write(')'))
        .toString();
  }
}

class $AthleteTrendsTable extends AthleteTrends
    with TableInfo<$AthleteTrendsTable, AthleteTrend> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $AthleteTrendsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _trendUuidMeta = const VerificationMeta(
    'trendUuid',
  );
  @override
  late final GeneratedColumn<String> trendUuid = GeneratedColumn<String>(
    'trend_uuid',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways('UNIQUE'),
  );
  static const VerificationMeta _userIdMeta = const VerificationMeta('userId');
  @override
  late final GeneratedColumn<String> userId = GeneratedColumn<String>(
    'user_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _groupIdMeta = const VerificationMeta(
    'groupId',
  );
  @override
  late final GeneratedColumn<String> groupId = GeneratedColumn<String>(
    'group_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _metricOrdinalMeta = const VerificationMeta(
    'metricOrdinal',
  );
  @override
  late final GeneratedColumn<String> metricOrdinal = GeneratedColumn<String>(
    'metric_ordinal',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _periodOrdinalMeta = const VerificationMeta(
    'periodOrdinal',
  );
  @override
  late final GeneratedColumn<String> periodOrdinal = GeneratedColumn<String>(
    'period_ordinal',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _directionOrdinalMeta = const VerificationMeta(
    'directionOrdinal',
  );
  @override
  late final GeneratedColumn<String> directionOrdinal = GeneratedColumn<String>(
    'direction_ordinal',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _currentValueMeta = const VerificationMeta(
    'currentValue',
  );
  @override
  late final GeneratedColumn<double> currentValue = GeneratedColumn<double>(
    'current_value',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _baselineValueMeta = const VerificationMeta(
    'baselineValue',
  );
  @override
  late final GeneratedColumn<double> baselineValue = GeneratedColumn<double>(
    'baseline_value',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _changePercentMeta = const VerificationMeta(
    'changePercent',
  );
  @override
  late final GeneratedColumn<double> changePercent = GeneratedColumn<double>(
    'change_percent',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _dataPointsMeta = const VerificationMeta(
    'dataPoints',
  );
  @override
  late final GeneratedColumn<int> dataPoints = GeneratedColumn<int>(
    'data_points',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _latestPeriodKeyMeta = const VerificationMeta(
    'latestPeriodKey',
  );
  @override
  late final GeneratedColumn<String> latestPeriodKey = GeneratedColumn<String>(
    'latest_period_key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _analyzedAtMsMeta = const VerificationMeta(
    'analyzedAtMs',
  );
  @override
  late final GeneratedColumn<int> analyzedAtMs = GeneratedColumn<int>(
    'analyzed_at_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    trendUuid,
    userId,
    groupId,
    metricOrdinal,
    periodOrdinal,
    directionOrdinal,
    currentValue,
    baselineValue,
    changePercent,
    dataPoints,
    latestPeriodKey,
    analyzedAtMs,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'athlete_trends';
  @override
  VerificationContext validateIntegrity(
    Insertable<AthleteTrend> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('trend_uuid')) {
      context.handle(
        _trendUuidMeta,
        trendUuid.isAcceptableOrUnknown(data['trend_uuid']!, _trendUuidMeta),
      );
    } else if (isInserting) {
      context.missing(_trendUuidMeta);
    }
    if (data.containsKey('user_id')) {
      context.handle(
        _userIdMeta,
        userId.isAcceptableOrUnknown(data['user_id']!, _userIdMeta),
      );
    } else if (isInserting) {
      context.missing(_userIdMeta);
    }
    if (data.containsKey('group_id')) {
      context.handle(
        _groupIdMeta,
        groupId.isAcceptableOrUnknown(data['group_id']!, _groupIdMeta),
      );
    } else if (isInserting) {
      context.missing(_groupIdMeta);
    }
    if (data.containsKey('metric_ordinal')) {
      context.handle(
        _metricOrdinalMeta,
        metricOrdinal.isAcceptableOrUnknown(
          data['metric_ordinal']!,
          _metricOrdinalMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_metricOrdinalMeta);
    }
    if (data.containsKey('period_ordinal')) {
      context.handle(
        _periodOrdinalMeta,
        periodOrdinal.isAcceptableOrUnknown(
          data['period_ordinal']!,
          _periodOrdinalMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_periodOrdinalMeta);
    }
    if (data.containsKey('direction_ordinal')) {
      context.handle(
        _directionOrdinalMeta,
        directionOrdinal.isAcceptableOrUnknown(
          data['direction_ordinal']!,
          _directionOrdinalMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_directionOrdinalMeta);
    }
    if (data.containsKey('current_value')) {
      context.handle(
        _currentValueMeta,
        currentValue.isAcceptableOrUnknown(
          data['current_value']!,
          _currentValueMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_currentValueMeta);
    }
    if (data.containsKey('baseline_value')) {
      context.handle(
        _baselineValueMeta,
        baselineValue.isAcceptableOrUnknown(
          data['baseline_value']!,
          _baselineValueMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_baselineValueMeta);
    }
    if (data.containsKey('change_percent')) {
      context.handle(
        _changePercentMeta,
        changePercent.isAcceptableOrUnknown(
          data['change_percent']!,
          _changePercentMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_changePercentMeta);
    }
    if (data.containsKey('data_points')) {
      context.handle(
        _dataPointsMeta,
        dataPoints.isAcceptableOrUnknown(data['data_points']!, _dataPointsMeta),
      );
    } else if (isInserting) {
      context.missing(_dataPointsMeta);
    }
    if (data.containsKey('latest_period_key')) {
      context.handle(
        _latestPeriodKeyMeta,
        latestPeriodKey.isAcceptableOrUnknown(
          data['latest_period_key']!,
          _latestPeriodKeyMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_latestPeriodKeyMeta);
    }
    if (data.containsKey('analyzed_at_ms')) {
      context.handle(
        _analyzedAtMsMeta,
        analyzedAtMs.isAcceptableOrUnknown(
          data['analyzed_at_ms']!,
          _analyzedAtMsMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_analyzedAtMsMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  AthleteTrend map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return AthleteTrend(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      trendUuid: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}trend_uuid'],
      )!,
      userId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}user_id'],
      )!,
      groupId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}group_id'],
      )!,
      metricOrdinal: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}metric_ordinal'],
      )!,
      periodOrdinal: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}period_ordinal'],
      )!,
      directionOrdinal: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}direction_ordinal'],
      )!,
      currentValue: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}current_value'],
      )!,
      baselineValue: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}baseline_value'],
      )!,
      changePercent: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}change_percent'],
      )!,
      dataPoints: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}data_points'],
      )!,
      latestPeriodKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}latest_period_key'],
      )!,
      analyzedAtMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}analyzed_at_ms'],
      )!,
    );
  }

  @override
  $AthleteTrendsTable createAlias(String alias) {
    return $AthleteTrendsTable(attachedDatabase, alias);
  }
}

class AthleteTrend extends DataClass implements Insertable<AthleteTrend> {
  final int id;
  final String trendUuid;
  final String userId;
  final String groupId;
  final String metricOrdinal;
  final String periodOrdinal;
  final String directionOrdinal;
  final double currentValue;
  final double baselineValue;
  final double changePercent;
  final int dataPoints;
  final String latestPeriodKey;
  final int analyzedAtMs;
  const AthleteTrend({
    required this.id,
    required this.trendUuid,
    required this.userId,
    required this.groupId,
    required this.metricOrdinal,
    required this.periodOrdinal,
    required this.directionOrdinal,
    required this.currentValue,
    required this.baselineValue,
    required this.changePercent,
    required this.dataPoints,
    required this.latestPeriodKey,
    required this.analyzedAtMs,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['trend_uuid'] = Variable<String>(trendUuid);
    map['user_id'] = Variable<String>(userId);
    map['group_id'] = Variable<String>(groupId);
    map['metric_ordinal'] = Variable<String>(metricOrdinal);
    map['period_ordinal'] = Variable<String>(periodOrdinal);
    map['direction_ordinal'] = Variable<String>(directionOrdinal);
    map['current_value'] = Variable<double>(currentValue);
    map['baseline_value'] = Variable<double>(baselineValue);
    map['change_percent'] = Variable<double>(changePercent);
    map['data_points'] = Variable<int>(dataPoints);
    map['latest_period_key'] = Variable<String>(latestPeriodKey);
    map['analyzed_at_ms'] = Variable<int>(analyzedAtMs);
    return map;
  }

  AthleteTrendsCompanion toCompanion(bool nullToAbsent) {
    return AthleteTrendsCompanion(
      id: Value(id),
      trendUuid: Value(trendUuid),
      userId: Value(userId),
      groupId: Value(groupId),
      metricOrdinal: Value(metricOrdinal),
      periodOrdinal: Value(periodOrdinal),
      directionOrdinal: Value(directionOrdinal),
      currentValue: Value(currentValue),
      baselineValue: Value(baselineValue),
      changePercent: Value(changePercent),
      dataPoints: Value(dataPoints),
      latestPeriodKey: Value(latestPeriodKey),
      analyzedAtMs: Value(analyzedAtMs),
    );
  }

  factory AthleteTrend.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return AthleteTrend(
      id: serializer.fromJson<int>(json['id']),
      trendUuid: serializer.fromJson<String>(json['trendUuid']),
      userId: serializer.fromJson<String>(json['userId']),
      groupId: serializer.fromJson<String>(json['groupId']),
      metricOrdinal: serializer.fromJson<String>(json['metricOrdinal']),
      periodOrdinal: serializer.fromJson<String>(json['periodOrdinal']),
      directionOrdinal: serializer.fromJson<String>(json['directionOrdinal']),
      currentValue: serializer.fromJson<double>(json['currentValue']),
      baselineValue: serializer.fromJson<double>(json['baselineValue']),
      changePercent: serializer.fromJson<double>(json['changePercent']),
      dataPoints: serializer.fromJson<int>(json['dataPoints']),
      latestPeriodKey: serializer.fromJson<String>(json['latestPeriodKey']),
      analyzedAtMs: serializer.fromJson<int>(json['analyzedAtMs']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'trendUuid': serializer.toJson<String>(trendUuid),
      'userId': serializer.toJson<String>(userId),
      'groupId': serializer.toJson<String>(groupId),
      'metricOrdinal': serializer.toJson<String>(metricOrdinal),
      'periodOrdinal': serializer.toJson<String>(periodOrdinal),
      'directionOrdinal': serializer.toJson<String>(directionOrdinal),
      'currentValue': serializer.toJson<double>(currentValue),
      'baselineValue': serializer.toJson<double>(baselineValue),
      'changePercent': serializer.toJson<double>(changePercent),
      'dataPoints': serializer.toJson<int>(dataPoints),
      'latestPeriodKey': serializer.toJson<String>(latestPeriodKey),
      'analyzedAtMs': serializer.toJson<int>(analyzedAtMs),
    };
  }

  AthleteTrend copyWith({
    int? id,
    String? trendUuid,
    String? userId,
    String? groupId,
    String? metricOrdinal,
    String? periodOrdinal,
    String? directionOrdinal,
    double? currentValue,
    double? baselineValue,
    double? changePercent,
    int? dataPoints,
    String? latestPeriodKey,
    int? analyzedAtMs,
  }) => AthleteTrend(
    id: id ?? this.id,
    trendUuid: trendUuid ?? this.trendUuid,
    userId: userId ?? this.userId,
    groupId: groupId ?? this.groupId,
    metricOrdinal: metricOrdinal ?? this.metricOrdinal,
    periodOrdinal: periodOrdinal ?? this.periodOrdinal,
    directionOrdinal: directionOrdinal ?? this.directionOrdinal,
    currentValue: currentValue ?? this.currentValue,
    baselineValue: baselineValue ?? this.baselineValue,
    changePercent: changePercent ?? this.changePercent,
    dataPoints: dataPoints ?? this.dataPoints,
    latestPeriodKey: latestPeriodKey ?? this.latestPeriodKey,
    analyzedAtMs: analyzedAtMs ?? this.analyzedAtMs,
  );
  AthleteTrend copyWithCompanion(AthleteTrendsCompanion data) {
    return AthleteTrend(
      id: data.id.present ? data.id.value : this.id,
      trendUuid: data.trendUuid.present ? data.trendUuid.value : this.trendUuid,
      userId: data.userId.present ? data.userId.value : this.userId,
      groupId: data.groupId.present ? data.groupId.value : this.groupId,
      metricOrdinal: data.metricOrdinal.present
          ? data.metricOrdinal.value
          : this.metricOrdinal,
      periodOrdinal: data.periodOrdinal.present
          ? data.periodOrdinal.value
          : this.periodOrdinal,
      directionOrdinal: data.directionOrdinal.present
          ? data.directionOrdinal.value
          : this.directionOrdinal,
      currentValue: data.currentValue.present
          ? data.currentValue.value
          : this.currentValue,
      baselineValue: data.baselineValue.present
          ? data.baselineValue.value
          : this.baselineValue,
      changePercent: data.changePercent.present
          ? data.changePercent.value
          : this.changePercent,
      dataPoints: data.dataPoints.present
          ? data.dataPoints.value
          : this.dataPoints,
      latestPeriodKey: data.latestPeriodKey.present
          ? data.latestPeriodKey.value
          : this.latestPeriodKey,
      analyzedAtMs: data.analyzedAtMs.present
          ? data.analyzedAtMs.value
          : this.analyzedAtMs,
    );
  }

  @override
  String toString() {
    return (StringBuffer('AthleteTrend(')
          ..write('id: $id, ')
          ..write('trendUuid: $trendUuid, ')
          ..write('userId: $userId, ')
          ..write('groupId: $groupId, ')
          ..write('metricOrdinal: $metricOrdinal, ')
          ..write('periodOrdinal: $periodOrdinal, ')
          ..write('directionOrdinal: $directionOrdinal, ')
          ..write('currentValue: $currentValue, ')
          ..write('baselineValue: $baselineValue, ')
          ..write('changePercent: $changePercent, ')
          ..write('dataPoints: $dataPoints, ')
          ..write('latestPeriodKey: $latestPeriodKey, ')
          ..write('analyzedAtMs: $analyzedAtMs')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    trendUuid,
    userId,
    groupId,
    metricOrdinal,
    periodOrdinal,
    directionOrdinal,
    currentValue,
    baselineValue,
    changePercent,
    dataPoints,
    latestPeriodKey,
    analyzedAtMs,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is AthleteTrend &&
          other.id == this.id &&
          other.trendUuid == this.trendUuid &&
          other.userId == this.userId &&
          other.groupId == this.groupId &&
          other.metricOrdinal == this.metricOrdinal &&
          other.periodOrdinal == this.periodOrdinal &&
          other.directionOrdinal == this.directionOrdinal &&
          other.currentValue == this.currentValue &&
          other.baselineValue == this.baselineValue &&
          other.changePercent == this.changePercent &&
          other.dataPoints == this.dataPoints &&
          other.latestPeriodKey == this.latestPeriodKey &&
          other.analyzedAtMs == this.analyzedAtMs);
}

class AthleteTrendsCompanion extends UpdateCompanion<AthleteTrend> {
  final Value<int> id;
  final Value<String> trendUuid;
  final Value<String> userId;
  final Value<String> groupId;
  final Value<String> metricOrdinal;
  final Value<String> periodOrdinal;
  final Value<String> directionOrdinal;
  final Value<double> currentValue;
  final Value<double> baselineValue;
  final Value<double> changePercent;
  final Value<int> dataPoints;
  final Value<String> latestPeriodKey;
  final Value<int> analyzedAtMs;
  const AthleteTrendsCompanion({
    this.id = const Value.absent(),
    this.trendUuid = const Value.absent(),
    this.userId = const Value.absent(),
    this.groupId = const Value.absent(),
    this.metricOrdinal = const Value.absent(),
    this.periodOrdinal = const Value.absent(),
    this.directionOrdinal = const Value.absent(),
    this.currentValue = const Value.absent(),
    this.baselineValue = const Value.absent(),
    this.changePercent = const Value.absent(),
    this.dataPoints = const Value.absent(),
    this.latestPeriodKey = const Value.absent(),
    this.analyzedAtMs = const Value.absent(),
  });
  AthleteTrendsCompanion.insert({
    this.id = const Value.absent(),
    required String trendUuid,
    required String userId,
    required String groupId,
    required String metricOrdinal,
    required String periodOrdinal,
    required String directionOrdinal,
    required double currentValue,
    required double baselineValue,
    required double changePercent,
    required int dataPoints,
    required String latestPeriodKey,
    required int analyzedAtMs,
  }) : trendUuid = Value(trendUuid),
       userId = Value(userId),
       groupId = Value(groupId),
       metricOrdinal = Value(metricOrdinal),
       periodOrdinal = Value(periodOrdinal),
       directionOrdinal = Value(directionOrdinal),
       currentValue = Value(currentValue),
       baselineValue = Value(baselineValue),
       changePercent = Value(changePercent),
       dataPoints = Value(dataPoints),
       latestPeriodKey = Value(latestPeriodKey),
       analyzedAtMs = Value(analyzedAtMs);
  static Insertable<AthleteTrend> custom({
    Expression<int>? id,
    Expression<String>? trendUuid,
    Expression<String>? userId,
    Expression<String>? groupId,
    Expression<String>? metricOrdinal,
    Expression<String>? periodOrdinal,
    Expression<String>? directionOrdinal,
    Expression<double>? currentValue,
    Expression<double>? baselineValue,
    Expression<double>? changePercent,
    Expression<int>? dataPoints,
    Expression<String>? latestPeriodKey,
    Expression<int>? analyzedAtMs,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (trendUuid != null) 'trend_uuid': trendUuid,
      if (userId != null) 'user_id': userId,
      if (groupId != null) 'group_id': groupId,
      if (metricOrdinal != null) 'metric_ordinal': metricOrdinal,
      if (periodOrdinal != null) 'period_ordinal': periodOrdinal,
      if (directionOrdinal != null) 'direction_ordinal': directionOrdinal,
      if (currentValue != null) 'current_value': currentValue,
      if (baselineValue != null) 'baseline_value': baselineValue,
      if (changePercent != null) 'change_percent': changePercent,
      if (dataPoints != null) 'data_points': dataPoints,
      if (latestPeriodKey != null) 'latest_period_key': latestPeriodKey,
      if (analyzedAtMs != null) 'analyzed_at_ms': analyzedAtMs,
    });
  }

  AthleteTrendsCompanion copyWith({
    Value<int>? id,
    Value<String>? trendUuid,
    Value<String>? userId,
    Value<String>? groupId,
    Value<String>? metricOrdinal,
    Value<String>? periodOrdinal,
    Value<String>? directionOrdinal,
    Value<double>? currentValue,
    Value<double>? baselineValue,
    Value<double>? changePercent,
    Value<int>? dataPoints,
    Value<String>? latestPeriodKey,
    Value<int>? analyzedAtMs,
  }) {
    return AthleteTrendsCompanion(
      id: id ?? this.id,
      trendUuid: trendUuid ?? this.trendUuid,
      userId: userId ?? this.userId,
      groupId: groupId ?? this.groupId,
      metricOrdinal: metricOrdinal ?? this.metricOrdinal,
      periodOrdinal: periodOrdinal ?? this.periodOrdinal,
      directionOrdinal: directionOrdinal ?? this.directionOrdinal,
      currentValue: currentValue ?? this.currentValue,
      baselineValue: baselineValue ?? this.baselineValue,
      changePercent: changePercent ?? this.changePercent,
      dataPoints: dataPoints ?? this.dataPoints,
      latestPeriodKey: latestPeriodKey ?? this.latestPeriodKey,
      analyzedAtMs: analyzedAtMs ?? this.analyzedAtMs,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (trendUuid.present) {
      map['trend_uuid'] = Variable<String>(trendUuid.value);
    }
    if (userId.present) {
      map['user_id'] = Variable<String>(userId.value);
    }
    if (groupId.present) {
      map['group_id'] = Variable<String>(groupId.value);
    }
    if (metricOrdinal.present) {
      map['metric_ordinal'] = Variable<String>(metricOrdinal.value);
    }
    if (periodOrdinal.present) {
      map['period_ordinal'] = Variable<String>(periodOrdinal.value);
    }
    if (directionOrdinal.present) {
      map['direction_ordinal'] = Variable<String>(directionOrdinal.value);
    }
    if (currentValue.present) {
      map['current_value'] = Variable<double>(currentValue.value);
    }
    if (baselineValue.present) {
      map['baseline_value'] = Variable<double>(baselineValue.value);
    }
    if (changePercent.present) {
      map['change_percent'] = Variable<double>(changePercent.value);
    }
    if (dataPoints.present) {
      map['data_points'] = Variable<int>(dataPoints.value);
    }
    if (latestPeriodKey.present) {
      map['latest_period_key'] = Variable<String>(latestPeriodKey.value);
    }
    if (analyzedAtMs.present) {
      map['analyzed_at_ms'] = Variable<int>(analyzedAtMs.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('AthleteTrendsCompanion(')
          ..write('id: $id, ')
          ..write('trendUuid: $trendUuid, ')
          ..write('userId: $userId, ')
          ..write('groupId: $groupId, ')
          ..write('metricOrdinal: $metricOrdinal, ')
          ..write('periodOrdinal: $periodOrdinal, ')
          ..write('directionOrdinal: $directionOrdinal, ')
          ..write('currentValue: $currentValue, ')
          ..write('baselineValue: $baselineValue, ')
          ..write('changePercent: $changePercent, ')
          ..write('dataPoints: $dataPoints, ')
          ..write('latestPeriodKey: $latestPeriodKey, ')
          ..write('analyzedAtMs: $analyzedAtMs')
          ..write(')'))
        .toString();
  }
}

class $CoachInsightsTable extends CoachInsights
    with TableInfo<$CoachInsightsTable, CoachInsight> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CoachInsightsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _insightUuidMeta = const VerificationMeta(
    'insightUuid',
  );
  @override
  late final GeneratedColumn<String> insightUuid = GeneratedColumn<String>(
    'insight_uuid',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways('UNIQUE'),
  );
  static const VerificationMeta _groupIdMeta = const VerificationMeta(
    'groupId',
  );
  @override
  late final GeneratedColumn<String> groupId = GeneratedColumn<String>(
    'group_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _targetUserIdMeta = const VerificationMeta(
    'targetUserId',
  );
  @override
  late final GeneratedColumn<String> targetUserId = GeneratedColumn<String>(
    'target_user_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _targetDisplayNameMeta = const VerificationMeta(
    'targetDisplayName',
  );
  @override
  late final GeneratedColumn<String> targetDisplayName =
      GeneratedColumn<String>(
        'target_display_name',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      );
  static const VerificationMeta _typeOrdinalMeta = const VerificationMeta(
    'typeOrdinal',
  );
  @override
  late final GeneratedColumn<String> typeOrdinal = GeneratedColumn<String>(
    'type_ordinal',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _priorityOrdinalMeta = const VerificationMeta(
    'priorityOrdinal',
  );
  @override
  late final GeneratedColumn<String> priorityOrdinal = GeneratedColumn<String>(
    'priority_ordinal',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
    'title',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _messageMeta = const VerificationMeta(
    'message',
  );
  @override
  late final GeneratedColumn<String> message = GeneratedColumn<String>(
    'message',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _metricOrdinalMeta = const VerificationMeta(
    'metricOrdinal',
  );
  @override
  late final GeneratedColumn<String> metricOrdinal = GeneratedColumn<String>(
    'metric_ordinal',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _referenceValueMeta = const VerificationMeta(
    'referenceValue',
  );
  @override
  late final GeneratedColumn<double> referenceValue = GeneratedColumn<double>(
    'reference_value',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _changePercentMeta = const VerificationMeta(
    'changePercent',
  );
  @override
  late final GeneratedColumn<double> changePercent = GeneratedColumn<double>(
    'change_percent',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _relatedEntityIdMeta = const VerificationMeta(
    'relatedEntityId',
  );
  @override
  late final GeneratedColumn<String> relatedEntityId = GeneratedColumn<String>(
    'related_entity_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _createdAtMsMeta = const VerificationMeta(
    'createdAtMs',
  );
  @override
  late final GeneratedColumn<int> createdAtMs = GeneratedColumn<int>(
    'created_at_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _readAtMsMeta = const VerificationMeta(
    'readAtMs',
  );
  @override
  late final GeneratedColumn<int> readAtMs = GeneratedColumn<int>(
    'read_at_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _dismissedMeta = const VerificationMeta(
    'dismissed',
  );
  @override
  late final GeneratedColumn<bool> dismissed = GeneratedColumn<bool>(
    'dismissed',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("dismissed" IN (0, 1))',
    ),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    insightUuid,
    groupId,
    targetUserId,
    targetDisplayName,
    typeOrdinal,
    priorityOrdinal,
    title,
    message,
    metricOrdinal,
    referenceValue,
    changePercent,
    relatedEntityId,
    createdAtMs,
    readAtMs,
    dismissed,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'coach_insights';
  @override
  VerificationContext validateIntegrity(
    Insertable<CoachInsight> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('insight_uuid')) {
      context.handle(
        _insightUuidMeta,
        insightUuid.isAcceptableOrUnknown(
          data['insight_uuid']!,
          _insightUuidMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_insightUuidMeta);
    }
    if (data.containsKey('group_id')) {
      context.handle(
        _groupIdMeta,
        groupId.isAcceptableOrUnknown(data['group_id']!, _groupIdMeta),
      );
    } else if (isInserting) {
      context.missing(_groupIdMeta);
    }
    if (data.containsKey('target_user_id')) {
      context.handle(
        _targetUserIdMeta,
        targetUserId.isAcceptableOrUnknown(
          data['target_user_id']!,
          _targetUserIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_targetUserIdMeta);
    }
    if (data.containsKey('target_display_name')) {
      context.handle(
        _targetDisplayNameMeta,
        targetDisplayName.isAcceptableOrUnknown(
          data['target_display_name']!,
          _targetDisplayNameMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_targetDisplayNameMeta);
    }
    if (data.containsKey('type_ordinal')) {
      context.handle(
        _typeOrdinalMeta,
        typeOrdinal.isAcceptableOrUnknown(
          data['type_ordinal']!,
          _typeOrdinalMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_typeOrdinalMeta);
    }
    if (data.containsKey('priority_ordinal')) {
      context.handle(
        _priorityOrdinalMeta,
        priorityOrdinal.isAcceptableOrUnknown(
          data['priority_ordinal']!,
          _priorityOrdinalMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_priorityOrdinalMeta);
    }
    if (data.containsKey('title')) {
      context.handle(
        _titleMeta,
        title.isAcceptableOrUnknown(data['title']!, _titleMeta),
      );
    } else if (isInserting) {
      context.missing(_titleMeta);
    }
    if (data.containsKey('message')) {
      context.handle(
        _messageMeta,
        message.isAcceptableOrUnknown(data['message']!, _messageMeta),
      );
    } else if (isInserting) {
      context.missing(_messageMeta);
    }
    if (data.containsKey('metric_ordinal')) {
      context.handle(
        _metricOrdinalMeta,
        metricOrdinal.isAcceptableOrUnknown(
          data['metric_ordinal']!,
          _metricOrdinalMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_metricOrdinalMeta);
    }
    if (data.containsKey('reference_value')) {
      context.handle(
        _referenceValueMeta,
        referenceValue.isAcceptableOrUnknown(
          data['reference_value']!,
          _referenceValueMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_referenceValueMeta);
    }
    if (data.containsKey('change_percent')) {
      context.handle(
        _changePercentMeta,
        changePercent.isAcceptableOrUnknown(
          data['change_percent']!,
          _changePercentMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_changePercentMeta);
    }
    if (data.containsKey('related_entity_id')) {
      context.handle(
        _relatedEntityIdMeta,
        relatedEntityId.isAcceptableOrUnknown(
          data['related_entity_id']!,
          _relatedEntityIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_relatedEntityIdMeta);
    }
    if (data.containsKey('created_at_ms')) {
      context.handle(
        _createdAtMsMeta,
        createdAtMs.isAcceptableOrUnknown(
          data['created_at_ms']!,
          _createdAtMsMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_createdAtMsMeta);
    }
    if (data.containsKey('read_at_ms')) {
      context.handle(
        _readAtMsMeta,
        readAtMs.isAcceptableOrUnknown(data['read_at_ms']!, _readAtMsMeta),
      );
    } else if (isInserting) {
      context.missing(_readAtMsMeta);
    }
    if (data.containsKey('dismissed')) {
      context.handle(
        _dismissedMeta,
        dismissed.isAcceptableOrUnknown(data['dismissed']!, _dismissedMeta),
      );
    } else if (isInserting) {
      context.missing(_dismissedMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  CoachInsight map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CoachInsight(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      insightUuid: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}insight_uuid'],
      )!,
      groupId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}group_id'],
      )!,
      targetUserId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}target_user_id'],
      )!,
      targetDisplayName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}target_display_name'],
      )!,
      typeOrdinal: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}type_ordinal'],
      )!,
      priorityOrdinal: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}priority_ordinal'],
      )!,
      title: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title'],
      )!,
      message: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}message'],
      )!,
      metricOrdinal: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}metric_ordinal'],
      )!,
      referenceValue: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}reference_value'],
      )!,
      changePercent: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}change_percent'],
      )!,
      relatedEntityId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}related_entity_id'],
      )!,
      createdAtMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_at_ms'],
      )!,
      readAtMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}read_at_ms'],
      )!,
      dismissed: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}dismissed'],
      )!,
    );
  }

  @override
  $CoachInsightsTable createAlias(String alias) {
    return $CoachInsightsTable(attachedDatabase, alias);
  }
}

class CoachInsight extends DataClass implements Insertable<CoachInsight> {
  final int id;
  final String insightUuid;
  final String groupId;
  final String targetUserId;
  final String targetDisplayName;
  final String typeOrdinal;
  final String priorityOrdinal;
  final String title;
  final String message;
  final String metricOrdinal;
  final double referenceValue;
  final double changePercent;
  final String relatedEntityId;
  final int createdAtMs;
  final int readAtMs;
  final bool dismissed;
  const CoachInsight({
    required this.id,
    required this.insightUuid,
    required this.groupId,
    required this.targetUserId,
    required this.targetDisplayName,
    required this.typeOrdinal,
    required this.priorityOrdinal,
    required this.title,
    required this.message,
    required this.metricOrdinal,
    required this.referenceValue,
    required this.changePercent,
    required this.relatedEntityId,
    required this.createdAtMs,
    required this.readAtMs,
    required this.dismissed,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['insight_uuid'] = Variable<String>(insightUuid);
    map['group_id'] = Variable<String>(groupId);
    map['target_user_id'] = Variable<String>(targetUserId);
    map['target_display_name'] = Variable<String>(targetDisplayName);
    map['type_ordinal'] = Variable<String>(typeOrdinal);
    map['priority_ordinal'] = Variable<String>(priorityOrdinal);
    map['title'] = Variable<String>(title);
    map['message'] = Variable<String>(message);
    map['metric_ordinal'] = Variable<String>(metricOrdinal);
    map['reference_value'] = Variable<double>(referenceValue);
    map['change_percent'] = Variable<double>(changePercent);
    map['related_entity_id'] = Variable<String>(relatedEntityId);
    map['created_at_ms'] = Variable<int>(createdAtMs);
    map['read_at_ms'] = Variable<int>(readAtMs);
    map['dismissed'] = Variable<bool>(dismissed);
    return map;
  }

  CoachInsightsCompanion toCompanion(bool nullToAbsent) {
    return CoachInsightsCompanion(
      id: Value(id),
      insightUuid: Value(insightUuid),
      groupId: Value(groupId),
      targetUserId: Value(targetUserId),
      targetDisplayName: Value(targetDisplayName),
      typeOrdinal: Value(typeOrdinal),
      priorityOrdinal: Value(priorityOrdinal),
      title: Value(title),
      message: Value(message),
      metricOrdinal: Value(metricOrdinal),
      referenceValue: Value(referenceValue),
      changePercent: Value(changePercent),
      relatedEntityId: Value(relatedEntityId),
      createdAtMs: Value(createdAtMs),
      readAtMs: Value(readAtMs),
      dismissed: Value(dismissed),
    );
  }

  factory CoachInsight.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CoachInsight(
      id: serializer.fromJson<int>(json['id']),
      insightUuid: serializer.fromJson<String>(json['insightUuid']),
      groupId: serializer.fromJson<String>(json['groupId']),
      targetUserId: serializer.fromJson<String>(json['targetUserId']),
      targetDisplayName: serializer.fromJson<String>(json['targetDisplayName']),
      typeOrdinal: serializer.fromJson<String>(json['typeOrdinal']),
      priorityOrdinal: serializer.fromJson<String>(json['priorityOrdinal']),
      title: serializer.fromJson<String>(json['title']),
      message: serializer.fromJson<String>(json['message']),
      metricOrdinal: serializer.fromJson<String>(json['metricOrdinal']),
      referenceValue: serializer.fromJson<double>(json['referenceValue']),
      changePercent: serializer.fromJson<double>(json['changePercent']),
      relatedEntityId: serializer.fromJson<String>(json['relatedEntityId']),
      createdAtMs: serializer.fromJson<int>(json['createdAtMs']),
      readAtMs: serializer.fromJson<int>(json['readAtMs']),
      dismissed: serializer.fromJson<bool>(json['dismissed']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'insightUuid': serializer.toJson<String>(insightUuid),
      'groupId': serializer.toJson<String>(groupId),
      'targetUserId': serializer.toJson<String>(targetUserId),
      'targetDisplayName': serializer.toJson<String>(targetDisplayName),
      'typeOrdinal': serializer.toJson<String>(typeOrdinal),
      'priorityOrdinal': serializer.toJson<String>(priorityOrdinal),
      'title': serializer.toJson<String>(title),
      'message': serializer.toJson<String>(message),
      'metricOrdinal': serializer.toJson<String>(metricOrdinal),
      'referenceValue': serializer.toJson<double>(referenceValue),
      'changePercent': serializer.toJson<double>(changePercent),
      'relatedEntityId': serializer.toJson<String>(relatedEntityId),
      'createdAtMs': serializer.toJson<int>(createdAtMs),
      'readAtMs': serializer.toJson<int>(readAtMs),
      'dismissed': serializer.toJson<bool>(dismissed),
    };
  }

  CoachInsight copyWith({
    int? id,
    String? insightUuid,
    String? groupId,
    String? targetUserId,
    String? targetDisplayName,
    String? typeOrdinal,
    String? priorityOrdinal,
    String? title,
    String? message,
    String? metricOrdinal,
    double? referenceValue,
    double? changePercent,
    String? relatedEntityId,
    int? createdAtMs,
    int? readAtMs,
    bool? dismissed,
  }) => CoachInsight(
    id: id ?? this.id,
    insightUuid: insightUuid ?? this.insightUuid,
    groupId: groupId ?? this.groupId,
    targetUserId: targetUserId ?? this.targetUserId,
    targetDisplayName: targetDisplayName ?? this.targetDisplayName,
    typeOrdinal: typeOrdinal ?? this.typeOrdinal,
    priorityOrdinal: priorityOrdinal ?? this.priorityOrdinal,
    title: title ?? this.title,
    message: message ?? this.message,
    metricOrdinal: metricOrdinal ?? this.metricOrdinal,
    referenceValue: referenceValue ?? this.referenceValue,
    changePercent: changePercent ?? this.changePercent,
    relatedEntityId: relatedEntityId ?? this.relatedEntityId,
    createdAtMs: createdAtMs ?? this.createdAtMs,
    readAtMs: readAtMs ?? this.readAtMs,
    dismissed: dismissed ?? this.dismissed,
  );
  CoachInsight copyWithCompanion(CoachInsightsCompanion data) {
    return CoachInsight(
      id: data.id.present ? data.id.value : this.id,
      insightUuid: data.insightUuid.present
          ? data.insightUuid.value
          : this.insightUuid,
      groupId: data.groupId.present ? data.groupId.value : this.groupId,
      targetUserId: data.targetUserId.present
          ? data.targetUserId.value
          : this.targetUserId,
      targetDisplayName: data.targetDisplayName.present
          ? data.targetDisplayName.value
          : this.targetDisplayName,
      typeOrdinal: data.typeOrdinal.present
          ? data.typeOrdinal.value
          : this.typeOrdinal,
      priorityOrdinal: data.priorityOrdinal.present
          ? data.priorityOrdinal.value
          : this.priorityOrdinal,
      title: data.title.present ? data.title.value : this.title,
      message: data.message.present ? data.message.value : this.message,
      metricOrdinal: data.metricOrdinal.present
          ? data.metricOrdinal.value
          : this.metricOrdinal,
      referenceValue: data.referenceValue.present
          ? data.referenceValue.value
          : this.referenceValue,
      changePercent: data.changePercent.present
          ? data.changePercent.value
          : this.changePercent,
      relatedEntityId: data.relatedEntityId.present
          ? data.relatedEntityId.value
          : this.relatedEntityId,
      createdAtMs: data.createdAtMs.present
          ? data.createdAtMs.value
          : this.createdAtMs,
      readAtMs: data.readAtMs.present ? data.readAtMs.value : this.readAtMs,
      dismissed: data.dismissed.present ? data.dismissed.value : this.dismissed,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CoachInsight(')
          ..write('id: $id, ')
          ..write('insightUuid: $insightUuid, ')
          ..write('groupId: $groupId, ')
          ..write('targetUserId: $targetUserId, ')
          ..write('targetDisplayName: $targetDisplayName, ')
          ..write('typeOrdinal: $typeOrdinal, ')
          ..write('priorityOrdinal: $priorityOrdinal, ')
          ..write('title: $title, ')
          ..write('message: $message, ')
          ..write('metricOrdinal: $metricOrdinal, ')
          ..write('referenceValue: $referenceValue, ')
          ..write('changePercent: $changePercent, ')
          ..write('relatedEntityId: $relatedEntityId, ')
          ..write('createdAtMs: $createdAtMs, ')
          ..write('readAtMs: $readAtMs, ')
          ..write('dismissed: $dismissed')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    insightUuid,
    groupId,
    targetUserId,
    targetDisplayName,
    typeOrdinal,
    priorityOrdinal,
    title,
    message,
    metricOrdinal,
    referenceValue,
    changePercent,
    relatedEntityId,
    createdAtMs,
    readAtMs,
    dismissed,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CoachInsight &&
          other.id == this.id &&
          other.insightUuid == this.insightUuid &&
          other.groupId == this.groupId &&
          other.targetUserId == this.targetUserId &&
          other.targetDisplayName == this.targetDisplayName &&
          other.typeOrdinal == this.typeOrdinal &&
          other.priorityOrdinal == this.priorityOrdinal &&
          other.title == this.title &&
          other.message == this.message &&
          other.metricOrdinal == this.metricOrdinal &&
          other.referenceValue == this.referenceValue &&
          other.changePercent == this.changePercent &&
          other.relatedEntityId == this.relatedEntityId &&
          other.createdAtMs == this.createdAtMs &&
          other.readAtMs == this.readAtMs &&
          other.dismissed == this.dismissed);
}

class CoachInsightsCompanion extends UpdateCompanion<CoachInsight> {
  final Value<int> id;
  final Value<String> insightUuid;
  final Value<String> groupId;
  final Value<String> targetUserId;
  final Value<String> targetDisplayName;
  final Value<String> typeOrdinal;
  final Value<String> priorityOrdinal;
  final Value<String> title;
  final Value<String> message;
  final Value<String> metricOrdinal;
  final Value<double> referenceValue;
  final Value<double> changePercent;
  final Value<String> relatedEntityId;
  final Value<int> createdAtMs;
  final Value<int> readAtMs;
  final Value<bool> dismissed;
  const CoachInsightsCompanion({
    this.id = const Value.absent(),
    this.insightUuid = const Value.absent(),
    this.groupId = const Value.absent(),
    this.targetUserId = const Value.absent(),
    this.targetDisplayName = const Value.absent(),
    this.typeOrdinal = const Value.absent(),
    this.priorityOrdinal = const Value.absent(),
    this.title = const Value.absent(),
    this.message = const Value.absent(),
    this.metricOrdinal = const Value.absent(),
    this.referenceValue = const Value.absent(),
    this.changePercent = const Value.absent(),
    this.relatedEntityId = const Value.absent(),
    this.createdAtMs = const Value.absent(),
    this.readAtMs = const Value.absent(),
    this.dismissed = const Value.absent(),
  });
  CoachInsightsCompanion.insert({
    this.id = const Value.absent(),
    required String insightUuid,
    required String groupId,
    required String targetUserId,
    required String targetDisplayName,
    required String typeOrdinal,
    required String priorityOrdinal,
    required String title,
    required String message,
    required String metricOrdinal,
    required double referenceValue,
    required double changePercent,
    required String relatedEntityId,
    required int createdAtMs,
    required int readAtMs,
    required bool dismissed,
  }) : insightUuid = Value(insightUuid),
       groupId = Value(groupId),
       targetUserId = Value(targetUserId),
       targetDisplayName = Value(targetDisplayName),
       typeOrdinal = Value(typeOrdinal),
       priorityOrdinal = Value(priorityOrdinal),
       title = Value(title),
       message = Value(message),
       metricOrdinal = Value(metricOrdinal),
       referenceValue = Value(referenceValue),
       changePercent = Value(changePercent),
       relatedEntityId = Value(relatedEntityId),
       createdAtMs = Value(createdAtMs),
       readAtMs = Value(readAtMs),
       dismissed = Value(dismissed);
  static Insertable<CoachInsight> custom({
    Expression<int>? id,
    Expression<String>? insightUuid,
    Expression<String>? groupId,
    Expression<String>? targetUserId,
    Expression<String>? targetDisplayName,
    Expression<String>? typeOrdinal,
    Expression<String>? priorityOrdinal,
    Expression<String>? title,
    Expression<String>? message,
    Expression<String>? metricOrdinal,
    Expression<double>? referenceValue,
    Expression<double>? changePercent,
    Expression<String>? relatedEntityId,
    Expression<int>? createdAtMs,
    Expression<int>? readAtMs,
    Expression<bool>? dismissed,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (insightUuid != null) 'insight_uuid': insightUuid,
      if (groupId != null) 'group_id': groupId,
      if (targetUserId != null) 'target_user_id': targetUserId,
      if (targetDisplayName != null) 'target_display_name': targetDisplayName,
      if (typeOrdinal != null) 'type_ordinal': typeOrdinal,
      if (priorityOrdinal != null) 'priority_ordinal': priorityOrdinal,
      if (title != null) 'title': title,
      if (message != null) 'message': message,
      if (metricOrdinal != null) 'metric_ordinal': metricOrdinal,
      if (referenceValue != null) 'reference_value': referenceValue,
      if (changePercent != null) 'change_percent': changePercent,
      if (relatedEntityId != null) 'related_entity_id': relatedEntityId,
      if (createdAtMs != null) 'created_at_ms': createdAtMs,
      if (readAtMs != null) 'read_at_ms': readAtMs,
      if (dismissed != null) 'dismissed': dismissed,
    });
  }

  CoachInsightsCompanion copyWith({
    Value<int>? id,
    Value<String>? insightUuid,
    Value<String>? groupId,
    Value<String>? targetUserId,
    Value<String>? targetDisplayName,
    Value<String>? typeOrdinal,
    Value<String>? priorityOrdinal,
    Value<String>? title,
    Value<String>? message,
    Value<String>? metricOrdinal,
    Value<double>? referenceValue,
    Value<double>? changePercent,
    Value<String>? relatedEntityId,
    Value<int>? createdAtMs,
    Value<int>? readAtMs,
    Value<bool>? dismissed,
  }) {
    return CoachInsightsCompanion(
      id: id ?? this.id,
      insightUuid: insightUuid ?? this.insightUuid,
      groupId: groupId ?? this.groupId,
      targetUserId: targetUserId ?? this.targetUserId,
      targetDisplayName: targetDisplayName ?? this.targetDisplayName,
      typeOrdinal: typeOrdinal ?? this.typeOrdinal,
      priorityOrdinal: priorityOrdinal ?? this.priorityOrdinal,
      title: title ?? this.title,
      message: message ?? this.message,
      metricOrdinal: metricOrdinal ?? this.metricOrdinal,
      referenceValue: referenceValue ?? this.referenceValue,
      changePercent: changePercent ?? this.changePercent,
      relatedEntityId: relatedEntityId ?? this.relatedEntityId,
      createdAtMs: createdAtMs ?? this.createdAtMs,
      readAtMs: readAtMs ?? this.readAtMs,
      dismissed: dismissed ?? this.dismissed,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (insightUuid.present) {
      map['insight_uuid'] = Variable<String>(insightUuid.value);
    }
    if (groupId.present) {
      map['group_id'] = Variable<String>(groupId.value);
    }
    if (targetUserId.present) {
      map['target_user_id'] = Variable<String>(targetUserId.value);
    }
    if (targetDisplayName.present) {
      map['target_display_name'] = Variable<String>(targetDisplayName.value);
    }
    if (typeOrdinal.present) {
      map['type_ordinal'] = Variable<String>(typeOrdinal.value);
    }
    if (priorityOrdinal.present) {
      map['priority_ordinal'] = Variable<String>(priorityOrdinal.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (message.present) {
      map['message'] = Variable<String>(message.value);
    }
    if (metricOrdinal.present) {
      map['metric_ordinal'] = Variable<String>(metricOrdinal.value);
    }
    if (referenceValue.present) {
      map['reference_value'] = Variable<double>(referenceValue.value);
    }
    if (changePercent.present) {
      map['change_percent'] = Variable<double>(changePercent.value);
    }
    if (relatedEntityId.present) {
      map['related_entity_id'] = Variable<String>(relatedEntityId.value);
    }
    if (createdAtMs.present) {
      map['created_at_ms'] = Variable<int>(createdAtMs.value);
    }
    if (readAtMs.present) {
      map['read_at_ms'] = Variable<int>(readAtMs.value);
    }
    if (dismissed.present) {
      map['dismissed'] = Variable<bool>(dismissed.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CoachInsightsCompanion(')
          ..write('id: $id, ')
          ..write('insightUuid: $insightUuid, ')
          ..write('groupId: $groupId, ')
          ..write('targetUserId: $targetUserId, ')
          ..write('targetDisplayName: $targetDisplayName, ')
          ..write('typeOrdinal: $typeOrdinal, ')
          ..write('priorityOrdinal: $priorityOrdinal, ')
          ..write('title: $title, ')
          ..write('message: $message, ')
          ..write('metricOrdinal: $metricOrdinal, ')
          ..write('referenceValue: $referenceValue, ')
          ..write('changePercent: $changePercent, ')
          ..write('relatedEntityId: $relatedEntityId, ')
          ..write('createdAtMs: $createdAtMs, ')
          ..write('readAtMs: $readAtMs, ')
          ..write('dismissed: $dismissed')
          ..write(')'))
        .toString();
  }
}

class $FriendshipsTable extends Friendships
    with TableInfo<$FriendshipsTable, Friendship> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $FriendshipsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _friendshipUuidMeta = const VerificationMeta(
    'friendshipUuid',
  );
  @override
  late final GeneratedColumn<String> friendshipUuid = GeneratedColumn<String>(
    'friendship_uuid',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways('UNIQUE'),
  );
  static const VerificationMeta _userIdAMeta = const VerificationMeta(
    'userIdA',
  );
  @override
  late final GeneratedColumn<String> userIdA = GeneratedColumn<String>(
    'user_id_a',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _userIdBMeta = const VerificationMeta(
    'userIdB',
  );
  @override
  late final GeneratedColumn<String> userIdB = GeneratedColumn<String>(
    'user_id_b',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _statusOrdinalMeta = const VerificationMeta(
    'statusOrdinal',
  );
  @override
  late final GeneratedColumn<String> statusOrdinal = GeneratedColumn<String>(
    'status_ordinal',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _createdAtMsMeta = const VerificationMeta(
    'createdAtMs',
  );
  @override
  late final GeneratedColumn<int> createdAtMs = GeneratedColumn<int>(
    'created_at_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _acceptedAtMsMeta = const VerificationMeta(
    'acceptedAtMs',
  );
  @override
  late final GeneratedColumn<int> acceptedAtMs = GeneratedColumn<int>(
    'accepted_at_ms',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    friendshipUuid,
    userIdA,
    userIdB,
    statusOrdinal,
    createdAtMs,
    acceptedAtMs,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'friendships';
  @override
  VerificationContext validateIntegrity(
    Insertable<Friendship> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('friendship_uuid')) {
      context.handle(
        _friendshipUuidMeta,
        friendshipUuid.isAcceptableOrUnknown(
          data['friendship_uuid']!,
          _friendshipUuidMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_friendshipUuidMeta);
    }
    if (data.containsKey('user_id_a')) {
      context.handle(
        _userIdAMeta,
        userIdA.isAcceptableOrUnknown(data['user_id_a']!, _userIdAMeta),
      );
    } else if (isInserting) {
      context.missing(_userIdAMeta);
    }
    if (data.containsKey('user_id_b')) {
      context.handle(
        _userIdBMeta,
        userIdB.isAcceptableOrUnknown(data['user_id_b']!, _userIdBMeta),
      );
    } else if (isInserting) {
      context.missing(_userIdBMeta);
    }
    if (data.containsKey('status_ordinal')) {
      context.handle(
        _statusOrdinalMeta,
        statusOrdinal.isAcceptableOrUnknown(
          data['status_ordinal']!,
          _statusOrdinalMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_statusOrdinalMeta);
    }
    if (data.containsKey('created_at_ms')) {
      context.handle(
        _createdAtMsMeta,
        createdAtMs.isAcceptableOrUnknown(
          data['created_at_ms']!,
          _createdAtMsMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_createdAtMsMeta);
    }
    if (data.containsKey('accepted_at_ms')) {
      context.handle(
        _acceptedAtMsMeta,
        acceptedAtMs.isAcceptableOrUnknown(
          data['accepted_at_ms']!,
          _acceptedAtMsMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  List<Set<GeneratedColumn>> get uniqueKeys => [
    {userIdA, userIdB},
  ];
  @override
  Friendship map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Friendship(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      friendshipUuid: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}friendship_uuid'],
      )!,
      userIdA: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}user_id_a'],
      )!,
      userIdB: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}user_id_b'],
      )!,
      statusOrdinal: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}status_ordinal'],
      )!,
      createdAtMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_at_ms'],
      )!,
      acceptedAtMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}accepted_at_ms'],
      ),
    );
  }

  @override
  $FriendshipsTable createAlias(String alias) {
    return $FriendshipsTable(attachedDatabase, alias);
  }
}

class Friendship extends DataClass implements Insertable<Friendship> {
  final int id;
  final String friendshipUuid;
  final String userIdA;
  final String userIdB;
  final String statusOrdinal;
  final int createdAtMs;
  final int? acceptedAtMs;
  const Friendship({
    required this.id,
    required this.friendshipUuid,
    required this.userIdA,
    required this.userIdB,
    required this.statusOrdinal,
    required this.createdAtMs,
    this.acceptedAtMs,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['friendship_uuid'] = Variable<String>(friendshipUuid);
    map['user_id_a'] = Variable<String>(userIdA);
    map['user_id_b'] = Variable<String>(userIdB);
    map['status_ordinal'] = Variable<String>(statusOrdinal);
    map['created_at_ms'] = Variable<int>(createdAtMs);
    if (!nullToAbsent || acceptedAtMs != null) {
      map['accepted_at_ms'] = Variable<int>(acceptedAtMs);
    }
    return map;
  }

  FriendshipsCompanion toCompanion(bool nullToAbsent) {
    return FriendshipsCompanion(
      id: Value(id),
      friendshipUuid: Value(friendshipUuid),
      userIdA: Value(userIdA),
      userIdB: Value(userIdB),
      statusOrdinal: Value(statusOrdinal),
      createdAtMs: Value(createdAtMs),
      acceptedAtMs: acceptedAtMs == null && nullToAbsent
          ? const Value.absent()
          : Value(acceptedAtMs),
    );
  }

  factory Friendship.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Friendship(
      id: serializer.fromJson<int>(json['id']),
      friendshipUuid: serializer.fromJson<String>(json['friendshipUuid']),
      userIdA: serializer.fromJson<String>(json['userIdA']),
      userIdB: serializer.fromJson<String>(json['userIdB']),
      statusOrdinal: serializer.fromJson<String>(json['statusOrdinal']),
      createdAtMs: serializer.fromJson<int>(json['createdAtMs']),
      acceptedAtMs: serializer.fromJson<int?>(json['acceptedAtMs']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'friendshipUuid': serializer.toJson<String>(friendshipUuid),
      'userIdA': serializer.toJson<String>(userIdA),
      'userIdB': serializer.toJson<String>(userIdB),
      'statusOrdinal': serializer.toJson<String>(statusOrdinal),
      'createdAtMs': serializer.toJson<int>(createdAtMs),
      'acceptedAtMs': serializer.toJson<int?>(acceptedAtMs),
    };
  }

  Friendship copyWith({
    int? id,
    String? friendshipUuid,
    String? userIdA,
    String? userIdB,
    String? statusOrdinal,
    int? createdAtMs,
    Value<int?> acceptedAtMs = const Value.absent(),
  }) => Friendship(
    id: id ?? this.id,
    friendshipUuid: friendshipUuid ?? this.friendshipUuid,
    userIdA: userIdA ?? this.userIdA,
    userIdB: userIdB ?? this.userIdB,
    statusOrdinal: statusOrdinal ?? this.statusOrdinal,
    createdAtMs: createdAtMs ?? this.createdAtMs,
    acceptedAtMs: acceptedAtMs.present ? acceptedAtMs.value : this.acceptedAtMs,
  );
  Friendship copyWithCompanion(FriendshipsCompanion data) {
    return Friendship(
      id: data.id.present ? data.id.value : this.id,
      friendshipUuid: data.friendshipUuid.present
          ? data.friendshipUuid.value
          : this.friendshipUuid,
      userIdA: data.userIdA.present ? data.userIdA.value : this.userIdA,
      userIdB: data.userIdB.present ? data.userIdB.value : this.userIdB,
      statusOrdinal: data.statusOrdinal.present
          ? data.statusOrdinal.value
          : this.statusOrdinal,
      createdAtMs: data.createdAtMs.present
          ? data.createdAtMs.value
          : this.createdAtMs,
      acceptedAtMs: data.acceptedAtMs.present
          ? data.acceptedAtMs.value
          : this.acceptedAtMs,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Friendship(')
          ..write('id: $id, ')
          ..write('friendshipUuid: $friendshipUuid, ')
          ..write('userIdA: $userIdA, ')
          ..write('userIdB: $userIdB, ')
          ..write('statusOrdinal: $statusOrdinal, ')
          ..write('createdAtMs: $createdAtMs, ')
          ..write('acceptedAtMs: $acceptedAtMs')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    friendshipUuid,
    userIdA,
    userIdB,
    statusOrdinal,
    createdAtMs,
    acceptedAtMs,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Friendship &&
          other.id == this.id &&
          other.friendshipUuid == this.friendshipUuid &&
          other.userIdA == this.userIdA &&
          other.userIdB == this.userIdB &&
          other.statusOrdinal == this.statusOrdinal &&
          other.createdAtMs == this.createdAtMs &&
          other.acceptedAtMs == this.acceptedAtMs);
}

class FriendshipsCompanion extends UpdateCompanion<Friendship> {
  final Value<int> id;
  final Value<String> friendshipUuid;
  final Value<String> userIdA;
  final Value<String> userIdB;
  final Value<String> statusOrdinal;
  final Value<int> createdAtMs;
  final Value<int?> acceptedAtMs;
  const FriendshipsCompanion({
    this.id = const Value.absent(),
    this.friendshipUuid = const Value.absent(),
    this.userIdA = const Value.absent(),
    this.userIdB = const Value.absent(),
    this.statusOrdinal = const Value.absent(),
    this.createdAtMs = const Value.absent(),
    this.acceptedAtMs = const Value.absent(),
  });
  FriendshipsCompanion.insert({
    this.id = const Value.absent(),
    required String friendshipUuid,
    required String userIdA,
    required String userIdB,
    required String statusOrdinal,
    required int createdAtMs,
    this.acceptedAtMs = const Value.absent(),
  }) : friendshipUuid = Value(friendshipUuid),
       userIdA = Value(userIdA),
       userIdB = Value(userIdB),
       statusOrdinal = Value(statusOrdinal),
       createdAtMs = Value(createdAtMs);
  static Insertable<Friendship> custom({
    Expression<int>? id,
    Expression<String>? friendshipUuid,
    Expression<String>? userIdA,
    Expression<String>? userIdB,
    Expression<String>? statusOrdinal,
    Expression<int>? createdAtMs,
    Expression<int>? acceptedAtMs,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (friendshipUuid != null) 'friendship_uuid': friendshipUuid,
      if (userIdA != null) 'user_id_a': userIdA,
      if (userIdB != null) 'user_id_b': userIdB,
      if (statusOrdinal != null) 'status_ordinal': statusOrdinal,
      if (createdAtMs != null) 'created_at_ms': createdAtMs,
      if (acceptedAtMs != null) 'accepted_at_ms': acceptedAtMs,
    });
  }

  FriendshipsCompanion copyWith({
    Value<int>? id,
    Value<String>? friendshipUuid,
    Value<String>? userIdA,
    Value<String>? userIdB,
    Value<String>? statusOrdinal,
    Value<int>? createdAtMs,
    Value<int?>? acceptedAtMs,
  }) {
    return FriendshipsCompanion(
      id: id ?? this.id,
      friendshipUuid: friendshipUuid ?? this.friendshipUuid,
      userIdA: userIdA ?? this.userIdA,
      userIdB: userIdB ?? this.userIdB,
      statusOrdinal: statusOrdinal ?? this.statusOrdinal,
      createdAtMs: createdAtMs ?? this.createdAtMs,
      acceptedAtMs: acceptedAtMs ?? this.acceptedAtMs,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (friendshipUuid.present) {
      map['friendship_uuid'] = Variable<String>(friendshipUuid.value);
    }
    if (userIdA.present) {
      map['user_id_a'] = Variable<String>(userIdA.value);
    }
    if (userIdB.present) {
      map['user_id_b'] = Variable<String>(userIdB.value);
    }
    if (statusOrdinal.present) {
      map['status_ordinal'] = Variable<String>(statusOrdinal.value);
    }
    if (createdAtMs.present) {
      map['created_at_ms'] = Variable<int>(createdAtMs.value);
    }
    if (acceptedAtMs.present) {
      map['accepted_at_ms'] = Variable<int>(acceptedAtMs.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('FriendshipsCompanion(')
          ..write('id: $id, ')
          ..write('friendshipUuid: $friendshipUuid, ')
          ..write('userIdA: $userIdA, ')
          ..write('userIdB: $userIdB, ')
          ..write('statusOrdinal: $statusOrdinal, ')
          ..write('createdAtMs: $createdAtMs, ')
          ..write('acceptedAtMs: $acceptedAtMs')
          ..write(')'))
        .toString();
  }
}

class $GroupsTable extends Groups with TableInfo<$GroupsTable, Group> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $GroupsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _groupUuidMeta = const VerificationMeta(
    'groupUuid',
  );
  @override
  late final GeneratedColumn<String> groupUuid = GeneratedColumn<String>(
    'group_uuid',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways('UNIQUE'),
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _descriptionMeta = const VerificationMeta(
    'description',
  );
  @override
  late final GeneratedColumn<String> description = GeneratedColumn<String>(
    'description',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _avatarUrlMeta = const VerificationMeta(
    'avatarUrl',
  );
  @override
  late final GeneratedColumn<String> avatarUrl = GeneratedColumn<String>(
    'avatar_url',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdByUserIdMeta = const VerificationMeta(
    'createdByUserId',
  );
  @override
  late final GeneratedColumn<String> createdByUserId = GeneratedColumn<String>(
    'created_by_user_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _createdAtMsMeta = const VerificationMeta(
    'createdAtMs',
  );
  @override
  late final GeneratedColumn<int> createdAtMs = GeneratedColumn<int>(
    'created_at_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _privacyOrdinalMeta = const VerificationMeta(
    'privacyOrdinal',
  );
  @override
  late final GeneratedColumn<String> privacyOrdinal = GeneratedColumn<String>(
    'privacy_ordinal',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _maxMembersMeta = const VerificationMeta(
    'maxMembers',
  );
  @override
  late final GeneratedColumn<int> maxMembers = GeneratedColumn<int>(
    'max_members',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _memberCountMeta = const VerificationMeta(
    'memberCount',
  );
  @override
  late final GeneratedColumn<int> memberCount = GeneratedColumn<int>(
    'member_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    groupUuid,
    name,
    description,
    avatarUrl,
    createdByUserId,
    createdAtMs,
    privacyOrdinal,
    maxMembers,
    memberCount,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'groups';
  @override
  VerificationContext validateIntegrity(
    Insertable<Group> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('group_uuid')) {
      context.handle(
        _groupUuidMeta,
        groupUuid.isAcceptableOrUnknown(data['group_uuid']!, _groupUuidMeta),
      );
    } else if (isInserting) {
      context.missing(_groupUuidMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('description')) {
      context.handle(
        _descriptionMeta,
        description.isAcceptableOrUnknown(
          data['description']!,
          _descriptionMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_descriptionMeta);
    }
    if (data.containsKey('avatar_url')) {
      context.handle(
        _avatarUrlMeta,
        avatarUrl.isAcceptableOrUnknown(data['avatar_url']!, _avatarUrlMeta),
      );
    }
    if (data.containsKey('created_by_user_id')) {
      context.handle(
        _createdByUserIdMeta,
        createdByUserId.isAcceptableOrUnknown(
          data['created_by_user_id']!,
          _createdByUserIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_createdByUserIdMeta);
    }
    if (data.containsKey('created_at_ms')) {
      context.handle(
        _createdAtMsMeta,
        createdAtMs.isAcceptableOrUnknown(
          data['created_at_ms']!,
          _createdAtMsMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_createdAtMsMeta);
    }
    if (data.containsKey('privacy_ordinal')) {
      context.handle(
        _privacyOrdinalMeta,
        privacyOrdinal.isAcceptableOrUnknown(
          data['privacy_ordinal']!,
          _privacyOrdinalMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_privacyOrdinalMeta);
    }
    if (data.containsKey('max_members')) {
      context.handle(
        _maxMembersMeta,
        maxMembers.isAcceptableOrUnknown(data['max_members']!, _maxMembersMeta),
      );
    } else if (isInserting) {
      context.missing(_maxMembersMeta);
    }
    if (data.containsKey('member_count')) {
      context.handle(
        _memberCountMeta,
        memberCount.isAcceptableOrUnknown(
          data['member_count']!,
          _memberCountMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_memberCountMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Group map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Group(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      groupUuid: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}group_uuid'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      description: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}description'],
      )!,
      avatarUrl: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}avatar_url'],
      ),
      createdByUserId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}created_by_user_id'],
      )!,
      createdAtMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_at_ms'],
      )!,
      privacyOrdinal: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}privacy_ordinal'],
      )!,
      maxMembers: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}max_members'],
      )!,
      memberCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}member_count'],
      )!,
    );
  }

  @override
  $GroupsTable createAlias(String alias) {
    return $GroupsTable(attachedDatabase, alias);
  }
}

class Group extends DataClass implements Insertable<Group> {
  final int id;
  final String groupUuid;
  final String name;
  final String description;
  final String? avatarUrl;
  final String createdByUserId;
  final int createdAtMs;
  final String privacyOrdinal;
  final int maxMembers;
  final int memberCount;
  const Group({
    required this.id,
    required this.groupUuid,
    required this.name,
    required this.description,
    this.avatarUrl,
    required this.createdByUserId,
    required this.createdAtMs,
    required this.privacyOrdinal,
    required this.maxMembers,
    required this.memberCount,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['group_uuid'] = Variable<String>(groupUuid);
    map['name'] = Variable<String>(name);
    map['description'] = Variable<String>(description);
    if (!nullToAbsent || avatarUrl != null) {
      map['avatar_url'] = Variable<String>(avatarUrl);
    }
    map['created_by_user_id'] = Variable<String>(createdByUserId);
    map['created_at_ms'] = Variable<int>(createdAtMs);
    map['privacy_ordinal'] = Variable<String>(privacyOrdinal);
    map['max_members'] = Variable<int>(maxMembers);
    map['member_count'] = Variable<int>(memberCount);
    return map;
  }

  GroupsCompanion toCompanion(bool nullToAbsent) {
    return GroupsCompanion(
      id: Value(id),
      groupUuid: Value(groupUuid),
      name: Value(name),
      description: Value(description),
      avatarUrl: avatarUrl == null && nullToAbsent
          ? const Value.absent()
          : Value(avatarUrl),
      createdByUserId: Value(createdByUserId),
      createdAtMs: Value(createdAtMs),
      privacyOrdinal: Value(privacyOrdinal),
      maxMembers: Value(maxMembers),
      memberCount: Value(memberCount),
    );
  }

  factory Group.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Group(
      id: serializer.fromJson<int>(json['id']),
      groupUuid: serializer.fromJson<String>(json['groupUuid']),
      name: serializer.fromJson<String>(json['name']),
      description: serializer.fromJson<String>(json['description']),
      avatarUrl: serializer.fromJson<String?>(json['avatarUrl']),
      createdByUserId: serializer.fromJson<String>(json['createdByUserId']),
      createdAtMs: serializer.fromJson<int>(json['createdAtMs']),
      privacyOrdinal: serializer.fromJson<String>(json['privacyOrdinal']),
      maxMembers: serializer.fromJson<int>(json['maxMembers']),
      memberCount: serializer.fromJson<int>(json['memberCount']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'groupUuid': serializer.toJson<String>(groupUuid),
      'name': serializer.toJson<String>(name),
      'description': serializer.toJson<String>(description),
      'avatarUrl': serializer.toJson<String?>(avatarUrl),
      'createdByUserId': serializer.toJson<String>(createdByUserId),
      'createdAtMs': serializer.toJson<int>(createdAtMs),
      'privacyOrdinal': serializer.toJson<String>(privacyOrdinal),
      'maxMembers': serializer.toJson<int>(maxMembers),
      'memberCount': serializer.toJson<int>(memberCount),
    };
  }

  Group copyWith({
    int? id,
    String? groupUuid,
    String? name,
    String? description,
    Value<String?> avatarUrl = const Value.absent(),
    String? createdByUserId,
    int? createdAtMs,
    String? privacyOrdinal,
    int? maxMembers,
    int? memberCount,
  }) => Group(
    id: id ?? this.id,
    groupUuid: groupUuid ?? this.groupUuid,
    name: name ?? this.name,
    description: description ?? this.description,
    avatarUrl: avatarUrl.present ? avatarUrl.value : this.avatarUrl,
    createdByUserId: createdByUserId ?? this.createdByUserId,
    createdAtMs: createdAtMs ?? this.createdAtMs,
    privacyOrdinal: privacyOrdinal ?? this.privacyOrdinal,
    maxMembers: maxMembers ?? this.maxMembers,
    memberCount: memberCount ?? this.memberCount,
  );
  Group copyWithCompanion(GroupsCompanion data) {
    return Group(
      id: data.id.present ? data.id.value : this.id,
      groupUuid: data.groupUuid.present ? data.groupUuid.value : this.groupUuid,
      name: data.name.present ? data.name.value : this.name,
      description: data.description.present
          ? data.description.value
          : this.description,
      avatarUrl: data.avatarUrl.present ? data.avatarUrl.value : this.avatarUrl,
      createdByUserId: data.createdByUserId.present
          ? data.createdByUserId.value
          : this.createdByUserId,
      createdAtMs: data.createdAtMs.present
          ? data.createdAtMs.value
          : this.createdAtMs,
      privacyOrdinal: data.privacyOrdinal.present
          ? data.privacyOrdinal.value
          : this.privacyOrdinal,
      maxMembers: data.maxMembers.present
          ? data.maxMembers.value
          : this.maxMembers,
      memberCount: data.memberCount.present
          ? data.memberCount.value
          : this.memberCount,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Group(')
          ..write('id: $id, ')
          ..write('groupUuid: $groupUuid, ')
          ..write('name: $name, ')
          ..write('description: $description, ')
          ..write('avatarUrl: $avatarUrl, ')
          ..write('createdByUserId: $createdByUserId, ')
          ..write('createdAtMs: $createdAtMs, ')
          ..write('privacyOrdinal: $privacyOrdinal, ')
          ..write('maxMembers: $maxMembers, ')
          ..write('memberCount: $memberCount')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    groupUuid,
    name,
    description,
    avatarUrl,
    createdByUserId,
    createdAtMs,
    privacyOrdinal,
    maxMembers,
    memberCount,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Group &&
          other.id == this.id &&
          other.groupUuid == this.groupUuid &&
          other.name == this.name &&
          other.description == this.description &&
          other.avatarUrl == this.avatarUrl &&
          other.createdByUserId == this.createdByUserId &&
          other.createdAtMs == this.createdAtMs &&
          other.privacyOrdinal == this.privacyOrdinal &&
          other.maxMembers == this.maxMembers &&
          other.memberCount == this.memberCount);
}

class GroupsCompanion extends UpdateCompanion<Group> {
  final Value<int> id;
  final Value<String> groupUuid;
  final Value<String> name;
  final Value<String> description;
  final Value<String?> avatarUrl;
  final Value<String> createdByUserId;
  final Value<int> createdAtMs;
  final Value<String> privacyOrdinal;
  final Value<int> maxMembers;
  final Value<int> memberCount;
  const GroupsCompanion({
    this.id = const Value.absent(),
    this.groupUuid = const Value.absent(),
    this.name = const Value.absent(),
    this.description = const Value.absent(),
    this.avatarUrl = const Value.absent(),
    this.createdByUserId = const Value.absent(),
    this.createdAtMs = const Value.absent(),
    this.privacyOrdinal = const Value.absent(),
    this.maxMembers = const Value.absent(),
    this.memberCount = const Value.absent(),
  });
  GroupsCompanion.insert({
    this.id = const Value.absent(),
    required String groupUuid,
    required String name,
    required String description,
    this.avatarUrl = const Value.absent(),
    required String createdByUserId,
    required int createdAtMs,
    required String privacyOrdinal,
    required int maxMembers,
    required int memberCount,
  }) : groupUuid = Value(groupUuid),
       name = Value(name),
       description = Value(description),
       createdByUserId = Value(createdByUserId),
       createdAtMs = Value(createdAtMs),
       privacyOrdinal = Value(privacyOrdinal),
       maxMembers = Value(maxMembers),
       memberCount = Value(memberCount);
  static Insertable<Group> custom({
    Expression<int>? id,
    Expression<String>? groupUuid,
    Expression<String>? name,
    Expression<String>? description,
    Expression<String>? avatarUrl,
    Expression<String>? createdByUserId,
    Expression<int>? createdAtMs,
    Expression<String>? privacyOrdinal,
    Expression<int>? maxMembers,
    Expression<int>? memberCount,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (groupUuid != null) 'group_uuid': groupUuid,
      if (name != null) 'name': name,
      if (description != null) 'description': description,
      if (avatarUrl != null) 'avatar_url': avatarUrl,
      if (createdByUserId != null) 'created_by_user_id': createdByUserId,
      if (createdAtMs != null) 'created_at_ms': createdAtMs,
      if (privacyOrdinal != null) 'privacy_ordinal': privacyOrdinal,
      if (maxMembers != null) 'max_members': maxMembers,
      if (memberCount != null) 'member_count': memberCount,
    });
  }

  GroupsCompanion copyWith({
    Value<int>? id,
    Value<String>? groupUuid,
    Value<String>? name,
    Value<String>? description,
    Value<String?>? avatarUrl,
    Value<String>? createdByUserId,
    Value<int>? createdAtMs,
    Value<String>? privacyOrdinal,
    Value<int>? maxMembers,
    Value<int>? memberCount,
  }) {
    return GroupsCompanion(
      id: id ?? this.id,
      groupUuid: groupUuid ?? this.groupUuid,
      name: name ?? this.name,
      description: description ?? this.description,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      createdByUserId: createdByUserId ?? this.createdByUserId,
      createdAtMs: createdAtMs ?? this.createdAtMs,
      privacyOrdinal: privacyOrdinal ?? this.privacyOrdinal,
      maxMembers: maxMembers ?? this.maxMembers,
      memberCount: memberCount ?? this.memberCount,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (groupUuid.present) {
      map['group_uuid'] = Variable<String>(groupUuid.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (description.present) {
      map['description'] = Variable<String>(description.value);
    }
    if (avatarUrl.present) {
      map['avatar_url'] = Variable<String>(avatarUrl.value);
    }
    if (createdByUserId.present) {
      map['created_by_user_id'] = Variable<String>(createdByUserId.value);
    }
    if (createdAtMs.present) {
      map['created_at_ms'] = Variable<int>(createdAtMs.value);
    }
    if (privacyOrdinal.present) {
      map['privacy_ordinal'] = Variable<String>(privacyOrdinal.value);
    }
    if (maxMembers.present) {
      map['max_members'] = Variable<int>(maxMembers.value);
    }
    if (memberCount.present) {
      map['member_count'] = Variable<int>(memberCount.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('GroupsCompanion(')
          ..write('id: $id, ')
          ..write('groupUuid: $groupUuid, ')
          ..write('name: $name, ')
          ..write('description: $description, ')
          ..write('avatarUrl: $avatarUrl, ')
          ..write('createdByUserId: $createdByUserId, ')
          ..write('createdAtMs: $createdAtMs, ')
          ..write('privacyOrdinal: $privacyOrdinal, ')
          ..write('maxMembers: $maxMembers, ')
          ..write('memberCount: $memberCount')
          ..write(')'))
        .toString();
  }
}

class $GroupMembersTable extends GroupMembers
    with TableInfo<$GroupMembersTable, GroupMember> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $GroupMembersTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _memberUuidMeta = const VerificationMeta(
    'memberUuid',
  );
  @override
  late final GeneratedColumn<String> memberUuid = GeneratedColumn<String>(
    'member_uuid',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways('UNIQUE'),
  );
  static const VerificationMeta _groupIdMeta = const VerificationMeta(
    'groupId',
  );
  @override
  late final GeneratedColumn<String> groupId = GeneratedColumn<String>(
    'group_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _userIdMeta = const VerificationMeta('userId');
  @override
  late final GeneratedColumn<String> userId = GeneratedColumn<String>(
    'user_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _displayNameMeta = const VerificationMeta(
    'displayName',
  );
  @override
  late final GeneratedColumn<String> displayName = GeneratedColumn<String>(
    'display_name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _roleOrdinalMeta = const VerificationMeta(
    'roleOrdinal',
  );
  @override
  late final GeneratedColumn<String> roleOrdinal = GeneratedColumn<String>(
    'role_ordinal',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _statusOrdinalMeta = const VerificationMeta(
    'statusOrdinal',
  );
  @override
  late final GeneratedColumn<String> statusOrdinal = GeneratedColumn<String>(
    'status_ordinal',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _joinedAtMsMeta = const VerificationMeta(
    'joinedAtMs',
  );
  @override
  late final GeneratedColumn<int> joinedAtMs = GeneratedColumn<int>(
    'joined_at_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    memberUuid,
    groupId,
    userId,
    displayName,
    roleOrdinal,
    statusOrdinal,
    joinedAtMs,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'group_members';
  @override
  VerificationContext validateIntegrity(
    Insertable<GroupMember> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('member_uuid')) {
      context.handle(
        _memberUuidMeta,
        memberUuid.isAcceptableOrUnknown(data['member_uuid']!, _memberUuidMeta),
      );
    } else if (isInserting) {
      context.missing(_memberUuidMeta);
    }
    if (data.containsKey('group_id')) {
      context.handle(
        _groupIdMeta,
        groupId.isAcceptableOrUnknown(data['group_id']!, _groupIdMeta),
      );
    } else if (isInserting) {
      context.missing(_groupIdMeta);
    }
    if (data.containsKey('user_id')) {
      context.handle(
        _userIdMeta,
        userId.isAcceptableOrUnknown(data['user_id']!, _userIdMeta),
      );
    } else if (isInserting) {
      context.missing(_userIdMeta);
    }
    if (data.containsKey('display_name')) {
      context.handle(
        _displayNameMeta,
        displayName.isAcceptableOrUnknown(
          data['display_name']!,
          _displayNameMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_displayNameMeta);
    }
    if (data.containsKey('role_ordinal')) {
      context.handle(
        _roleOrdinalMeta,
        roleOrdinal.isAcceptableOrUnknown(
          data['role_ordinal']!,
          _roleOrdinalMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_roleOrdinalMeta);
    }
    if (data.containsKey('status_ordinal')) {
      context.handle(
        _statusOrdinalMeta,
        statusOrdinal.isAcceptableOrUnknown(
          data['status_ordinal']!,
          _statusOrdinalMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_statusOrdinalMeta);
    }
    if (data.containsKey('joined_at_ms')) {
      context.handle(
        _joinedAtMsMeta,
        joinedAtMs.isAcceptableOrUnknown(
          data['joined_at_ms']!,
          _joinedAtMsMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_joinedAtMsMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  GroupMember map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return GroupMember(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      memberUuid: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}member_uuid'],
      )!,
      groupId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}group_id'],
      )!,
      userId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}user_id'],
      )!,
      displayName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}display_name'],
      )!,
      roleOrdinal: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}role_ordinal'],
      )!,
      statusOrdinal: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}status_ordinal'],
      )!,
      joinedAtMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}joined_at_ms'],
      )!,
    );
  }

  @override
  $GroupMembersTable createAlias(String alias) {
    return $GroupMembersTable(attachedDatabase, alias);
  }
}

class GroupMember extends DataClass implements Insertable<GroupMember> {
  final int id;
  final String memberUuid;
  final String groupId;
  final String userId;
  final String displayName;
  final String roleOrdinal;
  final String statusOrdinal;
  final int joinedAtMs;
  const GroupMember({
    required this.id,
    required this.memberUuid,
    required this.groupId,
    required this.userId,
    required this.displayName,
    required this.roleOrdinal,
    required this.statusOrdinal,
    required this.joinedAtMs,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['member_uuid'] = Variable<String>(memberUuid);
    map['group_id'] = Variable<String>(groupId);
    map['user_id'] = Variable<String>(userId);
    map['display_name'] = Variable<String>(displayName);
    map['role_ordinal'] = Variable<String>(roleOrdinal);
    map['status_ordinal'] = Variable<String>(statusOrdinal);
    map['joined_at_ms'] = Variable<int>(joinedAtMs);
    return map;
  }

  GroupMembersCompanion toCompanion(bool nullToAbsent) {
    return GroupMembersCompanion(
      id: Value(id),
      memberUuid: Value(memberUuid),
      groupId: Value(groupId),
      userId: Value(userId),
      displayName: Value(displayName),
      roleOrdinal: Value(roleOrdinal),
      statusOrdinal: Value(statusOrdinal),
      joinedAtMs: Value(joinedAtMs),
    );
  }

  factory GroupMember.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return GroupMember(
      id: serializer.fromJson<int>(json['id']),
      memberUuid: serializer.fromJson<String>(json['memberUuid']),
      groupId: serializer.fromJson<String>(json['groupId']),
      userId: serializer.fromJson<String>(json['userId']),
      displayName: serializer.fromJson<String>(json['displayName']),
      roleOrdinal: serializer.fromJson<String>(json['roleOrdinal']),
      statusOrdinal: serializer.fromJson<String>(json['statusOrdinal']),
      joinedAtMs: serializer.fromJson<int>(json['joinedAtMs']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'memberUuid': serializer.toJson<String>(memberUuid),
      'groupId': serializer.toJson<String>(groupId),
      'userId': serializer.toJson<String>(userId),
      'displayName': serializer.toJson<String>(displayName),
      'roleOrdinal': serializer.toJson<String>(roleOrdinal),
      'statusOrdinal': serializer.toJson<String>(statusOrdinal),
      'joinedAtMs': serializer.toJson<int>(joinedAtMs),
    };
  }

  GroupMember copyWith({
    int? id,
    String? memberUuid,
    String? groupId,
    String? userId,
    String? displayName,
    String? roleOrdinal,
    String? statusOrdinal,
    int? joinedAtMs,
  }) => GroupMember(
    id: id ?? this.id,
    memberUuid: memberUuid ?? this.memberUuid,
    groupId: groupId ?? this.groupId,
    userId: userId ?? this.userId,
    displayName: displayName ?? this.displayName,
    roleOrdinal: roleOrdinal ?? this.roleOrdinal,
    statusOrdinal: statusOrdinal ?? this.statusOrdinal,
    joinedAtMs: joinedAtMs ?? this.joinedAtMs,
  );
  GroupMember copyWithCompanion(GroupMembersCompanion data) {
    return GroupMember(
      id: data.id.present ? data.id.value : this.id,
      memberUuid: data.memberUuid.present
          ? data.memberUuid.value
          : this.memberUuid,
      groupId: data.groupId.present ? data.groupId.value : this.groupId,
      userId: data.userId.present ? data.userId.value : this.userId,
      displayName: data.displayName.present
          ? data.displayName.value
          : this.displayName,
      roleOrdinal: data.roleOrdinal.present
          ? data.roleOrdinal.value
          : this.roleOrdinal,
      statusOrdinal: data.statusOrdinal.present
          ? data.statusOrdinal.value
          : this.statusOrdinal,
      joinedAtMs: data.joinedAtMs.present
          ? data.joinedAtMs.value
          : this.joinedAtMs,
    );
  }

  @override
  String toString() {
    return (StringBuffer('GroupMember(')
          ..write('id: $id, ')
          ..write('memberUuid: $memberUuid, ')
          ..write('groupId: $groupId, ')
          ..write('userId: $userId, ')
          ..write('displayName: $displayName, ')
          ..write('roleOrdinal: $roleOrdinal, ')
          ..write('statusOrdinal: $statusOrdinal, ')
          ..write('joinedAtMs: $joinedAtMs')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    memberUuid,
    groupId,
    userId,
    displayName,
    roleOrdinal,
    statusOrdinal,
    joinedAtMs,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is GroupMember &&
          other.id == this.id &&
          other.memberUuid == this.memberUuid &&
          other.groupId == this.groupId &&
          other.userId == this.userId &&
          other.displayName == this.displayName &&
          other.roleOrdinal == this.roleOrdinal &&
          other.statusOrdinal == this.statusOrdinal &&
          other.joinedAtMs == this.joinedAtMs);
}

class GroupMembersCompanion extends UpdateCompanion<GroupMember> {
  final Value<int> id;
  final Value<String> memberUuid;
  final Value<String> groupId;
  final Value<String> userId;
  final Value<String> displayName;
  final Value<String> roleOrdinal;
  final Value<String> statusOrdinal;
  final Value<int> joinedAtMs;
  const GroupMembersCompanion({
    this.id = const Value.absent(),
    this.memberUuid = const Value.absent(),
    this.groupId = const Value.absent(),
    this.userId = const Value.absent(),
    this.displayName = const Value.absent(),
    this.roleOrdinal = const Value.absent(),
    this.statusOrdinal = const Value.absent(),
    this.joinedAtMs = const Value.absent(),
  });
  GroupMembersCompanion.insert({
    this.id = const Value.absent(),
    required String memberUuid,
    required String groupId,
    required String userId,
    required String displayName,
    required String roleOrdinal,
    required String statusOrdinal,
    required int joinedAtMs,
  }) : memberUuid = Value(memberUuid),
       groupId = Value(groupId),
       userId = Value(userId),
       displayName = Value(displayName),
       roleOrdinal = Value(roleOrdinal),
       statusOrdinal = Value(statusOrdinal),
       joinedAtMs = Value(joinedAtMs);
  static Insertable<GroupMember> custom({
    Expression<int>? id,
    Expression<String>? memberUuid,
    Expression<String>? groupId,
    Expression<String>? userId,
    Expression<String>? displayName,
    Expression<String>? roleOrdinal,
    Expression<String>? statusOrdinal,
    Expression<int>? joinedAtMs,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (memberUuid != null) 'member_uuid': memberUuid,
      if (groupId != null) 'group_id': groupId,
      if (userId != null) 'user_id': userId,
      if (displayName != null) 'display_name': displayName,
      if (roleOrdinal != null) 'role_ordinal': roleOrdinal,
      if (statusOrdinal != null) 'status_ordinal': statusOrdinal,
      if (joinedAtMs != null) 'joined_at_ms': joinedAtMs,
    });
  }

  GroupMembersCompanion copyWith({
    Value<int>? id,
    Value<String>? memberUuid,
    Value<String>? groupId,
    Value<String>? userId,
    Value<String>? displayName,
    Value<String>? roleOrdinal,
    Value<String>? statusOrdinal,
    Value<int>? joinedAtMs,
  }) {
    return GroupMembersCompanion(
      id: id ?? this.id,
      memberUuid: memberUuid ?? this.memberUuid,
      groupId: groupId ?? this.groupId,
      userId: userId ?? this.userId,
      displayName: displayName ?? this.displayName,
      roleOrdinal: roleOrdinal ?? this.roleOrdinal,
      statusOrdinal: statusOrdinal ?? this.statusOrdinal,
      joinedAtMs: joinedAtMs ?? this.joinedAtMs,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (memberUuid.present) {
      map['member_uuid'] = Variable<String>(memberUuid.value);
    }
    if (groupId.present) {
      map['group_id'] = Variable<String>(groupId.value);
    }
    if (userId.present) {
      map['user_id'] = Variable<String>(userId.value);
    }
    if (displayName.present) {
      map['display_name'] = Variable<String>(displayName.value);
    }
    if (roleOrdinal.present) {
      map['role_ordinal'] = Variable<String>(roleOrdinal.value);
    }
    if (statusOrdinal.present) {
      map['status_ordinal'] = Variable<String>(statusOrdinal.value);
    }
    if (joinedAtMs.present) {
      map['joined_at_ms'] = Variable<int>(joinedAtMs.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('GroupMembersCompanion(')
          ..write('id: $id, ')
          ..write('memberUuid: $memberUuid, ')
          ..write('groupId: $groupId, ')
          ..write('userId: $userId, ')
          ..write('displayName: $displayName, ')
          ..write('roleOrdinal: $roleOrdinal, ')
          ..write('statusOrdinal: $statusOrdinal, ')
          ..write('joinedAtMs: $joinedAtMs')
          ..write(')'))
        .toString();
  }
}

class $GroupGoalsTable extends GroupGoals
    with TableInfo<$GroupGoalsTable, GroupGoal> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $GroupGoalsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _goalUuidMeta = const VerificationMeta(
    'goalUuid',
  );
  @override
  late final GeneratedColumn<String> goalUuid = GeneratedColumn<String>(
    'goal_uuid',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways('UNIQUE'),
  );
  static const VerificationMeta _groupIdMeta = const VerificationMeta(
    'groupId',
  );
  @override
  late final GeneratedColumn<String> groupId = GeneratedColumn<String>(
    'group_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
    'title',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _descriptionMeta = const VerificationMeta(
    'description',
  );
  @override
  late final GeneratedColumn<String> description = GeneratedColumn<String>(
    'description',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _targetValueMeta = const VerificationMeta(
    'targetValue',
  );
  @override
  late final GeneratedColumn<double> targetValue = GeneratedColumn<double>(
    'target_value',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _currentValueMeta = const VerificationMeta(
    'currentValue',
  );
  @override
  late final GeneratedColumn<double> currentValue = GeneratedColumn<double>(
    'current_value',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _metricOrdinalMeta = const VerificationMeta(
    'metricOrdinal',
  );
  @override
  late final GeneratedColumn<String> metricOrdinal = GeneratedColumn<String>(
    'metric_ordinal',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _startsAtMsMeta = const VerificationMeta(
    'startsAtMs',
  );
  @override
  late final GeneratedColumn<int> startsAtMs = GeneratedColumn<int>(
    'starts_at_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _endsAtMsMeta = const VerificationMeta(
    'endsAtMs',
  );
  @override
  late final GeneratedColumn<int> endsAtMs = GeneratedColumn<int>(
    'ends_at_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _createdByUserIdMeta = const VerificationMeta(
    'createdByUserId',
  );
  @override
  late final GeneratedColumn<String> createdByUserId = GeneratedColumn<String>(
    'created_by_user_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _statusOrdinalMeta = const VerificationMeta(
    'statusOrdinal',
  );
  @override
  late final GeneratedColumn<String> statusOrdinal = GeneratedColumn<String>(
    'status_ordinal',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    goalUuid,
    groupId,
    title,
    description,
    targetValue,
    currentValue,
    metricOrdinal,
    startsAtMs,
    endsAtMs,
    createdByUserId,
    statusOrdinal,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'group_goals';
  @override
  VerificationContext validateIntegrity(
    Insertable<GroupGoal> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('goal_uuid')) {
      context.handle(
        _goalUuidMeta,
        goalUuid.isAcceptableOrUnknown(data['goal_uuid']!, _goalUuidMeta),
      );
    } else if (isInserting) {
      context.missing(_goalUuidMeta);
    }
    if (data.containsKey('group_id')) {
      context.handle(
        _groupIdMeta,
        groupId.isAcceptableOrUnknown(data['group_id']!, _groupIdMeta),
      );
    } else if (isInserting) {
      context.missing(_groupIdMeta);
    }
    if (data.containsKey('title')) {
      context.handle(
        _titleMeta,
        title.isAcceptableOrUnknown(data['title']!, _titleMeta),
      );
    } else if (isInserting) {
      context.missing(_titleMeta);
    }
    if (data.containsKey('description')) {
      context.handle(
        _descriptionMeta,
        description.isAcceptableOrUnknown(
          data['description']!,
          _descriptionMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_descriptionMeta);
    }
    if (data.containsKey('target_value')) {
      context.handle(
        _targetValueMeta,
        targetValue.isAcceptableOrUnknown(
          data['target_value']!,
          _targetValueMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_targetValueMeta);
    }
    if (data.containsKey('current_value')) {
      context.handle(
        _currentValueMeta,
        currentValue.isAcceptableOrUnknown(
          data['current_value']!,
          _currentValueMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_currentValueMeta);
    }
    if (data.containsKey('metric_ordinal')) {
      context.handle(
        _metricOrdinalMeta,
        metricOrdinal.isAcceptableOrUnknown(
          data['metric_ordinal']!,
          _metricOrdinalMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_metricOrdinalMeta);
    }
    if (data.containsKey('starts_at_ms')) {
      context.handle(
        _startsAtMsMeta,
        startsAtMs.isAcceptableOrUnknown(
          data['starts_at_ms']!,
          _startsAtMsMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_startsAtMsMeta);
    }
    if (data.containsKey('ends_at_ms')) {
      context.handle(
        _endsAtMsMeta,
        endsAtMs.isAcceptableOrUnknown(data['ends_at_ms']!, _endsAtMsMeta),
      );
    } else if (isInserting) {
      context.missing(_endsAtMsMeta);
    }
    if (data.containsKey('created_by_user_id')) {
      context.handle(
        _createdByUserIdMeta,
        createdByUserId.isAcceptableOrUnknown(
          data['created_by_user_id']!,
          _createdByUserIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_createdByUserIdMeta);
    }
    if (data.containsKey('status_ordinal')) {
      context.handle(
        _statusOrdinalMeta,
        statusOrdinal.isAcceptableOrUnknown(
          data['status_ordinal']!,
          _statusOrdinalMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_statusOrdinalMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  GroupGoal map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return GroupGoal(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      goalUuid: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}goal_uuid'],
      )!,
      groupId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}group_id'],
      )!,
      title: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title'],
      )!,
      description: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}description'],
      )!,
      targetValue: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}target_value'],
      )!,
      currentValue: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}current_value'],
      )!,
      metricOrdinal: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}metric_ordinal'],
      )!,
      startsAtMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}starts_at_ms'],
      )!,
      endsAtMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}ends_at_ms'],
      )!,
      createdByUserId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}created_by_user_id'],
      )!,
      statusOrdinal: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}status_ordinal'],
      )!,
    );
  }

  @override
  $GroupGoalsTable createAlias(String alias) {
    return $GroupGoalsTable(attachedDatabase, alias);
  }
}

class GroupGoal extends DataClass implements Insertable<GroupGoal> {
  final int id;
  final String goalUuid;
  final String groupId;
  final String title;
  final String description;
  final double targetValue;
  final double currentValue;
  final String metricOrdinal;
  final int startsAtMs;
  final int endsAtMs;
  final String createdByUserId;
  final String statusOrdinal;
  const GroupGoal({
    required this.id,
    required this.goalUuid,
    required this.groupId,
    required this.title,
    required this.description,
    required this.targetValue,
    required this.currentValue,
    required this.metricOrdinal,
    required this.startsAtMs,
    required this.endsAtMs,
    required this.createdByUserId,
    required this.statusOrdinal,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['goal_uuid'] = Variable<String>(goalUuid);
    map['group_id'] = Variable<String>(groupId);
    map['title'] = Variable<String>(title);
    map['description'] = Variable<String>(description);
    map['target_value'] = Variable<double>(targetValue);
    map['current_value'] = Variable<double>(currentValue);
    map['metric_ordinal'] = Variable<String>(metricOrdinal);
    map['starts_at_ms'] = Variable<int>(startsAtMs);
    map['ends_at_ms'] = Variable<int>(endsAtMs);
    map['created_by_user_id'] = Variable<String>(createdByUserId);
    map['status_ordinal'] = Variable<String>(statusOrdinal);
    return map;
  }

  GroupGoalsCompanion toCompanion(bool nullToAbsent) {
    return GroupGoalsCompanion(
      id: Value(id),
      goalUuid: Value(goalUuid),
      groupId: Value(groupId),
      title: Value(title),
      description: Value(description),
      targetValue: Value(targetValue),
      currentValue: Value(currentValue),
      metricOrdinal: Value(metricOrdinal),
      startsAtMs: Value(startsAtMs),
      endsAtMs: Value(endsAtMs),
      createdByUserId: Value(createdByUserId),
      statusOrdinal: Value(statusOrdinal),
    );
  }

  factory GroupGoal.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return GroupGoal(
      id: serializer.fromJson<int>(json['id']),
      goalUuid: serializer.fromJson<String>(json['goalUuid']),
      groupId: serializer.fromJson<String>(json['groupId']),
      title: serializer.fromJson<String>(json['title']),
      description: serializer.fromJson<String>(json['description']),
      targetValue: serializer.fromJson<double>(json['targetValue']),
      currentValue: serializer.fromJson<double>(json['currentValue']),
      metricOrdinal: serializer.fromJson<String>(json['metricOrdinal']),
      startsAtMs: serializer.fromJson<int>(json['startsAtMs']),
      endsAtMs: serializer.fromJson<int>(json['endsAtMs']),
      createdByUserId: serializer.fromJson<String>(json['createdByUserId']),
      statusOrdinal: serializer.fromJson<String>(json['statusOrdinal']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'goalUuid': serializer.toJson<String>(goalUuid),
      'groupId': serializer.toJson<String>(groupId),
      'title': serializer.toJson<String>(title),
      'description': serializer.toJson<String>(description),
      'targetValue': serializer.toJson<double>(targetValue),
      'currentValue': serializer.toJson<double>(currentValue),
      'metricOrdinal': serializer.toJson<String>(metricOrdinal),
      'startsAtMs': serializer.toJson<int>(startsAtMs),
      'endsAtMs': serializer.toJson<int>(endsAtMs),
      'createdByUserId': serializer.toJson<String>(createdByUserId),
      'statusOrdinal': serializer.toJson<String>(statusOrdinal),
    };
  }

  GroupGoal copyWith({
    int? id,
    String? goalUuid,
    String? groupId,
    String? title,
    String? description,
    double? targetValue,
    double? currentValue,
    String? metricOrdinal,
    int? startsAtMs,
    int? endsAtMs,
    String? createdByUserId,
    String? statusOrdinal,
  }) => GroupGoal(
    id: id ?? this.id,
    goalUuid: goalUuid ?? this.goalUuid,
    groupId: groupId ?? this.groupId,
    title: title ?? this.title,
    description: description ?? this.description,
    targetValue: targetValue ?? this.targetValue,
    currentValue: currentValue ?? this.currentValue,
    metricOrdinal: metricOrdinal ?? this.metricOrdinal,
    startsAtMs: startsAtMs ?? this.startsAtMs,
    endsAtMs: endsAtMs ?? this.endsAtMs,
    createdByUserId: createdByUserId ?? this.createdByUserId,
    statusOrdinal: statusOrdinal ?? this.statusOrdinal,
  );
  GroupGoal copyWithCompanion(GroupGoalsCompanion data) {
    return GroupGoal(
      id: data.id.present ? data.id.value : this.id,
      goalUuid: data.goalUuid.present ? data.goalUuid.value : this.goalUuid,
      groupId: data.groupId.present ? data.groupId.value : this.groupId,
      title: data.title.present ? data.title.value : this.title,
      description: data.description.present
          ? data.description.value
          : this.description,
      targetValue: data.targetValue.present
          ? data.targetValue.value
          : this.targetValue,
      currentValue: data.currentValue.present
          ? data.currentValue.value
          : this.currentValue,
      metricOrdinal: data.metricOrdinal.present
          ? data.metricOrdinal.value
          : this.metricOrdinal,
      startsAtMs: data.startsAtMs.present
          ? data.startsAtMs.value
          : this.startsAtMs,
      endsAtMs: data.endsAtMs.present ? data.endsAtMs.value : this.endsAtMs,
      createdByUserId: data.createdByUserId.present
          ? data.createdByUserId.value
          : this.createdByUserId,
      statusOrdinal: data.statusOrdinal.present
          ? data.statusOrdinal.value
          : this.statusOrdinal,
    );
  }

  @override
  String toString() {
    return (StringBuffer('GroupGoal(')
          ..write('id: $id, ')
          ..write('goalUuid: $goalUuid, ')
          ..write('groupId: $groupId, ')
          ..write('title: $title, ')
          ..write('description: $description, ')
          ..write('targetValue: $targetValue, ')
          ..write('currentValue: $currentValue, ')
          ..write('metricOrdinal: $metricOrdinal, ')
          ..write('startsAtMs: $startsAtMs, ')
          ..write('endsAtMs: $endsAtMs, ')
          ..write('createdByUserId: $createdByUserId, ')
          ..write('statusOrdinal: $statusOrdinal')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    goalUuid,
    groupId,
    title,
    description,
    targetValue,
    currentValue,
    metricOrdinal,
    startsAtMs,
    endsAtMs,
    createdByUserId,
    statusOrdinal,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is GroupGoal &&
          other.id == this.id &&
          other.goalUuid == this.goalUuid &&
          other.groupId == this.groupId &&
          other.title == this.title &&
          other.description == this.description &&
          other.targetValue == this.targetValue &&
          other.currentValue == this.currentValue &&
          other.metricOrdinal == this.metricOrdinal &&
          other.startsAtMs == this.startsAtMs &&
          other.endsAtMs == this.endsAtMs &&
          other.createdByUserId == this.createdByUserId &&
          other.statusOrdinal == this.statusOrdinal);
}

class GroupGoalsCompanion extends UpdateCompanion<GroupGoal> {
  final Value<int> id;
  final Value<String> goalUuid;
  final Value<String> groupId;
  final Value<String> title;
  final Value<String> description;
  final Value<double> targetValue;
  final Value<double> currentValue;
  final Value<String> metricOrdinal;
  final Value<int> startsAtMs;
  final Value<int> endsAtMs;
  final Value<String> createdByUserId;
  final Value<String> statusOrdinal;
  const GroupGoalsCompanion({
    this.id = const Value.absent(),
    this.goalUuid = const Value.absent(),
    this.groupId = const Value.absent(),
    this.title = const Value.absent(),
    this.description = const Value.absent(),
    this.targetValue = const Value.absent(),
    this.currentValue = const Value.absent(),
    this.metricOrdinal = const Value.absent(),
    this.startsAtMs = const Value.absent(),
    this.endsAtMs = const Value.absent(),
    this.createdByUserId = const Value.absent(),
    this.statusOrdinal = const Value.absent(),
  });
  GroupGoalsCompanion.insert({
    this.id = const Value.absent(),
    required String goalUuid,
    required String groupId,
    required String title,
    required String description,
    required double targetValue,
    required double currentValue,
    required String metricOrdinal,
    required int startsAtMs,
    required int endsAtMs,
    required String createdByUserId,
    required String statusOrdinal,
  }) : goalUuid = Value(goalUuid),
       groupId = Value(groupId),
       title = Value(title),
       description = Value(description),
       targetValue = Value(targetValue),
       currentValue = Value(currentValue),
       metricOrdinal = Value(metricOrdinal),
       startsAtMs = Value(startsAtMs),
       endsAtMs = Value(endsAtMs),
       createdByUserId = Value(createdByUserId),
       statusOrdinal = Value(statusOrdinal);
  static Insertable<GroupGoal> custom({
    Expression<int>? id,
    Expression<String>? goalUuid,
    Expression<String>? groupId,
    Expression<String>? title,
    Expression<String>? description,
    Expression<double>? targetValue,
    Expression<double>? currentValue,
    Expression<String>? metricOrdinal,
    Expression<int>? startsAtMs,
    Expression<int>? endsAtMs,
    Expression<String>? createdByUserId,
    Expression<String>? statusOrdinal,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (goalUuid != null) 'goal_uuid': goalUuid,
      if (groupId != null) 'group_id': groupId,
      if (title != null) 'title': title,
      if (description != null) 'description': description,
      if (targetValue != null) 'target_value': targetValue,
      if (currentValue != null) 'current_value': currentValue,
      if (metricOrdinal != null) 'metric_ordinal': metricOrdinal,
      if (startsAtMs != null) 'starts_at_ms': startsAtMs,
      if (endsAtMs != null) 'ends_at_ms': endsAtMs,
      if (createdByUserId != null) 'created_by_user_id': createdByUserId,
      if (statusOrdinal != null) 'status_ordinal': statusOrdinal,
    });
  }

  GroupGoalsCompanion copyWith({
    Value<int>? id,
    Value<String>? goalUuid,
    Value<String>? groupId,
    Value<String>? title,
    Value<String>? description,
    Value<double>? targetValue,
    Value<double>? currentValue,
    Value<String>? metricOrdinal,
    Value<int>? startsAtMs,
    Value<int>? endsAtMs,
    Value<String>? createdByUserId,
    Value<String>? statusOrdinal,
  }) {
    return GroupGoalsCompanion(
      id: id ?? this.id,
      goalUuid: goalUuid ?? this.goalUuid,
      groupId: groupId ?? this.groupId,
      title: title ?? this.title,
      description: description ?? this.description,
      targetValue: targetValue ?? this.targetValue,
      currentValue: currentValue ?? this.currentValue,
      metricOrdinal: metricOrdinal ?? this.metricOrdinal,
      startsAtMs: startsAtMs ?? this.startsAtMs,
      endsAtMs: endsAtMs ?? this.endsAtMs,
      createdByUserId: createdByUserId ?? this.createdByUserId,
      statusOrdinal: statusOrdinal ?? this.statusOrdinal,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (goalUuid.present) {
      map['goal_uuid'] = Variable<String>(goalUuid.value);
    }
    if (groupId.present) {
      map['group_id'] = Variable<String>(groupId.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (description.present) {
      map['description'] = Variable<String>(description.value);
    }
    if (targetValue.present) {
      map['target_value'] = Variable<double>(targetValue.value);
    }
    if (currentValue.present) {
      map['current_value'] = Variable<double>(currentValue.value);
    }
    if (metricOrdinal.present) {
      map['metric_ordinal'] = Variable<String>(metricOrdinal.value);
    }
    if (startsAtMs.present) {
      map['starts_at_ms'] = Variable<int>(startsAtMs.value);
    }
    if (endsAtMs.present) {
      map['ends_at_ms'] = Variable<int>(endsAtMs.value);
    }
    if (createdByUserId.present) {
      map['created_by_user_id'] = Variable<String>(createdByUserId.value);
    }
    if (statusOrdinal.present) {
      map['status_ordinal'] = Variable<String>(statusOrdinal.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('GroupGoalsCompanion(')
          ..write('id: $id, ')
          ..write('goalUuid: $goalUuid, ')
          ..write('groupId: $groupId, ')
          ..write('title: $title, ')
          ..write('description: $description, ')
          ..write('targetValue: $targetValue, ')
          ..write('currentValue: $currentValue, ')
          ..write('metricOrdinal: $metricOrdinal, ')
          ..write('startsAtMs: $startsAtMs, ')
          ..write('endsAtMs: $endsAtMs, ')
          ..write('createdByUserId: $createdByUserId, ')
          ..write('statusOrdinal: $statusOrdinal')
          ..write(')'))
        .toString();
  }
}

class $EventsTable extends Events with TableInfo<$EventsTable, Event> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $EventsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _eventUuidMeta = const VerificationMeta(
    'eventUuid',
  );
  @override
  late final GeneratedColumn<String> eventUuid = GeneratedColumn<String>(
    'event_uuid',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways('UNIQUE'),
  );
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
    'title',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _descriptionMeta = const VerificationMeta(
    'description',
  );
  @override
  late final GeneratedColumn<String> description = GeneratedColumn<String>(
    'description',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _imageUrlMeta = const VerificationMeta(
    'imageUrl',
  );
  @override
  late final GeneratedColumn<String> imageUrl = GeneratedColumn<String>(
    'image_url',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _typeOrdinalMeta = const VerificationMeta(
    'typeOrdinal',
  );
  @override
  late final GeneratedColumn<String> typeOrdinal = GeneratedColumn<String>(
    'type_ordinal',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _metricOrdinalMeta = const VerificationMeta(
    'metricOrdinal',
  );
  @override
  late final GeneratedColumn<String> metricOrdinal = GeneratedColumn<String>(
    'metric_ordinal',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _targetValueMeta = const VerificationMeta(
    'targetValue',
  );
  @override
  late final GeneratedColumn<double> targetValue = GeneratedColumn<double>(
    'target_value',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _startsAtMsMeta = const VerificationMeta(
    'startsAtMs',
  );
  @override
  late final GeneratedColumn<int> startsAtMs = GeneratedColumn<int>(
    'starts_at_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _endsAtMsMeta = const VerificationMeta(
    'endsAtMs',
  );
  @override
  late final GeneratedColumn<int> endsAtMs = GeneratedColumn<int>(
    'ends_at_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _maxParticipantsMeta = const VerificationMeta(
    'maxParticipants',
  );
  @override
  late final GeneratedColumn<int> maxParticipants = GeneratedColumn<int>(
    'max_participants',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdBySystemMeta = const VerificationMeta(
    'createdBySystem',
  );
  @override
  late final GeneratedColumn<bool> createdBySystem = GeneratedColumn<bool>(
    'created_by_system',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("created_by_system" IN (0, 1))',
    ),
  );
  static const VerificationMeta _creatorUserIdMeta = const VerificationMeta(
    'creatorUserId',
  );
  @override
  late final GeneratedColumn<String> creatorUserId = GeneratedColumn<String>(
    'creator_user_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _rewardXpCompletionMeta =
      const VerificationMeta('rewardXpCompletion');
  @override
  late final GeneratedColumn<int> rewardXpCompletion = GeneratedColumn<int>(
    'reward_xp_completion',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _rewardCoinsCompletionMeta =
      const VerificationMeta('rewardCoinsCompletion');
  @override
  late final GeneratedColumn<int> rewardCoinsCompletion = GeneratedColumn<int>(
    'reward_coins_completion',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _rewardXpParticipationMeta =
      const VerificationMeta('rewardXpParticipation');
  @override
  late final GeneratedColumn<int> rewardXpParticipation = GeneratedColumn<int>(
    'reward_xp_participation',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _rewardBadgeIdMeta = const VerificationMeta(
    'rewardBadgeId',
  );
  @override
  late final GeneratedColumn<String> rewardBadgeId = GeneratedColumn<String>(
    'reward_badge_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _statusOrdinalMeta = const VerificationMeta(
    'statusOrdinal',
  );
  @override
  late final GeneratedColumn<String> statusOrdinal = GeneratedColumn<String>(
    'status_ordinal',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    eventUuid,
    title,
    description,
    imageUrl,
    typeOrdinal,
    metricOrdinal,
    targetValue,
    startsAtMs,
    endsAtMs,
    maxParticipants,
    createdBySystem,
    creatorUserId,
    rewardXpCompletion,
    rewardCoinsCompletion,
    rewardXpParticipation,
    rewardBadgeId,
    statusOrdinal,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'events';
  @override
  VerificationContext validateIntegrity(
    Insertable<Event> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('event_uuid')) {
      context.handle(
        _eventUuidMeta,
        eventUuid.isAcceptableOrUnknown(data['event_uuid']!, _eventUuidMeta),
      );
    } else if (isInserting) {
      context.missing(_eventUuidMeta);
    }
    if (data.containsKey('title')) {
      context.handle(
        _titleMeta,
        title.isAcceptableOrUnknown(data['title']!, _titleMeta),
      );
    } else if (isInserting) {
      context.missing(_titleMeta);
    }
    if (data.containsKey('description')) {
      context.handle(
        _descriptionMeta,
        description.isAcceptableOrUnknown(
          data['description']!,
          _descriptionMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_descriptionMeta);
    }
    if (data.containsKey('image_url')) {
      context.handle(
        _imageUrlMeta,
        imageUrl.isAcceptableOrUnknown(data['image_url']!, _imageUrlMeta),
      );
    }
    if (data.containsKey('type_ordinal')) {
      context.handle(
        _typeOrdinalMeta,
        typeOrdinal.isAcceptableOrUnknown(
          data['type_ordinal']!,
          _typeOrdinalMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_typeOrdinalMeta);
    }
    if (data.containsKey('metric_ordinal')) {
      context.handle(
        _metricOrdinalMeta,
        metricOrdinal.isAcceptableOrUnknown(
          data['metric_ordinal']!,
          _metricOrdinalMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_metricOrdinalMeta);
    }
    if (data.containsKey('target_value')) {
      context.handle(
        _targetValueMeta,
        targetValue.isAcceptableOrUnknown(
          data['target_value']!,
          _targetValueMeta,
        ),
      );
    }
    if (data.containsKey('starts_at_ms')) {
      context.handle(
        _startsAtMsMeta,
        startsAtMs.isAcceptableOrUnknown(
          data['starts_at_ms']!,
          _startsAtMsMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_startsAtMsMeta);
    }
    if (data.containsKey('ends_at_ms')) {
      context.handle(
        _endsAtMsMeta,
        endsAtMs.isAcceptableOrUnknown(data['ends_at_ms']!, _endsAtMsMeta),
      );
    } else if (isInserting) {
      context.missing(_endsAtMsMeta);
    }
    if (data.containsKey('max_participants')) {
      context.handle(
        _maxParticipantsMeta,
        maxParticipants.isAcceptableOrUnknown(
          data['max_participants']!,
          _maxParticipantsMeta,
        ),
      );
    }
    if (data.containsKey('created_by_system')) {
      context.handle(
        _createdBySystemMeta,
        createdBySystem.isAcceptableOrUnknown(
          data['created_by_system']!,
          _createdBySystemMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_createdBySystemMeta);
    }
    if (data.containsKey('creator_user_id')) {
      context.handle(
        _creatorUserIdMeta,
        creatorUserId.isAcceptableOrUnknown(
          data['creator_user_id']!,
          _creatorUserIdMeta,
        ),
      );
    }
    if (data.containsKey('reward_xp_completion')) {
      context.handle(
        _rewardXpCompletionMeta,
        rewardXpCompletion.isAcceptableOrUnknown(
          data['reward_xp_completion']!,
          _rewardXpCompletionMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_rewardXpCompletionMeta);
    }
    if (data.containsKey('reward_coins_completion')) {
      context.handle(
        _rewardCoinsCompletionMeta,
        rewardCoinsCompletion.isAcceptableOrUnknown(
          data['reward_coins_completion']!,
          _rewardCoinsCompletionMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_rewardCoinsCompletionMeta);
    }
    if (data.containsKey('reward_xp_participation')) {
      context.handle(
        _rewardXpParticipationMeta,
        rewardXpParticipation.isAcceptableOrUnknown(
          data['reward_xp_participation']!,
          _rewardXpParticipationMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_rewardXpParticipationMeta);
    }
    if (data.containsKey('reward_badge_id')) {
      context.handle(
        _rewardBadgeIdMeta,
        rewardBadgeId.isAcceptableOrUnknown(
          data['reward_badge_id']!,
          _rewardBadgeIdMeta,
        ),
      );
    }
    if (data.containsKey('status_ordinal')) {
      context.handle(
        _statusOrdinalMeta,
        statusOrdinal.isAcceptableOrUnknown(
          data['status_ordinal']!,
          _statusOrdinalMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_statusOrdinalMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Event map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Event(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      eventUuid: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}event_uuid'],
      )!,
      title: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title'],
      )!,
      description: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}description'],
      )!,
      imageUrl: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}image_url'],
      ),
      typeOrdinal: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}type_ordinal'],
      )!,
      metricOrdinal: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}metric_ordinal'],
      )!,
      targetValue: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}target_value'],
      ),
      startsAtMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}starts_at_ms'],
      )!,
      endsAtMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}ends_at_ms'],
      )!,
      maxParticipants: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}max_participants'],
      ),
      createdBySystem: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}created_by_system'],
      )!,
      creatorUserId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}creator_user_id'],
      ),
      rewardXpCompletion: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}reward_xp_completion'],
      )!,
      rewardCoinsCompletion: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}reward_coins_completion'],
      )!,
      rewardXpParticipation: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}reward_xp_participation'],
      )!,
      rewardBadgeId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}reward_badge_id'],
      ),
      statusOrdinal: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}status_ordinal'],
      )!,
    );
  }

  @override
  $EventsTable createAlias(String alias) {
    return $EventsTable(attachedDatabase, alias);
  }
}

class Event extends DataClass implements Insertable<Event> {
  final int id;
  final String eventUuid;
  final String title;
  final String description;
  final String? imageUrl;
  final String typeOrdinal;
  final String metricOrdinal;
  final double? targetValue;
  final int startsAtMs;
  final int endsAtMs;
  final int? maxParticipants;
  final bool createdBySystem;
  final String? creatorUserId;
  final int rewardXpCompletion;
  final int rewardCoinsCompletion;
  final int rewardXpParticipation;
  final String? rewardBadgeId;
  final String statusOrdinal;
  const Event({
    required this.id,
    required this.eventUuid,
    required this.title,
    required this.description,
    this.imageUrl,
    required this.typeOrdinal,
    required this.metricOrdinal,
    this.targetValue,
    required this.startsAtMs,
    required this.endsAtMs,
    this.maxParticipants,
    required this.createdBySystem,
    this.creatorUserId,
    required this.rewardXpCompletion,
    required this.rewardCoinsCompletion,
    required this.rewardXpParticipation,
    this.rewardBadgeId,
    required this.statusOrdinal,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['event_uuid'] = Variable<String>(eventUuid);
    map['title'] = Variable<String>(title);
    map['description'] = Variable<String>(description);
    if (!nullToAbsent || imageUrl != null) {
      map['image_url'] = Variable<String>(imageUrl);
    }
    map['type_ordinal'] = Variable<String>(typeOrdinal);
    map['metric_ordinal'] = Variable<String>(metricOrdinal);
    if (!nullToAbsent || targetValue != null) {
      map['target_value'] = Variable<double>(targetValue);
    }
    map['starts_at_ms'] = Variable<int>(startsAtMs);
    map['ends_at_ms'] = Variable<int>(endsAtMs);
    if (!nullToAbsent || maxParticipants != null) {
      map['max_participants'] = Variable<int>(maxParticipants);
    }
    map['created_by_system'] = Variable<bool>(createdBySystem);
    if (!nullToAbsent || creatorUserId != null) {
      map['creator_user_id'] = Variable<String>(creatorUserId);
    }
    map['reward_xp_completion'] = Variable<int>(rewardXpCompletion);
    map['reward_coins_completion'] = Variable<int>(rewardCoinsCompletion);
    map['reward_xp_participation'] = Variable<int>(rewardXpParticipation);
    if (!nullToAbsent || rewardBadgeId != null) {
      map['reward_badge_id'] = Variable<String>(rewardBadgeId);
    }
    map['status_ordinal'] = Variable<String>(statusOrdinal);
    return map;
  }

  EventsCompanion toCompanion(bool nullToAbsent) {
    return EventsCompanion(
      id: Value(id),
      eventUuid: Value(eventUuid),
      title: Value(title),
      description: Value(description),
      imageUrl: imageUrl == null && nullToAbsent
          ? const Value.absent()
          : Value(imageUrl),
      typeOrdinal: Value(typeOrdinal),
      metricOrdinal: Value(metricOrdinal),
      targetValue: targetValue == null && nullToAbsent
          ? const Value.absent()
          : Value(targetValue),
      startsAtMs: Value(startsAtMs),
      endsAtMs: Value(endsAtMs),
      maxParticipants: maxParticipants == null && nullToAbsent
          ? const Value.absent()
          : Value(maxParticipants),
      createdBySystem: Value(createdBySystem),
      creatorUserId: creatorUserId == null && nullToAbsent
          ? const Value.absent()
          : Value(creatorUserId),
      rewardXpCompletion: Value(rewardXpCompletion),
      rewardCoinsCompletion: Value(rewardCoinsCompletion),
      rewardXpParticipation: Value(rewardXpParticipation),
      rewardBadgeId: rewardBadgeId == null && nullToAbsent
          ? const Value.absent()
          : Value(rewardBadgeId),
      statusOrdinal: Value(statusOrdinal),
    );
  }

  factory Event.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Event(
      id: serializer.fromJson<int>(json['id']),
      eventUuid: serializer.fromJson<String>(json['eventUuid']),
      title: serializer.fromJson<String>(json['title']),
      description: serializer.fromJson<String>(json['description']),
      imageUrl: serializer.fromJson<String?>(json['imageUrl']),
      typeOrdinal: serializer.fromJson<String>(json['typeOrdinal']),
      metricOrdinal: serializer.fromJson<String>(json['metricOrdinal']),
      targetValue: serializer.fromJson<double?>(json['targetValue']),
      startsAtMs: serializer.fromJson<int>(json['startsAtMs']),
      endsAtMs: serializer.fromJson<int>(json['endsAtMs']),
      maxParticipants: serializer.fromJson<int?>(json['maxParticipants']),
      createdBySystem: serializer.fromJson<bool>(json['createdBySystem']),
      creatorUserId: serializer.fromJson<String?>(json['creatorUserId']),
      rewardXpCompletion: serializer.fromJson<int>(json['rewardXpCompletion']),
      rewardCoinsCompletion: serializer.fromJson<int>(
        json['rewardCoinsCompletion'],
      ),
      rewardXpParticipation: serializer.fromJson<int>(
        json['rewardXpParticipation'],
      ),
      rewardBadgeId: serializer.fromJson<String?>(json['rewardBadgeId']),
      statusOrdinal: serializer.fromJson<String>(json['statusOrdinal']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'eventUuid': serializer.toJson<String>(eventUuid),
      'title': serializer.toJson<String>(title),
      'description': serializer.toJson<String>(description),
      'imageUrl': serializer.toJson<String?>(imageUrl),
      'typeOrdinal': serializer.toJson<String>(typeOrdinal),
      'metricOrdinal': serializer.toJson<String>(metricOrdinal),
      'targetValue': serializer.toJson<double?>(targetValue),
      'startsAtMs': serializer.toJson<int>(startsAtMs),
      'endsAtMs': serializer.toJson<int>(endsAtMs),
      'maxParticipants': serializer.toJson<int?>(maxParticipants),
      'createdBySystem': serializer.toJson<bool>(createdBySystem),
      'creatorUserId': serializer.toJson<String?>(creatorUserId),
      'rewardXpCompletion': serializer.toJson<int>(rewardXpCompletion),
      'rewardCoinsCompletion': serializer.toJson<int>(rewardCoinsCompletion),
      'rewardXpParticipation': serializer.toJson<int>(rewardXpParticipation),
      'rewardBadgeId': serializer.toJson<String?>(rewardBadgeId),
      'statusOrdinal': serializer.toJson<String>(statusOrdinal),
    };
  }

  Event copyWith({
    int? id,
    String? eventUuid,
    String? title,
    String? description,
    Value<String?> imageUrl = const Value.absent(),
    String? typeOrdinal,
    String? metricOrdinal,
    Value<double?> targetValue = const Value.absent(),
    int? startsAtMs,
    int? endsAtMs,
    Value<int?> maxParticipants = const Value.absent(),
    bool? createdBySystem,
    Value<String?> creatorUserId = const Value.absent(),
    int? rewardXpCompletion,
    int? rewardCoinsCompletion,
    int? rewardXpParticipation,
    Value<String?> rewardBadgeId = const Value.absent(),
    String? statusOrdinal,
  }) => Event(
    id: id ?? this.id,
    eventUuid: eventUuid ?? this.eventUuid,
    title: title ?? this.title,
    description: description ?? this.description,
    imageUrl: imageUrl.present ? imageUrl.value : this.imageUrl,
    typeOrdinal: typeOrdinal ?? this.typeOrdinal,
    metricOrdinal: metricOrdinal ?? this.metricOrdinal,
    targetValue: targetValue.present ? targetValue.value : this.targetValue,
    startsAtMs: startsAtMs ?? this.startsAtMs,
    endsAtMs: endsAtMs ?? this.endsAtMs,
    maxParticipants: maxParticipants.present
        ? maxParticipants.value
        : this.maxParticipants,
    createdBySystem: createdBySystem ?? this.createdBySystem,
    creatorUserId: creatorUserId.present
        ? creatorUserId.value
        : this.creatorUserId,
    rewardXpCompletion: rewardXpCompletion ?? this.rewardXpCompletion,
    rewardCoinsCompletion: rewardCoinsCompletion ?? this.rewardCoinsCompletion,
    rewardXpParticipation: rewardXpParticipation ?? this.rewardXpParticipation,
    rewardBadgeId: rewardBadgeId.present
        ? rewardBadgeId.value
        : this.rewardBadgeId,
    statusOrdinal: statusOrdinal ?? this.statusOrdinal,
  );
  Event copyWithCompanion(EventsCompanion data) {
    return Event(
      id: data.id.present ? data.id.value : this.id,
      eventUuid: data.eventUuid.present ? data.eventUuid.value : this.eventUuid,
      title: data.title.present ? data.title.value : this.title,
      description: data.description.present
          ? data.description.value
          : this.description,
      imageUrl: data.imageUrl.present ? data.imageUrl.value : this.imageUrl,
      typeOrdinal: data.typeOrdinal.present
          ? data.typeOrdinal.value
          : this.typeOrdinal,
      metricOrdinal: data.metricOrdinal.present
          ? data.metricOrdinal.value
          : this.metricOrdinal,
      targetValue: data.targetValue.present
          ? data.targetValue.value
          : this.targetValue,
      startsAtMs: data.startsAtMs.present
          ? data.startsAtMs.value
          : this.startsAtMs,
      endsAtMs: data.endsAtMs.present ? data.endsAtMs.value : this.endsAtMs,
      maxParticipants: data.maxParticipants.present
          ? data.maxParticipants.value
          : this.maxParticipants,
      createdBySystem: data.createdBySystem.present
          ? data.createdBySystem.value
          : this.createdBySystem,
      creatorUserId: data.creatorUserId.present
          ? data.creatorUserId.value
          : this.creatorUserId,
      rewardXpCompletion: data.rewardXpCompletion.present
          ? data.rewardXpCompletion.value
          : this.rewardXpCompletion,
      rewardCoinsCompletion: data.rewardCoinsCompletion.present
          ? data.rewardCoinsCompletion.value
          : this.rewardCoinsCompletion,
      rewardXpParticipation: data.rewardXpParticipation.present
          ? data.rewardXpParticipation.value
          : this.rewardXpParticipation,
      rewardBadgeId: data.rewardBadgeId.present
          ? data.rewardBadgeId.value
          : this.rewardBadgeId,
      statusOrdinal: data.statusOrdinal.present
          ? data.statusOrdinal.value
          : this.statusOrdinal,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Event(')
          ..write('id: $id, ')
          ..write('eventUuid: $eventUuid, ')
          ..write('title: $title, ')
          ..write('description: $description, ')
          ..write('imageUrl: $imageUrl, ')
          ..write('typeOrdinal: $typeOrdinal, ')
          ..write('metricOrdinal: $metricOrdinal, ')
          ..write('targetValue: $targetValue, ')
          ..write('startsAtMs: $startsAtMs, ')
          ..write('endsAtMs: $endsAtMs, ')
          ..write('maxParticipants: $maxParticipants, ')
          ..write('createdBySystem: $createdBySystem, ')
          ..write('creatorUserId: $creatorUserId, ')
          ..write('rewardXpCompletion: $rewardXpCompletion, ')
          ..write('rewardCoinsCompletion: $rewardCoinsCompletion, ')
          ..write('rewardXpParticipation: $rewardXpParticipation, ')
          ..write('rewardBadgeId: $rewardBadgeId, ')
          ..write('statusOrdinal: $statusOrdinal')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    eventUuid,
    title,
    description,
    imageUrl,
    typeOrdinal,
    metricOrdinal,
    targetValue,
    startsAtMs,
    endsAtMs,
    maxParticipants,
    createdBySystem,
    creatorUserId,
    rewardXpCompletion,
    rewardCoinsCompletion,
    rewardXpParticipation,
    rewardBadgeId,
    statusOrdinal,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Event &&
          other.id == this.id &&
          other.eventUuid == this.eventUuid &&
          other.title == this.title &&
          other.description == this.description &&
          other.imageUrl == this.imageUrl &&
          other.typeOrdinal == this.typeOrdinal &&
          other.metricOrdinal == this.metricOrdinal &&
          other.targetValue == this.targetValue &&
          other.startsAtMs == this.startsAtMs &&
          other.endsAtMs == this.endsAtMs &&
          other.maxParticipants == this.maxParticipants &&
          other.createdBySystem == this.createdBySystem &&
          other.creatorUserId == this.creatorUserId &&
          other.rewardXpCompletion == this.rewardXpCompletion &&
          other.rewardCoinsCompletion == this.rewardCoinsCompletion &&
          other.rewardXpParticipation == this.rewardXpParticipation &&
          other.rewardBadgeId == this.rewardBadgeId &&
          other.statusOrdinal == this.statusOrdinal);
}

class EventsCompanion extends UpdateCompanion<Event> {
  final Value<int> id;
  final Value<String> eventUuid;
  final Value<String> title;
  final Value<String> description;
  final Value<String?> imageUrl;
  final Value<String> typeOrdinal;
  final Value<String> metricOrdinal;
  final Value<double?> targetValue;
  final Value<int> startsAtMs;
  final Value<int> endsAtMs;
  final Value<int?> maxParticipants;
  final Value<bool> createdBySystem;
  final Value<String?> creatorUserId;
  final Value<int> rewardXpCompletion;
  final Value<int> rewardCoinsCompletion;
  final Value<int> rewardXpParticipation;
  final Value<String?> rewardBadgeId;
  final Value<String> statusOrdinal;
  const EventsCompanion({
    this.id = const Value.absent(),
    this.eventUuid = const Value.absent(),
    this.title = const Value.absent(),
    this.description = const Value.absent(),
    this.imageUrl = const Value.absent(),
    this.typeOrdinal = const Value.absent(),
    this.metricOrdinal = const Value.absent(),
    this.targetValue = const Value.absent(),
    this.startsAtMs = const Value.absent(),
    this.endsAtMs = const Value.absent(),
    this.maxParticipants = const Value.absent(),
    this.createdBySystem = const Value.absent(),
    this.creatorUserId = const Value.absent(),
    this.rewardXpCompletion = const Value.absent(),
    this.rewardCoinsCompletion = const Value.absent(),
    this.rewardXpParticipation = const Value.absent(),
    this.rewardBadgeId = const Value.absent(),
    this.statusOrdinal = const Value.absent(),
  });
  EventsCompanion.insert({
    this.id = const Value.absent(),
    required String eventUuid,
    required String title,
    required String description,
    this.imageUrl = const Value.absent(),
    required String typeOrdinal,
    required String metricOrdinal,
    this.targetValue = const Value.absent(),
    required int startsAtMs,
    required int endsAtMs,
    this.maxParticipants = const Value.absent(),
    required bool createdBySystem,
    this.creatorUserId = const Value.absent(),
    required int rewardXpCompletion,
    required int rewardCoinsCompletion,
    required int rewardXpParticipation,
    this.rewardBadgeId = const Value.absent(),
    required String statusOrdinal,
  }) : eventUuid = Value(eventUuid),
       title = Value(title),
       description = Value(description),
       typeOrdinal = Value(typeOrdinal),
       metricOrdinal = Value(metricOrdinal),
       startsAtMs = Value(startsAtMs),
       endsAtMs = Value(endsAtMs),
       createdBySystem = Value(createdBySystem),
       rewardXpCompletion = Value(rewardXpCompletion),
       rewardCoinsCompletion = Value(rewardCoinsCompletion),
       rewardXpParticipation = Value(rewardXpParticipation),
       statusOrdinal = Value(statusOrdinal);
  static Insertable<Event> custom({
    Expression<int>? id,
    Expression<String>? eventUuid,
    Expression<String>? title,
    Expression<String>? description,
    Expression<String>? imageUrl,
    Expression<String>? typeOrdinal,
    Expression<String>? metricOrdinal,
    Expression<double>? targetValue,
    Expression<int>? startsAtMs,
    Expression<int>? endsAtMs,
    Expression<int>? maxParticipants,
    Expression<bool>? createdBySystem,
    Expression<String>? creatorUserId,
    Expression<int>? rewardXpCompletion,
    Expression<int>? rewardCoinsCompletion,
    Expression<int>? rewardXpParticipation,
    Expression<String>? rewardBadgeId,
    Expression<String>? statusOrdinal,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (eventUuid != null) 'event_uuid': eventUuid,
      if (title != null) 'title': title,
      if (description != null) 'description': description,
      if (imageUrl != null) 'image_url': imageUrl,
      if (typeOrdinal != null) 'type_ordinal': typeOrdinal,
      if (metricOrdinal != null) 'metric_ordinal': metricOrdinal,
      if (targetValue != null) 'target_value': targetValue,
      if (startsAtMs != null) 'starts_at_ms': startsAtMs,
      if (endsAtMs != null) 'ends_at_ms': endsAtMs,
      if (maxParticipants != null) 'max_participants': maxParticipants,
      if (createdBySystem != null) 'created_by_system': createdBySystem,
      if (creatorUserId != null) 'creator_user_id': creatorUserId,
      if (rewardXpCompletion != null)
        'reward_xp_completion': rewardXpCompletion,
      if (rewardCoinsCompletion != null)
        'reward_coins_completion': rewardCoinsCompletion,
      if (rewardXpParticipation != null)
        'reward_xp_participation': rewardXpParticipation,
      if (rewardBadgeId != null) 'reward_badge_id': rewardBadgeId,
      if (statusOrdinal != null) 'status_ordinal': statusOrdinal,
    });
  }

  EventsCompanion copyWith({
    Value<int>? id,
    Value<String>? eventUuid,
    Value<String>? title,
    Value<String>? description,
    Value<String?>? imageUrl,
    Value<String>? typeOrdinal,
    Value<String>? metricOrdinal,
    Value<double?>? targetValue,
    Value<int>? startsAtMs,
    Value<int>? endsAtMs,
    Value<int?>? maxParticipants,
    Value<bool>? createdBySystem,
    Value<String?>? creatorUserId,
    Value<int>? rewardXpCompletion,
    Value<int>? rewardCoinsCompletion,
    Value<int>? rewardXpParticipation,
    Value<String?>? rewardBadgeId,
    Value<String>? statusOrdinal,
  }) {
    return EventsCompanion(
      id: id ?? this.id,
      eventUuid: eventUuid ?? this.eventUuid,
      title: title ?? this.title,
      description: description ?? this.description,
      imageUrl: imageUrl ?? this.imageUrl,
      typeOrdinal: typeOrdinal ?? this.typeOrdinal,
      metricOrdinal: metricOrdinal ?? this.metricOrdinal,
      targetValue: targetValue ?? this.targetValue,
      startsAtMs: startsAtMs ?? this.startsAtMs,
      endsAtMs: endsAtMs ?? this.endsAtMs,
      maxParticipants: maxParticipants ?? this.maxParticipants,
      createdBySystem: createdBySystem ?? this.createdBySystem,
      creatorUserId: creatorUserId ?? this.creatorUserId,
      rewardXpCompletion: rewardXpCompletion ?? this.rewardXpCompletion,
      rewardCoinsCompletion:
          rewardCoinsCompletion ?? this.rewardCoinsCompletion,
      rewardXpParticipation:
          rewardXpParticipation ?? this.rewardXpParticipation,
      rewardBadgeId: rewardBadgeId ?? this.rewardBadgeId,
      statusOrdinal: statusOrdinal ?? this.statusOrdinal,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (eventUuid.present) {
      map['event_uuid'] = Variable<String>(eventUuid.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (description.present) {
      map['description'] = Variable<String>(description.value);
    }
    if (imageUrl.present) {
      map['image_url'] = Variable<String>(imageUrl.value);
    }
    if (typeOrdinal.present) {
      map['type_ordinal'] = Variable<String>(typeOrdinal.value);
    }
    if (metricOrdinal.present) {
      map['metric_ordinal'] = Variable<String>(metricOrdinal.value);
    }
    if (targetValue.present) {
      map['target_value'] = Variable<double>(targetValue.value);
    }
    if (startsAtMs.present) {
      map['starts_at_ms'] = Variable<int>(startsAtMs.value);
    }
    if (endsAtMs.present) {
      map['ends_at_ms'] = Variable<int>(endsAtMs.value);
    }
    if (maxParticipants.present) {
      map['max_participants'] = Variable<int>(maxParticipants.value);
    }
    if (createdBySystem.present) {
      map['created_by_system'] = Variable<bool>(createdBySystem.value);
    }
    if (creatorUserId.present) {
      map['creator_user_id'] = Variable<String>(creatorUserId.value);
    }
    if (rewardXpCompletion.present) {
      map['reward_xp_completion'] = Variable<int>(rewardXpCompletion.value);
    }
    if (rewardCoinsCompletion.present) {
      map['reward_coins_completion'] = Variable<int>(
        rewardCoinsCompletion.value,
      );
    }
    if (rewardXpParticipation.present) {
      map['reward_xp_participation'] = Variable<int>(
        rewardXpParticipation.value,
      );
    }
    if (rewardBadgeId.present) {
      map['reward_badge_id'] = Variable<String>(rewardBadgeId.value);
    }
    if (statusOrdinal.present) {
      map['status_ordinal'] = Variable<String>(statusOrdinal.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('EventsCompanion(')
          ..write('id: $id, ')
          ..write('eventUuid: $eventUuid, ')
          ..write('title: $title, ')
          ..write('description: $description, ')
          ..write('imageUrl: $imageUrl, ')
          ..write('typeOrdinal: $typeOrdinal, ')
          ..write('metricOrdinal: $metricOrdinal, ')
          ..write('targetValue: $targetValue, ')
          ..write('startsAtMs: $startsAtMs, ')
          ..write('endsAtMs: $endsAtMs, ')
          ..write('maxParticipants: $maxParticipants, ')
          ..write('createdBySystem: $createdBySystem, ')
          ..write('creatorUserId: $creatorUserId, ')
          ..write('rewardXpCompletion: $rewardXpCompletion, ')
          ..write('rewardCoinsCompletion: $rewardCoinsCompletion, ')
          ..write('rewardXpParticipation: $rewardXpParticipation, ')
          ..write('rewardBadgeId: $rewardBadgeId, ')
          ..write('statusOrdinal: $statusOrdinal')
          ..write(')'))
        .toString();
  }
}

class $EventParticipationsTable extends EventParticipations
    with TableInfo<$EventParticipationsTable, EventParticipation> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $EventParticipationsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _participationUuidMeta = const VerificationMeta(
    'participationUuid',
  );
  @override
  late final GeneratedColumn<String> participationUuid =
      GeneratedColumn<String>(
        'participation_uuid',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
        defaultConstraints: GeneratedColumn.constraintIsAlways('UNIQUE'),
      );
  static const VerificationMeta _eventIdMeta = const VerificationMeta(
    'eventId',
  );
  @override
  late final GeneratedColumn<String> eventId = GeneratedColumn<String>(
    'event_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _userIdMeta = const VerificationMeta('userId');
  @override
  late final GeneratedColumn<String> userId = GeneratedColumn<String>(
    'user_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _displayNameMeta = const VerificationMeta(
    'displayName',
  );
  @override
  late final GeneratedColumn<String> displayName = GeneratedColumn<String>(
    'display_name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _joinedAtMsMeta = const VerificationMeta(
    'joinedAtMs',
  );
  @override
  late final GeneratedColumn<int> joinedAtMs = GeneratedColumn<int>(
    'joined_at_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _currentValueMeta = const VerificationMeta(
    'currentValue',
  );
  @override
  late final GeneratedColumn<double> currentValue = GeneratedColumn<double>(
    'current_value',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _rankMeta = const VerificationMeta('rank');
  @override
  late final GeneratedColumn<int> rank = GeneratedColumn<int>(
    'rank',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _completedMeta = const VerificationMeta(
    'completed',
  );
  @override
  late final GeneratedColumn<bool> completed = GeneratedColumn<bool>(
    'completed',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("completed" IN (0, 1))',
    ),
  );
  static const VerificationMeta _completedAtMsMeta = const VerificationMeta(
    'completedAtMs',
  );
  @override
  late final GeneratedColumn<int> completedAtMs = GeneratedColumn<int>(
    'completed_at_ms',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _contributingSessionCountMeta =
      const VerificationMeta('contributingSessionCount');
  @override
  late final GeneratedColumn<int> contributingSessionCount =
      GeneratedColumn<int>(
        'contributing_session_count',
        aliasedName,
        false,
        type: DriftSqlType.int,
        requiredDuringInsert: true,
      );
  static const VerificationMeta _contributingSessionIdsCsvMeta =
      const VerificationMeta('contributingSessionIdsCsv');
  @override
  late final GeneratedColumn<String> contributingSessionIdsCsv =
      GeneratedColumn<String>(
        'contributing_session_ids_csv',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      );
  static const VerificationMeta _rewardsClaimedMeta = const VerificationMeta(
    'rewardsClaimed',
  );
  @override
  late final GeneratedColumn<bool> rewardsClaimed = GeneratedColumn<bool>(
    'rewards_claimed',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("rewards_claimed" IN (0, 1))',
    ),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    participationUuid,
    eventId,
    userId,
    displayName,
    joinedAtMs,
    currentValue,
    rank,
    completed,
    completedAtMs,
    contributingSessionCount,
    contributingSessionIdsCsv,
    rewardsClaimed,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'event_participations';
  @override
  VerificationContext validateIntegrity(
    Insertable<EventParticipation> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('participation_uuid')) {
      context.handle(
        _participationUuidMeta,
        participationUuid.isAcceptableOrUnknown(
          data['participation_uuid']!,
          _participationUuidMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_participationUuidMeta);
    }
    if (data.containsKey('event_id')) {
      context.handle(
        _eventIdMeta,
        eventId.isAcceptableOrUnknown(data['event_id']!, _eventIdMeta),
      );
    } else if (isInserting) {
      context.missing(_eventIdMeta);
    }
    if (data.containsKey('user_id')) {
      context.handle(
        _userIdMeta,
        userId.isAcceptableOrUnknown(data['user_id']!, _userIdMeta),
      );
    } else if (isInserting) {
      context.missing(_userIdMeta);
    }
    if (data.containsKey('display_name')) {
      context.handle(
        _displayNameMeta,
        displayName.isAcceptableOrUnknown(
          data['display_name']!,
          _displayNameMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_displayNameMeta);
    }
    if (data.containsKey('joined_at_ms')) {
      context.handle(
        _joinedAtMsMeta,
        joinedAtMs.isAcceptableOrUnknown(
          data['joined_at_ms']!,
          _joinedAtMsMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_joinedAtMsMeta);
    }
    if (data.containsKey('current_value')) {
      context.handle(
        _currentValueMeta,
        currentValue.isAcceptableOrUnknown(
          data['current_value']!,
          _currentValueMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_currentValueMeta);
    }
    if (data.containsKey('rank')) {
      context.handle(
        _rankMeta,
        rank.isAcceptableOrUnknown(data['rank']!, _rankMeta),
      );
    }
    if (data.containsKey('completed')) {
      context.handle(
        _completedMeta,
        completed.isAcceptableOrUnknown(data['completed']!, _completedMeta),
      );
    } else if (isInserting) {
      context.missing(_completedMeta);
    }
    if (data.containsKey('completed_at_ms')) {
      context.handle(
        _completedAtMsMeta,
        completedAtMs.isAcceptableOrUnknown(
          data['completed_at_ms']!,
          _completedAtMsMeta,
        ),
      );
    }
    if (data.containsKey('contributing_session_count')) {
      context.handle(
        _contributingSessionCountMeta,
        contributingSessionCount.isAcceptableOrUnknown(
          data['contributing_session_count']!,
          _contributingSessionCountMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_contributingSessionCountMeta);
    }
    if (data.containsKey('contributing_session_ids_csv')) {
      context.handle(
        _contributingSessionIdsCsvMeta,
        contributingSessionIdsCsv.isAcceptableOrUnknown(
          data['contributing_session_ids_csv']!,
          _contributingSessionIdsCsvMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_contributingSessionIdsCsvMeta);
    }
    if (data.containsKey('rewards_claimed')) {
      context.handle(
        _rewardsClaimedMeta,
        rewardsClaimed.isAcceptableOrUnknown(
          data['rewards_claimed']!,
          _rewardsClaimedMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_rewardsClaimedMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  List<Set<GeneratedColumn>> get uniqueKeys => [
    {eventId, userId},
  ];
  @override
  EventParticipation map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return EventParticipation(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      participationUuid: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}participation_uuid'],
      )!,
      eventId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}event_id'],
      )!,
      userId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}user_id'],
      )!,
      displayName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}display_name'],
      )!,
      joinedAtMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}joined_at_ms'],
      )!,
      currentValue: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}current_value'],
      )!,
      rank: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}rank'],
      ),
      completed: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}completed'],
      )!,
      completedAtMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}completed_at_ms'],
      ),
      contributingSessionCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}contributing_session_count'],
      )!,
      contributingSessionIdsCsv: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}contributing_session_ids_csv'],
      )!,
      rewardsClaimed: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}rewards_claimed'],
      )!,
    );
  }

  @override
  $EventParticipationsTable createAlias(String alias) {
    return $EventParticipationsTable(attachedDatabase, alias);
  }
}

class EventParticipation extends DataClass
    implements Insertable<EventParticipation> {
  final int id;
  final String participationUuid;
  final String eventId;
  final String userId;
  final String displayName;
  final int joinedAtMs;
  final double currentValue;
  final int? rank;
  final bool completed;
  final int? completedAtMs;
  final int contributingSessionCount;
  final String contributingSessionIdsCsv;
  final bool rewardsClaimed;
  const EventParticipation({
    required this.id,
    required this.participationUuid,
    required this.eventId,
    required this.userId,
    required this.displayName,
    required this.joinedAtMs,
    required this.currentValue,
    this.rank,
    required this.completed,
    this.completedAtMs,
    required this.contributingSessionCount,
    required this.contributingSessionIdsCsv,
    required this.rewardsClaimed,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['participation_uuid'] = Variable<String>(participationUuid);
    map['event_id'] = Variable<String>(eventId);
    map['user_id'] = Variable<String>(userId);
    map['display_name'] = Variable<String>(displayName);
    map['joined_at_ms'] = Variable<int>(joinedAtMs);
    map['current_value'] = Variable<double>(currentValue);
    if (!nullToAbsent || rank != null) {
      map['rank'] = Variable<int>(rank);
    }
    map['completed'] = Variable<bool>(completed);
    if (!nullToAbsent || completedAtMs != null) {
      map['completed_at_ms'] = Variable<int>(completedAtMs);
    }
    map['contributing_session_count'] = Variable<int>(contributingSessionCount);
    map['contributing_session_ids_csv'] = Variable<String>(
      contributingSessionIdsCsv,
    );
    map['rewards_claimed'] = Variable<bool>(rewardsClaimed);
    return map;
  }

  EventParticipationsCompanion toCompanion(bool nullToAbsent) {
    return EventParticipationsCompanion(
      id: Value(id),
      participationUuid: Value(participationUuid),
      eventId: Value(eventId),
      userId: Value(userId),
      displayName: Value(displayName),
      joinedAtMs: Value(joinedAtMs),
      currentValue: Value(currentValue),
      rank: rank == null && nullToAbsent ? const Value.absent() : Value(rank),
      completed: Value(completed),
      completedAtMs: completedAtMs == null && nullToAbsent
          ? const Value.absent()
          : Value(completedAtMs),
      contributingSessionCount: Value(contributingSessionCount),
      contributingSessionIdsCsv: Value(contributingSessionIdsCsv),
      rewardsClaimed: Value(rewardsClaimed),
    );
  }

  factory EventParticipation.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return EventParticipation(
      id: serializer.fromJson<int>(json['id']),
      participationUuid: serializer.fromJson<String>(json['participationUuid']),
      eventId: serializer.fromJson<String>(json['eventId']),
      userId: serializer.fromJson<String>(json['userId']),
      displayName: serializer.fromJson<String>(json['displayName']),
      joinedAtMs: serializer.fromJson<int>(json['joinedAtMs']),
      currentValue: serializer.fromJson<double>(json['currentValue']),
      rank: serializer.fromJson<int?>(json['rank']),
      completed: serializer.fromJson<bool>(json['completed']),
      completedAtMs: serializer.fromJson<int?>(json['completedAtMs']),
      contributingSessionCount: serializer.fromJson<int>(
        json['contributingSessionCount'],
      ),
      contributingSessionIdsCsv: serializer.fromJson<String>(
        json['contributingSessionIdsCsv'],
      ),
      rewardsClaimed: serializer.fromJson<bool>(json['rewardsClaimed']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'participationUuid': serializer.toJson<String>(participationUuid),
      'eventId': serializer.toJson<String>(eventId),
      'userId': serializer.toJson<String>(userId),
      'displayName': serializer.toJson<String>(displayName),
      'joinedAtMs': serializer.toJson<int>(joinedAtMs),
      'currentValue': serializer.toJson<double>(currentValue),
      'rank': serializer.toJson<int?>(rank),
      'completed': serializer.toJson<bool>(completed),
      'completedAtMs': serializer.toJson<int?>(completedAtMs),
      'contributingSessionCount': serializer.toJson<int>(
        contributingSessionCount,
      ),
      'contributingSessionIdsCsv': serializer.toJson<String>(
        contributingSessionIdsCsv,
      ),
      'rewardsClaimed': serializer.toJson<bool>(rewardsClaimed),
    };
  }

  EventParticipation copyWith({
    int? id,
    String? participationUuid,
    String? eventId,
    String? userId,
    String? displayName,
    int? joinedAtMs,
    double? currentValue,
    Value<int?> rank = const Value.absent(),
    bool? completed,
    Value<int?> completedAtMs = const Value.absent(),
    int? contributingSessionCount,
    String? contributingSessionIdsCsv,
    bool? rewardsClaimed,
  }) => EventParticipation(
    id: id ?? this.id,
    participationUuid: participationUuid ?? this.participationUuid,
    eventId: eventId ?? this.eventId,
    userId: userId ?? this.userId,
    displayName: displayName ?? this.displayName,
    joinedAtMs: joinedAtMs ?? this.joinedAtMs,
    currentValue: currentValue ?? this.currentValue,
    rank: rank.present ? rank.value : this.rank,
    completed: completed ?? this.completed,
    completedAtMs: completedAtMs.present
        ? completedAtMs.value
        : this.completedAtMs,
    contributingSessionCount:
        contributingSessionCount ?? this.contributingSessionCount,
    contributingSessionIdsCsv:
        contributingSessionIdsCsv ?? this.contributingSessionIdsCsv,
    rewardsClaimed: rewardsClaimed ?? this.rewardsClaimed,
  );
  EventParticipation copyWithCompanion(EventParticipationsCompanion data) {
    return EventParticipation(
      id: data.id.present ? data.id.value : this.id,
      participationUuid: data.participationUuid.present
          ? data.participationUuid.value
          : this.participationUuid,
      eventId: data.eventId.present ? data.eventId.value : this.eventId,
      userId: data.userId.present ? data.userId.value : this.userId,
      displayName: data.displayName.present
          ? data.displayName.value
          : this.displayName,
      joinedAtMs: data.joinedAtMs.present
          ? data.joinedAtMs.value
          : this.joinedAtMs,
      currentValue: data.currentValue.present
          ? data.currentValue.value
          : this.currentValue,
      rank: data.rank.present ? data.rank.value : this.rank,
      completed: data.completed.present ? data.completed.value : this.completed,
      completedAtMs: data.completedAtMs.present
          ? data.completedAtMs.value
          : this.completedAtMs,
      contributingSessionCount: data.contributingSessionCount.present
          ? data.contributingSessionCount.value
          : this.contributingSessionCount,
      contributingSessionIdsCsv: data.contributingSessionIdsCsv.present
          ? data.contributingSessionIdsCsv.value
          : this.contributingSessionIdsCsv,
      rewardsClaimed: data.rewardsClaimed.present
          ? data.rewardsClaimed.value
          : this.rewardsClaimed,
    );
  }

  @override
  String toString() {
    return (StringBuffer('EventParticipation(')
          ..write('id: $id, ')
          ..write('participationUuid: $participationUuid, ')
          ..write('eventId: $eventId, ')
          ..write('userId: $userId, ')
          ..write('displayName: $displayName, ')
          ..write('joinedAtMs: $joinedAtMs, ')
          ..write('currentValue: $currentValue, ')
          ..write('rank: $rank, ')
          ..write('completed: $completed, ')
          ..write('completedAtMs: $completedAtMs, ')
          ..write('contributingSessionCount: $contributingSessionCount, ')
          ..write('contributingSessionIdsCsv: $contributingSessionIdsCsv, ')
          ..write('rewardsClaimed: $rewardsClaimed')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    participationUuid,
    eventId,
    userId,
    displayName,
    joinedAtMs,
    currentValue,
    rank,
    completed,
    completedAtMs,
    contributingSessionCount,
    contributingSessionIdsCsv,
    rewardsClaimed,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is EventParticipation &&
          other.id == this.id &&
          other.participationUuid == this.participationUuid &&
          other.eventId == this.eventId &&
          other.userId == this.userId &&
          other.displayName == this.displayName &&
          other.joinedAtMs == this.joinedAtMs &&
          other.currentValue == this.currentValue &&
          other.rank == this.rank &&
          other.completed == this.completed &&
          other.completedAtMs == this.completedAtMs &&
          other.contributingSessionCount == this.contributingSessionCount &&
          other.contributingSessionIdsCsv == this.contributingSessionIdsCsv &&
          other.rewardsClaimed == this.rewardsClaimed);
}

class EventParticipationsCompanion extends UpdateCompanion<EventParticipation> {
  final Value<int> id;
  final Value<String> participationUuid;
  final Value<String> eventId;
  final Value<String> userId;
  final Value<String> displayName;
  final Value<int> joinedAtMs;
  final Value<double> currentValue;
  final Value<int?> rank;
  final Value<bool> completed;
  final Value<int?> completedAtMs;
  final Value<int> contributingSessionCount;
  final Value<String> contributingSessionIdsCsv;
  final Value<bool> rewardsClaimed;
  const EventParticipationsCompanion({
    this.id = const Value.absent(),
    this.participationUuid = const Value.absent(),
    this.eventId = const Value.absent(),
    this.userId = const Value.absent(),
    this.displayName = const Value.absent(),
    this.joinedAtMs = const Value.absent(),
    this.currentValue = const Value.absent(),
    this.rank = const Value.absent(),
    this.completed = const Value.absent(),
    this.completedAtMs = const Value.absent(),
    this.contributingSessionCount = const Value.absent(),
    this.contributingSessionIdsCsv = const Value.absent(),
    this.rewardsClaimed = const Value.absent(),
  });
  EventParticipationsCompanion.insert({
    this.id = const Value.absent(),
    required String participationUuid,
    required String eventId,
    required String userId,
    required String displayName,
    required int joinedAtMs,
    required double currentValue,
    this.rank = const Value.absent(),
    required bool completed,
    this.completedAtMs = const Value.absent(),
    required int contributingSessionCount,
    required String contributingSessionIdsCsv,
    required bool rewardsClaimed,
  }) : participationUuid = Value(participationUuid),
       eventId = Value(eventId),
       userId = Value(userId),
       displayName = Value(displayName),
       joinedAtMs = Value(joinedAtMs),
       currentValue = Value(currentValue),
       completed = Value(completed),
       contributingSessionCount = Value(contributingSessionCount),
       contributingSessionIdsCsv = Value(contributingSessionIdsCsv),
       rewardsClaimed = Value(rewardsClaimed);
  static Insertable<EventParticipation> custom({
    Expression<int>? id,
    Expression<String>? participationUuid,
    Expression<String>? eventId,
    Expression<String>? userId,
    Expression<String>? displayName,
    Expression<int>? joinedAtMs,
    Expression<double>? currentValue,
    Expression<int>? rank,
    Expression<bool>? completed,
    Expression<int>? completedAtMs,
    Expression<int>? contributingSessionCount,
    Expression<String>? contributingSessionIdsCsv,
    Expression<bool>? rewardsClaimed,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (participationUuid != null) 'participation_uuid': participationUuid,
      if (eventId != null) 'event_id': eventId,
      if (userId != null) 'user_id': userId,
      if (displayName != null) 'display_name': displayName,
      if (joinedAtMs != null) 'joined_at_ms': joinedAtMs,
      if (currentValue != null) 'current_value': currentValue,
      if (rank != null) 'rank': rank,
      if (completed != null) 'completed': completed,
      if (completedAtMs != null) 'completed_at_ms': completedAtMs,
      if (contributingSessionCount != null)
        'contributing_session_count': contributingSessionCount,
      if (contributingSessionIdsCsv != null)
        'contributing_session_ids_csv': contributingSessionIdsCsv,
      if (rewardsClaimed != null) 'rewards_claimed': rewardsClaimed,
    });
  }

  EventParticipationsCompanion copyWith({
    Value<int>? id,
    Value<String>? participationUuid,
    Value<String>? eventId,
    Value<String>? userId,
    Value<String>? displayName,
    Value<int>? joinedAtMs,
    Value<double>? currentValue,
    Value<int?>? rank,
    Value<bool>? completed,
    Value<int?>? completedAtMs,
    Value<int>? contributingSessionCount,
    Value<String>? contributingSessionIdsCsv,
    Value<bool>? rewardsClaimed,
  }) {
    return EventParticipationsCompanion(
      id: id ?? this.id,
      participationUuid: participationUuid ?? this.participationUuid,
      eventId: eventId ?? this.eventId,
      userId: userId ?? this.userId,
      displayName: displayName ?? this.displayName,
      joinedAtMs: joinedAtMs ?? this.joinedAtMs,
      currentValue: currentValue ?? this.currentValue,
      rank: rank ?? this.rank,
      completed: completed ?? this.completed,
      completedAtMs: completedAtMs ?? this.completedAtMs,
      contributingSessionCount:
          contributingSessionCount ?? this.contributingSessionCount,
      contributingSessionIdsCsv:
          contributingSessionIdsCsv ?? this.contributingSessionIdsCsv,
      rewardsClaimed: rewardsClaimed ?? this.rewardsClaimed,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (participationUuid.present) {
      map['participation_uuid'] = Variable<String>(participationUuid.value);
    }
    if (eventId.present) {
      map['event_id'] = Variable<String>(eventId.value);
    }
    if (userId.present) {
      map['user_id'] = Variable<String>(userId.value);
    }
    if (displayName.present) {
      map['display_name'] = Variable<String>(displayName.value);
    }
    if (joinedAtMs.present) {
      map['joined_at_ms'] = Variable<int>(joinedAtMs.value);
    }
    if (currentValue.present) {
      map['current_value'] = Variable<double>(currentValue.value);
    }
    if (rank.present) {
      map['rank'] = Variable<int>(rank.value);
    }
    if (completed.present) {
      map['completed'] = Variable<bool>(completed.value);
    }
    if (completedAtMs.present) {
      map['completed_at_ms'] = Variable<int>(completedAtMs.value);
    }
    if (contributingSessionCount.present) {
      map['contributing_session_count'] = Variable<int>(
        contributingSessionCount.value,
      );
    }
    if (contributingSessionIdsCsv.present) {
      map['contributing_session_ids_csv'] = Variable<String>(
        contributingSessionIdsCsv.value,
      );
    }
    if (rewardsClaimed.present) {
      map['rewards_claimed'] = Variable<bool>(rewardsClaimed.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('EventParticipationsCompanion(')
          ..write('id: $id, ')
          ..write('participationUuid: $participationUuid, ')
          ..write('eventId: $eventId, ')
          ..write('userId: $userId, ')
          ..write('displayName: $displayName, ')
          ..write('joinedAtMs: $joinedAtMs, ')
          ..write('currentValue: $currentValue, ')
          ..write('rank: $rank, ')
          ..write('completed: $completed, ')
          ..write('completedAtMs: $completedAtMs, ')
          ..write('contributingSessionCount: $contributingSessionCount, ')
          ..write('contributingSessionIdsCsv: $contributingSessionIdsCsv, ')
          ..write('rewardsClaimed: $rewardsClaimed')
          ..write(')'))
        .toString();
  }
}

class $LeaderboardSnapshotsTable extends LeaderboardSnapshots
    with TableInfo<$LeaderboardSnapshotsTable, LeaderboardSnapshot> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $LeaderboardSnapshotsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _snapshotUuidMeta = const VerificationMeta(
    'snapshotUuid',
  );
  @override
  late final GeneratedColumn<String> snapshotUuid = GeneratedColumn<String>(
    'snapshot_uuid',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways('UNIQUE'),
  );
  static const VerificationMeta _scopeOrdinalMeta = const VerificationMeta(
    'scopeOrdinal',
  );
  @override
  late final GeneratedColumn<String> scopeOrdinal = GeneratedColumn<String>(
    'scope_ordinal',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _groupIdMeta = const VerificationMeta(
    'groupId',
  );
  @override
  late final GeneratedColumn<String> groupId = GeneratedColumn<String>(
    'group_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _periodOrdinalMeta = const VerificationMeta(
    'periodOrdinal',
  );
  @override
  late final GeneratedColumn<String> periodOrdinal = GeneratedColumn<String>(
    'period_ordinal',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _metricOrdinalMeta = const VerificationMeta(
    'metricOrdinal',
  );
  @override
  late final GeneratedColumn<String> metricOrdinal = GeneratedColumn<String>(
    'metric_ordinal',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _periodKeyMeta = const VerificationMeta(
    'periodKey',
  );
  @override
  late final GeneratedColumn<String> periodKey = GeneratedColumn<String>(
    'period_key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _computedAtMsMeta = const VerificationMeta(
    'computedAtMs',
  );
  @override
  late final GeneratedColumn<int> computedAtMs = GeneratedColumn<int>(
    'computed_at_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _isFinalMeta = const VerificationMeta(
    'isFinal',
  );
  @override
  late final GeneratedColumn<bool> isFinal = GeneratedColumn<bool>(
    'is_final',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_final" IN (0, 1))',
    ),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    snapshotUuid,
    scopeOrdinal,
    groupId,
    periodOrdinal,
    metricOrdinal,
    periodKey,
    computedAtMs,
    isFinal,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'leaderboard_snapshots';
  @override
  VerificationContext validateIntegrity(
    Insertable<LeaderboardSnapshot> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('snapshot_uuid')) {
      context.handle(
        _snapshotUuidMeta,
        snapshotUuid.isAcceptableOrUnknown(
          data['snapshot_uuid']!,
          _snapshotUuidMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_snapshotUuidMeta);
    }
    if (data.containsKey('scope_ordinal')) {
      context.handle(
        _scopeOrdinalMeta,
        scopeOrdinal.isAcceptableOrUnknown(
          data['scope_ordinal']!,
          _scopeOrdinalMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_scopeOrdinalMeta);
    }
    if (data.containsKey('group_id')) {
      context.handle(
        _groupIdMeta,
        groupId.isAcceptableOrUnknown(data['group_id']!, _groupIdMeta),
      );
    }
    if (data.containsKey('period_ordinal')) {
      context.handle(
        _periodOrdinalMeta,
        periodOrdinal.isAcceptableOrUnknown(
          data['period_ordinal']!,
          _periodOrdinalMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_periodOrdinalMeta);
    }
    if (data.containsKey('metric_ordinal')) {
      context.handle(
        _metricOrdinalMeta,
        metricOrdinal.isAcceptableOrUnknown(
          data['metric_ordinal']!,
          _metricOrdinalMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_metricOrdinalMeta);
    }
    if (data.containsKey('period_key')) {
      context.handle(
        _periodKeyMeta,
        periodKey.isAcceptableOrUnknown(data['period_key']!, _periodKeyMeta),
      );
    } else if (isInserting) {
      context.missing(_periodKeyMeta);
    }
    if (data.containsKey('computed_at_ms')) {
      context.handle(
        _computedAtMsMeta,
        computedAtMs.isAcceptableOrUnknown(
          data['computed_at_ms']!,
          _computedAtMsMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_computedAtMsMeta);
    }
    if (data.containsKey('is_final')) {
      context.handle(
        _isFinalMeta,
        isFinal.isAcceptableOrUnknown(data['is_final']!, _isFinalMeta),
      );
    } else if (isInserting) {
      context.missing(_isFinalMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  LeaderboardSnapshot map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return LeaderboardSnapshot(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      snapshotUuid: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}snapshot_uuid'],
      )!,
      scopeOrdinal: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}scope_ordinal'],
      )!,
      groupId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}group_id'],
      ),
      periodOrdinal: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}period_ordinal'],
      )!,
      metricOrdinal: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}metric_ordinal'],
      )!,
      periodKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}period_key'],
      )!,
      computedAtMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}computed_at_ms'],
      )!,
      isFinal: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_final'],
      )!,
    );
  }

  @override
  $LeaderboardSnapshotsTable createAlias(String alias) {
    return $LeaderboardSnapshotsTable(attachedDatabase, alias);
  }
}

class LeaderboardSnapshot extends DataClass
    implements Insertable<LeaderboardSnapshot> {
  final int id;
  final String snapshotUuid;
  final String scopeOrdinal;
  final String? groupId;
  final String periodOrdinal;
  final String metricOrdinal;
  final String periodKey;
  final int computedAtMs;
  final bool isFinal;
  const LeaderboardSnapshot({
    required this.id,
    required this.snapshotUuid,
    required this.scopeOrdinal,
    this.groupId,
    required this.periodOrdinal,
    required this.metricOrdinal,
    required this.periodKey,
    required this.computedAtMs,
    required this.isFinal,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['snapshot_uuid'] = Variable<String>(snapshotUuid);
    map['scope_ordinal'] = Variable<String>(scopeOrdinal);
    if (!nullToAbsent || groupId != null) {
      map['group_id'] = Variable<String>(groupId);
    }
    map['period_ordinal'] = Variable<String>(periodOrdinal);
    map['metric_ordinal'] = Variable<String>(metricOrdinal);
    map['period_key'] = Variable<String>(periodKey);
    map['computed_at_ms'] = Variable<int>(computedAtMs);
    map['is_final'] = Variable<bool>(isFinal);
    return map;
  }

  LeaderboardSnapshotsCompanion toCompanion(bool nullToAbsent) {
    return LeaderboardSnapshotsCompanion(
      id: Value(id),
      snapshotUuid: Value(snapshotUuid),
      scopeOrdinal: Value(scopeOrdinal),
      groupId: groupId == null && nullToAbsent
          ? const Value.absent()
          : Value(groupId),
      periodOrdinal: Value(periodOrdinal),
      metricOrdinal: Value(metricOrdinal),
      periodKey: Value(periodKey),
      computedAtMs: Value(computedAtMs),
      isFinal: Value(isFinal),
    );
  }

  factory LeaderboardSnapshot.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return LeaderboardSnapshot(
      id: serializer.fromJson<int>(json['id']),
      snapshotUuid: serializer.fromJson<String>(json['snapshotUuid']),
      scopeOrdinal: serializer.fromJson<String>(json['scopeOrdinal']),
      groupId: serializer.fromJson<String?>(json['groupId']),
      periodOrdinal: serializer.fromJson<String>(json['periodOrdinal']),
      metricOrdinal: serializer.fromJson<String>(json['metricOrdinal']),
      periodKey: serializer.fromJson<String>(json['periodKey']),
      computedAtMs: serializer.fromJson<int>(json['computedAtMs']),
      isFinal: serializer.fromJson<bool>(json['isFinal']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'snapshotUuid': serializer.toJson<String>(snapshotUuid),
      'scopeOrdinal': serializer.toJson<String>(scopeOrdinal),
      'groupId': serializer.toJson<String?>(groupId),
      'periodOrdinal': serializer.toJson<String>(periodOrdinal),
      'metricOrdinal': serializer.toJson<String>(metricOrdinal),
      'periodKey': serializer.toJson<String>(periodKey),
      'computedAtMs': serializer.toJson<int>(computedAtMs),
      'isFinal': serializer.toJson<bool>(isFinal),
    };
  }

  LeaderboardSnapshot copyWith({
    int? id,
    String? snapshotUuid,
    String? scopeOrdinal,
    Value<String?> groupId = const Value.absent(),
    String? periodOrdinal,
    String? metricOrdinal,
    String? periodKey,
    int? computedAtMs,
    bool? isFinal,
  }) => LeaderboardSnapshot(
    id: id ?? this.id,
    snapshotUuid: snapshotUuid ?? this.snapshotUuid,
    scopeOrdinal: scopeOrdinal ?? this.scopeOrdinal,
    groupId: groupId.present ? groupId.value : this.groupId,
    periodOrdinal: periodOrdinal ?? this.periodOrdinal,
    metricOrdinal: metricOrdinal ?? this.metricOrdinal,
    periodKey: periodKey ?? this.periodKey,
    computedAtMs: computedAtMs ?? this.computedAtMs,
    isFinal: isFinal ?? this.isFinal,
  );
  LeaderboardSnapshot copyWithCompanion(LeaderboardSnapshotsCompanion data) {
    return LeaderboardSnapshot(
      id: data.id.present ? data.id.value : this.id,
      snapshotUuid: data.snapshotUuid.present
          ? data.snapshotUuid.value
          : this.snapshotUuid,
      scopeOrdinal: data.scopeOrdinal.present
          ? data.scopeOrdinal.value
          : this.scopeOrdinal,
      groupId: data.groupId.present ? data.groupId.value : this.groupId,
      periodOrdinal: data.periodOrdinal.present
          ? data.periodOrdinal.value
          : this.periodOrdinal,
      metricOrdinal: data.metricOrdinal.present
          ? data.metricOrdinal.value
          : this.metricOrdinal,
      periodKey: data.periodKey.present ? data.periodKey.value : this.periodKey,
      computedAtMs: data.computedAtMs.present
          ? data.computedAtMs.value
          : this.computedAtMs,
      isFinal: data.isFinal.present ? data.isFinal.value : this.isFinal,
    );
  }

  @override
  String toString() {
    return (StringBuffer('LeaderboardSnapshot(')
          ..write('id: $id, ')
          ..write('snapshotUuid: $snapshotUuid, ')
          ..write('scopeOrdinal: $scopeOrdinal, ')
          ..write('groupId: $groupId, ')
          ..write('periodOrdinal: $periodOrdinal, ')
          ..write('metricOrdinal: $metricOrdinal, ')
          ..write('periodKey: $periodKey, ')
          ..write('computedAtMs: $computedAtMs, ')
          ..write('isFinal: $isFinal')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    snapshotUuid,
    scopeOrdinal,
    groupId,
    periodOrdinal,
    metricOrdinal,
    periodKey,
    computedAtMs,
    isFinal,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is LeaderboardSnapshot &&
          other.id == this.id &&
          other.snapshotUuid == this.snapshotUuid &&
          other.scopeOrdinal == this.scopeOrdinal &&
          other.groupId == this.groupId &&
          other.periodOrdinal == this.periodOrdinal &&
          other.metricOrdinal == this.metricOrdinal &&
          other.periodKey == this.periodKey &&
          other.computedAtMs == this.computedAtMs &&
          other.isFinal == this.isFinal);
}

class LeaderboardSnapshotsCompanion
    extends UpdateCompanion<LeaderboardSnapshot> {
  final Value<int> id;
  final Value<String> snapshotUuid;
  final Value<String> scopeOrdinal;
  final Value<String?> groupId;
  final Value<String> periodOrdinal;
  final Value<String> metricOrdinal;
  final Value<String> periodKey;
  final Value<int> computedAtMs;
  final Value<bool> isFinal;
  const LeaderboardSnapshotsCompanion({
    this.id = const Value.absent(),
    this.snapshotUuid = const Value.absent(),
    this.scopeOrdinal = const Value.absent(),
    this.groupId = const Value.absent(),
    this.periodOrdinal = const Value.absent(),
    this.metricOrdinal = const Value.absent(),
    this.periodKey = const Value.absent(),
    this.computedAtMs = const Value.absent(),
    this.isFinal = const Value.absent(),
  });
  LeaderboardSnapshotsCompanion.insert({
    this.id = const Value.absent(),
    required String snapshotUuid,
    required String scopeOrdinal,
    this.groupId = const Value.absent(),
    required String periodOrdinal,
    required String metricOrdinal,
    required String periodKey,
    required int computedAtMs,
    required bool isFinal,
  }) : snapshotUuid = Value(snapshotUuid),
       scopeOrdinal = Value(scopeOrdinal),
       periodOrdinal = Value(periodOrdinal),
       metricOrdinal = Value(metricOrdinal),
       periodKey = Value(periodKey),
       computedAtMs = Value(computedAtMs),
       isFinal = Value(isFinal);
  static Insertable<LeaderboardSnapshot> custom({
    Expression<int>? id,
    Expression<String>? snapshotUuid,
    Expression<String>? scopeOrdinal,
    Expression<String>? groupId,
    Expression<String>? periodOrdinal,
    Expression<String>? metricOrdinal,
    Expression<String>? periodKey,
    Expression<int>? computedAtMs,
    Expression<bool>? isFinal,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (snapshotUuid != null) 'snapshot_uuid': snapshotUuid,
      if (scopeOrdinal != null) 'scope_ordinal': scopeOrdinal,
      if (groupId != null) 'group_id': groupId,
      if (periodOrdinal != null) 'period_ordinal': periodOrdinal,
      if (metricOrdinal != null) 'metric_ordinal': metricOrdinal,
      if (periodKey != null) 'period_key': periodKey,
      if (computedAtMs != null) 'computed_at_ms': computedAtMs,
      if (isFinal != null) 'is_final': isFinal,
    });
  }

  LeaderboardSnapshotsCompanion copyWith({
    Value<int>? id,
    Value<String>? snapshotUuid,
    Value<String>? scopeOrdinal,
    Value<String?>? groupId,
    Value<String>? periodOrdinal,
    Value<String>? metricOrdinal,
    Value<String>? periodKey,
    Value<int>? computedAtMs,
    Value<bool>? isFinal,
  }) {
    return LeaderboardSnapshotsCompanion(
      id: id ?? this.id,
      snapshotUuid: snapshotUuid ?? this.snapshotUuid,
      scopeOrdinal: scopeOrdinal ?? this.scopeOrdinal,
      groupId: groupId ?? this.groupId,
      periodOrdinal: periodOrdinal ?? this.periodOrdinal,
      metricOrdinal: metricOrdinal ?? this.metricOrdinal,
      periodKey: periodKey ?? this.periodKey,
      computedAtMs: computedAtMs ?? this.computedAtMs,
      isFinal: isFinal ?? this.isFinal,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (snapshotUuid.present) {
      map['snapshot_uuid'] = Variable<String>(snapshotUuid.value);
    }
    if (scopeOrdinal.present) {
      map['scope_ordinal'] = Variable<String>(scopeOrdinal.value);
    }
    if (groupId.present) {
      map['group_id'] = Variable<String>(groupId.value);
    }
    if (periodOrdinal.present) {
      map['period_ordinal'] = Variable<String>(periodOrdinal.value);
    }
    if (metricOrdinal.present) {
      map['metric_ordinal'] = Variable<String>(metricOrdinal.value);
    }
    if (periodKey.present) {
      map['period_key'] = Variable<String>(periodKey.value);
    }
    if (computedAtMs.present) {
      map['computed_at_ms'] = Variable<int>(computedAtMs.value);
    }
    if (isFinal.present) {
      map['is_final'] = Variable<bool>(isFinal.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('LeaderboardSnapshotsCompanion(')
          ..write('id: $id, ')
          ..write('snapshotUuid: $snapshotUuid, ')
          ..write('scopeOrdinal: $scopeOrdinal, ')
          ..write('groupId: $groupId, ')
          ..write('periodOrdinal: $periodOrdinal, ')
          ..write('metricOrdinal: $metricOrdinal, ')
          ..write('periodKey: $periodKey, ')
          ..write('computedAtMs: $computedAtMs, ')
          ..write('isFinal: $isFinal')
          ..write(')'))
        .toString();
  }
}

class $LeaderboardEntriesTable extends LeaderboardEntries
    with TableInfo<$LeaderboardEntriesTable, LeaderboardEntry> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $LeaderboardEntriesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _snapshotIdMeta = const VerificationMeta(
    'snapshotId',
  );
  @override
  late final GeneratedColumn<String> snapshotId = GeneratedColumn<String>(
    'snapshot_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _userIdMeta = const VerificationMeta('userId');
  @override
  late final GeneratedColumn<String> userId = GeneratedColumn<String>(
    'user_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _displayNameMeta = const VerificationMeta(
    'displayName',
  );
  @override
  late final GeneratedColumn<String> displayName = GeneratedColumn<String>(
    'display_name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _avatarUrlMeta = const VerificationMeta(
    'avatarUrl',
  );
  @override
  late final GeneratedColumn<String> avatarUrl = GeneratedColumn<String>(
    'avatar_url',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _levelMeta = const VerificationMeta('level');
  @override
  late final GeneratedColumn<int> level = GeneratedColumn<int>(
    'level',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _valueMeta = const VerificationMeta('value');
  @override
  late final GeneratedColumn<double> value = GeneratedColumn<double>(
    'value',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _rankMeta = const VerificationMeta('rank');
  @override
  late final GeneratedColumn<int> rank = GeneratedColumn<int>(
    'rank',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _periodKeyMeta = const VerificationMeta(
    'periodKey',
  );
  @override
  late final GeneratedColumn<String> periodKey = GeneratedColumn<String>(
    'period_key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    snapshotId,
    userId,
    displayName,
    avatarUrl,
    level,
    value,
    rank,
    periodKey,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'leaderboard_entries';
  @override
  VerificationContext validateIntegrity(
    Insertable<LeaderboardEntry> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('snapshot_id')) {
      context.handle(
        _snapshotIdMeta,
        snapshotId.isAcceptableOrUnknown(data['snapshot_id']!, _snapshotIdMeta),
      );
    } else if (isInserting) {
      context.missing(_snapshotIdMeta);
    }
    if (data.containsKey('user_id')) {
      context.handle(
        _userIdMeta,
        userId.isAcceptableOrUnknown(data['user_id']!, _userIdMeta),
      );
    } else if (isInserting) {
      context.missing(_userIdMeta);
    }
    if (data.containsKey('display_name')) {
      context.handle(
        _displayNameMeta,
        displayName.isAcceptableOrUnknown(
          data['display_name']!,
          _displayNameMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_displayNameMeta);
    }
    if (data.containsKey('avatar_url')) {
      context.handle(
        _avatarUrlMeta,
        avatarUrl.isAcceptableOrUnknown(data['avatar_url']!, _avatarUrlMeta),
      );
    }
    if (data.containsKey('level')) {
      context.handle(
        _levelMeta,
        level.isAcceptableOrUnknown(data['level']!, _levelMeta),
      );
    } else if (isInserting) {
      context.missing(_levelMeta);
    }
    if (data.containsKey('value')) {
      context.handle(
        _valueMeta,
        value.isAcceptableOrUnknown(data['value']!, _valueMeta),
      );
    } else if (isInserting) {
      context.missing(_valueMeta);
    }
    if (data.containsKey('rank')) {
      context.handle(
        _rankMeta,
        rank.isAcceptableOrUnknown(data['rank']!, _rankMeta),
      );
    } else if (isInserting) {
      context.missing(_rankMeta);
    }
    if (data.containsKey('period_key')) {
      context.handle(
        _periodKeyMeta,
        periodKey.isAcceptableOrUnknown(data['period_key']!, _periodKeyMeta),
      );
    } else if (isInserting) {
      context.missing(_periodKeyMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  LeaderboardEntry map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return LeaderboardEntry(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      snapshotId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}snapshot_id'],
      )!,
      userId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}user_id'],
      )!,
      displayName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}display_name'],
      )!,
      avatarUrl: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}avatar_url'],
      ),
      level: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}level'],
      )!,
      value: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}value'],
      )!,
      rank: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}rank'],
      )!,
      periodKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}period_key'],
      )!,
    );
  }

  @override
  $LeaderboardEntriesTable createAlias(String alias) {
    return $LeaderboardEntriesTable(attachedDatabase, alias);
  }
}

class LeaderboardEntry extends DataClass
    implements Insertable<LeaderboardEntry> {
  final int id;
  final String snapshotId;
  final String userId;
  final String displayName;
  final String? avatarUrl;
  final int level;
  final double value;
  final int rank;
  final String periodKey;
  const LeaderboardEntry({
    required this.id,
    required this.snapshotId,
    required this.userId,
    required this.displayName,
    this.avatarUrl,
    required this.level,
    required this.value,
    required this.rank,
    required this.periodKey,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['snapshot_id'] = Variable<String>(snapshotId);
    map['user_id'] = Variable<String>(userId);
    map['display_name'] = Variable<String>(displayName);
    if (!nullToAbsent || avatarUrl != null) {
      map['avatar_url'] = Variable<String>(avatarUrl);
    }
    map['level'] = Variable<int>(level);
    map['value'] = Variable<double>(value);
    map['rank'] = Variable<int>(rank);
    map['period_key'] = Variable<String>(periodKey);
    return map;
  }

  LeaderboardEntriesCompanion toCompanion(bool nullToAbsent) {
    return LeaderboardEntriesCompanion(
      id: Value(id),
      snapshotId: Value(snapshotId),
      userId: Value(userId),
      displayName: Value(displayName),
      avatarUrl: avatarUrl == null && nullToAbsent
          ? const Value.absent()
          : Value(avatarUrl),
      level: Value(level),
      value: Value(value),
      rank: Value(rank),
      periodKey: Value(periodKey),
    );
  }

  factory LeaderboardEntry.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return LeaderboardEntry(
      id: serializer.fromJson<int>(json['id']),
      snapshotId: serializer.fromJson<String>(json['snapshotId']),
      userId: serializer.fromJson<String>(json['userId']),
      displayName: serializer.fromJson<String>(json['displayName']),
      avatarUrl: serializer.fromJson<String?>(json['avatarUrl']),
      level: serializer.fromJson<int>(json['level']),
      value: serializer.fromJson<double>(json['value']),
      rank: serializer.fromJson<int>(json['rank']),
      periodKey: serializer.fromJson<String>(json['periodKey']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'snapshotId': serializer.toJson<String>(snapshotId),
      'userId': serializer.toJson<String>(userId),
      'displayName': serializer.toJson<String>(displayName),
      'avatarUrl': serializer.toJson<String?>(avatarUrl),
      'level': serializer.toJson<int>(level),
      'value': serializer.toJson<double>(value),
      'rank': serializer.toJson<int>(rank),
      'periodKey': serializer.toJson<String>(periodKey),
    };
  }

  LeaderboardEntry copyWith({
    int? id,
    String? snapshotId,
    String? userId,
    String? displayName,
    Value<String?> avatarUrl = const Value.absent(),
    int? level,
    double? value,
    int? rank,
    String? periodKey,
  }) => LeaderboardEntry(
    id: id ?? this.id,
    snapshotId: snapshotId ?? this.snapshotId,
    userId: userId ?? this.userId,
    displayName: displayName ?? this.displayName,
    avatarUrl: avatarUrl.present ? avatarUrl.value : this.avatarUrl,
    level: level ?? this.level,
    value: value ?? this.value,
    rank: rank ?? this.rank,
    periodKey: periodKey ?? this.periodKey,
  );
  LeaderboardEntry copyWithCompanion(LeaderboardEntriesCompanion data) {
    return LeaderboardEntry(
      id: data.id.present ? data.id.value : this.id,
      snapshotId: data.snapshotId.present
          ? data.snapshotId.value
          : this.snapshotId,
      userId: data.userId.present ? data.userId.value : this.userId,
      displayName: data.displayName.present
          ? data.displayName.value
          : this.displayName,
      avatarUrl: data.avatarUrl.present ? data.avatarUrl.value : this.avatarUrl,
      level: data.level.present ? data.level.value : this.level,
      value: data.value.present ? data.value.value : this.value,
      rank: data.rank.present ? data.rank.value : this.rank,
      periodKey: data.periodKey.present ? data.periodKey.value : this.periodKey,
    );
  }

  @override
  String toString() {
    return (StringBuffer('LeaderboardEntry(')
          ..write('id: $id, ')
          ..write('snapshotId: $snapshotId, ')
          ..write('userId: $userId, ')
          ..write('displayName: $displayName, ')
          ..write('avatarUrl: $avatarUrl, ')
          ..write('level: $level, ')
          ..write('value: $value, ')
          ..write('rank: $rank, ')
          ..write('periodKey: $periodKey')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    snapshotId,
    userId,
    displayName,
    avatarUrl,
    level,
    value,
    rank,
    periodKey,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is LeaderboardEntry &&
          other.id == this.id &&
          other.snapshotId == this.snapshotId &&
          other.userId == this.userId &&
          other.displayName == this.displayName &&
          other.avatarUrl == this.avatarUrl &&
          other.level == this.level &&
          other.value == this.value &&
          other.rank == this.rank &&
          other.periodKey == this.periodKey);
}

class LeaderboardEntriesCompanion extends UpdateCompanion<LeaderboardEntry> {
  final Value<int> id;
  final Value<String> snapshotId;
  final Value<String> userId;
  final Value<String> displayName;
  final Value<String?> avatarUrl;
  final Value<int> level;
  final Value<double> value;
  final Value<int> rank;
  final Value<String> periodKey;
  const LeaderboardEntriesCompanion({
    this.id = const Value.absent(),
    this.snapshotId = const Value.absent(),
    this.userId = const Value.absent(),
    this.displayName = const Value.absent(),
    this.avatarUrl = const Value.absent(),
    this.level = const Value.absent(),
    this.value = const Value.absent(),
    this.rank = const Value.absent(),
    this.periodKey = const Value.absent(),
  });
  LeaderboardEntriesCompanion.insert({
    this.id = const Value.absent(),
    required String snapshotId,
    required String userId,
    required String displayName,
    this.avatarUrl = const Value.absent(),
    required int level,
    required double value,
    required int rank,
    required String periodKey,
  }) : snapshotId = Value(snapshotId),
       userId = Value(userId),
       displayName = Value(displayName),
       level = Value(level),
       value = Value(value),
       rank = Value(rank),
       periodKey = Value(periodKey);
  static Insertable<LeaderboardEntry> custom({
    Expression<int>? id,
    Expression<String>? snapshotId,
    Expression<String>? userId,
    Expression<String>? displayName,
    Expression<String>? avatarUrl,
    Expression<int>? level,
    Expression<double>? value,
    Expression<int>? rank,
    Expression<String>? periodKey,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (snapshotId != null) 'snapshot_id': snapshotId,
      if (userId != null) 'user_id': userId,
      if (displayName != null) 'display_name': displayName,
      if (avatarUrl != null) 'avatar_url': avatarUrl,
      if (level != null) 'level': level,
      if (value != null) 'value': value,
      if (rank != null) 'rank': rank,
      if (periodKey != null) 'period_key': periodKey,
    });
  }

  LeaderboardEntriesCompanion copyWith({
    Value<int>? id,
    Value<String>? snapshotId,
    Value<String>? userId,
    Value<String>? displayName,
    Value<String?>? avatarUrl,
    Value<int>? level,
    Value<double>? value,
    Value<int>? rank,
    Value<String>? periodKey,
  }) {
    return LeaderboardEntriesCompanion(
      id: id ?? this.id,
      snapshotId: snapshotId ?? this.snapshotId,
      userId: userId ?? this.userId,
      displayName: displayName ?? this.displayName,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      level: level ?? this.level,
      value: value ?? this.value,
      rank: rank ?? this.rank,
      periodKey: periodKey ?? this.periodKey,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (snapshotId.present) {
      map['snapshot_id'] = Variable<String>(snapshotId.value);
    }
    if (userId.present) {
      map['user_id'] = Variable<String>(userId.value);
    }
    if (displayName.present) {
      map['display_name'] = Variable<String>(displayName.value);
    }
    if (avatarUrl.present) {
      map['avatar_url'] = Variable<String>(avatarUrl.value);
    }
    if (level.present) {
      map['level'] = Variable<int>(level.value);
    }
    if (value.present) {
      map['value'] = Variable<double>(value.value);
    }
    if (rank.present) {
      map['rank'] = Variable<int>(rank.value);
    }
    if (periodKey.present) {
      map['period_key'] = Variable<String>(periodKey.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('LeaderboardEntriesCompanion(')
          ..write('id: $id, ')
          ..write('snapshotId: $snapshotId, ')
          ..write('userId: $userId, ')
          ..write('displayName: $displayName, ')
          ..write('avatarUrl: $avatarUrl, ')
          ..write('level: $level, ')
          ..write('value: $value, ')
          ..write('rank: $rank, ')
          ..write('periodKey: $periodKey')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $LocationPointsTable locationPoints = $LocationPointsTable(this);
  late final $WorkoutSessionsTable workoutSessions = $WorkoutSessionsTable(
    this,
  );
  late final $ChallengesTable challenges = $ChallengesTable(this);
  late final $ChallengeResultsTable challengeResults = $ChallengeResultsTable(
    this,
  );
  late final $WalletsTable wallets = $WalletsTable(this);
  late final $LedgerEntriesTable ledgerEntries = $LedgerEntriesTable(this);
  late final $ProfileProgressesTable profileProgresses =
      $ProfileProgressesTable(this);
  late final $XpTransactionsTable xpTransactions = $XpTransactionsTable(this);
  late final $BadgeAwardsTable badgeAwards = $BadgeAwardsTable(this);
  late final $MissionProgressesTable missionProgresses =
      $MissionProgressesTable(this);
  late final $SeasonsTable seasons = $SeasonsTable(this);
  late final $SeasonProgressesTable seasonProgresses = $SeasonProgressesTable(
    this,
  );
  late final $CoachingGroupsTable coachingGroups = $CoachingGroupsTable(this);
  late final $CoachingMembersTable coachingMembers = $CoachingMembersTable(
    this,
  );
  late final $CoachingInvitesTable coachingInvites = $CoachingInvitesTable(
    this,
  );
  late final $CoachingRankingsTable coachingRankings = $CoachingRankingsTable(
    this,
  );
  late final $CoachingRankingEntriesTable coachingRankingEntries =
      $CoachingRankingEntriesTable(this);
  late final $AthleteBaselinesTable athleteBaselines = $AthleteBaselinesTable(
    this,
  );
  late final $AthleteTrendsTable athleteTrends = $AthleteTrendsTable(this);
  late final $CoachInsightsTable coachInsights = $CoachInsightsTable(this);
  late final $FriendshipsTable friendships = $FriendshipsTable(this);
  late final $GroupsTable groups = $GroupsTable(this);
  late final $GroupMembersTable groupMembers = $GroupMembersTable(this);
  late final $GroupGoalsTable groupGoals = $GroupGoalsTable(this);
  late final $EventsTable events = $EventsTable(this);
  late final $EventParticipationsTable eventParticipations =
      $EventParticipationsTable(this);
  late final $LeaderboardSnapshotsTable leaderboardSnapshots =
      $LeaderboardSnapshotsTable(this);
  late final $LeaderboardEntriesTable leaderboardEntries =
      $LeaderboardEntriesTable(this);
  late final Index idxLocationSessionTime = Index(
    'idx_location_session_time',
    'CREATE INDEX idx_location_session_time ON location_points (session_id, timestamp_ms)',
  );
  late final Index idxWorkoutStatus = Index(
    'idx_workout_status',
    'CREATE INDEX idx_workout_status ON workout_sessions (status)',
  );
  late final Index idxWorkoutStartTime = Index(
    'idx_workout_start_time',
    'CREATE INDEX idx_workout_start_time ON workout_sessions (start_time_ms)',
  );
  late final Index idxWorkoutVerified = Index(
    'idx_workout_verified',
    'CREATE INDEX idx_workout_verified ON workout_sessions (is_verified)',
  );
  late final Index idxWorkoutSynced = Index(
    'idx_workout_synced',
    'CREATE INDEX idx_workout_synced ON workout_sessions (is_synced)',
  );
  late final Index idxChallengeCreator = Index(
    'idx_challenge_creator',
    'CREATE INDEX idx_challenge_creator ON challenges (creator_user_id)',
  );
  late final Index idxChallengeStatus = Index(
    'idx_challenge_status',
    'CREATE INDEX idx_challenge_status ON challenges (status)',
  );
  late final Index idxChallengeCreatedAt = Index(
    'idx_challenge_created_at',
    'CREATE INDEX idx_challenge_created_at ON challenges (created_at_ms)',
  );
  late final Index idxLedgerUser = Index(
    'idx_ledger_user',
    'CREATE INDEX idx_ledger_user ON ledger_entries (user_id)',
  );
  late final Index idxLedgerRef = Index(
    'idx_ledger_ref',
    'CREATE INDEX idx_ledger_ref ON ledger_entries (ref_id)',
  );
  late final Index idxLedgerIssuer = Index(
    'idx_ledger_issuer',
    'CREATE INDEX idx_ledger_issuer ON ledger_entries (issuer_group_id)',
  );
  late final Index idxLedgerCreatedAt = Index(
    'idx_ledger_created_at',
    'CREATE INDEX idx_ledger_created_at ON ledger_entries (created_at_ms)',
  );
  late final Index idxXpUser = Index(
    'idx_xp_user',
    'CREATE INDEX idx_xp_user ON xp_transactions (user_id)',
  );
  late final Index idxXpRef = Index(
    'idx_xp_ref',
    'CREATE INDEX idx_xp_ref ON xp_transactions (ref_id)',
  );
  late final Index idxXpCreatedAt = Index(
    'idx_xp_created_at',
    'CREATE INDEX idx_xp_created_at ON xp_transactions (created_at_ms)',
  );
  late final Index idxBadgeUser = Index(
    'idx_badge_user',
    'CREATE INDEX idx_badge_user ON badge_awards (user_id)',
  );
  late final Index idxBadgeBadge = Index(
    'idx_badge_badge',
    'CREATE INDEX idx_badge_badge ON badge_awards (badge_id)',
  );
  late final Index idxMissionUser = Index(
    'idx_mission_user',
    'CREATE INDEX idx_mission_user ON mission_progresses (user_id)',
  );
  late final Index idxMissionId = Index(
    'idx_mission_id',
    'CREATE INDEX idx_mission_id ON mission_progresses (mission_id)',
  );
  late final Index idxMissionStatus = Index(
    'idx_mission_status',
    'CREATE INDEX idx_mission_status ON mission_progresses (status_ordinal)',
  );
  late final Index idxSeasonStatus = Index(
    'idx_season_status',
    'CREATE INDEX idx_season_status ON seasons (status_ordinal)',
  );
  late final Index idxSeasonProgUser = Index(
    'idx_season_prog_user',
    'CREATE INDEX idx_season_prog_user ON season_progresses (user_id)',
  );
  late final Index idxSeasonProgSeason = Index(
    'idx_season_prog_season',
    'CREATE INDEX idx_season_prog_season ON season_progresses (season_id)',
  );
  late final Index idxCgCoach = Index(
    'idx_cg_coach',
    'CREATE INDEX idx_cg_coach ON coaching_groups (coach_user_id)',
  );
  late final Index idxCmGroup = Index(
    'idx_cm_group',
    'CREATE INDEX idx_cm_group ON coaching_members (group_id)',
  );
  late final Index idxCmUser = Index(
    'idx_cm_user',
    'CREATE INDEX idx_cm_user ON coaching_members (user_id)',
  );
  late final Index idxCiGroup = Index(
    'idx_ci_group',
    'CREATE INDEX idx_ci_group ON coaching_invites (group_id)',
  );
  late final Index idxCiInvited = Index(
    'idx_ci_invited',
    'CREATE INDEX idx_ci_invited ON coaching_invites (invited_user_id)',
  );
  late final Index idxCiStatus = Index(
    'idx_ci_status',
    'CREATE INDEX idx_ci_status ON coaching_invites (status_ordinal)',
  );
  late final Index idxCrGroup = Index(
    'idx_cr_group',
    'CREATE INDEX idx_cr_group ON coaching_rankings (group_id)',
  );
  late final Index idxCrPeriodKey = Index(
    'idx_cr_period_key',
    'CREATE INDEX idx_cr_period_key ON coaching_rankings (period_key)',
  );
  late final Index idxCreRanking = Index(
    'idx_cre_ranking',
    'CREATE INDEX idx_cre_ranking ON coaching_ranking_entries (ranking_id)',
  );
  late final Index idxCreUser = Index(
    'idx_cre_user',
    'CREATE INDEX idx_cre_user ON coaching_ranking_entries (user_id)',
  );
  late final Index idxAbUser = Index(
    'idx_ab_user',
    'CREATE INDEX idx_ab_user ON athlete_baselines (user_id)',
  );
  late final Index idxAbGroup = Index(
    'idx_ab_group',
    'CREATE INDEX idx_ab_group ON athlete_baselines (group_id)',
  );
  late final Index idxAtUser = Index(
    'idx_at_user',
    'CREATE INDEX idx_at_user ON athlete_trends (user_id)',
  );
  late final Index idxAtGroup = Index(
    'idx_at_group',
    'CREATE INDEX idx_at_group ON athlete_trends (group_id)',
  );
  late final Index idxAtDirection = Index(
    'idx_at_direction',
    'CREATE INDEX idx_at_direction ON athlete_trends (direction_ordinal)',
  );
  late final Index idxInsightGroup = Index(
    'idx_insight_group',
    'CREATE INDEX idx_insight_group ON coach_insights (group_id)',
  );
  late final Index idxInsightTarget = Index(
    'idx_insight_target',
    'CREATE INDEX idx_insight_target ON coach_insights (target_user_id)',
  );
  late final Index idxInsightType = Index(
    'idx_insight_type',
    'CREATE INDEX idx_insight_type ON coach_insights (type_ordinal)',
  );
  late final Index idxInsightPriority = Index(
    'idx_insight_priority',
    'CREATE INDEX idx_insight_priority ON coach_insights (priority_ordinal)',
  );
  late final Index idxInsightRead = Index(
    'idx_insight_read',
    'CREATE INDEX idx_insight_read ON coach_insights (read_at_ms)',
  );
  late final Index idxFriendB = Index(
    'idx_friend_b',
    'CREATE INDEX idx_friend_b ON friendships (user_id_b)',
  );
  late final Index idxFriendStatus = Index(
    'idx_friend_status',
    'CREATE INDEX idx_friend_status ON friendships (status_ordinal)',
  );
  late final Index idxGroupCreator = Index(
    'idx_group_creator',
    'CREATE INDEX idx_group_creator ON "groups" (created_by_user_id)',
  );
  late final Index idxGmGroup = Index(
    'idx_gm_group',
    'CREATE INDEX idx_gm_group ON group_members (group_id)',
  );
  late final Index idxGmUser = Index(
    'idx_gm_user',
    'CREATE INDEX idx_gm_user ON group_members (user_id)',
  );
  late final Index idxGmStatus = Index(
    'idx_gm_status',
    'CREATE INDEX idx_gm_status ON group_members (status_ordinal)',
  );
  late final Index idxGgGroup = Index(
    'idx_gg_group',
    'CREATE INDEX idx_gg_group ON group_goals (group_id)',
  );
  late final Index idxGgStatus = Index(
    'idx_gg_status',
    'CREATE INDEX idx_gg_status ON group_goals (status_ordinal)',
  );
  late final Index idxEventStatus = Index(
    'idx_event_status',
    'CREATE INDEX idx_event_status ON events (status_ordinal)',
  );
  late final Index idxEpUser = Index(
    'idx_ep_user',
    'CREATE INDEX idx_ep_user ON event_participations (user_id)',
  );
  late final Index idxLbPeriodKey = Index(
    'idx_lb_period_key',
    'CREATE INDEX idx_lb_period_key ON leaderboard_snapshots (period_key)',
  );
  late final Index idxLeSnapshot = Index(
    'idx_le_snapshot',
    'CREATE INDEX idx_le_snapshot ON leaderboard_entries (snapshot_id)',
  );
  late final Index idxLeUser = Index(
    'idx_le_user',
    'CREATE INDEX idx_le_user ON leaderboard_entries (user_id)',
  );
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    locationPoints,
    workoutSessions,
    challenges,
    challengeResults,
    wallets,
    ledgerEntries,
    profileProgresses,
    xpTransactions,
    badgeAwards,
    missionProgresses,
    seasons,
    seasonProgresses,
    coachingGroups,
    coachingMembers,
    coachingInvites,
    coachingRankings,
    coachingRankingEntries,
    athleteBaselines,
    athleteTrends,
    coachInsights,
    friendships,
    groups,
    groupMembers,
    groupGoals,
    events,
    eventParticipations,
    leaderboardSnapshots,
    leaderboardEntries,
    idxLocationSessionTime,
    idxWorkoutStatus,
    idxWorkoutStartTime,
    idxWorkoutVerified,
    idxWorkoutSynced,
    idxChallengeCreator,
    idxChallengeStatus,
    idxChallengeCreatedAt,
    idxLedgerUser,
    idxLedgerRef,
    idxLedgerIssuer,
    idxLedgerCreatedAt,
    idxXpUser,
    idxXpRef,
    idxXpCreatedAt,
    idxBadgeUser,
    idxBadgeBadge,
    idxMissionUser,
    idxMissionId,
    idxMissionStatus,
    idxSeasonStatus,
    idxSeasonProgUser,
    idxSeasonProgSeason,
    idxCgCoach,
    idxCmGroup,
    idxCmUser,
    idxCiGroup,
    idxCiInvited,
    idxCiStatus,
    idxCrGroup,
    idxCrPeriodKey,
    idxCreRanking,
    idxCreUser,
    idxAbUser,
    idxAbGroup,
    idxAtUser,
    idxAtGroup,
    idxAtDirection,
    idxInsightGroup,
    idxInsightTarget,
    idxInsightType,
    idxInsightPriority,
    idxInsightRead,
    idxFriendB,
    idxFriendStatus,
    idxGroupCreator,
    idxGmGroup,
    idxGmUser,
    idxGmStatus,
    idxGgGroup,
    idxGgStatus,
    idxEventStatus,
    idxEpUser,
    idxLbPeriodKey,
    idxLeSnapshot,
    idxLeUser,
  ];
}

typedef $$LocationPointsTableCreateCompanionBuilder =
    LocationPointsCompanion Function({
      Value<int> id,
      required String sessionId,
      required double lat,
      required double lng,
      Value<double?> alt,
      Value<double?> accuracy,
      Value<double?> speed,
      Value<double?> bearing,
      required int timestampMs,
    });
typedef $$LocationPointsTableUpdateCompanionBuilder =
    LocationPointsCompanion Function({
      Value<int> id,
      Value<String> sessionId,
      Value<double> lat,
      Value<double> lng,
      Value<double?> alt,
      Value<double?> accuracy,
      Value<double?> speed,
      Value<double?> bearing,
      Value<int> timestampMs,
    });

class $$LocationPointsTableFilterComposer
    extends Composer<_$AppDatabase, $LocationPointsTable> {
  $$LocationPointsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sessionId => $composableBuilder(
    column: $table.sessionId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get lat => $composableBuilder(
    column: $table.lat,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get lng => $composableBuilder(
    column: $table.lng,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get alt => $composableBuilder(
    column: $table.alt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get accuracy => $composableBuilder(
    column: $table.accuracy,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get speed => $composableBuilder(
    column: $table.speed,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get bearing => $composableBuilder(
    column: $table.bearing,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get timestampMs => $composableBuilder(
    column: $table.timestampMs,
    builder: (column) => ColumnFilters(column),
  );
}

class $$LocationPointsTableOrderingComposer
    extends Composer<_$AppDatabase, $LocationPointsTable> {
  $$LocationPointsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sessionId => $composableBuilder(
    column: $table.sessionId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get lat => $composableBuilder(
    column: $table.lat,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get lng => $composableBuilder(
    column: $table.lng,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get alt => $composableBuilder(
    column: $table.alt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get accuracy => $composableBuilder(
    column: $table.accuracy,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get speed => $composableBuilder(
    column: $table.speed,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get bearing => $composableBuilder(
    column: $table.bearing,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get timestampMs => $composableBuilder(
    column: $table.timestampMs,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$LocationPointsTableAnnotationComposer
    extends Composer<_$AppDatabase, $LocationPointsTable> {
  $$LocationPointsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get sessionId =>
      $composableBuilder(column: $table.sessionId, builder: (column) => column);

  GeneratedColumn<double> get lat =>
      $composableBuilder(column: $table.lat, builder: (column) => column);

  GeneratedColumn<double> get lng =>
      $composableBuilder(column: $table.lng, builder: (column) => column);

  GeneratedColumn<double> get alt =>
      $composableBuilder(column: $table.alt, builder: (column) => column);

  GeneratedColumn<double> get accuracy =>
      $composableBuilder(column: $table.accuracy, builder: (column) => column);

  GeneratedColumn<double> get speed =>
      $composableBuilder(column: $table.speed, builder: (column) => column);

  GeneratedColumn<double> get bearing =>
      $composableBuilder(column: $table.bearing, builder: (column) => column);

  GeneratedColumn<int> get timestampMs => $composableBuilder(
    column: $table.timestampMs,
    builder: (column) => column,
  );
}

class $$LocationPointsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $LocationPointsTable,
          LocationPoint,
          $$LocationPointsTableFilterComposer,
          $$LocationPointsTableOrderingComposer,
          $$LocationPointsTableAnnotationComposer,
          $$LocationPointsTableCreateCompanionBuilder,
          $$LocationPointsTableUpdateCompanionBuilder,
          (
            LocationPoint,
            BaseReferences<_$AppDatabase, $LocationPointsTable, LocationPoint>,
          ),
          LocationPoint,
          PrefetchHooks Function()
        > {
  $$LocationPointsTableTableManager(
    _$AppDatabase db,
    $LocationPointsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$LocationPointsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$LocationPointsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$LocationPointsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> sessionId = const Value.absent(),
                Value<double> lat = const Value.absent(),
                Value<double> lng = const Value.absent(),
                Value<double?> alt = const Value.absent(),
                Value<double?> accuracy = const Value.absent(),
                Value<double?> speed = const Value.absent(),
                Value<double?> bearing = const Value.absent(),
                Value<int> timestampMs = const Value.absent(),
              }) => LocationPointsCompanion(
                id: id,
                sessionId: sessionId,
                lat: lat,
                lng: lng,
                alt: alt,
                accuracy: accuracy,
                speed: speed,
                bearing: bearing,
                timestampMs: timestampMs,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String sessionId,
                required double lat,
                required double lng,
                Value<double?> alt = const Value.absent(),
                Value<double?> accuracy = const Value.absent(),
                Value<double?> speed = const Value.absent(),
                Value<double?> bearing = const Value.absent(),
                required int timestampMs,
              }) => LocationPointsCompanion.insert(
                id: id,
                sessionId: sessionId,
                lat: lat,
                lng: lng,
                alt: alt,
                accuracy: accuracy,
                speed: speed,
                bearing: bearing,
                timestampMs: timestampMs,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$LocationPointsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $LocationPointsTable,
      LocationPoint,
      $$LocationPointsTableFilterComposer,
      $$LocationPointsTableOrderingComposer,
      $$LocationPointsTableAnnotationComposer,
      $$LocationPointsTableCreateCompanionBuilder,
      $$LocationPointsTableUpdateCompanionBuilder,
      (
        LocationPoint,
        BaseReferences<_$AppDatabase, $LocationPointsTable, LocationPoint>,
      ),
      LocationPoint,
      PrefetchHooks Function()
    >;
typedef $$WorkoutSessionsTableCreateCompanionBuilder =
    WorkoutSessionsCompanion Function({
      Value<int> id,
      required String sessionUuid,
      Value<String?> userId,
      required int status,
      required int startTimeMs,
      Value<int?> endTimeMs,
      required double totalDistanceM,
      required int movingMs,
      required bool isVerified,
      required bool isSynced,
      Value<String?> ghostSessionId,
      Value<List<String>> integrityFlags,
      Value<int?> avgBpm,
      Value<int?> maxBpm,
      Value<double?> avgCadenceSpm,
      Value<String> source,
      Value<String?> deviceName,
    });
typedef $$WorkoutSessionsTableUpdateCompanionBuilder =
    WorkoutSessionsCompanion Function({
      Value<int> id,
      Value<String> sessionUuid,
      Value<String?> userId,
      Value<int> status,
      Value<int> startTimeMs,
      Value<int?> endTimeMs,
      Value<double> totalDistanceM,
      Value<int> movingMs,
      Value<bool> isVerified,
      Value<bool> isSynced,
      Value<String?> ghostSessionId,
      Value<List<String>> integrityFlags,
      Value<int?> avgBpm,
      Value<int?> maxBpm,
      Value<double?> avgCadenceSpm,
      Value<String> source,
      Value<String?> deviceName,
    });

class $$WorkoutSessionsTableFilterComposer
    extends Composer<_$AppDatabase, $WorkoutSessionsTable> {
  $$WorkoutSessionsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sessionUuid => $composableBuilder(
    column: $table.sessionUuid,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get userId => $composableBuilder(
    column: $table.userId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get startTimeMs => $composableBuilder(
    column: $table.startTimeMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get endTimeMs => $composableBuilder(
    column: $table.endTimeMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get totalDistanceM => $composableBuilder(
    column: $table.totalDistanceM,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get movingMs => $composableBuilder(
    column: $table.movingMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isVerified => $composableBuilder(
    column: $table.isVerified,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isSynced => $composableBuilder(
    column: $table.isSynced,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get ghostSessionId => $composableBuilder(
    column: $table.ghostSessionId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<List<String>, List<String>, String>
  get integrityFlags => $composableBuilder(
    column: $table.integrityFlags,
    builder: (column) => ColumnWithTypeConverterFilters(column),
  );

  ColumnFilters<int> get avgBpm => $composableBuilder(
    column: $table.avgBpm,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get maxBpm => $composableBuilder(
    column: $table.maxBpm,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get avgCadenceSpm => $composableBuilder(
    column: $table.avgCadenceSpm,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get source => $composableBuilder(
    column: $table.source,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get deviceName => $composableBuilder(
    column: $table.deviceName,
    builder: (column) => ColumnFilters(column),
  );
}

class $$WorkoutSessionsTableOrderingComposer
    extends Composer<_$AppDatabase, $WorkoutSessionsTable> {
  $$WorkoutSessionsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sessionUuid => $composableBuilder(
    column: $table.sessionUuid,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get userId => $composableBuilder(
    column: $table.userId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get startTimeMs => $composableBuilder(
    column: $table.startTimeMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get endTimeMs => $composableBuilder(
    column: $table.endTimeMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get totalDistanceM => $composableBuilder(
    column: $table.totalDistanceM,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get movingMs => $composableBuilder(
    column: $table.movingMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isVerified => $composableBuilder(
    column: $table.isVerified,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isSynced => $composableBuilder(
    column: $table.isSynced,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get ghostSessionId => $composableBuilder(
    column: $table.ghostSessionId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get integrityFlags => $composableBuilder(
    column: $table.integrityFlags,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get avgBpm => $composableBuilder(
    column: $table.avgBpm,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get maxBpm => $composableBuilder(
    column: $table.maxBpm,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get avgCadenceSpm => $composableBuilder(
    column: $table.avgCadenceSpm,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get source => $composableBuilder(
    column: $table.source,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get deviceName => $composableBuilder(
    column: $table.deviceName,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$WorkoutSessionsTableAnnotationComposer
    extends Composer<_$AppDatabase, $WorkoutSessionsTable> {
  $$WorkoutSessionsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get sessionUuid => $composableBuilder(
    column: $table.sessionUuid,
    builder: (column) => column,
  );

  GeneratedColumn<String> get userId =>
      $composableBuilder(column: $table.userId, builder: (column) => column);

  GeneratedColumn<int> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<int> get startTimeMs => $composableBuilder(
    column: $table.startTimeMs,
    builder: (column) => column,
  );

  GeneratedColumn<int> get endTimeMs =>
      $composableBuilder(column: $table.endTimeMs, builder: (column) => column);

  GeneratedColumn<double> get totalDistanceM => $composableBuilder(
    column: $table.totalDistanceM,
    builder: (column) => column,
  );

  GeneratedColumn<int> get movingMs =>
      $composableBuilder(column: $table.movingMs, builder: (column) => column);

  GeneratedColumn<bool> get isVerified => $composableBuilder(
    column: $table.isVerified,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get isSynced =>
      $composableBuilder(column: $table.isSynced, builder: (column) => column);

  GeneratedColumn<String> get ghostSessionId => $composableBuilder(
    column: $table.ghostSessionId,
    builder: (column) => column,
  );

  GeneratedColumnWithTypeConverter<List<String>, String> get integrityFlags =>
      $composableBuilder(
        column: $table.integrityFlags,
        builder: (column) => column,
      );

  GeneratedColumn<int> get avgBpm =>
      $composableBuilder(column: $table.avgBpm, builder: (column) => column);

  GeneratedColumn<int> get maxBpm =>
      $composableBuilder(column: $table.maxBpm, builder: (column) => column);

  GeneratedColumn<double> get avgCadenceSpm => $composableBuilder(
    column: $table.avgCadenceSpm,
    builder: (column) => column,
  );

  GeneratedColumn<String> get source =>
      $composableBuilder(column: $table.source, builder: (column) => column);

  GeneratedColumn<String> get deviceName => $composableBuilder(
    column: $table.deviceName,
    builder: (column) => column,
  );
}

class $$WorkoutSessionsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $WorkoutSessionsTable,
          WorkoutSession,
          $$WorkoutSessionsTableFilterComposer,
          $$WorkoutSessionsTableOrderingComposer,
          $$WorkoutSessionsTableAnnotationComposer,
          $$WorkoutSessionsTableCreateCompanionBuilder,
          $$WorkoutSessionsTableUpdateCompanionBuilder,
          (
            WorkoutSession,
            BaseReferences<
              _$AppDatabase,
              $WorkoutSessionsTable,
              WorkoutSession
            >,
          ),
          WorkoutSession,
          PrefetchHooks Function()
        > {
  $$WorkoutSessionsTableTableManager(
    _$AppDatabase db,
    $WorkoutSessionsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$WorkoutSessionsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$WorkoutSessionsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$WorkoutSessionsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> sessionUuid = const Value.absent(),
                Value<String?> userId = const Value.absent(),
                Value<int> status = const Value.absent(),
                Value<int> startTimeMs = const Value.absent(),
                Value<int?> endTimeMs = const Value.absent(),
                Value<double> totalDistanceM = const Value.absent(),
                Value<int> movingMs = const Value.absent(),
                Value<bool> isVerified = const Value.absent(),
                Value<bool> isSynced = const Value.absent(),
                Value<String?> ghostSessionId = const Value.absent(),
                Value<List<String>> integrityFlags = const Value.absent(),
                Value<int?> avgBpm = const Value.absent(),
                Value<int?> maxBpm = const Value.absent(),
                Value<double?> avgCadenceSpm = const Value.absent(),
                Value<String> source = const Value.absent(),
                Value<String?> deviceName = const Value.absent(),
              }) => WorkoutSessionsCompanion(
                id: id,
                sessionUuid: sessionUuid,
                userId: userId,
                status: status,
                startTimeMs: startTimeMs,
                endTimeMs: endTimeMs,
                totalDistanceM: totalDistanceM,
                movingMs: movingMs,
                isVerified: isVerified,
                isSynced: isSynced,
                ghostSessionId: ghostSessionId,
                integrityFlags: integrityFlags,
                avgBpm: avgBpm,
                maxBpm: maxBpm,
                avgCadenceSpm: avgCadenceSpm,
                source: source,
                deviceName: deviceName,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String sessionUuid,
                Value<String?> userId = const Value.absent(),
                required int status,
                required int startTimeMs,
                Value<int?> endTimeMs = const Value.absent(),
                required double totalDistanceM,
                required int movingMs,
                required bool isVerified,
                required bool isSynced,
                Value<String?> ghostSessionId = const Value.absent(),
                Value<List<String>> integrityFlags = const Value.absent(),
                Value<int?> avgBpm = const Value.absent(),
                Value<int?> maxBpm = const Value.absent(),
                Value<double?> avgCadenceSpm = const Value.absent(),
                Value<String> source = const Value.absent(),
                Value<String?> deviceName = const Value.absent(),
              }) => WorkoutSessionsCompanion.insert(
                id: id,
                sessionUuid: sessionUuid,
                userId: userId,
                status: status,
                startTimeMs: startTimeMs,
                endTimeMs: endTimeMs,
                totalDistanceM: totalDistanceM,
                movingMs: movingMs,
                isVerified: isVerified,
                isSynced: isSynced,
                ghostSessionId: ghostSessionId,
                integrityFlags: integrityFlags,
                avgBpm: avgBpm,
                maxBpm: maxBpm,
                avgCadenceSpm: avgCadenceSpm,
                source: source,
                deviceName: deviceName,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$WorkoutSessionsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $WorkoutSessionsTable,
      WorkoutSession,
      $$WorkoutSessionsTableFilterComposer,
      $$WorkoutSessionsTableOrderingComposer,
      $$WorkoutSessionsTableAnnotationComposer,
      $$WorkoutSessionsTableCreateCompanionBuilder,
      $$WorkoutSessionsTableUpdateCompanionBuilder,
      (
        WorkoutSession,
        BaseReferences<_$AppDatabase, $WorkoutSessionsTable, WorkoutSession>,
      ),
      WorkoutSession,
      PrefetchHooks Function()
    >;
typedef $$ChallengesTableCreateCompanionBuilder =
    ChallengesCompanion Function({
      Value<int> id,
      required String challengeUuid,
      required String creatorUserId,
      required String status,
      required String type,
      Value<String?> title,
      required String metricOrdinal,
      Value<double?> target,
      required int windowMs,
      required String startModeOrdinal,
      Value<int?> fixedStartMs,
      required double minSessionDistanceM,
      required String antiCheatPolicyOrdinal,
      required int entryFeeCoins,
      required int createdAtMs,
      Value<int?> startsAtMs,
      Value<int?> endsAtMs,
      Value<String?> teamAGroupId,
      Value<String?> teamBGroupId,
      Value<String?> teamAGroupName,
      Value<String?> teamBGroupName,
      Value<int?> acceptDeadlineMs,
      Value<List<String>> participantsJson,
    });
typedef $$ChallengesTableUpdateCompanionBuilder =
    ChallengesCompanion Function({
      Value<int> id,
      Value<String> challengeUuid,
      Value<String> creatorUserId,
      Value<String> status,
      Value<String> type,
      Value<String?> title,
      Value<String> metricOrdinal,
      Value<double?> target,
      Value<int> windowMs,
      Value<String> startModeOrdinal,
      Value<int?> fixedStartMs,
      Value<double> minSessionDistanceM,
      Value<String> antiCheatPolicyOrdinal,
      Value<int> entryFeeCoins,
      Value<int> createdAtMs,
      Value<int?> startsAtMs,
      Value<int?> endsAtMs,
      Value<String?> teamAGroupId,
      Value<String?> teamBGroupId,
      Value<String?> teamAGroupName,
      Value<String?> teamBGroupName,
      Value<int?> acceptDeadlineMs,
      Value<List<String>> participantsJson,
    });

class $$ChallengesTableFilterComposer
    extends Composer<_$AppDatabase, $ChallengesTable> {
  $$ChallengesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get challengeUuid => $composableBuilder(
    column: $table.challengeUuid,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get creatorUserId => $composableBuilder(
    column: $table.creatorUserId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get type => $composableBuilder(
    column: $table.type,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get metricOrdinal => $composableBuilder(
    column: $table.metricOrdinal,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get target => $composableBuilder(
    column: $table.target,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get windowMs => $composableBuilder(
    column: $table.windowMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get startModeOrdinal => $composableBuilder(
    column: $table.startModeOrdinal,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get fixedStartMs => $composableBuilder(
    column: $table.fixedStartMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get minSessionDistanceM => $composableBuilder(
    column: $table.minSessionDistanceM,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get antiCheatPolicyOrdinal => $composableBuilder(
    column: $table.antiCheatPolicyOrdinal,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get entryFeeCoins => $composableBuilder(
    column: $table.entryFeeCoins,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get createdAtMs => $composableBuilder(
    column: $table.createdAtMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get startsAtMs => $composableBuilder(
    column: $table.startsAtMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get endsAtMs => $composableBuilder(
    column: $table.endsAtMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get teamAGroupId => $composableBuilder(
    column: $table.teamAGroupId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get teamBGroupId => $composableBuilder(
    column: $table.teamBGroupId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get teamAGroupName => $composableBuilder(
    column: $table.teamAGroupName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get teamBGroupName => $composableBuilder(
    column: $table.teamBGroupName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get acceptDeadlineMs => $composableBuilder(
    column: $table.acceptDeadlineMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<List<String>, List<String>, String>
  get participantsJson => $composableBuilder(
    column: $table.participantsJson,
    builder: (column) => ColumnWithTypeConverterFilters(column),
  );
}

class $$ChallengesTableOrderingComposer
    extends Composer<_$AppDatabase, $ChallengesTable> {
  $$ChallengesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get challengeUuid => $composableBuilder(
    column: $table.challengeUuid,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get creatorUserId => $composableBuilder(
    column: $table.creatorUserId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get type => $composableBuilder(
    column: $table.type,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get metricOrdinal => $composableBuilder(
    column: $table.metricOrdinal,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get target => $composableBuilder(
    column: $table.target,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get windowMs => $composableBuilder(
    column: $table.windowMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get startModeOrdinal => $composableBuilder(
    column: $table.startModeOrdinal,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get fixedStartMs => $composableBuilder(
    column: $table.fixedStartMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get minSessionDistanceM => $composableBuilder(
    column: $table.minSessionDistanceM,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get antiCheatPolicyOrdinal => $composableBuilder(
    column: $table.antiCheatPolicyOrdinal,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get entryFeeCoins => $composableBuilder(
    column: $table.entryFeeCoins,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get createdAtMs => $composableBuilder(
    column: $table.createdAtMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get startsAtMs => $composableBuilder(
    column: $table.startsAtMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get endsAtMs => $composableBuilder(
    column: $table.endsAtMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get teamAGroupId => $composableBuilder(
    column: $table.teamAGroupId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get teamBGroupId => $composableBuilder(
    column: $table.teamBGroupId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get teamAGroupName => $composableBuilder(
    column: $table.teamAGroupName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get teamBGroupName => $composableBuilder(
    column: $table.teamBGroupName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get acceptDeadlineMs => $composableBuilder(
    column: $table.acceptDeadlineMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get participantsJson => $composableBuilder(
    column: $table.participantsJson,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ChallengesTableAnnotationComposer
    extends Composer<_$AppDatabase, $ChallengesTable> {
  $$ChallengesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get challengeUuid => $composableBuilder(
    column: $table.challengeUuid,
    builder: (column) => column,
  );

  GeneratedColumn<String> get creatorUserId => $composableBuilder(
    column: $table.creatorUserId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<String> get type =>
      $composableBuilder(column: $table.type, builder: (column) => column);

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<String> get metricOrdinal => $composableBuilder(
    column: $table.metricOrdinal,
    builder: (column) => column,
  );

  GeneratedColumn<double> get target =>
      $composableBuilder(column: $table.target, builder: (column) => column);

  GeneratedColumn<int> get windowMs =>
      $composableBuilder(column: $table.windowMs, builder: (column) => column);

  GeneratedColumn<String> get startModeOrdinal => $composableBuilder(
    column: $table.startModeOrdinal,
    builder: (column) => column,
  );

  GeneratedColumn<int> get fixedStartMs => $composableBuilder(
    column: $table.fixedStartMs,
    builder: (column) => column,
  );

  GeneratedColumn<double> get minSessionDistanceM => $composableBuilder(
    column: $table.minSessionDistanceM,
    builder: (column) => column,
  );

  GeneratedColumn<String> get antiCheatPolicyOrdinal => $composableBuilder(
    column: $table.antiCheatPolicyOrdinal,
    builder: (column) => column,
  );

  GeneratedColumn<int> get entryFeeCoins => $composableBuilder(
    column: $table.entryFeeCoins,
    builder: (column) => column,
  );

  GeneratedColumn<int> get createdAtMs => $composableBuilder(
    column: $table.createdAtMs,
    builder: (column) => column,
  );

  GeneratedColumn<int> get startsAtMs => $composableBuilder(
    column: $table.startsAtMs,
    builder: (column) => column,
  );

  GeneratedColumn<int> get endsAtMs =>
      $composableBuilder(column: $table.endsAtMs, builder: (column) => column);

  GeneratedColumn<String> get teamAGroupId => $composableBuilder(
    column: $table.teamAGroupId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get teamBGroupId => $composableBuilder(
    column: $table.teamBGroupId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get teamAGroupName => $composableBuilder(
    column: $table.teamAGroupName,
    builder: (column) => column,
  );

  GeneratedColumn<String> get teamBGroupName => $composableBuilder(
    column: $table.teamBGroupName,
    builder: (column) => column,
  );

  GeneratedColumn<int> get acceptDeadlineMs => $composableBuilder(
    column: $table.acceptDeadlineMs,
    builder: (column) => column,
  );

  GeneratedColumnWithTypeConverter<List<String>, String> get participantsJson =>
      $composableBuilder(
        column: $table.participantsJson,
        builder: (column) => column,
      );
}

class $$ChallengesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ChallengesTable,
          Challenge,
          $$ChallengesTableFilterComposer,
          $$ChallengesTableOrderingComposer,
          $$ChallengesTableAnnotationComposer,
          $$ChallengesTableCreateCompanionBuilder,
          $$ChallengesTableUpdateCompanionBuilder,
          (
            Challenge,
            BaseReferences<_$AppDatabase, $ChallengesTable, Challenge>,
          ),
          Challenge,
          PrefetchHooks Function()
        > {
  $$ChallengesTableTableManager(_$AppDatabase db, $ChallengesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ChallengesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ChallengesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ChallengesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> challengeUuid = const Value.absent(),
                Value<String> creatorUserId = const Value.absent(),
                Value<String> status = const Value.absent(),
                Value<String> type = const Value.absent(),
                Value<String?> title = const Value.absent(),
                Value<String> metricOrdinal = const Value.absent(),
                Value<double?> target = const Value.absent(),
                Value<int> windowMs = const Value.absent(),
                Value<String> startModeOrdinal = const Value.absent(),
                Value<int?> fixedStartMs = const Value.absent(),
                Value<double> minSessionDistanceM = const Value.absent(),
                Value<String> antiCheatPolicyOrdinal = const Value.absent(),
                Value<int> entryFeeCoins = const Value.absent(),
                Value<int> createdAtMs = const Value.absent(),
                Value<int?> startsAtMs = const Value.absent(),
                Value<int?> endsAtMs = const Value.absent(),
                Value<String?> teamAGroupId = const Value.absent(),
                Value<String?> teamBGroupId = const Value.absent(),
                Value<String?> teamAGroupName = const Value.absent(),
                Value<String?> teamBGroupName = const Value.absent(),
                Value<int?> acceptDeadlineMs = const Value.absent(),
                Value<List<String>> participantsJson = const Value.absent(),
              }) => ChallengesCompanion(
                id: id,
                challengeUuid: challengeUuid,
                creatorUserId: creatorUserId,
                status: status,
                type: type,
                title: title,
                metricOrdinal: metricOrdinal,
                target: target,
                windowMs: windowMs,
                startModeOrdinal: startModeOrdinal,
                fixedStartMs: fixedStartMs,
                minSessionDistanceM: minSessionDistanceM,
                antiCheatPolicyOrdinal: antiCheatPolicyOrdinal,
                entryFeeCoins: entryFeeCoins,
                createdAtMs: createdAtMs,
                startsAtMs: startsAtMs,
                endsAtMs: endsAtMs,
                teamAGroupId: teamAGroupId,
                teamBGroupId: teamBGroupId,
                teamAGroupName: teamAGroupName,
                teamBGroupName: teamBGroupName,
                acceptDeadlineMs: acceptDeadlineMs,
                participantsJson: participantsJson,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String challengeUuid,
                required String creatorUserId,
                required String status,
                required String type,
                Value<String?> title = const Value.absent(),
                required String metricOrdinal,
                Value<double?> target = const Value.absent(),
                required int windowMs,
                required String startModeOrdinal,
                Value<int?> fixedStartMs = const Value.absent(),
                required double minSessionDistanceM,
                required String antiCheatPolicyOrdinal,
                required int entryFeeCoins,
                required int createdAtMs,
                Value<int?> startsAtMs = const Value.absent(),
                Value<int?> endsAtMs = const Value.absent(),
                Value<String?> teamAGroupId = const Value.absent(),
                Value<String?> teamBGroupId = const Value.absent(),
                Value<String?> teamAGroupName = const Value.absent(),
                Value<String?> teamBGroupName = const Value.absent(),
                Value<int?> acceptDeadlineMs = const Value.absent(),
                Value<List<String>> participantsJson = const Value.absent(),
              }) => ChallengesCompanion.insert(
                id: id,
                challengeUuid: challengeUuid,
                creatorUserId: creatorUserId,
                status: status,
                type: type,
                title: title,
                metricOrdinal: metricOrdinal,
                target: target,
                windowMs: windowMs,
                startModeOrdinal: startModeOrdinal,
                fixedStartMs: fixedStartMs,
                minSessionDistanceM: minSessionDistanceM,
                antiCheatPolicyOrdinal: antiCheatPolicyOrdinal,
                entryFeeCoins: entryFeeCoins,
                createdAtMs: createdAtMs,
                startsAtMs: startsAtMs,
                endsAtMs: endsAtMs,
                teamAGroupId: teamAGroupId,
                teamBGroupId: teamBGroupId,
                teamAGroupName: teamAGroupName,
                teamBGroupName: teamBGroupName,
                acceptDeadlineMs: acceptDeadlineMs,
                participantsJson: participantsJson,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$ChallengesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ChallengesTable,
      Challenge,
      $$ChallengesTableFilterComposer,
      $$ChallengesTableOrderingComposer,
      $$ChallengesTableAnnotationComposer,
      $$ChallengesTableCreateCompanionBuilder,
      $$ChallengesTableUpdateCompanionBuilder,
      (Challenge, BaseReferences<_$AppDatabase, $ChallengesTable, Challenge>),
      Challenge,
      PrefetchHooks Function()
    >;
typedef $$ChallengeResultsTableCreateCompanionBuilder =
    ChallengeResultsCompanion Function({
      Value<int> id,
      required String challengeId,
      required String metricOrdinal,
      required int totalCoinsDistributed,
      required int calculatedAtMs,
      Value<List<String>> resultsJson,
    });
typedef $$ChallengeResultsTableUpdateCompanionBuilder =
    ChallengeResultsCompanion Function({
      Value<int> id,
      Value<String> challengeId,
      Value<String> metricOrdinal,
      Value<int> totalCoinsDistributed,
      Value<int> calculatedAtMs,
      Value<List<String>> resultsJson,
    });

class $$ChallengeResultsTableFilterComposer
    extends Composer<_$AppDatabase, $ChallengeResultsTable> {
  $$ChallengeResultsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get challengeId => $composableBuilder(
    column: $table.challengeId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get metricOrdinal => $composableBuilder(
    column: $table.metricOrdinal,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get totalCoinsDistributed => $composableBuilder(
    column: $table.totalCoinsDistributed,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get calculatedAtMs => $composableBuilder(
    column: $table.calculatedAtMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<List<String>, List<String>, String>
  get resultsJson => $composableBuilder(
    column: $table.resultsJson,
    builder: (column) => ColumnWithTypeConverterFilters(column),
  );
}

class $$ChallengeResultsTableOrderingComposer
    extends Composer<_$AppDatabase, $ChallengeResultsTable> {
  $$ChallengeResultsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get challengeId => $composableBuilder(
    column: $table.challengeId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get metricOrdinal => $composableBuilder(
    column: $table.metricOrdinal,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get totalCoinsDistributed => $composableBuilder(
    column: $table.totalCoinsDistributed,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get calculatedAtMs => $composableBuilder(
    column: $table.calculatedAtMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get resultsJson => $composableBuilder(
    column: $table.resultsJson,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ChallengeResultsTableAnnotationComposer
    extends Composer<_$AppDatabase, $ChallengeResultsTable> {
  $$ChallengeResultsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get challengeId => $composableBuilder(
    column: $table.challengeId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get metricOrdinal => $composableBuilder(
    column: $table.metricOrdinal,
    builder: (column) => column,
  );

  GeneratedColumn<int> get totalCoinsDistributed => $composableBuilder(
    column: $table.totalCoinsDistributed,
    builder: (column) => column,
  );

  GeneratedColumn<int> get calculatedAtMs => $composableBuilder(
    column: $table.calculatedAtMs,
    builder: (column) => column,
  );

  GeneratedColumnWithTypeConverter<List<String>, String> get resultsJson =>
      $composableBuilder(
        column: $table.resultsJson,
        builder: (column) => column,
      );
}

class $$ChallengeResultsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ChallengeResultsTable,
          ChallengeResult,
          $$ChallengeResultsTableFilterComposer,
          $$ChallengeResultsTableOrderingComposer,
          $$ChallengeResultsTableAnnotationComposer,
          $$ChallengeResultsTableCreateCompanionBuilder,
          $$ChallengeResultsTableUpdateCompanionBuilder,
          (
            ChallengeResult,
            BaseReferences<
              _$AppDatabase,
              $ChallengeResultsTable,
              ChallengeResult
            >,
          ),
          ChallengeResult,
          PrefetchHooks Function()
        > {
  $$ChallengeResultsTableTableManager(
    _$AppDatabase db,
    $ChallengeResultsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ChallengeResultsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ChallengeResultsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ChallengeResultsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> challengeId = const Value.absent(),
                Value<String> metricOrdinal = const Value.absent(),
                Value<int> totalCoinsDistributed = const Value.absent(),
                Value<int> calculatedAtMs = const Value.absent(),
                Value<List<String>> resultsJson = const Value.absent(),
              }) => ChallengeResultsCompanion(
                id: id,
                challengeId: challengeId,
                metricOrdinal: metricOrdinal,
                totalCoinsDistributed: totalCoinsDistributed,
                calculatedAtMs: calculatedAtMs,
                resultsJson: resultsJson,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String challengeId,
                required String metricOrdinal,
                required int totalCoinsDistributed,
                required int calculatedAtMs,
                Value<List<String>> resultsJson = const Value.absent(),
              }) => ChallengeResultsCompanion.insert(
                id: id,
                challengeId: challengeId,
                metricOrdinal: metricOrdinal,
                totalCoinsDistributed: totalCoinsDistributed,
                calculatedAtMs: calculatedAtMs,
                resultsJson: resultsJson,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$ChallengeResultsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ChallengeResultsTable,
      ChallengeResult,
      $$ChallengeResultsTableFilterComposer,
      $$ChallengeResultsTableOrderingComposer,
      $$ChallengeResultsTableAnnotationComposer,
      $$ChallengeResultsTableCreateCompanionBuilder,
      $$ChallengeResultsTableUpdateCompanionBuilder,
      (
        ChallengeResult,
        BaseReferences<_$AppDatabase, $ChallengeResultsTable, ChallengeResult>,
      ),
      ChallengeResult,
      PrefetchHooks Function()
    >;
typedef $$WalletsTableCreateCompanionBuilder =
    WalletsCompanion Function({
      Value<int> id,
      required String userId,
      required int balanceCoins,
      Value<int> pendingCoins,
      required int lifetimeEarnedCoins,
      required int lifetimeSpentCoins,
      Value<int?> lastReconciledAtMs,
    });
typedef $$WalletsTableUpdateCompanionBuilder =
    WalletsCompanion Function({
      Value<int> id,
      Value<String> userId,
      Value<int> balanceCoins,
      Value<int> pendingCoins,
      Value<int> lifetimeEarnedCoins,
      Value<int> lifetimeSpentCoins,
      Value<int?> lastReconciledAtMs,
    });

class $$WalletsTableFilterComposer
    extends Composer<_$AppDatabase, $WalletsTable> {
  $$WalletsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get userId => $composableBuilder(
    column: $table.userId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get balanceCoins => $composableBuilder(
    column: $table.balanceCoins,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get pendingCoins => $composableBuilder(
    column: $table.pendingCoins,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get lifetimeEarnedCoins => $composableBuilder(
    column: $table.lifetimeEarnedCoins,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get lifetimeSpentCoins => $composableBuilder(
    column: $table.lifetimeSpentCoins,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get lastReconciledAtMs => $composableBuilder(
    column: $table.lastReconciledAtMs,
    builder: (column) => ColumnFilters(column),
  );
}

class $$WalletsTableOrderingComposer
    extends Composer<_$AppDatabase, $WalletsTable> {
  $$WalletsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get userId => $composableBuilder(
    column: $table.userId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get balanceCoins => $composableBuilder(
    column: $table.balanceCoins,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get pendingCoins => $composableBuilder(
    column: $table.pendingCoins,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get lifetimeEarnedCoins => $composableBuilder(
    column: $table.lifetimeEarnedCoins,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get lifetimeSpentCoins => $composableBuilder(
    column: $table.lifetimeSpentCoins,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get lastReconciledAtMs => $composableBuilder(
    column: $table.lastReconciledAtMs,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$WalletsTableAnnotationComposer
    extends Composer<_$AppDatabase, $WalletsTable> {
  $$WalletsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get userId =>
      $composableBuilder(column: $table.userId, builder: (column) => column);

  GeneratedColumn<int> get balanceCoins => $composableBuilder(
    column: $table.balanceCoins,
    builder: (column) => column,
  );

  GeneratedColumn<int> get pendingCoins => $composableBuilder(
    column: $table.pendingCoins,
    builder: (column) => column,
  );

  GeneratedColumn<int> get lifetimeEarnedCoins => $composableBuilder(
    column: $table.lifetimeEarnedCoins,
    builder: (column) => column,
  );

  GeneratedColumn<int> get lifetimeSpentCoins => $composableBuilder(
    column: $table.lifetimeSpentCoins,
    builder: (column) => column,
  );

  GeneratedColumn<int> get lastReconciledAtMs => $composableBuilder(
    column: $table.lastReconciledAtMs,
    builder: (column) => column,
  );
}

class $$WalletsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $WalletsTable,
          Wallet,
          $$WalletsTableFilterComposer,
          $$WalletsTableOrderingComposer,
          $$WalletsTableAnnotationComposer,
          $$WalletsTableCreateCompanionBuilder,
          $$WalletsTableUpdateCompanionBuilder,
          (Wallet, BaseReferences<_$AppDatabase, $WalletsTable, Wallet>),
          Wallet,
          PrefetchHooks Function()
        > {
  $$WalletsTableTableManager(_$AppDatabase db, $WalletsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$WalletsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$WalletsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$WalletsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> userId = const Value.absent(),
                Value<int> balanceCoins = const Value.absent(),
                Value<int> pendingCoins = const Value.absent(),
                Value<int> lifetimeEarnedCoins = const Value.absent(),
                Value<int> lifetimeSpentCoins = const Value.absent(),
                Value<int?> lastReconciledAtMs = const Value.absent(),
              }) => WalletsCompanion(
                id: id,
                userId: userId,
                balanceCoins: balanceCoins,
                pendingCoins: pendingCoins,
                lifetimeEarnedCoins: lifetimeEarnedCoins,
                lifetimeSpentCoins: lifetimeSpentCoins,
                lastReconciledAtMs: lastReconciledAtMs,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String userId,
                required int balanceCoins,
                Value<int> pendingCoins = const Value.absent(),
                required int lifetimeEarnedCoins,
                required int lifetimeSpentCoins,
                Value<int?> lastReconciledAtMs = const Value.absent(),
              }) => WalletsCompanion.insert(
                id: id,
                userId: userId,
                balanceCoins: balanceCoins,
                pendingCoins: pendingCoins,
                lifetimeEarnedCoins: lifetimeEarnedCoins,
                lifetimeSpentCoins: lifetimeSpentCoins,
                lastReconciledAtMs: lastReconciledAtMs,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$WalletsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $WalletsTable,
      Wallet,
      $$WalletsTableFilterComposer,
      $$WalletsTableOrderingComposer,
      $$WalletsTableAnnotationComposer,
      $$WalletsTableCreateCompanionBuilder,
      $$WalletsTableUpdateCompanionBuilder,
      (Wallet, BaseReferences<_$AppDatabase, $WalletsTable, Wallet>),
      Wallet,
      PrefetchHooks Function()
    >;
typedef $$LedgerEntriesTableCreateCompanionBuilder =
    LedgerEntriesCompanion Function({
      Value<int> id,
      required String entryUuid,
      required String userId,
      required int deltaCoins,
      required String reasonOrdinal,
      Value<String?> refId,
      Value<String?> issuerGroupId,
      required int createdAtMs,
    });
typedef $$LedgerEntriesTableUpdateCompanionBuilder =
    LedgerEntriesCompanion Function({
      Value<int> id,
      Value<String> entryUuid,
      Value<String> userId,
      Value<int> deltaCoins,
      Value<String> reasonOrdinal,
      Value<String?> refId,
      Value<String?> issuerGroupId,
      Value<int> createdAtMs,
    });

class $$LedgerEntriesTableFilterComposer
    extends Composer<_$AppDatabase, $LedgerEntriesTable> {
  $$LedgerEntriesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get entryUuid => $composableBuilder(
    column: $table.entryUuid,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get userId => $composableBuilder(
    column: $table.userId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get deltaCoins => $composableBuilder(
    column: $table.deltaCoins,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get reasonOrdinal => $composableBuilder(
    column: $table.reasonOrdinal,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get refId => $composableBuilder(
    column: $table.refId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get issuerGroupId => $composableBuilder(
    column: $table.issuerGroupId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get createdAtMs => $composableBuilder(
    column: $table.createdAtMs,
    builder: (column) => ColumnFilters(column),
  );
}

class $$LedgerEntriesTableOrderingComposer
    extends Composer<_$AppDatabase, $LedgerEntriesTable> {
  $$LedgerEntriesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get entryUuid => $composableBuilder(
    column: $table.entryUuid,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get userId => $composableBuilder(
    column: $table.userId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get deltaCoins => $composableBuilder(
    column: $table.deltaCoins,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get reasonOrdinal => $composableBuilder(
    column: $table.reasonOrdinal,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get refId => $composableBuilder(
    column: $table.refId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get issuerGroupId => $composableBuilder(
    column: $table.issuerGroupId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get createdAtMs => $composableBuilder(
    column: $table.createdAtMs,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$LedgerEntriesTableAnnotationComposer
    extends Composer<_$AppDatabase, $LedgerEntriesTable> {
  $$LedgerEntriesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get entryUuid =>
      $composableBuilder(column: $table.entryUuid, builder: (column) => column);

  GeneratedColumn<String> get userId =>
      $composableBuilder(column: $table.userId, builder: (column) => column);

  GeneratedColumn<int> get deltaCoins => $composableBuilder(
    column: $table.deltaCoins,
    builder: (column) => column,
  );

  GeneratedColumn<String> get reasonOrdinal => $composableBuilder(
    column: $table.reasonOrdinal,
    builder: (column) => column,
  );

  GeneratedColumn<String> get refId =>
      $composableBuilder(column: $table.refId, builder: (column) => column);

  GeneratedColumn<String> get issuerGroupId => $composableBuilder(
    column: $table.issuerGroupId,
    builder: (column) => column,
  );

  GeneratedColumn<int> get createdAtMs => $composableBuilder(
    column: $table.createdAtMs,
    builder: (column) => column,
  );
}

class $$LedgerEntriesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $LedgerEntriesTable,
          LedgerEntry,
          $$LedgerEntriesTableFilterComposer,
          $$LedgerEntriesTableOrderingComposer,
          $$LedgerEntriesTableAnnotationComposer,
          $$LedgerEntriesTableCreateCompanionBuilder,
          $$LedgerEntriesTableUpdateCompanionBuilder,
          (
            LedgerEntry,
            BaseReferences<_$AppDatabase, $LedgerEntriesTable, LedgerEntry>,
          ),
          LedgerEntry,
          PrefetchHooks Function()
        > {
  $$LedgerEntriesTableTableManager(_$AppDatabase db, $LedgerEntriesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$LedgerEntriesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$LedgerEntriesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$LedgerEntriesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> entryUuid = const Value.absent(),
                Value<String> userId = const Value.absent(),
                Value<int> deltaCoins = const Value.absent(),
                Value<String> reasonOrdinal = const Value.absent(),
                Value<String?> refId = const Value.absent(),
                Value<String?> issuerGroupId = const Value.absent(),
                Value<int> createdAtMs = const Value.absent(),
              }) => LedgerEntriesCompanion(
                id: id,
                entryUuid: entryUuid,
                userId: userId,
                deltaCoins: deltaCoins,
                reasonOrdinal: reasonOrdinal,
                refId: refId,
                issuerGroupId: issuerGroupId,
                createdAtMs: createdAtMs,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String entryUuid,
                required String userId,
                required int deltaCoins,
                required String reasonOrdinal,
                Value<String?> refId = const Value.absent(),
                Value<String?> issuerGroupId = const Value.absent(),
                required int createdAtMs,
              }) => LedgerEntriesCompanion.insert(
                id: id,
                entryUuid: entryUuid,
                userId: userId,
                deltaCoins: deltaCoins,
                reasonOrdinal: reasonOrdinal,
                refId: refId,
                issuerGroupId: issuerGroupId,
                createdAtMs: createdAtMs,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$LedgerEntriesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $LedgerEntriesTable,
      LedgerEntry,
      $$LedgerEntriesTableFilterComposer,
      $$LedgerEntriesTableOrderingComposer,
      $$LedgerEntriesTableAnnotationComposer,
      $$LedgerEntriesTableCreateCompanionBuilder,
      $$LedgerEntriesTableUpdateCompanionBuilder,
      (
        LedgerEntry,
        BaseReferences<_$AppDatabase, $LedgerEntriesTable, LedgerEntry>,
      ),
      LedgerEntry,
      PrefetchHooks Function()
    >;
typedef $$ProfileProgressesTableCreateCompanionBuilder =
    ProfileProgressesCompanion Function({
      Value<int> id,
      required String userId,
      required int totalXp,
      required int seasonXp,
      Value<String?> currentSeasonId,
      required int dailyStreakCount,
      required int streakBest,
      Value<int?> lastStreakDayMs,
      required bool hasFreezeAvailable,
      required int weeklySessionCount,
      required int monthlySessionCount,
      required int lifetimeSessionCount,
      required double lifetimeDistanceM,
      required int lifetimeMovingMs,
    });
typedef $$ProfileProgressesTableUpdateCompanionBuilder =
    ProfileProgressesCompanion Function({
      Value<int> id,
      Value<String> userId,
      Value<int> totalXp,
      Value<int> seasonXp,
      Value<String?> currentSeasonId,
      Value<int> dailyStreakCount,
      Value<int> streakBest,
      Value<int?> lastStreakDayMs,
      Value<bool> hasFreezeAvailable,
      Value<int> weeklySessionCount,
      Value<int> monthlySessionCount,
      Value<int> lifetimeSessionCount,
      Value<double> lifetimeDistanceM,
      Value<int> lifetimeMovingMs,
    });

class $$ProfileProgressesTableFilterComposer
    extends Composer<_$AppDatabase, $ProfileProgressesTable> {
  $$ProfileProgressesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get userId => $composableBuilder(
    column: $table.userId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get totalXp => $composableBuilder(
    column: $table.totalXp,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get seasonXp => $composableBuilder(
    column: $table.seasonXp,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get currentSeasonId => $composableBuilder(
    column: $table.currentSeasonId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get dailyStreakCount => $composableBuilder(
    column: $table.dailyStreakCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get streakBest => $composableBuilder(
    column: $table.streakBest,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get lastStreakDayMs => $composableBuilder(
    column: $table.lastStreakDayMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get hasFreezeAvailable => $composableBuilder(
    column: $table.hasFreezeAvailable,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get weeklySessionCount => $composableBuilder(
    column: $table.weeklySessionCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get monthlySessionCount => $composableBuilder(
    column: $table.monthlySessionCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get lifetimeSessionCount => $composableBuilder(
    column: $table.lifetimeSessionCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get lifetimeDistanceM => $composableBuilder(
    column: $table.lifetimeDistanceM,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get lifetimeMovingMs => $composableBuilder(
    column: $table.lifetimeMovingMs,
    builder: (column) => ColumnFilters(column),
  );
}

class $$ProfileProgressesTableOrderingComposer
    extends Composer<_$AppDatabase, $ProfileProgressesTable> {
  $$ProfileProgressesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get userId => $composableBuilder(
    column: $table.userId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get totalXp => $composableBuilder(
    column: $table.totalXp,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get seasonXp => $composableBuilder(
    column: $table.seasonXp,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get currentSeasonId => $composableBuilder(
    column: $table.currentSeasonId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get dailyStreakCount => $composableBuilder(
    column: $table.dailyStreakCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get streakBest => $composableBuilder(
    column: $table.streakBest,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get lastStreakDayMs => $composableBuilder(
    column: $table.lastStreakDayMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get hasFreezeAvailable => $composableBuilder(
    column: $table.hasFreezeAvailable,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get weeklySessionCount => $composableBuilder(
    column: $table.weeklySessionCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get monthlySessionCount => $composableBuilder(
    column: $table.monthlySessionCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get lifetimeSessionCount => $composableBuilder(
    column: $table.lifetimeSessionCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get lifetimeDistanceM => $composableBuilder(
    column: $table.lifetimeDistanceM,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get lifetimeMovingMs => $composableBuilder(
    column: $table.lifetimeMovingMs,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ProfileProgressesTableAnnotationComposer
    extends Composer<_$AppDatabase, $ProfileProgressesTable> {
  $$ProfileProgressesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get userId =>
      $composableBuilder(column: $table.userId, builder: (column) => column);

  GeneratedColumn<int> get totalXp =>
      $composableBuilder(column: $table.totalXp, builder: (column) => column);

  GeneratedColumn<int> get seasonXp =>
      $composableBuilder(column: $table.seasonXp, builder: (column) => column);

  GeneratedColumn<String> get currentSeasonId => $composableBuilder(
    column: $table.currentSeasonId,
    builder: (column) => column,
  );

  GeneratedColumn<int> get dailyStreakCount => $composableBuilder(
    column: $table.dailyStreakCount,
    builder: (column) => column,
  );

  GeneratedColumn<int> get streakBest => $composableBuilder(
    column: $table.streakBest,
    builder: (column) => column,
  );

  GeneratedColumn<int> get lastStreakDayMs => $composableBuilder(
    column: $table.lastStreakDayMs,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get hasFreezeAvailable => $composableBuilder(
    column: $table.hasFreezeAvailable,
    builder: (column) => column,
  );

  GeneratedColumn<int> get weeklySessionCount => $composableBuilder(
    column: $table.weeklySessionCount,
    builder: (column) => column,
  );

  GeneratedColumn<int> get monthlySessionCount => $composableBuilder(
    column: $table.monthlySessionCount,
    builder: (column) => column,
  );

  GeneratedColumn<int> get lifetimeSessionCount => $composableBuilder(
    column: $table.lifetimeSessionCount,
    builder: (column) => column,
  );

  GeneratedColumn<double> get lifetimeDistanceM => $composableBuilder(
    column: $table.lifetimeDistanceM,
    builder: (column) => column,
  );

  GeneratedColumn<int> get lifetimeMovingMs => $composableBuilder(
    column: $table.lifetimeMovingMs,
    builder: (column) => column,
  );
}

class $$ProfileProgressesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ProfileProgressesTable,
          ProfileProgress,
          $$ProfileProgressesTableFilterComposer,
          $$ProfileProgressesTableOrderingComposer,
          $$ProfileProgressesTableAnnotationComposer,
          $$ProfileProgressesTableCreateCompanionBuilder,
          $$ProfileProgressesTableUpdateCompanionBuilder,
          (
            ProfileProgress,
            BaseReferences<
              _$AppDatabase,
              $ProfileProgressesTable,
              ProfileProgress
            >,
          ),
          ProfileProgress,
          PrefetchHooks Function()
        > {
  $$ProfileProgressesTableTableManager(
    _$AppDatabase db,
    $ProfileProgressesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ProfileProgressesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ProfileProgressesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ProfileProgressesTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> userId = const Value.absent(),
                Value<int> totalXp = const Value.absent(),
                Value<int> seasonXp = const Value.absent(),
                Value<String?> currentSeasonId = const Value.absent(),
                Value<int> dailyStreakCount = const Value.absent(),
                Value<int> streakBest = const Value.absent(),
                Value<int?> lastStreakDayMs = const Value.absent(),
                Value<bool> hasFreezeAvailable = const Value.absent(),
                Value<int> weeklySessionCount = const Value.absent(),
                Value<int> monthlySessionCount = const Value.absent(),
                Value<int> lifetimeSessionCount = const Value.absent(),
                Value<double> lifetimeDistanceM = const Value.absent(),
                Value<int> lifetimeMovingMs = const Value.absent(),
              }) => ProfileProgressesCompanion(
                id: id,
                userId: userId,
                totalXp: totalXp,
                seasonXp: seasonXp,
                currentSeasonId: currentSeasonId,
                dailyStreakCount: dailyStreakCount,
                streakBest: streakBest,
                lastStreakDayMs: lastStreakDayMs,
                hasFreezeAvailable: hasFreezeAvailable,
                weeklySessionCount: weeklySessionCount,
                monthlySessionCount: monthlySessionCount,
                lifetimeSessionCount: lifetimeSessionCount,
                lifetimeDistanceM: lifetimeDistanceM,
                lifetimeMovingMs: lifetimeMovingMs,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String userId,
                required int totalXp,
                required int seasonXp,
                Value<String?> currentSeasonId = const Value.absent(),
                required int dailyStreakCount,
                required int streakBest,
                Value<int?> lastStreakDayMs = const Value.absent(),
                required bool hasFreezeAvailable,
                required int weeklySessionCount,
                required int monthlySessionCount,
                required int lifetimeSessionCount,
                required double lifetimeDistanceM,
                required int lifetimeMovingMs,
              }) => ProfileProgressesCompanion.insert(
                id: id,
                userId: userId,
                totalXp: totalXp,
                seasonXp: seasonXp,
                currentSeasonId: currentSeasonId,
                dailyStreakCount: dailyStreakCount,
                streakBest: streakBest,
                lastStreakDayMs: lastStreakDayMs,
                hasFreezeAvailable: hasFreezeAvailable,
                weeklySessionCount: weeklySessionCount,
                monthlySessionCount: monthlySessionCount,
                lifetimeSessionCount: lifetimeSessionCount,
                lifetimeDistanceM: lifetimeDistanceM,
                lifetimeMovingMs: lifetimeMovingMs,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$ProfileProgressesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ProfileProgressesTable,
      ProfileProgress,
      $$ProfileProgressesTableFilterComposer,
      $$ProfileProgressesTableOrderingComposer,
      $$ProfileProgressesTableAnnotationComposer,
      $$ProfileProgressesTableCreateCompanionBuilder,
      $$ProfileProgressesTableUpdateCompanionBuilder,
      (
        ProfileProgress,
        BaseReferences<_$AppDatabase, $ProfileProgressesTable, ProfileProgress>,
      ),
      ProfileProgress,
      PrefetchHooks Function()
    >;
typedef $$XpTransactionsTableCreateCompanionBuilder =
    XpTransactionsCompanion Function({
      Value<int> id,
      required String txUuid,
      required String userId,
      required int xp,
      required String sourceOrdinal,
      Value<String?> refId,
      required int createdAtMs,
    });
typedef $$XpTransactionsTableUpdateCompanionBuilder =
    XpTransactionsCompanion Function({
      Value<int> id,
      Value<String> txUuid,
      Value<String> userId,
      Value<int> xp,
      Value<String> sourceOrdinal,
      Value<String?> refId,
      Value<int> createdAtMs,
    });

class $$XpTransactionsTableFilterComposer
    extends Composer<_$AppDatabase, $XpTransactionsTable> {
  $$XpTransactionsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get txUuid => $composableBuilder(
    column: $table.txUuid,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get userId => $composableBuilder(
    column: $table.userId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get xp => $composableBuilder(
    column: $table.xp,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sourceOrdinal => $composableBuilder(
    column: $table.sourceOrdinal,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get refId => $composableBuilder(
    column: $table.refId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get createdAtMs => $composableBuilder(
    column: $table.createdAtMs,
    builder: (column) => ColumnFilters(column),
  );
}

class $$XpTransactionsTableOrderingComposer
    extends Composer<_$AppDatabase, $XpTransactionsTable> {
  $$XpTransactionsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get txUuid => $composableBuilder(
    column: $table.txUuid,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get userId => $composableBuilder(
    column: $table.userId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get xp => $composableBuilder(
    column: $table.xp,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sourceOrdinal => $composableBuilder(
    column: $table.sourceOrdinal,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get refId => $composableBuilder(
    column: $table.refId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get createdAtMs => $composableBuilder(
    column: $table.createdAtMs,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$XpTransactionsTableAnnotationComposer
    extends Composer<_$AppDatabase, $XpTransactionsTable> {
  $$XpTransactionsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get txUuid =>
      $composableBuilder(column: $table.txUuid, builder: (column) => column);

  GeneratedColumn<String> get userId =>
      $composableBuilder(column: $table.userId, builder: (column) => column);

  GeneratedColumn<int> get xp =>
      $composableBuilder(column: $table.xp, builder: (column) => column);

  GeneratedColumn<String> get sourceOrdinal => $composableBuilder(
    column: $table.sourceOrdinal,
    builder: (column) => column,
  );

  GeneratedColumn<String> get refId =>
      $composableBuilder(column: $table.refId, builder: (column) => column);

  GeneratedColumn<int> get createdAtMs => $composableBuilder(
    column: $table.createdAtMs,
    builder: (column) => column,
  );
}

class $$XpTransactionsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $XpTransactionsTable,
          XpTransaction,
          $$XpTransactionsTableFilterComposer,
          $$XpTransactionsTableOrderingComposer,
          $$XpTransactionsTableAnnotationComposer,
          $$XpTransactionsTableCreateCompanionBuilder,
          $$XpTransactionsTableUpdateCompanionBuilder,
          (
            XpTransaction,
            BaseReferences<_$AppDatabase, $XpTransactionsTable, XpTransaction>,
          ),
          XpTransaction,
          PrefetchHooks Function()
        > {
  $$XpTransactionsTableTableManager(
    _$AppDatabase db,
    $XpTransactionsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$XpTransactionsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$XpTransactionsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$XpTransactionsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> txUuid = const Value.absent(),
                Value<String> userId = const Value.absent(),
                Value<int> xp = const Value.absent(),
                Value<String> sourceOrdinal = const Value.absent(),
                Value<String?> refId = const Value.absent(),
                Value<int> createdAtMs = const Value.absent(),
              }) => XpTransactionsCompanion(
                id: id,
                txUuid: txUuid,
                userId: userId,
                xp: xp,
                sourceOrdinal: sourceOrdinal,
                refId: refId,
                createdAtMs: createdAtMs,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String txUuid,
                required String userId,
                required int xp,
                required String sourceOrdinal,
                Value<String?> refId = const Value.absent(),
                required int createdAtMs,
              }) => XpTransactionsCompanion.insert(
                id: id,
                txUuid: txUuid,
                userId: userId,
                xp: xp,
                sourceOrdinal: sourceOrdinal,
                refId: refId,
                createdAtMs: createdAtMs,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$XpTransactionsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $XpTransactionsTable,
      XpTransaction,
      $$XpTransactionsTableFilterComposer,
      $$XpTransactionsTableOrderingComposer,
      $$XpTransactionsTableAnnotationComposer,
      $$XpTransactionsTableCreateCompanionBuilder,
      $$XpTransactionsTableUpdateCompanionBuilder,
      (
        XpTransaction,
        BaseReferences<_$AppDatabase, $XpTransactionsTable, XpTransaction>,
      ),
      XpTransaction,
      PrefetchHooks Function()
    >;
typedef $$BadgeAwardsTableCreateCompanionBuilder =
    BadgeAwardsCompanion Function({
      Value<int> id,
      required String awardUuid,
      required String userId,
      required String badgeId,
      Value<String?> triggerSessionId,
      required int unlockedAtMs,
      required int xpAwarded,
      required int coinsAwarded,
    });
typedef $$BadgeAwardsTableUpdateCompanionBuilder =
    BadgeAwardsCompanion Function({
      Value<int> id,
      Value<String> awardUuid,
      Value<String> userId,
      Value<String> badgeId,
      Value<String?> triggerSessionId,
      Value<int> unlockedAtMs,
      Value<int> xpAwarded,
      Value<int> coinsAwarded,
    });

class $$BadgeAwardsTableFilterComposer
    extends Composer<_$AppDatabase, $BadgeAwardsTable> {
  $$BadgeAwardsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get awardUuid => $composableBuilder(
    column: $table.awardUuid,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get userId => $composableBuilder(
    column: $table.userId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get badgeId => $composableBuilder(
    column: $table.badgeId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get triggerSessionId => $composableBuilder(
    column: $table.triggerSessionId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get unlockedAtMs => $composableBuilder(
    column: $table.unlockedAtMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get xpAwarded => $composableBuilder(
    column: $table.xpAwarded,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get coinsAwarded => $composableBuilder(
    column: $table.coinsAwarded,
    builder: (column) => ColumnFilters(column),
  );
}

class $$BadgeAwardsTableOrderingComposer
    extends Composer<_$AppDatabase, $BadgeAwardsTable> {
  $$BadgeAwardsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get awardUuid => $composableBuilder(
    column: $table.awardUuid,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get userId => $composableBuilder(
    column: $table.userId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get badgeId => $composableBuilder(
    column: $table.badgeId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get triggerSessionId => $composableBuilder(
    column: $table.triggerSessionId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get unlockedAtMs => $composableBuilder(
    column: $table.unlockedAtMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get xpAwarded => $composableBuilder(
    column: $table.xpAwarded,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get coinsAwarded => $composableBuilder(
    column: $table.coinsAwarded,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$BadgeAwardsTableAnnotationComposer
    extends Composer<_$AppDatabase, $BadgeAwardsTable> {
  $$BadgeAwardsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get awardUuid =>
      $composableBuilder(column: $table.awardUuid, builder: (column) => column);

  GeneratedColumn<String> get userId =>
      $composableBuilder(column: $table.userId, builder: (column) => column);

  GeneratedColumn<String> get badgeId =>
      $composableBuilder(column: $table.badgeId, builder: (column) => column);

  GeneratedColumn<String> get triggerSessionId => $composableBuilder(
    column: $table.triggerSessionId,
    builder: (column) => column,
  );

  GeneratedColumn<int> get unlockedAtMs => $composableBuilder(
    column: $table.unlockedAtMs,
    builder: (column) => column,
  );

  GeneratedColumn<int> get xpAwarded =>
      $composableBuilder(column: $table.xpAwarded, builder: (column) => column);

  GeneratedColumn<int> get coinsAwarded => $composableBuilder(
    column: $table.coinsAwarded,
    builder: (column) => column,
  );
}

class $$BadgeAwardsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $BadgeAwardsTable,
          BadgeAward,
          $$BadgeAwardsTableFilterComposer,
          $$BadgeAwardsTableOrderingComposer,
          $$BadgeAwardsTableAnnotationComposer,
          $$BadgeAwardsTableCreateCompanionBuilder,
          $$BadgeAwardsTableUpdateCompanionBuilder,
          (
            BadgeAward,
            BaseReferences<_$AppDatabase, $BadgeAwardsTable, BadgeAward>,
          ),
          BadgeAward,
          PrefetchHooks Function()
        > {
  $$BadgeAwardsTableTableManager(_$AppDatabase db, $BadgeAwardsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$BadgeAwardsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$BadgeAwardsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$BadgeAwardsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> awardUuid = const Value.absent(),
                Value<String> userId = const Value.absent(),
                Value<String> badgeId = const Value.absent(),
                Value<String?> triggerSessionId = const Value.absent(),
                Value<int> unlockedAtMs = const Value.absent(),
                Value<int> xpAwarded = const Value.absent(),
                Value<int> coinsAwarded = const Value.absent(),
              }) => BadgeAwardsCompanion(
                id: id,
                awardUuid: awardUuid,
                userId: userId,
                badgeId: badgeId,
                triggerSessionId: triggerSessionId,
                unlockedAtMs: unlockedAtMs,
                xpAwarded: xpAwarded,
                coinsAwarded: coinsAwarded,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String awardUuid,
                required String userId,
                required String badgeId,
                Value<String?> triggerSessionId = const Value.absent(),
                required int unlockedAtMs,
                required int xpAwarded,
                required int coinsAwarded,
              }) => BadgeAwardsCompanion.insert(
                id: id,
                awardUuid: awardUuid,
                userId: userId,
                badgeId: badgeId,
                triggerSessionId: triggerSessionId,
                unlockedAtMs: unlockedAtMs,
                xpAwarded: xpAwarded,
                coinsAwarded: coinsAwarded,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$BadgeAwardsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $BadgeAwardsTable,
      BadgeAward,
      $$BadgeAwardsTableFilterComposer,
      $$BadgeAwardsTableOrderingComposer,
      $$BadgeAwardsTableAnnotationComposer,
      $$BadgeAwardsTableCreateCompanionBuilder,
      $$BadgeAwardsTableUpdateCompanionBuilder,
      (
        BadgeAward,
        BaseReferences<_$AppDatabase, $BadgeAwardsTable, BadgeAward>,
      ),
      BadgeAward,
      PrefetchHooks Function()
    >;
typedef $$MissionProgressesTableCreateCompanionBuilder =
    MissionProgressesCompanion Function({
      Value<int> id,
      required String progressUuid,
      required String userId,
      required String missionId,
      required String statusOrdinal,
      required double currentValue,
      required double targetValue,
      required int assignedAtMs,
      Value<int?> completedAtMs,
      required int completionCount,
      required String contributingSessionIdsJson,
    });
typedef $$MissionProgressesTableUpdateCompanionBuilder =
    MissionProgressesCompanion Function({
      Value<int> id,
      Value<String> progressUuid,
      Value<String> userId,
      Value<String> missionId,
      Value<String> statusOrdinal,
      Value<double> currentValue,
      Value<double> targetValue,
      Value<int> assignedAtMs,
      Value<int?> completedAtMs,
      Value<int> completionCount,
      Value<String> contributingSessionIdsJson,
    });

class $$MissionProgressesTableFilterComposer
    extends Composer<_$AppDatabase, $MissionProgressesTable> {
  $$MissionProgressesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get progressUuid => $composableBuilder(
    column: $table.progressUuid,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get userId => $composableBuilder(
    column: $table.userId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get missionId => $composableBuilder(
    column: $table.missionId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get statusOrdinal => $composableBuilder(
    column: $table.statusOrdinal,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get currentValue => $composableBuilder(
    column: $table.currentValue,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get targetValue => $composableBuilder(
    column: $table.targetValue,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get assignedAtMs => $composableBuilder(
    column: $table.assignedAtMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get completedAtMs => $composableBuilder(
    column: $table.completedAtMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get completionCount => $composableBuilder(
    column: $table.completionCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get contributingSessionIdsJson => $composableBuilder(
    column: $table.contributingSessionIdsJson,
    builder: (column) => ColumnFilters(column),
  );
}

class $$MissionProgressesTableOrderingComposer
    extends Composer<_$AppDatabase, $MissionProgressesTable> {
  $$MissionProgressesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get progressUuid => $composableBuilder(
    column: $table.progressUuid,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get userId => $composableBuilder(
    column: $table.userId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get missionId => $composableBuilder(
    column: $table.missionId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get statusOrdinal => $composableBuilder(
    column: $table.statusOrdinal,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get currentValue => $composableBuilder(
    column: $table.currentValue,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get targetValue => $composableBuilder(
    column: $table.targetValue,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get assignedAtMs => $composableBuilder(
    column: $table.assignedAtMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get completedAtMs => $composableBuilder(
    column: $table.completedAtMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get completionCount => $composableBuilder(
    column: $table.completionCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get contributingSessionIdsJson => $composableBuilder(
    column: $table.contributingSessionIdsJson,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$MissionProgressesTableAnnotationComposer
    extends Composer<_$AppDatabase, $MissionProgressesTable> {
  $$MissionProgressesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get progressUuid => $composableBuilder(
    column: $table.progressUuid,
    builder: (column) => column,
  );

  GeneratedColumn<String> get userId =>
      $composableBuilder(column: $table.userId, builder: (column) => column);

  GeneratedColumn<String> get missionId =>
      $composableBuilder(column: $table.missionId, builder: (column) => column);

  GeneratedColumn<String> get statusOrdinal => $composableBuilder(
    column: $table.statusOrdinal,
    builder: (column) => column,
  );

  GeneratedColumn<double> get currentValue => $composableBuilder(
    column: $table.currentValue,
    builder: (column) => column,
  );

  GeneratedColumn<double> get targetValue => $composableBuilder(
    column: $table.targetValue,
    builder: (column) => column,
  );

  GeneratedColumn<int> get assignedAtMs => $composableBuilder(
    column: $table.assignedAtMs,
    builder: (column) => column,
  );

  GeneratedColumn<int> get completedAtMs => $composableBuilder(
    column: $table.completedAtMs,
    builder: (column) => column,
  );

  GeneratedColumn<int> get completionCount => $composableBuilder(
    column: $table.completionCount,
    builder: (column) => column,
  );

  GeneratedColumn<String> get contributingSessionIdsJson => $composableBuilder(
    column: $table.contributingSessionIdsJson,
    builder: (column) => column,
  );
}

class $$MissionProgressesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $MissionProgressesTable,
          MissionProgress,
          $$MissionProgressesTableFilterComposer,
          $$MissionProgressesTableOrderingComposer,
          $$MissionProgressesTableAnnotationComposer,
          $$MissionProgressesTableCreateCompanionBuilder,
          $$MissionProgressesTableUpdateCompanionBuilder,
          (
            MissionProgress,
            BaseReferences<
              _$AppDatabase,
              $MissionProgressesTable,
              MissionProgress
            >,
          ),
          MissionProgress,
          PrefetchHooks Function()
        > {
  $$MissionProgressesTableTableManager(
    _$AppDatabase db,
    $MissionProgressesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$MissionProgressesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$MissionProgressesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$MissionProgressesTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> progressUuid = const Value.absent(),
                Value<String> userId = const Value.absent(),
                Value<String> missionId = const Value.absent(),
                Value<String> statusOrdinal = const Value.absent(),
                Value<double> currentValue = const Value.absent(),
                Value<double> targetValue = const Value.absent(),
                Value<int> assignedAtMs = const Value.absent(),
                Value<int?> completedAtMs = const Value.absent(),
                Value<int> completionCount = const Value.absent(),
                Value<String> contributingSessionIdsJson = const Value.absent(),
              }) => MissionProgressesCompanion(
                id: id,
                progressUuid: progressUuid,
                userId: userId,
                missionId: missionId,
                statusOrdinal: statusOrdinal,
                currentValue: currentValue,
                targetValue: targetValue,
                assignedAtMs: assignedAtMs,
                completedAtMs: completedAtMs,
                completionCount: completionCount,
                contributingSessionIdsJson: contributingSessionIdsJson,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String progressUuid,
                required String userId,
                required String missionId,
                required String statusOrdinal,
                required double currentValue,
                required double targetValue,
                required int assignedAtMs,
                Value<int?> completedAtMs = const Value.absent(),
                required int completionCount,
                required String contributingSessionIdsJson,
              }) => MissionProgressesCompanion.insert(
                id: id,
                progressUuid: progressUuid,
                userId: userId,
                missionId: missionId,
                statusOrdinal: statusOrdinal,
                currentValue: currentValue,
                targetValue: targetValue,
                assignedAtMs: assignedAtMs,
                completedAtMs: completedAtMs,
                completionCount: completionCount,
                contributingSessionIdsJson: contributingSessionIdsJson,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$MissionProgressesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $MissionProgressesTable,
      MissionProgress,
      $$MissionProgressesTableFilterComposer,
      $$MissionProgressesTableOrderingComposer,
      $$MissionProgressesTableAnnotationComposer,
      $$MissionProgressesTableCreateCompanionBuilder,
      $$MissionProgressesTableUpdateCompanionBuilder,
      (
        MissionProgress,
        BaseReferences<_$AppDatabase, $MissionProgressesTable, MissionProgress>,
      ),
      MissionProgress,
      PrefetchHooks Function()
    >;
typedef $$SeasonsTableCreateCompanionBuilder =
    SeasonsCompanion Function({
      Value<int> id,
      required String seasonUuid,
      required String name,
      required String statusOrdinal,
      required int startsAtMs,
      required int endsAtMs,
      required String passXpMilestonesStr,
    });
typedef $$SeasonsTableUpdateCompanionBuilder =
    SeasonsCompanion Function({
      Value<int> id,
      Value<String> seasonUuid,
      Value<String> name,
      Value<String> statusOrdinal,
      Value<int> startsAtMs,
      Value<int> endsAtMs,
      Value<String> passXpMilestonesStr,
    });

class $$SeasonsTableFilterComposer
    extends Composer<_$AppDatabase, $SeasonsTable> {
  $$SeasonsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get seasonUuid => $composableBuilder(
    column: $table.seasonUuid,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get statusOrdinal => $composableBuilder(
    column: $table.statusOrdinal,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get startsAtMs => $composableBuilder(
    column: $table.startsAtMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get endsAtMs => $composableBuilder(
    column: $table.endsAtMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get passXpMilestonesStr => $composableBuilder(
    column: $table.passXpMilestonesStr,
    builder: (column) => ColumnFilters(column),
  );
}

class $$SeasonsTableOrderingComposer
    extends Composer<_$AppDatabase, $SeasonsTable> {
  $$SeasonsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get seasonUuid => $composableBuilder(
    column: $table.seasonUuid,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get statusOrdinal => $composableBuilder(
    column: $table.statusOrdinal,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get startsAtMs => $composableBuilder(
    column: $table.startsAtMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get endsAtMs => $composableBuilder(
    column: $table.endsAtMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get passXpMilestonesStr => $composableBuilder(
    column: $table.passXpMilestonesStr,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SeasonsTableAnnotationComposer
    extends Composer<_$AppDatabase, $SeasonsTable> {
  $$SeasonsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get seasonUuid => $composableBuilder(
    column: $table.seasonUuid,
    builder: (column) => column,
  );

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get statusOrdinal => $composableBuilder(
    column: $table.statusOrdinal,
    builder: (column) => column,
  );

  GeneratedColumn<int> get startsAtMs => $composableBuilder(
    column: $table.startsAtMs,
    builder: (column) => column,
  );

  GeneratedColumn<int> get endsAtMs =>
      $composableBuilder(column: $table.endsAtMs, builder: (column) => column);

  GeneratedColumn<String> get passXpMilestonesStr => $composableBuilder(
    column: $table.passXpMilestonesStr,
    builder: (column) => column,
  );
}

class $$SeasonsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $SeasonsTable,
          Season,
          $$SeasonsTableFilterComposer,
          $$SeasonsTableOrderingComposer,
          $$SeasonsTableAnnotationComposer,
          $$SeasonsTableCreateCompanionBuilder,
          $$SeasonsTableUpdateCompanionBuilder,
          (Season, BaseReferences<_$AppDatabase, $SeasonsTable, Season>),
          Season,
          PrefetchHooks Function()
        > {
  $$SeasonsTableTableManager(_$AppDatabase db, $SeasonsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SeasonsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SeasonsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SeasonsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> seasonUuid = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String> statusOrdinal = const Value.absent(),
                Value<int> startsAtMs = const Value.absent(),
                Value<int> endsAtMs = const Value.absent(),
                Value<String> passXpMilestonesStr = const Value.absent(),
              }) => SeasonsCompanion(
                id: id,
                seasonUuid: seasonUuid,
                name: name,
                statusOrdinal: statusOrdinal,
                startsAtMs: startsAtMs,
                endsAtMs: endsAtMs,
                passXpMilestonesStr: passXpMilestonesStr,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String seasonUuid,
                required String name,
                required String statusOrdinal,
                required int startsAtMs,
                required int endsAtMs,
                required String passXpMilestonesStr,
              }) => SeasonsCompanion.insert(
                id: id,
                seasonUuid: seasonUuid,
                name: name,
                statusOrdinal: statusOrdinal,
                startsAtMs: startsAtMs,
                endsAtMs: endsAtMs,
                passXpMilestonesStr: passXpMilestonesStr,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$SeasonsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $SeasonsTable,
      Season,
      $$SeasonsTableFilterComposer,
      $$SeasonsTableOrderingComposer,
      $$SeasonsTableAnnotationComposer,
      $$SeasonsTableCreateCompanionBuilder,
      $$SeasonsTableUpdateCompanionBuilder,
      (Season, BaseReferences<_$AppDatabase, $SeasonsTable, Season>),
      Season,
      PrefetchHooks Function()
    >;
typedef $$SeasonProgressesTableCreateCompanionBuilder =
    SeasonProgressesCompanion Function({
      Value<int> id,
      required String userId,
      required String seasonId,
      required int seasonXp,
      required String claimedMilestoneIndicesStr,
      required bool endRewardsClaimed,
    });
typedef $$SeasonProgressesTableUpdateCompanionBuilder =
    SeasonProgressesCompanion Function({
      Value<int> id,
      Value<String> userId,
      Value<String> seasonId,
      Value<int> seasonXp,
      Value<String> claimedMilestoneIndicesStr,
      Value<bool> endRewardsClaimed,
    });

class $$SeasonProgressesTableFilterComposer
    extends Composer<_$AppDatabase, $SeasonProgressesTable> {
  $$SeasonProgressesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get userId => $composableBuilder(
    column: $table.userId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get seasonId => $composableBuilder(
    column: $table.seasonId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get seasonXp => $composableBuilder(
    column: $table.seasonXp,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get claimedMilestoneIndicesStr => $composableBuilder(
    column: $table.claimedMilestoneIndicesStr,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get endRewardsClaimed => $composableBuilder(
    column: $table.endRewardsClaimed,
    builder: (column) => ColumnFilters(column),
  );
}

class $$SeasonProgressesTableOrderingComposer
    extends Composer<_$AppDatabase, $SeasonProgressesTable> {
  $$SeasonProgressesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get userId => $composableBuilder(
    column: $table.userId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get seasonId => $composableBuilder(
    column: $table.seasonId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get seasonXp => $composableBuilder(
    column: $table.seasonXp,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get claimedMilestoneIndicesStr => $composableBuilder(
    column: $table.claimedMilestoneIndicesStr,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get endRewardsClaimed => $composableBuilder(
    column: $table.endRewardsClaimed,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SeasonProgressesTableAnnotationComposer
    extends Composer<_$AppDatabase, $SeasonProgressesTable> {
  $$SeasonProgressesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get userId =>
      $composableBuilder(column: $table.userId, builder: (column) => column);

  GeneratedColumn<String> get seasonId =>
      $composableBuilder(column: $table.seasonId, builder: (column) => column);

  GeneratedColumn<int> get seasonXp =>
      $composableBuilder(column: $table.seasonXp, builder: (column) => column);

  GeneratedColumn<String> get claimedMilestoneIndicesStr => $composableBuilder(
    column: $table.claimedMilestoneIndicesStr,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get endRewardsClaimed => $composableBuilder(
    column: $table.endRewardsClaimed,
    builder: (column) => column,
  );
}

class $$SeasonProgressesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $SeasonProgressesTable,
          SeasonProgress,
          $$SeasonProgressesTableFilterComposer,
          $$SeasonProgressesTableOrderingComposer,
          $$SeasonProgressesTableAnnotationComposer,
          $$SeasonProgressesTableCreateCompanionBuilder,
          $$SeasonProgressesTableUpdateCompanionBuilder,
          (
            SeasonProgress,
            BaseReferences<
              _$AppDatabase,
              $SeasonProgressesTable,
              SeasonProgress
            >,
          ),
          SeasonProgress,
          PrefetchHooks Function()
        > {
  $$SeasonProgressesTableTableManager(
    _$AppDatabase db,
    $SeasonProgressesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SeasonProgressesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SeasonProgressesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SeasonProgressesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> userId = const Value.absent(),
                Value<String> seasonId = const Value.absent(),
                Value<int> seasonXp = const Value.absent(),
                Value<String> claimedMilestoneIndicesStr = const Value.absent(),
                Value<bool> endRewardsClaimed = const Value.absent(),
              }) => SeasonProgressesCompanion(
                id: id,
                userId: userId,
                seasonId: seasonId,
                seasonXp: seasonXp,
                claimedMilestoneIndicesStr: claimedMilestoneIndicesStr,
                endRewardsClaimed: endRewardsClaimed,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String userId,
                required String seasonId,
                required int seasonXp,
                required String claimedMilestoneIndicesStr,
                required bool endRewardsClaimed,
              }) => SeasonProgressesCompanion.insert(
                id: id,
                userId: userId,
                seasonId: seasonId,
                seasonXp: seasonXp,
                claimedMilestoneIndicesStr: claimedMilestoneIndicesStr,
                endRewardsClaimed: endRewardsClaimed,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$SeasonProgressesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $SeasonProgressesTable,
      SeasonProgress,
      $$SeasonProgressesTableFilterComposer,
      $$SeasonProgressesTableOrderingComposer,
      $$SeasonProgressesTableAnnotationComposer,
      $$SeasonProgressesTableCreateCompanionBuilder,
      $$SeasonProgressesTableUpdateCompanionBuilder,
      (
        SeasonProgress,
        BaseReferences<_$AppDatabase, $SeasonProgressesTable, SeasonProgress>,
      ),
      SeasonProgress,
      PrefetchHooks Function()
    >;
typedef $$CoachingGroupsTableCreateCompanionBuilder =
    CoachingGroupsCompanion Function({
      Value<int> id,
      required String groupUuid,
      required String name,
      Value<String?> logoUrl,
      required String coachUserId,
      required String description,
      required String city,
      Value<String?> inviteCode,
      required bool inviteEnabled,
      required int createdAtMs,
    });
typedef $$CoachingGroupsTableUpdateCompanionBuilder =
    CoachingGroupsCompanion Function({
      Value<int> id,
      Value<String> groupUuid,
      Value<String> name,
      Value<String?> logoUrl,
      Value<String> coachUserId,
      Value<String> description,
      Value<String> city,
      Value<String?> inviteCode,
      Value<bool> inviteEnabled,
      Value<int> createdAtMs,
    });

class $$CoachingGroupsTableFilterComposer
    extends Composer<_$AppDatabase, $CoachingGroupsTable> {
  $$CoachingGroupsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get groupUuid => $composableBuilder(
    column: $table.groupUuid,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get logoUrl => $composableBuilder(
    column: $table.logoUrl,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get coachUserId => $composableBuilder(
    column: $table.coachUserId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get city => $composableBuilder(
    column: $table.city,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get inviteCode => $composableBuilder(
    column: $table.inviteCode,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get inviteEnabled => $composableBuilder(
    column: $table.inviteEnabled,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get createdAtMs => $composableBuilder(
    column: $table.createdAtMs,
    builder: (column) => ColumnFilters(column),
  );
}

class $$CoachingGroupsTableOrderingComposer
    extends Composer<_$AppDatabase, $CoachingGroupsTable> {
  $$CoachingGroupsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get groupUuid => $composableBuilder(
    column: $table.groupUuid,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get logoUrl => $composableBuilder(
    column: $table.logoUrl,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get coachUserId => $composableBuilder(
    column: $table.coachUserId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get city => $composableBuilder(
    column: $table.city,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get inviteCode => $composableBuilder(
    column: $table.inviteCode,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get inviteEnabled => $composableBuilder(
    column: $table.inviteEnabled,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get createdAtMs => $composableBuilder(
    column: $table.createdAtMs,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$CoachingGroupsTableAnnotationComposer
    extends Composer<_$AppDatabase, $CoachingGroupsTable> {
  $$CoachingGroupsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get groupUuid =>
      $composableBuilder(column: $table.groupUuid, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get logoUrl =>
      $composableBuilder(column: $table.logoUrl, builder: (column) => column);

  GeneratedColumn<String> get coachUserId => $composableBuilder(
    column: $table.coachUserId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => column,
  );

  GeneratedColumn<String> get city =>
      $composableBuilder(column: $table.city, builder: (column) => column);

  GeneratedColumn<String> get inviteCode => $composableBuilder(
    column: $table.inviteCode,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get inviteEnabled => $composableBuilder(
    column: $table.inviteEnabled,
    builder: (column) => column,
  );

  GeneratedColumn<int> get createdAtMs => $composableBuilder(
    column: $table.createdAtMs,
    builder: (column) => column,
  );
}

class $$CoachingGroupsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $CoachingGroupsTable,
          CoachingGroup,
          $$CoachingGroupsTableFilterComposer,
          $$CoachingGroupsTableOrderingComposer,
          $$CoachingGroupsTableAnnotationComposer,
          $$CoachingGroupsTableCreateCompanionBuilder,
          $$CoachingGroupsTableUpdateCompanionBuilder,
          (
            CoachingGroup,
            BaseReferences<_$AppDatabase, $CoachingGroupsTable, CoachingGroup>,
          ),
          CoachingGroup,
          PrefetchHooks Function()
        > {
  $$CoachingGroupsTableTableManager(
    _$AppDatabase db,
    $CoachingGroupsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CoachingGroupsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CoachingGroupsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CoachingGroupsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> groupUuid = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String?> logoUrl = const Value.absent(),
                Value<String> coachUserId = const Value.absent(),
                Value<String> description = const Value.absent(),
                Value<String> city = const Value.absent(),
                Value<String?> inviteCode = const Value.absent(),
                Value<bool> inviteEnabled = const Value.absent(),
                Value<int> createdAtMs = const Value.absent(),
              }) => CoachingGroupsCompanion(
                id: id,
                groupUuid: groupUuid,
                name: name,
                logoUrl: logoUrl,
                coachUserId: coachUserId,
                description: description,
                city: city,
                inviteCode: inviteCode,
                inviteEnabled: inviteEnabled,
                createdAtMs: createdAtMs,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String groupUuid,
                required String name,
                Value<String?> logoUrl = const Value.absent(),
                required String coachUserId,
                required String description,
                required String city,
                Value<String?> inviteCode = const Value.absent(),
                required bool inviteEnabled,
                required int createdAtMs,
              }) => CoachingGroupsCompanion.insert(
                id: id,
                groupUuid: groupUuid,
                name: name,
                logoUrl: logoUrl,
                coachUserId: coachUserId,
                description: description,
                city: city,
                inviteCode: inviteCode,
                inviteEnabled: inviteEnabled,
                createdAtMs: createdAtMs,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$CoachingGroupsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $CoachingGroupsTable,
      CoachingGroup,
      $$CoachingGroupsTableFilterComposer,
      $$CoachingGroupsTableOrderingComposer,
      $$CoachingGroupsTableAnnotationComposer,
      $$CoachingGroupsTableCreateCompanionBuilder,
      $$CoachingGroupsTableUpdateCompanionBuilder,
      (
        CoachingGroup,
        BaseReferences<_$AppDatabase, $CoachingGroupsTable, CoachingGroup>,
      ),
      CoachingGroup,
      PrefetchHooks Function()
    >;
typedef $$CoachingMembersTableCreateCompanionBuilder =
    CoachingMembersCompanion Function({
      Value<int> id,
      required String memberUuid,
      required String groupId,
      required String userId,
      required String displayName,
      required String roleOrdinal,
      required int joinedAtMs,
    });
typedef $$CoachingMembersTableUpdateCompanionBuilder =
    CoachingMembersCompanion Function({
      Value<int> id,
      Value<String> memberUuid,
      Value<String> groupId,
      Value<String> userId,
      Value<String> displayName,
      Value<String> roleOrdinal,
      Value<int> joinedAtMs,
    });

class $$CoachingMembersTableFilterComposer
    extends Composer<_$AppDatabase, $CoachingMembersTable> {
  $$CoachingMembersTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get memberUuid => $composableBuilder(
    column: $table.memberUuid,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get groupId => $composableBuilder(
    column: $table.groupId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get userId => $composableBuilder(
    column: $table.userId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get displayName => $composableBuilder(
    column: $table.displayName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get roleOrdinal => $composableBuilder(
    column: $table.roleOrdinal,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get joinedAtMs => $composableBuilder(
    column: $table.joinedAtMs,
    builder: (column) => ColumnFilters(column),
  );
}

class $$CoachingMembersTableOrderingComposer
    extends Composer<_$AppDatabase, $CoachingMembersTable> {
  $$CoachingMembersTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get memberUuid => $composableBuilder(
    column: $table.memberUuid,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get groupId => $composableBuilder(
    column: $table.groupId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get userId => $composableBuilder(
    column: $table.userId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get displayName => $composableBuilder(
    column: $table.displayName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get roleOrdinal => $composableBuilder(
    column: $table.roleOrdinal,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get joinedAtMs => $composableBuilder(
    column: $table.joinedAtMs,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$CoachingMembersTableAnnotationComposer
    extends Composer<_$AppDatabase, $CoachingMembersTable> {
  $$CoachingMembersTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get memberUuid => $composableBuilder(
    column: $table.memberUuid,
    builder: (column) => column,
  );

  GeneratedColumn<String> get groupId =>
      $composableBuilder(column: $table.groupId, builder: (column) => column);

  GeneratedColumn<String> get userId =>
      $composableBuilder(column: $table.userId, builder: (column) => column);

  GeneratedColumn<String> get displayName => $composableBuilder(
    column: $table.displayName,
    builder: (column) => column,
  );

  GeneratedColumn<String> get roleOrdinal => $composableBuilder(
    column: $table.roleOrdinal,
    builder: (column) => column,
  );

  GeneratedColumn<int> get joinedAtMs => $composableBuilder(
    column: $table.joinedAtMs,
    builder: (column) => column,
  );
}

class $$CoachingMembersTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $CoachingMembersTable,
          CoachingMember,
          $$CoachingMembersTableFilterComposer,
          $$CoachingMembersTableOrderingComposer,
          $$CoachingMembersTableAnnotationComposer,
          $$CoachingMembersTableCreateCompanionBuilder,
          $$CoachingMembersTableUpdateCompanionBuilder,
          (
            CoachingMember,
            BaseReferences<
              _$AppDatabase,
              $CoachingMembersTable,
              CoachingMember
            >,
          ),
          CoachingMember,
          PrefetchHooks Function()
        > {
  $$CoachingMembersTableTableManager(
    _$AppDatabase db,
    $CoachingMembersTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CoachingMembersTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CoachingMembersTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CoachingMembersTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> memberUuid = const Value.absent(),
                Value<String> groupId = const Value.absent(),
                Value<String> userId = const Value.absent(),
                Value<String> displayName = const Value.absent(),
                Value<String> roleOrdinal = const Value.absent(),
                Value<int> joinedAtMs = const Value.absent(),
              }) => CoachingMembersCompanion(
                id: id,
                memberUuid: memberUuid,
                groupId: groupId,
                userId: userId,
                displayName: displayName,
                roleOrdinal: roleOrdinal,
                joinedAtMs: joinedAtMs,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String memberUuid,
                required String groupId,
                required String userId,
                required String displayName,
                required String roleOrdinal,
                required int joinedAtMs,
              }) => CoachingMembersCompanion.insert(
                id: id,
                memberUuid: memberUuid,
                groupId: groupId,
                userId: userId,
                displayName: displayName,
                roleOrdinal: roleOrdinal,
                joinedAtMs: joinedAtMs,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$CoachingMembersTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $CoachingMembersTable,
      CoachingMember,
      $$CoachingMembersTableFilterComposer,
      $$CoachingMembersTableOrderingComposer,
      $$CoachingMembersTableAnnotationComposer,
      $$CoachingMembersTableCreateCompanionBuilder,
      $$CoachingMembersTableUpdateCompanionBuilder,
      (
        CoachingMember,
        BaseReferences<_$AppDatabase, $CoachingMembersTable, CoachingMember>,
      ),
      CoachingMember,
      PrefetchHooks Function()
    >;
typedef $$CoachingInvitesTableCreateCompanionBuilder =
    CoachingInvitesCompanion Function({
      Value<int> id,
      required String inviteUuid,
      required String groupId,
      required String invitedUserId,
      required String invitedByUserId,
      required String statusOrdinal,
      required int expiresAtMs,
      required int createdAtMs,
    });
typedef $$CoachingInvitesTableUpdateCompanionBuilder =
    CoachingInvitesCompanion Function({
      Value<int> id,
      Value<String> inviteUuid,
      Value<String> groupId,
      Value<String> invitedUserId,
      Value<String> invitedByUserId,
      Value<String> statusOrdinal,
      Value<int> expiresAtMs,
      Value<int> createdAtMs,
    });

class $$CoachingInvitesTableFilterComposer
    extends Composer<_$AppDatabase, $CoachingInvitesTable> {
  $$CoachingInvitesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get inviteUuid => $composableBuilder(
    column: $table.inviteUuid,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get groupId => $composableBuilder(
    column: $table.groupId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get invitedUserId => $composableBuilder(
    column: $table.invitedUserId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get invitedByUserId => $composableBuilder(
    column: $table.invitedByUserId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get statusOrdinal => $composableBuilder(
    column: $table.statusOrdinal,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get expiresAtMs => $composableBuilder(
    column: $table.expiresAtMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get createdAtMs => $composableBuilder(
    column: $table.createdAtMs,
    builder: (column) => ColumnFilters(column),
  );
}

class $$CoachingInvitesTableOrderingComposer
    extends Composer<_$AppDatabase, $CoachingInvitesTable> {
  $$CoachingInvitesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get inviteUuid => $composableBuilder(
    column: $table.inviteUuid,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get groupId => $composableBuilder(
    column: $table.groupId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get invitedUserId => $composableBuilder(
    column: $table.invitedUserId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get invitedByUserId => $composableBuilder(
    column: $table.invitedByUserId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get statusOrdinal => $composableBuilder(
    column: $table.statusOrdinal,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get expiresAtMs => $composableBuilder(
    column: $table.expiresAtMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get createdAtMs => $composableBuilder(
    column: $table.createdAtMs,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$CoachingInvitesTableAnnotationComposer
    extends Composer<_$AppDatabase, $CoachingInvitesTable> {
  $$CoachingInvitesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get inviteUuid => $composableBuilder(
    column: $table.inviteUuid,
    builder: (column) => column,
  );

  GeneratedColumn<String> get groupId =>
      $composableBuilder(column: $table.groupId, builder: (column) => column);

  GeneratedColumn<String> get invitedUserId => $composableBuilder(
    column: $table.invitedUserId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get invitedByUserId => $composableBuilder(
    column: $table.invitedByUserId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get statusOrdinal => $composableBuilder(
    column: $table.statusOrdinal,
    builder: (column) => column,
  );

  GeneratedColumn<int> get expiresAtMs => $composableBuilder(
    column: $table.expiresAtMs,
    builder: (column) => column,
  );

  GeneratedColumn<int> get createdAtMs => $composableBuilder(
    column: $table.createdAtMs,
    builder: (column) => column,
  );
}

class $$CoachingInvitesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $CoachingInvitesTable,
          CoachingInvite,
          $$CoachingInvitesTableFilterComposer,
          $$CoachingInvitesTableOrderingComposer,
          $$CoachingInvitesTableAnnotationComposer,
          $$CoachingInvitesTableCreateCompanionBuilder,
          $$CoachingInvitesTableUpdateCompanionBuilder,
          (
            CoachingInvite,
            BaseReferences<
              _$AppDatabase,
              $CoachingInvitesTable,
              CoachingInvite
            >,
          ),
          CoachingInvite,
          PrefetchHooks Function()
        > {
  $$CoachingInvitesTableTableManager(
    _$AppDatabase db,
    $CoachingInvitesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CoachingInvitesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CoachingInvitesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CoachingInvitesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> inviteUuid = const Value.absent(),
                Value<String> groupId = const Value.absent(),
                Value<String> invitedUserId = const Value.absent(),
                Value<String> invitedByUserId = const Value.absent(),
                Value<String> statusOrdinal = const Value.absent(),
                Value<int> expiresAtMs = const Value.absent(),
                Value<int> createdAtMs = const Value.absent(),
              }) => CoachingInvitesCompanion(
                id: id,
                inviteUuid: inviteUuid,
                groupId: groupId,
                invitedUserId: invitedUserId,
                invitedByUserId: invitedByUserId,
                statusOrdinal: statusOrdinal,
                expiresAtMs: expiresAtMs,
                createdAtMs: createdAtMs,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String inviteUuid,
                required String groupId,
                required String invitedUserId,
                required String invitedByUserId,
                required String statusOrdinal,
                required int expiresAtMs,
                required int createdAtMs,
              }) => CoachingInvitesCompanion.insert(
                id: id,
                inviteUuid: inviteUuid,
                groupId: groupId,
                invitedUserId: invitedUserId,
                invitedByUserId: invitedByUserId,
                statusOrdinal: statusOrdinal,
                expiresAtMs: expiresAtMs,
                createdAtMs: createdAtMs,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$CoachingInvitesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $CoachingInvitesTable,
      CoachingInvite,
      $$CoachingInvitesTableFilterComposer,
      $$CoachingInvitesTableOrderingComposer,
      $$CoachingInvitesTableAnnotationComposer,
      $$CoachingInvitesTableCreateCompanionBuilder,
      $$CoachingInvitesTableUpdateCompanionBuilder,
      (
        CoachingInvite,
        BaseReferences<_$AppDatabase, $CoachingInvitesTable, CoachingInvite>,
      ),
      CoachingInvite,
      PrefetchHooks Function()
    >;
typedef $$CoachingRankingsTableCreateCompanionBuilder =
    CoachingRankingsCompanion Function({
      Value<int> id,
      required String rankingUuid,
      required String groupId,
      required String metricOrdinal,
      required String periodOrdinal,
      required String periodKey,
      required int startsAtMs,
      required int endsAtMs,
      required int computedAtMs,
    });
typedef $$CoachingRankingsTableUpdateCompanionBuilder =
    CoachingRankingsCompanion Function({
      Value<int> id,
      Value<String> rankingUuid,
      Value<String> groupId,
      Value<String> metricOrdinal,
      Value<String> periodOrdinal,
      Value<String> periodKey,
      Value<int> startsAtMs,
      Value<int> endsAtMs,
      Value<int> computedAtMs,
    });

class $$CoachingRankingsTableFilterComposer
    extends Composer<_$AppDatabase, $CoachingRankingsTable> {
  $$CoachingRankingsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get rankingUuid => $composableBuilder(
    column: $table.rankingUuid,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get groupId => $composableBuilder(
    column: $table.groupId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get metricOrdinal => $composableBuilder(
    column: $table.metricOrdinal,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get periodOrdinal => $composableBuilder(
    column: $table.periodOrdinal,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get periodKey => $composableBuilder(
    column: $table.periodKey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get startsAtMs => $composableBuilder(
    column: $table.startsAtMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get endsAtMs => $composableBuilder(
    column: $table.endsAtMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get computedAtMs => $composableBuilder(
    column: $table.computedAtMs,
    builder: (column) => ColumnFilters(column),
  );
}

class $$CoachingRankingsTableOrderingComposer
    extends Composer<_$AppDatabase, $CoachingRankingsTable> {
  $$CoachingRankingsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get rankingUuid => $composableBuilder(
    column: $table.rankingUuid,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get groupId => $composableBuilder(
    column: $table.groupId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get metricOrdinal => $composableBuilder(
    column: $table.metricOrdinal,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get periodOrdinal => $composableBuilder(
    column: $table.periodOrdinal,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get periodKey => $composableBuilder(
    column: $table.periodKey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get startsAtMs => $composableBuilder(
    column: $table.startsAtMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get endsAtMs => $composableBuilder(
    column: $table.endsAtMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get computedAtMs => $composableBuilder(
    column: $table.computedAtMs,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$CoachingRankingsTableAnnotationComposer
    extends Composer<_$AppDatabase, $CoachingRankingsTable> {
  $$CoachingRankingsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get rankingUuid => $composableBuilder(
    column: $table.rankingUuid,
    builder: (column) => column,
  );

  GeneratedColumn<String> get groupId =>
      $composableBuilder(column: $table.groupId, builder: (column) => column);

  GeneratedColumn<String> get metricOrdinal => $composableBuilder(
    column: $table.metricOrdinal,
    builder: (column) => column,
  );

  GeneratedColumn<String> get periodOrdinal => $composableBuilder(
    column: $table.periodOrdinal,
    builder: (column) => column,
  );

  GeneratedColumn<String> get periodKey =>
      $composableBuilder(column: $table.periodKey, builder: (column) => column);

  GeneratedColumn<int> get startsAtMs => $composableBuilder(
    column: $table.startsAtMs,
    builder: (column) => column,
  );

  GeneratedColumn<int> get endsAtMs =>
      $composableBuilder(column: $table.endsAtMs, builder: (column) => column);

  GeneratedColumn<int> get computedAtMs => $composableBuilder(
    column: $table.computedAtMs,
    builder: (column) => column,
  );
}

class $$CoachingRankingsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $CoachingRankingsTable,
          CoachingRanking,
          $$CoachingRankingsTableFilterComposer,
          $$CoachingRankingsTableOrderingComposer,
          $$CoachingRankingsTableAnnotationComposer,
          $$CoachingRankingsTableCreateCompanionBuilder,
          $$CoachingRankingsTableUpdateCompanionBuilder,
          (
            CoachingRanking,
            BaseReferences<
              _$AppDatabase,
              $CoachingRankingsTable,
              CoachingRanking
            >,
          ),
          CoachingRanking,
          PrefetchHooks Function()
        > {
  $$CoachingRankingsTableTableManager(
    _$AppDatabase db,
    $CoachingRankingsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CoachingRankingsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CoachingRankingsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CoachingRankingsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> rankingUuid = const Value.absent(),
                Value<String> groupId = const Value.absent(),
                Value<String> metricOrdinal = const Value.absent(),
                Value<String> periodOrdinal = const Value.absent(),
                Value<String> periodKey = const Value.absent(),
                Value<int> startsAtMs = const Value.absent(),
                Value<int> endsAtMs = const Value.absent(),
                Value<int> computedAtMs = const Value.absent(),
              }) => CoachingRankingsCompanion(
                id: id,
                rankingUuid: rankingUuid,
                groupId: groupId,
                metricOrdinal: metricOrdinal,
                periodOrdinal: periodOrdinal,
                periodKey: periodKey,
                startsAtMs: startsAtMs,
                endsAtMs: endsAtMs,
                computedAtMs: computedAtMs,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String rankingUuid,
                required String groupId,
                required String metricOrdinal,
                required String periodOrdinal,
                required String periodKey,
                required int startsAtMs,
                required int endsAtMs,
                required int computedAtMs,
              }) => CoachingRankingsCompanion.insert(
                id: id,
                rankingUuid: rankingUuid,
                groupId: groupId,
                metricOrdinal: metricOrdinal,
                periodOrdinal: periodOrdinal,
                periodKey: periodKey,
                startsAtMs: startsAtMs,
                endsAtMs: endsAtMs,
                computedAtMs: computedAtMs,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$CoachingRankingsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $CoachingRankingsTable,
      CoachingRanking,
      $$CoachingRankingsTableFilterComposer,
      $$CoachingRankingsTableOrderingComposer,
      $$CoachingRankingsTableAnnotationComposer,
      $$CoachingRankingsTableCreateCompanionBuilder,
      $$CoachingRankingsTableUpdateCompanionBuilder,
      (
        CoachingRanking,
        BaseReferences<_$AppDatabase, $CoachingRankingsTable, CoachingRanking>,
      ),
      CoachingRanking,
      PrefetchHooks Function()
    >;
typedef $$CoachingRankingEntriesTableCreateCompanionBuilder =
    CoachingRankingEntriesCompanion Function({
      Value<int> id,
      required String rankingId,
      required String userId,
      required String displayName,
      required double value,
      required int rank,
      required int sessionCount,
    });
typedef $$CoachingRankingEntriesTableUpdateCompanionBuilder =
    CoachingRankingEntriesCompanion Function({
      Value<int> id,
      Value<String> rankingId,
      Value<String> userId,
      Value<String> displayName,
      Value<double> value,
      Value<int> rank,
      Value<int> sessionCount,
    });

class $$CoachingRankingEntriesTableFilterComposer
    extends Composer<_$AppDatabase, $CoachingRankingEntriesTable> {
  $$CoachingRankingEntriesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get rankingId => $composableBuilder(
    column: $table.rankingId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get userId => $composableBuilder(
    column: $table.userId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get displayName => $composableBuilder(
    column: $table.displayName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get rank => $composableBuilder(
    column: $table.rank,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get sessionCount => $composableBuilder(
    column: $table.sessionCount,
    builder: (column) => ColumnFilters(column),
  );
}

class $$CoachingRankingEntriesTableOrderingComposer
    extends Composer<_$AppDatabase, $CoachingRankingEntriesTable> {
  $$CoachingRankingEntriesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get rankingId => $composableBuilder(
    column: $table.rankingId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get userId => $composableBuilder(
    column: $table.userId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get displayName => $composableBuilder(
    column: $table.displayName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get rank => $composableBuilder(
    column: $table.rank,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get sessionCount => $composableBuilder(
    column: $table.sessionCount,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$CoachingRankingEntriesTableAnnotationComposer
    extends Composer<_$AppDatabase, $CoachingRankingEntriesTable> {
  $$CoachingRankingEntriesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get rankingId =>
      $composableBuilder(column: $table.rankingId, builder: (column) => column);

  GeneratedColumn<String> get userId =>
      $composableBuilder(column: $table.userId, builder: (column) => column);

  GeneratedColumn<String> get displayName => $composableBuilder(
    column: $table.displayName,
    builder: (column) => column,
  );

  GeneratedColumn<double> get value =>
      $composableBuilder(column: $table.value, builder: (column) => column);

  GeneratedColumn<int> get rank =>
      $composableBuilder(column: $table.rank, builder: (column) => column);

  GeneratedColumn<int> get sessionCount => $composableBuilder(
    column: $table.sessionCount,
    builder: (column) => column,
  );
}

class $$CoachingRankingEntriesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $CoachingRankingEntriesTable,
          CoachingRankingEntry,
          $$CoachingRankingEntriesTableFilterComposer,
          $$CoachingRankingEntriesTableOrderingComposer,
          $$CoachingRankingEntriesTableAnnotationComposer,
          $$CoachingRankingEntriesTableCreateCompanionBuilder,
          $$CoachingRankingEntriesTableUpdateCompanionBuilder,
          (
            CoachingRankingEntry,
            BaseReferences<
              _$AppDatabase,
              $CoachingRankingEntriesTable,
              CoachingRankingEntry
            >,
          ),
          CoachingRankingEntry,
          PrefetchHooks Function()
        > {
  $$CoachingRankingEntriesTableTableManager(
    _$AppDatabase db,
    $CoachingRankingEntriesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CoachingRankingEntriesTableFilterComposer(
                $db: db,
                $table: table,
              ),
          createOrderingComposer: () =>
              $$CoachingRankingEntriesTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$CoachingRankingEntriesTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> rankingId = const Value.absent(),
                Value<String> userId = const Value.absent(),
                Value<String> displayName = const Value.absent(),
                Value<double> value = const Value.absent(),
                Value<int> rank = const Value.absent(),
                Value<int> sessionCount = const Value.absent(),
              }) => CoachingRankingEntriesCompanion(
                id: id,
                rankingId: rankingId,
                userId: userId,
                displayName: displayName,
                value: value,
                rank: rank,
                sessionCount: sessionCount,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String rankingId,
                required String userId,
                required String displayName,
                required double value,
                required int rank,
                required int sessionCount,
              }) => CoachingRankingEntriesCompanion.insert(
                id: id,
                rankingId: rankingId,
                userId: userId,
                displayName: displayName,
                value: value,
                rank: rank,
                sessionCount: sessionCount,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$CoachingRankingEntriesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $CoachingRankingEntriesTable,
      CoachingRankingEntry,
      $$CoachingRankingEntriesTableFilterComposer,
      $$CoachingRankingEntriesTableOrderingComposer,
      $$CoachingRankingEntriesTableAnnotationComposer,
      $$CoachingRankingEntriesTableCreateCompanionBuilder,
      $$CoachingRankingEntriesTableUpdateCompanionBuilder,
      (
        CoachingRankingEntry,
        BaseReferences<
          _$AppDatabase,
          $CoachingRankingEntriesTable,
          CoachingRankingEntry
        >,
      ),
      CoachingRankingEntry,
      PrefetchHooks Function()
    >;
typedef $$AthleteBaselinesTableCreateCompanionBuilder =
    AthleteBaselinesCompanion Function({
      Value<int> id,
      required String baselineUuid,
      required String userId,
      required String groupId,
      required String metricOrdinal,
      required double value,
      required int sampleSize,
      required int windowStartMs,
      required int windowEndMs,
      required int computedAtMs,
    });
typedef $$AthleteBaselinesTableUpdateCompanionBuilder =
    AthleteBaselinesCompanion Function({
      Value<int> id,
      Value<String> baselineUuid,
      Value<String> userId,
      Value<String> groupId,
      Value<String> metricOrdinal,
      Value<double> value,
      Value<int> sampleSize,
      Value<int> windowStartMs,
      Value<int> windowEndMs,
      Value<int> computedAtMs,
    });

class $$AthleteBaselinesTableFilterComposer
    extends Composer<_$AppDatabase, $AthleteBaselinesTable> {
  $$AthleteBaselinesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get baselineUuid => $composableBuilder(
    column: $table.baselineUuid,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get userId => $composableBuilder(
    column: $table.userId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get groupId => $composableBuilder(
    column: $table.groupId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get metricOrdinal => $composableBuilder(
    column: $table.metricOrdinal,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get sampleSize => $composableBuilder(
    column: $table.sampleSize,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get windowStartMs => $composableBuilder(
    column: $table.windowStartMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get windowEndMs => $composableBuilder(
    column: $table.windowEndMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get computedAtMs => $composableBuilder(
    column: $table.computedAtMs,
    builder: (column) => ColumnFilters(column),
  );
}

class $$AthleteBaselinesTableOrderingComposer
    extends Composer<_$AppDatabase, $AthleteBaselinesTable> {
  $$AthleteBaselinesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get baselineUuid => $composableBuilder(
    column: $table.baselineUuid,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get userId => $composableBuilder(
    column: $table.userId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get groupId => $composableBuilder(
    column: $table.groupId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get metricOrdinal => $composableBuilder(
    column: $table.metricOrdinal,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get sampleSize => $composableBuilder(
    column: $table.sampleSize,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get windowStartMs => $composableBuilder(
    column: $table.windowStartMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get windowEndMs => $composableBuilder(
    column: $table.windowEndMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get computedAtMs => $composableBuilder(
    column: $table.computedAtMs,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$AthleteBaselinesTableAnnotationComposer
    extends Composer<_$AppDatabase, $AthleteBaselinesTable> {
  $$AthleteBaselinesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get baselineUuid => $composableBuilder(
    column: $table.baselineUuid,
    builder: (column) => column,
  );

  GeneratedColumn<String> get userId =>
      $composableBuilder(column: $table.userId, builder: (column) => column);

  GeneratedColumn<String> get groupId =>
      $composableBuilder(column: $table.groupId, builder: (column) => column);

  GeneratedColumn<String> get metricOrdinal => $composableBuilder(
    column: $table.metricOrdinal,
    builder: (column) => column,
  );

  GeneratedColumn<double> get value =>
      $composableBuilder(column: $table.value, builder: (column) => column);

  GeneratedColumn<int> get sampleSize => $composableBuilder(
    column: $table.sampleSize,
    builder: (column) => column,
  );

  GeneratedColumn<int> get windowStartMs => $composableBuilder(
    column: $table.windowStartMs,
    builder: (column) => column,
  );

  GeneratedColumn<int> get windowEndMs => $composableBuilder(
    column: $table.windowEndMs,
    builder: (column) => column,
  );

  GeneratedColumn<int> get computedAtMs => $composableBuilder(
    column: $table.computedAtMs,
    builder: (column) => column,
  );
}

class $$AthleteBaselinesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $AthleteBaselinesTable,
          AthleteBaseline,
          $$AthleteBaselinesTableFilterComposer,
          $$AthleteBaselinesTableOrderingComposer,
          $$AthleteBaselinesTableAnnotationComposer,
          $$AthleteBaselinesTableCreateCompanionBuilder,
          $$AthleteBaselinesTableUpdateCompanionBuilder,
          (
            AthleteBaseline,
            BaseReferences<
              _$AppDatabase,
              $AthleteBaselinesTable,
              AthleteBaseline
            >,
          ),
          AthleteBaseline,
          PrefetchHooks Function()
        > {
  $$AthleteBaselinesTableTableManager(
    _$AppDatabase db,
    $AthleteBaselinesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$AthleteBaselinesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$AthleteBaselinesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$AthleteBaselinesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> baselineUuid = const Value.absent(),
                Value<String> userId = const Value.absent(),
                Value<String> groupId = const Value.absent(),
                Value<String> metricOrdinal = const Value.absent(),
                Value<double> value = const Value.absent(),
                Value<int> sampleSize = const Value.absent(),
                Value<int> windowStartMs = const Value.absent(),
                Value<int> windowEndMs = const Value.absent(),
                Value<int> computedAtMs = const Value.absent(),
              }) => AthleteBaselinesCompanion(
                id: id,
                baselineUuid: baselineUuid,
                userId: userId,
                groupId: groupId,
                metricOrdinal: metricOrdinal,
                value: value,
                sampleSize: sampleSize,
                windowStartMs: windowStartMs,
                windowEndMs: windowEndMs,
                computedAtMs: computedAtMs,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String baselineUuid,
                required String userId,
                required String groupId,
                required String metricOrdinal,
                required double value,
                required int sampleSize,
                required int windowStartMs,
                required int windowEndMs,
                required int computedAtMs,
              }) => AthleteBaselinesCompanion.insert(
                id: id,
                baselineUuid: baselineUuid,
                userId: userId,
                groupId: groupId,
                metricOrdinal: metricOrdinal,
                value: value,
                sampleSize: sampleSize,
                windowStartMs: windowStartMs,
                windowEndMs: windowEndMs,
                computedAtMs: computedAtMs,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$AthleteBaselinesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $AthleteBaselinesTable,
      AthleteBaseline,
      $$AthleteBaselinesTableFilterComposer,
      $$AthleteBaselinesTableOrderingComposer,
      $$AthleteBaselinesTableAnnotationComposer,
      $$AthleteBaselinesTableCreateCompanionBuilder,
      $$AthleteBaselinesTableUpdateCompanionBuilder,
      (
        AthleteBaseline,
        BaseReferences<_$AppDatabase, $AthleteBaselinesTable, AthleteBaseline>,
      ),
      AthleteBaseline,
      PrefetchHooks Function()
    >;
typedef $$AthleteTrendsTableCreateCompanionBuilder =
    AthleteTrendsCompanion Function({
      Value<int> id,
      required String trendUuid,
      required String userId,
      required String groupId,
      required String metricOrdinal,
      required String periodOrdinal,
      required String directionOrdinal,
      required double currentValue,
      required double baselineValue,
      required double changePercent,
      required int dataPoints,
      required String latestPeriodKey,
      required int analyzedAtMs,
    });
typedef $$AthleteTrendsTableUpdateCompanionBuilder =
    AthleteTrendsCompanion Function({
      Value<int> id,
      Value<String> trendUuid,
      Value<String> userId,
      Value<String> groupId,
      Value<String> metricOrdinal,
      Value<String> periodOrdinal,
      Value<String> directionOrdinal,
      Value<double> currentValue,
      Value<double> baselineValue,
      Value<double> changePercent,
      Value<int> dataPoints,
      Value<String> latestPeriodKey,
      Value<int> analyzedAtMs,
    });

class $$AthleteTrendsTableFilterComposer
    extends Composer<_$AppDatabase, $AthleteTrendsTable> {
  $$AthleteTrendsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get trendUuid => $composableBuilder(
    column: $table.trendUuid,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get userId => $composableBuilder(
    column: $table.userId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get groupId => $composableBuilder(
    column: $table.groupId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get metricOrdinal => $composableBuilder(
    column: $table.metricOrdinal,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get periodOrdinal => $composableBuilder(
    column: $table.periodOrdinal,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get directionOrdinal => $composableBuilder(
    column: $table.directionOrdinal,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get currentValue => $composableBuilder(
    column: $table.currentValue,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get baselineValue => $composableBuilder(
    column: $table.baselineValue,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get changePercent => $composableBuilder(
    column: $table.changePercent,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get dataPoints => $composableBuilder(
    column: $table.dataPoints,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get latestPeriodKey => $composableBuilder(
    column: $table.latestPeriodKey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get analyzedAtMs => $composableBuilder(
    column: $table.analyzedAtMs,
    builder: (column) => ColumnFilters(column),
  );
}

class $$AthleteTrendsTableOrderingComposer
    extends Composer<_$AppDatabase, $AthleteTrendsTable> {
  $$AthleteTrendsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get trendUuid => $composableBuilder(
    column: $table.trendUuid,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get userId => $composableBuilder(
    column: $table.userId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get groupId => $composableBuilder(
    column: $table.groupId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get metricOrdinal => $composableBuilder(
    column: $table.metricOrdinal,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get periodOrdinal => $composableBuilder(
    column: $table.periodOrdinal,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get directionOrdinal => $composableBuilder(
    column: $table.directionOrdinal,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get currentValue => $composableBuilder(
    column: $table.currentValue,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get baselineValue => $composableBuilder(
    column: $table.baselineValue,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get changePercent => $composableBuilder(
    column: $table.changePercent,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get dataPoints => $composableBuilder(
    column: $table.dataPoints,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get latestPeriodKey => $composableBuilder(
    column: $table.latestPeriodKey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get analyzedAtMs => $composableBuilder(
    column: $table.analyzedAtMs,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$AthleteTrendsTableAnnotationComposer
    extends Composer<_$AppDatabase, $AthleteTrendsTable> {
  $$AthleteTrendsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get trendUuid =>
      $composableBuilder(column: $table.trendUuid, builder: (column) => column);

  GeneratedColumn<String> get userId =>
      $composableBuilder(column: $table.userId, builder: (column) => column);

  GeneratedColumn<String> get groupId =>
      $composableBuilder(column: $table.groupId, builder: (column) => column);

  GeneratedColumn<String> get metricOrdinal => $composableBuilder(
    column: $table.metricOrdinal,
    builder: (column) => column,
  );

  GeneratedColumn<String> get periodOrdinal => $composableBuilder(
    column: $table.periodOrdinal,
    builder: (column) => column,
  );

  GeneratedColumn<String> get directionOrdinal => $composableBuilder(
    column: $table.directionOrdinal,
    builder: (column) => column,
  );

  GeneratedColumn<double> get currentValue => $composableBuilder(
    column: $table.currentValue,
    builder: (column) => column,
  );

  GeneratedColumn<double> get baselineValue => $composableBuilder(
    column: $table.baselineValue,
    builder: (column) => column,
  );

  GeneratedColumn<double> get changePercent => $composableBuilder(
    column: $table.changePercent,
    builder: (column) => column,
  );

  GeneratedColumn<int> get dataPoints => $composableBuilder(
    column: $table.dataPoints,
    builder: (column) => column,
  );

  GeneratedColumn<String> get latestPeriodKey => $composableBuilder(
    column: $table.latestPeriodKey,
    builder: (column) => column,
  );

  GeneratedColumn<int> get analyzedAtMs => $composableBuilder(
    column: $table.analyzedAtMs,
    builder: (column) => column,
  );
}

class $$AthleteTrendsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $AthleteTrendsTable,
          AthleteTrend,
          $$AthleteTrendsTableFilterComposer,
          $$AthleteTrendsTableOrderingComposer,
          $$AthleteTrendsTableAnnotationComposer,
          $$AthleteTrendsTableCreateCompanionBuilder,
          $$AthleteTrendsTableUpdateCompanionBuilder,
          (
            AthleteTrend,
            BaseReferences<_$AppDatabase, $AthleteTrendsTable, AthleteTrend>,
          ),
          AthleteTrend,
          PrefetchHooks Function()
        > {
  $$AthleteTrendsTableTableManager(_$AppDatabase db, $AthleteTrendsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$AthleteTrendsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$AthleteTrendsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$AthleteTrendsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> trendUuid = const Value.absent(),
                Value<String> userId = const Value.absent(),
                Value<String> groupId = const Value.absent(),
                Value<String> metricOrdinal = const Value.absent(),
                Value<String> periodOrdinal = const Value.absent(),
                Value<String> directionOrdinal = const Value.absent(),
                Value<double> currentValue = const Value.absent(),
                Value<double> baselineValue = const Value.absent(),
                Value<double> changePercent = const Value.absent(),
                Value<int> dataPoints = const Value.absent(),
                Value<String> latestPeriodKey = const Value.absent(),
                Value<int> analyzedAtMs = const Value.absent(),
              }) => AthleteTrendsCompanion(
                id: id,
                trendUuid: trendUuid,
                userId: userId,
                groupId: groupId,
                metricOrdinal: metricOrdinal,
                periodOrdinal: periodOrdinal,
                directionOrdinal: directionOrdinal,
                currentValue: currentValue,
                baselineValue: baselineValue,
                changePercent: changePercent,
                dataPoints: dataPoints,
                latestPeriodKey: latestPeriodKey,
                analyzedAtMs: analyzedAtMs,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String trendUuid,
                required String userId,
                required String groupId,
                required String metricOrdinal,
                required String periodOrdinal,
                required String directionOrdinal,
                required double currentValue,
                required double baselineValue,
                required double changePercent,
                required int dataPoints,
                required String latestPeriodKey,
                required int analyzedAtMs,
              }) => AthleteTrendsCompanion.insert(
                id: id,
                trendUuid: trendUuid,
                userId: userId,
                groupId: groupId,
                metricOrdinal: metricOrdinal,
                periodOrdinal: periodOrdinal,
                directionOrdinal: directionOrdinal,
                currentValue: currentValue,
                baselineValue: baselineValue,
                changePercent: changePercent,
                dataPoints: dataPoints,
                latestPeriodKey: latestPeriodKey,
                analyzedAtMs: analyzedAtMs,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$AthleteTrendsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $AthleteTrendsTable,
      AthleteTrend,
      $$AthleteTrendsTableFilterComposer,
      $$AthleteTrendsTableOrderingComposer,
      $$AthleteTrendsTableAnnotationComposer,
      $$AthleteTrendsTableCreateCompanionBuilder,
      $$AthleteTrendsTableUpdateCompanionBuilder,
      (
        AthleteTrend,
        BaseReferences<_$AppDatabase, $AthleteTrendsTable, AthleteTrend>,
      ),
      AthleteTrend,
      PrefetchHooks Function()
    >;
typedef $$CoachInsightsTableCreateCompanionBuilder =
    CoachInsightsCompanion Function({
      Value<int> id,
      required String insightUuid,
      required String groupId,
      required String targetUserId,
      required String targetDisplayName,
      required String typeOrdinal,
      required String priorityOrdinal,
      required String title,
      required String message,
      required String metricOrdinal,
      required double referenceValue,
      required double changePercent,
      required String relatedEntityId,
      required int createdAtMs,
      required int readAtMs,
      required bool dismissed,
    });
typedef $$CoachInsightsTableUpdateCompanionBuilder =
    CoachInsightsCompanion Function({
      Value<int> id,
      Value<String> insightUuid,
      Value<String> groupId,
      Value<String> targetUserId,
      Value<String> targetDisplayName,
      Value<String> typeOrdinal,
      Value<String> priorityOrdinal,
      Value<String> title,
      Value<String> message,
      Value<String> metricOrdinal,
      Value<double> referenceValue,
      Value<double> changePercent,
      Value<String> relatedEntityId,
      Value<int> createdAtMs,
      Value<int> readAtMs,
      Value<bool> dismissed,
    });

class $$CoachInsightsTableFilterComposer
    extends Composer<_$AppDatabase, $CoachInsightsTable> {
  $$CoachInsightsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get insightUuid => $composableBuilder(
    column: $table.insightUuid,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get groupId => $composableBuilder(
    column: $table.groupId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get targetUserId => $composableBuilder(
    column: $table.targetUserId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get targetDisplayName => $composableBuilder(
    column: $table.targetDisplayName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get typeOrdinal => $composableBuilder(
    column: $table.typeOrdinal,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get priorityOrdinal => $composableBuilder(
    column: $table.priorityOrdinal,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get message => $composableBuilder(
    column: $table.message,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get metricOrdinal => $composableBuilder(
    column: $table.metricOrdinal,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get referenceValue => $composableBuilder(
    column: $table.referenceValue,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get changePercent => $composableBuilder(
    column: $table.changePercent,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get relatedEntityId => $composableBuilder(
    column: $table.relatedEntityId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get createdAtMs => $composableBuilder(
    column: $table.createdAtMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get readAtMs => $composableBuilder(
    column: $table.readAtMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get dismissed => $composableBuilder(
    column: $table.dismissed,
    builder: (column) => ColumnFilters(column),
  );
}

class $$CoachInsightsTableOrderingComposer
    extends Composer<_$AppDatabase, $CoachInsightsTable> {
  $$CoachInsightsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get insightUuid => $composableBuilder(
    column: $table.insightUuid,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get groupId => $composableBuilder(
    column: $table.groupId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get targetUserId => $composableBuilder(
    column: $table.targetUserId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get targetDisplayName => $composableBuilder(
    column: $table.targetDisplayName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get typeOrdinal => $composableBuilder(
    column: $table.typeOrdinal,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get priorityOrdinal => $composableBuilder(
    column: $table.priorityOrdinal,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get message => $composableBuilder(
    column: $table.message,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get metricOrdinal => $composableBuilder(
    column: $table.metricOrdinal,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get referenceValue => $composableBuilder(
    column: $table.referenceValue,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get changePercent => $composableBuilder(
    column: $table.changePercent,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get relatedEntityId => $composableBuilder(
    column: $table.relatedEntityId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get createdAtMs => $composableBuilder(
    column: $table.createdAtMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get readAtMs => $composableBuilder(
    column: $table.readAtMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get dismissed => $composableBuilder(
    column: $table.dismissed,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$CoachInsightsTableAnnotationComposer
    extends Composer<_$AppDatabase, $CoachInsightsTable> {
  $$CoachInsightsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get insightUuid => $composableBuilder(
    column: $table.insightUuid,
    builder: (column) => column,
  );

  GeneratedColumn<String> get groupId =>
      $composableBuilder(column: $table.groupId, builder: (column) => column);

  GeneratedColumn<String> get targetUserId => $composableBuilder(
    column: $table.targetUserId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get targetDisplayName => $composableBuilder(
    column: $table.targetDisplayName,
    builder: (column) => column,
  );

  GeneratedColumn<String> get typeOrdinal => $composableBuilder(
    column: $table.typeOrdinal,
    builder: (column) => column,
  );

  GeneratedColumn<String> get priorityOrdinal => $composableBuilder(
    column: $table.priorityOrdinal,
    builder: (column) => column,
  );

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<String> get message =>
      $composableBuilder(column: $table.message, builder: (column) => column);

  GeneratedColumn<String> get metricOrdinal => $composableBuilder(
    column: $table.metricOrdinal,
    builder: (column) => column,
  );

  GeneratedColumn<double> get referenceValue => $composableBuilder(
    column: $table.referenceValue,
    builder: (column) => column,
  );

  GeneratedColumn<double> get changePercent => $composableBuilder(
    column: $table.changePercent,
    builder: (column) => column,
  );

  GeneratedColumn<String> get relatedEntityId => $composableBuilder(
    column: $table.relatedEntityId,
    builder: (column) => column,
  );

  GeneratedColumn<int> get createdAtMs => $composableBuilder(
    column: $table.createdAtMs,
    builder: (column) => column,
  );

  GeneratedColumn<int> get readAtMs =>
      $composableBuilder(column: $table.readAtMs, builder: (column) => column);

  GeneratedColumn<bool> get dismissed =>
      $composableBuilder(column: $table.dismissed, builder: (column) => column);
}

class $$CoachInsightsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $CoachInsightsTable,
          CoachInsight,
          $$CoachInsightsTableFilterComposer,
          $$CoachInsightsTableOrderingComposer,
          $$CoachInsightsTableAnnotationComposer,
          $$CoachInsightsTableCreateCompanionBuilder,
          $$CoachInsightsTableUpdateCompanionBuilder,
          (
            CoachInsight,
            BaseReferences<_$AppDatabase, $CoachInsightsTable, CoachInsight>,
          ),
          CoachInsight,
          PrefetchHooks Function()
        > {
  $$CoachInsightsTableTableManager(_$AppDatabase db, $CoachInsightsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CoachInsightsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CoachInsightsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CoachInsightsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> insightUuid = const Value.absent(),
                Value<String> groupId = const Value.absent(),
                Value<String> targetUserId = const Value.absent(),
                Value<String> targetDisplayName = const Value.absent(),
                Value<String> typeOrdinal = const Value.absent(),
                Value<String> priorityOrdinal = const Value.absent(),
                Value<String> title = const Value.absent(),
                Value<String> message = const Value.absent(),
                Value<String> metricOrdinal = const Value.absent(),
                Value<double> referenceValue = const Value.absent(),
                Value<double> changePercent = const Value.absent(),
                Value<String> relatedEntityId = const Value.absent(),
                Value<int> createdAtMs = const Value.absent(),
                Value<int> readAtMs = const Value.absent(),
                Value<bool> dismissed = const Value.absent(),
              }) => CoachInsightsCompanion(
                id: id,
                insightUuid: insightUuid,
                groupId: groupId,
                targetUserId: targetUserId,
                targetDisplayName: targetDisplayName,
                typeOrdinal: typeOrdinal,
                priorityOrdinal: priorityOrdinal,
                title: title,
                message: message,
                metricOrdinal: metricOrdinal,
                referenceValue: referenceValue,
                changePercent: changePercent,
                relatedEntityId: relatedEntityId,
                createdAtMs: createdAtMs,
                readAtMs: readAtMs,
                dismissed: dismissed,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String insightUuid,
                required String groupId,
                required String targetUserId,
                required String targetDisplayName,
                required String typeOrdinal,
                required String priorityOrdinal,
                required String title,
                required String message,
                required String metricOrdinal,
                required double referenceValue,
                required double changePercent,
                required String relatedEntityId,
                required int createdAtMs,
                required int readAtMs,
                required bool dismissed,
              }) => CoachInsightsCompanion.insert(
                id: id,
                insightUuid: insightUuid,
                groupId: groupId,
                targetUserId: targetUserId,
                targetDisplayName: targetDisplayName,
                typeOrdinal: typeOrdinal,
                priorityOrdinal: priorityOrdinal,
                title: title,
                message: message,
                metricOrdinal: metricOrdinal,
                referenceValue: referenceValue,
                changePercent: changePercent,
                relatedEntityId: relatedEntityId,
                createdAtMs: createdAtMs,
                readAtMs: readAtMs,
                dismissed: dismissed,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$CoachInsightsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $CoachInsightsTable,
      CoachInsight,
      $$CoachInsightsTableFilterComposer,
      $$CoachInsightsTableOrderingComposer,
      $$CoachInsightsTableAnnotationComposer,
      $$CoachInsightsTableCreateCompanionBuilder,
      $$CoachInsightsTableUpdateCompanionBuilder,
      (
        CoachInsight,
        BaseReferences<_$AppDatabase, $CoachInsightsTable, CoachInsight>,
      ),
      CoachInsight,
      PrefetchHooks Function()
    >;
typedef $$FriendshipsTableCreateCompanionBuilder =
    FriendshipsCompanion Function({
      Value<int> id,
      required String friendshipUuid,
      required String userIdA,
      required String userIdB,
      required String statusOrdinal,
      required int createdAtMs,
      Value<int?> acceptedAtMs,
    });
typedef $$FriendshipsTableUpdateCompanionBuilder =
    FriendshipsCompanion Function({
      Value<int> id,
      Value<String> friendshipUuid,
      Value<String> userIdA,
      Value<String> userIdB,
      Value<String> statusOrdinal,
      Value<int> createdAtMs,
      Value<int?> acceptedAtMs,
    });

class $$FriendshipsTableFilterComposer
    extends Composer<_$AppDatabase, $FriendshipsTable> {
  $$FriendshipsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get friendshipUuid => $composableBuilder(
    column: $table.friendshipUuid,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get userIdA => $composableBuilder(
    column: $table.userIdA,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get userIdB => $composableBuilder(
    column: $table.userIdB,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get statusOrdinal => $composableBuilder(
    column: $table.statusOrdinal,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get createdAtMs => $composableBuilder(
    column: $table.createdAtMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get acceptedAtMs => $composableBuilder(
    column: $table.acceptedAtMs,
    builder: (column) => ColumnFilters(column),
  );
}

class $$FriendshipsTableOrderingComposer
    extends Composer<_$AppDatabase, $FriendshipsTable> {
  $$FriendshipsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get friendshipUuid => $composableBuilder(
    column: $table.friendshipUuid,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get userIdA => $composableBuilder(
    column: $table.userIdA,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get userIdB => $composableBuilder(
    column: $table.userIdB,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get statusOrdinal => $composableBuilder(
    column: $table.statusOrdinal,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get createdAtMs => $composableBuilder(
    column: $table.createdAtMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get acceptedAtMs => $composableBuilder(
    column: $table.acceptedAtMs,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$FriendshipsTableAnnotationComposer
    extends Composer<_$AppDatabase, $FriendshipsTable> {
  $$FriendshipsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get friendshipUuid => $composableBuilder(
    column: $table.friendshipUuid,
    builder: (column) => column,
  );

  GeneratedColumn<String> get userIdA =>
      $composableBuilder(column: $table.userIdA, builder: (column) => column);

  GeneratedColumn<String> get userIdB =>
      $composableBuilder(column: $table.userIdB, builder: (column) => column);

  GeneratedColumn<String> get statusOrdinal => $composableBuilder(
    column: $table.statusOrdinal,
    builder: (column) => column,
  );

  GeneratedColumn<int> get createdAtMs => $composableBuilder(
    column: $table.createdAtMs,
    builder: (column) => column,
  );

  GeneratedColumn<int> get acceptedAtMs => $composableBuilder(
    column: $table.acceptedAtMs,
    builder: (column) => column,
  );
}

class $$FriendshipsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $FriendshipsTable,
          Friendship,
          $$FriendshipsTableFilterComposer,
          $$FriendshipsTableOrderingComposer,
          $$FriendshipsTableAnnotationComposer,
          $$FriendshipsTableCreateCompanionBuilder,
          $$FriendshipsTableUpdateCompanionBuilder,
          (
            Friendship,
            BaseReferences<_$AppDatabase, $FriendshipsTable, Friendship>,
          ),
          Friendship,
          PrefetchHooks Function()
        > {
  $$FriendshipsTableTableManager(_$AppDatabase db, $FriendshipsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$FriendshipsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$FriendshipsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$FriendshipsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> friendshipUuid = const Value.absent(),
                Value<String> userIdA = const Value.absent(),
                Value<String> userIdB = const Value.absent(),
                Value<String> statusOrdinal = const Value.absent(),
                Value<int> createdAtMs = const Value.absent(),
                Value<int?> acceptedAtMs = const Value.absent(),
              }) => FriendshipsCompanion(
                id: id,
                friendshipUuid: friendshipUuid,
                userIdA: userIdA,
                userIdB: userIdB,
                statusOrdinal: statusOrdinal,
                createdAtMs: createdAtMs,
                acceptedAtMs: acceptedAtMs,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String friendshipUuid,
                required String userIdA,
                required String userIdB,
                required String statusOrdinal,
                required int createdAtMs,
                Value<int?> acceptedAtMs = const Value.absent(),
              }) => FriendshipsCompanion.insert(
                id: id,
                friendshipUuid: friendshipUuid,
                userIdA: userIdA,
                userIdB: userIdB,
                statusOrdinal: statusOrdinal,
                createdAtMs: createdAtMs,
                acceptedAtMs: acceptedAtMs,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$FriendshipsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $FriendshipsTable,
      Friendship,
      $$FriendshipsTableFilterComposer,
      $$FriendshipsTableOrderingComposer,
      $$FriendshipsTableAnnotationComposer,
      $$FriendshipsTableCreateCompanionBuilder,
      $$FriendshipsTableUpdateCompanionBuilder,
      (
        Friendship,
        BaseReferences<_$AppDatabase, $FriendshipsTable, Friendship>,
      ),
      Friendship,
      PrefetchHooks Function()
    >;
typedef $$GroupsTableCreateCompanionBuilder =
    GroupsCompanion Function({
      Value<int> id,
      required String groupUuid,
      required String name,
      required String description,
      Value<String?> avatarUrl,
      required String createdByUserId,
      required int createdAtMs,
      required String privacyOrdinal,
      required int maxMembers,
      required int memberCount,
    });
typedef $$GroupsTableUpdateCompanionBuilder =
    GroupsCompanion Function({
      Value<int> id,
      Value<String> groupUuid,
      Value<String> name,
      Value<String> description,
      Value<String?> avatarUrl,
      Value<String> createdByUserId,
      Value<int> createdAtMs,
      Value<String> privacyOrdinal,
      Value<int> maxMembers,
      Value<int> memberCount,
    });

class $$GroupsTableFilterComposer
    extends Composer<_$AppDatabase, $GroupsTable> {
  $$GroupsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get groupUuid => $composableBuilder(
    column: $table.groupUuid,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get avatarUrl => $composableBuilder(
    column: $table.avatarUrl,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get createdByUserId => $composableBuilder(
    column: $table.createdByUserId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get createdAtMs => $composableBuilder(
    column: $table.createdAtMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get privacyOrdinal => $composableBuilder(
    column: $table.privacyOrdinal,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get maxMembers => $composableBuilder(
    column: $table.maxMembers,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get memberCount => $composableBuilder(
    column: $table.memberCount,
    builder: (column) => ColumnFilters(column),
  );
}

class $$GroupsTableOrderingComposer
    extends Composer<_$AppDatabase, $GroupsTable> {
  $$GroupsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get groupUuid => $composableBuilder(
    column: $table.groupUuid,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get avatarUrl => $composableBuilder(
    column: $table.avatarUrl,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get createdByUserId => $composableBuilder(
    column: $table.createdByUserId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get createdAtMs => $composableBuilder(
    column: $table.createdAtMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get privacyOrdinal => $composableBuilder(
    column: $table.privacyOrdinal,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get maxMembers => $composableBuilder(
    column: $table.maxMembers,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get memberCount => $composableBuilder(
    column: $table.memberCount,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$GroupsTableAnnotationComposer
    extends Composer<_$AppDatabase, $GroupsTable> {
  $$GroupsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get groupUuid =>
      $composableBuilder(column: $table.groupUuid, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => column,
  );

  GeneratedColumn<String> get avatarUrl =>
      $composableBuilder(column: $table.avatarUrl, builder: (column) => column);

  GeneratedColumn<String> get createdByUserId => $composableBuilder(
    column: $table.createdByUserId,
    builder: (column) => column,
  );

  GeneratedColumn<int> get createdAtMs => $composableBuilder(
    column: $table.createdAtMs,
    builder: (column) => column,
  );

  GeneratedColumn<String> get privacyOrdinal => $composableBuilder(
    column: $table.privacyOrdinal,
    builder: (column) => column,
  );

  GeneratedColumn<int> get maxMembers => $composableBuilder(
    column: $table.maxMembers,
    builder: (column) => column,
  );

  GeneratedColumn<int> get memberCount => $composableBuilder(
    column: $table.memberCount,
    builder: (column) => column,
  );
}

class $$GroupsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $GroupsTable,
          Group,
          $$GroupsTableFilterComposer,
          $$GroupsTableOrderingComposer,
          $$GroupsTableAnnotationComposer,
          $$GroupsTableCreateCompanionBuilder,
          $$GroupsTableUpdateCompanionBuilder,
          (Group, BaseReferences<_$AppDatabase, $GroupsTable, Group>),
          Group,
          PrefetchHooks Function()
        > {
  $$GroupsTableTableManager(_$AppDatabase db, $GroupsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$GroupsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$GroupsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$GroupsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> groupUuid = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String> description = const Value.absent(),
                Value<String?> avatarUrl = const Value.absent(),
                Value<String> createdByUserId = const Value.absent(),
                Value<int> createdAtMs = const Value.absent(),
                Value<String> privacyOrdinal = const Value.absent(),
                Value<int> maxMembers = const Value.absent(),
                Value<int> memberCount = const Value.absent(),
              }) => GroupsCompanion(
                id: id,
                groupUuid: groupUuid,
                name: name,
                description: description,
                avatarUrl: avatarUrl,
                createdByUserId: createdByUserId,
                createdAtMs: createdAtMs,
                privacyOrdinal: privacyOrdinal,
                maxMembers: maxMembers,
                memberCount: memberCount,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String groupUuid,
                required String name,
                required String description,
                Value<String?> avatarUrl = const Value.absent(),
                required String createdByUserId,
                required int createdAtMs,
                required String privacyOrdinal,
                required int maxMembers,
                required int memberCount,
              }) => GroupsCompanion.insert(
                id: id,
                groupUuid: groupUuid,
                name: name,
                description: description,
                avatarUrl: avatarUrl,
                createdByUserId: createdByUserId,
                createdAtMs: createdAtMs,
                privacyOrdinal: privacyOrdinal,
                maxMembers: maxMembers,
                memberCount: memberCount,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$GroupsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $GroupsTable,
      Group,
      $$GroupsTableFilterComposer,
      $$GroupsTableOrderingComposer,
      $$GroupsTableAnnotationComposer,
      $$GroupsTableCreateCompanionBuilder,
      $$GroupsTableUpdateCompanionBuilder,
      (Group, BaseReferences<_$AppDatabase, $GroupsTable, Group>),
      Group,
      PrefetchHooks Function()
    >;
typedef $$GroupMembersTableCreateCompanionBuilder =
    GroupMembersCompanion Function({
      Value<int> id,
      required String memberUuid,
      required String groupId,
      required String userId,
      required String displayName,
      required String roleOrdinal,
      required String statusOrdinal,
      required int joinedAtMs,
    });
typedef $$GroupMembersTableUpdateCompanionBuilder =
    GroupMembersCompanion Function({
      Value<int> id,
      Value<String> memberUuid,
      Value<String> groupId,
      Value<String> userId,
      Value<String> displayName,
      Value<String> roleOrdinal,
      Value<String> statusOrdinal,
      Value<int> joinedAtMs,
    });

class $$GroupMembersTableFilterComposer
    extends Composer<_$AppDatabase, $GroupMembersTable> {
  $$GroupMembersTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get memberUuid => $composableBuilder(
    column: $table.memberUuid,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get groupId => $composableBuilder(
    column: $table.groupId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get userId => $composableBuilder(
    column: $table.userId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get displayName => $composableBuilder(
    column: $table.displayName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get roleOrdinal => $composableBuilder(
    column: $table.roleOrdinal,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get statusOrdinal => $composableBuilder(
    column: $table.statusOrdinal,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get joinedAtMs => $composableBuilder(
    column: $table.joinedAtMs,
    builder: (column) => ColumnFilters(column),
  );
}

class $$GroupMembersTableOrderingComposer
    extends Composer<_$AppDatabase, $GroupMembersTable> {
  $$GroupMembersTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get memberUuid => $composableBuilder(
    column: $table.memberUuid,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get groupId => $composableBuilder(
    column: $table.groupId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get userId => $composableBuilder(
    column: $table.userId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get displayName => $composableBuilder(
    column: $table.displayName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get roleOrdinal => $composableBuilder(
    column: $table.roleOrdinal,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get statusOrdinal => $composableBuilder(
    column: $table.statusOrdinal,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get joinedAtMs => $composableBuilder(
    column: $table.joinedAtMs,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$GroupMembersTableAnnotationComposer
    extends Composer<_$AppDatabase, $GroupMembersTable> {
  $$GroupMembersTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get memberUuid => $composableBuilder(
    column: $table.memberUuid,
    builder: (column) => column,
  );

  GeneratedColumn<String> get groupId =>
      $composableBuilder(column: $table.groupId, builder: (column) => column);

  GeneratedColumn<String> get userId =>
      $composableBuilder(column: $table.userId, builder: (column) => column);

  GeneratedColumn<String> get displayName => $composableBuilder(
    column: $table.displayName,
    builder: (column) => column,
  );

  GeneratedColumn<String> get roleOrdinal => $composableBuilder(
    column: $table.roleOrdinal,
    builder: (column) => column,
  );

  GeneratedColumn<String> get statusOrdinal => $composableBuilder(
    column: $table.statusOrdinal,
    builder: (column) => column,
  );

  GeneratedColumn<int> get joinedAtMs => $composableBuilder(
    column: $table.joinedAtMs,
    builder: (column) => column,
  );
}

class $$GroupMembersTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $GroupMembersTable,
          GroupMember,
          $$GroupMembersTableFilterComposer,
          $$GroupMembersTableOrderingComposer,
          $$GroupMembersTableAnnotationComposer,
          $$GroupMembersTableCreateCompanionBuilder,
          $$GroupMembersTableUpdateCompanionBuilder,
          (
            GroupMember,
            BaseReferences<_$AppDatabase, $GroupMembersTable, GroupMember>,
          ),
          GroupMember,
          PrefetchHooks Function()
        > {
  $$GroupMembersTableTableManager(_$AppDatabase db, $GroupMembersTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$GroupMembersTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$GroupMembersTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$GroupMembersTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> memberUuid = const Value.absent(),
                Value<String> groupId = const Value.absent(),
                Value<String> userId = const Value.absent(),
                Value<String> displayName = const Value.absent(),
                Value<String> roleOrdinal = const Value.absent(),
                Value<String> statusOrdinal = const Value.absent(),
                Value<int> joinedAtMs = const Value.absent(),
              }) => GroupMembersCompanion(
                id: id,
                memberUuid: memberUuid,
                groupId: groupId,
                userId: userId,
                displayName: displayName,
                roleOrdinal: roleOrdinal,
                statusOrdinal: statusOrdinal,
                joinedAtMs: joinedAtMs,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String memberUuid,
                required String groupId,
                required String userId,
                required String displayName,
                required String roleOrdinal,
                required String statusOrdinal,
                required int joinedAtMs,
              }) => GroupMembersCompanion.insert(
                id: id,
                memberUuid: memberUuid,
                groupId: groupId,
                userId: userId,
                displayName: displayName,
                roleOrdinal: roleOrdinal,
                statusOrdinal: statusOrdinal,
                joinedAtMs: joinedAtMs,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$GroupMembersTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $GroupMembersTable,
      GroupMember,
      $$GroupMembersTableFilterComposer,
      $$GroupMembersTableOrderingComposer,
      $$GroupMembersTableAnnotationComposer,
      $$GroupMembersTableCreateCompanionBuilder,
      $$GroupMembersTableUpdateCompanionBuilder,
      (
        GroupMember,
        BaseReferences<_$AppDatabase, $GroupMembersTable, GroupMember>,
      ),
      GroupMember,
      PrefetchHooks Function()
    >;
typedef $$GroupGoalsTableCreateCompanionBuilder =
    GroupGoalsCompanion Function({
      Value<int> id,
      required String goalUuid,
      required String groupId,
      required String title,
      required String description,
      required double targetValue,
      required double currentValue,
      required String metricOrdinal,
      required int startsAtMs,
      required int endsAtMs,
      required String createdByUserId,
      required String statusOrdinal,
    });
typedef $$GroupGoalsTableUpdateCompanionBuilder =
    GroupGoalsCompanion Function({
      Value<int> id,
      Value<String> goalUuid,
      Value<String> groupId,
      Value<String> title,
      Value<String> description,
      Value<double> targetValue,
      Value<double> currentValue,
      Value<String> metricOrdinal,
      Value<int> startsAtMs,
      Value<int> endsAtMs,
      Value<String> createdByUserId,
      Value<String> statusOrdinal,
    });

class $$GroupGoalsTableFilterComposer
    extends Composer<_$AppDatabase, $GroupGoalsTable> {
  $$GroupGoalsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get goalUuid => $composableBuilder(
    column: $table.goalUuid,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get groupId => $composableBuilder(
    column: $table.groupId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get targetValue => $composableBuilder(
    column: $table.targetValue,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get currentValue => $composableBuilder(
    column: $table.currentValue,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get metricOrdinal => $composableBuilder(
    column: $table.metricOrdinal,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get startsAtMs => $composableBuilder(
    column: $table.startsAtMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get endsAtMs => $composableBuilder(
    column: $table.endsAtMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get createdByUserId => $composableBuilder(
    column: $table.createdByUserId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get statusOrdinal => $composableBuilder(
    column: $table.statusOrdinal,
    builder: (column) => ColumnFilters(column),
  );
}

class $$GroupGoalsTableOrderingComposer
    extends Composer<_$AppDatabase, $GroupGoalsTable> {
  $$GroupGoalsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get goalUuid => $composableBuilder(
    column: $table.goalUuid,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get groupId => $composableBuilder(
    column: $table.groupId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get targetValue => $composableBuilder(
    column: $table.targetValue,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get currentValue => $composableBuilder(
    column: $table.currentValue,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get metricOrdinal => $composableBuilder(
    column: $table.metricOrdinal,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get startsAtMs => $composableBuilder(
    column: $table.startsAtMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get endsAtMs => $composableBuilder(
    column: $table.endsAtMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get createdByUserId => $composableBuilder(
    column: $table.createdByUserId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get statusOrdinal => $composableBuilder(
    column: $table.statusOrdinal,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$GroupGoalsTableAnnotationComposer
    extends Composer<_$AppDatabase, $GroupGoalsTable> {
  $$GroupGoalsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get goalUuid =>
      $composableBuilder(column: $table.goalUuid, builder: (column) => column);

  GeneratedColumn<String> get groupId =>
      $composableBuilder(column: $table.groupId, builder: (column) => column);

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => column,
  );

  GeneratedColumn<double> get targetValue => $composableBuilder(
    column: $table.targetValue,
    builder: (column) => column,
  );

  GeneratedColumn<double> get currentValue => $composableBuilder(
    column: $table.currentValue,
    builder: (column) => column,
  );

  GeneratedColumn<String> get metricOrdinal => $composableBuilder(
    column: $table.metricOrdinal,
    builder: (column) => column,
  );

  GeneratedColumn<int> get startsAtMs => $composableBuilder(
    column: $table.startsAtMs,
    builder: (column) => column,
  );

  GeneratedColumn<int> get endsAtMs =>
      $composableBuilder(column: $table.endsAtMs, builder: (column) => column);

  GeneratedColumn<String> get createdByUserId => $composableBuilder(
    column: $table.createdByUserId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get statusOrdinal => $composableBuilder(
    column: $table.statusOrdinal,
    builder: (column) => column,
  );
}

class $$GroupGoalsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $GroupGoalsTable,
          GroupGoal,
          $$GroupGoalsTableFilterComposer,
          $$GroupGoalsTableOrderingComposer,
          $$GroupGoalsTableAnnotationComposer,
          $$GroupGoalsTableCreateCompanionBuilder,
          $$GroupGoalsTableUpdateCompanionBuilder,
          (
            GroupGoal,
            BaseReferences<_$AppDatabase, $GroupGoalsTable, GroupGoal>,
          ),
          GroupGoal,
          PrefetchHooks Function()
        > {
  $$GroupGoalsTableTableManager(_$AppDatabase db, $GroupGoalsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$GroupGoalsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$GroupGoalsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$GroupGoalsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> goalUuid = const Value.absent(),
                Value<String> groupId = const Value.absent(),
                Value<String> title = const Value.absent(),
                Value<String> description = const Value.absent(),
                Value<double> targetValue = const Value.absent(),
                Value<double> currentValue = const Value.absent(),
                Value<String> metricOrdinal = const Value.absent(),
                Value<int> startsAtMs = const Value.absent(),
                Value<int> endsAtMs = const Value.absent(),
                Value<String> createdByUserId = const Value.absent(),
                Value<String> statusOrdinal = const Value.absent(),
              }) => GroupGoalsCompanion(
                id: id,
                goalUuid: goalUuid,
                groupId: groupId,
                title: title,
                description: description,
                targetValue: targetValue,
                currentValue: currentValue,
                metricOrdinal: metricOrdinal,
                startsAtMs: startsAtMs,
                endsAtMs: endsAtMs,
                createdByUserId: createdByUserId,
                statusOrdinal: statusOrdinal,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String goalUuid,
                required String groupId,
                required String title,
                required String description,
                required double targetValue,
                required double currentValue,
                required String metricOrdinal,
                required int startsAtMs,
                required int endsAtMs,
                required String createdByUserId,
                required String statusOrdinal,
              }) => GroupGoalsCompanion.insert(
                id: id,
                goalUuid: goalUuid,
                groupId: groupId,
                title: title,
                description: description,
                targetValue: targetValue,
                currentValue: currentValue,
                metricOrdinal: metricOrdinal,
                startsAtMs: startsAtMs,
                endsAtMs: endsAtMs,
                createdByUserId: createdByUserId,
                statusOrdinal: statusOrdinal,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$GroupGoalsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $GroupGoalsTable,
      GroupGoal,
      $$GroupGoalsTableFilterComposer,
      $$GroupGoalsTableOrderingComposer,
      $$GroupGoalsTableAnnotationComposer,
      $$GroupGoalsTableCreateCompanionBuilder,
      $$GroupGoalsTableUpdateCompanionBuilder,
      (GroupGoal, BaseReferences<_$AppDatabase, $GroupGoalsTable, GroupGoal>),
      GroupGoal,
      PrefetchHooks Function()
    >;
typedef $$EventsTableCreateCompanionBuilder =
    EventsCompanion Function({
      Value<int> id,
      required String eventUuid,
      required String title,
      required String description,
      Value<String?> imageUrl,
      required String typeOrdinal,
      required String metricOrdinal,
      Value<double?> targetValue,
      required int startsAtMs,
      required int endsAtMs,
      Value<int?> maxParticipants,
      required bool createdBySystem,
      Value<String?> creatorUserId,
      required int rewardXpCompletion,
      required int rewardCoinsCompletion,
      required int rewardXpParticipation,
      Value<String?> rewardBadgeId,
      required String statusOrdinal,
    });
typedef $$EventsTableUpdateCompanionBuilder =
    EventsCompanion Function({
      Value<int> id,
      Value<String> eventUuid,
      Value<String> title,
      Value<String> description,
      Value<String?> imageUrl,
      Value<String> typeOrdinal,
      Value<String> metricOrdinal,
      Value<double?> targetValue,
      Value<int> startsAtMs,
      Value<int> endsAtMs,
      Value<int?> maxParticipants,
      Value<bool> createdBySystem,
      Value<String?> creatorUserId,
      Value<int> rewardXpCompletion,
      Value<int> rewardCoinsCompletion,
      Value<int> rewardXpParticipation,
      Value<String?> rewardBadgeId,
      Value<String> statusOrdinal,
    });

class $$EventsTableFilterComposer
    extends Composer<_$AppDatabase, $EventsTable> {
  $$EventsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get eventUuid => $composableBuilder(
    column: $table.eventUuid,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get imageUrl => $composableBuilder(
    column: $table.imageUrl,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get typeOrdinal => $composableBuilder(
    column: $table.typeOrdinal,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get metricOrdinal => $composableBuilder(
    column: $table.metricOrdinal,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get targetValue => $composableBuilder(
    column: $table.targetValue,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get startsAtMs => $composableBuilder(
    column: $table.startsAtMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get endsAtMs => $composableBuilder(
    column: $table.endsAtMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get maxParticipants => $composableBuilder(
    column: $table.maxParticipants,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get createdBySystem => $composableBuilder(
    column: $table.createdBySystem,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get creatorUserId => $composableBuilder(
    column: $table.creatorUserId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get rewardXpCompletion => $composableBuilder(
    column: $table.rewardXpCompletion,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get rewardCoinsCompletion => $composableBuilder(
    column: $table.rewardCoinsCompletion,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get rewardXpParticipation => $composableBuilder(
    column: $table.rewardXpParticipation,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get rewardBadgeId => $composableBuilder(
    column: $table.rewardBadgeId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get statusOrdinal => $composableBuilder(
    column: $table.statusOrdinal,
    builder: (column) => ColumnFilters(column),
  );
}

class $$EventsTableOrderingComposer
    extends Composer<_$AppDatabase, $EventsTable> {
  $$EventsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get eventUuid => $composableBuilder(
    column: $table.eventUuid,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get imageUrl => $composableBuilder(
    column: $table.imageUrl,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get typeOrdinal => $composableBuilder(
    column: $table.typeOrdinal,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get metricOrdinal => $composableBuilder(
    column: $table.metricOrdinal,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get targetValue => $composableBuilder(
    column: $table.targetValue,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get startsAtMs => $composableBuilder(
    column: $table.startsAtMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get endsAtMs => $composableBuilder(
    column: $table.endsAtMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get maxParticipants => $composableBuilder(
    column: $table.maxParticipants,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get createdBySystem => $composableBuilder(
    column: $table.createdBySystem,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get creatorUserId => $composableBuilder(
    column: $table.creatorUserId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get rewardXpCompletion => $composableBuilder(
    column: $table.rewardXpCompletion,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get rewardCoinsCompletion => $composableBuilder(
    column: $table.rewardCoinsCompletion,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get rewardXpParticipation => $composableBuilder(
    column: $table.rewardXpParticipation,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get rewardBadgeId => $composableBuilder(
    column: $table.rewardBadgeId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get statusOrdinal => $composableBuilder(
    column: $table.statusOrdinal,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$EventsTableAnnotationComposer
    extends Composer<_$AppDatabase, $EventsTable> {
  $$EventsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get eventUuid =>
      $composableBuilder(column: $table.eventUuid, builder: (column) => column);

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => column,
  );

  GeneratedColumn<String> get imageUrl =>
      $composableBuilder(column: $table.imageUrl, builder: (column) => column);

  GeneratedColumn<String> get typeOrdinal => $composableBuilder(
    column: $table.typeOrdinal,
    builder: (column) => column,
  );

  GeneratedColumn<String> get metricOrdinal => $composableBuilder(
    column: $table.metricOrdinal,
    builder: (column) => column,
  );

  GeneratedColumn<double> get targetValue => $composableBuilder(
    column: $table.targetValue,
    builder: (column) => column,
  );

  GeneratedColumn<int> get startsAtMs => $composableBuilder(
    column: $table.startsAtMs,
    builder: (column) => column,
  );

  GeneratedColumn<int> get endsAtMs =>
      $composableBuilder(column: $table.endsAtMs, builder: (column) => column);

  GeneratedColumn<int> get maxParticipants => $composableBuilder(
    column: $table.maxParticipants,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get createdBySystem => $composableBuilder(
    column: $table.createdBySystem,
    builder: (column) => column,
  );

  GeneratedColumn<String> get creatorUserId => $composableBuilder(
    column: $table.creatorUserId,
    builder: (column) => column,
  );

  GeneratedColumn<int> get rewardXpCompletion => $composableBuilder(
    column: $table.rewardXpCompletion,
    builder: (column) => column,
  );

  GeneratedColumn<int> get rewardCoinsCompletion => $composableBuilder(
    column: $table.rewardCoinsCompletion,
    builder: (column) => column,
  );

  GeneratedColumn<int> get rewardXpParticipation => $composableBuilder(
    column: $table.rewardXpParticipation,
    builder: (column) => column,
  );

  GeneratedColumn<String> get rewardBadgeId => $composableBuilder(
    column: $table.rewardBadgeId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get statusOrdinal => $composableBuilder(
    column: $table.statusOrdinal,
    builder: (column) => column,
  );
}

class $$EventsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $EventsTable,
          Event,
          $$EventsTableFilterComposer,
          $$EventsTableOrderingComposer,
          $$EventsTableAnnotationComposer,
          $$EventsTableCreateCompanionBuilder,
          $$EventsTableUpdateCompanionBuilder,
          (Event, BaseReferences<_$AppDatabase, $EventsTable, Event>),
          Event,
          PrefetchHooks Function()
        > {
  $$EventsTableTableManager(_$AppDatabase db, $EventsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$EventsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$EventsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$EventsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> eventUuid = const Value.absent(),
                Value<String> title = const Value.absent(),
                Value<String> description = const Value.absent(),
                Value<String?> imageUrl = const Value.absent(),
                Value<String> typeOrdinal = const Value.absent(),
                Value<String> metricOrdinal = const Value.absent(),
                Value<double?> targetValue = const Value.absent(),
                Value<int> startsAtMs = const Value.absent(),
                Value<int> endsAtMs = const Value.absent(),
                Value<int?> maxParticipants = const Value.absent(),
                Value<bool> createdBySystem = const Value.absent(),
                Value<String?> creatorUserId = const Value.absent(),
                Value<int> rewardXpCompletion = const Value.absent(),
                Value<int> rewardCoinsCompletion = const Value.absent(),
                Value<int> rewardXpParticipation = const Value.absent(),
                Value<String?> rewardBadgeId = const Value.absent(),
                Value<String> statusOrdinal = const Value.absent(),
              }) => EventsCompanion(
                id: id,
                eventUuid: eventUuid,
                title: title,
                description: description,
                imageUrl: imageUrl,
                typeOrdinal: typeOrdinal,
                metricOrdinal: metricOrdinal,
                targetValue: targetValue,
                startsAtMs: startsAtMs,
                endsAtMs: endsAtMs,
                maxParticipants: maxParticipants,
                createdBySystem: createdBySystem,
                creatorUserId: creatorUserId,
                rewardXpCompletion: rewardXpCompletion,
                rewardCoinsCompletion: rewardCoinsCompletion,
                rewardXpParticipation: rewardXpParticipation,
                rewardBadgeId: rewardBadgeId,
                statusOrdinal: statusOrdinal,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String eventUuid,
                required String title,
                required String description,
                Value<String?> imageUrl = const Value.absent(),
                required String typeOrdinal,
                required String metricOrdinal,
                Value<double?> targetValue = const Value.absent(),
                required int startsAtMs,
                required int endsAtMs,
                Value<int?> maxParticipants = const Value.absent(),
                required bool createdBySystem,
                Value<String?> creatorUserId = const Value.absent(),
                required int rewardXpCompletion,
                required int rewardCoinsCompletion,
                required int rewardXpParticipation,
                Value<String?> rewardBadgeId = const Value.absent(),
                required String statusOrdinal,
              }) => EventsCompanion.insert(
                id: id,
                eventUuid: eventUuid,
                title: title,
                description: description,
                imageUrl: imageUrl,
                typeOrdinal: typeOrdinal,
                metricOrdinal: metricOrdinal,
                targetValue: targetValue,
                startsAtMs: startsAtMs,
                endsAtMs: endsAtMs,
                maxParticipants: maxParticipants,
                createdBySystem: createdBySystem,
                creatorUserId: creatorUserId,
                rewardXpCompletion: rewardXpCompletion,
                rewardCoinsCompletion: rewardCoinsCompletion,
                rewardXpParticipation: rewardXpParticipation,
                rewardBadgeId: rewardBadgeId,
                statusOrdinal: statusOrdinal,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$EventsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $EventsTable,
      Event,
      $$EventsTableFilterComposer,
      $$EventsTableOrderingComposer,
      $$EventsTableAnnotationComposer,
      $$EventsTableCreateCompanionBuilder,
      $$EventsTableUpdateCompanionBuilder,
      (Event, BaseReferences<_$AppDatabase, $EventsTable, Event>),
      Event,
      PrefetchHooks Function()
    >;
typedef $$EventParticipationsTableCreateCompanionBuilder =
    EventParticipationsCompanion Function({
      Value<int> id,
      required String participationUuid,
      required String eventId,
      required String userId,
      required String displayName,
      required int joinedAtMs,
      required double currentValue,
      Value<int?> rank,
      required bool completed,
      Value<int?> completedAtMs,
      required int contributingSessionCount,
      required String contributingSessionIdsCsv,
      required bool rewardsClaimed,
    });
typedef $$EventParticipationsTableUpdateCompanionBuilder =
    EventParticipationsCompanion Function({
      Value<int> id,
      Value<String> participationUuid,
      Value<String> eventId,
      Value<String> userId,
      Value<String> displayName,
      Value<int> joinedAtMs,
      Value<double> currentValue,
      Value<int?> rank,
      Value<bool> completed,
      Value<int?> completedAtMs,
      Value<int> contributingSessionCount,
      Value<String> contributingSessionIdsCsv,
      Value<bool> rewardsClaimed,
    });

class $$EventParticipationsTableFilterComposer
    extends Composer<_$AppDatabase, $EventParticipationsTable> {
  $$EventParticipationsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get participationUuid => $composableBuilder(
    column: $table.participationUuid,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get eventId => $composableBuilder(
    column: $table.eventId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get userId => $composableBuilder(
    column: $table.userId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get displayName => $composableBuilder(
    column: $table.displayName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get joinedAtMs => $composableBuilder(
    column: $table.joinedAtMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get currentValue => $composableBuilder(
    column: $table.currentValue,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get rank => $composableBuilder(
    column: $table.rank,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get completed => $composableBuilder(
    column: $table.completed,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get completedAtMs => $composableBuilder(
    column: $table.completedAtMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get contributingSessionCount => $composableBuilder(
    column: $table.contributingSessionCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get contributingSessionIdsCsv => $composableBuilder(
    column: $table.contributingSessionIdsCsv,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get rewardsClaimed => $composableBuilder(
    column: $table.rewardsClaimed,
    builder: (column) => ColumnFilters(column),
  );
}

class $$EventParticipationsTableOrderingComposer
    extends Composer<_$AppDatabase, $EventParticipationsTable> {
  $$EventParticipationsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get participationUuid => $composableBuilder(
    column: $table.participationUuid,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get eventId => $composableBuilder(
    column: $table.eventId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get userId => $composableBuilder(
    column: $table.userId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get displayName => $composableBuilder(
    column: $table.displayName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get joinedAtMs => $composableBuilder(
    column: $table.joinedAtMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get currentValue => $composableBuilder(
    column: $table.currentValue,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get rank => $composableBuilder(
    column: $table.rank,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get completed => $composableBuilder(
    column: $table.completed,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get completedAtMs => $composableBuilder(
    column: $table.completedAtMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get contributingSessionCount => $composableBuilder(
    column: $table.contributingSessionCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get contributingSessionIdsCsv => $composableBuilder(
    column: $table.contributingSessionIdsCsv,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get rewardsClaimed => $composableBuilder(
    column: $table.rewardsClaimed,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$EventParticipationsTableAnnotationComposer
    extends Composer<_$AppDatabase, $EventParticipationsTable> {
  $$EventParticipationsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get participationUuid => $composableBuilder(
    column: $table.participationUuid,
    builder: (column) => column,
  );

  GeneratedColumn<String> get eventId =>
      $composableBuilder(column: $table.eventId, builder: (column) => column);

  GeneratedColumn<String> get userId =>
      $composableBuilder(column: $table.userId, builder: (column) => column);

  GeneratedColumn<String> get displayName => $composableBuilder(
    column: $table.displayName,
    builder: (column) => column,
  );

  GeneratedColumn<int> get joinedAtMs => $composableBuilder(
    column: $table.joinedAtMs,
    builder: (column) => column,
  );

  GeneratedColumn<double> get currentValue => $composableBuilder(
    column: $table.currentValue,
    builder: (column) => column,
  );

  GeneratedColumn<int> get rank =>
      $composableBuilder(column: $table.rank, builder: (column) => column);

  GeneratedColumn<bool> get completed =>
      $composableBuilder(column: $table.completed, builder: (column) => column);

  GeneratedColumn<int> get completedAtMs => $composableBuilder(
    column: $table.completedAtMs,
    builder: (column) => column,
  );

  GeneratedColumn<int> get contributingSessionCount => $composableBuilder(
    column: $table.contributingSessionCount,
    builder: (column) => column,
  );

  GeneratedColumn<String> get contributingSessionIdsCsv => $composableBuilder(
    column: $table.contributingSessionIdsCsv,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get rewardsClaimed => $composableBuilder(
    column: $table.rewardsClaimed,
    builder: (column) => column,
  );
}

class $$EventParticipationsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $EventParticipationsTable,
          EventParticipation,
          $$EventParticipationsTableFilterComposer,
          $$EventParticipationsTableOrderingComposer,
          $$EventParticipationsTableAnnotationComposer,
          $$EventParticipationsTableCreateCompanionBuilder,
          $$EventParticipationsTableUpdateCompanionBuilder,
          (
            EventParticipation,
            BaseReferences<
              _$AppDatabase,
              $EventParticipationsTable,
              EventParticipation
            >,
          ),
          EventParticipation,
          PrefetchHooks Function()
        > {
  $$EventParticipationsTableTableManager(
    _$AppDatabase db,
    $EventParticipationsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$EventParticipationsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$EventParticipationsTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$EventParticipationsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> participationUuid = const Value.absent(),
                Value<String> eventId = const Value.absent(),
                Value<String> userId = const Value.absent(),
                Value<String> displayName = const Value.absent(),
                Value<int> joinedAtMs = const Value.absent(),
                Value<double> currentValue = const Value.absent(),
                Value<int?> rank = const Value.absent(),
                Value<bool> completed = const Value.absent(),
                Value<int?> completedAtMs = const Value.absent(),
                Value<int> contributingSessionCount = const Value.absent(),
                Value<String> contributingSessionIdsCsv = const Value.absent(),
                Value<bool> rewardsClaimed = const Value.absent(),
              }) => EventParticipationsCompanion(
                id: id,
                participationUuid: participationUuid,
                eventId: eventId,
                userId: userId,
                displayName: displayName,
                joinedAtMs: joinedAtMs,
                currentValue: currentValue,
                rank: rank,
                completed: completed,
                completedAtMs: completedAtMs,
                contributingSessionCount: contributingSessionCount,
                contributingSessionIdsCsv: contributingSessionIdsCsv,
                rewardsClaimed: rewardsClaimed,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String participationUuid,
                required String eventId,
                required String userId,
                required String displayName,
                required int joinedAtMs,
                required double currentValue,
                Value<int?> rank = const Value.absent(),
                required bool completed,
                Value<int?> completedAtMs = const Value.absent(),
                required int contributingSessionCount,
                required String contributingSessionIdsCsv,
                required bool rewardsClaimed,
              }) => EventParticipationsCompanion.insert(
                id: id,
                participationUuid: participationUuid,
                eventId: eventId,
                userId: userId,
                displayName: displayName,
                joinedAtMs: joinedAtMs,
                currentValue: currentValue,
                rank: rank,
                completed: completed,
                completedAtMs: completedAtMs,
                contributingSessionCount: contributingSessionCount,
                contributingSessionIdsCsv: contributingSessionIdsCsv,
                rewardsClaimed: rewardsClaimed,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$EventParticipationsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $EventParticipationsTable,
      EventParticipation,
      $$EventParticipationsTableFilterComposer,
      $$EventParticipationsTableOrderingComposer,
      $$EventParticipationsTableAnnotationComposer,
      $$EventParticipationsTableCreateCompanionBuilder,
      $$EventParticipationsTableUpdateCompanionBuilder,
      (
        EventParticipation,
        BaseReferences<
          _$AppDatabase,
          $EventParticipationsTable,
          EventParticipation
        >,
      ),
      EventParticipation,
      PrefetchHooks Function()
    >;
typedef $$LeaderboardSnapshotsTableCreateCompanionBuilder =
    LeaderboardSnapshotsCompanion Function({
      Value<int> id,
      required String snapshotUuid,
      required String scopeOrdinal,
      Value<String?> groupId,
      required String periodOrdinal,
      required String metricOrdinal,
      required String periodKey,
      required int computedAtMs,
      required bool isFinal,
    });
typedef $$LeaderboardSnapshotsTableUpdateCompanionBuilder =
    LeaderboardSnapshotsCompanion Function({
      Value<int> id,
      Value<String> snapshotUuid,
      Value<String> scopeOrdinal,
      Value<String?> groupId,
      Value<String> periodOrdinal,
      Value<String> metricOrdinal,
      Value<String> periodKey,
      Value<int> computedAtMs,
      Value<bool> isFinal,
    });

class $$LeaderboardSnapshotsTableFilterComposer
    extends Composer<_$AppDatabase, $LeaderboardSnapshotsTable> {
  $$LeaderboardSnapshotsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get snapshotUuid => $composableBuilder(
    column: $table.snapshotUuid,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get scopeOrdinal => $composableBuilder(
    column: $table.scopeOrdinal,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get groupId => $composableBuilder(
    column: $table.groupId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get periodOrdinal => $composableBuilder(
    column: $table.periodOrdinal,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get metricOrdinal => $composableBuilder(
    column: $table.metricOrdinal,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get periodKey => $composableBuilder(
    column: $table.periodKey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get computedAtMs => $composableBuilder(
    column: $table.computedAtMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isFinal => $composableBuilder(
    column: $table.isFinal,
    builder: (column) => ColumnFilters(column),
  );
}

class $$LeaderboardSnapshotsTableOrderingComposer
    extends Composer<_$AppDatabase, $LeaderboardSnapshotsTable> {
  $$LeaderboardSnapshotsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get snapshotUuid => $composableBuilder(
    column: $table.snapshotUuid,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get scopeOrdinal => $composableBuilder(
    column: $table.scopeOrdinal,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get groupId => $composableBuilder(
    column: $table.groupId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get periodOrdinal => $composableBuilder(
    column: $table.periodOrdinal,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get metricOrdinal => $composableBuilder(
    column: $table.metricOrdinal,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get periodKey => $composableBuilder(
    column: $table.periodKey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get computedAtMs => $composableBuilder(
    column: $table.computedAtMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isFinal => $composableBuilder(
    column: $table.isFinal,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$LeaderboardSnapshotsTableAnnotationComposer
    extends Composer<_$AppDatabase, $LeaderboardSnapshotsTable> {
  $$LeaderboardSnapshotsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get snapshotUuid => $composableBuilder(
    column: $table.snapshotUuid,
    builder: (column) => column,
  );

  GeneratedColumn<String> get scopeOrdinal => $composableBuilder(
    column: $table.scopeOrdinal,
    builder: (column) => column,
  );

  GeneratedColumn<String> get groupId =>
      $composableBuilder(column: $table.groupId, builder: (column) => column);

  GeneratedColumn<String> get periodOrdinal => $composableBuilder(
    column: $table.periodOrdinal,
    builder: (column) => column,
  );

  GeneratedColumn<String> get metricOrdinal => $composableBuilder(
    column: $table.metricOrdinal,
    builder: (column) => column,
  );

  GeneratedColumn<String> get periodKey =>
      $composableBuilder(column: $table.periodKey, builder: (column) => column);

  GeneratedColumn<int> get computedAtMs => $composableBuilder(
    column: $table.computedAtMs,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get isFinal =>
      $composableBuilder(column: $table.isFinal, builder: (column) => column);
}

class $$LeaderboardSnapshotsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $LeaderboardSnapshotsTable,
          LeaderboardSnapshot,
          $$LeaderboardSnapshotsTableFilterComposer,
          $$LeaderboardSnapshotsTableOrderingComposer,
          $$LeaderboardSnapshotsTableAnnotationComposer,
          $$LeaderboardSnapshotsTableCreateCompanionBuilder,
          $$LeaderboardSnapshotsTableUpdateCompanionBuilder,
          (
            LeaderboardSnapshot,
            BaseReferences<
              _$AppDatabase,
              $LeaderboardSnapshotsTable,
              LeaderboardSnapshot
            >,
          ),
          LeaderboardSnapshot,
          PrefetchHooks Function()
        > {
  $$LeaderboardSnapshotsTableTableManager(
    _$AppDatabase db,
    $LeaderboardSnapshotsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$LeaderboardSnapshotsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$LeaderboardSnapshotsTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$LeaderboardSnapshotsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> snapshotUuid = const Value.absent(),
                Value<String> scopeOrdinal = const Value.absent(),
                Value<String?> groupId = const Value.absent(),
                Value<String> periodOrdinal = const Value.absent(),
                Value<String> metricOrdinal = const Value.absent(),
                Value<String> periodKey = const Value.absent(),
                Value<int> computedAtMs = const Value.absent(),
                Value<bool> isFinal = const Value.absent(),
              }) => LeaderboardSnapshotsCompanion(
                id: id,
                snapshotUuid: snapshotUuid,
                scopeOrdinal: scopeOrdinal,
                groupId: groupId,
                periodOrdinal: periodOrdinal,
                metricOrdinal: metricOrdinal,
                periodKey: periodKey,
                computedAtMs: computedAtMs,
                isFinal: isFinal,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String snapshotUuid,
                required String scopeOrdinal,
                Value<String?> groupId = const Value.absent(),
                required String periodOrdinal,
                required String metricOrdinal,
                required String periodKey,
                required int computedAtMs,
                required bool isFinal,
              }) => LeaderboardSnapshotsCompanion.insert(
                id: id,
                snapshotUuid: snapshotUuid,
                scopeOrdinal: scopeOrdinal,
                groupId: groupId,
                periodOrdinal: periodOrdinal,
                metricOrdinal: metricOrdinal,
                periodKey: periodKey,
                computedAtMs: computedAtMs,
                isFinal: isFinal,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$LeaderboardSnapshotsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $LeaderboardSnapshotsTable,
      LeaderboardSnapshot,
      $$LeaderboardSnapshotsTableFilterComposer,
      $$LeaderboardSnapshotsTableOrderingComposer,
      $$LeaderboardSnapshotsTableAnnotationComposer,
      $$LeaderboardSnapshotsTableCreateCompanionBuilder,
      $$LeaderboardSnapshotsTableUpdateCompanionBuilder,
      (
        LeaderboardSnapshot,
        BaseReferences<
          _$AppDatabase,
          $LeaderboardSnapshotsTable,
          LeaderboardSnapshot
        >,
      ),
      LeaderboardSnapshot,
      PrefetchHooks Function()
    >;
typedef $$LeaderboardEntriesTableCreateCompanionBuilder =
    LeaderboardEntriesCompanion Function({
      Value<int> id,
      required String snapshotId,
      required String userId,
      required String displayName,
      Value<String?> avatarUrl,
      required int level,
      required double value,
      required int rank,
      required String periodKey,
    });
typedef $$LeaderboardEntriesTableUpdateCompanionBuilder =
    LeaderboardEntriesCompanion Function({
      Value<int> id,
      Value<String> snapshotId,
      Value<String> userId,
      Value<String> displayName,
      Value<String?> avatarUrl,
      Value<int> level,
      Value<double> value,
      Value<int> rank,
      Value<String> periodKey,
    });

class $$LeaderboardEntriesTableFilterComposer
    extends Composer<_$AppDatabase, $LeaderboardEntriesTable> {
  $$LeaderboardEntriesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get snapshotId => $composableBuilder(
    column: $table.snapshotId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get userId => $composableBuilder(
    column: $table.userId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get displayName => $composableBuilder(
    column: $table.displayName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get avatarUrl => $composableBuilder(
    column: $table.avatarUrl,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get level => $composableBuilder(
    column: $table.level,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get rank => $composableBuilder(
    column: $table.rank,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get periodKey => $composableBuilder(
    column: $table.periodKey,
    builder: (column) => ColumnFilters(column),
  );
}

class $$LeaderboardEntriesTableOrderingComposer
    extends Composer<_$AppDatabase, $LeaderboardEntriesTable> {
  $$LeaderboardEntriesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get snapshotId => $composableBuilder(
    column: $table.snapshotId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get userId => $composableBuilder(
    column: $table.userId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get displayName => $composableBuilder(
    column: $table.displayName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get avatarUrl => $composableBuilder(
    column: $table.avatarUrl,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get level => $composableBuilder(
    column: $table.level,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get rank => $composableBuilder(
    column: $table.rank,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get periodKey => $composableBuilder(
    column: $table.periodKey,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$LeaderboardEntriesTableAnnotationComposer
    extends Composer<_$AppDatabase, $LeaderboardEntriesTable> {
  $$LeaderboardEntriesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get snapshotId => $composableBuilder(
    column: $table.snapshotId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get userId =>
      $composableBuilder(column: $table.userId, builder: (column) => column);

  GeneratedColumn<String> get displayName => $composableBuilder(
    column: $table.displayName,
    builder: (column) => column,
  );

  GeneratedColumn<String> get avatarUrl =>
      $composableBuilder(column: $table.avatarUrl, builder: (column) => column);

  GeneratedColumn<int> get level =>
      $composableBuilder(column: $table.level, builder: (column) => column);

  GeneratedColumn<double> get value =>
      $composableBuilder(column: $table.value, builder: (column) => column);

  GeneratedColumn<int> get rank =>
      $composableBuilder(column: $table.rank, builder: (column) => column);

  GeneratedColumn<String> get periodKey =>
      $composableBuilder(column: $table.periodKey, builder: (column) => column);
}

class $$LeaderboardEntriesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $LeaderboardEntriesTable,
          LeaderboardEntry,
          $$LeaderboardEntriesTableFilterComposer,
          $$LeaderboardEntriesTableOrderingComposer,
          $$LeaderboardEntriesTableAnnotationComposer,
          $$LeaderboardEntriesTableCreateCompanionBuilder,
          $$LeaderboardEntriesTableUpdateCompanionBuilder,
          (
            LeaderboardEntry,
            BaseReferences<
              _$AppDatabase,
              $LeaderboardEntriesTable,
              LeaderboardEntry
            >,
          ),
          LeaderboardEntry,
          PrefetchHooks Function()
        > {
  $$LeaderboardEntriesTableTableManager(
    _$AppDatabase db,
    $LeaderboardEntriesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$LeaderboardEntriesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$LeaderboardEntriesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$LeaderboardEntriesTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> snapshotId = const Value.absent(),
                Value<String> userId = const Value.absent(),
                Value<String> displayName = const Value.absent(),
                Value<String?> avatarUrl = const Value.absent(),
                Value<int> level = const Value.absent(),
                Value<double> value = const Value.absent(),
                Value<int> rank = const Value.absent(),
                Value<String> periodKey = const Value.absent(),
              }) => LeaderboardEntriesCompanion(
                id: id,
                snapshotId: snapshotId,
                userId: userId,
                displayName: displayName,
                avatarUrl: avatarUrl,
                level: level,
                value: value,
                rank: rank,
                periodKey: periodKey,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String snapshotId,
                required String userId,
                required String displayName,
                Value<String?> avatarUrl = const Value.absent(),
                required int level,
                required double value,
                required int rank,
                required String periodKey,
              }) => LeaderboardEntriesCompanion.insert(
                id: id,
                snapshotId: snapshotId,
                userId: userId,
                displayName: displayName,
                avatarUrl: avatarUrl,
                level: level,
                value: value,
                rank: rank,
                periodKey: periodKey,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$LeaderboardEntriesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $LeaderboardEntriesTable,
      LeaderboardEntry,
      $$LeaderboardEntriesTableFilterComposer,
      $$LeaderboardEntriesTableOrderingComposer,
      $$LeaderboardEntriesTableAnnotationComposer,
      $$LeaderboardEntriesTableCreateCompanionBuilder,
      $$LeaderboardEntriesTableUpdateCompanionBuilder,
      (
        LeaderboardEntry,
        BaseReferences<
          _$AppDatabase,
          $LeaderboardEntriesTable,
          LeaderboardEntry
        >,
      ),
      LeaderboardEntry,
      PrefetchHooks Function()
    >;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$LocationPointsTableTableManager get locationPoints =>
      $$LocationPointsTableTableManager(_db, _db.locationPoints);
  $$WorkoutSessionsTableTableManager get workoutSessions =>
      $$WorkoutSessionsTableTableManager(_db, _db.workoutSessions);
  $$ChallengesTableTableManager get challenges =>
      $$ChallengesTableTableManager(_db, _db.challenges);
  $$ChallengeResultsTableTableManager get challengeResults =>
      $$ChallengeResultsTableTableManager(_db, _db.challengeResults);
  $$WalletsTableTableManager get wallets =>
      $$WalletsTableTableManager(_db, _db.wallets);
  $$LedgerEntriesTableTableManager get ledgerEntries =>
      $$LedgerEntriesTableTableManager(_db, _db.ledgerEntries);
  $$ProfileProgressesTableTableManager get profileProgresses =>
      $$ProfileProgressesTableTableManager(_db, _db.profileProgresses);
  $$XpTransactionsTableTableManager get xpTransactions =>
      $$XpTransactionsTableTableManager(_db, _db.xpTransactions);
  $$BadgeAwardsTableTableManager get badgeAwards =>
      $$BadgeAwardsTableTableManager(_db, _db.badgeAwards);
  $$MissionProgressesTableTableManager get missionProgresses =>
      $$MissionProgressesTableTableManager(_db, _db.missionProgresses);
  $$SeasonsTableTableManager get seasons =>
      $$SeasonsTableTableManager(_db, _db.seasons);
  $$SeasonProgressesTableTableManager get seasonProgresses =>
      $$SeasonProgressesTableTableManager(_db, _db.seasonProgresses);
  $$CoachingGroupsTableTableManager get coachingGroups =>
      $$CoachingGroupsTableTableManager(_db, _db.coachingGroups);
  $$CoachingMembersTableTableManager get coachingMembers =>
      $$CoachingMembersTableTableManager(_db, _db.coachingMembers);
  $$CoachingInvitesTableTableManager get coachingInvites =>
      $$CoachingInvitesTableTableManager(_db, _db.coachingInvites);
  $$CoachingRankingsTableTableManager get coachingRankings =>
      $$CoachingRankingsTableTableManager(_db, _db.coachingRankings);
  $$CoachingRankingEntriesTableTableManager get coachingRankingEntries =>
      $$CoachingRankingEntriesTableTableManager(
        _db,
        _db.coachingRankingEntries,
      );
  $$AthleteBaselinesTableTableManager get athleteBaselines =>
      $$AthleteBaselinesTableTableManager(_db, _db.athleteBaselines);
  $$AthleteTrendsTableTableManager get athleteTrends =>
      $$AthleteTrendsTableTableManager(_db, _db.athleteTrends);
  $$CoachInsightsTableTableManager get coachInsights =>
      $$CoachInsightsTableTableManager(_db, _db.coachInsights);
  $$FriendshipsTableTableManager get friendships =>
      $$FriendshipsTableTableManager(_db, _db.friendships);
  $$GroupsTableTableManager get groups =>
      $$GroupsTableTableManager(_db, _db.groups);
  $$GroupMembersTableTableManager get groupMembers =>
      $$GroupMembersTableTableManager(_db, _db.groupMembers);
  $$GroupGoalsTableTableManager get groupGoals =>
      $$GroupGoalsTableTableManager(_db, _db.groupGoals);
  $$EventsTableTableManager get events =>
      $$EventsTableTableManager(_db, _db.events);
  $$EventParticipationsTableTableManager get eventParticipations =>
      $$EventParticipationsTableTableManager(_db, _db.eventParticipations);
  $$LeaderboardSnapshotsTableTableManager get leaderboardSnapshots =>
      $$LeaderboardSnapshotsTableTableManager(_db, _db.leaderboardSnapshots);
  $$LeaderboardEntriesTableTableManager get leaderboardEntries =>
      $$LeaderboardEntriesTableTableManager(_db, _db.leaderboardEntries);
}
