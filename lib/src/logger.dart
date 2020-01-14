import 'dart:async';
import 'dart:collection';

import 'level.dart';
import 'log_record.dart';

/// Whether to allow fine-grain logging and configuration of loggers in a
/// hierarchy.
///
/// When false, all hierarchical logging instead is merged in the root logger.
bool hierarchicalLoggingEnabled = false;

/// Automatically record stack traces for any message of this level or above.
///
/// Because this is expensive, this is off by default.
Level recordStackTraceAtLevel = Level.OFF;

/// The default [Level].
const defaultLevel = Level.INFO;

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
    if (parent == null) {
      _level = defaultLevel;
    } else {
      parent._children[name] = this;
    }
  }

  /// Effective level considering the levels established in this logger's
  /// parents (when [hierarchicalLoggingEnabled] is true).
  Level get level {
    Level effectiveLevel;

    if (parent == null) {
      // We're either the root logger or a detached logger.  Return our own
      // level.
      effectiveLevel = _level;
    } else if (!hierarchicalLoggingEnabled) {
      effectiveLevel = root._level;
    } else {
      effectiveLevel = _level ?? parent.level;
    }

    assert(effectiveLevel != null);
    return effectiveLevel;
  }

  /// Override the level for this particular [Logger] and its children.
  set level(Level value) {
    if (!hierarchicalLoggingEnabled && parent != null) {
      throw UnsupportedError(
          'Please set "hierarchicalLoggingEnabled" to true if you want to '
          'change the level on a non-root logger.');
    }
    _level = value;
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

      if (parent == null) {
        _publish(record);
      } else if (!hierarchicalLoggingEnabled) {
        root._publish(record);
      } else {
        var target = this;
        while (target != null) {
          target._publish(record);
          target = target.parent;
        }
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
