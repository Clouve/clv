.PHONY: test lint

test:
	./tests/bats/bats-core/bin/bats tests/

lint:
	shellcheck install uninstall bin/* bin/init/* bin/inc/*
