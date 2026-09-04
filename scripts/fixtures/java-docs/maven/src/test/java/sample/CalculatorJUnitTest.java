package sample;

import org.junit.jupiter.api.Test;
import static org.junit.jupiter.api.Assertions.assertEquals;

public class CalculatorJUnitTest {
    @Test
    public void passes() {
        assertEquals(5, Calculator.add(2, 3));
    }

    @Test
    public void fails() {
        assertEquals(6, Calculator.add(2, 3));
    }
}
