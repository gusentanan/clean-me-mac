package main

import "testing"

func TestHumanSize(t *testing.T) {
	cases := []struct {
		bytes int64
		want  string
	}{
		{0, "0B"},
		{512, "512B"},
		{1024, "1.0K"},
		{1536, "1.5K"},
		{1024 * 1024, "1.0M"},
		{5 * 1024 * 1024 * 1024, "5.0G"},
	}
	for _, c := range cases {
		if got := humanSize(c.bytes); got != c.want {
			t.Errorf("humanSize(%d) = %q, want %q", c.bytes, got, c.want)
		}
	}
}

func TestBar(t *testing.T) {
	full := bar(100, 100, 10)
	if full != "██████████" {
		t.Errorf("bar(100,100,10) = %q, want all filled", full)
	}
	empty := bar(0, 100, 10)
	if empty != "░░░░░░░░░░" {
		t.Errorf("bar(0,100,10) = %q, want all empty", empty)
	}
	half := bar(50, 100, 10)
	if half != "█████░░░░░" {
		t.Errorf("bar(50,100,10) = %q, want half filled", half)
	}
	// total=0 must not divide by zero / panic.
	zeroTotal := bar(0, 0, 10)
	if zeroTotal != "░░░░░░░░░░" {
		t.Errorf("bar(0,0,10) = %q, want all empty (no div-by-zero)", zeroTotal)
	}
}

func TestPct(t *testing.T) {
	if got := pct(25, 100); got != 25 {
		t.Errorf("pct(25,100) = %v, want 25", got)
	}
	if got := pct(1, 0); got != 0 {
		t.Errorf("pct(1,0) = %v, want 0 (no div-by-zero)", got)
	}
}

func TestTruncate(t *testing.T) {
	if got := truncate("short", 10); got != "short" {
		t.Errorf("truncate short string changed it: %q", got)
	}
	if got := truncate("a very long label indeed", 10); got != "a very ..." {
		t.Errorf("truncate long string = %q", got)
	}
	if got := truncate("abc", 2); len([]rune(got)) != 2 {
		t.Errorf("truncate with max<=3 should hard-cut, got %q", got)
	}
}
