#!/bin/zsh
# One entry point for every marketing asset. See README.md.
#
#   capture.sh build     build the capture app (Release + demo mode)
#   capture.sh stills    App Store frames, then the marketing copy over them
#   capture.sh docs      docs/images (light and dark) and the website images
#   capture.sh video     the App Store preview
#   capture.sh all       build, then all of the above
#   capture.sh restore   panic button: put the desktop back, quit the capture app
#
# Every step takes over the screen. Turn on a Focus mode first.
set -e
source "${0:A:h}/common.sh"

build () {
  # The Release configuration, so the app is the one that ships: no Debug
  # marker bar on the glyph, Launch at Login present. CAPTURE compiles in the
  # demo mode, and its own bundle ID keeps it apart from the installed
  # CalPeek (its own preferences container and Calendar grant). Neither
  # override is in project.yml, so no archive can pick them up.
  echo "== building the capture app =="
  (cd $REPO && xcodegen generate >/dev/null)
  xcodebuild -project $REPO/CalPeek.xcodeproj -scheme CalPeek -configuration Release \
    -derivedDataPath $WORK/build \
    SWIFT_ACTIVE_COMPILATION_CONDITIONS='APPSTORE CAPTURE' \
    PRODUCT_BUNDLE_IDENTIFIER=$APP_ID \
    build 2>&1 | grep -E 'error:|BUILD (SUCCEEDED|FAILED)'
  [[ -d $APP ]] || { echo "ABORT: build produced no app"; exit 1; }
}

stills () {
  $CAPTURE_DIR/shoot_appstore.sh
  $CAPTURE_DIR/caption_appstore.sh
}

docs () {
  local mode
  for mode in light dark; do
    $CAPTURE_DIR/shoot_docs.sh $mode
    $CAPTURE_DIR/shoot_settings.sh $mode
  done
  cp docs_out/*-light.png docs_out/*-dark.png $REPO/docs/images/
  # The website uses the light set under its own names.
  mkdir -p $ASSETS/web
  cp docs_out/join-light.png       $ASSETS/web/01-hero-popover-transparent.png
  cp docs_out/day-light.png        $ASSETS/web/02-day-agenda-transparent.png
  cp docs_out/create-light.png     $ASSETS/web/03-quick-add-transparent.png
  cp docs_out/appearance-light.png $ASSETS/web/04-appearance-transparent.png
  cp docs_out/chooser-light.png    $ASSETS/web/05-join-chooser-transparent.png
  echo "docs/images and AppStoreAssets/web updated"
}

video () {
  $CAPTURE_DIR/record_video.sh
  $CAPTURE_DIR/cut_video.sh
}

restore () {
  pkill -x backdrop 2>/dev/null || true
  input esc 2>/dev/null || true
  quit_app
  restore_wallpaper
  defaults write com.apple.finder CreateDesktop true && killall Finder
  osascript -e 'tell application "System Events" to set visible of every process whose background only is false to true' >/dev/null 2>&1 || true
  echo "desktop restored, capture app quit"
}

# Hands the menu bar back to the installed CalPeek, if there is one.
finish () {
  quit_app
  open -b com.briangibson.calpeek 2>/dev/null || true
}

case ${1:-} in
  build)   build ;;
  stills)  stills; finish ;;
  docs)    docs; finish ;;
  video)   video; finish ;;
  all)     build; stills; docs; video; finish ;;
  restore) restore; finish ;;
  *) sed -n '2,11p' $CAPTURE_DIR/capture.sh | sed 's/^# \{0,1\}//'; exit 2 ;;
esac
