// What the browser treats as an ad.
//
// Two mechanisms share this data:
//
// 1. The WebView's native content blockers ([adContentBlockers]) stop
//    the request before it leaves the device — every banner, tracker,
//    ad script and ad redirect on the lists below.
// 2. A document-start user script ([adHideScript]) keeps [adHideCss]
//    on the page, hiding what a blocked request would have left behind
//    (empty slots, overlays, sponsored widgets).

import 'dart:convert';

import 'package:flutter_inappwebview/flutter_inappwebview.dart';

/// Ad and tracking networks, matched as domains: a host matches when
/// it equals an entry or ends in `.entry`, so `ad.doubleclick.net` is
/// caught by `doubleclick.net` while `notdoubleclick.net` is not.
const blockedAdDomains = <String>[
  // Google ad serving.
  'doubleclick.net',
  'googlesyndication.com',
  'googleadservices.com',
  'googletagservices.com',
  'adservice.google.com',
  '2mdn.net',
  'admob.com',
  // Programmatic exchanges and SSPs.
  'adnxs.com',
  'rubiconproject.com',
  'pubmatic.com',
  'openx.net',
  'casalemedia.com',
  'smartadserver.com',
  'adform.net',
  'media.net',
  'indexww.com',
  'sovrn.com',
  'lijit.com',
  'sharethrough.com',
  'sonobi.com',
  'bidswitch.net',
  '33across.com',
  'adition.com',
  'adkernel.com',
  'sitescout.com',
  'yieldmanager.com',
  'ads.yahoo.com',
  // Ad tech: verification, targeting, demand.
  'criteo.com',
  'criteo.net',
  'adsrvr.org',
  'demdex.net',
  'everesttech.net',
  'bluekai.com',
  'krxd.net',
  'exelator.com',
  'agkn.com',
  'advertising.com',
  'mathtag.com',
  'serving-sys.com',
  'adtechus.com',
  'doubleverify.com',
  'adsafeprotected.com',
  'moatads.com',
  // Native, content-recommendation and sponsor units.
  'taboola.com',
  'taboola.net',
  'taboolasyndication.com',
  'outbrain.com',
  'outbrainimg.com',
  'mgid.com',
  'revcontent.com',
  'content.ad',
  'adskeeper.com',
  'zergnet.com',
  'adblade.com',
  'buysellads.com',
  'carbonads.com',
  'gumgum.com',
  'teads.tv',
  'yieldmo.com',
  'smartclip.net',
  // Video ad serving.
  'springserve.com',
  'vidible.tv',
  // Interstitial, popup and pop-under networks.
  'adsterra.com',
  'propellerads.com',
  'popads.net',
  'popmyads.com',
  'hilltopads.com',
  'clickadu.com',
  'adcash.com',
  'exoclick.com',
  // Mobile ad SDKs (their web endpoints).
  'adcolony.com',
  'applovin.com',
  'chartboost.com',
  'inmobi.com',
  'vungle.com',
  'mintegral.com',
  'unityads.unity3d.com',
  'startappservice.com',
  'ironsrc.com',
  'supersonicads.com',
  'amazon-adsystem.com',
];

/// Path segments that mark an ad resource on any host, so a site's
/// own `/ads/banner.js` is blocked too. The patterns must match the
/// whole url (the native side uses `Matcher.matches`) and only ever
/// see subresources — pages are never blocked by their path.
const _adPathPatterns = <String>[
  '.*/ads?(/|\$|\\?|#).*',
  '.*/adserver(/|\$|\\?|#).*',
  '.*/adframe(/|\$|\\?|#).*',
  '.*/pagead(/|\$|\\?|#).*',
  '.*/adsbygoogle.*',
  '.*/prebid.*',
  '.*/ads?\\.php.*',
  '.*/ads?\\.js.*',
];

