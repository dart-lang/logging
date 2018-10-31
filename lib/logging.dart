// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

library logging;

import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:developer' as developer;

/// Whether to allow fine-grain logging and configuration of loggers in a
/// hierarchy.
///
/// When false, all logging is merged in the root logger.
bool hierarchicalLoggingEnabled = false;

/// Automatically record stack traces for any message of this level or above.
///
/// Because this is expensive, this is off by default.
Level recordStackTraceAtLevel = Level.OFF;

/// Level for the root-logger.
///
/// This will be the level of all loggers if [hierarchicalLoggingEnabled] is
/// false.
Level _rootLevel = Level.INFO;

/// Use a [Logger] to log debug messages.
///
/// [Logger]s are named using a hierarchical dot-separated name convention.
class Logger {
  /// Simple name of this logger.
  final String name;

  /// The full name of this logger, which includes the parent's full name.
  String get fullName =>
      (parent == null || parent.name == '') ? name : '${parent.fullName}.$name';

  /// Parent of this logger in the hierarchy of loggers.
  final Logger parent;

  /// Logging [Level] used for entries generated on this logger.
  Level _level;

  final Map<String, Logger> _children;

  /// Children in the hierarchy of loggers, indexed by their simple names.
  final Map<String, Logger> children;

  /// Controller used to notify when log entries are added to this logger.
  StreamController<LogRecord> _controller;

  /// Singleton constructor. Calling `new Logger(name)` will return the same
  /// actual instance whenever it is called with the same string name.
  factory Logger(String name) =>
      _loggers.putIfAbsent(name, () => Logger._named(name));

  /// Creates a new detached [Logger].
  ///
  /// Returns a new [Logger] instance (unlike `new Logger`, which returns a
  /// [Logger] singleton), which doesn't have any parent or children,
  /// and is not a part of the global hierarchical loggers structure.
  ///
  /// It can be useful when you just need a local short-living logger,
  /// which you'd like to be garbage-collected later.
  factory Logger.detached(String name) =>
      Logger._internal(name, null, <String, Logger>{});

  factory Logger._named(String name) {
    if (name.startsWith('.')) {
      throw ArgumentError("name shouldn't start with a '.'");
    }
    // Split hierarchical names (separated with '.').
    var dot = name.lastIndexOf('.');
    Logger parent;
    String thisName;
    if (dot == -1) {
      if (name != '') parent = Logger('');
      thisName = name;
    } else {
      parent = Logger(name.substring(0, dot));
      thisName = name.substring(dot + 1);
    }
    return Logger._internal(thisName, parent, <String, Logger>{});
  }

  Logger._internal(this.name, this.parent, Map<String, Logger> children)
      : _children = children,
        children = UnmodifiableMapView(children) {
    if (parent != null) parent._children[name] = this;
  }

  /// Effective level considering the levels established in this logger's
  /// parents (when [hierarchicalLoggingEnabled] is true).
  Level get level {
    if (hierarchicalLoggingEnabled) {
      if (_level != null) return _level;
      if (parent != null) return parent.level;
    }
    return _rootLevel;
  }

  /// Override the level for this particular [Logger] and its children.
  set level(Level value) {
    if (hierarchicalLoggingEnabled && parent != null) {
      _level = value;
    } else {
      if (parent != null) {
        throw UnsupportedError(
            'Please set "hierarchicalLoggingEnabled" to true if you want to '
            'change the level on a non-root logger.');
      }
      _rootLevel = value;
    }
  }

  /// Returns a stream of messages added to this [Logger].
  ///
  /// You can listen for messages using the standard stream APIs, for instance:
  ///
  /// ```dart
  /// logger.onRecord.listen((record) { ... });
  /// ```
  Stream<LogRecord> get onRecord => _getStream();

  void clearListeners() {
    if (hierarchicalLoggingEnabled || parent == null) {
      if (_controller != null) {
        _controller.close();
        _controller = null;
      }
    } else {
      root.clearListeners();
    }
  }

  /// Whether a message for [value]'s level is loggable in this logger.
  bool isLoggable(Level value) => (value >= level);

