#!/usr/bin/env bash
# Install the fixture app's Angular packages and the language servers used by the integration tests.
# Usage: test/scripts/install-lsp-deps.sh [angular-version]   (default: 20)
# Package install scripts are never run (--ignore-scripts).
set -euo pipefail

VERSION="${1:-20}"
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
APP="$REPO/test/fixtures/angular-test-app"
SERVERS="$REPO/test/.servers"
NPM_FLAGS=(--ignore-scripts --no-audit --no-fund --no-save --no-package-lock)

ts_minor="$(npm view "@angular/compiler-cli@$VERSION" peerDependencies.typescript --json | node -e '
  const ranges = [].concat(JSON.parse(require("fs").readFileSync(0, "utf8")));
  console.log(ranges[ranges.length - 1].match(/\d+\.\d+/)[0]);
')"

echo "Angular $VERSION, TypeScript ~$ts_minor"

rm -rf "$APP/node_modules"
(cd "$APP" && npm install "${NPM_FLAGS[@]}" \
  "@angular/core@$VERSION" "@angular/common@$VERSION" "@angular/compiler@$VERSION" \
  "@angular/forms@$VERSION" "@angular/animations@$VERSION" "@angular/router@$VERSION" \
  "@angular/platform-browser@$VERSION" "@angular/compiler-cli@$VERSION" \
  rxjs@7.8 tslib zone.js "typescript@~$ts_minor")

major="$(node -p "require('$APP/node_modules/@angular/core/package.json').version.split('.')[0]")"
rm -rf "$SERVERS"
mkdir -p "$SERVERS"
echo '{ "private": true }' > "$SERVERS/package.json"
(cd "$SERVERS" && npm install "${NPM_FLAGS[@]}" \
  "@angular/language-server@$major" "typescript@~$ts_minor" typescript-language-server)

node -p "'installed @angular/core ' + require('$APP/node_modules/@angular/core/package.json').version + ', @angular/language-server ' + require('$SERVERS/node_modules/@angular/language-server/package.json').version"
