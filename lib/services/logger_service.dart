import 'package:logger/logger.dart';
import 'package:flutter/foundation.dart';

/// Centralized logging service for the application
///
/// Provides different log levels:
/// - trace: Extremely detailed information, typically only of interest when diagnosing problems
/// - debug: Detailed information, typically only of interest when diagnosing problems
/// - info: General information about app execution, interesting to users or administrators
/// - warning: Potentially harmful situations or recoverable errors
/// - error: Error events that might still allow the app to continue running
/// - fatal: Very severe error events that will presumably lead the app to abort
class AppLogger {
  static final Logger _logger = Logger(
    filter: ProductionFilter(),
    printer: PrettyPrinter(
      methodCount: 2, // Number of method calls to be displayed
      errorMethodCount: 8, // Number of method calls if stacktrace is provided
      lineLength: 120, // Width of the output
      colors: true, // Colorful log messages
      printEmojis: true, // Print an emoji for each log message
      dateTimeFormat: DateTimeFormat.none, // No timestamp in logs
    ),
  );

  // Trace level - extremely detailed information
  static void trace(String message, [dynamic error, StackTrace? stackTrace]) {
    _logger.t(message, error: error, stackTrace: stackTrace);
  }

  // Debug level - detailed information for diagnosing problems
  static void debug(String message, [dynamic error, StackTrace? stackTrace]) {
    _logger.d(message, error: error, stackTrace: stackTrace);
  }

  // Info level - general information about app execution
  static void info(String message, [dynamic error, StackTrace? stackTrace]) {
    _logger.i(message, error: error, stackTrace: stackTrace);
  }

  // Warning level - potentially harmful situations
  static void warning(String message, [dynamic error, StackTrace? stackTrace]) {
    _logger.w(message, error: error, stackTrace: stackTrace);
  }

  // Error level - error events that might allow the app to continue
  static void error(String message, [dynamic error, StackTrace? stackTrace]) {
    _logger.e(message, error: error, stackTrace: stackTrace);
  }

  // Fatal level - very severe error events
  static void fatal(String message, [dynamic error, StackTrace? stackTrace]) {
    _logger.f(message, error: error, stackTrace: stackTrace);
  }

  // Service-specific loggers with prefixes for better organization

  static void auth(
    String message, {
    String level = 'info',
    dynamic error,
    StackTrace? stackTrace,
  }) {
    final prefixedMessage = '[AUTH] $message';
    _logWithLevel(level, prefixedMessage, error, stackTrace);
  }

  static void purchase(
    String message, {
    String level = 'info',
    dynamic error,
    StackTrace? stackTrace,
  }) {
    final prefixedMessage = '[PURCHASE] $message';
    _logWithLevel(level, prefixedMessage, error, stackTrace);
  }

  static void words(
    String message, {
    String level = 'info',
    dynamic error,
    StackTrace? stackTrace,
  }) {
    final prefixedMessage = '[WORDS] $message';
    _logWithLevel(level, prefixedMessage, error, stackTrace);
  }

  static void download(
    String message, {
    String level = 'info',
    dynamic error,
    StackTrace? stackTrace,
  }) {
    final prefixedMessage = '[DOWNLOAD] $message';
    _logWithLevel(level, prefixedMessage, error, stackTrace);
  }

  static void storage(
    String message, {
    String level = 'info',
    dynamic error,
    StackTrace? stackTrace,
  }) {
    final prefixedMessage = '[STORAGE] $message';
    _logWithLevel(level, prefixedMessage, error, stackTrace);
  }

  static void profile(
    String message, {
    String level = 'info',
    dynamic error,
    StackTrace? stackTrace,
  }) {
    final prefixedMessage = '[PROFILE] $message';
    _logWithLevel(level, prefixedMessage, error, stackTrace);
  }

  static void revenueCat(
    String message, {
    String level = 'info',
    dynamic error,
    StackTrace? stackTrace,
  }) {
    final prefixedMessage = '[REVENUE_CAT] $message';
    _logWithLevel(level, prefixedMessage, error, stackTrace);
  }

  // Helper method to log with specific level
  static void _logWithLevel(
    String level,
    String message,
    dynamic error,
    StackTrace? stackTrace,
  ) {
    switch (level.toLowerCase()) {
      case 'trace':
        _logger.t(message, error: error, stackTrace: stackTrace);
        break;
      case 'debug':
        _logger.d(message, error: error, stackTrace: stackTrace);
        break;
      case 'info':
        _logger.i(message, error: error, stackTrace: stackTrace);
        break;
      case 'warning':
      case 'warn':
        _logger.w(message, error: error, stackTrace: stackTrace);
        break;
      case 'error':
        _logger.e(message, error: error, stackTrace: stackTrace);
        break;
      case 'fatal':
        _logger.f(message, error: error, stackTrace: stackTrace);
        break;
      default:
        _logger.i(message, error: error, stackTrace: stackTrace);
    }
  }
}

/// Custom filter that shows different log levels based on build mode
class ProductionFilter extends LogFilter {
  @override
  bool shouldLog(LogEvent event) {
    if (kDebugMode) {
      // In debug mode, show all logs
      return true;
    } else {
      // In production, only show warnings and above
      return event.level.index >= Level.warning.index;
    }
  }
}
