import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

class AdService {
  // ── Gerçek Ad Unit ID'ler ──────────────────────────────────────
  static const String _bannerAdUnitId =
      'ca-app-pub-4724604313563318/7668392596';

  // ── Banner Reklam ──────────────────────────────────────────────
  static BannerAd? _bannerAd;
  static bool _isBannerLoaded = false;

  static BannerAd? get bannerAd => _isBannerLoaded ? _bannerAd : null;

  static void loadBannerAd({VoidCallback? onLoaded}) {
    _bannerAd = BannerAd(
      adUnitId: _bannerAdUnitId,
      size: AdSize.banner,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (ad) {
          _isBannerLoaded = true;
          onLoaded?.call();
        },
        onAdFailedToLoad: (ad, error) {
          _isBannerLoaded = false;
          ad.dispose();
        },
      ),
    )..load();
  }

  static void disposeBanner() {
    _bannerAd?.dispose();
    _bannerAd = null;
    _isBannerLoaded = false;
  }

  // ── Interstitial Reklam (Oyun Bitince) ────────────────────────
  static InterstitialAd? _interstitialAd;

  static void loadInterstitialAd() {
    InterstitialAd.load(
      adUnitId: _bannerAdUnitId, // Aynı ID (gerekirse ayrı oluşturun)
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) {
          _interstitialAd = ad;
        },
        onAdFailedToLoad: (error) {
          _interstitialAd = null;
        },
      ),
    );
  }

  static void showInterstitialAd({VoidCallback? onDismissed}) {
    if (_interstitialAd == null) {
      onDismissed?.call();
      return;
    }
    _interstitialAd!.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        _interstitialAd = null;
        onDismissed?.call();
      },
      onAdFailedToShowFullScreenContent: (ad, error) {
        ad.dispose();
        _interstitialAd = null;
        onDismissed?.call();
      },
    );
    _interstitialAd!.show();
  }

  // ── Rewarded Reklam (Sihirli Değnek) ──────────────────────────
  static RewardedAd? _rewardedAd;
  static bool _isRewardedAdLoaded = false;

  static bool get isRewardedAdReady => _isRewardedAdLoaded && _rewardedAd != null;

  static void loadRewardedAd() {
    RewardedAd.load(
      adUnitId: 'ca-app-pub-3940256099942544/5224354917', // Test ID - gerçek ID ile değiştirin
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (ad) {
          _rewardedAd = ad;
          _isRewardedAdLoaded = true;
        },
        onAdFailedToLoad: (error) {
          _rewardedAd = null;
          _isRewardedAdLoaded = false;
        },
      ),
    );
  }

  static void showRewardedAd({required VoidCallback onRewarded, VoidCallback? onDismissed}) {
    if (_rewardedAd == null) {
      onDismissed?.call();
      return;
    }
    _rewardedAd!.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        _rewardedAd = null;
        _isRewardedAdLoaded = false;
        loadRewardedAd(); // Preload next one
        onDismissed?.call();
      },
      onAdFailedToShowFullScreenContent: (ad, error) {
        ad.dispose();
        _rewardedAd = null;
        _isRewardedAdLoaded = false;
        loadRewardedAd();
        onDismissed?.call();
      },
    );
    _rewardedAd!.show(
      onUserEarnedReward: (ad, reward) {
        onRewarded();
      },
    );
  }
}