  /// Adds a log record for a [message] at a particular [logLevel] if
  /// `isLoggable(logLevel)` is true.
  ///
  /// Use this method to create log entries for user-defined levels. To record a
  /// message at a predefined level (e.g. [Level.INFO], [Level.WARNING], etc)
  /// you can use their specialized methods instead (e.g. [info], [warning],
  /// etc).
  ///
  /// If [message] is a [Function], it will be lazy evaluated. Additionally, if
  /// [message] or its evaluated value is not a [String], then 'toString()' will
  /// be called on the object and the result will be logged. The log record will
  /// contain a field holding the original object.
  ///
  /// The log record will also contain a field for the zone in which this call
  /// was made. This can be advantageous if a log listener wants to handler
  /// records of different zones differently (e.g. group log records by HTTP
  /// request if each HTTP request handler runs in it's own zone).
  void log(Level logLevel, message,
      [Object error, StackTrace stackTrace, Zone zone]) {
    Object object;
    if (isLoggable(logLevel)) {
      if (message is Function) {
        message = message();
      }

      String msg;
      if (message is String) {
        msg = message;
      } else {
        msg = message.toString();
        object = message;
      }

      if (stackTrace == null && logLevel >= recordStackTraceAtLevel) {
        stackTrace = StackTrace.current;
        error ??= 'autogenerated stack trace for $logLevel $msg';
      }
      zone ??= Zone.current;

      var record =
          LogRecord(logLevel, msg, fullName, error, stackTrace, zone, object);

      if (hierarchicalLoggingEnabled) {
        var target = this;
        while (target != null) {
          target._publish(record);
          target = target.parent;
        }
      } else {
        root._publish(record);
      }
    }
  }

  /// Log message at level [Level.FINEST].
  void finest(message, [Object error, StackTrace stackTrace]) =>
      log(Level.FINEST, message, error, stackTrace);

  /// Log message at level [Level.FINER].
  void finer(message, [Object error, StackTrace stackTrace]) =>
      log(Level.FINER, message, error, stackTrace);

  /// Log message at level [Level.FINE].
  void fine(message, [Object error, StackTrace stackTrace]) =>
      log(Level.FINE, message, error, stackTrace);

  /// Log message at level [Level.CONFIG].
  void config(message, [Object error, StackTrace stackTrace]) =>
      log(Level.CONFIG, message, error, stackTrace);

  /// Log message at level [Level.INFO].
  void info(message, [Object error, StackTrace stackTrace]) =>
      log(Level.INFO, message, error, stackTrace);

  /// Log message at level [Level.WARNING].
  void warning(message, [Object error, StackTrace stackTrace]) =>
      log(Level.WARNING, message, error, stackTrace);

  /// Log message at level [Level.SEVERE].
  void severe(message, [Object error, StackTrace stackTrace]) =>
      log(Level.SEVERE, message, error, stackTrace);

  /// Log message at level [Level.SHOUT].
  void shout(message, [Object error, StackTrace stackTrace]) =>
      log(Level.SHOUT, message, error, stackTrace);

  Stream<LogRecord> _getStream() {
    if (hierarchicalLoggingEnabled || parent == null) {
      _controller ??= StreamController<LogRecord>.broadcast(sync: true);
      return _controller.stream;
    } else {
      return root._getStream();
    }
  }

  void _publish(LogRecord record) {
    if (_controller != null) {
      _controller.add(record);
    }
  }

  /// Top-level root [Logger].
  static final Logger root = Logger('');

  /// All [Logger]s in the system.
  static final Map<String, Logger> _loggers = <String, Logger>{};
}

/// Handler callback to process log entries as they are added to a [Logger].
@deprecated
typedef LoggerHandler = void Function(LogRecord record);

/// [Level]s to control logging output. Logging can be enabled to include all
/// levels above certain [Level]. [Level]s are ordered using an integer
/// value [Level.value]. The predefined [Level] constants below are sorted as
/// follows (in descending order): [Level.SHOUT], [Level.SEVERE],
/// [Level.WARNING], [Level.INFO], [Level.CONFIG], [Level.FINE], [Level.FINER],
/// [Level.FINEST], and [Level.ALL].
///
/// We recommend using one of the predefined logging levels. If you define your
/// own level, make sure you use a value between those used in [Level.ALL] and
/// [Level.OFF].
class Level implements Comparable<Level> {
  final String name;

