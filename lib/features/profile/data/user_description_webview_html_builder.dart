String buildUserDescriptionWebViewHtml({
  required String userDescriptionHtml,
  required String faThemeCss,
  required bool enableTextSelection,
}) {
  final selectionCss = enableTextSelection
      ? '''
      html, body, body * {
        -webkit-touch-callout: default !important;
        -webkit-user-select: text !important;
        user-select: text !important;
      }
'''
      : '''
      html, body, body * {
        -webkit-touch-callout: none !important;
        -webkit-user-select: none !important;
        user-select: none !important;
      }
''';

  return '''
<html>
  <head>
    <meta name="viewport" content="width=device-width, initial-scale=1.0" />
    <base href="https://www.furaffinity.net/">
    <link rel="stylesheet" href="https://fonts.googleapis.com/css?family=Open+Sans:300,300i,400,400i,500,500i,600,600i,700,700i">
    <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/wenk/1.0.8/wenk.min.css">
    <style>
      $faThemeCss

      ::selection {
        background: rgba(224, 147, 33, 0.4) !important;
        color: #fff !important;
      }

      ::-webkit-selection {
        background: rgba(224, 147, 33, 0.4) !important;
        color: #fff !important;
      }

      html, body {
        margin: 0 !important;
        padding: 0 !important;
        background-color: #000 !important;
        color: #fff !important;
        font-family: 'Open Sans', sans-serif;
      }

      $selectionCss

      body {
        margin: 8px;
      }

      .container, .section-body, .userpage-layout-profile, .user-submitted-links {
        background-color: transparent !important;
      }

      #page-userpage .userpage-profile {
        border: none !important;
      }

      img {
        max-width: 100%;
        height: auto;
      }

      a.iconusername img {
        width: 60px;
        height: auto;
      }

      @media (max-width: 600px) {
        a.iconusername img {
          width: 40px;
        }
      }

      @media (min-width: 1200px) {
        a.iconusername img {
          width: 80px;
        }
      }

      code {
        display: block;
        margin: 10px 0;
      }

      .bbcode_center {
        text-align: center !important;
      }

      .bbcode_right {
        text-align: right !important;
      }

      .bbcode_left {
        text-align: left !important;
      }

      h1, h2, h3, h4 {
        color: #fff !important;
      }

      h1, h2, h3, h4, h5, h6 {
        text-align: center;
      }

      sup.bbcode_sup {
        display: block;
        text-align: inherit;
        margin-bottom: 10px;
      }

      a {
        color: #E09321 !important;
        text-decoration: none !important;
      }
    </style>
    <script>
      (() => {
        let playbackEnabled = true;

        const isGif = (image) => {
          const source = image.currentSrc || image.getAttribute('src') || '';
          if (!source) return false;
          try {
            return new URL(source, document.baseURI).pathname.toLowerCase().endsWith('.gif');
          } catch (_) {
            return false;
          }
        };

        const pauseImage = (image) => {
          if (image.dataset.faGifPaused === '1' || !isGif(image)) return;
          if (!image.complete || image.naturalWidth === 0 || image.naturalHeight === 0) {
            if (image.dataset.faGifPending !== '1') {
              image.dataset.faGifPending = '1';
              image.addEventListener('load', () => {
                delete image.dataset.faGifPending;
                if (!playbackEnabled) pauseImage(image);
              }, { once: true });
            }
            return;
          }

          const rect = image.getBoundingClientRect();
          const computed = window.getComputedStyle(image);
          const snapshot = document.createElement('canvas');
          snapshot.width = image.naturalWidth;
          snapshot.height = image.naturalHeight;
          snapshot.dataset.faGifSnapshot = '1';
          snapshot.style.width = Math.max(1, rect.width) + 'px';
          snapshot.style.height = Math.max(1, rect.height) + 'px';
          snapshot.style.display = computed.display;
          snapshot.style.verticalAlign = computed.verticalAlign;
          snapshot.style.objectFit = computed.objectFit;
          snapshot.style.maxWidth = computed.maxWidth;
          snapshot.style.maxHeight = computed.maxHeight;
          try {
            snapshot.getContext('2d').drawImage(
              image,
              0,
              0,
              snapshot.width,
              snapshot.height,
            );
          } catch (_) {}

          image.dataset.faGifSource = image.currentSrc || image.getAttribute('src') || '';
          image.dataset.faGifSrcset = image.getAttribute('srcset') || '';
          image.dataset.faGifDisplay = image.style.display;
          image.dataset.faGifPaused = '1';
          image.parentNode.insertBefore(snapshot, image);
          image.style.display = 'none';
          image.removeAttribute('srcset');
          image.removeAttribute('src');
        };

        const resumeImage = (image) => {
          if (image.dataset.faGifPaused !== '1') return;
          const snapshot = image.previousElementSibling;
          const source = image.dataset.faGifSource || '';
          const srcset = image.dataset.faGifSrcset || '';
          const display = image.dataset.faGifDisplay || '';
          const reveal = () => {
            image.style.display = display;
            if (snapshot && snapshot.dataset.faGifSnapshot === '1') {
              snapshot.remove();
            }
            delete image.dataset.faGifPaused;
            delete image.dataset.faGifSource;
            delete image.dataset.faGifSrcset;
            delete image.dataset.faGifDisplay;
            if (!playbackEnabled) pauseImage(image);
          };
          image.addEventListener('load', reveal, { once: true });
          image.addEventListener('error', reveal, { once: true });
          if (srcset) image.setAttribute('srcset', srcset);
          if (source) image.setAttribute('src', source);
        };

        window.__faProfileSetGifPlayback = (enabled) => {
          playbackEnabled = enabled === true;
          document.querySelectorAll('img').forEach((image) => {
            if (playbackEnabled) {
              resumeImage(image);
            } else {
              pauseImage(image);
            }
          });
        };

        document.addEventListener('load', (event) => {
          if (!playbackEnabled && event.target instanceof HTMLImageElement) {
            pauseImage(event.target);
          }
        }, true);
      })();
    </script>
    <script src="https://www.furaffinity.net/themes/beta/js/prototype.1.7.3.min.js"></script>
    <script src="https://www.furaffinity.net/themes/beta/js/common.js?u=2024112800"></script>
    <script src="https://www.furaffinity.net/themes/beta/js/script.js?u=2024112800"></script>
  </head>
  <body class="c-bodyColor" id="pageid-userpage">
    <div id="page-userpage">
      $userDescriptionHtml
    </div>
  </body>
</html>
''';
}
