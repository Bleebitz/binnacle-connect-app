#!/usr/bin/env bash
# Regression test for connect_audit.py. Fixture A must BLOCK, fixture B must PASS.
set -u
fail=0
python3 connect_audit.py fixtures/broken/lib >/dev/null 2>&1
[ $? -eq 1 ] || { echo "FAIL: broken fixture should have blocked"; fail=1; }
python3 connect_audit.py fixtures/fixed/lib >/dev/null 2>&1
[ $? -eq 0 ] || { echo "FAIL: fixed fixture should have passed"; fail=1; }
[ $fail -eq 0 ] && echo "connect_audit self-test OK (broken blocks, fixed passes)"
exit $fail
