.PHONY: test lint

test:
	./tests/bats/bats-core/bin/bats tests/

lint:
	shellcheck --severity=warning install uninstall bin/inc/* bin/init/* $(shell find bin -maxdepth 1 -type f)
