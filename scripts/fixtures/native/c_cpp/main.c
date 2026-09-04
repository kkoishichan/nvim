#include <stdio.h>
#include <stdlib.h>

int square(int value) {
  return value * value; // BREAKPOINT
}

int main(int argc, char **argv) {
  (void)argv;
  int result = square(3); // DEFINITION
  printf("square=%d\n", result);
  int fail = argc > 1 || getenv("NVIM_NATIVE_FAIL") != NULL;
  return result == (fail ? 8 : 9) ? 0 : 1;
}
