import 'dart:async';

import 'package:dcache/dcache.dart';

import '../core/cache_object.dart';

abstract class DatabaseInterface {
  bool shouldCacheObjectType(Type type);
  Future<bool> containsObject(String key, Type type);
  Future<bool> containsObjectWhere(
      String where, Type type, List<Object>? whereArgs);
  Future<CacheObject?> getOneObject(String key, Type type);
  Future<CacheObject?> getOneObjectWhere(
      String where, Type type, List<Object>? whereArgs);
  Future<List<CacheObject>> getObjects(List<String> keys, Type type);
  Future<List<CacheObject>> getObjectsWhere(
      String where, Type type, List<Object>? whereArgs);
  Future<void> storeObject(CacheObject object);
  Future<void> updateObject(CacheObject object);
  Future<void> removeObject(String key, Type type);
  Future<void> removeObjects(List<String> keys, Type type);
  Future<void> removeAllObjects();
}

class DatabaseStorage implements DatabaseInterface {
  DatabaseStorage({required this.name, required DatabaseInterface database})
      : _diskStorage = database;

  final String name;
  final DatabaseInterface _diskStorage;
  final LruCache _memoryCache =
      LruCache<String, CacheObject>(storage: InMemoryStorage(30));

  String getObjectCacheID(String key, Type type) {
    String identifier = '$type-$key';
    return identifier;
  }

  String getObjectQueryID(Type type, String where, List<Object>? whereArgs) {
    String identifier = '';
    if (whereArgs != null) {
      String args = whereArgs.toString();
      identifier = '$type-$where=$args';
    } else {
      identifier = '$type-$where';
    }

    return identifier;
  }

  @override
  bool shouldCacheObjectType(Type type) {
    return _diskStorage.shouldCacheObjectType(type);
  }

  @override
  Future<bool> containsObject(String key, Type type) async {
    String identifier = getObjectCacheID(key, type);
    return await _diskStorage.containsObject(key, type) ||
        _memoryCache.containsKey(identifier);
  }

  @override
  Future<bool> containsObjectWhere(
      String where, Type type, List<Object>? whereArgs) async {
    String identifier = getObjectQueryID(type, where, whereArgs);
    return await _diskStorage.containsObjectWhere(where, type, whereArgs) ||
        _memoryCache.containsKey(identifier);
  }

  @override
  Future<CacheObject?> getOneObject(String key, Type type) async {
    Completer<CacheObject?> completer = Completer();

    bool shouldCache = shouldCacheObjectType(type) && key.isNotEmpty;
    if (shouldCache) {
      CacheObject? object;
      String identifier = getObjectCacheID(key, type);
      if (_memoryCache.containsKey(identifier)) {
        object = _memoryCache.get(identifier);
      } else {
        object = await _diskStorage.getOneObject(key, type);
        if (object != null) {
          _memoryCache[identifier] = object;
        }
      }

      completer.complete(object);
    } else {
      CacheObject? object = await _diskStorage.getOneObject(key, type);
      completer.complete(object);
    }

    return completer.future;
  }

  @override
  Future<CacheObject?> getOneObjectWhere(
      String where, Type type, List<Object>? whereArgs) async {
    Completer<CacheObject?> completer = Completer();

    bool shouldCache = shouldCacheObjectType(type);
    if (shouldCache) {
      CacheObject? object;
      String identifier = getObjectQueryID(type, where, whereArgs);
      if (_memoryCache.containsKey(identifier)) {
        object = _memoryCache[identifier];
      } else {
        object = await _diskStorage.getOneObjectWhere(where, type, whereArgs);
        if (object != null) {
          _memoryCache.set(identifier, object);
        }
      }

      completer.complete(object);
    } else {
      CacheObject? object =
          await _diskStorage.getOneObjectWhere(where, type, whereArgs);
      completer.complete(object);
    }

    return completer.future;
  }

  @override
  Future<List<CacheObject>> getObjects(List<String> keys, Type type) async {
    Completer<List<CacheObject>> completer = Completer();

    bool shouldCache = shouldCacheObjectType(type);
    List<CacheObject> outputs = [];
    List<String> request = [];

    if (shouldCache) {
      for (String key in keys) {
        String identifier = getObjectCacheID(key, type);
        CacheObject? object = _memoryCache[identifier];
        if (object != null) {
          outputs.add(object);
        } else {
          request.add(key);
        }
      }
    } else {
      request.addAll(keys);
    }

    if (request.isNotEmpty) {
      List<CacheObject> objects = await _diskStorage.getObjects(keys, type);
      if (shouldCache) {
        for (CacheObject object in objects) {
          String identifier = getObjectCacheID(object.objectID(), type);
          _memoryCache.set(identifier, object);
          outputs.add(object);
        }
      }
    }

    completer.complete(outputs);
    return completer.future;
  }

  @override
  Future<List<CacheObject>> getObjectsWhere(
      String where, Type type, List<Object>? whereArgs) async {
    Completer<List<CacheObject>> completer = Completer();

    bool shouldCache = shouldCacheObjectType(type);
    List<CacheObject> outputs = [];
    bool request = false;

    String identifier = getObjectQueryID(type, where, whereArgs);
    if (shouldCache) {
      CacheObject? object = _memoryCache[identifier];
      if (object != null) {
        outputs.add(object);
      } else {
        request = true;
      }
    } else {
      request = true;
    }

    if (request) {
      outputs = await _diskStorage.getObjectsWhere(where, type, whereArgs);
      if (shouldCache) {
        _memoryCache[identifier] = outputs;
      }
    }

    completer.complete(outputs);
    return completer.future;
  }

  @override
  Future<void> storeObject(CacheObject object) async {
    String identifier = getObjectCacheID(object.objectID(), object.runtimeType);
    await _diskStorage.storeObject(object);
    if (shouldCacheObjectType(object.runtimeType)) {
      _memoryCache[identifier] = object;
    }
  }

  @override
  Future<void> updateObject(CacheObject object) async {
    String identifier = getObjectCacheID(object.objectID(), object.runtimeType);
    await _diskStorage.storeObject(object);
    if (shouldCacheObjectType(object.runtimeType)) {
      _memoryCache[identifier] = object;
    }
  }

  @override
  Future<void> removeObject(String key, Type type) {
    String identifier = getObjectCacheID(key, type);
    _memoryCache[identifier] = null;

    return _diskStorage.removeObject(key, type);
  }

  @override
  Future<void> removeObjects(List<String> keys, Type type) {
    for (String key in keys) {
      String identifier = getObjectCacheID(key, type);
      _memoryCache[identifier] = null;
    }

    return _diskStorage.removeObjects(keys, type);
  }

  @override
  Future<void> removeAllObjects() {
    _memoryCache.clear();
    return _diskStorage.removeAllObjects();
  }
}
