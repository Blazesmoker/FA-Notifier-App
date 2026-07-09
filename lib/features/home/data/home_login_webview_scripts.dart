const String homeLoginInitialHtml =
    '<!doctype html><html><head><meta name="viewport" content="width=device-width,initial-scale=1"></head><body style="margin:0;background:#000;"></body></html>';

const String homeLoginOuterHtmlScript = 'document.documentElement.outerHTML;';

const String homeLoginCss = '''
      /* Minimal CSS to hide some FA elements on login page */
      .mobile-navigation,
      nav#ddmenu,
      .news-block,
      .leaderboardAd,
      .mobile-notification-bar,
      .footerAds,
      .floatleft,
      .submenu-trigger,
      .banner-svg,
      .message-bar-desktop,
      .notification-container,
      .dropdown,
      #main-window > nav,
      #main-window > .message-bar-desktop,
      #main-window > .news-block,
      #footer .auto_link.footer-links,
      #footer .footerAds__slot,
      #footer .footerAds__column {
        display: none !important;
      }

      /* Center username, password, and login button */
      section.login-page .section-body {
        text-align: center !important;
      }

      section.login-page .section-body input[type="text"],
      section.login-page .section-body input[type="password"],
      section.login-page .section-body input[type="submit"] {
        display: block !important;
        margin: 0 auto !important;
        margin-bottom: 10px !important;
        max-width: 300px;
      }
    ''';
