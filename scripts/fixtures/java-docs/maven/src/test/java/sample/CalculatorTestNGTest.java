package sample;

import org.testng.annotations.Test;
import static org.testng.Assert.assertEquals;

public class CalculatorTestNGTest {
    @Test
    public void passes() {
        assertEquals(Calculator.add(2, 3), 5);
    }

    @Test
    public void fails() {
        assertEquals(Calculator.add(2, 3), 6);
    }
}
