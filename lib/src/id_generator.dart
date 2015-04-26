part of sync.client;

class IdGenerator {
  int _counter = 0;
  String prefix = null;

  /**
   * Creates IdGenerator with [prefix]
   */
  IdGenerator([this.prefix]);

  String next() {
    _counter++;
    return prefix + '-' + _counter.toRadixString(36);
  }
}
