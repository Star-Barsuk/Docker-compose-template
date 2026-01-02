#!/bin/bash
source "$(dirname "$0")/lib.sh"

docker::up()    { log::info "Starting containers (stub)"; }
docker::down()  { log::info "Stopping containers (stub)"; }
docker::build() { log::info "Building images (stub)"; }
docker::stop()  { log::info "Stopping containers (stub)"; }
docker::clean() { log::info "Cleaning stack (stub)"; }
docker::nuke()  { log::info "Nuking stack (stub)"; }
docker::logs()  { log::info "Showing logs (stub)"; }
docker::shell() { log::info "Entering Docker shell (stub)"; }

main() {
    case "${1:-}" in
        up|down|build|stop|clean|nuke|logs|shell) docker::$1 ;;
        *) echo "Usage: $0 {up|down|build|stop|clean|nuke|logs|shell}"; exit 1 ;;
    esac
}

[[ "${BASH_SOURCE[0]}" == "${0}" ]] && main "$@"
