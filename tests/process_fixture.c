// # Tetrodotoxin
// Copyright (c) 2023-present Matt Kaes and contributors

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#ifdef _WIN32
#include <fcntl.h>
#include <io.h>
#include <windows.h>
// Exercise case insensitive SDK library lookup when cross linking from Linux.
#pragma comment(lib, "LiBcMt")
#else
#include <unistd.h>
#endif
static int run(int argc, char** argv) {
#ifdef _WIN32
  _setmode(_fileno(stdin), _O_BINARY);
  _setmode(_fileno(stdout), _O_BINARY);
  _setmode(_fileno(stderr), _O_BINARY);
#endif
  if (argc < 2) {
    return 1;
  }
  if (!strcmp(argv[1], "timeout")) {
#ifdef _WIN32
    Sleep(2000);
#else
    sleep(2);
#endif
    return 0;
  }
  if (!strcmp(argv[1], "arguments")) {
    for (int i = 2; i < argc; ++i) {
      fwrite(argv[i], 1, strlen(argv[i]) + 1, stdout);
    }
    return 0;
  }
  unsigned char data[4096];
  size_t count;
  while ((count = fread(data, 1, sizeof(data), stdin))) {
    fwrite(data, 1, count, stdout);
    fwrite(data, 1, count, stderr);
  }
  return 7;
}

#ifdef _WIN32
int wmain(int argc, wchar_t** argv) {
  char** arguments = calloc((size_t)argc, sizeof(char*));
  if (!arguments) {
    return 1;
  }
  int status = 1;
  for (int i = 0; i < argc; ++i) {
    const int size =
        WideCharToMultiByte(CP_UTF8, 0, argv[i], -1, NULL, 0, NULL, NULL);
    if (!size || !(arguments[i] = malloc((size_t)size))) {
      goto cleanup;
    }
    if (!WideCharToMultiByte(
            CP_UTF8, 0, argv[i], -1, arguments[i], size, NULL, NULL)) {
      goto cleanup;
    }
  }
  status = run(argc, arguments);
cleanup:
  for (int i = 0; i < argc; ++i) {
    free(arguments[i]);
  }
  free(arguments);
  return status;
}
#else
int main(int argc, char** argv) {
  return run(argc, argv);
}
#endif
