import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'dio_provider.g.dart';

@Riverpod(keepAlive: true)
Dio dio(Ref ref) {
  final dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 30),
      headers: {'User-Agent': 'Noctua-app'},
    ),
  );

  if (kDebugMode) {
    dio.interceptors.add(LogInterceptor(requestHeader: false, responseHeader: false, logPrint: (o) => debugPrint('$o')));
  }

  return dio;
}
