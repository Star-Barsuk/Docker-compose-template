#!/bin/bash
source "$(dirname "$0")/lib.sh"

secrets::check()    { log::info "Checking secrets (stub)"; }
secrets::list()     { log::info "Listing secrets (stub)"; }
secrets::generate() { log::info "Generating secrets (stub)"; }

main() {
    case "${1:-}" in
        check|list|generate) secrets::$1 ;;
        *) echo "Usage: $0 {check|list|generate}"; exit 1 ;;
    esac
}

[[ "${BASH_SOURCE[0]}" == "${0}" ]] && main "$@"
