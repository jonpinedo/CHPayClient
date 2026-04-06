import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:open_filex/open_filex.dart';
import 'ziti_service.dart';

const String _kBaseUrl = 'http://chpay-api.private';

class UpdateInfo {
  final int versionCode;
  final String versionName;
  final bool mandatory;
  final String changelog;
  final bool available;

  const UpdateInfo({
    required this.versionCode,
    required this.versionName,
    required this.mandatory,
    required this.changelog,
    required this.available,
  });

  factory UpdateInfo.fromJson(Map<String, dynamic> json) => UpdateInfo(
        versionCode: json['versionCode'] as int,
        versionName: json['versionName'] as String,
        mandatory:   json['mandatory']   as bool,
        changelog:   json['changelog']   as String,
        available:   json['available']   as bool,
      );
}

class UpdateService {
  static const _channel = MethodChannel('com.chpayclient/update');

  /// Consulta el servidor y devuelve [UpdateInfo] si hay una versión más nueva,
  /// o null si la app está al día o si la consulta falla (no bloqueante).
  static Future<UpdateInfo?> checkForUpdate() async {
    try {
      final response = await ZitiService.get('$_kBaseUrl/api/update/version');
      if (response.statusCode != 200) return null;

      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final info = UpdateInfo.fromJson(json);
      if (!info.available) return null;

      final pkg = await PackageInfo.fromPlatform();
      final localCode = int.tryParse(pkg.buildNumber) ?? 0;

      if (info.versionCode <= localCode) return null;
      return info;
    } catch (_) {
      return null;
    }
  }

  /// Descarga el APK e invoca el instalador del sistema Android.
  /// Devuelve true si el instalador se abrió correctamente.
  static Future<bool> downloadAndInstall(String bearer) async {
    final status = await Permission.requestInstallPackages.request();
    if (!status.isGranted) {
      throw Exception('Permiso REQUEST_INSTALL_PACKAGES denegado');
    }

    final result = await _channel.invokeMethod<Map>('downloadApk', {
      'url':    '$_kBaseUrl/api/update/apk',
      'bearer': bearer,
    });

    final path = result?['path'] as String?;
    if (path == null || !File(path).existsSync()) {
      throw Exception('APK no encontrado tras la descarga');
    }

    final openResult = await OpenFilex.open(
      path,
      type: 'application/vnd.android.package-archive',
    );
    return openResult.type == ResultType.done;
  }
}
