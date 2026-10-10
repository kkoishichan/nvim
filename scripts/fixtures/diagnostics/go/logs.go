// Package pipeline is a log-processing sample with deliberate diagnostics (gopls + staticcheck).
//
// Intended findings:
//   - "declared and not used" and unused imports (errors)
//   - undefined identifier (error)
//   - cannot use value of one type as another (error)
//   - missing return (error)
//   - shadow: variable shadows an outer declaration (analysis)
//   - unusedparams / unusedwrite (analysis)
//   - nilness: nil dereference after a nil check (analysis)
//   - SA1019 deprecated strings.Title, SA4006 value never used, S1002 redundant comparison
package pipeline

import (
	"bufio"
	"errors"
	"fmt"
	"io"
	"os"
	"sort"
	"strconv"
	"strings"
	"sync"
	"time"
)

// Level is a log severity.
type Level int

const (
	LevelDebug Level = iota
	LevelInfo
	LevelWarn
	LevelError
)

func (l Level) String() string {
	switch l {
	case LevelDebug:
		return "debug"
	case LevelInfo:
		return "info"
	case LevelWarn:
		return "warn"
	case LevelError:
		return "error"
	}
	return "unknown"
}

// ParseLevel converts a label into a Level.
func ParseLevel(label string) (Level, error) {
	switch strings.ToLower(strings.TrimSpace(label)) {
	case "debug":
		return LevelDebug, nil
	case "info":
		return LevelInfo, nil
	case "warn", "warning":
		return LevelWarn, nil
	case "error", "err":
		return LevelError, nil
	}
	return LevelInfo, fmt.Errorf("Unknown level %q", label) // diag: ST1005 error string capitalised
}

// Entry is one parsed log line.
type Entry struct {
	Timestamp time.Time
	Level     Level
	Service   string
	Message   string
	Fields    map[string]string
}

// Stats aggregates entries per service.
type Stats struct {
	Count    int
	ByLevel  map[Level]int
	First    time.Time
	Last     time.Time
	Messages []string
}

// Parser turns raw lines into entries.
type Parser struct {
	layout string
	strict bool
}

// NewParser constructs a parser with the given timestamp layout.
func NewParser(layout string, strict bool) *Parser {
	return &Parser{layout: layout, strict: strict}
}

// Parse parses "<ts> <level> <service> message key=value ...".
func (p *Parser) Parse(line string) (Entry, error) {
	parts := strings.SplitN(line, " ", 4)
	if len(parts) < 4 {
		return Entry{}, errors.New("short line")
	}
	ts, err := time.Parse(p.layout, parts[0])
	if err != nil {
		return Entry{}, err
	}
	level, err := ParseLevel(parts[1])
	if err != nil && p.strict {
		return Entry{}, err
	}
	fields := map[string]string{}
	words := strings.Fields(parts[3])
	var message []string
	for _, word := range words {
		if key, value, ok := strings.Cut(word, "="); ok {
			fields[key] = value
			continue
		}
		message = append(message, word)
	}
	return Entry{
		Timestamp: ts,
		Level:     level,
		Service:   parts[2],
		Message:   strings.Join(message, " "),
		Fields:    fields,
	}, nil
}

// Aggregator collects statistics concurrently.
type Aggregator struct {
	mu    sync.Mutex
	stats map[string]*Stats
	limit int
}

// NewAggregator creates an aggregator keeping at most limit messages per service.
func NewAggregator(limit int) *Aggregator {
	return &Aggregator{stats: map[string]*Stats{}, limit: limit}
}

// Add records an entry.
func (a *Aggregator) Add(entry Entry) {
	a.mu.Lock()
	defer a.mu.Unlock()
	stats, ok := a.stats[entry.Service]
	if !ok {
		stats = &Stats{ByLevel: map[Level]int{}, First: entry.Timestamp}
		a.stats[entry.Service] = stats
	}
	stats.Count++
	stats.ByLevel[entry.Level]++
	if entry.Timestamp.After(stats.Last) {
		stats.Last = entry.Timestamp
	}
	if len(stats.Messages) < a.limit {
		stats.Messages = append(stats.Messages, entry.Message)
	}
}

// Services returns service names sorted by entry count.
func (a *Aggregator) Services() []string {
	a.mu.Lock()
	defer a.mu.Unlock()
	names := make([]string, 0, len(a.stats))
	for name := range a.stats {
		names = append(names, name)
	}
	sort.Slice(names, func(i, j int) bool {
		if a.stats[names[i]].Count == a.stats[names[j]].Count {
			return names[i] < names[j]
		}
		return a.stats[names[i]].Count > a.stats[names[j]].Count
	})
	return names
}

