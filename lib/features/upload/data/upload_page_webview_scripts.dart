String buildUploadInitialPageScript({required bool isIOS}) {
  return isIOS
      ? _buildUploadInitialIosScript()
      : _buildUploadInitialDefaultScript();
}

String buildUploadFinalizePageScript({required bool isIOS}) {
  return isIOS
      ? _buildUploadFinalizeIosScript()
      : _buildUploadFinalizeDefaultScript();
}

String buildClearFinalizeFormScript() {
  return '''
        (function() {
          function __b64(o) { return 'B64:' + btoa(unescape(encodeURIComponent(JSON.stringify(o)))); }

          function __escapeHTML(text) {
            var htmlEscapes = {
              '&': '&amp;',
              '<': '&lt;',
              '>': '&gt;',
              '"': '&quot;',
              "'": '&#x27;',
              '/': '&#x2F;'
            };
            return String(text).replace(/[&<>"'\\/]/g, function(match) { return htmlEscapes[match]; });
          }

          function __setHidden(el, hidden) {
            if (!el) return;
            try {
              if (hidden) el.classList.add('hidden');
              else el.classList.remove('hidden');
            } catch (_) {}
          }

          function __updateTitlePreview(value) {
            var defaultTitle = document.querySelector('.default-preview-title');
            var userTitle = document.querySelector('.user-preview-title');
            if (!defaultTitle || !userTitle) return;
            var v = String(value || '');
            if (v !== '') {
              __setHidden(defaultTitle, true);
              userTitle.textContent = v.replace(/\\n/g, ' ');
              __setHidden(userTitle, false);
            } else {
              __setHidden(defaultTitle, false);
              __setHidden(userTitle, true);
            }
          }

          function __updateDescPreview(value) {
            var defaultDesc = document.querySelector('.default-preview-text');
            var userDesc = document.querySelector('.user-preview-text');
            if (!defaultDesc || !userDesc) return;
            var v = String(value || '');
            if (v !== '') {
              __setHidden(defaultDesc, true);
              userDesc.innerHTML = __escapeHTML(v).replace(/\\n/g, '<br />');
              __setHidden(userDesc, false);
            } else {
              __setHidden(defaultDesc, false);
              __setHidden(userDesc, true);
              userDesc.innerHTML = '';
            }
          }

          function __syncPreviewToForm() {
            var titleEl = document.querySelector('input#title') || document.querySelector('input[name="title"]');
            var msgEl = document.querySelector('textarea#message');
            var titleVal = titleEl ? String(titleEl.value || '') : '';
            var msgVal = msgEl ? String(msgEl.value || '') : '';
            __updateTitlePreview(titleVal);
            __updateDescPreview(msgVal);
            return true;
          }

          try {
            var form = document.getElementById('myform');
            if (!form) return __b64({ ok: false, error: 'Finalize form not found' });
            form.reset();
            __syncPreviewToForm();
            return __b64({ ok: true });
          } catch (e) {
            return __b64({ ok: false, error: String(e) });
          }
        })();
      ''';
}

String _buildUploadInitialIosScript() {
  return '''
        (function() {
          var style = document.createElement('style');
          style.type = 'text/css';
          style.innerHTML = \`
            .mobile-navigation,
            #header,
            #footer,
            .leaderboardAd,
            .news-block,
            .mobile-notification-bar,
            nav#ddmenu,
            .online-stats,
            .footnote,
            .footerAds,
            .floatleft,
            .submenu-trigger,
            .banner-svg,
            .leaderboardAd,
            .newsBlock,
            .footerAds__column,
            .message-bar-desktop,
            .notification-container,
            .dropdown,
            .some-other-class {
              display: none !important;
            }

            .content {
              margin: 0 !important;
              padding: 0 !important;
            }
            
            .section-options,
            .captcha-container,
            #fa-captcha-main,
            .cf-turnstile {
              display: block !important;
              visibility: visible !important;
            }
          \`;
          document.head.appendChild(style);
          
          function ensureTurnstile() {
            setTimeout(function() {
              if (window.turnstile && !document.querySelector('iframe[src*="challenges.cloudflare.com"]')) {
                console.log('Forcing Turnstile re-render on iOS');
                var turnstileElements = document.querySelectorAll('.cf-turnstile');
                turnstileElements.forEach(function(el) {
                  el.innerHTML = '';
                  try {
                    window.turnstile.render(el);
                  } catch(e) {
                    console.log('Turnstile re-render failed:', e);
                  }
                });
              }
            }, 1000);
          }
          
          if (document.readyState === 'loading') {
            document.addEventListener('DOMContentLoaded', ensureTurnstile);
          } else {
            ensureTurnstile();
          }
        })();
      ''';
}

