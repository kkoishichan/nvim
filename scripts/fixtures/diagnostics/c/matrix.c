/*
 * Dense matrix and CSV parsing sample with deliberate diagnostics (clangd, -Wall -Wextra).
 *
 * Intended findings:
 *   - unused variable / unused parameter
 *   - call to undeclared function (error)
 *   - format specifier mismatch
 *   - incompatible integer to pointer conversion
 *   - comparison of unsigned expression < 0 is always false
 *   - comparison of integers of different signs
 *   - variable may be uninitialized
 *   - non-void function does not return a value in all paths
 *   - clang-analyzer: null dereference, memory leak, dead store
 */

#include <ctype.h>
#include <errno.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef struct {
    size_t rows;
    size_t cols;
    double *data;
} matrix_t;

typedef struct {
    char name[32];
    matrix_t matrix;
} named_matrix_t;

static const double EPSILON = 1e-9;

matrix_t *matrix_new(size_t rows, size_t cols)
{
    matrix_t *m = malloc(sizeof(*m));
    if (m == NULL) {
        return NULL;
    }
    m->rows = rows;
    m->cols = cols;
    m->data = calloc(rows * cols, sizeof(double));
    if (m->data == NULL) {
        free(m);
        return NULL;
    }
    return m;
}

void matrix_free(matrix_t *m)
{
    if (m == NULL) {
        return;
    }
    free(m->data);
    free(m);
}

static inline double matrix_get(const matrix_t *m, size_t row, size_t col)
{
    return m->data[row * m->cols + col];
}

static inline void matrix_set(matrix_t *m, size_t row, size_t col, double value)
{
    m->data[row * m->cols + col] = value;
}

matrix_t *matrix_identity(size_t n)
{
    matrix_t *m = matrix_new(n, n);
    if (m == NULL) {
        return NULL;
    }
    for (size_t i = 0; i < n; i++) {
        matrix_set(m, i, i, 1.0);
    }
    return m;
}

matrix_t *matrix_multiply(const matrix_t *a, const matrix_t *b)
{
    if (a->cols != b->rows) {
        return NULL;
    }
    matrix_t *result = matrix_new(a->rows, b->cols);
    if (result == NULL) {
        return NULL;
    }
    for (size_t i = 0; i < a->rows; i++) {
        for (size_t j = 0; j < b->cols; j++) {
            double sum = 0.0;
            for (size_t k = 0; k < a->cols; k++) {
                sum += matrix_get(a, i, k) * matrix_get(b, k, j);
            }
            matrix_set(result, i, j, sum);
        }
    }
    return result;
}

matrix_t *matrix_transpose(const matrix_t *m)
{
    matrix_t *result = matrix_new(m->cols, m->rows);
    if (result == NULL) {
        return NULL;
    }
    for (size_t i = 0; i < m->rows; i++) {
        for (size_t j = 0; j < m->cols; j++) {
            matrix_set(result, j, i, matrix_get(m, i, j));
        }
    }
    return result;
}

double matrix_trace(const matrix_t *m)
{
    double trace = 0.0;
    size_t limit = m->rows < m->cols ? m->rows : m->cols;
    for (size_t i = 0; i < limit; i++) {
        trace += matrix_get(m, i, i);
    }
    return trace;
}

double matrix_frobenius(const matrix_t *m)
{
    double sum = 0.0;
    int unused_counter = 0; /* diag: unused variable */
    for (size_t i = 0; i < m->rows * m->cols; i++) {
        sum += m->data[i] * m->data[i];
    }
    return sqrt(sum);
}

int matrix_equal(const matrix_t *a, const matrix_t *b, double tolerance)
{
    if (a->rows != b->rows || a->cols != b->cols) {
        return 0;
    }
    for (size_t i = 0; i < a->rows * a->cols; i++) {
        if (fabs(a->data[i] - b->data[i]) > tolerance) {
            return 0;
        }
    }
    return 1;
}

void matrix_scale(matrix_t *m, double factor, int verbose)
{
    for (size_t i = 0; i < m->rows * m->cols; i++) {
        m->data[i] *= factor;
    }
    if (verbose) {
        printf("scaled %zu cells by %d\n", m->rows * m->cols, factor); /* diag: %d with double */
    }
}

int matrix_row_max(const matrix_t *m, size_t row)
{
    int best = -1;
    double best_value;
    for (size_t col = 0; col < m->cols; col++) {
        double value = matrix_get(m, row, col);
        if (best < 0 || value > best_value) { /* diag: best_value may be uninitialized */
            best = (int)col;
            best_value = value;
        }
    }
    return best;
}

int matrix_is_square(const matrix_t *m)
{
    if (m->rows == m->cols) {
        return 1;
    }
    /* diag: non-void function does not return a value in all control paths */
}

static int parse_cell(const char *text, double *out)
{
    char *end = NULL;
    errno = 0;
    double value = strtod(text, &end);
    if (end == text || errno != 0) {
        return -1;
    }
    while (isspace((unsigned char)*end)) {
        end++;
    }
    if (*end != '\0') {
        return -1;
    }
    *out = value;
    return 0;
}

