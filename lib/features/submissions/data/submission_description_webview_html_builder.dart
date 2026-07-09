String buildSubmissionDescriptionWebViewHtml({
  required String submissionDescriptionHtml,
  required String faThemeCss,
  required bool enableTextSelection,
}) {
  String textColor = '#FFFFFF';

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
        color: $textColor !important;
        font-family: 'Open Sans', sans-serif;
      }

      $selectionCss

      body {
        margin: 8px;
      }

      .submission-description,
      .bbcode,
      .user-submitted-links {
        background-color: transparent !important;
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
        margin-bottom: 10px;
      }

      .bbcode_center {
        text-align: center !important;
      }

      .bbcode_right {
        text-align: right !important;
        display: block;
      }

      .bbcode_left {
        text-align: left !important;
        display: block;
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

      a.auto_link.named_url:hover {
        text-decoration: underline;
      }
    </style>

    <script src="https://www.furaffinity.net/themes/beta/js/prototype.1.7.3.min.js"></script>
    <script src="https://www.furaffinity.net/themes/beta/js/common.js?u=2024112800"></script>
    <script src="https://www.furaffinity.net/themes/beta/js/script.js?u=2024112800"></script>
  </head>
  <body class="c-bodyColor" id="pageid-submission">
    $submissionDescriptionHtml
  </body>
</html>
''';
}
