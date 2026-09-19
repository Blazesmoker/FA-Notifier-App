

String documentViewerCss({
  required bool usesReaderPresentation,
  required bool usesDarkReaderColors,
  required bool expandsToContent,
  required bool inspectionMode,
}) {
  final readerCss = usesReaderPresentation
      ? '''
body,pre,code{color:#e0e0e0!important;font-size:14px!important;line-height:1.4!important}
pre{margin:0!important;padding:12px!important;white-space:pre-wrap!important;overflow-wrap:anywhere!important}
#openPostReader{padding:0 12px;color:#e0e0e0;font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif;font-size:14px;line-height:1.4}
.openPostReaderPage+.openPostReaderPage{margin-top:14px}
.openPostReaderLine{min-height:19.6px;white-space:pre-wrap;overflow-wrap:anywhere}
html.openPostFullTextReader,
html.openPostFullTextReader body{height:auto!important;min-height:0!important;overflow:hidden!important}
html.openPostFullTextReader #outerContainer,
html.openPostFullTextReader #mainContainer,
html.openPostFullTextReader #viewerContainer{position:relative!important;inset:auto!important;width:100%!important;height:auto!important;min-height:0!important;overflow:visible!important}
'''
      : '';
  final darkReaderCss = usesDarkReaderColors
      ? '''
.pdfViewer .page{background:#151515!important;border:0!important;box-shadow:none!important}
.pdfViewer .page canvas,
.pdfViewer .page svg{filter:invert(1)!important;mix-blend-mode:screen!important;opacity:.868!important}
'''
      : '';
  final expandedCss = expandsToContent
      ? '''
html,body{height:auto!important;min-height:0!important;overflow:hidden!important}
#outerContainer,
#mainContainer,
#viewerContainer{position:relative!important;inset:auto!important;width:100%!important;height:auto!important;min-height:0!important;overflow:visible!important}
#viewerContainer{overflow:hidden!important}
#viewer{min-height:0!important;padding:0!important}
.pdfViewer{padding-bottom:0!important}
'''
      : '';
  final inspectionCss = inspectionMode
      ? '''
html,body,#outerContainer,#mainContainer,#viewerContainer{height:100%!important}
#viewer.openPostInspectionSinglePage{display:flex!important;flex-direction:column!important;min-height:100%!important}
#viewer.openPostInspectionSinglePage .page{flex:none!important;margin-block:auto!important;margin-inline:auto!important}
'''
      : '';
  return '''
html,body{margin:0!important;padding:0!important;background:#151515!important;color:#e0e0e0!important}
:root{--toolbar-height:0px!important}
#toolbarContainer,
#secondaryToolbar,
#sidebarContainer,
#loadingBar,
#viewFind{display:none!important}
#outerContainer,
#mainContainer,
#viewerContainer{background:#151515!important}
#viewerContainer{top:0!important;inset-block-start:0!important}
#outerContainer.sidebarOpen #viewerContainer{inset-inline-start:0!important}
#mainContainer{min-width:0!important}
$readerCss
$darkReaderCss
$expandedCss
$inspectionCss
''';
}
