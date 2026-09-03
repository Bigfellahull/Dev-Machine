SHELL := /bin/bash

.PHONY: test lint verify

test:
	./tests/test-lifecycle.sh
	./tests/test-db.sh
	./tests/test-local-dev-tls.sh
	./tests/test-verify.sh
	PYTHONDONTWRITEBYTECODE=1 python3 -m unittest config/ai/skills/collab/tests/test_partner_turn.py
	./tests/test-static.sh

lint:
	./tests/test-static.sh

verify:
	./bootstrap/verify.sh
