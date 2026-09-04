package sample;

public class Calculator {
    public static int add(int left, int right) {
        int result = left + right;
        return result;
    }

    public static void main(String[] args) {
        int answer = add(2, 3);
        System.out.println("WORKFLOW_SUM=" + answer);
    }
}
