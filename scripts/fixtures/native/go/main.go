package main

import "fmt"

func Square(value int) int {
	return value * value // BREAKPOINT
}

func main() {
	result := Square(3) // DEFINITION
	fmt.Printf("square=%d\n", result)
}
