import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';

import '../core/cache_object.dart';
import '../core/key_monitor.dart';
import 'database_storage.dart';

class DatabaseCacheManager implements CacheObjectManager {
  DatabaseCacheManager(
      {required this.name,
      required DatabaseInterface database,
      this.downloader}) {
    _storage = DatabaseStorage(name: name, database: database);
    _connectivity = Connectivity();
    _connectivity.onConnectivityChanged.listen(_updateConnectionStatus);
  }

  final String name;
  late CacheObjectManagerDelegate? delegate;
  bool _versionCheckout = false;
  bool _retryDownload = false;
  final CacheObjectDownloader? downloader;

  late final DatabaseStorage _storage;
  final KeyMonitor _keyMonitor = KeyMonitor();
  Timer? _refreshController;
  late Duration _refreshDuration;
  Timer? _retryController;
  late Duration _retryDuration;
  late Connectivity _connectivity;
  bool _networkReachable = false;

  DatabaseStorage get storage => _storage;

  @override
  List<String> getMonitoredObjectIDs(List<String> objectIDs, Type type) {
    return _keyMonitor.findKeysInMonitoring(objectIDs, type);
  }

  @override
  bool objectInMonitoring(String objectID, Type type) {
    return _keyMonitor.keyInMonitoring(objectID, type);
  }

  @override
  void startMonitoring(Type type) {
    if (_storage.shouldCacheObjectType(type)) {
      _keyMonitor.startMonitoring(type);
    }
  }

  @override
  void stopMonitoring(Type type) {
    _keyMonitor.stopMonitoring(type);
  }

  void setVersionCheckout(bool checkout, {int seconds = 30}) {
    if (_versionCheckout == checkout) return;

    if (checkout) {
      if (downloader != null && downloader is VersionObjectDownloader) {
        _versionCheckout = checkout;
        _refreshDuration = Duration(seconds: seconds);
      }
    } else {
      _versionCheckout = checkout;
      _endVersionCheckout();
    }
  }

  void setRetryDownload(bool retry, {int seconds = 30}) {
    if (_retryDownload == retry) return;

    if (retry) {
      if (downloader != null) {
        _retryDownload = retry;
        _retryDuration = Duration(seconds: seconds);
      }
    } else {
      _retryDownload = retry;
      _endRetryDownload();
    }
  }

  void _updateConnectionStatus(ConnectivityResult result) async {
    bool reachable = result == ConnectivityResult.none ? false : true;
    if (_networkReachable == reachable) return;

    _networkReachable = reachable;
    if (!reachable) {
      _endVersionCheckout();
      _endRetryDownload();
    } else {
      _updateRefreshTimer();
      _updateRetryTimer();
    }
  }

  void _updateRefreshTimer() {
    if (_keyMonitor.refreshKeyStackIsEmpty()) {
      _endVersionCheckout();
    } else {
      if (_refreshController == null &&
          _versionCheckout == true &&
          downloader != null) {
        _beginVersionCheckout();
      }
    }
  }

  void _updateRetryTimer() {
    if (_keyMonitor.retryKeyStackIsEmpty()) {
      _endRetryDownload();
    } else {
      if (_retryController != null &&
          _retryDownload == true &&
          downloader != null) {
        _beginRetryDownload();
      }
    }
  }

  void _beginVersionCheckout() {
    _refreshController = Timer.periodic(_refreshDuration, (_) {
      if (!_networkReachable) return;

      for (Type type in _keyMonitor.monitoredTypes()) {
        List<String>? keys = _keyMonitor.refreshKeys(type);
        if (keys != null && keys.isNotEmpty) {
          _updateExpiredObjects(keys, type);
        }
      }
    });
  }

