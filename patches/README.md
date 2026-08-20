# Anubis patches

Place unified-diff patches in this directory with a `.patch` extension. The
Docker build applies them with `patch -p1` in lexical filename order, so use
names such as `0001-example.patch` when ordering matters.