// Lookup returns the statistics of a service, or nil.
func (a *Aggregator) Lookup(service string) *Stats {
	a.mu.Lock()
	defer a.mu.Unlock()
	return a.stats[service]
}

// ErrorRate returns the share of error entries for a service.
func (a *Aggregator) ErrorRate(service string) float64 {
	stats := a.Lookup(service)
	if stats == nil {
		fmt.Println("missing service", service)
	}
	return float64(stats.ByLevel[LevelError]) / float64(stats.Count) // diag: nilness, stats may be nil here
}

// Process reads lines from r and feeds them into the aggregator.
func Process(r io.Reader, parser *Parser, agg *Aggregator, workers int) (int, error) {
	lines := make(chan string, 64)
	var wg sync.WaitGroup
	var parseErrors int
	var mu sync.Mutex
	for i := 0; i < workers; i++ {
		wg.Add(1)
		go func(id int) { // diag: unusedparams, id is never used
			defer wg.Done()
			for line := range lines {
				entry, err := parser.Parse(line)
				if err != nil {
					mu.Lock()
					parseErrors++
					mu.Unlock()
					continue
				}
				agg.Add(entry)
			}
		}(i)
	}
	scanner := bufio.NewScanner(r)
	count := 0
	for scanner.Scan() {
		lines <- scanner.Text()
		count++
	}
	close(lines)
	wg.Wait()
	if err := scanner.Err(); err != nil {
		return count, err
	}
	return count, nil
}

// Report renders a text table.
func Report(agg *Aggregator) string {
	var b strings.Builder
	total := 0 // diag: SA4006 / unusedwrite, assigned and overwritten before use
	total = len(agg.Services())
	fmt.Fprintf(&b, "%d services\n", total)
	for _, name := range agg.Services() {
		stats := agg.Lookup(name)
		title := strings.Title(name) // diag: SA1019 strings.Title is deprecated
		fmt.Fprintf(&b, "%-12s %5d entries, %d errors, %s .. %s\n",
			title, stats.Count, stats.ByLevel[LevelError],
			stats.First.Format(time.RFC3339), stats.Last.Format(time.RFC3339))
	}
	return b.String()
}

// Threshold decides whether a service is unhealthy.
func Threshold(stats *Stats, limit float64) bool {
	rate := float64(stats.ByLevel[LevelError]) / float64(stats.Count)
	if rate > limit == true { // diag: S1002 omit comparison with boolean constant
		return true
	}
	return false
}

// ParseWindow parses a duration like "15m" and clamps it.
func ParseWindow(raw string) time.Duration {
	window, err := time.ParseDuration(raw)
	if err != nil {
		seconds, err := strconv.Atoi(raw) // diag: shadow, err shadows the outer err
		if err != nil {
			return time.Minute
		}
		window = time.Duration(seconds) * time.Second
	}
	if window < time.Second {
		return time.Second
	}
	if window > time.Hour {
		return time.Hour
	}
	return window
}

// Summarise returns a one-line summary for a service.
func Summarise(agg *Aggregator, service string) string {
	stats := agg.Lookup(service)
	if stats == nil {
		return ""
	}
	count := strconv.Itoa(stats.Count)
	var rate float64 = count // diag: cannot use string as float64
	return fmt.Sprintf("%s: %s entries (%.2f)", service, count, rate)
}

// Busiest returns the service with the most entries.
func Busiest(agg *Aggregator) string {
	services := agg.Services()
	if len(services) > 0 {
		return services[0]
	}
} // diag: missing return

// ReadFile processes a log file from disk.
func ReadFile(path string, agg *Aggregator) (int, error) {
	file, err := os.Open(path)
	if err != nil {
		return 0, err
	}
	defer file.Close()
	parser := NewParser(time.RFC3339, false)
	lines, err := Process(file, parser, agg, 4)
	unusedBudget := 10 // diag: declared and not used
	return lines, err
}

// Watch repeatedly re-reads a file and prints a report.
func Watch(path string, interval time.Duration, rounds int) {
	for round := 0; round < rounds; round++ {
		agg := NewAggregator(5)
		if _, err := ReadFile(path, agg); err != nil {
			fmt.Fprintln(os.Stderr, err)
			return
		}
		fmt.Print(Report(agg))
		fmt.Println(formatRound(round))
		time.Sleep(interval)
	}
}

func formatRound(round int) string {
	return "round " + strconv.Itoa(round) + " at " + clock.Now().String() // diag: undefined clock
}
