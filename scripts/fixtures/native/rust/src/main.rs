fn square(value: i32) -> i32 {
    value * value // BREAKPOINT
}

fn main() {
    let result = square(3); // DEFINITION
    println!("square={result}");
}

#[cfg(test)]
mod tests {
    use super::square;

    #[test]
    fn square_matches_expected() {
        let expected = if std::env::var("NVIM_NATIVE_FAIL").as_deref() == Ok("1") {
            8
        } else {
            9
        };
        assert_eq!(square(3), expected);
    }
}
