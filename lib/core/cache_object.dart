import 'dart:async';

abstract class CacheObject {
  String objectID();
  String objectVersion();
  bool ignored();
  Map<String, dynamic> toMap();
}

abstract class CacheObjectManagerDelegate {
  void didUpdateObjects(List<String> keys, Type type);
  void didDownloadRetryObjects(List<CacheObject> objects, Type type);
}

abstract class CacheObjectDownloader {
  Future<List<CacheObject>?> downloadObjects(List<String> objectIDs, Type type);
  List<String> shouldDownloadObjectIDs(List<String> objectIDs, Type type);
  List<String> objectsInDownloading(List<String> objectIDs, Type type);
}

class VersionPackage {
  VersionPackage(this.requestKeys, this.ignoredKeys, this.versions);

  final Map<String, String> versions;
  List<CacheObject>? objects;
  final List<String> requestKeys;
  final List<String> ignoredKeys;
}

abstract class VersionObjectDownloader extends CacheObjectDownloader {
  Future<VersionPackage> checkoutVersion(List<String> objectIDs, Type type);
}

class DownloadPackage {
  DownloadPackage(this.requestKeys);

  List<CacheObject>? newObjects;
  List<CacheObject>? cachedObjects;
  List<CacheObject>? updatedObjects;
  final List<String> requestKeys;
  List<String>? ignoredKeys;
}

abstract class CacheObjectManager {
  void startMonitoring(Type type);
  void stopMonitoring(Type type);
  List<String> getMonitoredObjectIDs(List<String> objectIDs, Type type);
  bool objectInMonitoring(String objectID, Type type);
  FutureOr<DownloadPackage?> downloadObjects(List<String> keys, Type type);
  void retryDownloadObjects(List<String> keys, Type type);
  void removeRetryDownloads(List<String> keys, Type type);
  void removeMonitoredVersions(List<String> keys, Type type);
  Future<bool> containsObject(String key, Type type);
  Future<void> storeObject(CacheObject object);
  Future<void> removeObject(String key, Type type);
  Future<void> removeObjects(List<String> keys, Type type);
}
