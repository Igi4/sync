part of sync.common;

void printLogRecord(LogRecord r) {
  print("[${r.loggerName}][${r.level.toString().padLeft(7, " ")}] ${r.message}");
}

final Logger logger = new Logger('sync')..onRecord.listen(printLogRecord);