  Future<void> _updateExpiredObjects(List<String> keys, Type type) async {
    if (!_keyMonitor.containsType(type) || downloader == null) return;

    if (downloader is VersionObjectDownloader) {
      VersionObjectDownloader manager = downloader as VersionObjectDownloader;
      VersionPackage version = await manager.checkoutVersion(keys, type);
      List<String> expiredKeys =
          _keyMonitor.expiredKeys(keys, version.versions, type);
      if (expiredKeys.isNotEmpty) {
        await removeObjects(expiredKeys, type);
      }

      if (version.objects == null) {
        DownloadPackage? downloads =
            await downloadObjects(version.requestKeys, type);
        if (downloads == null) return;

        List<String> keys = List.from(downloads.requestKeys);
        if (downloads.ignoredKeys != null) {
          keys.removeWhere((k) => downloads.ignoredKeys!.contains(k));
        }

        delegate?.didUpdateObjects(keys, type);
      } else {
        for (var value in version.objects!) {
          storeObject(value);
          delegate?.didUpdateObjects(keys, type);
        }
      }
    }
  }

  void _endVersionCheckout() {
    if (_refreshController != null) {
      _refreshController!.cancel();
      _refreshController = null;
    }
  }

  void _beginRetryDownload() {
    if (_retryController == null ||
        _keyMonitor.retryKeyStackIsEmpty() ||
        !_networkReachable) return;

    void updateObjects(
        List<CacheObject> objects, List<String> keys, Type type) {
      for (CacheObject object in objects) {
        _storage.updateObject(object);
      }

      delegate?.didDownloadRetryObjects(objects, type);
    }

    _retryController = Timer.periodic(_retryDuration, (value) {
      if (!_networkReachable) return;

      for (Type type in _keyMonitor.monitoredTypes()) {
        List<String>? keys = _keyMonitor.retryKeys(type);
        if (keys != null && keys.isNotEmpty) {
          downloader!.downloadObjects(keys, type).then((e) {
            if (e == null) return;
            updateObjects(e, keys, type);
          });
        }
      }
    });
  }

  void _endRetryDownload() {
    if (_retryController != null) {
      _retryController!.cancel();
      _retryController = null;
    }
  }

  @override
  void retryDownloadObjects(List<String> keys, Type type) {
    _keyMonitor.updateRetryKeys(keys, type);
    _updateRetryTimer();
  }

  @override
  void removeRetryDownloads(List<String> keys, Type type) {
    _keyMonitor.removeRetryKeys(keys, type);
    _updateRetryTimer();
  }

  void _updateMonitoredVersionFromObjects(List<CacheObject> objects, Type type,
      Function(CacheObject)? enumerationBlock) {
    bool cache = _storage.shouldCacheObjectType(type);
    if (cache) {
      _keyMonitor.updateVersions(objects, type, enumerationBlock);
      _updateRefreshTimer();
    } else {
      if (cache && enumerationBlock != null) {
        for (CacheObject object in objects) {
          enumerationBlock(object);
        }
      }
    }
  }

  @override
  void removeMonitoredVersions(List<String> keys, Type type) {
    _keyMonitor.removeVersions(keys, type);
    _updateRefreshTimer();
  }

  @override
  Future<bool> containsObject(String key, Type type) async {
    return await _storage.containsObject(key, type);
  }

  @override
  Future<void> removeObject(String key, Type type) async {
    await _storage.removeObject(key, type);
    removeMonitoredVersions([key], type);
  }

  @override
  Future<void> removeObjects(List<String> keys, Type type) async {
    await _storage.removeObjects(keys, type);
    removeMonitoredVersions(keys, type);
  }

  @override
  Future<void> storeObject(CacheObject object) async {
    _storage.storeObject(object);
    if (_storage.shouldCacheObjectType(object.runtimeType)) {
      _updateMonitoredVersionFromObjects([object], object.runtimeType, null);
    }
  }

