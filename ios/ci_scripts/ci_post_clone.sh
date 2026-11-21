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
project_url=${RUUUTO_RELEASE_SUPABASE_URL:-}
publishable_key=${RUUUTO_RELEASE_SUPABASE_PUBLISHABLE_KEY:-}
invitation_host=${RUUUTO_RELEASE_INVITATION_HOST:-}

validate_host() {
    case "$1" in
        *[!A-Za-z0-9.-]*|.*|*.|*..*|-*|*-|*.-*|*-.*|'' ) return 1 ;;
        *.*) return 0 ;;
        *) return 1 ;;
    esac
}

if [ -n "$project_url" ]; then
    case "$project_url" in
        https://*) url_host=${project_url#https://}; url_host=${url_host%/} ;;
        *) fail 'RUUUTO_RELEASE_SUPABASE_URL must be an HTTPS Project URL.' ;;
    esac
    [ -z "$host" ] || [ "$host" = "$url_host" ] ||
        fail 'The Supabase URL and host point to different projects.'
    host=$url_host
fi

if [ -n "$invitation_host" ]; then
    validate_host "$invitation_host" || fail 'RUUUTO_RELEASE_INVITATION_HOST must be a fully qualified hostname.'
fi

case "${RUUUTO_REQUIRE_SUPABASE_FOR_ARCHIVE:-0}" in
    0|1) ;;
    *) fail 'Set RUUUTO_REQUIRE_SUPABASE_FOR_ARCHIVE to 0 or 1.' ;;
esac

if [ -z "$host" ] && [ -z "$publishable_key" ]; then
    if [ "${CI_XCODEBUILD_ACTION:-}" = archive ] && [ "${RUUUTO_REQUIRE_SUPABASE_FOR_ARCHIVE:-0}" = 1 ]; then
        fail 'Set both RUUUTO_RELEASE_SUPABASE_HOST and RUUUTO_RELEASE_SUPABASE_PUBLISHABLE_KEY for the distribution archive.'
    fi
    [ -n "$invitation_host" ] || exit 0
else
    [ -n "$host" ] && [ -n "$publishable_key" ] ||
        fail 'Set the Supabase Project URL and publishable key together.'
    validate_host "$host" || fail 'The Supabase Project URL must contain only a fully qualified hostname.'

    case "$publishable_key" in
        sb_publishable_?*) ;;
        *) fail 'RUUUTO_RELEASE_SUPABASE_PUBLISHABLE_KEY must be a Supabase publishable key.' ;;
    esac
    case "${publishable_key#sb_publishable_}" in
        *[!A-Za-z0-9_-]*)
            fail 'RUUUTO_RELEASE_SUPABASE_PUBLISHABLE_KEY contains invalid characters.'
            ;;
    esac
fi

[ -n "${CI_PRIMARY_REPOSITORY_PATH:-}" ] || fail 'Xcode Cloud did not provide CI_PRIMARY_REPOSITORY_PATH.'
config_directory="$CI_PRIMARY_REPOSITORY_PATH/ios/Configuration"
[ -f "$config_directory/Release.xcconfig" ] || fail 'Could not locate ios/Configuration/Release.xcconfig.'

umask 077
temporary_config=$(mktemp "$config_directory/.ruuuto-release.XXXXXX")
trap 'rm -f "$temporary_config"' EXIT
{
    if [ -n "$host" ]; then
        printf 'RUUUTO_SUPABASE_HOST = %s\nRUUUTO_SUPABASE_PUBLISHABLE_KEY = %s\n' "$host" "$publishable_key"
    fi
    if [ -n "$invitation_host" ]; then
        printf 'RUUUTO_INVITATION_HOST = %s\n' "$invitation_host"
    fi
} > "$temporary_config"
mv -f "$temporary_config" "$config_directory/Cloud.Release.xcconfig"
