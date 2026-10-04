#!/bin/bash
TARGET="${1:-all}"
case "$TARGET" in
    api)
        deploy_api
        ;;
    all)
        deploy_api
        ;;
    *)
        fail "unknown"
        ;;
esac
