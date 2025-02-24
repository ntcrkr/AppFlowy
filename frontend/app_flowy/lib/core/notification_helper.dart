import 'dart:async';
import 'dart:typed_data';
import 'package:flowy_sdk/protobuf/dart-notify/protobuf.dart';
import 'package:flowy_sdk/protobuf/flowy-user/protobuf.dart';
import 'package:dartz/dartz.dart';
import 'package:flowy_sdk/protobuf/flowy-error/errors.pb.dart';
import 'package:flowy_sdk/protobuf/flowy-folder/dart_notification.pb.dart';
import 'package:flowy_sdk/protobuf/flowy-grid/dart_notification.pb.dart';
import 'package:flowy_sdk/rust_stream.dart';

// User
typedef UserNotificationCallback = void Function(UserNotification, Either<Uint8List, FlowyError>);

class UserNotificationParser extends NotificationParser<UserNotification, FlowyError> {
  UserNotificationParser({required String id, required UserNotificationCallback callback})
      : super(
          id: id,
          callback: callback,
          tyParser: (ty) => UserNotification.valueOf(ty),
          errorParser: (bytes) => FlowyError.fromBuffer(bytes),
        );
}

// Folder
typedef FolderNotificationCallback = void Function(FolderNotification, Either<Uint8List, FlowyError>);

class FolderNotificationParser extends NotificationParser<FolderNotification, FlowyError> {
  FolderNotificationParser({String? id, required FolderNotificationCallback callback})
      : super(
          id: id,
          callback: callback,
          tyParser: (ty) => FolderNotification.valueOf(ty),
          errorParser: (bytes) => FlowyError.fromBuffer(bytes),
        );
}

// Grid
typedef GridNotificationCallback = void Function(GridNotification, Either<Uint8List, FlowyError>);

class GridNotificationParser extends NotificationParser<GridNotification, FlowyError> {
  GridNotificationParser({String? id, required GridNotificationCallback callback})
      : super(
          id: id,
          callback: callback,
          tyParser: (ty) => GridNotification.valueOf(ty),
          errorParser: (bytes) => FlowyError.fromBuffer(bytes),
        );
}

typedef GridNotificationHandler = Function(GridNotification ty, Either<Uint8List, FlowyError> result);

class GridNotificationListener {
  StreamSubscription<SubscribeObject>? _subscription;
  GridNotificationParser? _parser;

  GridNotificationListener({required String objectId, required GridNotificationHandler handler})
      : _parser = GridNotificationParser(id: objectId, callback: handler) {
    _subscription = RustStreamReceiver.listen((observable) => _parser?.parse(observable));
  }

  Future<void> stop() async {
    _parser = null;
    await _subscription?.cancel();
  }
}

class NotificationParser<T, E> {
  String? id;
  void Function(T, Either<Uint8List, E>) callback;

  T? Function(int) tyParser;
  E Function(Uint8List) errorParser;

  NotificationParser({this.id, required this.callback, required this.errorParser, required this.tyParser});
  void parse(SubscribeObject subject) {
    if (id != null) {
      if (subject.id != id) {
        return;
      }
    }

    final ty = tyParser(subject.ty);
    if (ty == null) {
      return;
    }

    if (subject.hasError()) {
      final bytes = Uint8List.fromList(subject.error);
      final error = errorParser(bytes);
      callback(ty, right(error));
    } else {
      final bytes = Uint8List.fromList(subject.payload);
      callback(ty, left(bytes));
    }
  }
}
