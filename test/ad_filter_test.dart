// Ad blocking rules.

import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:movie_player/ad_filter.dart';

void main() {
  group('blocked hosts', () {
    test('known ad domains and their subdomains match', () {
      expect(
        blocksAdHost(Uri.parse('https://ad.doubleclick.net/x')),
        isTrue,
      );
      expect(blocksAdHost(Uri.parse('https://doubleclick.net/')), isTrue);
      expect(
        blocksAdHost(
          Uri.parse('https://pagead2.googlesyndication.com/pagead/js/ads.js'),
        ),
        isTrue,
      );
      expect(
        blocksAdHost(Uri.parse('https://adservice.google.com/pagead')),
        isTrue,
      );
      expect(
        blocksAdHost(
            Uri.parse('https://securepubads.g.doubleclick.net/gampad')),
        isTrue,
      );
    });

    test('ordinary sites stay untouched', () {
      // A path is not a host: /ads on a normal site is fine here.
      expect(blocksAdHost(Uri.parse('https://example.com/ads')), isFalse);
      expect(blocksAdHost(Uri.parse('https://notdoubleclick.net/')), isFalse);
      expect(
        blocksAdHost(Uri.parse('https://doubleclick.net.evil.com/')),
        isFalse,
      );
      expect(blocksAdHost(Uri.parse('https://example.com/')), isFalse);
    });
  });

  group('ad urls', () {
    test('ad hosts and ad paths on any host match', () {
      expect(blocksAdUrl(Uri.parse('https://ad.doubleclick.net/x')), isTrue);
      expect(blocksAdUrl(Uri.parse('https://site.com/ads/banner.js')), isTrue);
      expect(blocksAdUrl(Uri.parse('https://site.com/ad')), isTrue);
      expect(blocksAdUrl(Uri.parse('https://site.com/ads?x=1')), isTrue);
      expect(blocksAdUrl(Uri.parse('https://site.com/js/ad.php?x=1')), isTrue);
      expect(blocksAdUrl(Uri.parse('https://site.com/adframe/1')), isTrue);
      expect(blocksAdUrl(Uri.parse('https://site.com/pagead/adsbygoogle.js')),
          isTrue);
    });

    test('lookalike paths do not match', () {
      expect(blocksAdUrl(Uri.parse('https://site.com/loads/x.js')), isFalse);
      expect(blocksAdUrl(Uri.parse('https://site.com/article')), isFalse);
      expect(blocksAdUrl(Uri.parse('https://site.com/js/add.js')), isFalse);
      expect(blocksAdUrl(Uri.parse('https://site.com/readme')), isFalse);
    });
  });

  group('native rules', () {
    test('one host rule plus path rules that skip the page itself', () {
      final rules = adContentBlockers();

      // The host rule: every resource type, pages included.
      expect(rules, isNotEmpty);
      expect(rules.first.trigger.urlFilter, contains('doubleclick'));
      expect(rules.first.trigger.resourceType, isEmpty);
      expect(rules.first.action.type, ContentBlockerActionType.BLOCK);

      // The path rules never block a document, so a page under a
      // blocked path still opens.
      for (final rule in rules.skip(1)) {
        expect(rule.action.type, ContentBlockerActionType.BLOCK);
        expect(rule.trigger.resourceType, isNotEmpty);
        expect(
          rule.trigger.resourceType,
          isNot(contains(ContentBlockerTriggerResourceType.DOCUMENT)),
        );
      }
    });
  });

  group('hide script', () {
    test('carries the css and the current flag', () {
      final on = adHideScript(true);
      expect(on, contains('adsbygoogle'));
      expect(on, contains('window.__mplayerAdBlock'));
      expect(on, contains('apply(true)'));
      expect(adHideScript(false), contains('apply(false)'));
    });

    test('the css hides ad slots, iframes and overlays', () {
      expect(adHideCss, contains('div[id^="taboola"]'));
      expect(adHideCss, contains('iframe[src*="doubleclick"]'));
      expect(adHideCss, contains('[class*="ad-overlay"]'));
    });
  });
}
