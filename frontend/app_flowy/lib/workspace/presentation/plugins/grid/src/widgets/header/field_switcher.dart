import 'dart:typed_data';

import 'package:app_flowy/workspace/application/grid/field/type_option/type_option_service.dart';
import 'package:dartz/dartz.dart' show Either;
import 'package:flowy_infra/image.dart';
import 'package:flowy_infra/theme.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:flowy_infra_ui/style_widget/button.dart';
import 'package:flowy_infra_ui/style_widget/text.dart';
import 'package:flowy_sdk/log.dart';
import 'package:flowy_sdk/protobuf/flowy-error/errors.pb.dart';
import 'package:flowy_sdk/protobuf/flowy-grid-data-model/grid.pb.dart';
import 'package:flowy_sdk/protobuf/flowy-grid/checkbox_type_option.pbserver.dart';
import 'package:flowy_sdk/protobuf/flowy-grid/text_type_option.pb.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:app_flowy/startup/startup.dart';
import 'package:app_flowy/workspace/application/grid/prelude.dart';
import 'package:app_flowy/workspace/presentation/plugins/grid/src/layout/sizes.dart';
import 'package:app_flowy/workspace/presentation/plugins/grid/src/widgets/header/field_type_list.dart';
import 'package:app_flowy/workspace/presentation/plugins/grid/src/widgets/header/type_option/date.dart';
import 'field_type_extension.dart';
import 'type_option/multi_select.dart';
import 'type_option/number.dart';
import 'type_option/single_select.dart';

typedef UpdateFieldCallback = void Function(Field, Uint8List);
typedef SwitchToFieldCallback = Future<Either<EditFieldContext, FlowyError>> Function(
  String fieldId,
  FieldType fieldType,
);

class FieldSwitcher extends StatefulWidget {
  final SwitchFieldContext switchContext;
  final UpdateFieldCallback onUpdated;
  final SwitchToFieldCallback onSwitchToField;

  const FieldSwitcher({
    required this.switchContext,
    required this.onUpdated,
    required this.onSwitchToField,
    Key? key,
  }) : super(key: key);

  @override
  State<FieldSwitcher> createState() => _FieldSwitcherState();
}

class _FieldSwitcherState extends State<FieldSwitcher> {
  String? currentOverlayIdentifier;

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => getIt<FieldSwitcherBloc>(param1: widget.switchContext),
      child: BlocConsumer<FieldSwitcherBloc, FieldSwitchState>(
        listener: (context, state) {
          widget.onUpdated(state.field, state.typeOptionData);
        },
        builder: (context, state) {
          List<Widget> children = [_switchFieldTypeButton(context, state.field)];
          final typeOptionWidget = _typeOptionWidget(context: context, state: state);

          if (typeOptionWidget != null) {
            children.add(typeOptionWidget);
          }

          return ListView(
            shrinkWrap: true,
            children: children,
          );
        },
      ),
    );
  }

  Widget _switchFieldTypeButton(BuildContext context, Field field) {
    final theme = context.watch<AppTheme>();
    return SizedBox(
      height: GridSize.typeOptionItemHeight,
      child: FlowyButton(
        text: FlowyText.medium(field.fieldType.title(), fontSize: 12),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        hoverColor: theme.hover,
        onTap: () {
          final list = FieldTypeList(onSelectField: (newFieldType) {
            widget.onSwitchToField(field.id, newFieldType).then((result) {
              result.fold(
                (editFieldContext) {
                  context.read<FieldSwitcherBloc>().add(
                        FieldSwitchEvent.toFieldType(
                          editFieldContext.gridField,
                          editFieldContext.typeOptionData,
                        ),
                      );
                },
                (err) => Log.error(err),
              );
            });
          });
          _showOverlay(context, list);
        },
        leftIcon: svgWidget(field.fieldType.iconName(), color: theme.iconColor),
        rightIcon: svgWidget("grid/more", color: theme.iconColor),
      ),
    );
  }

  Widget? _typeOptionWidget({
    required BuildContext context,
    required FieldSwitchState state,
  }) {
    final overlayDelegate = TypeOptionOverlayDelegate(
      showOverlay: _showOverlay,
      hideOverlay: _hideOverlay,
    );

    final dataDelegate = TypeOptionDataDelegate(didUpdateTypeOptionData: (data) {
      context.read<FieldSwitcherBloc>().add(FieldSwitchEvent.didUpdateTypeOptionData(data));
    });

    final typeOptionContext = TypeOptionContext(
      gridId: state.gridId,
      field: state.field,
      data: state.typeOptionData,
    );

    final builder = _makeTypeOptionBuild(
      typeOptionContext: typeOptionContext,
      overlayDelegate: overlayDelegate,
      dataDelegate: dataDelegate,
    );

    return builder.customWidget;
  }

  void _showOverlay(BuildContext context, Widget child, {VoidCallback? onRemoved}) {
    final identifier = child.toString();
    if (currentOverlayIdentifier != null) {
      FlowyOverlay.of(context).remove(currentOverlayIdentifier!);
    }

    currentOverlayIdentifier = identifier;
    FlowyOverlay.of(context).insertWithAnchor(
      widget: OverlayContainer(
        child: child,
        constraints: BoxConstraints.loose(const Size(460, 440)),
      ),
      identifier: identifier,
      anchorContext: context,
      anchorDirection: AnchorDirection.leftWithCenterAligned,
      style: FlowyOverlayStyle(blur: false),
      anchorOffset: const Offset(-20, 0),
    );
  }

  void _hideOverlay(BuildContext context) {
    if (currentOverlayIdentifier != null) {
      FlowyOverlay.of(context).remove(currentOverlayIdentifier!);
    }
  }
}