/// Resource types the path rules apply to: everything except the
/// page itself ([ContentBlockerTriggerResourceType.DOCUMENT]).
List<ContentBlockerTriggerResourceType> _subresourceTypes() => [
      ContentBlockerTriggerResourceType.IMAGE,
      ContentBlockerTriggerResourceType.STYLE_SHEET,
      ContentBlockerTriggerResourceType.SCRIPT,
      ContentBlockerTriggerResourceType.FONT,
      ContentBlockerTriggerResourceType.MEDIA,
      ContentBlockerTriggerResourceType.SVG_DOCUMENT,
      ContentBlockerTriggerResourceType.RAW,
    ];

/// The rules for the WebView's native content blocker: one rule for
/// the known ad hosts (all resource types, pages included, so ad
/// redirects die too) plus one per path pattern for subresources.
List<ContentBlocker> adContentBlockers() {
  final hosts = blockedAdDomains.map(RegExp.escape).join('|');
  return [
    ContentBlocker(
      trigger: ContentBlockerTrigger(
        urlFilter: '^https?://([^/?#]*\\.)?($hosts)(:[0-9]+)?([/?#].*)?\$',
      ),
      action: ContentBlockerAction(type: ContentBlockerActionType.BLOCK),
    ),
    for (final pattern in _adPathPatterns)
      ContentBlocker(
        trigger: ContentBlockerTrigger(
          urlFilter: pattern,
          resourceType: _subresourceTypes(),
        ),
        action: ContentBlockerAction(type: ContentBlockerActionType.BLOCK),
      ),
  ];
}

/// Whether [url] comes from one of [blockedAdDomains].
bool blocksAdHost(Uri url) {
  final host = url.host.toLowerCase();
  if (host.isEmpty) return false;
  for (final domain in blockedAdDomains) {
    if (host == domain || host.endsWith('.$domain')) return true;
  }
  return false;
}

/// Whether [url] is an ad resource by host or by its path — the same
/// decision the native rules make, for callers that run in Dart
/// (navigation cancels, pop-up filtering, tests).
bool blocksAdUrl(Uri url) {
  if (blocksAdHost(url)) return true;
  final target = url.toString();
  return _adPathPatterns.any(
    (pattern) => RegExp(pattern, caseSensitive: false).hasMatch(target),
  );
}

/// Hides what a blocked request would have left on the page: banner
/// slots, ad iframes, overlays, sponsored and native-ad widgets.
const adHideCss = '''
ins.adsbygoogle,
.adsbygoogle,
[class*="adsbygoogle"],
.google-auto-placed,
[id^="div-gpt-ad"],
[id^="google_ads"],
[id^="aswift"],
iframe[src*="doubleclick"],
iframe[src*="googlesyndication"],
iframe[src*="adnxs"],
iframe[src*="adservice.google"],
.ad-slot,
.ad-banner,
.ad-container,
.ad-wrapper,
.ad-unit,
.ad-label,
.ad-sticky,
.ad-overlay,
.ad-popup,
[class*="ad-banner"],
[class*="ad-container"],
[class*="ad-wrapper"],
[class*="ad-slot"],
[class*="ad-overlay"],
[class*="ad-popup"],
[class*="fullscreen-ad"],
[class*="interstitial"],
.ad,
.ads,
#ad,
#ads,
.sponsored,
.sponsored-post,
.sponsored-content,
[class*="sponsored-"],
.native-ad,
[class*="native-ad"],
.advert,
div[id^="taboola"],
.taboola,
[class*="taboola"],
.OUTBRAIN,
.outbrain,
div[id^="outbrain"],
[class*="outbrain"],
.player-ad-overlay,
.ad-showing,
[class*="ad-showing"]
''';

/// The script that keeps [adHideCss] applied in every frame and lets
/// the toggle flip it in pages that are already open: it defines
/// `window.__mplayerAdBlock(enabled)` and applies [enabled] at once.
String adHideScript(bool enabled) => '''
(function () {
  var css = ${jsonEncode(adHideCss)};
  var id = 'mplayer-adblock-style';
  function apply (on) {
    var el = document.getElementById(id);
    if (!el) {
      el = document.createElement('style');
      el.id = id;
      (document.documentElement || document.head || document).appendChild(el);
    }
    el.textContent = on ? css : '';
  }
  window.__mplayerAdBlock = apply;
  apply($enabled);
})();
''';