  /// Unique value for this level. Used to order levels, so filtering can
  /// exclude messages whose level is under certain value.
  final int value;

  const Level(this.name, this.value);

  /// Special key to turn on logging for all levels ([value] = 0).
  static const Level ALL = Level('ALL', 0);

  /// Special key to turn off all logging ([value] = 2000).
  static const Level OFF = Level('OFF', 2000);

  /// Key for highly detailed tracing ([value] = 300).
  static const Level FINEST = Level('FINEST', 300);

  /// Key for fairly detailed tracing ([value] = 400).
  static const Level FINER = Level('FINER', 400);

  /// Key for tracing information ([value] = 500).
  static const Level FINE = Level('FINE', 500);

  /// Key for static configuration messages ([value] = 700).
  static const Level CONFIG = Level('CONFIG', 700);

  /// Key for informational messages ([value] = 800).
  static const Level INFO = Level('INFO', 800);

  /// Key for potential problems ([value] = 900).
  static const Level WARNING = Level('WARNING', 900);

  /// Key for serious failures ([value] = 1000).
  static const Level SEVERE = Level('SEVERE', 1000);

  /// Key for extra debugging loudness ([value] = 1200).
  static const Level SHOUT = Level('SHOUT', 1200);

  static const List<Level> LEVELS = [
    ALL,
    FINEST,
    FINER,
    FINE,
    CONFIG,
    INFO,
    WARNING,
    SEVERE,
    SHOUT,
    OFF
  ];

  @override
  bool operator ==(Object other) => other is Level && value == other.value;
  bool operator <(Level other) => value < other.value;
  bool operator <=(Level other) => value <= other.value;
  bool operator >(Level other) => value > other.value;
  bool operator >=(Level other) => value >= other.value;

  @override
  int compareTo(Level other) => value - other.value;

  @override
  int get hashCode => value;

  @override
  String toString() => name;
}

/// A log entry representation used to propagate information from [Logger] to
/// individual handlers.
class LogRecord {
  final Level level;
  final String message;

  /// Non-string message passed to Logger.
  final Object object;

  /// Logger where this record is stored.
  final String loggerName;

  /// Time when this record was created.
  final DateTime time;

  /// Unique sequence number greater than all log records created before it.
  final int sequenceNumber;

  static int _nextNumber = 0;

  /// Associated error (if any) when recording errors messages.
  final Object error;

  /// Associated stackTrace (if any) when recording errors messages.
  final StackTrace stackTrace;

  /// Zone of the calling code which resulted in this LogRecord.
  final Zone zone;

  LogRecord(this.level, this.message, this.loggerName,
      [this.error, this.stackTrace, this.zone, this.object])
      : time = DateTime.now(),
        sequenceNumber = LogRecord._nextNumber++;

  @override
  String toString() => '[${level.name}] $loggerName: $message';
}

typedef _ServiceExtensionCallback = Future<Map<String, dynamic>> Function(
    Map<String, String> parameters);

/// A shared manager instance whose recorded messages are logged to the
/// developer console.
final LogManager logManager = LogManager()..onRecord.listen((record) {
  developer.log(
    record.message,
    name: record.loggerName,
    time: record.time,
    error: record.error,
    level: record.level.value,
    stackTrace: record.stackTrace,
  );
});

/// Log Managers record messages only written to loggers explicitly enabled by
/// name.
///
/// For example, in the given source, only messages to `loggerA` will be sent to
/// the `onRecord` stream.
///
/// ```
/// var loggerA = Logger('loggerA');
/// var loggerA = Logger('loggerB');
///
/// var manager = LogManager()..enableLogging('loggerA');
///
/// loggerA.info('hello from logger A'); // recorded
/// loggerB.info('here goes nothing');   // ignored
/// ```
///
/// Log managers can be created but the provided [logManager] should suffice
/// for most purposes.  The shared manager redirects recorded messages to the
/// developer log.
///
/// **Important note:** managed loggers respect logger `root` level configuration.
/// For example, in the following, `logger` only reports `severe` messages
/// as expected.
///
/// ```
/// Logger.root.level = Level.SEVERE;
///
/// ...
///
/// var logger = Logger('my.logger');
/// logManager.enable('my.logger');
/// try {
///   logger.info('doing something'); // ignored
///   ...
/// } catch(e, stackTrace) {
///   logger.severe('uh-oh!, e, stackTrace); // recorded
/// }
/// ```
///
/// * To create loggers, see [Logger].
/// * To enable or disable a logger, use [enableLogging].
/// * To query channel enablement, use [shouldLog].
class LogManager {
  static bool _initialized;