abstract class TypeOptionBuilder {
  Widget? get customWidget;
}

TypeOptionBuilder _makeTypeOptionBuild({
  required TypeOptionContext typeOptionContext,
  required TypeOptionOverlayDelegate overlayDelegate,
  required TypeOptionDataDelegate dataDelegate,
}) {
  switch (typeOptionContext.field.fieldType) {
    case FieldType.Checkbox:
      return CheckboxTypeOptionBuilder(typeOptionContext.data);
    case FieldType.DateTime:
      return DateTypeOptionBuilder(typeOptionContext.data, overlayDelegate, dataDelegate);
    case FieldType.SingleSelect:
      return SingleSelectTypeOptionBuilder(typeOptionContext, overlayDelegate, dataDelegate);
    case FieldType.MultiSelect:
      return MultiSelectTypeOptionBuilder(typeOptionContext, overlayDelegate, dataDelegate);
    case FieldType.Number:
      return NumberTypeOptionBuilder(typeOptionContext.data, overlayDelegate, dataDelegate);
    case FieldType.RichText:
      return RichTextTypeOptionBuilder(typeOptionContext.data);

    default:
      throw UnimplementedError;
  }
}

abstract class TypeOptionWidget extends StatelessWidget {
  const TypeOptionWidget({Key? key}) : super(key: key);
}

typedef TypeOptionData = Uint8List;
typedef TypeOptionDataCallback = void Function(TypeOptionData typeOptionData);
typedef ShowOverlayCallback = void Function(
  BuildContext anchorContext,
  Widget child, {
  VoidCallback? onRemoved,
});
typedef HideOverlayCallback = void Function(BuildContext anchorContext);

class TypeOptionOverlayDelegate {
  ShowOverlayCallback showOverlay;
  HideOverlayCallback hideOverlay;
  TypeOptionOverlayDelegate({
    required this.showOverlay,
    required this.hideOverlay,
  });
}

class TypeOptionDataDelegate {
  TypeOptionDataCallback didUpdateTypeOptionData;

  TypeOptionDataDelegate({
    required this.didUpdateTypeOptionData,
  });
}

class RichTextTypeOptionBuilder extends TypeOptionBuilder {
  RichTextTypeOption typeOption;

  RichTextTypeOptionBuilder(TypeOptionData typeOptionData) : typeOption = RichTextTypeOption.fromBuffer(typeOptionData);

  @override
  Widget? get customWidget => null;
}

class CheckboxTypeOptionBuilder extends TypeOptionBuilder {
  CheckboxTypeOption typeOption;

  CheckboxTypeOptionBuilder(TypeOptionData typeOptionData) : typeOption = CheckboxTypeOption.fromBuffer(typeOptionData);

  @override
  Widget? get customWidget => null;
}
