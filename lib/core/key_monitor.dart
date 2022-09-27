import 'cache_object.dart';

class KeyMonitor {
  KeyMonitor();

  final List<Type> _monitoredTypes = [];
  final Map<Type, List<String>> _monitoredKeys = {};
  final Map<Type, Map<String, String>> _monitoredVersions = {};
  final Map<Type, List<String>> _retryKeys = {};
  final Map<Type, List<String>> _ignoredKeys = {};

  void startMonitoring(Type type) {
    if (!_monitoredTypes.contains(type)) {
      _monitoredTypes.add(type);
      _monitoredKeys[type] = <String>[];
      _monitoredVersions[type] = <String, String>{};
      _retryKeys[type] = <String>[];
      _ignoredKeys[type] = <String>[];
    }
  }

  List<Type> monitoredTypes() {
    return _monitoredTypes;
  }

  bool containsType(Type type) {
    return _monitoredTypes.contains(type);
  }

  void stopMonitoring(Type type) {
    if (_monitoredTypes.contains(type)) {
      _monitoredTypes.remove(type);
      _cleanUpForType(type);
    }
  }

  void _cleanUpForType(Type type) {
    _monitoredKeys.remove(type);
    _monitoredVersions.remove(type);
    _retryKeys.remove(type);
    _ignoredKeys.remove(type);
  }

  void updateMonitorKeysForType(List<String> keys, Type type) {
    if (containsType(type)) {
      _monitoredKeys[type] = keys;
    }
  }

  List<String> findKeysInMonitoring(List<String> keys, Type type) {
    if (!containsType(type)) return [];
    final List<String>? stored = _monitoredKeys[type];
    if (stored!.isEmpty) return [];

    List<String> results = [];
    for (String key in keys) {
      if (stored.contains(key)) {
        results.add(key);
      }
    }

    return results;
  }

  bool keyInMonitoring(String key, Type type) {
    if (!containsType(type)) return false;
    final List<String>? stored = _monitoredKeys[type];
    return stored!.contains(key);
  }

  Map<String, String>? versionsForType(Type type) {
    if (!containsType(type)) return null;
    return _monitoredVersions[type];
  }

  void updateVersions<T extends CacheObject>(
      List<T> objects, Type type, Function(T)? callback) {
    if (!containsType(type)) return;

    Map? versions = _monitoredVersions[type];
    for (T object in objects) {
      versions![object.objectID] = object.objectVersion;
      if (callback != null) {
        callback(object);
      }
    }
  }

  void removeVersions(List<String> keys, Type type) {
    if (!containsType(type)) return;

    Map? versions = _monitoredVersions[type];
    for (String key in keys) {
      versions!.remove(key);
    }
  }

  List<String> expiredKeys(
      List<String> keys, Map<String, String> versions, Type type) {
    if (!containsType(type)) return [];

    Map<String, String>? stored = _monitoredVersions[type];
    List<String> results = [];
    for (String key in keys) {
      final oldVersion = stored![key];
      final newVersion = versions[key];
      if (oldVersion != newVersion) {
        results.add(key);
      }
    }

    return results;
  }

  void updateIgnoredKeys(List<String> keys, List<String> excluded,
      List<String>? downloaded, Type type) {
    if (!containsType(type)) return;

    List<String> remains = List.of(keys);
    remains.removeWhere((element) {
      bool exc = excluded.contains(element);
      bool doc = false;
      if (downloaded != null) {
        doc = downloaded.contains(element);
      }

      return exc || doc;
    });

    if (remains.isEmpty) return;

    List<String>? ignored = _ignoredKeys[type];
    if (ignored == null) {
      ignored = <String>[];
      _ignoredKeys[type] = ignored;
    }

    ignored.addAll(remains);
  }

  void removeIgnoredKeys(List<String> keys, Type type) {
    if (!containsType(type)) return;

    List<String>? stored = _ignoredKeys[type];
    if (stored!.isEmpty) return;

    stored.removeWhere((element) => keys.contains(element));
  }

  List<String> requestKeyByRemovingIgnoredKeys(
      List<String> keys, List<CacheObject> objects, Type type) {
    if (!containsType(type)) return [];

    List<String>? stored = _ignoredKeys[type];
    List<String> results = List.of(keys);
    Iterable<String> exists = objects.map((e) => e.objectID());

    results.removeWhere(
        (element) => exists.contains(element) || stored!.contains(element));
    return results;
  }

  void updateRetryKeys(List<String> keys, Type type) {
    if (!containsType(type)) return;

    List<String>? stored = _ignoredKeys[type];
    stored!.addAll(keys);
  }

  void removeRetryKeys(List<String> keys, Type type) {
    if (!containsType(type)) return;

    List<String>? stored = _ignoredKeys[type];
    stored!.removeWhere((element) => keys.contains(element));
  }

  bool retryKeyIsEmpty(Type type) {
    List<String>? keys = retryKeys(type);
    return keys == null || keys.isEmpty;
  }

  List<String>? retryKeys(Type type) {
    return _retryKeys[type];
  }

  bool retryKeyStackIsEmpty() {
    bool empty = false;
    for (Type key in _retryKeys.keys) {
      List? value = _retryKeys[key];
      if (value!.isNotEmpty) {
        empty = true;
        break;
      }
    }

    return empty;
  }

  bool refreshKeyIsEmpty(Type type) {
    List<String>? keys = refreshKeys(type);
    return keys == null || keys.isEmpty;
  }

  List<String>? refreshKeys(Type type) {
    return _monitoredVersions[type]!.keys.toList();
  }

  bool refreshKeyStackIsEmpty() {
    bool empty = false;
    for (Type key in _monitoredVersions.keys) {
      Map<String, String>? value = _monitoredVersions[key];
      if (value!.isNotEmpty) {
        empty = true;
        break;
      }
    }

    return empty;
  }

  String? _monitoredVersion(String key, Type type) {
    Map<String, String>? version = _monitoredVersions[key];
    return version![key];
  }

  bool monitoredObjectIsExpired(CacheObject object) {
    if (!containsType(object.runtimeType)) return false;

    String? version = _monitoredVersion(object.objectID(), object.runtimeType);
    if (version != null) {
      return version == object.objectVersion() ? false : true;
    }

    return true;
  }
}
