import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

import 'package:biometric_mobile/core/storage/secure_token_store.dart';

/// In-memory [TokenStore] for tests.
class InMemoryTokenStore implements TokenStore {
  String? access;
  String? refresh;

  @override
  Future<void> saveTokens({
    required String access,
    required String refresh,
  }) async {
    this.access = access;
    this.refresh = refresh;
  }

  @override
  Future<void> saveAccess(String access) async => this.access = access;

  @override
  Future<String?> readAccess() async => access;

  @override
  Future<String?> readRefresh() async => refresh;

  @override
  Future<bool> hasTokens() async => refresh != null && refresh!.isNotEmpty;

  @override
  Future<void> clear() async {
    access = null;
    refresh = null;
  }
}

/// A canned response for [FakeHttpAdapter].
class FakeResponse {
  final int statusCode;
  final Object body;
  const FakeResponse(this.statusCode, this.body);
}

/// Dio adapter that returns canned responses based on the request path.
/// [handler] receives the [RequestOptions] and returns a [FakeResponse]; throw
/// a [DioException] to simulate connection errors.
class FakeHttpAdapter implements HttpClientAdapter {
  FakeHttpAdapter(this.handler);

  final FakeResponse Function(RequestOptions options) handler;

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final res = handler(options);
    final bytes = utf8.encode(jsonEncode(res.body));
    return ResponseBody.fromBytes(
      bytes,
      res.statusCode,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }
}
