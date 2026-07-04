import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:shared_preferences/shared_preferences.dart';

// App Store Connect(自動更新サブスクリプション)/ Google Play Console(定期購入)
// で作成する商品IDと完全に一致させること。
const String kRemoveAdsProductId = 'net.ogawalab.joho1App.removeads_monthly';

const _prefKeyAdsRemovedUntil = 'ads_removed_until_millis';

// in_app_purchaseはサブスクリプションの有効期限をプラットフォーム非依存の形では
// 教えてくれない(サーバー側のレシート検証が本来必要)。そのため、購入/復元が
// 成功するたびに「このぶんだけ広告非表示を延長する」という簡易的な有効期限を
// 端末内に保存し、その期限を過ぎたら自動的に広告表示に戻す運用にしている。
// 月額課金の実際の更新周期(約30日)より少し長めに猶予を持たせてある。
const _subscriptionGraceDays = 32;

bool get _iapSupported => !kIsWeb && (Platform.isIOS || Platform.isAndroid);

/// 「広告非表示」が現在有効かどうか。UIはこれを購読して表示を切り替える。
final ValueNotifier<bool> adsRemovedNotifier = ValueNotifier<bool>(false);

class PurchaseManager {
  PurchaseManager._();

  static StreamSubscription<List<PurchaseDetails>>? _subscription;
  static ProductDetails? _removeAdsProduct;

  static Future<void> init() async {
    await _refreshLocalExpiry();

    if (!_iapSupported) return;

    final iap = InAppPurchase.instance;
    if (!await iap.isAvailable()) return;

    _subscription = iap.purchaseStream.listen(
      _handlePurchaseUpdates,
      onDone: () => _subscription?.cancel(),
      onError: (_) {},
    );

    final response = await iap.queryProductDetails({kRemoveAdsProductId});
    if (response.productDetails.isNotEmpty) {
      _removeAdsProduct = response.productDetails.first;
    }

    // 起動時に購読状態を再同期する(更新されていれば有効期限が延長される)
    await iap.restorePurchases();
  }

  static ProductDetails? get removeAdsProduct => _removeAdsProduct;

  static Future<void> buySubscription() async {
    final product = _removeAdsProduct;
    if (product == null || !_iapSupported) return;
    final purchaseParam = PurchaseParam(productDetails: product);
    // サブスクリプションもin_app_purchaseではbuyNonConsumableを使う
    // (消費/非消費の区別であり、更新型かどうかはストア側の商品設定で決まる)。
    await InAppPurchase.instance.buyNonConsumable(purchaseParam: purchaseParam);
  }

  /// アプリのフォアグラウンド復帰時などに呼び、ストアの購読状態を再確認する。
  static Future<void> refreshStatus() async {
    await _refreshLocalExpiry();
    if (_iapSupported) {
      await InAppPurchase.instance.restorePurchases();
    }
  }

  static Future<void> restorePurchases() async {
    if (!_iapSupported) return;
    await InAppPurchase.instance.restorePurchases();
  }

  static Future<void> _handlePurchaseUpdates(
      List<PurchaseDetails> purchases) async {
    for (final purchase in purchases) {
      if (purchase.productID != kRemoveAdsProductId) continue;

      switch (purchase.status) {
        case PurchaseStatus.purchased:
        case PurchaseStatus.restored:
          await _extendAdsRemoved();
          break;
        case PurchaseStatus.error:
        case PurchaseStatus.canceled:
        case PurchaseStatus.pending:
          break;
      }

      if (purchase.pendingCompletePurchase) {
        await InAppPurchase.instance.completePurchase(purchase);
      }
    }
  }

  static Future<void> _extendAdsRemoved() async {
    final until = DateTime.now().add(const Duration(days: _subscriptionGraceDays));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_prefKeyAdsRemovedUntil, until.millisecondsSinceEpoch);
    adsRemovedNotifier.value = true;
  }

  static Future<void> _refreshLocalExpiry() async {
    final prefs = await SharedPreferences.getInstance();
    final untilMillis = prefs.getInt(_prefKeyAdsRemovedUntil);
    if (untilMillis == null) {
      adsRemovedNotifier.value = false;
      return;
    }
    final until = DateTime.fromMillisecondsSinceEpoch(untilMillis);
    adsRemovedNotifier.value = DateTime.now().isBefore(until);
  }

  static void dispose() {
    _subscription?.cancel();
    _subscription = null;
  }
}