String _buildUploadInitialDefaultScript() {
  return '''
        (function() {
          var style = document.createElement('style');
          style.type = 'text/css';
          style.innerHTML = \`
            .mobile-navigation,
            #header,
            #footer,
            .leaderboardAd,
            .news-block,
            .mobile-notification-bar,
            nav#ddmenu,
            .online-stats,
            .footnote,
            .footerAds,
            .floatleft,
            .submenu-trigger,
            .banner-svg,
            .leaderboardAd,
            .newsBlock,
            .footerAds__column,
            .message-bar-desktop,
            .notification-container,
            .dropdown,
            .dropzone,
            .some-other-class {
              display: none !important;
            }

            .content {
              margin: 0 !important;
              padding: 0 !important;
            }
          \`;
          document.head.appendChild(style);
        })();
      ''';
}

String _buildUploadFinalizeIosScript() {
  return '''
        (function() {
          var style = document.createElement('style');
          style.type = 'text/css';
          style.innerHTML = \`
            .mobile-navigation,
            #header,
            #footer,
            .leaderboardAd,
            .news-block,
            .mobile-notification-bar,
            nav#ddmenu,
            .online-stats,
            .footnote,
            .footerAds,
            .floatleft,
            .submenu-trigger,
            .banner-svg,
            .newsBlock,
            .footerAds__column,
            .message-bar-desktop,
            .notification-container,
            .dropdown {
              display: none !important;
            }

            .content {
              margin: 0 !important;
              padding: 0 !important;
            }
            
            .section-options,
            .captcha-container,
            #fa-captcha-main,
            .cf-turnstile {
              display: block !important;
              visibility: visible !important;
            }
          \`;
          document.head.appendChild(style);
          
          function ensureTurnstile() {
            setTimeout(function() {
              if (window.turnstile && !document.querySelector('iframe[src*="challenges.cloudflare.com"]')) {
                console.log('Forcing Turnstile re-render on iOS');
                var turnstileElements = document.querySelectorAll('.cf-turnstile');
                turnstileElements.forEach(function(el) {
                  el.innerHTML = '';
                  try {
                    window.turnstile.render(el);
                  } catch(e) {
                    console.log('Turnstile re-render failed:', e);
                  }
                });
              }
            }, 1000);
          }
          
          if (document.readyState === 'loading') {
            document.addEventListener('DOMContentLoaded', ensureTurnstile);
          } else {
            ensureTurnstile();
          }
        })();
      ''';
}

String _buildUploadFinalizeDefaultScript() {
  return '''
        (function() {
          var style = document.createElement('style');
          style.type = 'text/css';
          style.innerHTML = \`
            .mobile-navigation,
            #header,
            #footer,
            .leaderboardAd,
            .news-block,
            .mobile-notification-bar,
            nav#ddmenu,
            .online-stats,
            .footnote,
            .footerAds,
            .floatleft,
            .submenu-trigger,
            .banner-svg,
            .newsBlock,
            .footerAds__column,
            .message-bar-desktop,
            .notification-container,
            .dropdown,
            .dropzone {
              display: none !important;
            }

            .content {
              margin: 0 !important;
              padding: 0 !important;
            }
          \`;
          document.head.appendChild(style);
        })();
      ''';
}
