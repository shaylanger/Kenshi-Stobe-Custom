#!/usr/bin/env python3
"""build.sh adapter: run pending-fixes/kfp-rb-single.py (takes the KenshiFP ROOT) on a client dir copy."""
import sys, os, subprocess
subprocess.run([sys.executable, '/mnt/c/KenshiModding/pending-fixes/kfp-rb-single.py', os.path.dirname(os.path.abspath(sys.argv[1]))], check=True)
