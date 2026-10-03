{{flutter_js}}
{{flutter_build_config}}

// Serve CanvasKit from this app rather than Google's CDN, so the web build
// works offline and makes no third-party requests.
_flutter.loader.load({
  config: {
    canvasKitBaseUrl: "canvaskit/",
  },
});
