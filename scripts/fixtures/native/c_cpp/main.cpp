#include <iostream>
#include <cstdlib>

int doubled(int value) {
  return value * 2; // BREAKPOINT
}

int main(int argc, char **) {
  int result = doubled(3); // DEFINITION
  std::cout << "doubled=" << result << '\n';
  bool fail = argc > 1 || std::getenv("NVIM_NATIVE_FAIL") != nullptr;
  return result == (fail ? 5 : 6) ? 0 : 1;
}
