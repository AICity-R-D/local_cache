import 'dart:convert';
import 'dart:io';

import 'package:dcache/dcache.dart';

import '../core/cache_object.dart';

typedef CacheObjectCreator = CacheObject Function(
    Map<String, dynamic> map, Type type);

class FileManager {
  FileManager(
      {required this.name,
      required this.rootDirectory,
      required CacheObjectCreator objectCreator})
      : _objectCreator = objectCreator;

  final CacheObjectCreator _objectCreator;
  final String name;
  final String rootDirectory;

  String cachedFilePath(String key, Type type) {
    String folder = type.toString();
    return '$rootDirectory/$folder/$key.txt';
  }

  Future<bool> containsObject(String key, Type type) {
    String filePath = cachedFilePath(key, type);
    File file = File(filePath);
    return file.exists();
  }

  Future<CacheObject?> getObject(String key, Type type) async {
    String filePath = cachedFilePath(key, type);
    File file = File(filePath);
    bool exist = await file.exists();
    if (exist) {
      file.readAsString().then((value) {
        Map<String, Object> json = jsonDecode(value);
        return _objectCreator(json, type);
      });
    }

    return null;
  }

  Future<void> storeObject(CacheObject object) async {
    String filePath = cachedFilePath(object.objectID(), object.runtimeType);
    File file = File(filePath);
    String data = jsonEncode(object.toMap());
    await file.writeAsString(data);
  }

  Future<void> removeObject<T extends CacheObject>(
      String key, Type type) async {
    String filePath = cachedFilePath(key, type);
    File file = File(filePath);
    await file.delete();
  }
}

class FileStorage {
  FileStorage(
      {required this.name,
      required this.directoryPath,
      required CacheObjectCreator creator})
      : _fileManager = FileManager(
            name: name, rootDirectory: directoryPath, objectCreator: creator);

  final String name;
  final String directoryPath;
  final FileManager _fileManager;
  final LruCache _memoryCache =
      LruCache<String, Object>(storage: InMemoryStorage(60));

  String _cacheObjectID(String key, Type type) {
    String prefix = type.toString();
    return '$prefix-$key';
  }

  Future<CacheObject?> getOneObject(String key, Type type) async {
    String id = _cacheObjectID(key, type);
    if (_memoryCache.containsKey(id)) {
      return _memoryCache.get(id);
    }

    CacheObject? object = await _fileManager.getObject(key, type);
    if (object != null) {
      _memoryCache[id] = object;
    }

    return object;
  }

  Future<List<CacheObject>> getObjects(List<String> keys, Type type) async {
    List<CacheObject> result = [];
    for (String key in keys) {
      CacheObject? object = await getOneObject(key, type);
      if (object != null) {
        result.add(object);
      }
    }

    return result;
  }

  Future<bool> containsObject(String key, Type type) async {
    String id = _cacheObjectID(key, type);
    return await _fileManager.containsObject(key, type) ||
        _memoryCache.containsKey(id);
  }

  Future<void> storeObject(CacheObject object) async {
    await _fileManager.storeObject(object);

    String id = _cacheObjectID(object.objectID(), object.runtimeType);
    _memoryCache[id] = object;
  }

  Future<void> removeObject(String key, Type type) async {
    String id = _cacheObjectID(key, type);
    await _fileManager.removeObject(key, type);
    _memoryCache[id] = null;
  }

  Future<void> removeObjects(List<String> keys, Type type) async {
    for (String key in keys) {
      await removeObject(key, type);
    }
  }

  void removeCache(List<String> keys, Type type) {
    for (var value in keys) {
      String id = _cacheObjectID(value, type);
      _memoryCache[id] = null;
    }
  }
}
