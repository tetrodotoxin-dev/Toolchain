import os

ROOT_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BINARYEN_ROOT = ROOT_DIR
LLVM_ROOT = os.path.join(ROOT_DIR, "bin")
NODE_JS = "node"
FROZEN_CACHE = True
