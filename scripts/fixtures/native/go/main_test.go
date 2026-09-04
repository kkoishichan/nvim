package main

import (
	"os"
	"testing"
)

func TestSquare(t *testing.T) {
	expected := 9
	if os.Getenv("NVIM_NATIVE_FAIL") == "1" {
		expected = 8
	}
	if actual := Square(3); actual != expected {
		t.Fatalf("Square(3) = %d, expected %d", actual, expected)
	}
}
