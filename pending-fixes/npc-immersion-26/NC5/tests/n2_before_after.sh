#!/bin/bash
cd /mnt/c/KenshiTestRuns/imm26-nc5
echo "== before (NC4a src.orig)"; g++ -std=c++11 -Wall -Isrc.orig tests/n2_logic_tests.cpp -o /tmp/n2b 2>&1 | grep -c error; 
echo "== after"; g++ -std=c++11 -Wall -Isrc tests/n2_logic_tests.cpp -o /tmp/n2a 2>&1 | head -20; /tmp/n2a | tail -15; echo "exit=${PIPESTATUS[0]}"
