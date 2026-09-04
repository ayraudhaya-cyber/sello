/**
 * Sello PWA install bridge for Flutter web.
 *
 * - Chromium: captures `beforeinstallprompt` for an in-app Install button.
 * - iOS / iPadOS: no programmatic install; Flutter shows Share → Add to Home Screen.
 * Loaded from index.html before Flutter boots.
 */
(function () {
  'use strict';

  var deferredPrompt = null;
  var markedInstalled = false;
  /** True once Chromium has offered install this page session. */
  var seenInstallable = false;

  function isStandalone() {
    try {
      if (window.matchMedia) {
        if (window.matchMedia('(display-mode: standalone)').matches) return true;
        if (window.matchMedia('(display-mode: fullscreen)').matches) return true;
        if (window.matchMedia('(display-mode: minimal-ui)').matches) return true;
      }
    } catch (_) {}
    // iOS / iPadOS home-screen launch (Safari and WebKit shells)
    if (window.navigator && window.navigator.standalone === true) return true;
    return markedInstalled;
  }

  /** iPhone / iPad / iPod, including iPadOS desktop-UA mode. */
  function isAppleMobile() {
    var nav = window.navigator || {};
    var ua = nav.userAgent || '';
    if (/iPad|iPhone|iPod/.test(ua)) return true;
    if (nav.platform === 'MacIntel' && (nav.maxTouchPoints || 0) > 1) {
      return true;
    }
    return false;
  }

  function emit(name) {
    try {
      window.dispatchEvent(new CustomEvent(name));
    } catch (_) {}
  }

  window.addEventListener('beforeinstallprompt', function (event) {
    // Never available on iOS Safari — harmless if it never fires.
    event.preventDefault();
    deferredPrompt = event;
    seenInstallable = true;
    emit('sello-pwa-installable');
  });

  window.addEventListener('appinstalled', function () {
    deferredPrompt = null;
    seenInstallable = false;
    markedInstalled = true;
    emit('sello-pwa-installed');
  });

  window.selloPwa = {
    isStandalone: function () {
      return isStandalone();
    },
    /** True when the native prompt can be invoked right now. */
    canPrompt: function () {
      if (isAppleMobile() || isStandalone() || markedInstalled) return false;
      return deferredPrompt != null;
    },
    /**
     * True when the Install card should stay visible on Chromium —
     * including after the user cancels a prompt (event is one-shot until
     * the browser fires beforeinstallprompt again).
     */
    isInstallUiEligible: function () {
      if (isAppleMobile() || isStandalone() || markedInstalled) return false;
      return seenInstallable || deferredPrompt != null;
    },
    isAppleMobile: function () {
      return isAppleMobile() && !isStandalone();
    },
    isIosSafari: function () {
      return isAppleMobile() && !isStandalone();
    },
    promptInstall: function () {
      if (isAppleMobile() || isStandalone() || markedInstalled) {
        return Promise.resolve('unavailable');
      }
      if (!deferredPrompt) {
        return Promise.resolve('unavailable');
      }
      var promptEvent = deferredPrompt;
      deferredPrompt = null;
      return promptEvent.prompt().then(function () {
        return promptEvent.userChoice;
      }).then(function (choice) {
        if (choice && choice.outcome === 'accepted') {
          markedInstalled = true;
          seenInstallable = false;
          emit('sello-pwa-installed');
          return 'accepted';
        }
        // Dismissed: keep seenInstallable so the card remains; Chrome may
        // re-fire beforeinstallprompt and restore deferredPrompt.
        return 'dismissed';
      }).catch(function () {
        return 'unavailable';
      });
    },
  };
})();
