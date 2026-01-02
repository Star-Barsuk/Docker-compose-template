#!/bin/bash
source "$(dirname "$0")/lib.sh"

app::run()   { log::info "Running application (stub)"; }
app::test()  { log::info "Running tests (stub)"; }
app::lint()  { log::info "Linting code (stub)"; }
app::shell() { log::info "Entering app shell (stub)"; }

main() {
    local command="${1:-}"
    case "$command" in
        run)   app::run ;;
        test)  app::test ;;
        lint)  app::lint ;;
        shell) app::shell ;;
        *) echo "Usage: $0 {run|test|lint|shell}"; exit 1 ;;
    esac
}

[[ "${BASH_SOURCE[0]}" == "${0}" ]] && main "$@"