  final Set<String> _enabledLoggers = Set<String>();

  final StreamController<LogRecord> _logController =
      StreamController.broadcast(sync: true);
  final StreamController<String> _loggerAddedBroadcaster =
      StreamController.broadcast();
  final StreamController<String> _loggerEnabledBroadcaster =
      StreamController.broadcast();

  LogManager() {
    Logger.root.onRecord.listen((record) {
      if (shouldLog(record.loggerName)) {
        _logController.add(record);
      }
    });
  }

  /// Returns a stream of messages added to loggers enabled by this manager.
  Stream<LogRecord> get onRecord => _logController.stream;

  /// Enable (or disable) logging of messages sent to the given [logger].
  void enableLogging(String logger, {bool enable = true}) {
    enable ? _enabledLoggers.add(logger) : _enabledLoggers.remove(logger);
    _loggerEnabledBroadcaster.add(logger);
  }

  /// Whether messages to the given [logger] should be logged by this manager.
  /// @see [enableLogging]
  bool shouldLog(String logger) => _enabledLoggers.contains(logger);

  /// Called to register service extensions.
  void initServiceExtensions() {
    // Avoid double initialization.
    if (_initialized == true) {
      return;
    }

    // Fire events for new loggers.
    _loggerAddedBroadcaster.stream.listen((String name) {
      developer.postEvent('logging.logger.added', <String, dynamic>{
        'logger': name,
      });
    });

    // Fire events for logger enablement changes.
    _loggerEnabledBroadcaster.stream.listen((String name) {
      developer.postEvent('logging.logger.enabled', <String, dynamic>{
        'logger': name,
        'enabled': shouldLog(name),
      });
    });

    // Service for enabling loggers.
    _registerServiceExtension(
      name: 'enable',
      callback: (Map<String, Object> parameters) async {
        final String logger = parameters['logger'];
        if (logger != null) {
          if (parameters.containsKey('enabled')) {
            enableLogging(logger, enable: parameters['enabled'] == 'true');
          }
          return <String, dynamic>{
            'enabled': shouldLog(logger).toString(),
          };
        } else {
          return <String, dynamic>{};
        }
      },
    );

    // Service for querying loggers.
    _registerServiceExtension(
      name: 'loggers',
      callback: (Map<String, dynamic> parameters) async => {
            'value': Logger._loggers.keys
                .map((logger) => MapEntry(logger, <String, String>{
                      'enabled': shouldLog(logger).toString(),
                    }))
          },
    );

    _initialized = true;
  }

  /// Registers a service extension method with the given name and a callback to
  /// be called when the extension method is called.
  void _registerServiceExtension({
    String name,
    _ServiceExtensionCallback callback,
  }) {
    assert(name != null);
    assert(callback != null);
    final methodName = 'ext.dart.logging.$name';
    developer.registerExtension(methodName,
        (String method, Map<String, String> parameters) async {
      assert(method == methodName);

      dynamic caughtException;
      StackTrace caughtStack;
      Map<String, dynamic> result;
      try {
        result = await callback(parameters);
      } catch (exception, stack) {
        caughtException = exception;
        caughtStack = stack;
      }
      if (caughtException == null) {
        result['type'] = '_extensionType';
        result['method'] = method;
        return developer.ServiceExtensionResponse.result(json.encode(result));
      } else {
        return developer.ServiceExtensionResponse.error(
            developer.ServiceExtensionResponse.extensionError,
            json.encode(<String, String>{
              'exception': caughtException.toString(),
              'stack': caughtStack.toString(),
              'method': method,
            }));
      }
    });
  }
}
