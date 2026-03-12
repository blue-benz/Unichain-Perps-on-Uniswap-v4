SHELL := /bin/bash

ifneq (,$(wildcard .env))
include .env
export
endif

.PHONY: bootstrap build test fuzz integration coverage lint demo-local demo-unichain demo-hedge deploy-unichain verify-commits

bootstrap:
	./scripts/bootstrap.sh

build:
	forge build

test:
	forge test -vv

fuzz:
	forge test --match-path "test/fuzz/*" -vv

integration:
	forge test --match-path "test/integration/*" -vv

coverage:
	./scripts/verify_coverage.sh

lint:
	forge fmt --check

demo-local:
	./scripts/demo_local.sh

demo-unichain:
	./scripts/demo_unichain.sh

demo-hedge:
	forge test --match-test "test_swapUpdatesMarkPriceViaHookAndSupportsLongShortLifecycle" -vv

deploy-unichain:
	./scripts/deploy_unichain.sh

verify-commits:
	./scripts/verify_commits.sh 67
