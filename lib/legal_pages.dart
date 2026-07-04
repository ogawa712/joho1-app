import 'package:flutter/material.dart';

const _kBg = Color(0xFFF0F4FF);

const String kContactEmail = 'supportcontact77@gmail.com';
const String kAppName = '情報Ⅰ プログラミング対策';
const String kPolicyEffectiveDate = '2026年7月2日';

class _LegalTextPage extends StatelessWidget {
  final String title;
  final String body;

  const _LegalTextPage({required this.title, required this.body});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBg,
      appBar: AppBar(
        backgroundColor: _kBg,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: Text(
          title,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Color(0xFF1A1A2E)),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: SelectableText(
          body,
          style: const TextStyle(fontSize: 13.5, height: 1.9, color: Color(0xFF1A1A2E)),
        ),
      ),
    );
  }
}

class TermsOfServicePage extends StatelessWidget {
  const TermsOfServicePage({super.key});

  @override
  Widget build(BuildContext context) {
    return const _LegalTextPage(title: '利用規約', body: _termsBody);
  }
}

class PrivacyPolicyPage extends StatelessWidget {
  const PrivacyPolicyPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const _LegalTextPage(title: 'プライバシーポリシー', body: _privacyBody);
  }
}

const String _termsBody = '''
利用規約

制定日: $kPolicyEffectiveDate

この利用規約（以下「本規約」）は、$kAppName（以下「本アプリ」）の利用条件を定めるものです。本アプリをダウンロード・利用したユーザー（以下「ユーザー」）は、本規約に同意したものとみなします。

第1条（本アプリの内容）
本アプリは、大学入学共通テスト「情報I」対策として、プログラミング（Python）を中心とした問題演習機能を提供する学習支援アプリです。

第2条（利用料金・アプリ内課金）
1. 本アプリの基本機能は無料でご利用いただけます。
2. 本アプリでは「広告非表示」機能を、Apple App Store／Google Playを通じた月額の自動更新サブスクリプションとして提供しています。
3. サブスクリプションは、ユーザーが解約手続きを行わない限り、契約期間終了時に自動的に更新され、料金が発生します。
4. 解約は、次回更新日の24時間前までにApp Store／Google Playの設定から行う必要があります。解約手続きの方法は各プラットフォームの案内に従います。
5. アプリ内課金の決済は、Apple社またはGoogle社の提供する決済システムを通じて行われ、購入内容の詳細（価格、無料トライアルの有無、返金等を含む）は各プラットフォームの規約に従います。
6. 開発者は、サブスクリプションの内容・価格を変更する場合があります。価格変更は、適用法令に従い事前にユーザーに通知します。

第3条（広告の表示）
1. 本アプリは、広告非表示機能を購入していない場合、Google AdMobを通じた広告を表示します。
2. 広告の配信に関する事項は、プライバシーポリシーをご確認ください。

第4条（禁止事項）
ユーザーは、本アプリの利用にあたり、以下の行為をしてはなりません。
・本アプリのリバースエンジニアリング、逆コンパイル、逆アセンブルその他の解析行為
・本アプリの複製、改変、再配布
・本アプリの運営を妨害する行為
・法令または公序良俗に違反する行為
・その他、開発者が不適切と判断する行為

第5条（免責事項）
1. 本アプリで提供する問題・解説等の学習コンテンツは、大学入学共通テストでの得点を保証するものではありません。
2. 開発者は、本アプリの利用によりユーザーに生じた損害について、開発者の故意または重大な過失による場合を除き、責任を負わないものとします。
3. 本アプリは予告なく内容の変更、提供の中断・終了を行うことがあります。

第6条（知的財産権）
本アプリに含まれる文章、プログラム、デザイン等の著作権その他の知的財産権は、開発者または正当な権利者に帰属します。

第7条（規約の変更）
開発者は、必要と判断した場合、ユーザーへの事前通知なく本規約を変更できるものとします。変更後の規約は、本アプリ内に表示した時点から効力を生じます。

第8条（お問い合わせ）
本規約に関するお問い合わせは、下記の連絡先までお願いいたします。
連絡先: $kContactEmail
''';

const String _privacyBody = '''
プライバシーポリシー

制定日: $kPolicyEffectiveDate

$kAppName（以下「本アプリ」）における、ユーザーの情報の取り扱いについて説明します。

第1条（本アプリが取得する情報）
1. 本アプリは、氏名・メールアドレス等の個人を特定できる情報を、ユーザーに直接入力させる形では取得しません。
2. 本アプリの学習進捗（正解数、間違えた問題、ブックマークした問題、広告非表示サブスクリプションの契約状態など）は、ユーザーの端末内にのみ保存され、開発者のサーバー等の外部には送信されません。
3. アプリ内課金（広告非表示サブスクリプション）の決済処理は、Apple社またはGoogle社が提供する仕組みを通じて行われ、クレジットカード情報等の決済情報を本アプリおよび開発者が取得することはありません。

第2条（広告配信事業者による情報取得）
1. 本アプリは、広告表示のためGoogle AdMob（Google社が提供する広告配信サービス）を利用しています。
2. AdMobは、広告の表示・効果測定・不正防止等の目的で、広告識別子（IDFA／広告ID）、おおよその位置情報、端末情報等を取得する場合があります。
3. iOSでは、App Tracking Transparency（ATT）の仕組みに基づき、トラッキングを目的とした識別子の利用についてユーザーに許諾を求めます。ユーザーが許諾しない場合、パーソナライズされていない広告が配信されます。
4. Google社によるデータの取り扱いについては、以下のGoogleのプライバシーポリシーをご確認ください。
   https://policies.google.com/privacy

第3条（情報の利用目的）
本アプリが取得・利用する情報は、以下の目的のために利用します。
・広告の配信および広告効果の測定
・アプリ内課金の購入状態の管理
・本アプリの品質改善（クラッシュ等の技術的なログを含む場合があります）

第4条（第三者提供）
開発者は、法令に基づく場合を除き、ユーザーの情報を本人の同意なく第三者に提供することはありません。ただし、第2条に記載の広告配信事業者への情報提供はこの限りではありません。

第5条（情報の管理）
端末内に保存される学習データは、アプリの削除により消去されます。開発者はこれらのデータを外部で保管していません。

第6条（お子様のご利用について）
本アプリは学習目的のアプリですが、広告配信を含むため、13歳未満のお子様が利用される場合は保護者の方の管理のもとでご利用ください。

第7条（プライバシーポリシーの変更）
本ポリシーの内容は、法令の変更やサービス内容の変更等に応じて、予告なく変更されることがあります。変更後の内容は、本アプリ内に表示した時点から効力を生じます。

第8条（お問い合わせ）
本ポリシーに関するお問い合わせは、下記の連絡先までお願いいたします。
連絡先: $kContactEmail
''';
