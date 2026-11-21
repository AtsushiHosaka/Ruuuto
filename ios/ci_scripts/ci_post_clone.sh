#!/bin/sh
set +x
set -eu
export LC_ALL=C

[ "${CI_XCODE_CLOUD:-}" = TRUE ] || exit 0

fail() {
    printf '%s\n' "$1" >&2
    exit 1
}

host=${RUUUTO_RELEASE_SUPABASE_HOST:-}
publishable_key=${RUUUTO_RELEASE_SUPABASE_PUBLISHABLE_KEY:-}

case "${RUUUTO_REQUIRE_SUPABASE_FOR_ARCHIVE:-0}" in
    0|1) ;;
    *) fail 'Set RUUUTO_REQUIRE_SUPABASE_FOR_ARCHIVE to 0 or 1.' ;;
esac

if [ -z "$host" ] && [ -z "$publishable_key" ]; then
    if [ "${CI_XCODEBUILD_ACTION:-}" = archive ] && [ "${RUUUTO_REQUIRE_SUPABASE_FOR_ARCHIVE:-0}" = 1 ]; then
        fail 'Set both RUUUTO_RELEASE_SUPABASE_HOST and RUUUTO_RELEASE_SUPABASE_PUBLISHABLE_KEY for the distribution archive.'
    fi
    exit 0
fi

[ -n "$host" ] && [ -n "$publishable_key" ] ||
    fail 'Set both RUUUTO_RELEASE_SUPABASE_HOST and RUUUTO_RELEASE_SUPABASE_PUBLISHABLE_KEY together.'

case "$host" in
    *[!A-Za-z0-9.-]*|.*|*.|*..*|-*|*-|*.-*|*-.*)
        fail 'RUUUTO_RELEASE_SUPABASE_HOST must be a hostname without a URL scheme, port, or path.'
        ;;
    *.*) ;;
    *) fail 'RUUUTO_RELEASE_SUPABASE_HOST must be a fully qualified hostname.' ;;
esac

case "$publishable_key" in
    sb_publishable_?*) ;;
    *) fail 'RUUUTO_RELEASE_SUPABASE_PUBLISHABLE_KEY must be a Supabase publishable key.' ;;
esac
case "${publishable_key#sb_publishable_}" in
    *[!A-Za-z0-9_-]*)
        fail 'RUUUTO_RELEASE_SUPABASE_PUBLISHABLE_KEY contains invalid characters.'
        ;;
esac

[ -n "${CI_PRIMARY_REPOSITORY_PATH:-}" ] || fail 'Xcode Cloud did not provide CI_PRIMARY_REPOSITORY_PATH.'
config_directory="$CI_PRIMARY_REPOSITORY_PATH/ios/Configuration"
[ -f "$config_directory/Release.xcconfig" ] || fail 'Could not locate ios/Configuration/Release.xcconfig.'

umask 077
temporary_config=$(mktemp "$config_directory/.ruuuto-release.XXXXXX")
trap 'rm -f "$temporary_config"' EXIT
printf 'RUUUTO_SUPABASE_HOST = %s\nRUUUTO_SUPABASE_PUBLISHABLE_KEY = %s\n' "$host" "$publishable_key" > "$temporary_config"
mv -f "$temporary_config" "$config_directory/Cloud.Release.xcconfig"