  @override
  Future<DownloadPackage?> downloadObjects(List<String> keys, Type type) async {
    Completer<DownloadPackage?> completer = Completer();

    if (downloader == null || _keyMonitor.containsType(type)) {
      completer.complete(null);
      return completer.future;
    }

    try {
      List<CacheObject>? result = await downloader!.downloadObjects(keys, type);
      if (result != null) {
        DownloadPackage package = DownloadPackage(keys);
        List<CacheObject> newObjects = [];
        List<CacheObject> cachedObjects = [];
        List<CacheObject> updatedObjects = [];
        List<String> ignored = List.from(keys);

        _updateMonitoredVersionFromObjects(result, type, (p0) async {
          ignored.remove(p0.objectID());

          bool contains = await containsObject(p0.objectID(), type);
          bool expired = _keyMonitor.monitoredObjectIsExpired(p0);

          if (!contains) {
            await storeObject(p0);
            newObjects.add(p0);
          } else {
            if (expired) {
              await storeObject(p0);
              updatedObjects.add(p0);
            } else {
              cachedObjects.add(p0);
            }
          }

          package.ignoredKeys = ignored;
          package.newObjects = newObjects;
          package.cachedObjects = cachedObjects;
          package.updatedObjects = updatedObjects;
          completer.complete(package);
        });
      }
    } catch (e) {
      rethrow;
    }

    return completer.future;
  }

  Future<CacheObject?> getObject(String key, Type type) async {
    Completer<CacheObject?> completer = Completer();
    CacheObject? object = await _storage.getOneObject(key, type);
    if (_keyMonitor.containsType(type) && object != null) {
      _updateMonitoredVersionFromObjects([object], type, null);
    }

    completer.complete(object);
    return completer.future;
  }

  Future<CacheObject?> getObjectWhere(
      String where, Type type, List<Object>? whereArgs) async {
    Completer<CacheObject?> completer = Completer();
    CacheObject? object =
        await _storage.getOneObjectWhere(where, type, whereArgs);
    if (_keyMonitor.containsType(type) && object != null) {
      _updateMonitoredVersionFromObjects([object], type, null);
    }

    completer.complete(object);
    return completer.future;
  }

  Future<List<CacheObject>> getObjects(List<String> keys, Type type) async {
    Completer<List<CacheObject>> completer = Completer();
    List<CacheObject> objects = await _storage.getObjects(keys, type);
    if (_keyMonitor.containsType(type) && objects.isNotEmpty) {
      _updateMonitoredVersionFromObjects(objects, type, null);
    }

    completer.complete(objects);
    return completer.future;
  }

  Future<List<CacheObject>> getObjectsWhere(
      String where, Type type, List<Object>? whereArgs) async {
    Completer<List<CacheObject>> completer = Completer();
    List<CacheObject> objects =
        await _storage.getObjectsWhere(where, type, whereArgs);
    if (_keyMonitor.containsType(type) && objects.isNotEmpty) {
      _updateMonitoredVersionFromObjects(objects, type, null);
    }

    completer.complete(objects);
    return completer.future;
  }

  void getObjectsWithCompletion(
      List<String> keys,
      Type type,
      Function(List<CacheObject>?, List<String> keys) storage,
      Function(List<CacheObject>? downloads, List<String> keys) completion) {
    if (!_keyMonitor.containsType(type)) return;

    getObjects(keys, type).then((objects) {
      List<String> requestKeys = List.from(keys);
      List<String> storedKeys = [];
      if (objects.isNotEmpty) {
        _updateMonitoredVersionFromObjects(objects, type, (e) {
          storedKeys.add(e.objectID());
          requestKeys.remove(e.objectID());
        });
      }

      if (requestKeys.isNotEmpty) {
        downloadObjects(requestKeys, type).then((e) {
          if (e == null) {
            completion(null, keys);
          } else {
            List<String> downloadedKeys = List.from(e.requestKeys);
            if (e.ignoredKeys != null) {
              downloadedKeys.removeWhere((k) => e.ignoredKeys!.contains(k));
            }

            completion(e.newObjects, downloadedKeys);
          }
        });
      }
    });
  }
}
