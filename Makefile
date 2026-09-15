SHELL := /bin/bash

.PHONY: test lint verify

test:
	./tests/test-lifecycle.sh
	./tests/test-db.sh
	./tests/test-local-dev-tls.sh
	./tests/test-verify.sh
	./tests/test-profiles.sh
	PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s tests -p 'test_*.py'
	PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s config/ai/skills/collab/tests
	./tests/test-static.sh

lint:
	./tests/test-static.sh

verify:
	./bootstrap/verify.sh
