// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'comment_translation_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(CommentTranslationNotifier)
final commentTranslationProvider = CommentTranslationNotifierProvider._();

final class CommentTranslationNotifierProvider
    extends $NotifierProvider<CommentTranslationNotifier, int> {
  CommentTranslationNotifierProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'commentTranslationProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$commentTranslationNotifierHash();

  @$internal
  @override
  CommentTranslationNotifier create() => CommentTranslationNotifier();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(int value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<int>(value),
    );
  }
}

String _$commentTranslationNotifierHash() =>
    r'bfe39bd3d0efa90ac3ca26b6f1e7d1b2781dac5a';

abstract class _$CommentTranslationNotifier extends $Notifier<int> {
  int build();
  @$mustCallSuper
  @override
  void runBuild() {
    final ref = this.ref as $Ref<int, int>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<int, int>,
              int,
              Object?,
              Object?
            >;
    element.handleCreate(ref, build);
  }
}