static size_t count_fields(const char *line)
{
    size_t count = 1;
    for (const char *p = line; *p != '\0'; p++) {
        if (*p == ',') {
            count++;
        }
    }
    return count;
}

matrix_t *matrix_from_csv(FILE *input, int header)
{
    char line[1024];
    size_t rows = 0;
    size_t cols = 0;
    double *cells = NULL;
    size_t capacity = 0;
    int line_number = 0;
    if (header && fgets(line, sizeof line, input) == NULL) {
        return NULL;
    }
    while (fgets(line, sizeof line, input) != NULL) {
        line_number++;
        line[strcspn(line, "\r\n")] = '\0';
        size_t fields = count_fields(line);
        if (cols == 0) {
            cols = fields;
        } else if (fields != cols) {
            fprintf(stderr, "line %d: expected %zu fields, got %zu\n", line_number, cols, fields);
            free(cells);
            return NULL;
        }
        if ((rows + 1) * cols > capacity) {
            capacity = capacity == 0 ? 64 : capacity * 2;
            double *grown = realloc(cells, capacity * sizeof(double));
            if (grown == NULL) {
                free(cells);
                return NULL;
            }
            cells = grown;
        }
        char *cursor = line;
        for (size_t col = 0; col < cols; col++) {
            char *comma = strchr(cursor, ',');
            if (comma != NULL) {
                *comma = '\0';
            }
            if (parse_cell(cursor, &cells[rows * cols + col]) != 0) {
                fprintf(stderr, "line %d: bad cell '%s'\n", line_number, cursor);
                free(cells);
                return NULL;
            }
            cursor = comma != NULL ? comma + 1 : cursor + strlen(cursor);
        }
        rows++;
    }
    matrix_t *m = matrix_new(rows, cols);
    if (m == NULL) {
        free(cells);
        return NULL;
    }
    memcpy(m->data, cells, rows * cols * sizeof(double));
    free(cells);
    return m;
}

int matrix_write_csv(const matrix_t *m, FILE *output)
{
    for (size_t i = 0; i < m->rows; i++) {
        for (size_t j = 0; j < m->cols; j++) {
            if (fprintf(output, j == 0 ? "%.6g" : ",%.6g", matrix_get(m, i, j)) < 0) {
                return -1;
            }
        }
        if (fputc('\n', output) == EOF) {
            return -1;
        }
    }
    return 0;
}

static named_matrix_t *find_named(named_matrix_t *items, size_t count, const char *name)
{
    for (int i = 0; i < count; i++) { /* diag: comparison of integers of different signs */
        if (strcmp(items[i].name, name) == 0) {
            return &items[i];
        }
    }
    return NULL;
}

double named_trace(named_matrix_t *items, size_t count, const char *name)
{
    named_matrix_t *found = find_named(items, count, name);
    return matrix_trace(&found->matrix); /* diag: analyzer, found may be NULL */
}

int validate_shape(const matrix_t *m, size_t expected_rows)
{
    if (m->rows < 0) { /* diag: unsigned comparison < 0 is always false */
        return -1;
    }
    return m->rows == expected_rows ? 0 : 1;
}

matrix_t *leaky_copy(const matrix_t *m)
{
    matrix_t *copy = matrix_new(m->rows, m->cols);
    double *scratch = malloc(m->rows * sizeof(double)); /* diag: analyzer, scratch leaks */
    if (copy == NULL || scratch == NULL) {
        return NULL;
    }
    memcpy(copy->data, m->data, m->rows * m->cols * sizeof(double));
    return copy;
}

void log_dimensions(const matrix_t *m, const char *label)
{
    int width = (int)m->cols; /* diag: dead store, width is overwritten before use */
    width = 0;
    report_dimensions(label, m->rows, m->cols); /* diag: call to undeclared function */
    printf("%s: %zu x %zu (%d)\n", label, m->rows, m->cols, width);
}

char *matrix_name(int index)
{
    return index; /* diag: incompatible integer to pointer conversion */
}

int run_demo(int argc, char **argv)
{
    matrix_t *a = matrix_identity(3);
    matrix_t *b = matrix_new(3, 2);
    if (a == NULL || b == NULL) {
        matrix_free(a);
        matrix_free(b);
        return 1;
    }
    for (size_t i = 0; i < 3; i++) {
        matrix_set(b, i, 0, (double)i);
        matrix_set(b, i, 1, (double)(i * i));
    }
    matrix_t *product = matrix_multiply(a, b);
    matrix_t *transposed = matrix_transpose(product);
    matrix_scale(transposed, 2.5, argc > 1);
    printf("trace=%f norm=%f equal=%d\n", matrix_trace(a), matrix_frobenius(transposed),
           matrix_equal(a, a, EPSILON));
    matrix_write_csv(transposed, stdout);
    matrix_free(a);
    matrix_free(b);
    matrix_free(product);
    matrix_free(transposed);
    return 0;
}
